import 'dart:async';

import 'package:lpinyin/lpinyin.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/services/picture_service.dart';
import 'package:sylvakru/base/services/stream_client.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:sylvakru/layer/layers_manager.dart';

ArtistAlbumManager artistAlbumManager = ArtistAlbumManager();

class ArtistAlbumManager {
  List<Artist> artistList = [];
  Map<String, Artist> artistMap = {};

  List<Album> albumList = [];
  // streamSoure will has duplicate name album
  Map<String, Album> albumMap = {};
  final updateNotifier = ValueNotifier(0);

  /// The albums shown in the "recently added" module on the home page.
  List<Album> recentlyAddedAlbumList = [];
  final recentlyAddedNotifier = ValueNotifier(0);

  /// How many albums the "recently added" module shows at most.
  static const int recentlyAddedLimit = 20;

  ArtistAlbumManager() {
    artistsIsAscendingNotifier.addListener(() {
      sortArtists();
      updateNotifier.value++;
    });
    albumsIsAscendingNotifier.addListener(() {
      sortAlbums();
      updateNotifier.value++;
    });
  }

  List<ArtistAlbumBase> getArtistAlbumList(bool isArtist) {
    return isArtist ? artistList : albumList;
  }

  ValueNotifier<bool> getRandomizeNotifier(bool isArtist) {
    return isArtist ? artistsRandomizeNotifier : albumsRandomizeNotifier;
  }

  ValueNotifier<bool> getIsAscendingNotifier(bool isArtist) {
    return isArtist ? artistsIsAscendingNotifier : albumsIsAscendingNotifier;
  }

  ValueNotifier<bool> getUseLargePictureNotifier(bool isArtist) {
    return isArtist
        ? artistsUseLargePictureNotifier
        : albumsUseLargePictureNotifier;
  }

  void classify() {
    for (final song in library.songList) {
      _processSong(song);
    }

    sortArtists();
    sortAlbums();

    for (final album in albumList) {
      album.sort();
    }

    for (final artist in artistList) {
      artist.combineAlbums();
    }

    updateRecentlyAddedFromAlbums();

    updateNotifier.value++;
  }

  /// The albums that have ever been added, newest added first.
  ///
  /// Stream sources only know the albums they have already fetched, so this
  /// list is filled by [loadRecentlyAdded].
  List<Album> get recentlyAddedAlbums {
    final sorted = albumList.where((album) => album.addedTime != null).toList()
      ..sort((a, b) => b.addedTime!.compareTo(a.addedTime!));
    return sorted;
  }

  /// Rebuilds [recentlyAddedAlbumList] from the local album list.
  ///
  /// Only meaningful for non-stream sources, where every album already knows
  /// when its files were last modified.
  void updateRecentlyAddedFromAlbums() {
    recentlyAddedAlbumList = recentlyAddedAlbums
        .take(recentlyAddedLimit)
        .toList();
    recentlyAddedNotifier.value++;
  }

  /// The server side sort used to ask for the newest albums.
  String get _recentlyAddedSortType {
    switch (sourceType) {
      case .navidrome:
        // getAlbumList2 'newest' is already ordered by creation time, newest
        // first.
        return 'newest';
      case .emby:
        return 'DateCreated';
      default:
        return 'alphabeticalByName';
    }
  }

  Completer<void>? _recentlyAddedCompleter;
  bool _recentlyAddedLoaded = false;

  /// Whether the "recently added" albums have been fetched already.
  bool get recentlyAddedLoaded => _recentlyAddedLoaded;

