import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/asset_images.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/recommend.dart';
import 'package:sylvakru/base/utils/common_utils.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/utils/media_query.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:sylvakru/base/widgets/cover_art_widget.dart';
import 'package:sylvakru/base/widgets/my_navigator.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/layer/layers_manager.dart';
import 'package:sylvakru/landscape_view/title_bar.dart';

final GlobalKey<NavigatorState> forYouKey = GlobalKey();
final forYouVisibleNotifier = ValueNotifier(true);

/// "For You": recommended artists and songs, split into two sections.
///
/// Everything is derived locally from play counts, last-played times,
/// favourites and tags, so it works on every source type (local, WebDAV,
/// Navidrome, Emby, FnOS) without asking any server.
class ForYouLayer extends StatefulWidget {
  const ForYouLayer({super.key});

  @override
  State<ForYouLayer> createState() => _ForYouLayerState();
}

class _ForYouLayerState extends State<ForYouLayer> {
  final scrollController = ScrollController();

  /// Drives the horizontal artist row's scrollbar.
  final artistController = ScrollController();

  /// Picks the random draw to show.
  ///
  /// Starts from the clock rather than 0, so opening the app again offers a
  /// different set instead of repeating the same one every launch. "Refresh"
  /// bumps it to move on from the current set.
  int _seed = DateTime.now().millisecondsSinceEpoch;

