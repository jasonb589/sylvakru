import 'dart:async';
import 'package:sylvakru/base/design/app_tokens.dart';
import 'package:sylvakru/base/design/cover_backdrop.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gamepads/flutter_gamepads.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smooth_corner/smooth_corner.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/asset_images.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/data/history.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/base/services/my_window_listener.dart';
import 'package:sylvakru/base/utils/media_query.dart';
import 'package:sylvakru/base/widgets/big_play_bar.dart';
import 'package:sylvakru/base/widgets/cover_art_widget.dart';
import 'package:sylvakru/base/widgets/scale_widget.dart';
import 'package:sylvakru/big_picture_view/panels/big_albums_panel.dart';
import 'package:sylvakru/big_picture_view/panels/big_artists_panel.dart';
import 'package:sylvakru/big_picture_view/panels/big_folders_panel.dart';
import 'package:sylvakru/big_picture_view/panels/big_home_panel.dart';
import 'package:sylvakru/big_picture_view/panels/big_playlists_panel.dart';
import 'package:sylvakru/big_picture_view/panels/big_for_you_panel.dart';
import 'package:sylvakru/big_picture_view/panels/big_frequently_panel.dart';
import 'package:sylvakru/big_picture_view/panels/big_recently_added_panel.dart';
import 'package:sylvakru/big_picture_view/panels/big_recently_panel.dart';
import 'package:sylvakru/big_picture_view/panels/big_settings_panel.dart';
import 'package:sylvakru/big_picture_view/panels/big_songs_panel.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/layer/layers_manager.dart';
import 'package:window_manager/window_manager.dart';

/// The tabs of the big picture view, in the order they are shown.
///
/// The panels, the tab labels and the bottom bar's "…" action are all read off
/// this list, because they used to be three lists kept in step by hand and one
/// of them was left behind: when For You was inserted second, the "…" action
/// still answered the numbering from before it, so For You offered the whole
/// library's song menu and Albums had no button at all.
enum BigPictureTab {
  home,
  forYou,
  songs,
  artists,
  albums,
  folders,
  frequently,
  recently,
  recentlyAdded,
  playlists,
  settings;

  /// The label on this tab.
  String label(AppLocalizations l10n) {
    switch (this) {
      case BigPictureTab.home:
        return l10n.home;
      case BigPictureTab.forYou:
        return l10n.forYou;
      case BigPictureTab.songs:
        return l10n.songs;
      case BigPictureTab.artists:
        return l10n.artists;
      case BigPictureTab.albums:
        return l10n.albums;
      case BigPictureTab.folders:
        return l10n.folders;
      case BigPictureTab.frequently:
        return l10n.frequently;
      case BigPictureTab.recently:
        return l10n.recently;
      case BigPictureTab.recentlyAdded:
        return l10n.recentlyAdded;
      case BigPictureTab.playlists:
        return l10n.playlists;
      case BigPictureTab.settings:
        return l10n.settings;
    }
  }
}

/// The panel each tab shows, in the same order as [BigPictureTab].
const bigPicturePanels = <Widget>[
  BigHomePanel(),
  BigForYouPanel(),
  BigSongsPanel(),
  BigArtistsPanel(),
  BigAlbumsPanel(),
  BigFoldersPanel(),
  BigFrequentlyPanel(),
  BigRecentlyPanel(),
  BigRecentlyAddedPanel(),
  BigPlaylistsPanel(),
  BigSettingsPanel(),
];

/// What the bottom bar's "…" button offers on a tab, if anything.
enum BigPictureMenu { none, songs, artists, albums, frequently, recently }

