import 'dart:math';

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smooth_corner/smooth_corner.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/data/history.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/playlist.dart';
import 'package:sylvakru/base/data/recommend.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/base/utils/media_query.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:sylvakru/base/widgets/cover_art_widget.dart';
import 'package:sylvakru/base/widgets/my_navigator.dart';
import 'package:sylvakru/base/widgets/my_scaffold.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/landscape_view/title_bar.dart';
import 'package:sylvakru/layer/layers_manager.dart';

part '../landscape_view/panels/home_panel.dart';
part '../portrait_view/pages/home_page.dart';

final GlobalKey<NavigatorState> homeKey = GlobalKey();
final homeVisibleNotifier = ValueNotifier(true);

class HomeLayer extends StatefulWidget {
  const HomeLayer({super.key});

  @override
  State<StatefulWidget> createState() => HomeLayerState();
}

class HomeLayerState extends State<HomeLayer> {
  final albumsSC = ScrollController();
  final frequentlySC = ScrollController();
  final recentlySC = ScrollController();
  final playlistsSC = ScrollController();
  final recommendSongsSC = ScrollController();
  final recommendArtistsSC = ScrollController();

  final albumsDisplayIconNotifier = ValueNotifier(false);
  final frequentlyDisplayIconNotifier = ValueNotifier(false);
  final recentlyDisplayIconNotifier = ValueNotifier(false);
  final playlistsDisplayIconNotifier = ValueNotifier(false);
  final recommendSongsDisplayIconNotifier = ValueNotifier(false);
  final recommendArtistsDisplayIconNotifier = ValueNotifier(false);

  final albumsChangeNotifier = ValueNotifier(0);
  final frequentlyChangeNotifier = ValueNotifier(0);
  final recentlyChangeNotifier = ValueNotifier(0);
  final playlistsChangeNotifier = ValueNotifier(0);
  final recommendSongsChangeNotifier = ValueNotifier(0);
  final recommendArtistsChangeNotifier = ValueNotifier(0);

  /// Picks the random draw shown in the "For You" section.
  ///
  /// Starts from the clock so reopening the app offers a different set, and
  /// "Refresh" bumps it to move on from the current one.
  int recommendSeed = DateTime.now().millisecondsSinceEpoch;

