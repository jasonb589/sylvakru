import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/utils/path.dart';

/// Until 4.15.1 starting the app moved every cache file whose name belonged to
/// a loaded song into the downloads folder and called it a download, so simply
/// listening to a song filled the download centre while the temporary cache
/// read 0 MB. The one-time pass has to put those files back, keep real
/// downloads, and never run a second time.
void main() {
  late Directory support;

  setUpAll(() async {
    support = Directory.systemTemp.createTempSync('sylvakru_cache_split');
    appSupportDir = support;
    await logger.init();
  });

  setUp(() async {
    sourceType = SourceType.navidrome;
    isStreamSource = true;
    isNotStreamSource = false;
    library.id2Song.clear();
    await setting.load();
    downloadSplitRepaired = false;

    for (final path in [
      getCachesPath(sourceType),
      getDownloadsPath(sourceType),
    ]) {
      final directory = Directory(path);
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
  });

  MyAudioMetadata songWithId(String id) {
    final song = MyAudioMetadata(
      AudioMetadata(title: id),
      id: id,
      path: '/music/$id.flac',
    );
    library.id2Song[id] = song;
    return song;
  }

  MyAudioMetadata playedInDownloads(String id) {
    final song = songWithId(id);
    File(song.downloadPath!).createSync(recursive: true);
    song.downloadExist = true;
    return song;
  }

  test('a song that was only played moves back to the cache', () async {
    final song = playedInDownloads('played');

    await library.repairDownloadCacheMixUp();

    expect(File(song.downloadPath!).existsSync(), isFalse);
    expect(File(song.cachePath!).existsSync(), isTrue);
    expect(song.cacheExist, isTrue);
    expect(song.downloadExist, isFalse);
    expect(library.offlineMusicSongs, isEmpty);
  });

  test('the pass runs once and leaves later downloads alone', () async {
    await library.repairDownloadCacheMixUp();
    expect(downloadSplitRepaired, isTrue);
    expect(
      File('${appSupportDir.path}/setting.json').readAsStringSync(),
      contains('"downloadSplitRepaired":true'),
    );

    final song = playedInDownloads('downloaded');
    await library.repairDownloadCacheMixUp();

    expect(File(song.downloadPath!).existsSync(), isTrue);
    expect(File(song.cachePath!).existsSync(), isFalse);
    expect(song.downloadExist, isTrue);
    expect(library.offlineMusicSongs.map((item) => item.id), ['downloaded']);
  });

  test('a song with both copies keeps its download', () async {
    final song = playedInDownloads('both');
    File(song.cachePath!).createSync(recursive: true);

    await library.repairDownloadCacheMixUp();

    expect(File(song.downloadPath!).existsSync(), isTrue);
    expect(song.downloadExist, isTrue);
    expect(library.offlineMusicSongs.map((item) => item.id), ['both']);
  });
}
