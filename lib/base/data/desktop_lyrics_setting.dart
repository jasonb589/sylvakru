import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';

/// Position and lock state of the desktop lyrics window.
///
/// That window runs in its own Flutter engine, so it cannot read the main
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

  /// Whether the window is pinned in place.
  ///
  /// Locked means dragging is disabled; the buttons stay clickable, and the
  /// window keeps receiving mouse input (locking never turns on click-through).
  final lockedNotifier = ValueNotifier(false);

  /// Last position the user dragged the window to, or null if never moved.
  ///
  /// A null position is what makes the window come back to its default spot
  /// above the taskbar; a stored one is restored as-is.
  final positionNotifier = ValueNotifier<Offset?>(null);

  Future<void> load() async {
    final file = this.file;
    if (!file.existsSync()) {
      file.createSync(recursive: true);
      file.writeAsStringSync('{}');
    }
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map;
      lockedNotifier.value = json['locked'] as bool? ?? false;
      final dx = (json['dx'] as num?)?.toDouble();
      final dy = (json['dy'] as num?)?.toDouble();
      if (dx != null && dy != null) {
        positionNotifier.value = Offset(dx, dy);
      }
    } catch (_) {
      // a corrupt file must not stop the lyrics window from opening; it simply
      // falls back to the defaults above
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
          'locked': lockedNotifier.value,
          if (position != null) 'dx': position.dx,
          if (position != null) 'dy': position.dy,
        }),
      );
    } catch (_) {
      // losing the saved position is not worth breaking playback over
    }
  }
}

final desktopLyricsSetting = DesktopLyricsSetting();
