import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/services/lyric.dart';
import 'package:sylvakru/base/utils/path.dart';

/// What "clear the cache" has to mean: the folder really goes, with whatever
/// grew below it, and the lyrics that were parsed for the songs go with it -
/// otherwise a song keeps the words it read before the .lrc file was edited.
void main() {
  late Directory support;

  setUpAll(() async {
    support = Directory.systemTemp.createTempSync('sylvakru_cache_clear');
    appSupportDir = support;
    await logger.init();
  });

  setUp(() async {
    sourceType = SourceType.navidrome;
    isStreamSource = true;
    isNotStreamSource = false;
    cacheSizeNotifier.value = 0;
    await setting.load();
    library.id2Song.clear();
    final cacheDir = Directory(getCachesPath(sourceType));
    if (cacheDir.existsSync()) {
      cacheDir.deleteSync(recursive: true);
    }
  });

  MyAudioMetadata song(String id) {
    final item = MyAudioMetadata(
      AudioMetadata(title: id),
      id: id,
      path: '/music/$id.flac',
    );
    library.id2Song[id] = item;
    return item;
  }

  test(
    'clearing the cache removes the folder and everything under it',
    () async {
      final item = song('cached');
      final cacheDir = Directory(getCachesPath(sourceType));
      final nested = Directory('${cacheDir.path}/nested')
        ..createSync(recursive: true);
      File('${cacheDir.path}/top').writeAsStringSync('audio');
      File('${nested.path}/deep').writeAsStringSync('audio');
      item.cacheExist = true;
      cacheSizeNotifier.value = 3;

      await library.clearCache();

      expect(cacheDir.existsSync(), isFalse);
      expect(item.cacheExist, isFalse);
      expect(cacheSizeNotifier.value, 0);
    },
  );

  test(
    'clearing the cache drops the lyrics that were already parsed',
    () async {
      final item = song('lyrics');
      item.parsedLyrics = ParsedLyrics()
        ..lines.add(LyricLine(Duration.zero, 'Hello', []));

      await library.clearLrcCache();

      expect(item.parsedLyrics, isNull);
    },
  );
}
