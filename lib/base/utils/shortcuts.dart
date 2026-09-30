import 'package:flutter/services.dart';

/// What a key press asks the player to do.
///
/// The mapping lives here, apart from the handler that runs it, so what each key
/// does can be read - and tested - without a player, a window or a keyboard.
enum ShortcutAction {
  playPause,
  next,
  previous,
  seekBackward,
  seekForward,
  volumeDown,
  volumeUp,
  mute,
  favorite,
  lyricsPage,
  help,
}

/// How far the seek shortcuts move the song.
const Duration shortcutSeekStep = Duration(seconds: 5);

/// How much of the volume the volume shortcuts add or take away, as a fraction.
const double shortcutVolumeStep = 0.05;

/// The volume the app starts at. Used when a mute has to be undone and nothing
/// remembers what the volume was before it.
const double appDefaultVolume = 0.3;

/// The keys behind each action, spelled the way the help panel prints them.
///
/// A test walks [ShortcutAction.values] and fails when one of them has no label,
/// so an action cannot be added without saying which key reaches it.
const Map<ShortcutAction, String> shortcutKeyLabels = {
  ShortcutAction.playPause: 'Space',
  ShortcutAction.next: 'Ctrl + →',
  ShortcutAction.previous: 'Ctrl + ←',
  ShortcutAction.seekBackward: 'Ctrl + Shift + ←',
  ShortcutAction.seekForward: 'Ctrl + Shift + →',
  ShortcutAction.volumeDown: 'Ctrl + ↓',
  ShortcutAction.volumeUp: 'Ctrl + ↑',
  ShortcutAction.mute: 'Ctrl + M',
  ShortcutAction.favorite: 'Ctrl + D',
  ShortcutAction.lyricsPage: 'Ctrl + L',
  ShortcutAction.help: 'F1',
};

/// The action [key] asks for, or null when the key is not one of ours.
///
/// [typing] must be true while a text field has the caret: a shortcut that
/// swallowed those keystrokes would make the field unusable. Keys carrying Alt
/// are left alone as well - those belong to menus and to the window.
///
/// Media keys are recognised on their own: keyboards that have them send
/// play/pause, next and previous without any modifier.
ShortcutAction? shortcutActionFor({
  required LogicalKeyboardKey key,
  bool control = false,
  bool shift = false,
  bool alt = false,
  bool typing = false,
}) {
  if (typing || alt) {
    return null;
  }

  switch (key) {
    case LogicalKeyboardKey.space:
      // Plain space only: Ctrl+Space and Shift+Space belong to the platform.
      return control || shift ? null : ShortcutAction.playPause;
    case LogicalKeyboardKey.mediaPlayPause:
    case LogicalKeyboardKey.mediaPlay:
      return ShortcutAction.playPause;
    case LogicalKeyboardKey.mediaTrackNext:
      return ShortcutAction.next;
    case LogicalKeyboardKey.mediaTrackPrevious:
      return ShortcutAction.previous;
    case LogicalKeyboardKey.f1:
      return ShortcutAction.help;
  }

  if (!control) {
    return null;
  }

  switch (key) {
    case LogicalKeyboardKey.arrowRight:
      return shift ? ShortcutAction.seekForward : ShortcutAction.next;
    case LogicalKeyboardKey.arrowLeft:
      return shift ? ShortcutAction.seekBackward : ShortcutAction.previous;
    case LogicalKeyboardKey.arrowUp:
      return ShortcutAction.volumeUp;
    case LogicalKeyboardKey.arrowDown:
      return ShortcutAction.volumeDown;
    case LogicalKeyboardKey.keyM:
      return ShortcutAction.mute;
    case LogicalKeyboardKey.keyD:
      return ShortcutAction.favorite;
    case LogicalKeyboardKey.keyL:
      return ShortcutAction.lyricsPage;
  }

  return null;
}

/// The volume [step]s away from [current], kept inside 0..1.
double shortcutVolume(double current, double step) =>
    (current + step).clamp(0.0, 1.0);
