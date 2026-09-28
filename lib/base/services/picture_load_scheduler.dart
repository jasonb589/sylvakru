import 'dart:async';

import 'package:sylvakru/base/services/picture_service.dart';

PictureLoadScheduler pictureLoadScheduler = PictureLoadScheduler();

class PictureLoadScheduler {
  final int maxConcurrent = 6;

  int _running = 0;
  final _queue = <_Task>[];

  final Map<String, Completer<void>> _pictureCompleterMap = {};
  final Set<String> _scheduled = {};
  final Set<int> _needRun = {};

  Future<void> load(String id, Future<void> Function() loader, int? widgetId) {
    final completer = _pictureCompleterMap.putIfAbsent(
      id,
      () => Completer<void>(),
    );

    if (widgetId != null) {
      _needRun.add(widgetId);
    }
    _queue.add(
      _Task(id, widgetId, () async {
        if (!_scheduled.contains(id)) {
          _scheduled.add(id);

          await loader();
          completer.complete();
        }
        _running--;
        _schedule();
      }),
    );

    _schedule();

    return completer.future;
  }

  void _schedule() {
    while (_running < maxConcurrent && _queue.isNotEmpty) {
      final task = _queue.removeAt(0);
      if (task.widgetId == null || _needRun.contains(task.widgetId!)) {
        _running++;
        task.run();
      } else {
        // The widget that asked for this is gone, so the fetch would be for
        // nobody. Whoever joined the same future still has to be let go.
        _releaseIfNothingQueued(task.id);
      }
    }
  }

  /// Completes the shared future for [id] once no other task still wants it.
  ///
  /// Dropping a cancelled task used to leave its completer pending for good,
  /// and the map kept handing that dead future to every later caller: a page
  /// waiting for a cover colour would wait forever.
  void _releaseIfNothingQueued(String id) {
    if (_queue.any((task) => task.id == id)) {
      return;
    }
    _scheduled.remove(id);
    final completer = _pictureCompleterMap.remove(id);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void cancel(int widgetId) {
    _needRun.remove(widgetId);
  }

  void resetPicture(MyPicture picture) {
    _scheduled.remove(picture.id);
    _pictureCompleterMap.remove(picture.id);
  }

  void clear() {
    _queue.clear();
    _needRun.clear();
    _scheduled.clear();
    _pictureCompleterMap.clear();
    _running = 0;
  }
}

class _Task {
  final String id;
  final int? widgetId;
  final Future<void> Function() run;

  _Task(this.id, this.widgetId, this.run);
}
