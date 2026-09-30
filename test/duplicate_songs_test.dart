import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/utils/duplicate_songs.dart';

/// The duplicate report has to find the same recording twice without inventing
/// duplicates: a different length or a different artist is a different take, and
/// a song with no title is nothing to compare by.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Building a song touches the app's support folder (cover and cache paths).
  setUpAll(() {
    appSupportDir = Directory.systemTemp.createTempSync('sylvakru_dupes');
  });

  MyAudioMetadata song(
    String? title,
    String? artist, {
    Duration? length,
    String? path,
  }) => MyAudioMetadata(
    AudioMetadata(title: title, artist: artist, duration: length),
    id: '${title ?? ''}-${artist ?? ''}-${path ?? ''}',
    path: path,
  );

  group('findDuplicateSongs', () {
    test('the same song twice, a second and a half apart', () {
      final groups = findDuplicateSongs([
        song(
          'Know Better',
          'Tinashe',
          length: const Duration(seconds: 211),
          path: '/a/1.flac',
        ),
        song(
          'Know Better',
          'Tinashe',
          length: const Duration(seconds: 212, milliseconds: 500),
          path: '/b/1.mp3',
        ),
      ]);

      expect(groups, hasLength(1));
      expect(groups.first.songs, hasLength(2));
      expect(groups.first.song.path, '/a/1.flac', reason: 'shortest first');
    });

    test('case, padding and punctuation are not a second song', () {
      final groups = findDuplicateSongs([
        song('Know Better', 'Tinashe', length: const Duration(seconds: 211)),
        song(' know better ', 'TINASHE', length: const Duration(seconds: 211)),
      ]);

      expect(groups, hasLength(1));
    });

    test('a different take is not a duplicate', () {
      final groups = findDuplicateSongs([
        song('Know Better', 'Tinashe', length: const Duration(seconds: 211)),
        song('Know Better', 'Tinashe', length: const Duration(seconds: 254)),
        song(
          'Know Better',
          'Someone Else',
          length: const Duration(seconds: 211),
        ),
      ]);

      expect(groups, isEmpty);
    });

    test('a length in the middle does not weld two takes together', () {
      // 100s and 101.5s are one recording; 103s is a take of its own. The
      // cluster is measured against its shortest member, never the last one in.
      final groups = findDuplicateSongs([
        song('T', 'A', length: const Duration(seconds: 100)),
        song('T', 'A', length: const Duration(seconds: 101, milliseconds: 500)),
        song('T', 'A', length: const Duration(seconds: 103)),
      ]);

      expect(groups, hasLength(1));
      expect(groups.first.songs.map((song) => song.duration), [
        const Duration(seconds: 100),
        const Duration(seconds: 101, milliseconds: 500),
      ]);
    });

    test('songs without a title are left out', () {
      final groups = findDuplicateSongs([
        song(null, 'Tinashe', length: const Duration(seconds: 211)),
        song('   ', 'Tinashe', length: const Duration(seconds: 211)),
      ]);

      expect(groups, isEmpty);
    });

    test('an unknown length only compares with another unknown length', () {
      final groups = findDuplicateSongs([
        song('T', 'A'),
        song('T', 'A'),
        song('T', 'A', length: const Duration(seconds: 200)),
      ]);

      expect(groups, hasLength(1));
      expect(groups.first.songs, hasLength(2));
      expect(groups.first.songs.every((song) => song.duration == null), isTrue);
    });

    test('groups are listed by title', () {
      final groups = findDuplicateSongs([
        song('Zebra', 'A', length: const Duration(seconds: 100)),
        song('Zebra', 'A', length: const Duration(seconds: 100)),
        song('apple', 'A', length: const Duration(seconds: 100)),
        song('apple', 'A', length: const Duration(seconds: 100)),
      ]);

      expect(groups.map((group) => group.song.title), ['apple', 'Zebra']);
    });
  });

  group('songPath', () {
    test('prefers the song file, then the download, then the cache', () {
      expect(songPath(song('T', 'A', path: '/songs/x.flac')), '/songs/x.flac');

      final downloaded = song('T', 'A')..downloadPath = '/downloads/x.mp3';
      expect(songPath(downloaded), '/downloads/x.mp3');

      final cached = song('T', 'A')..cachePath = '/cache/hash';
      expect(songPath(cached), '/cache/hash');

      expect(songPath(song('T', 'A')), isNull);
    });
  });
}
