import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/utils/shortcuts.dart';
import 'package:sylvakru/base/widgets/shortcuts_help.dart';
import 'package:sylvakru/l10n/generated/app_localizations_en.dart';

/// What each key does, without a player or a window.
///
/// The point of the table being here instead of inside the handler is that the
/// dangerous cases can be stated: a bare arrow key must keep moving the focus,
/// Alt belongs to the menus, a text field with the caret owns every key - and a
/// key the user changes by hand may not break any of that either.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ShortcutAction? action(
    LogicalKeyboardKey key, {
    bool control = false,
    bool shift = false,
    bool alt = false,
    bool typing = false,
    Map<ShortcutAction, ShortcutBinding>? bindings,
  }) => shortcutActionFor(
    key: key,
    control: control,
    shift: shift,
    alt: alt,
    typing: typing,
    bindings: bindings ?? defaultShortcutBindings,
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

  group('the table in force', () {
    test('is the defaults when nothing has been changed', () {
      expect(effectiveBindings({}), defaultShortcutBindings);
    });

    test('follows a change, and only for that action', () {
      const custom = ShortcutBinding(LogicalKeyboardKey.keyJ, control: true);
      final bindings = effectiveBindings({ShortcutAction.next: custom});

      expect(bindings[ShortcutAction.next], custom);
      expect(
        bindings[ShortcutAction.previous],
        defaultShortcutBindings[ShortcutAction.previous],
      );

      // The handler passes this table in, so the new key works and the old one
      // is free again.
      expect(
        action(LogicalKeyboardKey.keyJ, control: true, bindings: bindings),
        ShortcutAction.next,
      );
      expect(
        action(
          LogicalKeyboardKey.arrowRight,
          control: true,
          bindings: bindings,
        ),
        isNull,
      );
    });
  });

  group('changing a key', () {
    test('a free combination is taken and saved as a change', () {
      const wanted = ShortcutBinding(LogicalKeyboardKey.keyH, control: true);
      final overrides = assignShortcut(
        current: defaultShortcutBindings,
        action: ShortcutAction.favorite,
        binding: wanted,
      );

      expect(overrides, {ShortcutAction.favorite: wanted});
    });

    test('a combination another action holds swaps the two', () {
      final mine = defaultShortcutBindings[ShortcutAction.favorite]!;
      final theirs = defaultShortcutBindings[ShortcutAction.mute]!;

      final overrides = assignShortcut(
        current: defaultShortcutBindings,
        action: ShortcutAction.favorite,
        binding: theirs,
      );

      expect(overrides![ShortcutAction.favorite], theirs);
      expect(
        overrides[ShortcutAction.mute],
        mine,
        reason: 'the other action gets the old key instead of losing one',
      );
      expect(overrides, hasLength(2));
    });

    test('a combination that would break the app is refused', () {
      for (final binding in const [
        ShortcutBinding(LogicalKeyboardKey.keyA),
        ShortcutBinding(LogicalKeyboardKey.arrowRight),
        ShortcutBinding(LogicalKeyboardKey.escape),
        ShortcutBinding(LogicalKeyboardKey.tab, shift: true),
        ShortcutBinding(LogicalKeyboardKey.f11),
      ]) {
        expect(isUsableBinding(binding), isFalse, reason: bindingText(binding));
        expect(
          assignShortcut(
            current: defaultShortcutBindings,
            action: ShortcutAction.next,
            binding: binding,
          ),
          isNull,
          reason: bindingText(binding),
        );
      }

      // Space and the media keys are the two that stand alone on purpose: they
      // are playback keys and nothing else.
      expect(
        isUsableBinding(const ShortcutBinding(LogicalKeyboardKey.space)),
        isTrue,
      );
      expect(
        isUsableBinding(
          const ShortcutBinding(LogicalKeyboardKey.mediaTrackNext),
        ),
        isTrue,
      );
      expect(
        isUsableBinding(
          const ShortcutBinding(LogicalKeyboardKey.keyA, control: true),
        ),
        isTrue,
      );
    });

    test('going back to the default drops the change', () {
      final overrides = assignShortcut(
        current: effectiveBindings({
          ShortcutAction.mute: const ShortcutBinding(LogicalKeyboardKey.space),
        }),
        action: ShortcutAction.mute,
        binding: defaultShortcutBindings[ShortcutAction.mute]!,
      );

      expect(overrides, isEmpty);
    });

    test('no two actions end up on one key', () {
      var current = defaultShortcutBindings;
      var overrides = <ShortcutAction, ShortcutBinding>{};

      // Three changes in a row, two of them onto a key someone else holds.
      for (final (action, binding) in [
        (
          ShortcutAction.next,
          const ShortcutBinding(LogicalKeyboardKey.keyJ, control: true),
        ),
        (
          ShortcutAction.mute,
          const ShortcutBinding(LogicalKeyboardKey.keyJ, control: true),
        ),
        (
          ShortcutAction.seekForward,
          const ShortcutBinding(LogicalKeyboardKey.keyQ, control: true),
        ),
      ]) {
        overrides = assignShortcut(
          current: current,
          action: action,
          binding: binding,
        )!;
        current = effectiveBindings(overrides);
      }

      final bindings = current.values.toList();
      expect(bindings.toSet().length, bindings.length);
      expect(current[ShortcutAction.mute]!.key, LogicalKeyboardKey.keyJ);
    });
  });

  group('the settings file', () {
    test('a change survives a round trip', () {
      final overrides = {
        ShortcutAction.next: const ShortcutBinding(
          LogicalKeyboardKey.keyJ,
          control: true,
        ),
        ShortcutAction.seekForward: const ShortcutBinding(
          LogicalKeyboardKey.period,
          control: true,
          shift: true,
        ),
      };

      expect(
        decodeShortcutOverrides(encodeShortcutOverrides(overrides)),
        overrides,
      );
    });

    test('anything unusable is left out instead of costing a key', () {
      expect(decodeShortcutOverrides(null), isEmpty);
      expect(decodeShortcutOverrides('nonsense'), isEmpty);
      expect(decodeShortcutOverrides({'next': 'not-a-binding'}), isEmpty);
      expect(decodeShortcutOverrides({'noSuchAction': 'c74'}), isEmpty);
      // A bare letter is not something the panel would accept either, so a file
      // that carries one does not get to break typing.
      expect(
        decodeShortcutOverrides({'next': '${LogicalKeyboardKey.keyA.keyId}'}),
        isEmpty,
      );
      // An action left at its default needs no entry.
      expect(
        decodeShortcutOverrides({
          'next': encodeShortcut(defaultShortcutBindings[ShortcutAction.next]!),
        }),
        isEmpty,
      );
    });

    test('one binding reads back as it was written', () {
      for (final binding in const [
        ShortcutBinding(LogicalKeyboardKey.space),
        ShortcutBinding(
          LogicalKeyboardKey.arrowLeft,
          control: true,
          shift: true,
        ),
        ShortcutBinding(LogicalKeyboardKey.f1),
        ShortcutBinding(LogicalKeyboardKey.mediaTrackNext),
      ]) {
        expect(decodeShortcut(encodeShortcut(binding)), binding);
      }

      expect(decodeShortcut(''), isNull);
      expect(decodeShortcut('c'), isNull);
      expect(decodeShortcut('x123'), isNull);
    });
  });

  group('what the panel prints', () {
    final l10n = AppLocalizationsEn();

    test('every action has a key and a description', () {
      for (final action in ShortcutAction.values) {
        final binding = defaultShortcutBindings[action];
        expect(binding, isNotNull, reason: 'no default key for $action');
        expect(bindingText(binding!), isNotEmpty, reason: '$action');
        expect(
          shortcutLabel(l10n, action).isNotEmpty,
          isTrue,
          reason: 'no description for $action',
        );
      }
      expect(defaultShortcutBindings.length, ShortcutAction.values.length);
    });

    test('writes a combination the way the panel shows it', () {
      expect(
        bindingText(defaultShortcutBindings[ShortcutAction.next]!),
        'Ctrl + →',
      );
      expect(
        bindingText(defaultShortcutBindings[ShortcutAction.seekBackward]!),
        'Ctrl + Shift + ←',
      );
      expect(
        bindingText(defaultShortcutBindings[ShortcutAction.mute]!),
        'Ctrl + M',
      );
      expect(bindingText(defaultShortcutBindings[ShortcutAction.help]!), 'F1');
      expect(
        bindingText(defaultShortcutBindings[ShortcutAction.playPause]!),
        'Space',
      );
    });

    test('no two defaults share a combination', () {
      final bindings = defaultShortcutBindings.values.toList();
      expect(bindings.toSet().length, bindings.length);
    });
  });
}
