import 'package:material_ui/material_ui.dart';
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

final GlobalKey<NavigatorState> downloadKey = GlobalKey();
final downloadVisibleNotifier = ValueNotifier(true);

/// "Downloads": every song that has an offline copy, and the space it takes.
///
/// This used to be a dialog buried two levels inside Settings → Cache, which
/// made the only place that manages offline copies the last place anyone would
/// look for it. It is a first-class destination now, reached from the sidebar.
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

    // The offline list changes under us in three ways: a download finishes, a
    // copy is removed, or the LRU sweep drops one to stay under the limit.
    return ListenableBuilder(
      listenable: Listenable.merge([
        library.changeNotifier,
        cacheSizeNotifier,
        cacheLimitMbNotifier,
        downloadingSongIdsNotifier,
      ]),
      builder: (context, _) {
        final songs = library.offlineSongs;

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
                child: Row(
                  children: [
                    const Icon(Icons.download_for_offline_rounded, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.offlineSongs,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      storageLabel(),
                      style: TextStyle(color: iconColor.value),
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(child: const SizedBox(height: 10)),

            if (songs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.download_for_offline_rounded,
                  title: l10n.noOfflineSongs,
                ),
              )
            else
              SliverList.builder(
                itemCount: songs.length,
                itemBuilder: (context, index) {
                  return offlineRow(
                    context,
                    songs[index],
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

  /// How much space the offline copies take, against the configured limit.
  String storageLabel() {
    final used = '${cacheSizeNotifier.value.toStringAsFixed(1)}MB';
    final limit = cacheLimitMbNotifier.value;
    return limit <= 0 ? used : '$used / $limit MB';
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
}