  List<SongRecommendation> recommendedSongs = const [];
  List<ArtistRecommendation> recommendedArtists = const [];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildRecommendations();
    });

    // stream sources have not fetched their artists yet at this point
    _ensureArtists();
  }

  @override
  void dispose() {
    albumsSC.dispose();
    frequentlySC.dispose();
    recentlySC.dispose();
    playlistsSC.dispose();
    recommendSongsSC.dispose();
    recommendArtistsSC.dispose();
    super.dispose();
  }

  /// Loads the artist list if the source has not provided it yet.
  ///
  /// Stream sources only fetch their artists when the artist page is opened,
  /// so without this the recommended-artists row would stay empty until the
  /// listener happened to visit that page first.
  Future<void> _ensureArtists() async {
    if (artistAlbumManager.artistList.isNotEmpty || !isStreamSource) {
      return;
    }
    await artistAlbumManager.loadArtists();
    if (mounted) {
      _rebuildRecommendations();
    }
  }

  void _rebuildRecommendations() {
    if (!mounted) {
      return;
    }
    setState(() {
      recommendedSongs = Recommender.randomSongs(
        songs: library.songList,
        seed: recommendSeed,
      );
      recommendedArtists = Recommender.randomArtists(
        artists: artistAlbumManager.artistList,
        seed: recommendSeed,
      );
    });
  }

  void _refreshRecommendations() {
    recommendSeed++;
    _rebuildRecommendations();
  }

  @override
  Widget build(BuildContext context) {
    return myNavigator(
      key: homeKey,
      visibleNotifier: homeVisibleNotifier,
      pageViewBuilder: () => pageView(context),
      panelViewBuilder: () => panelView(context),
    );
  }

  Widget content(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    double extraSize = max(0, (shortestSide - 750) * 0.2);
    return ListView(
      children: [
        Row(
          mainAxisSize: .min,
          children: [
            SizedBox(width: 20),
            GestureDetector(
              onTap: () {
                layersManager.switchRootLayer('albums');
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Row(
                  children: [
                    Text(
                      l10n.albums,
                      style: .new(fontWeight: .bold, fontSize: 20),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 10),

        mouseRegionForScroll(
          child: SizedBox(
            height: 180 + extraSize,
            child: ValueListenableBuilder(
              valueListenable: artistAlbumManager.updateNotifier,
              builder: (context, value, child) {
                return ListView.separated(
                  controller: albumsSC,
                  scrollDirection: .horizontal,
                  itemCount: artistAlbumManager.albumList.length + 1,
                  separatorBuilder: (context, index) {
                    return SizedBox(width: 15);
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return SizedBox(width: 5);
                    }
                    index--;
                    final album = artistAlbumManager.albumList[index];
                    return Column(
                      children: [
                        GestureDetector(
                          onTap: () {
                            layersManager.pushDetail('home', album);
                          },
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Hero(
                              tag: '${album.picture.id}home${album.name}',
                              transitionOnUserGestures: true,
                              child: CoverArtWidget(
                                size: 150 + extraSize,
                                borderRadius: 15,
                                picture: album.picture,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 5),
                        SizedBox(
                          width: 140 + extraSize,
                          child: Text(
                            album.name,
                            style: .new(overflow: .ellipsis, fontSize: 15),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          scrollController: albumsSC,
          displayIconNotifier: albumsDisplayIconNotifier,
          changeNotifier: albumsChangeNotifier,
          iconTop: 55 + extraSize / 2,
        ),

        SizedBox(height: 15),

        Row(
          mainAxisSize: .min,
          children: [
            SizedBox(width: 20),
            GestureDetector(
              onTap: () {
                layersManager.switchRootLayer('frequently');
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Row(
                  children: [
                    Text(
                      l10n.frequently,
                      style: .new(fontWeight: .bold, fontSize: 20),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 10),

        mouseRegionForScroll(
          child: ValueListenableBuilder(
            valueListenable: history.frequentlyChangeNotifier,
            builder: (context, value, child) {
              return songListView(history.frequentlySongList, frequentlySC);
            },
          ),
          scrollController: frequentlySC,
          displayIconNotifier: frequentlyDisplayIconNotifier,
          changeNotifier: frequentlyChangeNotifier,
          iconTop: 67,
        ),

        SizedBox(height: 15),

        Row(
          mainAxisSize: .min,
          children: [
            SizedBox(width: 20),
            GestureDetector(
              onTap: () {
                layersManager.switchRootLayer('recently');
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Row(
                  children: [
                    Text(
                      l10n.recently,
                      style: .new(fontWeight: .bold, fontSize: 20),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 10),

        mouseRegionForScroll(
          child: ValueListenableBuilder(
            valueListenable: history.recentlyChangeNotifier,
            builder: (context, value, child) {
              return songListView(history.recentlySongList, recentlySC);
            },
          ),
          scrollController: recentlySC,
          displayIconNotifier: recentlyDisplayIconNotifier,
          changeNotifier: frequentlyChangeNotifier,
          iconTop: 67,
        ),

        SizedBox(height: 15),

        Row(
          mainAxisSize: .min,
          children: [
            SizedBox(width: 20),
            GestureDetector(
              onTap: () {
                layersManager.switchRootLayer('playlists');
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Row(
                  children: [
                    Text(
                      l10n.playlists,
                      style: .new(fontWeight: .bold, fontSize: 20),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 10),

        mouseRegionForScroll(
          child: SizedBox(
            height: 180 + extraSize,
            child: ValueListenableBuilder(
              valueListenable: playlistManager.updateNotifier,
              builder: (context, value, child) {
                return ListView.separated(
                  controller: playlistsSC,
                  scrollDirection: .horizontal,
                  itemCount: playlistManager.playlists.length + 1,
                  separatorBuilder: (context, index) {
                    return SizedBox(width: 15);
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return SizedBox(width: 5);
                    }
                    index--;
                    final playlist = playlistManager.playlists[index];
                    return ValueListenableBuilder(
                      valueListenable: playlist.changeNotifier,
                      builder: (context, value, child) {
                        return Column(
                          children: [
                            GestureDetector(
                              onTap: () {
                                layersManager.pushDetail('home', playlist);
                              },
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Hero(
                                  tag:
                                      '${playlist.picture?.id ?? ''}home${playlist.isFavorite ? l10n.favorites : playlist.name}',
                                  transitionOnUserGestures: true,
                                  child: CoverArtWidget(
                                    size: 150 + extraSize,
                                    borderRadius: 15,
                                    picture: playlist.picture,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 5),
                            SizedBox(
                              width: 140 + extraSize,
                              child: Text(
                                playlist.isFavorite
                                    ? l10n.favorites
                                    : playlist.name,
                                style: .new(overflow: .ellipsis, fontSize: 15),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          scrollController: playlistsSC,
          displayIconNotifier: playlistsDisplayIconNotifier,
          changeNotifier: playlistsChangeNotifier,
          iconTop: 55 + extraSize / 2,
        ),
        SizedBox(height: 15),


        // "For You": a straight random draw from the library, refreshed by the
        // button on the right. It is deliberately not a taste model, so the
        // only thing that changes the set is the seed.
        Row(
          mainAxisSize: .min,
          children: [
            SizedBox(width: 20),
            GestureDetector(
              onTap: () {
                layersManager.switchRootLayer('forYou');
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Row(
                  children: [
                    Text(
                      l10n.forYou,
                      style: .new(fontWeight: .bold, fontSize: 20),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 20),
                  ],
                ),
              ),
            ),
            Spacer(),
            TextButton.icon(
              onPressed: _refreshRecommendations,
              style: TextButton.styleFrom(foregroundColor: iconColor.value),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n.refreshRecommendations),
            ),
            SizedBox(width: 20),
          ],
        ),
        SizedBox(height: 10),

        // nothing to draw from yet: a stream source may still be loading
        if (recommendedSongs.isEmpty && recommendedArtists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Text(
              l10n.recommendEmpty,
              style: .new(fontSize: 13, color: iconColor.value),
            ),
          )
        else ...[
          if (recommendedArtists.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 8),
              child: Text(
                l10n.recommendArtists,
                style: .new(fontWeight: .bold, fontSize: 15),
              ),
            ),
            mouseRegionForScroll(
              child: SizedBox(
                height: 194,
                child: ListView.separated(
                  controller: recommendArtistsSC,
                  scrollDirection: .horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: recommendedArtists.length,
                  separatorBuilder: (context, index) {
                    return SizedBox(width: 16);
                  },
                  itemBuilder: (context, index) {
                    final artist = recommendedArtists[index].artist;
                    return SizedBox(
                      width: 132,
                      child: GestureDetector(
                        onTap: () {
                          layersManager.openArtistDetail(artist);
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Column(
                            crossAxisAlignment: .start,
                            children: [
                              ListenableBuilder(
                                listenable: Listenable.merge([
                                  artist.picture.changeNotifier,
                                ]),
                                builder: (context, child) {
                                  return CoverArtWidget(
                                    size: 132,
                                    borderRadius: 10,
                                    picture: artist.picture,
                                  );
                                },
                              ),
                              SizedBox(height: 8),
                              Text(
                                artist.name,
                                style: .new(
                                  fontWeight: .bold,
                                  fontSize: 14,
                                  overflow: .ellipsis,
                                ),
                              ),
                              SizedBox(height: 1),
                              Text(
                                _artistSubtitle(recommendedArtists[index]),
                                style: .new(
                                  fontSize: 11,
                                  color: iconColor.value,
                                  overflow: .ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              scrollController: recommendArtistsSC,
              displayIconNotifier: recommendArtistsDisplayIconNotifier,
              changeNotifier: recommendArtistsChangeNotifier,
              iconTop: 66,
            ),
            SizedBox(height: 15),
          ],
          if (recommendedSongs.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 8),
              child: Text(
                l10n.recommendSongs,
                style: .new(fontWeight: .bold, fontSize: 15),
              ),
            ),
            mouseRegionForScroll(
              child: songListView(
                recommendedSongs.map((recommendation) {
                  return recommendation.song;
                }).toList(),
                recommendSongsSC,
              ),
              scrollController: recommendSongsSC,
              displayIconNotifier: recommendSongsDisplayIconNotifier,
              changeNotifier: recommendSongsChangeNotifier,
              iconTop: 67,
            ),
            SizedBox(height: 15),
          ],
        ],
        if (isTooNarrow(context)) SizedBox(height: 60),
      ],
    );
  }

  Widget songListView(
    List<MyAudioMetadata> songList,
    ScrollController scrollController,
  ) {
    return SizedBox(
      height: 180,
      child: MouseRegion(
        child: ListView.builder(
          padding: .zero,
          controller: scrollController,
          scrollDirection: .horizontal,
          itemCount: songList.length ~/ 3 + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return SizedBox(width: 15);
            }
            index -= 1;
            return SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: .min,
                children: List.generate(min(3, songList.length - index * 3), (
                  j,
                ) {
                  final song = songList[index * 3 + j];
                  return InkWell(
                    onTap: isMobile
                        ? () {
                            audioHandler.setPlayQueue(
                              songList,
                              0,
                              targetIndex: index * 3 + j,
                            );
                          }
                        : null,
                    onDoubleTap: isMobile
                        ? null
                        : () {
                            audioHandler.setPlayQueue(
                              songList,
                              0,
                              targetIndex: index * 3 + j,
                            );
                          },
                    customBorder: SmoothRectangleBorder(
                      smoothness: 1,
                      borderRadius: .circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          SizedBox(width: 5),
                          CoverArtWidget(
                            size: 50,
                            borderRadius: 5,
                            picture: song.picture,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: .start,
                              children: [
                                Text(
                                  getTitle(song),
                                  style: .new(
                                    fontSize: 15,
                                    overflow: .ellipsis,
                                  ),
                                ),
                                Text(
                                  '${getArtist(song)} - ${getAlbum(song)}',
                                  style: .new(
                                    fontSize: 12,
                                    overflow: .ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              showSongOptions(
                                context: context,
                                song: song,
                                includeGoToArtist: true,
                                includeGoToAlbum: true,
                                useDialog: !isTooNarrow(context),
                              );
                            },
                            icon: Icon(Icons.more_vert_rounded, size: 20),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget mouseRegionForScroll({
    required Widget child,
    required ScrollController scrollController,
    required ValueNotifier<bool> displayIconNotifier,
    required ValueNotifier<int> changeNotifier,
    required double iconTop,
  }) {
    bool isScrolling = false;
    final scrollDistance = MediaQuery.sizeOf(context).width / 2;
    return MouseRegion(
      onEnter: (event) {
        displayIconNotifier.value = true;
      },
      onExit: (event) {
        displayIconNotifier.value = false;
      },
      child: Stack(
        children: [
          child,
          ListenableBuilder(
            listenable: Listenable.merge([displayIconNotifier, changeNotifier]),
            builder: (context, child) {
              if (isMobile ||
                  !displayIconNotifier.value ||
                  scrollController.position.pixels == 0) {
                return SizedBox.shrink();
              }
              return Positioned(
                top: iconTop,
                left: 20,
                child: Center(
                  child: ValueListenableBuilder(
                    valueListenable: iconColor.valueNotifier,
                    builder: (context, value, child) {
                      return GlassContainer(
                        settings: LiquidGlassSettings(
                          glassColor: glassColor.value,
                        ),
                        shape: const LiquidRoundedSuperellipse(
                          borderRadius: 30,
                        ),
                        child: IconButton(
                          color: value,
                          onPressed: () async {
                            if (isScrolling) {
                              return;
                            }
                            isScrolling = true;
                            await scrollController.animateTo(
                              (scrollController.offset - scrollDistance).clamp(
                                0.0,
                                scrollController.position.maxScrollExtent,
                              ),
                              duration: Duration(milliseconds: 500),
                              curve: Curves.easeInOutCubic,
                            );
                            isScrolling = false;
                            changeNotifier.value++;
                          },
                          icon: Icon(Icons.arrow_back_ios_new_rounded),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),

          ListenableBuilder(
            listenable: Listenable.merge([displayIconNotifier, changeNotifier]),
            builder: (context, child) {
              if (isMobile ||
                  !scrollController.position.hasContentDimensions ||
                  !displayIconNotifier.value ||
                  scrollController.position.extentAfter <= 0) {
                return SizedBox.shrink();
              }
              return Positioned(
                top: iconTop,
                right: 20,
                child: Center(
                  child: ValueListenableBuilder(
                    valueListenable: iconColor.valueNotifier,
                    builder: (context, value, child) {
                      return GlassContainer(
                        settings: LiquidGlassSettings(
                          glassColor: glassColor.value,
                        ),
                        shape: const LiquidRoundedSuperellipse(
                          borderRadius: 30,
                        ),
                        child: IconButton(
                          color: value,
                          onPressed: () async {
                            if (isScrolling) {
                              return;
                            }
                            isScrolling = true;

                            await scrollController.animateTo(
                              (scrollController.offset + scrollDistance).clamp(
                                0.0,
                                scrollController.position.maxScrollExtent,
                              ),
                              duration: Duration(milliseconds: 500),
                              curve: Curves.easeInOutCubic,
                            );

                            isScrolling = false;
                            changeNotifier.value++;
                          },
                          icon: Icon(Icons.arrow_forward_ios_rounded),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// The muted second line of a recommended artist card: how many songs are
  /// still unheard, or an invitation to explore when everything is known.
  String _artistSubtitle(ArtistRecommendation recommendation) {
    final l10n = AppLocalizations.of(context);
    final unexplored =
        recommendation.totalSongs - recommendation.playedSongs;
    if (unexplored > 0) {
      return l10n.reasonUnexplored(unexplored);
    }
    return l10n.reasonExplore;
  }
}
