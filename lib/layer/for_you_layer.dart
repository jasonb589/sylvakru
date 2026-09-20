import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/asset_images.dart';
import 'package:sylvakru/base/data/history.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/playlist.dart';
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

  /// Bumped by "refresh" to pick a different set from the same taste profile.
  int _seed = 0;

  Taste? _taste;
  List<SongRecommendation> _songs = const [];
  List<ArtistRecommendation> _artists = const [];

  /// Ids played during this session, so the list keeps offering something new.
  final Set<String> _playedThisSession = {};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuild();
    });

    // playing a song changes what should be recommended
    history.recentlyChangeNotifier.addListener(_onHistoryChanged);
    library.changeNotifier.addListener(_onHistoryChanged);
  }

  @override
  void dispose() {
    history.recentlyChangeNotifier.removeListener(_onHistoryChanged);
    library.changeNotifier.removeListener(_onHistoryChanged);
    scrollController.dispose();
    super.dispose();
  }

  void _onHistoryChanged() {
    if (!mounted) {
      return;
    }
    for (final song in history.recentlySongList.take(20)) {
      _playedThisSession.add(song.id);
    }
    _rebuild();
  }

  /// Ids of every favourited song, used to weight the taste profile.
  Set<String> get _favoriteIds {
    for (final playlist in playlistManager.playlists) {
      if (playlist.isFavorite) {
        return playlist.songList.map((e) => e.id).toSet();
      }
    }
    return const {};
  }

  void _rebuild() {
    final taste = Recommender.buildTaste(
      library.songList,
      favoriteIds: _favoriteIds,
    );

    setState(() {
      _taste = taste;
      _songs = Recommender.recommendSongs(
        songs: library.songList,
        taste: taste,
        playedRecently: _playedThisSession,
        favoriteIds: _favoriteIds,
        seed: _seed,
      );
      _artists = Recommender.recommendArtists(
        artists: artistAlbumManager.artistList,
        taste: taste,
      );
    });
  }

  void _refresh() {
    _seed++;
    _rebuild();
  }

  /// Plays the recommended songs starting at [index].
  void _playFrom(int index) {
    if (_songs.isEmpty) {
      return;
    }
    audioHandler.setPlayQueue(_songs.map((e) => e.song).toList(), index);
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
    final taste = _taste;

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
                ImageIcon(recentlyImage, size: 34),
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
                TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(l10n.refreshRecommendations),
                ),
              ],
            ),
          ),
        ),

        // nothing to work with yet: say so instead of showing an empty grid
        if (taste == null || taste.isEmpty)
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

  /// A horizontally scrolling row of recommended artists.
  Widget artistRow(double horizontalPadding) {
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        itemCount: _artists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 15),
        itemBuilder: (context, index) {
          final recommendation = _artists[index];
          final artist = recommendation.artist;

          return SizedBox(
            width: 130,
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
                    listenable: Listenable.merge([artist.picture.changeNotifier]),
                    builder: (_, _) {
                      return CoverArtWidget(
                        size: 130,
                        borderRadius: 10,
                        picture: artist.picture,
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  Text(
                    _artistReasonText(recommendation),
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
    );
  }

  String _artistReasonText(ArtistRecommendation recommendation) {
    final l10n = AppLocalizations.of(context);
    // an artist with unheard material is the most useful thing to say
    final unexplored = recommendation.totalSongs - recommendation.playedSongs;
    if (recommendation.reason == RecommendReason.favoriteArtist &&
        unexplored > 0) {
      return l10n.reasonUnexplored(unexplored);
    }
    return recommendReasonText(
      l10n,
      recommendation.reason,
      basis: recommendation.basis,
    );
  }

  Widget songTile(BuildContext context, int index) {
    final l10n = AppLocalizations.of(context);
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
            '${getArtist(song)} · ${recommendReasonText(l10n, recommendation.reason, basis: recommendation.basis)}',
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

/// Caption explaining why something was recommended.
String recommendReasonText(
  AppLocalizations l10n,
  RecommendReason reason, {
  String? basis,
}) {
  switch (reason) {
    case RecommendReason.favoriteArtist:
      return basis == null
          ? l10n.reasonExplore
          : l10n.reasonFavoriteArtist(basis);
    case RecommendReason.similarGenre:
      return basis == null
          ? l10n.reasonExplore
          : l10n.reasonSimilarGenre(basis);
    case RecommendReason.rediscover:
      return l10n.reasonRediscover;
    case RecommendReason.explore:
      return l10n.reasonExplore;
  }
}
