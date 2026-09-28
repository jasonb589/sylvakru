import 'package:flutter/foundation.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/download_cancellation.dart';

/// Downloads that run at the same time.
///
/// Two connections keep a queue moving without turning a home server into a
/// bottleneck; the client uses the same figure as its picture prefetcher.
const int downloadConcurrency = 2;

/// How often a failed download is tried again before it is reported.
const int downloadRetries = 2;

/// Progress per song id: 0..1, or -1 while the size is unknown.
final ValueNotifier<Map<String, double>> downloadProgressNotifier =
    ValueNotifier({});

/// Songs the queue gave up on, with what went wrong, for the centre to show.
final ValueNotifier<Map<String, String>> downloadErrorsNotifier = ValueNotifier(
  {},
);

/// Ids waiting to start, in the order they were asked for.
final ValueNotifier<List<String>> downloadQueueNotifier = ValueNotifier([]);

/// Ids the queue has running right now.
final ValueNotifier<Set<String>> downloadRunningNotifier = ValueNotifier({});

/// True while the listener has paused the queue.
final ValueNotifier<bool> downloadPausedNotifier = ValueNotifier(false);

/// The download queue: what is running, what is waiting, what failed.
///
/// The library can already fetch one song; what was missing was somewhere that
/// knows about the others — how many run at once, which one is next, and how a
/// cancel or a retry reaches a transfer that is already in flight.
class DownloadQueue {
  /// Lets a caller hand in the transfer itself. Production leaves it null and
  /// the library picks the right client for the source; a test can then watch
  /// the queue without a server.
  DownloadQueue({this.downloader});

  final SongDownloader? downloader;

  final Map<String, DownloadCancellation> _cancellations = {};
  final Map<String, int> _attempts = {};
  bool _pumping = false;

  /// Queues songs for download and starts what it can. Songs already queued,
  /// running or downloaded are ignored, so the caller can pass a whole album.
  void add(Iterable<MyAudioMetadata> songs) {
    final waiting = [...downloadQueueNotifier.value];
    for (final song in songs) {
      if (song.downloadExist ||
          waiting.contains(song.id) ||
          downloadRunningNotifier.value.contains(song.id)) {
        continue;
      }
      waiting.add(song.id);
      _attempts.remove(song.id);
      downloadErrorsNotifier.value = {...downloadErrorsNotifier.value}
        ..remove(song.id);
    }
    downloadQueueNotifier.value = waiting;
    _pump();
  }

  /// Stops a running download, or drops a waiting one from the queue.
  void cancel(String id) {
    if (downloadQueueNotifier.value.contains(id)) {
      downloadQueueNotifier.value = downloadQueueNotifier.value
          .where((queued) => queued != id)
          .toList();
    }
    _cancellations[id]?.cancel();
    _clearProgress(id);
  }

  /// Puts a finished-looking item back on the queue: a failure the listener
  /// wants to retry, or something they cancelled by mistake.
  void retry(MyAudioMetadata song) {
    _attempts.remove(song.id);
    downloadErrorsNotifier.value = {...downloadErrorsNotifier.value}
      ..remove(song.id);
    add([song]);
  }

  void setPaused(bool paused) {
    downloadPausedNotifier.value = paused;
    if (!paused) {
      _pump();
    }
  }

  /// Ids that are waiting or running: what the centre lists as "downloading".
  Set<String> get activeIds => {
    ...downloadQueueNotifier.value,
    ...downloadRunningNotifier.value,
  };

  void _pump() {
    if (_pumping) {
      return;
    }
    _pumping = true;
    try {
      while (!downloadPausedNotifier.value &&
          downloadRunningNotifier.value.length < downloadConcurrency) {
        final waiting = [...downloadQueueNotifier.value];
        if (waiting.isEmpty) {
          break;
        }
        final id = waiting.removeAt(0);
        downloadQueueNotifier.value = waiting;

        final song = library.id2Song[id];
        if (song == null || song.downloadExist) {
          continue;
        }
        downloadRunningNotifier.value = {...downloadRunningNotifier.value, id};
        _run(song);
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _run(MyAudioMetadata song) async {
    final cancellation = DownloadCancellation();
    _cancellations[song.id] = cancellation;
    _setProgress(song.id, -1);

    try {
      final success = await library.downloadForOffline(
        song,
        downloader: downloader,
        onProgress: (received, total) =>
            _setProgress(song.id, total > 0 ? received / total : -1),
        cancellation: cancellation,
      );

      if (!success && !cancellation.isCancelled) {
        final attempts = (_attempts[song.id] ?? 0) + 1;
        _attempts[song.id] = attempts;
        if (attempts <= downloadRetries) {
          // Straight back to the end of the queue: a server hiccup should not
          // need the listener to notice it.
          downloadQueueNotifier.value = [
            ...downloadQueueNotifier.value,
            song.id,
          ];
        } else {
          downloadErrorsNotifier.value = {
            ...downloadErrorsNotifier.value,
            song.id: 'download failed',
          };
        }
      } else if (success) {
        _attempts.remove(song.id);
      }
    } finally {
      _cancellations.remove(song.id);
      _clearProgress(song.id);
      final running = {...downloadRunningNotifier.value}..remove(song.id);
      downloadRunningNotifier.value = running;
      _pump();
    }
  }

  void _setProgress(String id, double value) {
    downloadProgressNotifier.value = {
      ...downloadProgressNotifier.value,
      id: value,
    };
  }

  void _clearProgress(String id) {
    final progress = {...downloadProgressNotifier.value}..remove(id);
    downloadProgressNotifier.value = progress;
  }
}

final downloadQueue = DownloadQueue();
