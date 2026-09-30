import 'package:flutter/services.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/data/playlist.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/services/my_window_listener.dart';
import 'package:sylvakru/base/utils/dynamic_lyrics_page_route.dart';
import 'package:sylvakru/base/utils/shortcuts.dart';
import 'package:sylvakru/base/widgets/shortcuts_help.dart';
import 'package:sylvakru/layer/lyrics_page_layer.dart';
import 'package:window_manager/window_manager.dart';

bool isTyping = false;

bool shiftIsPressed = false;
bool ctrlIsPressed = false;

/// The volume the mute shortcut has to put back, kept from the moment it was
/// muted - the speaker button in the player keeps its own copy for the same
/// reason.
double? _volumeBeforeMute;

void keyboardInit() {
  HardwareKeyboard.instance.addHandler((event) {
    if (event is KeyDownEvent) {
      // The shortcuts panel is waiting for a key of its own: nothing may happen
      // meanwhile, or rebinding to Ctrl+→ would also skip a song.
      if (isCapturingShortcut) {
        return false;
      }
      switch (event.logicalKey) {
        case LogicalKeyboardKey.shiftLeft:
        case LogicalKeyboardKey.shiftRight:
          shiftIsPressed = true;
          break;
        case LogicalKeyboardKey.controlLeft:
        case LogicalKeyboardKey.controlRight:
          ctrlIsPressed = true;
          break;
        case LogicalKeyboardKey.escape:
          if (displayLyricsPage && isFullScreenNotifier.value) {
            windowManager.setFullScreen(false);
            isFullScreenNotifier.value = false;
          }
          break;
        case LogicalKeyboardKey.f11:
          if (displayLyricsPage && !isMaximizedNotifier.value) {
            windowManager.setFullScreen(true);
            isFullScreenNotifier.value = true;
          }
          break;
        default:
          // Everything else is looked up in the shared table, so which key does
          // what can be read - and tested - without a window.
          return runShortcut(
            shortcutActionFor(
              key: event.logicalKey,
              control: ctrlIsPressed,
              shift: shiftIsPressed,
              typing: isTyping,
              // The table the user has set up, defaults with their changes on
              // top. Read here rather than cached: a rebind has to take effect
              // on the very next key press.
              bindings: effectiveBindings(shortcutBindingsNotifier.value),
            ),
          );
      }
    } else if (event is KeyUpEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.shiftLeft:
        case LogicalKeyboardKey.shiftRight:
          shiftIsPressed = false;
          break;
        case LogicalKeyboardKey.controlLeft:
        case LogicalKeyboardKey.controlRight:
          ctrlIsPressed = false;
          break;
      }
    }
    return false;
  });
}

/// Does what [action] asks for. True means the key was used up and must not
/// reach whatever has focus as well.
///
/// Space is the exception, as it always was: it answers playback *and* still
/// reaches the focused control, so nothing that used to work stops working.
bool runShortcut(ShortcutAction? action) {
  switch (action) {
    case null:
      return false;

    case ShortcutAction.playPause:
      if (playQueue.isEmpty) {
        return false;
      }
      audioHandler.togglePlay();
      return false;

    case ShortcutAction.next:
    case ShortcutAction.previous:
      if (playQueue.isEmpty) {
        return false;
      }
      if (action == ShortcutAction.next) {
        audioHandler.skipToNext();
      } else {
        audioHandler.skipToPrevious();
      }
      return true;

    case ShortcutAction.seekForward:
    case ShortcutAction.seekBackward:
      if (playQueue.isEmpty) {
        return false;
      }
      final step = action == ShortcutAction.seekForward
          ? shortcutSeekStep
          : -shortcutSeekStep;
      final target = audioHandler.getPosition() + step;
      audioHandler.seek(target.isNegative ? Duration.zero : target);
      return true;

    case ShortcutAction.volumeUp:
    case ShortcutAction.volumeDown:
      final step = action == ShortcutAction.volumeUp
          ? shortcutVolumeStep
          : -shortcutVolumeStep;
      setPlayerVolume(shortcutVolume(volumeNotifier.value, step));
      return true;

    case ShortcutAction.mute:
      final current = volumeNotifier.value;
      if (current > 0) {
        _volumeBeforeMute = current;
        setPlayerVolume(0);
      } else {
        // Muted from here or from the speaker button: either way, back to what
        // it was, or to the volume the app starts at.
        setPlayerVolume(_volumeBeforeMute ?? appDefaultVolume);
      }
      return true;

    case ShortcutAction.favorite:
      final song = currentSongNotifier.value;
      if (song == null) {
        return false;
      }
      toggleFavoriteState(song);
      return true;

    case ShortcutAction.lyricsPage:
      if (displayLyricsPage) {
        globalNavigatorKey.currentState?.maybePop();
        return true;
      }
      if (playQueue.isEmpty) {
        return false;
      }
      globalNavigatorKey.currentState?.push(
        DynamicLyricsPageRoute(pageBuilder: (_, _, _) => LyricsPageLayer()),
      );
      return true;

    case ShortcutAction.help:
      final context = globalNavigatorKey.currentContext;
      if (context != null) {
        showShortcutsHelp(context);
      }
      return true;
  }
}

/// The notifier is what the sliders show, so it moves with the player's volume.
void setPlayerVolume(double value) {
  volumeNotifier.value = value;
  audioHandler.setVolume(value);
}
