import 'dart:io';

import 'package:sylvakru/base/services/logger.dart';

/// The command that shows [path] in the platform's file manager, or null when
/// there is no way to do it.
///
/// Kept pure so a test can read the arguments without opening anything. The
/// Windows switch is a single argument (`/select,C:\...`): passing it quoted
/// makes Explorer open a folder with that name instead of selecting the file.
List<String>? revealCommand(
  String path, {
  bool isWindows = false,
  bool isMacOS = false,
}) {
  if (isWindows) {
    return ['explorer', '/select,${File(path).absolute.path}'];
  }
  if (isMacOS) {
    return ['open', '-R', path];
  }
  final parent = File(path).parent.path;
  if (parent.isEmpty) {
    return null;
  }
  return ['xdg-open', parent];
}

/// Shows a downloaded file in Explorer, Finder or the desktop's file manager.
///
/// Best effort, and no exit code is trusted: Explorer answers with a non-zero
/// code even when it worked, so "the command started" is as much as this can
/// honestly claim. Nothing about the download depends on it.
Future<bool> revealInFileManager(String path) async {
  final command = revealCommand(
    path,
    isWindows: Platform.isWindows,
    isMacOS: Platform.isMacOS,
  );
  if (command == null) {
    return false;
  }
  try {
    await Process.run(command.first, command.sublist(1));
    return true;
  } catch (error) {
    logger.output('Failed to show $path in the file manager: $error');
    return false;
  }
}
