import 'dart:async';
import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/utils/path.dart';

MyAudioMetadata _song(String id) => MyAudioMetadata(
  AudioMetadata(title: id),
  id: id,
  path: '/music/$id.flac',
);

void main() {
  late Directory support;

  setUpAll(() async {
    support = Directory.systemTemp.createTempSync('sylvakru_offline');
    appSupportDir = support;
    await logger.init();
  });

  setUp(() {
    sourceType = SourceType.navidrome;
    isStreamSource = true;
    isNotStreamSource = false;
    cacheSizeNotifier.value = 0;
    downloadSizeNotifier.value = 0;
    downloadingSongIdsNotifier.value = {};
    offlineMusicLimitMbNotifier.value = 0;
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
  });

  test('downloads an offline copy into downloads and reports it', () async {
    final song = _song('downloadable');
    library.id2Song[song.id] = song;

    final result = await library.downloadForOffline(
      song,
      downloader: (song) async {
        await File(song.downloadPath!).writeAsString('audio');
        return true;
      },
    );

    expect(result, isTrue);
    expect(song.downloadExist, isTrue);
    expect(File(song.downloadPath!).readAsStringSync(), 'audio');
    expect(File(song.cachePath!).existsSync(), isFalse);
    expect(library.offlineMusicSongs, contains(song));
    expect(downloadSizeNotifier.value, greaterThan(0));
    expect(downloadingSongIdsNotifier.value, isEmpty);
  });

  test('stream sources can download a song that has no remote path', () async {
    final song = MyAudioMetadata(AudioMetadata(title: 'stream'), id: 'stream');
    library.id2Song[song.id] = song;

    expect(
      await library.downloadForOffline(
        song,
        downloader: (song) async {
          await File(song.downloadPath!).writeAsString('audio');
          return true;
        },
      ),
      isTrue,
    );
  });

  test(
    'migrates known legacy copies and leaves unknown cache files alone',
    () async {
      final known = _song('known-legacy');
      library.id2Song[known.id] = known;
      final oldFile = File(known.cachePath!)..createSync(recursive: true);
      oldFile.writeAsStringSync('legacy audio');
      final unknown = File('${getCachesPath(sourceType)}/temporary-file')
        ..createSync(recursive: true);
      unknown.writeAsStringSync('temporary audio');

      await library.migrateLegacyOfflineCopies();

      expect(File(known.downloadPath!).readAsStringSync(), 'legacy audio');
      expect(File(known.cachePath!).existsSync(), isFalse);
      expect(known.cacheExist, isFalse);
      expect(known.downloadExist, isTrue);
      expect(unknown.existsSync(), isTrue);
      expect(downloadSizeNotifier.value, greaterThan(0));

      await library.migrateLegacyOfflineCopies();
      expect(unknown.existsSync(), isTrue);
      expect(File(known.downloadPath!).existsSync(), isTrue);
    },
  );

  test('keeps queued copies while the limit can still be met', () async {
    final playing = _song('playing');
    final queued = _song('queued');
    final disposable = _song('disposable');
    for (final song in [playing, queued, disposable]) {
      library.id2Song[song.id] = song;
    }
    for (final song in [playing, queued, disposable]) {
      final file = File(song.downloadPath!)..createSync(recursive: true);
      file.writeAsBytesSync(List.filled(2 * 1024 * 1024, 0));
      song.downloadExist = true;
    }
    for (final id in ['playing', 'queued', 'disposable']) {
      File(library.id2Song[id]!.downloadPath!).setLastModifiedSync(
        DateTime.now().subtract(
          Duration(days: 4 - ['playing', 'queued', 'disposable'].indexOf(id)),
        ),
      );
    }
    offlineMusicLimitMbNotifier.value = 5;

    await library.enforceDownloadLimit(keepSongIds: {'playing', 'queued'});

    expect(File(playing.downloadPath!).existsSync(), isTrue);
    expect(File(queued.downloadPath!).existsSync(), isTrue);
    expect(File(disposable.downloadPath!).existsSync(), isFalse);
    expect(disposable.downloadExist, isFalse);
  });

  test('evicts queued copies when the queue alone exceeds the limit', () async {
    final playing = _song('playing');
    final queued = _song('queued');
    final olderQueued = _song('olderQueued');
    for (final song in [playing, queued, olderQueued]) {
      library.id2Song[song.id] = song;
    }
    for (final song in [playing, queued, olderQueued]) {
      final file = File(song.downloadPath!)..createSync(recursive: true);
      file.writeAsBytesSync(List.filled(2 * 1024 * 1024, 0));
      song.downloadExist = true;
    }
    File(
      playing.downloadPath!,
    ).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 1)));
    File(
      queued.downloadPath!,
    ).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));
    File(
      olderQueued.downloadPath!,
    ).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 3)));
    offlineMusicLimitMbNotifier.value = 3;

    await library.enforceDownloadLimit(
      keepSongId: 'playing',
      keepSongIds: {'playing', 'queued', 'olderQueued'},
    );

    expect(File(playing.downloadPath!).existsSync(), isTrue);
    expect(playing.downloadExist, isTrue);
    expect(File(olderQueued.downloadPath!).existsSync(), isFalse);
    expect(File(queued.downloadPath!).existsSync(), isFalse);
  });

  test('evicts the oldest unqueued offline copy first', () async {
    final playing = _song('playing');
    final queued = _song('queued');
    final old = _song('old');
    for (final song in [playing, queued, old]) {
      library.id2Song[song.id] = song;
      final file = File(song.downloadPath!)..createSync(recursive: true);
      file.writeAsBytesSync(List.filled(2 * 1024 * 1024, 0));
      song.downloadExist = true;
    }
    final now = DateTime.now();
    File(
      old.downloadPath!,
    ).setLastModifiedSync(now.subtract(const Duration(days: 3)));
    File(
      playing.downloadPath!,
    ).setLastModifiedSync(now.subtract(const Duration(days: 2)));
    File(
      queued.downloadPath!,
    ).setLastModifiedSync(now.subtract(const Duration(days: 1)));
    offlineMusicLimitMbNotifier.value = 4;

    await library.enforceDownloadLimit(keepSongIds: {'playing', 'queued'});

    expect(File(playing.downloadPath!).existsSync(), isTrue);
    expect(File(queued.downloadPath!).existsSync(), isTrue);
    expect(File(old.downloadPath!).existsSync(), isFalse);
    expect(old.downloadExist, isFalse);
  });

  test('failed downloads remove partial files and allow retry', () async {
    final song = _song('failed');
    library.id2Song[song.id] = song;

    final result = await library.downloadForOffline(
      song,
      downloader: (song) async {
        await File(song.downloadPath!).writeAsString('partial');
        return false;
      },
    );

    expect(result, isFalse);
    expect(song.downloadExist, isFalse);
    expect(File(song.downloadPath!).existsSync(), isFalse);
    expect(downloadingSongIdsNotifier.value, isEmpty);
  });

  test('rejects duplicate downloads while one is in progress', () async {
    final song = _song('duplicate');
    library.id2Song[song.id] = song;
    final started = Completer<void>();
    final release = Completer<void>();

    final first = library.downloadForOffline(
      song,
      downloader: (song) async {
        started.complete();
        await release.future;
        await File(song.downloadPath!).writeAsString('audio');
        return true;
      },
    );
    await started.future;

    expect(
      await library.downloadForOffline(song, downloader: (_) async => true),
      isFalse,
    );
    release.complete();
    expect(await first, isTrue);
  });

  test(
    'removes an offline copy but protects a currently playing song',
    () async {
      final song = _song('remove');
      library.id2Song[song.id] = song;
      await library.downloadForOffline(
        song,
        downloader: (song) async {
          await File(song.downloadPath!).writeAsString('audio');
          return true;
        },
      );

      expect(
        await library.removeOfflineCopy(song, currentlyPlaying: true),
        isFalse,
      );
      expect(song.downloadExist, isTrue);
      expect(
        await library.removeOfflineCopy(song, currentlyQueued: true),
        isFalse,
      );
      expect(song.downloadExist, isTrue);
      expect(File(song.downloadPath!).existsSync(), isTrue);
      expect(await library.removeOfflineCopy(song), isTrue);

      expect(song.downloadExist, isFalse);
      expect(File(song.downloadPath!).existsSync(), isFalse);
    },
  );

  test('local sources do not expose a downloadable copy', () async {
    sourceType = SourceType.local;
    isStreamSource = false;
    isNotStreamSource = true;
    final song = _song('local');

    expect(await library.downloadForOffline(song), isFalse);
    expect(song.downloadPath, isNull);
  });
}