/// The menu [tab] has for a library that comes from [source].
///
/// Only a panel that *is* one list has that list's own menu. The panels that
/// gather their own — For You (which has a refresh of its own), folders, the new
/// arrivals, the playlists — and the settings have no such list, and the home
/// panel is not a list at all. A stream source keeps no play history, so the
/// frequently and recently panels have nothing to act on there either.
BigPictureMenu bigPictureMenuFor(BigPictureTab tab, SourceType source) {
  switch (tab) {
    case BigPictureTab.home:
    case BigPictureTab.forYou:
    case BigPictureTab.folders:
    case BigPictureTab.recentlyAdded:
    case BigPictureTab.playlists:
    case BigPictureTab.settings:
      return BigPictureMenu.none;
    case BigPictureTab.songs:
      return BigPictureMenu.songs;
    case BigPictureTab.artists:
      return BigPictureMenu.artists;
    case BigPictureTab.albums:
      return BigPictureMenu.albums;
    case BigPictureTab.frequently:
      return source == .navidrome
          ? BigPictureMenu.none
          : BigPictureMenu.frequently;
    case BigPictureTab.recently:
      return source == .navidrome
          ? BigPictureMenu.none
          : BigPictureMenu.recently;
  }
}

class BigPictureView extends StatefulWidget {
  const BigPictureView({super.key});

  @override
  State<StatefulWidget> createState() => _BigPictureViewState();
}

class _BigPictureViewState extends State<BigPictureView> {
  final _pageController = PageController();
  final _currentIndexNotifier = ValueNotifier(0);
  final topNode = FocusScopeNode();
  final pageViewNode = FocusScopeNode();
  final bottomNode = FocusScopeNode();

