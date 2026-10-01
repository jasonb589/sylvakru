import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/asset_images.dart';
import 'package:sylvakru/base/widgets/buttons.dart';
import 'package:sylvakru/base/widgets/bottom_bar_song_tile.dart';
import 'package:sylvakru/base/utils/dynamic_lyrics_page_route.dart';
import 'package:sylvakru/landscape_view/speaker.dart';
import 'package:sylvakru/landscape_view/volume_bar.dart';
import 'package:sylvakru/base/widgets/seekbar.dart';
import 'package:sylvakru/landscape_view/desktop_lyrics.dart';
import 'package:sylvakru/layer/lyrics_page_layer.dart';

class BottomControl extends StatelessWidget {
  /// Height of the bar. The song tile inside it is measured against this.
  static const double barHeight = 75;

  const BottomControl({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: bottomColor.valueNotifier,
      builder: (context, value, child) {
        return Material(
          color: value,
          child: SizedBox(
            height: barHeight,
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
        return BottomBarSongTile(
          song: currentSong,
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
    );
  }

  Widget bottomSeekBar() {
    // Shrink with the window instead of holding a fixed width: on a narrow
    // desktop window a 400px bar squeezed the song tile and the controls.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(0.0, isMobile ? 300.0 : 400.0)
            : (isMobile ? 300.0 : 400.0);
        return SizedBox(
          width: width,
          child: ValueListenableBuilder(
            valueListenable: currentSongNotifier,
            builder: (_, _, _) {
              return SeekBar(widgetHeight: 20, seekBarHeight: 10);
            },
          ),
        );
      },
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
        downloadButton(25),

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
