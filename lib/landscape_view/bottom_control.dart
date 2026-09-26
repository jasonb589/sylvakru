import 'package:sylvakru/base/design/marquee_text.dart';
import 'package:sylvakru/base/design/app_tokens.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/design/interaction_overlay.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/asset_images.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/base/widgets/buttons.dart';
import 'package:sylvakru/base/widgets/cover_art_widget.dart';
import 'package:sylvakru/base/utils/dynamic_lyrics_page_route.dart';
import 'package:sylvakru/landscape_view/speaker.dart';
import 'package:sylvakru/landscape_view/volume_bar.dart';
import 'package:sylvakru/base/widgets/seekbar.dart';
import 'package:sylvakru/base/widgets/lyrics_line_bar.dart';
import 'package:sylvakru/landscape_view/desktop_lyrics.dart';
import 'package:sylvakru/layer/lyrics_page_layer.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:smooth_corner/smooth_corner.dart';

class BottomControl extends StatelessWidget {
  const BottomControl({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: bottomColor.valueNotifier,
      builder: (context, value, child) {
        return Material(
          color: value,
          child: SizedBox(
            height: 75,
            child: Row(
              children: [
                Expanded(flex: 2, child: currentSongTile(context)),

                if (isMobile) ...[
                  Expanded(flex: 2, child: bottomSeekBar()),
                  Expanded(
                    flex: 2,
                    child: Row(
                      mainAxisAlignment: .end,
                      children: [...playControls(), SizedBox(width: 10)],
                    ),
                  ),
                ] else ...[
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: .center,
                          children: playControls(),
                        ),
                        Transform.translate(
                          offset: Offset(0, -6),
                          child: bottomSeekBar(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(flex: 2, child: otherControls(context)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget currentSongTile(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: currentSongNotifier,
      builder: (_, currentSong, _) {
        return Theme(
          data: AppOverlay.none(context, keepFocus: true),
          child: Material(
            color: Colors.transparent,
            shape: SmoothRectangleBorder(
              smoothness: 1,
              borderRadius: .all(.circular(10)),
            ),
            clipBehavior: .antiAlias,
            child: ListenableBuilder(
              listenable: Listenable.merge([currentSong?.updateNotifier]),
              builder: (context, _) {
                return ListTile(
                  leading: Hero(
                    tag: 'cover',
                    child: CoverArtWidget(
                      size: 50,
                      borderRadius: 5,
                      elevation: AppElevation.control,
                      picture: currentSong?.picture,
                      useResize: false,
                    ),
                  ),
                  title: MarqueeText(text: getTitle(currentSong)),
                  subtitle: currentSong != null
                      ? LyricsLineBar(
                          fontSize: 13,
                          maxLines: 1,
                          // no timed lyrics: keep showing artist - album
                          fallback: Row(
                            children: [
                              // the artist name links to its artist page, the
                              // rest of the tile still opens the lyrics page
                              Flexible(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    goToArtist(currentSong, context);
                                  },
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: Text(
                                      getArtist(currentSong),
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  " - ${getAlbum(currentSong)}",
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        )
                      : null,
                  onTap: () {
                    if (playQueue.isEmpty) {
                      return;
                    }
                    Navigator.of(context, rootNavigator: true).push(
                      DynamicLyricsPageRoute(
                        pageBuilder: (_, _, _) => LyricsPageLayer(),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget bottomSeekBar() {
    return SizedBox(
      width: isMobile ? 300 : 400,
      child: ValueListenableBuilder(
        valueListenable: currentSongNotifier,
        builder: (_, _, _) {
          return SeekBar(widgetHeight: 20, seekBarHeight: 10);
        },
      ),
    );
  }

  List<Widget> playControls() {
    return [
      playModeButton(25),

      skip2PreviousButton(25),

      playOrPauseButton(35),

      skip2NextButton(25),

      showPlayQueueButton(25),
    ];
  }

  Widget otherControls(BuildContext context) {
    return Row(
      children: [
        Spacer(),
        IconButton(
          onPressed: toggleDesktopLyrics,
          icon: const ImageIcon(desktopLyricsImage, size: 25),
        ),
        favoriteButton(25),

        ValueListenableBuilder(
          valueListenable: iconColor.valueNotifier,
          builder: (context, value, child) {
            return Speaker(color: value);
          },
        ),
        Center(
          child: SizedBox(
            height: 20,
            width: 120,
            child: ValueListenableBuilder(
              valueListenable: volumeBarColor.valueNotifier,
              builder: (context, value, child) {
                return VolumeBar(activeColor: value);
              },
            ),
          ),
        ),
        SizedBox(width: 30),
      ],
    );
  }
}