  @override
  void dispose() {
    topNode.dispose();
    pageViewNode.dispose();
    bottomNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: mainPageThemeNotifier,
      builder: (context, value, child) {
        return Stack(
          fit: StackFit.expand,
          children: [
            ListenableBuilder(
              listenable: Listenable.merge([currentSongNotifier]),
              builder: (context, _) {
                if (mainPageThemeNotifier.value != .vivid) {
                  return SizedBox.shrink();
                }
                return CoverArtWidget(
                  picture: currentSongNotifier.value?.picture,
                  color: currentCoverArtColor,
                );
              },
            ),
            ListenableBuilder(
              listenable: Listenable.merge([currentSongNotifier]),
              builder: (context, child) {
                if (mainPageThemeNotifier.value != .vivid) {
                  return SizedBox.shrink();
                }

                return CoverBackdrop(colour: currentCoverArtColor);
              },
            ),

            Material(
              color: panelColor.value,
              child: KeyboardListener(
                focusNode: pageViewNode,
                onKeyEvent: (value) {
                  if (value is KeyUpEvent) {
                    return;
                  }
                  if (value.logicalKey == .goBack ||
                      value.logicalKey == .keyT) {
                    topNode.requestFocus();
                  }
                },
                child: GamepadInterceptor(
                  onBeforeIntent: (activator, intent) {
                    if (intent is DismissIntent) {
                      topNode.requestFocus();
                      return false;
                    }
                    return true;
                  },
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (value) {
                      _currentIndexNotifier.value = value;
                    },
                    children: bigPicturePanels,
                  ),
                ),
              ),
            ),

            topBar(context),
            bottomBar(context),
          ],
        );
      },
    );
  }

  Widget topBar(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tabs = [for (final tab in BigPictureTab.values) tab.label(l10n)];

    final windowsControl = isTV
        ? null
        : Row(
            children: [
              if (!isFullScreenNotifier.value)
                IconButton(
                  onPressed: () async {
                    if (!await showConfirmDialog(context, l10n.switchMode)) {
                      return;
                    }
                    await Future.delayed(Duration(milliseconds: 250));
                    viewModeNotifier.value = .normal;
                    layersManager.switchRootLayer('songs');
                  },
                  icon: ImageIcon(bigPictureModeImage),
                ),

              if (!isMobile && !isFullScreenNotifier.value) ...[
                IconButton(
                  onPressed: () {
                    windowManager.minimize();
                  },
                  icon: ImageIcon(minimizeImage),
                ),
                IconButton(
                  onPressed: () async {
                    isMaximizedNotifier.value
                        ? windowManager.unmaximize()
                        : windowManager.maximize();
                  },
                  icon: ImageIcon(
                    isMaximizedNotifier.value ? unmaximizeImage : maximizeImage,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    windowManager.close();
                  },
                  icon: ImageIcon(closeImage),
                ),
              ],
            ],
          );

    return Positioned(
      top: getTopOffset(context),
      left: 0,
      right: 0,

      child: KeyboardListener(
        focusNode: topNode,
        onKeyEvent: (value) {
          if (value is KeyUpEvent) {
            return;
          }
          if (value.logicalKey == .arrowDown) {
            pageViewNode.requestFocus();
          } else if (value.logicalKey == .arrowUp) {
            bottomNode.requestFocus();
          }
        },
        child: GamepadInterceptor(
          onBeforeIntent: (activator, intent) {
            if (intent is DirectionalFocusIntent) {
              if (intent.direction == .down) {
                pageViewNode.requestFocus();
              } else if (intent.direction == .up) {
                bottomNode.requestFocus();
              }
            }
            return true;
          },
          child: SizedBox(
            height: 75,
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: Material(
                    color: Colors.transparent,
                    child: Row(
                      children: [
                        SizedBox(width: isMobile ? 10 : 20),

                        if (!isMobile && !isMaximizedNotifier.value)
                          GlassContainer(
                            settings: LiquidGlassSettings(
                              glassColor: glassColor.value,
                            ),
                            shape: const LiquidRoundedSuperellipse(
                              borderRadius: 30,
                            ),
                            child: IconButton(
                              onPressed: () async {
                                if (isFullScreenNotifier.value) {
                                  isFullScreenNotifier.value = false;
                                  await windowManager.setFullScreen(false);
                                } else {
                                  isFullScreenNotifier.value = true;
                                  await windowManager.setFullScreen(true);
                                }
                              },
                              icon: ImageIcon(
                                isFullScreenNotifier.value
                                    ? fullscreenExitImage
                                    : fullscreenImage,
                              ),
                            ),
                          ),
                        // Expanded(
                        //   child: GlassContainer(
                        //     settings: LiquidGlassSettings(
                        //       glassColor: glassColor.value,
                        //     ),
                        //     shape: const LiquidRoundedSuperellipse(
                        //       borderRadius: 30,
                        //     ),
                        //     child: TextField(
                        //       decoration: InputDecoration(
                        //         prefixIcon: Icon(Icons.search),
                        //         suffixIcon: IconButton(
                        //           onPressed: () {},
                        //           icon: const Icon(Icons.clear),
                        //           padding: EdgeInsets.zero,
                        //         ),
                        //         filled: true,
                        //         fillColor: Colors.transparent,
                        //         contentPadding: EdgeInsets.zero,
                        //         isDense: true,
                        //         border: OutlineInputBorder(
                        //           borderSide: BorderSide.none,
                        //         ),
                        //       ),
                        //     ),
                        //   ),
                        // ),
                        SizedBox(width: 30),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GlassContainer(
                        settings: LiquidGlassSettings(
                          glassColor: glassColor.value,
                        ),
                        shape: const LiquidRoundedSuperellipse(
                          borderRadius: 30,
                        ),
                        clipBehavior: .antiAlias,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth,
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 15,
                                vertical: 7.5,
                              ),
                              child: Row(
                                mainAxisAlignment: .center,
                                children: List.generate(tabs.length, (index) {
                                  return ValueListenableBuilder(
                                    valueListenable: _currentIndexNotifier,
                                    builder: (context, value, child) {
                                      return ValueListenableBuilder(
                                        valueListenable:
                                            selectedItemColor.valueNotifier,
                                        builder: (context, colorValue, child) {
                                          return Material(
                                            shape: SmoothRectangleBorder(
                                              smoothness: 1,
                                              borderRadius: .circular(25),
                                            ),
                                            color: index == value
                                                ? colorValue
                                                : Colors.transparent,
                                            clipBehavior: .antiAlias,
                                            child: child,
                                          );
                                        },
                                        child: ScaleWidget(
                                          onTap: () {
                                            _pageController.animateToPage(
                                              index,
                                              duration: AppDuration.calm,
                                              curve: AppCurve.enter,
                                            );
                                          },
                                          needFocusColor: true,
                                          autoFocus: index == 0,
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 15,
                                              vertical: isMobile ? 4 : 0,
                                            ),
                                            child: Text(
                                              tabs[index],
                                              style: TextStyle(
                                                fontSize: 18.5,
                                                fontWeight: FontWeight.bold,
                                                color: index == value
                                                    ? textColor.value
                                                    : textColor.value.withAlpha(
                                                        128,
                                                      ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                }),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                Expanded(
                  flex: 1,
                  child: isTV
                      ? SizedBox.shrink()
                      : Row(
                          mainAxisAlignment: .end,

                          children: [
                            GlassContainer(
                              settings: LiquidGlassSettings(
                                glassColor: glassColor.value,
                              ),
                              shape: const LiquidRoundedSuperellipse(
                                borderRadius: 30,
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal:
                                      windowsControl!.children.length > 1
                                      ? 10.0
                                      : 0,
                                ),
                                child: windowsControl,
                              ),
                            ),
                            SizedBox(width: isMobile ? 10 : 20),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget bottomBar(BuildContext context) {
    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      child: KeyboardListener(
        focusNode: bottomNode,
        onKeyEvent: (value) {
          if (value is KeyUpEvent) {
            return;
          }

          if (value.logicalKey == .arrowDown) {
            topNode.requestFocus();
          } else if (value.logicalKey == .arrowUp) {
            pageViewNode.requestFocus();
          }
        },
        child: GamepadInterceptor(
          onBeforeIntent: (activator, intent) {
            if (intent is DirectionalFocusIntent) {
              if (intent.direction == .down) {
                topNode.requestFocus();
                return false;
              } else if (intent.direction == .up) {
                pageViewNode.requestFocus();
                return false;
              }
            } else if (intent is DismissIntent) {
              topNode.requestFocus();
              return false;
            }
            return true;
          },
          child: Row(
            mainAxisAlignment: .center,
            children: [
              Expanded(flex: 1, child: SizedBox.shrink()),
              Expanded(flex: 3, child: Center(child: BigPlayBar())),
              Expanded(
                flex: 1,
                child: ValueListenableBuilder(
                  valueListenable: _currentIndexNotifier,
                  builder: (context, value, child) {
                    // The tab is named rather than counted: the panel, the tab
                    // and this button all come off [BigPictureTab].
                    final menu = bigPictureMenuFor(
                      BigPictureTab.values[value],
                      sourceType,
                    );
                    if (menu == BigPictureMenu.none) {
                      return SizedBox.shrink();
                    }
                    return Row(
                      mainAxisAlignment: .end,
                      children: [
                        GlassContainer(
                          settings: LiquidGlassSettings(
                            glassColor: glassColor.value,
                          ),
                          shape: const LiquidRoundedSuperellipse(
                            borderRadius: 30,
                          ),
                          child: IconButton(
                            onPressed: () {
                              switch (menu) {
                                case BigPictureMenu.none:
                                  break;
                                case BigPictureMenu.songs:
                                  showSongListOptions(
                                    context,
                                    library.songList,
                                  );
                                case BigPictureMenu.artists:
                                  showArtistsAlbumsOptions(context, true);
                                case BigPictureMenu.albums:
                                  showArtistsAlbumsOptions(context, false);
                                case BigPictureMenu.frequently:
                                  showSongListOptions(
                                    context,
                                    history.frequentlySongList,
                                  );
                                case BigPictureMenu.recently:
                                  showSongListOptions(
                                    context,
                                    history.recentlySongList,
                                  );
                              }
                            },
                            icon: ImageIcon(optionImage),
                          ),
                        ),
                        SizedBox(width: isMobile ? 10 : 20),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
