import 'dart:convert';
import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/playlist.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/utils/advanced_song_search.dart';

MyAudioMetadata _song(String id, String title, int year) => MyAudioMetadata(
  AudioMetadata(title: title, year: year),
  id: id,
);

void main() {
  setUpAll(() {
    appSupportDir = Directory.systemTemp.createTempSync('sylvakru_smart');
  });

  setUp(() {
    sourceType = SourceType.local;
    isStreamSource = false;
    isNotStreamSource = true;
    library.id2Song.clear();
    library.songList = [];
    playlistManager.reset();
  });

  test('smart playlist definition round-trips and applies rules', () {
    final definition = SmartPlaylistDefinition(
      name: 'Nineties',
      criteria: SongSearchCriteria(
        query: 'blue',
        fields: {SongSearchField.title},
        minYear: 1990,
        maxYear: 1999,
      ),
      sortType: 1,
    );

    final restored = SmartPlaylistDefinition.fromJson(definition.toJson());
    final songs = [
      _song('b', 'Blue Moon', 1995),
      _song('a', 'Blue Train', 1992),
      _song('old', 'Blue Note', 1985),
    ];

    expect(restored.name, 'Nineties');
    expect(restored.criteria.query, 'blue');
    expect(restored.apply(songs).map((song) => song.id), ['b', 'a']);
  });

  test('empty rules match the whole library', () {
    final songs = [_song('a', 'First', 1990), _song('b', 'Second', 2000)];
    final definition = SmartPlaylistDefinition(
      name: 'Everything',
      criteria: SongSearchCriteria(),
    );

    expect(definition.apply(songs).map((song) => song.id), ['a', 'b']);
  });

  test('sync reloads local playlists and smart rules after reset', () async {
    final songs = [
      _song('train', 'Blue Train', 1995),
      _song('moon', 'Blue Moon', 1996),
      _song('red', 'Red River', 1997),
    ];
    library.songList = songs;
    library.id2Song.addEntries(songs.map((song) => MapEntry(song.id, song)));

    final criteria = SongSearchCriteria(
      query: 'blue',
      fields: {SongSearchField.title},
      minYear: 1990,
      maxYear: 1999,
    );
    final playlistsFile = File(
      '${appSupportDir.path}/local/playlist_config/sylvakru_playlists.json',
    )..createSync(recursive: true);
    playlistsFile.writeAsStringSync(
      jsonEncode([
        'Manual',
        {
          'type': 'smart',
          'name': 'Blue Nineties',
          'criteria': criteria.toJson(),
          'sortType': 1,
        },
      ]),
    );

    playlistManager.reset();
    await playlistManager.sync();

    expect(playlistManager.getPlaylistByName('Manual')?.isSmart, isFalse);
    final smartPlaylist = playlistManager.getPlaylistByName('Blue Nineties');
    expect(smartPlaylist?.isSmart, isTrue);
    expect(smartPlaylist?.canModify, isFalse);
    expect(smartPlaylist?.songList.map((song) => song.id), ['moon', 'train']);
    expect(smartPlaylist!.songListFile.existsSync(), isFalse);
  });

  test('creating smart playlists trims names and rejects duplicates', () async {
    final definition = SmartPlaylistDefinition(
      name: '  Favorites  ',
      criteria: SongSearchCriteria(
        query: 'blue',
        fields: {SongSearchField.title},
      ),
    );

    expect(await playlistManager.createSmartPlaylist(definition), isTrue);
    expect(playlistManager.getPlaylistByName('Favorites')?.isSmart, isTrue);
    expect(await playlistManager.createSmartPlaylist(definition), isFalse);
  });
}
