import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/utils/disk_space.dart';
import 'package:sylvakru/base/utils/path.dart';

/// The channel the Windows runner answers on: Dart cannot ask a volume how
/// much room is left, so the question goes to the platform.
const diskSpaceChannel = MethodChannel('sylvakru/disk_space');

/// Free bytes on the download volume, or null while unknown.
///
/// Null is a normal state, not an error: on a platform that cannot answer the
/// reminder simply stays quiet instead of guessing.
final ValueNotifier<int?> diskFreeSpaceBytesNotifier = ValueNotifier<int?>(
  null,
);

/// How long an answer is reused. The download center asks on every rebuild,
/// and a figure a few seconds old is the same figure.
const diskSpaceCacheDuration = Duration(seconds: 10);

String? _cachedPath;
DateTime? _cachedAt;

/// The folder whose volume matters: the one downloads are written to.
String diskSpaceTargetPath() {
  final root = downloadRootDir;
  return root == null || root.isEmpty ? appSupportDir.path : root;
}

/// [path], or its closest parent that exists.
///
/// `df` refuses a path that is not there yet, and a fresh install has no
/// downloads folder to point at.
String existingAncestor(String path) {
  var current = path;
  for (var depth = 0; depth < 12; depth++) {
    if (Directory(current).existsSync()) {
      return current;
    }
    final parent = File(current).parent.path;
    if (parent == current || parent.isEmpty) {
      break;
    }
    current = parent;
  }
  return Directory.current.path;
}

/// Asks the platform for the free bytes on the volume [path] lives on.
///
/// Windows answers through the runner; the other desktops are asked through
/// `df`, which keeps the native side to the platform that ships. Anything that
/// goes wrong is an unknown figure rather than an exception.
Future<int?> readFreeSpaceBytes(String path) async {
  try {
    if (Platform.isWindows) {
      return await diskSpaceChannel.invokeMethod<int>('freeSpace', {
        'path': path,
      });
    }
    final result = await Process.run('df', [
      '-P',
      '-k',
      existingAncestor(path),
    ]);
    if (result.exitCode != 0) {
      return null;
    }
    return parseDfFreeBytes(result.stdout.toString());
  } catch (_) {
    return null;
  }
}

/// Reads the answer for the download volume, reusing the cached one unless
/// [force] asks for a fresh figure.
Future<int?> refreshDiskFreeSpace({bool force = false}) async {
  final target = diskSpaceTargetPath();
  final now = DateTime.now();
  final cachedAt = _cachedAt;
  if (!force &&
      _cachedPath == target &&
      cachedAt != null &&
      now.difference(cachedAt) < diskSpaceCacheDuration) {
    return diskFreeSpaceBytesNotifier.value;
  }
  _cachedPath = target;
  _cachedAt = now;

  final bytes = await readFreeSpaceBytes(target);
  // A read that failed leaves the last known figure in place: it is closer to
  // the truth than an unknown, and the reminder keeps working across it.
  if (bytes != null) {
    diskFreeSpaceBytesNotifier.value = bytes;
  }
  return bytes;
}
