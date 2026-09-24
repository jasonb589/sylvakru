import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';

/// Version of the text-only desktop lyrics window layout.
///
/// Increment this when the window's content geometry changes enough that old
/// saved coordinates are no longer meaningful.
const int desktopLyricsLayoutVersion = 3;

/// Saved layout state of the desktop lyrics window.
///
/// The window runs in its own Flutter engine, so it cannot read the main
/// window's state. It keeps this small file of its own rather than going
/// through the shared setting.json, which would drag the whole settings
/// machinery into the second engine.
class DesktopLyricsSetting {
  /// Guards [save] until [load] has run, so a save that happens before the
  /// file was read cannot overwrite a previously stored position with defaults.
  bool loaded = false;
  File? _file;

  /// The settings file, created lazily so [load] can safely run more than once
  /// (a `late final` field would throw on the second call).
  File get file => _file ??= File('${appSupportDir.path}/desktop_lyrics.json');

  /// Last position the user dragged the window to, or null if never moved.
  final positionNotifier = ValueNotifier<Offset?>(null);

  Future<void> load() async {
    final file = this.file;
    if (!file.existsSync()) {
      file.createSync(recursive: true);
      file.writeAsStringSync('{}');
    }
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map;
      final savedLayout = (json['layout'] as num?)?.toInt() ?? 1;
      if (savedLayout != desktopLyricsLayoutVersion) {
        // The previous layout reserved a controls row above the lyric. Its
        // saved coordinates are not meaningful for the text-only window.
        positionNotifier.value = null;
        loaded = true;
        save();
        return;
      }
      final dx = (json['dx'] as num?)?.toDouble();
      final dy = (json['dy'] as num?)?.toDouble();
      if (dx != null && dy != null) {
        positionNotifier.value = Offset(dx, dy);
      }
    } catch (_) {
      // A corrupt file must not stop the lyrics window from opening; it simply
      // falls back to the default position.
    }
    loaded = true;
  }

  void save() {
    if (!loaded) {
      return;
    }
    final position = positionNotifier.value;
    try {
      file.writeAsStringSync(
        jsonEncode({
          'layout': desktopLyricsLayoutVersion,
          if (position != null) 'dx': position.dx,
          if (position != null) 'dy': position.dy,
        }),
      );
    } catch (_) {
      // Losing the saved position is not worth breaking playback over.
    }
  }
}

final desktopLyricsSetting = DesktopLyricsSetting();
