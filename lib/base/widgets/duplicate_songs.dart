import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/asset_images.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/base/utils/common_utils.dart';
import 'package:sylvakru/base/utils/duplicate_songs.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:sylvakru/base/utils/reveal_in_file_manager.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';

/// The songs that look like the same recording, listed for the user to decide.
///
/// A report, not a cleaner: the same song twice can be deliberate (a live take
/// beside the studio one), so nothing here is removed. The folder button opens
/// the place one copy lives, which is what makes the list actionable at all.
Future<void> showDuplicateSongs(
  BuildContext context,
  AppLocalizations l10n,
  List<MyAudioMetadata> songs,
) async {
  showCenterLoading();
  final groups = findDuplicateSongs(songs);
  removeCenterLoading();

  if (!context.mounted) {
    return;
  }

  if (groups.isEmpty) {
    showCenterMessage(l10n.noDuplicateSongs);
    return;
  }

  await showAnimationDialog<void>(
    context: context,
    child: SizedBox(
      width: 460,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.duplicateSongs,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.duplicateSongsCount(groups.length),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: groups.length,
                itemBuilder: (context, index) =>
                    _group(context, l10n, groups[index]),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _group(
  BuildContext context,
  AppLocalizations l10n,
  DuplicateGroup group,
) {
  final body = Theme.of(context).textTheme.bodySmall;
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${getTitle(group.song)} — ${getArtist(group.song)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        for (final song in group.songs)
          Row(
            children: [
              Expanded(
                child: Text(
                  _copyLine(l10n, song),
                  style: body,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: l10n.filePath,
                icon: const ImageIcon(folderImage, size: 18),
                onPressed: () {
                  final path = songPath(song);
                  if (path != null) {
                    revealInFileManager(path);
                  }
                },
              ),
            ],
          ),
      ],
    ),
  );
}

/// One copy of the song, as the report lists it: how long it is and where it is.
String _copyLine(AppLocalizations l10n, MyAudioMetadata song) {
  final length = song.duration;
  final size = length == null
      ? l10n.duplicateLengthUnknown
      : formatDuration(length, ms: false);
  return '$size · ${songPath(song) ?? l10n.duplicateNoPath}';
}
