import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/data/playlist.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/base/data/smart_playlist.dart';
import 'package:sylvakru/base/widgets/smart_playlist_criteria_dialog.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';

Future<bool> showCreateSmartPlaylistDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final name = (await getInputTextDialog(context, l10n.smartPlaylistName)).trim();
  if (name.isEmpty || !context.mounted) {
    return false;
  }

  final criteria = await showAnimationDialog<SmartPlaylistCriteria>(
    context: context,
    child: SmartPlaylistCriteriaDialog(criteria: SmartPlaylistCriteria()),
  );
  if (criteria == null || !context.mounted) {
    return false;
  }

  final created = await playlistManager.createSmartPlaylist(
    SmartPlaylistDefinition(name: name, criteria: criteria),
  );
  if (!created && context.mounted) {
    showCenterMessage(l10n.smartPlaylistNameExists);
  }
  return created;
}
