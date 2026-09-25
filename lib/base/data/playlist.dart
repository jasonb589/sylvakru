import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/base/services/picture_service.dart';
import 'package:sylvakru/base/services/stream_client.dart';
import 'package:sylvakru/base/utils/path.dart';
import 'package:sylvakru/base/utils/advanced_song_search.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:sylvakru/layer/layers_manager.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';

final playlistManager = PlaylistManager();

class PlaylistManager {
  late File _playlistsFile;

  List<Playlist> playlists = [];
  Map<String, Playlist> playlistMap = {};
  ValueNotifier<int> updateNotifier = ValueNotifier(0);

  PlaylistManager() {
    addPlaylist(Playlist(name: 'Favorite'));
  }

  Future<void> _prepareForLoad() async {
    _playlistsFile = File(
      "${getPlaylistConfigPath(sourceType)}/sylvakru_playlists.json",
    );
    initFile(_playlistsFile, true);

    final contentList = await readJsonListFile(_playlistsFile);
    for (final content in contentList) {
      if (isNotStreamSource) {
        if (content is String && content.isNotEmpty) {
          if (!playlistMap.containsKey(content)) {
            addPlaylist(Playlist(name: content));
          }
          continue;
        }
        if (content is Map && content['type'] == 'smart') {
          final name = content['name'];
          final rawCriteria = content['criteria'];
          if (name is! String || name.isEmpty || rawCriteria is! Map) {
            continue;
          }
          final definition = SmartPlaylistDefinition.fromJson(
            Map<String, dynamic>.from(content),
          );
          if (!playlistMap.containsKey(definition.name)) {
            addPlaylist(
              Playlist(
                name: definition.name,
                isSmart: true,
                smartDefinition: definition,
              ),
            );
          }
        }
      } else if (content is Map && content['type'] != 'smart') {
        final name = content['name'];
        final id = content['id'];
        if (name is String &&
            name.isNotEmpty &&
            id is String &&
            id.isNotEmpty &&
            !playlistMap.containsKey(name)) {
          addPlaylist(Playlist(name: name, id: id));
        }
      }
    }
    updateNotifier.value++;
  }

  Future<void> _prepareForSync() async {
    if (isStreamSource) {
      _playlistsFile = File(
        "${getPlaylistConfigPath(sourceType)}/sylvakru_playlists.json",
      );
      initFile(_playlistsFile, true);

      final tmpPlaylist = await streamClient?.getPlaylists();
      for (final playlist in tmpPlaylist ?? <Playlist>[]) {
        if (playlist.name == '_sylvakru_play_queue_') {
          if (playlist.id != null) {
            await streamClient?.deletePlaylist(playlist.id!);
          }
          continue;
        }
        if (playlist.id == null || playlist.id!.isEmpty) {
          continue;
        }
        if (playlistMap[playlist.name] == null) {
          addPlaylist(playlist);
        }
        playlistMap[playlist.name]!.id = playlist.id;
      }
      update();
    }
  }

  Future<void> load() async {
    await _prepareForLoad();
    for (final playlist in playlists) {
      await playlist.load();
    }
  }

  Future<void> sync() async {
    if (isNotStreamSource) {
      await _prepareForLoad();
    } else {
      await _prepareForSync();
    }
    for (final playlist in playlists) {
      await playlist.sync();
    }
  }

  Playlist getPlaylistByIndex(int index) {
    assert(index >= 0 && index < playlists.length);
    return playlists[index];
  }

  Playlist? getPlaylistByName(String name) => playlistMap[name];

  void addPlaylist(Playlist playlist) {
    playlists.add(playlist);
    playlistMap[playlist.name] = playlist;
  }

  Future<bool> createSmartPlaylist(SmartPlaylistDefinition definition) async {
    if (isStreamSource) {
      return false;
    }
    final name = definition.name.trim();
    if (name.isEmpty || playlists.any((playlist) => playlist.name == name)) {
      return false;
    }
    final savedDefinition = SmartPlaylistDefinition(
      name: name,
      criteria: definition.criteria,
      sortType: definition.sortType,
    );
    final playlist = Playlist(
      name: name,
      isSmart: true,
      smartDefinition: savedDefinition,
    );
    playlist.refreshSmartSongs();
    addPlaylist(playlist);
    update();
    return true;
  }

  Future<bool> createPlaylist(String name) async {
    for (final playlist in playlists) {
      if (name == playlist.name) {
        showCenterMessage('Playlist exists');
        return false;
      }
    }

    final playlist = Playlist(name: name);
    if (isStreamSource) {
      playlist.id = await streamClient?.createPlaylist(name);
      if (playlist.id == null) {
        showCenterMessage('Create playlist failed');
        return false;
      }
    }
    addPlaylist(playlist);
    update();
    return true;
  }

  Future<void> deletePlaylist(Playlist playlist) async {
    if (playlist.isSmart) {
      playlists.remove(playlist);
      playlistMap.remove(playlist.name);
      update();
      return;
    }

    playlist.songListFile.deleteSync();
    if (playlist.id != null && streamClient != null) {
      if (!await streamClient!.deletePlaylist(playlist.id!)) {
        showCenterMessage('Delete playlist failed');
        return;
      }
    }
    playlists.remove(playlist);
    playlistMap.remove(playlist.name);
    update();
  }

