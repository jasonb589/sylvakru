import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/utils/shortcuts.dart';
import 'package:sylvakru/base/widgets/shortcuts_help.dart';
import 'package:sylvakru/l10n/generated/app_localizations_en.dart';

/// What each key does, without a player or a window.
///
/// The point of the table being here instead of inside the handler is that the
/// dangerous cases can be stated: a bare arrow key must keep moving the focus,
/// Alt belongs to the menus, and a text field with the caret owns every key.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ShortcutAction? action(
    LogicalKeyboardKey key, {
    bool control = false,
    bool shift = false,
    bool alt = false,
    bool typing = false,
  }) => shortcutActionFor(
    key: key,
    control: control,
    shift: shift,
    alt: alt,
    typing: typing,
  );

  group('the keys behind each action', () {
    test('space keeps answering playback', () {
      expect(action(LogicalKeyboardKey.space), ShortcutAction.playPause);
      expect(action(LogicalKeyboardKey.space, control: true), isNull);
      expect(action(LogicalKeyboardKey.space, shift: true), isNull);
    });

    test('media keys work on their own', () {
      expect(
        action(LogicalKeyboardKey.mediaPlayPause),
        ShortcutAction.playPause,
      );
      expect(action(LogicalKeyboardKey.mediaPlay), ShortcutAction.playPause);
      expect(action(LogicalKeyboardKey.mediaTrackNext), ShortcutAction.next);
      expect(
        action(LogicalKeyboardKey.mediaTrackPrevious),
        ShortcutAction.previous,
      );
    });

    test('ctrl arrows steer the player', () {
      expect(
        action(LogicalKeyboardKey.arrowRight, control: true),
        ShortcutAction.next,
      );
      expect(
        action(LogicalKeyboardKey.arrowLeft, control: true),
        ShortcutAction.previous,
      );
      expect(
        action(LogicalKeyboardKey.arrowRight, control: true, shift: true),
        ShortcutAction.seekForward,
      );
      expect(
        action(LogicalKeyboardKey.arrowLeft, control: true, shift: true),
        ShortcutAction.seekBackward,
      );
      expect(
        action(LogicalKeyboardKey.arrowUp, control: true),
        ShortcutAction.volumeUp,
      );
      expect(
        action(LogicalKeyboardKey.arrowDown, control: true),
        ShortcutAction.volumeDown,
      );
    });

    test('the rest of the table', () {
      expect(
        action(LogicalKeyboardKey.keyM, control: true),
        ShortcutAction.mute,
      );
      expect(
        action(LogicalKeyboardKey.keyD, control: true),
        ShortcutAction.favorite,
      );
      expect(
        action(LogicalKeyboardKey.keyL, control: true),
        ShortcutAction.lyricsPage,
      );
      expect(action(LogicalKeyboardKey.f1), ShortcutAction.help);
    });

    test('plain keys, alt keys and typing are left to the app', () {
      // A bare arrow is how lists are walked with the keyboard.
      expect(action(LogicalKeyboardKey.arrowRight), isNull);
      expect(action(LogicalKeyboardKey.arrowLeft), isNull);
      expect(action(LogicalKeyboardKey.keyM), isNull);
      expect(action(LogicalKeyboardKey.keyD), isNull);

      // Alt belongs to the menus, the window and the platform.
      expect(
        action(LogicalKeyboardKey.arrowRight, control: true, alt: true),
        isNull,
      );
      expect(action(LogicalKeyboardKey.space, alt: true), isNull);

      // A field with the caret owns every key, modifiers or not.
      for (final key in [
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.f1,
        LogicalKeyboardKey.mediaTrackNext,
        LogicalKeyboardKey.keyD,
      ]) {
        expect(
          action(key, control: true, typing: true),
          isNull,
          reason: '$key while typing',
        );
        expect(action(key, typing: true), isNull, reason: '$key while typing');
      }
    });

    test('the volume steps stay inside 0..1', () {
      expect(shortcutVolume(0.5, shortcutVolumeStep), closeTo(0.55, 1e-9));
      expect(shortcutVolume(0.98, shortcutVolumeStep), 1.0);
      expect(shortcutVolume(0.02, -shortcutVolumeStep), 0.0);
      expect(shortcutVolume(0.0, -shortcutVolumeStep), 0.0);
      expect(shortcutVolume(1.0, shortcutVolumeStep), 1.0);
    });
  });

  group('what the help panel prints', () {
    final l10n = AppLocalizationsEn();

    test('names every action and every key', () {
      for (final action in ShortcutAction.values) {
        expect(
          (shortcutKeyLabels[action] ?? '').isNotEmpty,
          isTrue,
          reason: 'no key listed for $action',
        );
        expect(
          shortcutLabel(l10n, action).isNotEmpty,
          isTrue,
          reason: 'no description for $action',
        );
      }
      expect(shortcutKeyLabels.length, ShortcutAction.values.length);
    });

    test('never claims the same key twice', () {
      final keys = shortcutKeyLabels.values.toList();
      expect(keys.toSet().length, keys.length, reason: '$keys');
    });
  });
}
