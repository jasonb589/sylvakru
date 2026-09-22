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

/// The colour the desktop lyrics draw in, derived from the current album.
///
/// The colour the desktop lyrics draw in, derived from the current album.
///
/// The desktop lyrics live in their own Flutter engine, so they cannot read the
/// main window's currentCoverArtColor. The main window pushes the album colour
/// over the method channel (see WindowControllerExtension.sendColor) and it is
/// turned into a tint that keeps the album's hue while staying legible on the
/// window's own translucent black backdrop.
final desktopLyricsColorNotifier = ValueNotifier<Color>(
  ContrastColorGenerator.onDarkBackdrop(Colors.grey),
);

/// Recomputes the desktop lyrics colour from an ARGB album colour.
void setDesktopLyricsColor(int argb) {
  desktopLyricsColorNotifier.value = ContrastColorGenerator.onDarkBackdrop(
    Color(argb),
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
              // The window itself stays transparent: the backdrop only wraps
              // the lyric line (plus the controls on hover), so it hugs the
              // text instead of filling the whole 1000x200 window.
              child: Center(
                child: Material(
                  color: isTransparent ? Colors.transparent : Colors.black45,
                  shape: SmoothRectangleBorder(
                    smoothness: 1,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ValueListenableBuilder(
                    valueListenable: desktopLyricsColorNotifier,
                    builder: (context, color, child) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isTransparent)
                              SizedBox(height: 50, child: controlsRow(color)),
                            content(color),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget content(Color color) {
    return ValueListenableBuilder(
      valueListenable: updateDesktopLyricsNotifier,
      builder: (context, value, child) {
        if (currentLyricLine == null) {
          return Text(
            'Sylvakru',
            style: TextStyle(
              fontSize: isMobile ? 20 : 30,
              color: color,
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
                    desktopLyricsTextColor: color,
                  );
                },
              )
            else
              Text(
                currentLyricLine!.text,

                style: TextStyle(
                  fontSize: isMobile ? 20 : 30,
                  color: color,
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
                  color: color.withAlpha(140),
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

  Widget controlsRow(Color color) {
    // the buttons follow the album colour too
    final buttonColor = color;
    // mainAxisSize.min keeps the row hugging the buttons: a Spacer would make
    // it as wide as the window and stretch the backdrop with it
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The lock button is gone with the tray's "unlock" item: locking made
        // the window ignore mouse events, and window_manager's
        // setIgnoreMouseEvents(false) also clears WS_EX_LAYERED, so unlocking
        // could not restore the transparent window properly.
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
      ],
    );
  }
}
