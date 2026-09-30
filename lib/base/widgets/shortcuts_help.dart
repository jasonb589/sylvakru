import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/base/utils/shortcuts.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';

/// What each shortcut does, in the app's own language.
///
/// A test walks [ShortcutAction.values] through this, so an action cannot be
/// added to the player without a line here saying what it does.
String shortcutLabel(AppLocalizations l10n, ShortcutAction action) {
  switch (action) {
    case ShortcutAction.playPause:
      return l10n.shortcutPlayPause;
    case ShortcutAction.next:
      return l10n.shortcutNext;
    case ShortcutAction.previous:
      return l10n.shortcutPrevious;
    case ShortcutAction.seekBackward:
      return l10n.shortcutSeekBackward;
    case ShortcutAction.seekForward:
      return l10n.shortcutSeekForward;
    case ShortcutAction.volumeDown:
      return l10n.shortcutVolumeDown;
    case ShortcutAction.volumeUp:
      return l10n.shortcutVolumeUp;
    case ShortcutAction.mute:
      return l10n.shortcutMute;
    case ShortcutAction.favorite:
      return l10n.shortcutFavorite;
    case ShortcutAction.lyricsPage:
      return l10n.shortcutLyricsPage;
    case ShortcutAction.help:
      return l10n.shortcutHelp;
  }
}

/// The keys the app answers to, and where they can be changed.
///
/// Opened from the settings row and with F1. Tapping a key starts a capture: the
/// panel then listens for one combination, and the player's own handler stands
/// down for the duration (see [isCapturingShortcut]).
Future<void> showShortcutsHelp(BuildContext context) {
  return showAnimationDialog<void>(
    context: context,
    child: const SizedBox(width: 420, child: ShortcutsPanel()),
  );
}

/// The list of shortcuts, one row per action, each key editable.
class ShortcutsPanel extends StatefulWidget {
  const ShortcutsPanel({super.key});

  @override
  State<ShortcutsPanel> createState() => _ShortcutsPanelState();
}

class _ShortcutsPanelState extends State<ShortcutsPanel> {
  /// The action whose key is being captured, if any.
  ShortcutAction? _capturing;

  /// The combination just pressed, waiting for the user to accept taking it
  /// over from another action.
  ShortcutBinding? _pending;

  /// The message under the captured row: a combination that cannot be used, or
  /// the action that already holds it.
  String? _problem;

  ShortcutAction? _conflict;

  @override
  void dispose() {
    _stopCapture();
    super.dispose();
  }

  void _startCapture(ShortcutAction action) {
    HardwareKeyboard.instance.removeHandler(_onKey);
    HardwareKeyboard.instance.addHandler(_onKey);
    isCapturingShortcut = true;
    setState(() {
      _capturing = action;
      _pending = null;
      _conflict = null;
      _problem = null;
    });
  }

  void _stopCapture() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    isCapturingShortcut = false;
    _capturing = null;
    _pending = null;
    _conflict = null;
    _problem = null;
  }

  /// Takes the combination being pressed. Returns true so it cannot also reach
  /// whatever the panel is drawn over.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || _capturing == null) {
      return false;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // Escape gets out of the capture; it is never a binding itself.
      setState(_stopCapture);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight ||
        event.logicalKey == LogicalKeyboardKey.shiftLeft ||
        event.logicalKey == LogicalKeyboardKey.shiftRight) {
      // A modifier on its own is not a combination yet.
      return true;
    }

    final keyboard = HardwareKeyboard.instance;
    final binding = ShortcutBinding(
      event.logicalKey,
      control: keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
    );

    if (!isUsableBinding(binding)) {
      setState(() {
        _pending = null;
        _conflict = null;
        _problem = AppLocalizations.of(context).shortcutNotAllowed;
      });
      return true;
    }

    final holder = shortcutHolder(
      effectiveBindings(shortcutBindingsNotifier.value),
      _capturing!,
      binding,
    );
    if (holder != null) {
      setState(() {
        _pending = binding;
        _conflict = holder;
        _problem = null;
      });
      return true;
    }

    _apply(binding);
    return true;
  }

  void _apply(ShortcutBinding binding) {
    final l10n = AppLocalizations.of(context);
    final action = _capturing;
    if (action == null) {
      return;
    }

    final overrides = assignShortcut(
      current: effectiveBindings(shortcutBindingsNotifier.value),
      action: action,
      binding: binding,
    );

    if (overrides == null) {
      setState(() => _problem = l10n.shortcutNotAllowed);
      return;
    }

    shortcutBindingsNotifier.value = overrides;
    setting.save();
    setState(_stopCapture);
  }

  void _restoreDefaults() {
    shortcutBindingsNotifier.value = {};
    setting.save();
    setState(_stopCapture);
    showCenterMessage(AppLocalizations.of(context).shortcutRestored);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return ValueListenableBuilder<Map<ShortcutAction, ShortcutBinding>>(
      valueListenable: shortcutBindingsNotifier,
      builder: (context, overrides, _) {
        final bindings = effectiveBindings(overrides);

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    l10n.shortcuts,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (overrides.isNotEmpty)
                    TextButton(
                      onPressed: _restoreDefaults,
                      child: Text(l10n.shortcutRestoreDefaults),
                    ),
                ],
              ),
              Text(l10n.shortcutEditHint, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final action in ShortcutAction.values)
                      _row(context, l10n, theme, action, bindings[action]!),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(l10n.shortcutMediaKeys, style: theme.textTheme.bodySmall),
            ],
          ),
        );
      },
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    ShortcutAction action,
    ShortcutBinding binding,
  ) {
    final capturing = _capturing == action;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(shortcutLabel(l10n, action))),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () =>
                  capturing ? setState(_stopCapture) : _startCapture(action),
              child: Text(
                capturing ? l10n.shortcutPressKeys : bindingText(binding),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        if (capturing && _problem != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _problem!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (capturing && _conflict != null && _pending != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.shortcutConflict(shortcutLabel(l10n, _conflict!)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _apply(_pending!),
                  child: Text(l10n.shortcutReplace),
                ),
                TextButton(
                  onPressed: () => setState(_stopCapture),
                  child: Text(l10n.cancel),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
