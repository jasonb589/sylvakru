import 'package:material_ui/material_ui.dart';
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

/// The keys the app answers to, one line each.
///
/// Opened from the settings row and with F1: a shortcut that nothing spells out
/// is a shortcut nobody finds.
Future<void> showShortcutsHelp(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showAnimationDialog<void>(
    context: context,
    child: SizedBox(
      width: 360,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.shortcuts,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            for (final action in ShortcutAction.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(child: Text(shortcutLabel(l10n, action))),
                    const SizedBox(width: 12),
                    Text(
                      shortcutKeyLabels[action] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 2),
            Text(
              l10n.shortcutMediaKeys,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}