  List<SongRecommendation> _songs = const [];
  List<ArtistRecommendation> _artists = const [];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuild();
    });

    // stream sources have not fetched their artists yet at this point
    _ensureArtists();
  }

  @override
  void dispose() {
    scrollController.dispose();
    artistController.dispose();
    super.dispose();
  }

  /// Loads the artist list if the source has not provided it yet.
  ///
  /// Stream sources only fetch their artists when the artist page is opened,
  /// so without this the artist section would stay empty until the listener
  /// happened to visit that page first.
  Future<void> _ensureArtists() async {
    if (artistAlbumManager.artistList.isNotEmpty || !isStreamSource) {
      return;
    }
    await artistAlbumManager.loadArtists();
    if (mounted) {
      _rebuild();
    }
  }

  void _rebuild() {
    setState(() {
      _songs = Recommender.randomSongs(
        songs: library.songList,
        seed: _seed,
      );
      _artists = Recommender.randomArtists(
        artists: artistAlbumManager.artistList,
        seed: _seed,
      );
    });
  }

  void _refresh() {
    _seed++;
    _rebuild();
  }

  /// Plays the recommended songs starting at [index].
  ///
  /// The second positional argument is the play mode, not the index, so the
  /// target has to be passed by name: passing the index positionally would be
  /// read as a mode and the queue would start on a random song.
  void _playFrom(int index) {
    if (_songs.isEmpty) {
      return;
    }
    audioHandler.setPlayQueue(
      _songs.map((e) => e.song).toList(),
      0,
      targetIndex: index,
    );
  }

  @override
  Widget build(BuildContext context) {
    return myNavigator(
      key: forYouKey,
      visibleNotifier: forYouVisibleNotifier,
      pageViewBuilder: () => pageView(context),
      panelViewBuilder: () => panelView(context),
    );
  }

  Widget panelView(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        TitleBar(
          hintText: l10n.searchSongs,
          textController: TextEditingController(),
          scrollToTop: () {
            scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.linear,
            );
          },
        ),
        Expanded(child: content(context, horizontalPadding: 30)),
      ],
    );
  }

  Widget pageView(BuildContext context) {
    return SafeArea(
      child: content(context, horizontalPadding: 20),
    );
  }

  Widget content(BuildContext context, {required double horizontalPadding}) {
    final l10n = AppLocalizations.of(context);
    // nothing to draw from yet: a stream source may still be loading
    final empty = _songs.isEmpty && _artists.isEmpty;

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
                ImageIcon(forYouImage, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.forYou,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // same colour as the icons around it: the theme default for a
                // TextButton is the purple accent, which stands out badly here
                TextButton.icon(
                  onPressed: _refresh,
                  style: TextButton.styleFrom(
                    foregroundColor: iconColor.value,
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(l10n.refreshRecommendations),
                ),
              ],
            ),
          ),
        ),

        // nothing to work with yet: say so instead of showing an empty grid
        if (empty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text(
                  l10n.recommendEmpty,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: iconColor.value),
                ),
              ),
            ),
          )
        else ...[
          if (_artists.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: sectionHeader(
                context,
                l10n.recommendArtists,
                horizontalPadding,
              ),
            ),
            SliverToBoxAdapter(
              child: artistRow(horizontalPadding),
            ),
          ],
          if (_songs.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: sectionHeader(
                context,
                l10n.recommendSongs,
                horizontalPadding,
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                0,
                horizontalPadding,
                30,
              ),
              sliver: SliverList.builder(
                itemCount: _songs.length,
                itemBuilder: (context, index) => songTile(context, index),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget sectionHeader(
    BuildContext context,
    String text,
    double horizontalPadding,
  ) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        24,
        horizontalPadding,
        10,
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// A horizontally scrolling row of recommended artist cards.
  ///
  /// Card layout follows the platform-playlist style: cover, bold title, muted
  /// subtitle. The cover is kept modest (132px) because artist images from the
  /// metadata provider are only around 300px, so a larger render would just be
  /// an upscaled blur.
  ///
  /// A thin scrollbar sits under the row: without it there is no hint that more
  /// artists continue past the right edge.
  Widget artistRow(double horizontalPadding) {
    const cardWidth = 132.0;
    const coverSize = 132.0;

    return Scrollbar(
      controller: artistController,
      // horizontal, so it hugs the bottom of the row
      thickness: 4,
      radius: const Radius.circular(4),
      child: SizedBox(
        // cover + title + subtitle + room for the scrollbar
        height: coverSize + 62,
        child: ListView.separated(
          controller: artistController,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            0,
            horizontalPadding,
            12,
          ),
          itemCount: _artists.length,
          separatorBuilder: (_, _) => const SizedBox(width: 16),
          itemBuilder: (context, index) {
            final recommendation = _artists[index];
            final artist = recommendation.artist;

            return SizedBox(
              width: cardWidth,
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  layersManager.openArtistDetail(artist);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListenableBuilder(
                      listenable: Listenable.merge([
                        artist.picture.changeNotifier,
                      ]),
                      builder: (_, _) {
                        return CoverArtWidget(
                          size: coverSize,
                          borderRadius: 10,
                          picture: artist.picture,
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _artistSubtitle(recommendation),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: iconColor.value),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
  /// The muted second line of an artist card: how many songs are still
  /// unheard, or the artist's name when everything is known.
  String _artistSubtitle(ArtistRecommendation recommendation) {
    final l10n = AppLocalizations.of(context);
    final unexplored = recommendation.totalSongs - recommendation.playedSongs;
    if (unexplored > 0) {
      return l10n.reasonUnexplored(unexplored);
    }
    return l10n.reasonExplore;
  }

  Widget songTile(BuildContext context, int index) {
    final recommendation = _songs[index];
    final song = recommendation.song;
    final playing = currentSongNotifier.value?.id == song.id;

    return ListenableBuilder(
      listenable: Listenable.merge([
        currentSongNotifier,
        song.picture.changeNotifier,
      ]),
      builder: (context, _) {
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 5),
          leading: CoverArtWidget(
            size: 44,
            borderRadius: 5,
            picture: song.picture,
          ),
          title: Text(
            getTitle(song),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: playing ? iconColor.value : null,
            ),
          ),
          subtitle: Text(
            '${getArtist(song)} · ${getAlbum(song)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Text(
            song.duration == null ? '' : formatDuration(song.duration!),
            style: const TextStyle(fontSize: 12),
          ),
          onTap: () => _playFrom(index),
        );
      },
    );
  }
}
