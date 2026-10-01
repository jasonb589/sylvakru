import 'dart:convert';
import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/playlist.dart';
import 'package:sylvakru/base/data/smart_playlist.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';

MyAudioMetadata _song(
  String id, {
  String? title,
  String? artist,
  String? album,
  String? albumArtist,
  String? genre,
  int? year,
  int? durationSeconds,
  int? bitrate,
}) => MyAudioMetadata(
  AudioMetadata(
    title: title,
    artist: artist,
    album: album,
    albumArtist: albumArtist,
    genre: genre,
    year: year,
    duration: durationSeconds == null
        ? null
        : Duration(seconds: durationSeconds),
    bitrate: bitrate,
  ),
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
      criteria: SmartPlaylistCriteria(
        query: 'blue',
        fields: {SmartPlaylistField.title},
        minYear: 1990,
        maxYear: 1999,
      ),
      sortType: 1,
    );

    final restored = SmartPlaylistDefinition.fromJson(definition.toJson());
    final songs = [
      _song('b', title: 'Blue Moon', year: 1995),
      _song('a', title: 'Blue Train', year: 1992),
      _song('old', title: 'Blue Note', year: 1985),
    ];

    expect(restored.name, 'Nineties');
    expect(restored.criteria.query, 'blue');
    expect(restored.apply(songs).map((song) => song.id), ['b', 'a']);
  });

  test('empty rules match the whole library', () {
    final songs = [
      _song('a', title: 'First', year: 1990),
      _song('b', title: 'Second', year: 2000),
    ];
    final definition = SmartPlaylistDefinition(
      name: 'Everything',
      criteria: SmartPlaylistCriteria(),
    );

    expect(definition.apply(songs).map((song) => song.id), ['a', 'b']);
  });

  test('sync reloads local playlists and smart rules after reset', () async {
    final songs = [
      _song('train', title: 'Blue Train', year: 1995),
      _song('moon', title: 'Blue Moon', year: 1996),
      _song('red', title: 'Red River', year: 1997),
    ];
    library.songList = songs;
    library.id2Song.addEntries(songs.map((song) => MapEntry(song.id, song)));

    final criteria = SmartPlaylistCriteria(
      query: 'blue',
      fields: {SmartPlaylistField.title},
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
      criteria: SmartPlaylistCriteria(
        query: 'blue',
        fields: {SmartPlaylistField.title},
      ),
    );

    expect(await playlistManager.createSmartPlaylist(definition), isTrue);
    expect(playlistManager.getPlaylistByName('Favorites')?.isSmart, isTrue);
    expect(await playlistManager.createSmartPlaylist(definition), isFalse);
  });

  group('criteria', () {
    List<MyAudioMetadata> songs() => [
      _song(
        'one',
        title: 'Blue Train',
        artist: 'John Coltrane',
        album: 'Classic Jazz',
        albumArtist: 'John Coltrane Quartet',
        genre: 'Jazz',
        year: 1957,
        durationSeconds: 600,
        bitrate: 320,
      ),
      _song(
        'two',
        title: 'Blue in Green',
        artist: 'Miles Davis',
        album: 'Kind of Blue',
        genre: 'Jazz',
        year: 1959,
        durationSeconds: 337,
        bitrate: 256,
      ),
      _song(
        'three',
        title: 'Blue Sky',
        artist: 'The Allman Brothers Band',
        album: 'Eat a Peach',
        genre: 'Rock',
      ),
    ];

    test('searches enabled metadata fields case-insensitively', () {
      final criteria = SmartPlaylistCriteria(
        query: 'COLTRANE QUARTET',
        fields: {SmartPlaylistField.albumArtist},
      );

      expect(criteria.applyToList(songs()).map((song) => song.id), ['one']);
    });

    test('exact matching uses the selected field only', () {
      final criteria = SmartPlaylistCriteria(
        query: 'Blue Train',
        fields: {SmartPlaylistField.title},
        exactMatch: true,
      );

      expect(criteria.applyToList(songs()).map((song) => song.id), ['one']);
      expect(
        SmartPlaylistCriteria(
          query: 'Blue',
          fields: {SmartPlaylistField.title},
          exactMatch: true,
        ).applyToList(songs()),
        isEmpty,
      );
    });

    test('combines year, duration and bitrate ranges inclusively', () {
      final criteria = SmartPlaylistCriteria(
        minYear: 1957,
        maxYear: 1959,
        minDurationSeconds: 337,
        maxDurationSeconds: 600,
        minBitrateKbps: 256,
        maxBitrateKbps: 320,
      );

      expect(criteria.applyToList(songs()).map((song) => song.id), [
        'one',
        'two',
      ]);
    });

    test('a range excludes songs whose metadata is missing', () {
      final criteria = SmartPlaylistCriteria(minYear: 1950);

      expect(criteria.applyToList(songs()).map((song) => song.id), [
        'one',
        'two',
      ]);
    });

    test('does not match a keyword when no search fields are selected', () {
      final criteria = SmartPlaylistCriteria(query: 'blue', fields: const {});

      expect(criteria.applyToList(songs()), isEmpty);
    });
  });
}