  void update() {
    _playlistsFile = File(
      '${getPlaylistConfigPath(sourceType)}/sylvakru_playlists.json',
    );
    initFile(_playlistsFile, true);
    _playlistsFile.writeAsStringSync(
      jsonEncode(
        playlists.skip(1).map((playlist) {
          if (playlist.isSmart) {
            return {
              'type': 'smart',
              ...playlist.smartDefinition!.toJson(),
            };
          }
          return isStreamSource
              ? {'id': playlist.id, 'name': playlist.name}
              : playlist.name;
        }).toList(),
      ),
    );
    updateNotifier.value++;
  }

  void reset() {
    playlists.clear();
    playlistMap.clear();
    addPlaylist(Playlist(name: 'Favorite'));
    updateNotifier.value++;
  }
}

class Playlist {
  String name;

  String? id;

  late File songListFile;

  final bool isSmart;
  final SmartPlaylistDefinition? smartDefinition;

  List<MyAudioMetadata> songList = [];

  late bool isFavorite;
  late bool isNotFavorite;

  final changeNotifier = ValueNotifier(0);
  final sortTypeNotifier = ValueNotifier(0);
  bool canModify = true;

  Playlist({
    required this.name,
    this.id,
    this.isSmart = false,
    this.smartDefinition,
  }) {
    songListFile = File('${getPlaylistConfigPath(sourceType)}/$name.json');
    if (!isSmart) {
      initFile(songListFile, true);
    }
    isFavorite = name == 'Favorite';
    isNotFavorite = !isFavorite;
  }

  void refreshSmartSongs() {
    if (!isSmart || smartDefinition == null) {
      return;
    }
    songList = smartDefinition!.apply(library.songList);
    canModify = false;
    changeNotifier.value++;
  }

  MyPicture? get picture => getFirstSong(songList)?.picture;

  int get totalCount => songList.length;

  Future<void> load() async {
    canModify = false;
    changeNotifier.value++;

    if (isSmart) {
      refreshSmartSongs();
      canModify = false;
      layersManager.updateBackground();
      return;
    }

    final decoded = await readJsonListFile(songListFile);
    final validSongIds = <String>[];
    for (final id in decoded) {
      if (id is! String) {
        continue;
      }
      final song = library.id2Song[id];
      if (song == null) {
        continue;
      }
      songList.add(song);
      validSongIds.add(id);
      if (isFavorite) {
        song.isFavoriteNotifier.value = true;
      }
    }
    await songListFile.writeAsString(jsonEncode(validSongIds));

    canModify = true;
    changeNotifier.value++;
    layersManager.updateBackground();
  }

  Future<void> sync() async {
    songList.clear();
    if (isSmart) {
      refreshSmartSongs();
      layersManager.updateBackground();
      return;
    }

    if (isNotStreamSource) {
      await load();
    } else {
      canModify = false;
      changeNotifier.value++;
      List<MyAudioMetadata>? tmpSongs;
      if (isFavorite) {
        tmpSongs = await streamClient?.getStarredSongs();
      } else if (id != null) {
        tmpSongs = await streamClient?.getPlaylistSongs(id!);
      }
      for (final song in tmpSongs ?? []) {
        songList.add(song);
        if (isFavorite) {
          song.isFavoriteNotifier.value = true;
        }
      }
      canModify = true;
      changeNotifier.value++;
      layersManager.updateBackground();
    }
    final songIds = songList.map((e) => e.id).toList();
    await songListFile.writeAsString(jsonEncode(songIds));
  }

  Future<void> add(List<MyAudioMetadata> songList) async {
    if (isSmart || !canModify) {
      showCenterMessage('Can not modify, it\'s updating');
      return;
    }
    for (MyAudioMetadata song in songList) {
      final targetSongList = this.songList;
      if (targetSongList.contains(song)) {
        continue;
      }
      targetSongList.insert(0, song);

      if (isFavorite) {
        song.isFavoriteNotifier.value = true;
      }
    }
    await update();
  }

  Future<void> remove(List<MyAudioMetadata> songList) async {
    if (isSmart || !canModify) {
      showCenterMessage('Can not modify, it\'s updating');
      return;
    }
    for (MyAudioMetadata song in songList) {
      final targetSongList = this.songList;
      targetSongList.remove(song);

      if (isFavorite) {
        song.isFavoriteNotifier.value = false;
      }
    }
    await update();
  }

  Future<void> update() async {
    if (isSmart || !canModify) {
      showCenterMessage('Can not modify, it\'s updating');
      return;
    }
    canModify = false;
    changeNotifier.value++;
    playlistManager.updateNotifier.value++;
    layersManager.updateBackground();

    final songIds = songList.map((e) => e.id).toList();
    await songListFile.writeAsString(jsonEncode(songIds));
    if (isStreamSource) {
      late bool success;
      if (isFavorite) {
        success = await streamClient?.updateStarredSongs(songIds) ?? false;
      } else {
        success =
            await streamClient?.updatePlaylistSongs(id!, songIds) ?? false;
      }
      if (!success) {
        showCenterMessage('Update playlist failed');
      }
    }
    canModify = true;
    changeNotifier.value++;
  }
}

void toggleFavoriteState(MyAudioMetadata song) {
  final favorite = playlistManager.playlists.first;
  if (!favorite.canModify) {
    return;
  }
  final isFavorite = song.isFavoriteNotifier;
  if (isFavorite.value) {
    favorite.remove([song]);
  } else {
    favorite.add([song]);
  }
}