  /// Loads the albums for the "recently added" module.
  ///
  /// Local and WebDAV libraries are sorted locally, stream sources are asked
  /// for their newest albums instead.
  Future<void> loadRecentlyAdded({bool force = false}) async {
    if (_recentlyAddedLoaded && !force) {
      return;
    }

    final pending = _recentlyAddedCompleter;
    if (pending != null) {
      return pending.future;
    }

    if (isNotStreamSource) {
      // notifies through updateRecentlyAddedFromAlbums
      updateRecentlyAddedFromAlbums();
      _recentlyAddedLoaded = true;
      return;
    }

    final completer = Completer<void>();
    _recentlyAddedCompleter = completer;
    try {
      final albumList = await streamClient?.getAlbumList(
        0,
        type: _recentlyAddedSortType,
        descending: true,
      );
      if (albumList != null) {
        final sorted = albumList.toList();
        // trust the server order unless every album knows its creation time
        if (sorted.every((album) => album.created != null)) {
          sorted.sort((a, b) => b.created!.compareTo(a.created!));
        }
        recentlyAddedAlbumList = sorted.take(recentlyAddedLimit).toList();
      }
      // a failed request must not be cached as success, otherwise the module
      // stays empty for the whole session when the server was unreachable
      if (albumList != null) {
        _recentlyAddedLoaded = true;
        recentlyAddedNotifier.value++;
      }
    } finally {
      _recentlyAddedCompleter = null;
      completer.complete();
    }
  }

  void _processSong(MyAudioMetadata song) {
    final albumName = getAlbum(song);

    Album? album = albumMap[albumName];
    if (album == null) {
      album = Album(albumName);
      albumList.add(album);
      albumMap[albumName] = album;
    }

    if (song.year != null && album.year == null) {
      album.year = song.year;
    }

    album.songList.add(song);

    for (String artistName in getArtists(getArtist(song))) {
      Artist? artist = artistMap[artistName];
      if (artist == null) {
        artist = Artist(artistName);
        artistList.add(artist);
        artistMap[artistName] = artist;
      }
      artist.albumSet.add(album);
    }
  }

  void sortArtists() {
    artistList.sort((a, b) {
      if (artistsIsAscendingNotifier.value) {
        return a.compareName.compareTo(b.compareName);
      } else {
        return b.compareName.compareTo(a.compareName);
      }
    });
  }

  void sortAlbums() {
    albumList.sort((a, b) {
      if (albumsIsAscendingNotifier.value) {
        return a.compareName.compareTo(b.compareName);
      } else {
        return b.compareName.compareTo(a.compareName);
      }
    });
  }

  void updateArtistAlbum() {
    layersManager.clearArtistAlbum();
    artistList.clear();
    albumList.clear();
    artistMap.clear();
    albumMap.clear();

    // stream sources have to ask the server again for their newest albums
    _recentlyAddedLoaded = false;
    recentlyAddedAlbumList = [];

    classify();
  }

  // use completer to avoid loading same data multiple times
  Completer<void>? artistCompleter;
  Completer<int?>? ablumCompleter;

  Future<void> loadArtists() async {
    if (artistCompleter == null) {
      artistCompleter = Completer<void>();
      final tmpArtistList = await streamClient?.getArtistList();
      if (tmpArtistList == null) {
        artistAlbumManager.updateNotifier.value++;
        artistCompleter!.complete();
        return;
      }

      for (final artist in tmpArtistList) {
        artistList.add(artist);
        artistMap[artist.name] = artist;
      }
      sortArtists();
      artistAlbumManager.updateNotifier.value++;
      artistCompleter!.complete();
      return;
    }
    artistAlbumManager.updateNotifier.value++;
    return artistCompleter!.future;
  }

  // null: error; 0: end
  Future<int?> loadAlbums() async {
    if (ablumCompleter == null) {
      ablumCompleter = Completer<int?>();
      final albumList = await streamClient?.getAlbumList(
        artistAlbumManager.albumList.length,
      );
      if (albumList == null) {
        artistAlbumManager.updateNotifier.value++;
        ablumCompleter!.complete(null);
        ablumCompleter = null;
        return null;
      }

      artistAlbumManager.albumList.addAll(albumList);
      sortAlbums();
      artistAlbumManager.updateNotifier.value++;

      ablumCompleter!.complete(albumList.length);
      ablumCompleter = null;
      return albumList.length;
    }
    return ablumCompleter!.future;
  }
}

abstract class ArtistAlbumBase {
  String? id;
  final String name;
  late final String compareName;

  final List<MyAudioMetadata> songList = [];

  final bool isArtist;

