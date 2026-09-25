import 'dart:io';
import 'dart:async';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/utils/path.dart';

import 'package:sylvakru/base/services/logger.dart';

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
    downloadingSongIdsNotifier.value = {};
    library.id2Song.clear();
    final cacheDir = Directory(getCachesPath(sourceType));
    if (cacheDir.existsSync()) {
      cacheDir.deleteSync(recursive: true);
    }
  });

  test('downloads an offline copy and reports it in the library', () async {
    final song = _song('downloadable');
    library.id2Song[song.id] = song;

    final result = await library.downloadForOffline(
      song,
      downloader: (song) async {
        await File(song.cachePath!).writeAsString('audio');
        return true;
      },
    );

    expect(result, isTrue);
    expect(song.cacheExist, isTrue);
    expect(File(song.cachePath!).readAsStringSync(), 'audio');
    expect(library.offlineSongs, contains(song));
    expect(downloadingSongIdsNotifier.value, isEmpty);
  });

  test('stream sources can download a song that has no remote path', () async {
    final song = MyAudioMetadata(AudioMetadata(title: 'stream'), id: 'stream');
    library.id2Song[song.id] = song;

    expect(
      await library.downloadForOffline(
        song,
        downloader: (song) async {
          await File(song.cachePath!).writeAsString('audio');
          return true;
        },
      ),
      isTrue,
    );
  });

  test('cache eviction preserves every queued cached song', () async {
    final playing = _song('playing');
    final queued = _song('queued');
    final disposable = _song('disposable');
    for (final song in [playing, queued, disposable]) {
      library.id2Song[song.id] = song;
    }
    for (final song in [playing, queued, disposable]) {
      final file = File(song.cachePath!)..createSync(recursive: true);
      file.writeAsBytesSync(List.filled(2 * 1024 * 1024, 0));
      song.cacheExist = true;
    }
    for (final id in ['playing', 'queued', 'disposable']) {
      File(library.id2Song[id]!.cachePath!).setLastModifiedSync(
        DateTime.now().subtract(
          Duration(days: 4 - ['playing', 'queued', 'disposable'].indexOf(id)),
        ),
      );
    }
    cacheLimitMbNotifier.value = 3;

    await library.enforceCacheLimit(
      keepSongIds: {'playing', 'queued', 'disposable'},
    );

    expect(File(playing.cachePath!).existsSync(), isTrue);
    expect(File(queued.cachePath!).existsSync(), isTrue);
    expect(File(disposable.cachePath!).existsSync(), isTrue);
    expect(disposable.cacheExist, isTrue);
  });

  test('evicts the oldest unqueued offline copy first', () async {
    final playing = _song('playing');
    final queued = _song('queued');
    final old = _song('old');
    for (final song in [playing, queued, old]) {
      library.id2Song[song.id] = song;
      final file = File(song.cachePath!)..createSync(recursive: true);
      file.writeAsBytesSync(List.filled(2 * 1024 * 1024, 0));
      song.cacheExist = true;
    }
    final now = DateTime.now();
    File(
      old.cachePath!,
    ).setLastModifiedSync(now.subtract(const Duration(days: 3)));
    File(
      playing.cachePath!,
    ).setLastModifiedSync(now.subtract(const Duration(days: 2)));
    File(
      queued.cachePath!,
    ).setLastModifiedSync(now.subtract(const Duration(days: 1)));
    cacheLimitMbNotifier.value = 4;

    await library.enforceCacheLimit(keepSongIds: {'playing', 'queued'});

    expect(File(playing.cachePath!).existsSync(), isTrue);
    expect(File(queued.cachePath!).existsSync(), isTrue);
    expect(File(old.cachePath!).existsSync(), isFalse);
    expect(old.cacheExist, isFalse);
  });

  test('failed downloads remove partial files and allow retry', () async {
    final song = _song('failed');
    library.id2Song[song.id] = song;

    final result = await library.downloadForOffline(
      song,
      downloader: (song) async {
        await File(song.cachePath!).writeAsString('partial');
        return false;
      },
    );

    expect(result, isFalse);
    expect(song.cacheExist, isFalse);
    expect(File(song.cachePath!).existsSync(), isFalse);
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
        await File(song.cachePath!).writeAsString('audio');
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
          await File(song.cachePath!).writeAsString('audio');
          return true;
        },
      );

      expect(
        await library.removeOfflineCopy(song, currentlyPlaying: true),
        isFalse,
      );
      expect(song.cacheExist, isTrue);
      expect(
        await library.removeOfflineCopy(song, currentlyQueued: true),
        isFalse,
      );
      expect(song.cacheExist, isTrue);
      expect(File(song.cachePath!).existsSync(), isTrue);
      expect(await library.removeOfflineCopy(song), isTrue);

      expect(song.cacheExist, isFalse);
      expect(File(song.cachePath!).existsSync(), isFalse);
    },
  );

  test('local sources do not expose a downloadable cache', () async {
    sourceType = SourceType.local;
    isStreamSource = false;
    isNotStreamSource = true;
    final song = _song('local');

    expect(await library.downloadForOffline(song), isFalse);
    expect(song.cachePath, isNull);
  });
}
