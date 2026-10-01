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
import 'package:sylvakru/base/services/disk_space_service.dart';
import 'package:sylvakru/base/utils/disk_space.dart';
import 'package:sylvakru/base/widgets/my_navigator.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/landscape_view/title_bar.dart';
import 'package:sylvakru/layer/layers_manager.dart';
import 'package:sylvakru/base/utils/download_list_order.dart';
import 'package:sylvakru/base/utils/zoom_page_route.dart';
import 'package:sylvakru/base/widgets/selectable_song_list_page.dart';
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

  /// How the list is ordered and whether it is split into sections. The centre
  /// is a view of the same downloads rather than a setting, so these live with
  /// the page instead of in setting.json.
  final sortNotifier = ValueNotifier(DownloadSort.title);
  final groupNotifier = ValueNotifier(DownloadGroup.none);

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
    // The volume is asked again every time the page comes up: downloads and
    // everything else on the machine keep changing it.
    refreshDiskFreeSpace();
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
        // The rows mark the song that is playing: that mark follows the
        // player, not the library.
        currentSongNotifier,
        downloadSizeNotifier,
        otherDownloadSizeNotifier,
        offlineMusicLimitMbNotifier,
        downloadOverLimitMbNotifier,
        downloadingSongIdsNotifier,
        downloadQueueNotifier,
        downloadRunningNotifier,
        downloadProgressNotifier,
        downloadErrorsNotifier,
        diskFreeSpaceBytesNotifier,
        diskSpaceWarnMbNotifier,
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
                        // A context of the button's own, so the menu hangs off
                        // it: the page's context put every one of these menus
                        // at the bottom-left corner of the page instead.
                        Builder(
                          builder: (context) => Tooltip(
                            message: l10n.offlineMusicStorage,
                            child: TextButton.icon(
                              onPressed: () => _showListMenu(context, l10n),
                              icon: const Icon(Icons.tune, size: 16),
                              label: Text(storageLabel(l10n)),
                            ),
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
                    if (isDiskSpaceLow(
                      freeBytes: diskFreeSpaceBytesNotifier.value,
                      thresholdMb: diskSpaceWarnMbNotifier.value,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 15,
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                l10n.diskSpaceLow(
                                  formatBytes(
                                    diskFreeSpaceBytesNotifier.value!,
                                  ),
                                  '${diskSpaceWarnMbNotifier.value} MB',
                                ),
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
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
              ListenableBuilder(
                listenable: Listenable.merge([sortNotifier, groupNotifier]),
                builder: (context, _) {
                  final entries = buildDownloadList(
                    songs,
                    sort: sortNotifier.value,
                    group: groupNotifier.value,
                  );
                  return SliverList.builder(
                    itemCount: downloading.length + entries.length,
                    itemBuilder: (context, index) {
                      if (index < downloading.length) {
                        return downloadingRow(
                          context,
                          downloading[index],
                          horizontalPadding,
                        );
                      }
                      final entry = entries[index - downloading.length];
                      final header = entry.title;
                      if (header != null) {
                        return sectionHeader(context, header);
                      }
                      return offlineRow(
                        context,
                        entry.song!,
                        songs,
                        horizontalPadding,
                      );
                    },
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

  /// What the download volume has left, or that nobody can say.
  String _freeSpaceLabel(AppLocalizations l10n) {
    final bytes = diskFreeSpaceBytesNotifier.value;
    return bytes == null ? l10n.diskFreeSpaceUnknown : formatBytes(bytes);
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

  /// The menu behind the storage button: the limit, the other files, and how
  /// the list is ordered.
  void _showListMenu(BuildContext context, AppLocalizations l10n) {
    final box = context.findRenderObject() as RenderBox?;
    final position = box != null && box.hasSize
        ? box.localToGlobal(box.size.bottomLeft(Offset.zero))
        : Offset.zero;

    showContextMenu(context, [
      MenuItem(
        text: '${l10n.diskFreeSpace} · ${_freeSpaceLabel(l10n)}',
        callback: () => refreshDiskFreeSpace(force: true),
      ),
      MenuItem(
        text: l10n.offlineMusicLimit,
        callback: () => _showOfflineLimitPicker(context, l10n),
      ),
      MenuItem(
        text: otherDownloadSizeNotifier.value > 0
            ? '${l10n.otherFiles} ${otherDownloadSizeNotifier.value.toStringAsFixed(1)}MB'
            : l10n.otherFiles,
        callback: () => _showOtherFiles(context, l10n),
      ),
      MenuItem(
        text: '${l10n.sortBy} · ${_sortLabel(l10n, sortNotifier.value)}',
        callback: () => _pickSort(context, l10n),
      ),
      MenuItem(
        text: '${l10n.groupBy} · ${_groupLabel(l10n, groupNotifier.value)}',
        callback: () => _pickGroup(context, l10n),
      ),
      MenuItem(text: l10n.selectSongs, callback: () => _openSelection(context)),
    ], position);
  }

  String _sortLabel(AppLocalizations l10n, DownloadSort sort) {
    switch (sort) {
      case DownloadSort.title:
        return l10n.sortTitle;
      case DownloadSort.artist:
        return l10n.sortArtist;
      case DownloadSort.album:
        return l10n.sortAlbum;
      case DownloadSort.recentlyPlayed:
        return l10n.sortRecentlyPlayed;
      case DownloadSort.mostPlayed:
        return l10n.sortMostPlayed;
    }
  }

  String _groupLabel(AppLocalizations l10n, DownloadGroup group) {
    switch (group) {
      case DownloadGroup.none:
        return l10n.groupNone;
      case DownloadGroup.album:
        return l10n.groupAlbum;
      case DownloadGroup.artist:
        return l10n.groupArtist;
    }
  }

  Future<void> _pickSort(BuildContext context, AppLocalizations l10n) async {
    final chosen = await _pickFrom<DownloadSort>(context, l10n.sortBy, [
      for (final option in DownloadSort.values)
        (option, _sortLabel(l10n, option)),
    ], sortNotifier.value);
    if (chosen != null) {
      sortNotifier.value = chosen;
    }
  }

  Future<void> _pickGroup(BuildContext context, AppLocalizations l10n) async {
    final chosen = await _pickFrom<DownloadGroup>(context, l10n.groupBy, [
      for (final option in DownloadGroup.values)
        (option, _groupLabel(l10n, option)),
    ], groupNotifier.value);
    if (chosen != null) {
      groupNotifier.value = chosen;
    }
  }

  /// One labelled chooser, the same shape the settings use for a short list.
  Future<T?> _pickFrom<T>(
    BuildContext context,
    String title,
    List<(T, String)> options,
    T current,
  ) {
    return showAnimationDialog<T>(
      context: context,
      child: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: Text(title, style: AppText.sheetTitle),
            ),
            for (final (value, label) in options)
              ListTile(
                leading: Icon(
                  value == current
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                ),
                title: Text(label),
                onTap: () => Navigator.of(context).pop(value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// A section heading, for when the list is grouped.
  Widget sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: iconColor.value,
        ),
      ),
    );
  }

  /// Selects several downloads and removes them in one go. The file that is
  /// playing stays: it cannot be deleted while the player holds it open.
  Future<void> _openSelection(BuildContext context) async {
    final songs = library.offlineMusicSongs;
    if (songs.isEmpty) {
      return;
    }
    await Navigator.of(context).push(
      ZoomPageRoute(
        builder: (_) => SelectableSongListPage(
          songList: songs,
          reorderable: false,
          isSelectedNotifierMap: {
            for (final song in songs) song: ValueNotifier(false),
          },
          onDelete: (selected) async {
            for (final song in selected) {
              if (currentSongNotifier.value?.id == song.id &&
                  isPlayingNotifier.value) {
                continue;
              }
              await library.removeOfflineCopy(song);
            }
          },
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
  /// and decides, one file at a time. The list belongs to the dialog, so a file
  /// that is removed takes its own row away and leaves the rest to be read: the
  /// delete used to close the dialog and open a new one from the context it had
  /// just popped, which usually showed nothing at all.
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
      child: _OtherFilesDialog(files: files, l10n: l10n),
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
      // The long press is taken here rather than by the tile, so the menu can
      // hang off the row that was pressed instead of the corner of the window.
      onLongPressStart: (details) =>
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

/// The "other files" list, as a dialog that keeps itself while files go.
class _OtherFilesDialog extends StatefulWidget {
  const _OtherFilesDialog({required this.files, required this.l10n});

  final List<({String path, int bytes})> files;
  final AppLocalizations l10n;

  @override
  State<_OtherFilesDialog> createState() => _OtherFilesDialogState();
}

class _OtherFilesDialogState extends State<_OtherFilesDialog> {
  late final List<({String path, int bytes})> _files = List.of(widget.files);

  Future<void> _delete(({String path, int bytes}) file) async {
    final confirmed = await showConfirmDialog(context, widget.l10n.deleteFile);
    if (!confirmed || !mounted) {
      return;
    }
    // The accounting behind the dialog is refreshed by the delete itself, so
    // the row is all that has to go.
    await library.deleteOtherDownload(file.path);
    if (!mounted) {
      return;
    }
    setState(() => _files.remove(file));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_files.isEmpty)
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
                  for (final file in _files)
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
                            onPressed: () => _delete(file),
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
    );
  }
}
