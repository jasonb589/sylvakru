import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/data/history.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/playlist.dart';
import 'package:sylvakru/base/data/recommend.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/utils/common_utils.dart';
import 'package:sylvakru/base/utils/media_query.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:sylvakru/base/utils/zoom_page_route.dart';
import 'package:sylvakru/base/widgets/cover_art_widget.dart';
import 'package:sylvakru/base/widgets/scale_widget.dart';
import 'package:sylvakru/big_picture_view/panels/big_single_artist_panel.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';

/// Big picture "For You" tab: recommended artists and songs.
///
/// Uses the same local taste model as the desktop page, so no server support is
/// required.
class BigForYouPanel extends StatefulWidget {
  const BigForYouPanel({super.key});

  @override
  State<StatefulWidget> createState() => _BigForYouPanelState();
}

class _BigForYouPanelState extends State<BigForYouPanel> {
  final verticalController = ScrollController();
  final artistController = ScrollController();

  int _seed = 0;
  Taste? _taste;
  List<SongRecommendation> _songs = const [];
  List<ArtistRecommendation> _artists = const [];
  final Set<String> _playedThisSession = {};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuild();
    });

    history.recentlyChangeNotifier.addListener(_onHistoryChanged);
    library.changeNotifier.addListener(_onHistoryChanged);
  }

  @override
  void dispose() {
    history.recentlyChangeNotifier.removeListener(_onHistoryChanged);
    library.changeNotifier.removeListener(_onHistoryChanged);
    verticalController.dispose();
    artistController.dispose();
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

  /// Plays the recommended songs starting at [index].
  ///
  /// The second positional argument is the play mode, not the index, so the
  /// target has to be passed by name.
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
    final l10n = AppLocalizations.of(context);
    final taste = _taste;

    return ListView(
      controller: verticalController,
      padding: EdgeInsets.symmetric(vertical: 75 + getTopOffset(context)),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isTooNarrow(context) ? 20 : 40,
          ),
          child: Row(
            children: [
              Text(
                l10n.forYou,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  _seed++;
                  _rebuild();
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(l10n.refreshRecommendations),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        if (taste == null || taste.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
            child: Center(
              child: Text(
                l10n.recommendEmpty,
                textAlign: TextAlign.center,
                style: TextStyle(color: iconColor.value),
              ),
            ),
          )
        else ...[
          if (_artists.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isTooNarrow(context) ? 20 : 40,
              ),
              child: Text(
                l10n.recommendArtists,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // cover + title + subtitle + room for the scrollbar
            SizedBox(height: 132 + 76, child: artistRow()),
          ],
          if (_songs.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isTooNarrow(context) ? 20 : 40,
              ),
              child: Text(
                l10n.recommendSongs,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < _songs.length; i++)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isTooNarrow(context) ? 20 : 40,
                ),
                child: songTile(context, i),
              ),
            const SizedBox(height: 40),
          ],
        ],
      ],
    );
  }

  /// Recommended artist cards.
  ///
  /// Cover is 132px rather than full size: the metadata provider's artist
  /// images are only around 300px, so rendering them larger just upscales a
  /// blur. A thin scrollbar under the row shows that more continue off-screen.
  Widget artistRow() {
    const coverSize = 132.0;
    final sidePadding = isTooNarrow(context) ? 20.0 : 40.0;

    return Scrollbar(
      controller: artistController,
      thickness: 4,
      radius: const Radius.circular(4),
      child: ListView.separated(
        controller: artistController,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(sidePadding, 0, sidePadding, 12),
        itemCount: _artists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final recommendation = _artists[index];
          final artist = recommendation.artist;

          return ScaleWidget(
            onTap: () {
              Navigator.of(context).push(
                ZoomPageRoute(
                  builder: (context) => BigSingleArtistPanel(artist: artist),
                ),
              );
            },
            child: SizedBox(
              width: coverSize,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 15),
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
                  SizedBox(
                    width: coverSize,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        artist.name,
                        style: const TextStyle(overflow: TextOverflow.ellipsis),
                      ),
                      subtitle: Text(
                        _artistReasonText(recommendation),
                        style: const TextStyle(
                          fontSize: 11,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      visualDensity: const VisualDensity(vertical: -4),
                    ),
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
    final unexplored = recommendation.totalSongs - recommendation.playedSongs;
    if (recommendation.reason == RecommendReason.favoriteArtist &&
        unexplored > 0) {
      return l10n.reasonUnexplored(unexplored);
    }
    return bigRecommendReasonText(
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
          contentPadding: EdgeInsets.zero,
          leading: CoverArtWidget(
            size: 45,
            borderRadius: 5,
            picture: song.picture,
          ),
          title: Text(
            getTitle(song),
            style: TextStyle(
              overflow: TextOverflow.ellipsis,
              color: playing ? iconColor.value : null,
            ),
          ),
          subtitle: Text(
            '${getArtist(song)} · ${bigRecommendReasonText(l10n, recommendation.reason, basis: recommendation.basis)}',
            style: const TextStyle(fontSize: 12, overflow: TextOverflow.ellipsis),
          ),
          trailing: Text(formatDuration(getDuration(song))),
          visualDensity: const VisualDensity(vertical: -4),
          onTap: () => _playFrom(index),
        );
      },
    );
  }
}

/// Caption explaining why something was recommended (big picture styling).
String bigRecommendReasonText(
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
