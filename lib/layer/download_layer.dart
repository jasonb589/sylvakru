import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/asset_images.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/design/app_tokens.dart';
import 'package:sylvakru/base/design/empty_state.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/base/utils/media_query.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:sylvakru/base/widgets/cover_art_widget.dart';
import 'package:sylvakru/base/widgets/my_navigator.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/landscape_view/title_bar.dart';
import 'package:sylvakru/layer/layers_manager.dart';

final GlobalKey<NavigatorState> downloadKey = GlobalKey();
final downloadVisibleNotifier = ValueNotifier(true);

/// "Offline Music": every song with a user-managed offline copy, and the
/// storage it occupies. Temporary playback cache is intentionally excluded.
class DownloadLayer extends StatefulWidget {
  const DownloadLayer({super.key});

  @override
  State<DownloadLayer> createState() => _DownloadLayerState();
}

class _DownloadLayerState extends State<DownloadLayer> {
  final scrollController = ScrollController();

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return myNavigator(
      key: downloadKey,
      visibleNotifier: downloadVisibleNotifier,
      pageViewBuilder: () => pageView(context),
      panelViewBuilder: () => panelView(context),
    );
  }

  Widget panelView(BuildContext context) {
    return Column(
      children: [
        TitleBar(
          scrollToTop: () {
            scrollController.animateTo(
              0,
              duration: AppDuration.normal,
              curve: AppCurve.standard,
            );
          },
        ),
        Expanded(child: content(context, horizontalPadding: 30)),
      ],
    );
  }

  Widget pageView(BuildContext context) {
    return SafeArea(child: content(context, horizontalPadding: 20));
  }

  Widget content(BuildContext context, {required double horizontalPadding}) {
    final l10n = AppLocalizations.of(context);

    // The offline list changes when a download finishes, a copy is removed,
    // or the offline limit evicts a file.
    return ListenableBuilder(
      listenable: Listenable.merge([
        library.changeNotifier,
        downloadSizeNotifier,
        offlineMusicLimitMbNotifier,
        downloadingSongIdsNotifier,
      ]),
      builder: (context, _) {
        final songs = library.offlineMusicSongs;
        // Downloads still running are listed too, so a download that has not
        // finished is visible instead of the list only filling in later.
        final downloading = downloadingSongIdsNotifier.value
            .map((id) => library.id2Song[id])
            .whereType<MyAudioMetadata>()
            .where((song) => !song.downloadExist)
            .toList();

        return CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  10 + getTopOffset(context),
                  horizontalPadding,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const ImageIcon(offlineMusicImage, size: 34),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.offlineMusic,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Tooltip(
                          message: l10n.offlineMusicStorage,
                          child: TextButton.icon(
                            onPressed: () =>
                                _showOfflineLimitPicker(context, l10n),
                            icon: const Icon(Icons.tune, size: 16),
                            label: Text(storageLabel()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.offlineMusicDescription,
                      style: TextStyle(color: iconColor.value, fontSize: 12),
                    ),
                    Text(
                      l10n.offlineMusicCount(songs.length),
                      style: TextStyle(color: iconColor.value, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(child: const SizedBox(height: 10)),

            if (songs.isEmpty && downloading.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.music_note_outlined,
                  title: l10n.noOfflineMusic,
                  subtitle: l10n.noOfflineMusicHint,
                  action: TextButton.icon(
                    onPressed: () => layersManager.switchRootLayer('songs'),
                    icon: const Icon(Icons.library_music_outlined, size: 18),
                    label: Text(l10n.browseSongs),
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: downloading.length + songs.length,
                itemBuilder: (context, index) {
                  if (index < downloading.length) {
                    return downloadingRow(
                      context,
                      downloading[index],
                      horizontalPadding,
                    );
                  }
                  return offlineRow(
                    context,
                    songs[index - downloading.length],
                    songs,
                    horizontalPadding,
                  );
                },
              ),

            SliverToBoxAdapter(child: const SizedBox(height: 20)),
          ],
        );
      },
    );
  }

  /// How much space the offline copies take, against the offline music limit.
  String storageLabel() {
    final used = '${downloadSizeNotifier.value.toStringAsFixed(1)}MB';
    final limit = offlineMusicLimitMbNotifier.value;
    return limit <= 0 ? used : '$used / $limit MB';
  }

  void _showOfflineLimitPicker(BuildContext context, AppLocalizations l10n) {
    showAnimationDialog(
      context: context,
      child: SizedBox(
        width: 300,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
          child: ValueListenableBuilder(
            valueListenable: offlineMusicLimitMbNotifier,
            builder: (context, current, child) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 35,
                    child: Text(
                      l10n.offlineMusicLimit,
                      style: AppText.sheetTitle,
                    ),
                  ),
                  for (final option in offlineMusicLimitOptionsMb)
                    ListTile(
                      title: Text(
                        option <= 0
                            ? l10n.offlineMusicLimitUnlimited
                            : '$option MB',
                      ),
                      trailing: current == option
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () {
                        offlineMusicLimitMbNotifier.value = option;
                        setting.save();
                        library.enforceDownloadLimit(
                          keepSongIds: playQueue.map((song) => song.id).toSet(),
                        );
                        Navigator.pop(context);
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget offlineRow(
    BuildContext context,
    MyAudioMetadata song,
    List<MyAudioMetadata> songs,
    double horizontalPadding,
  ) {
    final l10n = AppLocalizations.of(context);

    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      // The row that is playing right now, so tapping through the list gives
      // the same "you are here" cue the song lists use.
      selected: currentSongNotifier.value?.id == song.id,
      selectedColor: highlightTextColor.value,
      selectedTileColor: selectedItemColor.value,
      leading: CoverArtWidget(
        size: 42,
        borderRadius: AppRadius.coverTiny,
        picture: song.picture,
      ),
      title: Text(getTitle(song), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        getArtist(song),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: l10n.removeDownload,
        onPressed: () async {
          // Never pull the file out from under a playing or queued track; the
          // same guard the song menu uses.
          final removed = await library.removeOfflineCopy(
            song,
            currentlyPlaying:
                currentSongNotifier.value?.id == song.id &&
                isPlayingNotifier.value,
            currentlyQueued: playQueue.any((item) => item.id == song.id),
          );
          if (!removed && context.mounted) {
            showCenterMessage(l10n.downloadInUse);
          }
        },
      ),
      onTap: () {
        audioHandler.setPlayQueue(songs, 0, targetIndex: songs.indexOf(song));
      },
    );
  }

  /// A song whose offline copy is still being written.
  Widget downloadingRow(
    BuildContext context,
    MyAudioMetadata song,
    double horizontalPadding,
  ) {
    final l10n = AppLocalizations.of(context);

    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      leading: CoverArtWidget(
        size: 42,
        borderRadius: AppRadius.coverTiny,
        picture: song.picture,
      ),
      title: Text(getTitle(song), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(l10n.downloading),
      trailing: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      enabled: false,
    );
  }
}
