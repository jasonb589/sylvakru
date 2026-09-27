import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/utils/path.dart';

MyAudioMetadata song(String id) => MyAudioMetadata(
  AudioMetadata(title: id),
  id: id,
  path: '/music/$id.flac',
);

File writeDownloadFile(String name, double mb) {
  final file = File('${getDownloadsPath(sourceType)}/$name');
  file.createSync(recursive: true);
  file.writeAsBytesSync(List.filled((mb * 1024 * 1024).round(), 0));
  return file;
}

void main() {
  late Directory support;
  late Directory downloadDir;

  setUpAll(() async {
    support = Directory.systemTemp.createTempSync('sylvakru_download_limit');
    appSupportDir = support;
    await logger.init();
  });

  setUp(() {
    sourceType = SourceType.navidrome;
    isStreamSource = true;
    isNotStreamSource = false;
    library.id2Song.clear();

    for (final path in [
      getCachesPath(sourceType),
      getDownloadsPath(sourceType),
    ]) {
      final directory = Directory(path);
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
    downloadDir = Directory(getDownloadsPath(sourceType));
    downloadDir.createSync(recursive: true);
    offlineMusicLimitMbNotifier.value = 0;
    downloadSizeNotifier.value = 0;
  });

  double downloadMb() {
    var total = 0;
    for (final entity in downloadDir.listSync()) {
      if (entity is File) {
        total += entity.lengthSync();
      }
    }
    return total / (1024 * 1024);
  }

  group('enforceDownloadLimit', () {
    test('does nothing when no limit is set', () async {
      writeDownloadFile('a', 3);
      writeDownloadFile('b', 3);

      await library.enforceDownloadLimit();

      expect(downloadMb(), closeTo(6, 0.1));
    });

    test('trims offline music down to the limit', () async {
      for (final name in ['old', 'mid', 'new']) {
        writeDownloadFile(name, 2);
      }
      final now = DateTime.now();
      File(
        '${downloadDir.path}/old',
      ).setLastModifiedSync(now.subtract(const Duration(days: 3)));
      File(
        '${downloadDir.path}/mid',
      ).setLastModifiedSync(now.subtract(const Duration(days: 2)));
      File(
        '${downloadDir.path}/new',
      ).setLastModifiedSync(now.subtract(const Duration(days: 1)));

      offlineMusicLimitMbNotifier.value = 3;
      await library.enforceDownloadLimit();

      expect(downloadMb(), lessThanOrEqualTo(3.1));
      expect(File('${downloadDir.path}/old').existsSync(), isFalse);
    });

    test('never deletes the song that is playing', () async {
      final playing = song('playing');
      final playingFile = File(playing.downloadPath!);
      playingFile.createSync(recursive: true);
      playingFile.writeAsBytesSync(List.filled(2 * 1024 * 1024, 0));
      playing.downloadExist = true;
      writeDownloadFile('other-old', 2);
      writeDownloadFile('other-new', 2);

      final now = DateTime.now();
      playingFile.setLastModifiedSync(now.subtract(const Duration(days: 5)));
      File(
        '${downloadDir.path}/other-old',
      ).setLastModifiedSync(now.subtract(const Duration(days: 3)));
      File(
        '${downloadDir.path}/other-new',
      ).setLastModifiedSync(now.subtract(const Duration(days: 1)));

      library.id2Song['playing'] = playing;

      offlineMusicLimitMbNotifier.value = 3;
      await library.enforceDownloadLimit(keepSongId: 'playing');

      expect(
        playingFile.existsSync(),
        isTrue,
        reason: 'the playing song must keep its offline file',
      );
      expect(downloadMb(), lessThanOrEqualTo(3.1));
    });

    test('leaves offline music that already fits alone', () async {
      writeDownloadFile('a', 1);
      offlineMusicLimitMbNotifier.value = 100;

      await library.enforceDownloadLimit();

      expect(File('${downloadDir.path}/a').existsSync(), isTrue);
    });

    test(
      'does not include temporary cache in the offline music limit',
      () async {
        writeDownloadFile('offline', 2);
        final cacheFile = File('${getCachesPath(sourceType)}/temporary');
        cacheFile.createSync(recursive: true);
        cacheFile.writeAsBytesSync(List.filled(10 * 1024 * 1024, 0));
        cacheSizeNotifier.value = 10;
        offlineMusicLimitMbNotifier.value = 1;

        await library.enforceDownloadLimit();

        expect(File('${downloadDir.path}/offline').existsSync(), isFalse);
        expect(cacheFile.existsSync(), isTrue);
      },
    );

    test('is harmless when the downloads directory does not exist', () async {
      downloadDir.deleteSync(recursive: true);
      offlineMusicLimitMbNotifier.value = 1;

      await library.enforceDownloadLimit();
    });
  });
}
