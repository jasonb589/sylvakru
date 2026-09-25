import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/utils/advanced_song_search.dart';

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
}) {
  return MyAudioMetadata(
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
}

void main() {
  setUpAll(() {
    appSupportDir = Directory.systemTemp.createTempSync('sylvakru_search');
  });

  group('SongSearchCriteria', () {
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
      final result = filterSongListAdvanced(
        songs(),
        query: 'COLTRANE QUARTET',
        criteria: SongSearchCriteria(fields: {SongSearchField.albumArtist}),
      );

      expect(result.map((song) => song.id), ['one']);
    });

    test('default criteria detects custom field selections', () {
      expect(SongSearchCriteria().isDefault, isTrue);
      expect(
        SongSearchCriteria(fields: {SongSearchField.title}).isDefault,
        isFalse,
      );
    });

    test('exact matching uses the selected field only', () {
      final criteria = SongSearchCriteria(
        fields: {SongSearchField.title},
        exactMatch: true,
      );

      expect(
        filterSongListAdvanced(songs(), query: 'Blue Train', criteria: criteria)
            .map((song) => song.id),
        ['one'],
      );
      expect(
        filterSongListAdvanced(songs(), query: 'Blue', criteria: criteria),
        isEmpty,
      );
    });

    test('combines year, duration and bitrate ranges inclusively', () {
      final result = filterSongListAdvanced(
        songs(),
        query: '',
        criteria: SongSearchCriteria(
          minYear: 1957,
          maxYear: 1959,
          minDurationSeconds: 337,
          maxDurationSeconds: 600,
          minBitrateKbps: 256,
          maxBitrateKbps: 320,
        ),
      );

      expect(result.map((song) => song.id), ['one', 'two']);
    });

    test('a range excludes songs whose metadata is missing', () {
      final result = filterSongListAdvanced(
        songs(),
        query: '',
        criteria: SongSearchCriteria(minYear: 1950),
      );

      expect(result.map((song) => song.id), ['one', 'two']);
    });

    test('does not match keyword when no search fields are selected', () {
      final result = filterSongListAdvanced(
        songs(),
        query: 'blue',
        criteria: SongSearchCriteria(fields: const {}),
      );

      expect(result, isEmpty);
    });
  });
}
