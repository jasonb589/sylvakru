import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/utils/path.dart';
import 'package:sylvakru/base/services/logger.dart';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';

MyAudioMetadata song(String id) => MyAudioMetadata(
  AudioMetadata(title: id),
  id: id,
  path: '/music/$id.flac',
);
File writeCacheFile(String name, double mb) {
  final file = File('${getCachesPath(sourceType)}/$name');
  file.createSync(recursive: true);
  file.writeAsBytesSync(List.filled((mb * 1024 * 1024).round(), 0));
  return file;
}

void main() {
  late Directory support;
  late Directory cacheDir;

  // appSupportDir is a late final, so it can only be assigned once per process
  // appSupportDir is a late final, so it can only be assigned once per process
  setUpAll(() async {
    support = Directory.systemTemp.createTempSync('sylvakru_cache');
    appSupportDir = support;
    // enforceCacheLimit logs what it evicted
    await logger.init();
  });
  setUp(() {
    sourceType = SourceType.navidrome;
    isStreamSource = true;
    isNotStreamSource = false;

    cacheDir = Directory(getCachesPath(sourceType));
    if (cacheDir.existsSync()) {
      cacheDir.deleteSync(recursive: true);
    }
    cacheDir.createSync(recursive: true);
    cacheLimitMbNotifier.value = 0;
  });

  double cacheMb() {
    var total = 0;
    for (final entity in cacheDir.listSync()) {
      if (entity is File) {
        total += entity.lengthSync();
      }
    }
    return total / (1024 * 1024);
  }

  group('enforceCacheLimit', () {
    test('does nothing when no limit is set', () async {
      writeCacheFile('a', 3);
      writeCacheFile('b', 3);

      await library.enforceCacheLimit();

      expect(cacheMb(), closeTo(6, 0.1));
    });

    test('trims the cache down to the limit', () async {
      // 2 + 2 + 2 MB against a 3 MB bound: at least one file has to go
      for (final name in ['old', 'mid', 'new']) {
        writeCacheFile(name, 2);
      }
      // make the age order unambiguous (lastAccessed is not reliable on every
      // filesystem, so the code falls back to the modification time)
      final now = DateTime.now();
      File('${cacheDir.path}/old').setLastModifiedSync(
        now.subtract(const Duration(days: 3)),
      );
      File('${cacheDir.path}/mid').setLastModifiedSync(
        now.subtract(const Duration(days: 2)),
      );
      File('${cacheDir.path}/new').setLastModifiedSync(
        now.subtract(const Duration(days: 1)),
      );

      cacheLimitMbNotifier.value = 3;
      await library.enforceCacheLimit();

      expect(cacheMb(), lessThanOrEqualTo(3.1));
      // the oldest went first
      expect(File('${cacheDir.path}/old').existsSync(), isFalse);
    });

    test('never deletes the song that is playing', () async {
      // the cached file name is the md5 of the song id, so build the song
      // first and use the path it computed
      final playing = song('playing');
      final playingFile = File(playing.cachePath!);
      playingFile.createSync(recursive: true);
      playingFile.writeAsBytesSync(List.filled(2 * 1024 * 1024, 0));
      writeCacheFile('other-old', 2);
      writeCacheFile('other-new', 2);

      final now = DateTime.now();
      // make the playing song's file the oldest, i.e. the first eviction
      // candidate, so only the "keep" rule can save it
      playingFile.setLastModifiedSync(now.subtract(const Duration(days: 5)));
      File('${cacheDir.path}/other-old').setLastModifiedSync(
        now.subtract(const Duration(days: 3)),
      );
      File('${cacheDir.path}/other-new').setLastModifiedSync(
        now.subtract(const Duration(days: 1)),
      );

      library.id2Song['playing'] = playing;
      addTearDown(() => library.id2Song.remove('playing'));

      cacheLimitMbNotifier.value = 3;
      await library.enforceCacheLimit(keepSongId: 'playing');

      expect(
        playingFile.existsSync(),
        isTrue,
        reason: 'the playing song must keep its cached file',
      );
      expect(cacheMb(), lessThanOrEqualTo(3.1));
    });

    test('leaves a cache that already fits alone', () async {
      writeCacheFile('a', 1);
      cacheLimitMbNotifier.value = 100;

      await library.enforceCacheLimit();

      expect(File('${cacheDir.path}/a').existsSync(), isTrue);
    });

    test('is harmless when the cache directory does not exist', () async {
      cacheDir.deleteSync(recursive: true);
      cacheLimitMbNotifier.value = 1;

      await library.enforceCacheLimit();
    });
  });
}
