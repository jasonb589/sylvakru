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
import 'package:sylvakru/base/utils/download_info.dart';
import 'package:sylvakru/base/widgets/cover_art_widget.dart';
import 'package:path/path.dart' as p;
import 'package:sylvakru/base/utils/reveal_in_file_manager.dart';
import 'package:sylvakru/base/widgets/my_navigator.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/landscape_view/title_bar.dart';
import 'package:sylvakru/layer/layers_manager.dart';
import 'package:sylvakru/base/services/download_queue.dart';

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
  void initState() {
    super.initState();
    // Files can be deleted in Explorer while the app is running: re-read the
    // folder whenever the page comes into view, so a row never keeps claiming a
    // download that is no longer there.
    downloadVisibleNotifier.addListener(_recheckDownloads);
    _recheckDownloads();
  }

  @override
  void dispose() {
    downloadVisibleNotifier.removeListener(_recheckDownloads);
    scrollController.dispose();
    super.dispose();
  }

  void _recheckDownloads() {
    if (!downloadVisibleNotifier.value) {
      return;
    }
    library.repointDownloads();
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
        otherDownloadSizeNotifier,
        offlineMusicLimitMbNotifier,
        downloadOverLimitMbNotifier,
        downloadingSongIdsNotifier,
        downloadQueueNotifier,
        downloadRunningNotifier,
        downloadProgressNotifier,
        downloadErrorsNotifier,
      ]),
      builder: (context, _) {
        final songs = library.offlineMusicSongs;
        // Queued and running downloads are listed too, so a download that has
        // not finished yet is visible instead of the list only filling in later.
        final downloading = downloadQueue.activeIds
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
                            label: Text(storageLabel(l10n)),
                          ),
                        ),
                        ValueListenableBuilder(
                          valueListenable: otherDownloadSizeNotifier,
                          builder: (context, other, _) {
                            if (other <= 0) {
                              return const SizedBox.shrink();
                            }
                            return TextButton(
                              onPressed: () => _showOtherFiles(context, l10n),
                              child: Text(
                                '${l10n.otherFiles} ${other.toStringAsFixed(1)}MB',
                              ),
                            );
                          },
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
  /// How much space the downloaded files take, and how much of the folder
  /// belongs to something else, against the configured limit.
  ///
  /// The two figures are shown apart because only the first one is the
  /// library's: leftover or hand-copied files used to be folded into it, which
  /// is why the number never matched the list beneath it.
  String storageLabel(AppLocalizations l10n) {
    final used = '${downloadSizeNotifier.value.toStringAsFixed(1)}MB';
    final limit = offlineMusicLimitMbNotifier.value;
    final limitText = limit <= 0 ? '' : ' / $limit MB';
    final other = otherDownloadSizeNotifier.value;
    final otherText = other < 0.1
        ? ''
        : ' · ${l10n.otherFiles} ${other.toStringAsFixed(1)}MB';
    return '$used$limitText$otherText';
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
                        library.cleanUpToLimit(
                          keepSongIds: playQueue.map((song) => song.id).toSet(),
                        );
                        library.checkDownloadBudget();
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

  /// Removes one download, moving off it first when it is the playing file.
  ///
  /// Shared by the row's delete button and its menu, so the two cannot drift.
  Future<void> _removeDownload(
    BuildContext context,
    MyAudioMetadata song,
    AppLocalizations l10n,
  ) async {
    // A playing file cannot be deleted, so this case moves on first instead of
    // refusing and asking the listener to pause.
    if (currentSongNotifier.value?.id == song.id && isPlayingNotifier.value) {
      await audioHandler.skipToNext();
      if (currentSongNotifier.value?.id == song.id) {
        // Nothing to move on to: the file is still in use.
        if (context.mounted) {
          showCenterMessage(l10n.downloadInUse);
        }
        return;
      }
    }
    final removed = await library.removeOfflineCopy(song);
    if (!removed && context.mounted) {
      showCenterMessage(l10n.downloadInUse);
    }
  }

  /// The menu a downloaded row offers: where the file is, and removing it.
  void _showOfflineRowMenu(
    BuildContext context,
    MyAudioMetadata song,
    AppLocalizations l10n,
    Offset? position,
  ) {
    final path = song.downloadPath;
    if (path == null) {
      return;
    }
    showContextMenu(context, [
      MenuItem(
        text: l10n.revealInFolder,
        callback: () => revealInFileManager(path),
      ),
      MenuItem(
        text: l10n.removeDownload,
        callback: () => _removeDownload(context, song, l10n),
      ),
    ], position ?? Offset.zero);
  }

  /// The files in the downloads folder that belong to no song.
  ///
  /// Listed rather than deleted: they may be anything, so the listener looks
  /// and decides, one file at a time.
  Future<void> _showOtherFiles(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final files = await library.otherDownloadFiles();
    if (!context.mounted) {
      return;
    }

    await showAnimationDialog(
      context: context,
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (files.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(l10n.otherFilesEmpty),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Text(
                  l10n.otherFilesHint,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final file in files)
                      ListTile(
                        title: Text(
                          p.basename(file.path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(formatBytes(file.bytes)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: l10n.revealInFolder,
                              icon: const Icon(Icons.folder_open_rounded),
                              onPressed: () => revealInFileManager(file.path),
                            ),
                            IconButton(
                              tooltip: l10n.deleteFile,
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final confirmed = await showConfirmDialog(
                                  context,
                                  l10n.deleteFile,
                                );
                                if (!confirmed) {
                                  return;
                                }
                                await library.deleteOtherDownload(file.path);
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  _showOtherFiles(context, l10n);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
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

    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showOfflineRowMenu(context, song, l10n, details.globalPosition),
      child: ListTile(
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
        title: Text(
          getTitle(song),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [getArtist(song), ?describeDownloadQuality(song)].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: l10n.removeDownload,
          onPressed: () => _removeDownload(context, song, l10n),
        ),
        onLongPress: () => _showOfflineRowMenu(context, song, l10n, null),
        onTap: () {
          audioHandler.setPlayQueue(songs, 0, targetIndex: songs.indexOf(song));
        },
      ),
    );
  }

  /// A song the queue is working on, waiting on, or gave up on.
  ///
  /// A running download shows how far it has come; one whose size the server
  /// did not report stays indeterminate rather than pretending to be at 0%.
  Widget downloadingRow(
    BuildContext context,
    MyAudioMetadata song,
    double horizontalPadding,
  ) {
    final l10n = AppLocalizations.of(context);
    final error = downloadErrorsNotifier.value[song.id];
    final progress = downloadProgressNotifier.value[song.id] ?? -1;
    final running = downloadRunningNotifier.value.contains(song.id);

    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      leading: CoverArtWidget(
        size: 42,
        borderRadius: AppRadius.coverTiny,
        picture: song.picture,
      ),
      title: Text(getTitle(song), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: error != null
          ? Text(
              l10n.downloadFailed,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : running && progress >= 0
          ? Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 3,
              ),
            )
          : Text(
              [l10n.downloading, ?describeDownloadQuality(song)].join(' · '),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.downloadRetry,
              onPressed: () => downloadQueue.retry(song),
            ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.downloadCancel,
            onPressed: () => downloadQueue.cancel(song.id),
          ),
        ],
      ),
    );
  }
}
