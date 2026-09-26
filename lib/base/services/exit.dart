import 'dart:io';

import 'package:sylvakru/landscape_view/desktop_lyrics.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/extensions/window_controller_extension.dart';
import 'package:sylvakru/base/services/logger.dart';

import 'package:sylvakru/base/services/single_instance.dart';
import 'package:window_manager/window_manager.dart';

bool _exited = false;

Future<void> exitApp() async {
  if (_exited) {
    return;
  }
  // Set before the first await: quitting now takes a moment while the audio
  // output drains, and a second close during that window must not start a
  // second teardown.
  _exited = true;

  // Stop the engine before anything else is torn down. Closing the window, or
  // calling exit, while audio is still streaming destroys the output mid
  // buffer, which is audible as a click on the way out.
  try {
    await audioHandler.shutdownAudio();
  } catch (error) {
    // A failure here must never stop the app from quitting.
    logger.output('Failed to shut audio down cleanly: $error');
  }

  await lyricsWindowController?.close();
  await SingleInstance.end();
  // only this allows quick exit on Windows
  if (Platform.isWindows) {
    await windowManager.setPreventClose(false);
    windowManager.close();
    return;
  }

  exit(0);
}
