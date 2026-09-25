import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/data/playlist.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/base/utils/advanced_song_search.dart';
import 'package:sylvakru/base/widgets/advanced_song_search_dialog.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';

Future<bool> showCreateSmartPlaylistDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final name = (await getInputTextDialog(context, l10n.smartPlaylistName)).trim();
  if (name.isEmpty || !context.mounted) {
    return false;
  }

  final criteria = await showAnimationDialog<SongSearchCriteria>(
    context: context,
    child: AdvancedSongSearchDialog(
      criteria: SongSearchCriteria(),
      editQuery: true,
    ),
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