  MyPicture? _picture;
  MyPicture get picture => isStreamSource ? _picture! : getCoverSong().picture;

  ArtistAlbumBase(this.name, this.isArtist, {this.id, String? coverArtId}) {
    id ??= name;
    compareName = PinyinHelper.getPinyinE(name);
    if (isStreamSource) {
      _picture = MyPicture.form(coverArtId ?? '');
    }
  }

  bool get isEmpty => songList.isEmpty;

  MyAudioMetadata getCoverSong() {
    return songList.first;
  }

  int get totalCount => songList.length;

  Completer<void>? completer;

  Future<void> load();
}

class Artist extends ArtistAlbumBase {
  Artist(String name, {super.id, super.coverArtId}) : super(name, false);

  Set<Album> albumSet = {};

  List<Album> albumList = [];

  final changeNotifier = ValueNotifier(0);

  void combineAlbums() {
    albumSet.removeWhere((album) => album.isEmpty);
    albumList = albumSet.toList();
    albumList.sort((a, b) {
      int aYear = a.year ?? 9999;
      int bYear = b.year ?? 9999;

      return aYear.compareTo(bYear);
    });

    for (final album in albumList) {
      songList.addAll(album.artist2SongList[name]!);
    }
  }

  @override
  Future<void> load() async {
    if (completer == null) {
      completer = Completer<void>();
      if (sourceType == .navidrome || sourceType == .feiniu) {
        final albums = await streamClient?.getArtistAlbumList(id!);
        if (albums == null) {
          completer!.complete();
          return;
        } else {
          albumList.addAll(albums);
        }

        for (final album in albumList) {
          await album.load();
          if (sourceType == .navidrome) {
            songList.addAll(album.songList);
          }
          changeNotifier.value++;
        }
        if (sourceType == .feiniu) {
          songList.addAll(await streamClient?.getArtistSongs(id!) ?? []);
          changeNotifier.value++;
        }
        completer!.complete();
        return;
      } else {
        songList.addAll(await streamClient?.getArtistSongs(id!) ?? []);
        changeNotifier.value++;
        completer!.complete();
        return;
      }
    }
    return completer!.future;
  }
}

class Album extends ArtistAlbumBase {
  Album(String name, {super.id, super.coverArtId, this.year, this.created})
    : super(name, false);

  Map<String, List<MyAudioMetadata>> artist2SongList = {};
  int? year;

  /// Creation time reported by the server, only available for stream sources.
  DateTime? created;

  DateTime? _addedTime;
  bool _addedTimeReady = false;

  /// When this album entered the library.
  ///
  /// Local and WebDAV libraries have no creation time, so the newest file
  /// modification time among the album's songs is used instead. The result is
  /// cached because it is read while sorting the whole album list.
  DateTime? get addedTime {
    if (_addedTimeReady) {
      return _addedTime;
    }
    _addedTimeReady = true;

    if (created != null) {
      return _addedTime = created;
    }

    DateTime? latest;
    for (final song in songList) {
      final modified = song.modified;
      if (modified != null && (latest == null || modified.isAfter(latest))) {
        latest = modified;
      }
    }
    return _addedTime = latest;
  }

  int _sort(MyAudioMetadata a, MyAudioMetadata b) {
    final discA = a.disc ?? 9999;
    final discB = b.disc ?? 9999;

    final discCompare = discA.compareTo(discB);
    if (discCompare != 0) return discCompare;

    final trackA = a.track ?? 9999;
    final trackB = b.track ?? 9999;

    return trackA.compareTo(trackB);
  }

  void sort() {
    songList.sort((a, b) => _sort(a, b));
    for (final song in songList) {
      for (String artistName in getArtists(getArtist(song))) {
        final tmp = artist2SongList.putIfAbsent(artistName, () => []);
        tmp.add(song);
      }
    }
  }

  @override
  Future<void> load() async {
    if (completer == null) {
      // ensure load one time
      completer = Completer<void>();
      songList.addAll(await streamClient?.getAlbumSongs(id!) ?? []);
      completer!.complete();
      return;
    }
    return completer!.future;
  }
}
