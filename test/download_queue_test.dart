import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/download_queue.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/utils/path.dart';

/// The queue is what turns "download this album" into two transfers at a time,
/// a couple of retries and something the centre can show. It has to skip what
/// is already there, cap how much runs at once, and keep a failure visible.
void main() {
  late Directory support;

  setUpAll(() async {
    support = Directory.systemTemp.createTempSync('sylvakru_queue');
    appSupportDir = support;
    await logger.init();
  });

  setUp(() async {
    sourceType = SourceType.navidrome;
    isStreamSource = true;
    isNotStreamSource = false;
    library.id2Song.clear();
    await setting.load();
    downloadQueueNotifier.value = [];
    downloadRunningNotifier.value = {};
    downloadProgressNotifier.value = {};
    downloadErrorsNotifier.value = {};
    downloadPausedNotifier.value = false;

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

  MyAudioMetadata queueSong(String id) {
    final song = MyAudioMetadata(
      AudioMetadata(title: id),
      id: id,
      path: '/music/$id.flac',
    );
    library.id2Song[id] = song;
    return song;
  }

  /// Waits for the queue to go quiet: nothing waiting, nothing running.
  Future<void> settle() async {
    for (var i = 0; i < 500; i++) {
      if (downloadQueueNotifier.value.isEmpty &&
          downloadRunningNotifier.value.isEmpty) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 5));
    }
  }

  SongDownloader writing(String contents, {Duration? delay}) => (song) async {
    if (delay != null) {
      await Future.delayed(delay);
    }
    await File(song.downloadPath!).writeAsString(contents);
    return true;
  };

  test('runs two at a time and finishes the whole batch', () async {
    final songs = [
      for (final id in ['a', 'b', 'c']) queueSong(id),
    ];
    final queue = DownloadQueue(
      downloader: writing('audio', delay: const Duration(milliseconds: 20)),
    );

    queue.add(songs);

    expect(downloadRunningNotifier.value.length, downloadConcurrency);
    expect(
      downloadQueueNotifier.value.length,
      songs.length - downloadConcurrency,
    );

    await settle();

    expect(downloadRunningNotifier.value, isEmpty);
    expect(downloadQueueNotifier.value, isEmpty);
    expect(library.offlineMusicSongs.length, songs.length);
    for (final song in songs) {
      expect(File(song.downloadPath!).readAsStringSync(), 'audio');
    }
  });

  test('skips songs that are already downloaded', () async {
    final song = queueSong('here');
    File(song.downloadPath!).createSync(recursive: true);
    song.downloadExist = true;

    var transfers = 0;
    final queue = DownloadQueue(
      downloader: (song) async {
        transfers++;
        return true;
      },
    );

    queue.add([song]);

    expect(transfers, 0);
    expect(downloadQueueNotifier.value, isEmpty);
    expect(downloadRunningNotifier.value, isEmpty);
  });

  test('retries twice and then reports the failure', () async {
    final song = queueSong('broken');
    var attempts = 0;
    final queue = DownloadQueue(
      downloader: (song) async {
        attempts++;
        return false;
      },
    );

    queue.add([song]);
    await settle();

    expect(attempts, downloadRetries + 1);
    expect(downloadErrorsNotifier.value.keys, contains('broken'));
    expect(song.downloadExist, isFalse);
  });

  test('a paused queue waits, and cancelling drops just that song', () async {
    final songs = [
      for (final id in ['x', 'y', 'z']) queueSong(id),
    ];
    final queue = DownloadQueue(downloader: writing('audio'));

    queue.setPaused(true);
    queue.add(songs);

    expect(downloadRunningNotifier.value, isEmpty);
    expect(downloadQueueNotifier.value, ['x', 'y', 'z']);

    queue.cancel('y');
    expect(downloadQueueNotifier.value, ['x', 'z']);

    queue.setPaused(false);
    await settle();

    expect(File(library.id2Song['x']!.downloadPath!).existsSync(), isTrue);
    expect(File(library.id2Song['z']!.downloadPath!).existsSync(), isTrue);
    expect(File(library.id2Song['y']!.downloadPath!).existsSync(), isFalse);
    expect(downloadErrorsNotifier.value, isEmpty);
  });
}
