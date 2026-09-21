import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/audio_handler.dart';

import 'package:sylvakru/base/asset_images.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/services/lyric.dart';
import 'package:sylvakru/base/utils/contrast_color_generator.dart';
import 'package:sylvakru/base/widgets/lyric_list_view.dart';
import 'package:sylvakru/base/extensions/window_controller_extension.dart';
import 'package:smooth_corner/smooth_corner.dart';
import 'package:window_manager/window_manager.dart';

WindowController? lyricsWindowController;
bool lyricsWindowVisible = false;

Duration desktopLyricsCurrentPosition = Duration.zero;

LyricLine? currentLyricLine;
bool currentLyricLineIsKaraoke = false;
final updateDesktopLyricsNotifier = ValueNotifier(0);

/// The text and control colours derived from the current album colour.
///
/// The desktop lyrics live in their own Flutter engine, so they cannot read the
/// main window's currentCoverArtColor. The main window pushes the album colour
/// over the method channel (see WindowControllerExtension.sendColor) and it is
/// turned into the very same contrast theme the playback lyrics page uses.
final desktopLyricsThemeNotifier = ValueNotifier<ContrastColorTextTheme>(
  ContrastColorGenerator.generate(Colors.grey, darkBackground: true),
);

/// Recomputes the desktop lyrics colours from an ARGB album colour.
///
/// [darkBackground] is pinned because the window always draws on its own
/// translucent black backdrop, whatever the cover art happens to look like;
/// letting the cover decide would put near-black text on a black window.
void setDesktopLyricsColor(int argb) {
  desktopLyricsThemeNotifier.value = ContrastColorGenerator.generate(
    Color(argb),
    darkBackground: true,
  );
}

/// Shows or hides the desktop lyrics window.
///
/// The window is a separate Flutter engine, so it starts on a neutral default
/// colour and cannot read the album colour by itself. The colour is therefore
/// pushed on every show, otherwise reopening it would keep whatever colour the
/// previous song left behind until the track changes again.
Future<void> toggleDesktopLyrics() async {
  final controller = lyricsWindowController;
  if (controller == null) {
    return;
  }
  if (lyricsWindowVisible) {
    await controller.hide();
  } else {
    await updateDesktopLyrics();
    await controller.sendColor(currentCoverArtColor);
    await controller.show();
  }
  lyricsWindowVisible = !lyricsWindowVisible;
}

Future<void> initDesktopLyrics() async {
  lyricsWindowController = await WindowController.create(
    WindowConfiguration(hiddenAtLaunch: true, arguments: 'desktop_lyrics'),
  );
}

class DesktopLyrics extends StatelessWidget {
  final ValueNotifier<bool> _isTransparentNotifier = ValueNotifier(false);

  DesktopLyrics({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: Platform.isWindows
          ? ThemeData(fontFamily: 'Microsoft YaHei')
          : null,

      home: ValueListenableBuilder(
        valueListenable: _isTransparentNotifier,
        builder: (context, isTransparent, child) {
          bool isDragging = false;
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (details) async {
              isDragging = true;
              await windowManager.startDragging();
              isDragging = false;
            },
            child: MouseRegion(
              onEnter: (_) {
                _isTransparentNotifier.value = false;
              },
              onExit: (_) {
                if (isDragging) {
                  return;
                }
                _isTransparentNotifier.value = true;
              },
              child: Material(
                color: isTransparent ? Colors.transparent : Colors.black45,
                shape: SmoothRectangleBorder(
                  smoothness: 1,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: ValueListenableBuilder(
                  valueListenable: desktopLyricsThemeNotifier,
                  builder: (context, theme, child) {
                    return Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 50,
                            child: isTransparent ? null : controlsRow(theme),
                          ),
                          content(theme),
                          Spacer(),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget content(ContrastColorTextTheme theme) {
    return ValueListenableBuilder(
      valueListenable: updateDesktopLyricsNotifier,
      builder: (context, value, child) {
        if (currentLyricLine == null) {
          return Text(
            'Sylvakru',
            style: TextStyle(
              fontSize: isMobile ? 20 : 30,
              color: theme.regular,
              shadows: [
                Shadow(
                  offset: Offset(0, 1),
                  blurRadius: 1,
                  color: Colors.black87,
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: .center,
          children: [
            if (currentLyricLineIsKaraoke)
              ValueListenableBuilder(
                valueListenable: updateLyricsNotifier,
                builder: (context, value, child) {
                  return KaraokeText(
                    key: UniqueKey(),
                    line: currentLyricLine!,
                    position: desktopLyricsCurrentPosition,
                    fontSize: isMobile ? 20 : 30,
                    expanded: false,
                    isDesktopLyrics: true,
                    desktopLyricsTextColor: theme.accent,
                  );
                },
              )
            else
              Text(
                currentLyricLine!.text,

                style: TextStyle(
                  fontSize: isMobile ? 20 : 30,
                  color: theme.regular,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 1,
                      color: Colors.black87,
                    ),
                  ],
                ),
              ),
            for (final translate in currentLyricLine!.translates)
              Text(
                translate,

                style: TextStyle(
                  fontSize: isMobile ? 14 : 24,
                  color: theme.regular.withAlpha(128),
                  shadows: [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 1,
                      color: Colors.black87,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget controlsRow(ContrastColorTextTheme theme) {
    // the buttons follow the album colour too, but keep enough contrast against
    // the window's black backdrop
    final buttonColor = theme.regular;
    return Row(
      children: [
        Spacer(),
        IconButton(
          color: buttonColor,

          onPressed: () async {
            await windowManager.setIgnoreMouseEvents(true);
          },
          icon: Icon(Icons.lock_rounded, size: 20),
        ),
        IconButton(
          color: buttonColor,
          icon: const ImageIcon(previousButtonImage, size: 25),
          onPressed: () async {
            final controllers = await WindowController.getAll();
            for (final controller in controllers) {
              if (controller.arguments.isEmpty) {
                controller.skipToPrevious();
              }
            }
          },
        ),
        IconButton(
          color: buttonColor,
          icon: ValueListenableBuilder(
            valueListenable: isPlayingNotifier,
            builder: (_, isPlaying, _) {
              return Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 30,
              );
            },
          ),
          onPressed: () async {
            final controllers = await WindowController.getAll();
            for (final controller in controllers) {
              if (controller.arguments.isEmpty) {
                controller.togglePlay();
              }
            }
          },
        ),
        IconButton(
          color: buttonColor,
          icon: const ImageIcon(nextButtonImage, size: 25),
          onPressed: () async {
            final controllers = await WindowController.getAll();
            for (final controller in controllers) {
              if (controller.arguments.isEmpty) {
                controller.skipToNext();
              }
            }
          },
        ),
        IconButton(
          color: buttonColor,

          onPressed: () async {
            final controllers = await WindowController.getAll();
            for (final controller in controllers) {
              if (controller.arguments.isEmpty) {
                controller.hideDesktopLyrics();
              }
            }
            windowManager.hide();
          },
          icon: Icon(Icons.close),
        ),
        Spacer(),
      ],
    );
  }
}
