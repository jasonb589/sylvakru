import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:material_ui/material_ui.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:smooth_corner/smooth_corner.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/asset_images.dart';
import 'package:sylvakru/base/data/desktop_lyrics_setting.dart';
import 'package:sylvakru/base/extensions/window_controller_extension.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/services/lyric.dart';
import 'package:sylvakru/base/utils/contrast_color_generator.dart';
import 'package:sylvakru/base/widgets/lyric_list_view.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/l10n/generated/app_localizations_en.dart';
import 'package:window_manager/window_manager.dart';

WindowController? lyricsWindowController;
bool lyricsWindowVisible = false;

Duration desktopLyricsCurrentPosition = Duration.zero;

LyricLine? currentLyricLine;
bool currentLyricLineIsKaraoke = false;
final updateDesktopLyricsNotifier = ValueNotifier(0);

/// The size the desktop lyrics window is created at.
///
/// The window then shrinks to hug the lyrics (see [_DesktopLyricsState]), so
/// this is only a starting point; it is kept small rather than the old
/// 1000x200 so that a missed first fit cannot leave a large dead rectangle on
/// the desktop.
const Size desktopLyricsInitialSize = Size(360, 110);

/// Space kept between the lyrics and the bottom of the work area, so the window
/// sits a little above the taskbar instead of touching it.
const double desktopLyricsTaskbarGap = 12;

/// Top-left corner that centres a window of [size] just above the taskbar.
Offset desktopLyricsCenteredPosition(Rect workArea, Size size) => Offset(
  workArea.left + (workArea.width - size.width) / 2,
  workArea.bottom - size.height - desktopLyricsTaskbarGap,
);

/// Where a desktop lyrics window of [size] should open.
///
/// A [saved] position is honoured as long as it still lands inside one of the
/// current [workAreas]. It is dropped when it does not: a window dragged onto a
/// second monitor that is later unplugged would otherwise reopen off-screen,
/// where it can neither be seen nor reached. A dropped or missing position
/// falls back to [primaryWorkArea], centred above the taskbar.
Offset desktopLyricsPosition({
  required Size size,
  required Offset? saved,
  required Rect primaryWorkArea,
  required List<Rect> workAreas,
}) {
  if (saved != null && workAreas.any((area) => area.contains(saved))) {
    return saved;
  }
  return desktopLyricsCenteredPosition(primaryWorkArea, size);
}

/// Work area of [display] in logical pixels, already excluding the taskbar
/// (that is what the `visible*` fields report).
Rect _workAreaOf(Display display) {
  final position = display.visiblePosition ?? Offset.zero;
  final size = display.visibleSize ?? display.size;
  return Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
}

/// Resolves where a window of [size] should sit right now, or null when the
/// platform will not report the displays.
///
/// screen_retriever is best effort: on failure the caller leaves the window
/// wherever it already is rather than guessing.
Future<Offset?> resolveDesktopLyricsPosition(Size size) async {
  try {
    final primary = await screenRetriever.getPrimaryDisplay();
    final displays = await screenRetriever.getAllDisplays();
    return desktopLyricsPosition(
      size: size,
      saved: desktopLyricsSetting.positionNotifier.value,
      primaryWorkArea: _workAreaOf(primary),
      workAreas: [for (final display in displays) _workAreaOf(display)],
    );
  } catch (_) {
    return null;
  }
}

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

class DesktopLyrics extends StatefulWidget {
  const DesktopLyrics({super.key});

  @override
  State<DesktopLyrics> createState() => _DesktopLyricsState();
}

class _DesktopLyricsState extends State<DesktopLyrics> {
  /// Bounds for the fitted window. The width ceiling is what a long line is
  /// allowed to reach before it wraps; the floor keeps the controls row, which
  /// is wider than short lyric lines, from being clipped.
  static const double _minWidth = 300;
  static const double _maxWidth = 1000;
  static const double _minHeight = 70;
  static const double _maxHeight = 260;

  /// Whether the pointer is over the lyrics, which reveals the backdrop and the
  /// controls.
  final ValueNotifier<bool> _hoveredNotifier = ValueNotifier(false);

  /// Measured to size the window to its content.
  final GlobalKey _backdropKey = GlobalKey();

  bool _isDragging = false;
  bool _geometryScheduled = false;
  bool _applyingGeometry = false;

  /// The size the window was last fitted to, or null before the first fit.
  Size? _windowSize;

  @override
  void initState() {
    super.initState();
    // The window is sized from the lyric text, so it has to be re-measured
    // whenever the line changes. This notifier fires on each lyric line change,
    // not per frame.
    updateDesktopLyricsNotifier.addListener(_onContentChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onContentChanged());
  }

  @override
  void dispose() {
    updateDesktopLyricsNotifier.removeListener(_onContentChanged);
    _hoveredNotifier.dispose();
    super.dispose();
  }

  /// Schedules a window fit for after the frame that is about to be built, so
  /// the new line is already laid out when it is measured.
  void _onContentChanged() {
    if (_geometryScheduled) {
      return;
    }
    _geometryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geometryScheduled = false;
      _syncWindowGeometry();
    });
  }

  /// Resizes the window to hug the lyrics.
  ///
  /// A Flutter window swallows every click inside its rectangle, even where it
  /// draws nothing, so the old fixed 1000x200 window blocked a large part of the
  /// desktop. Fitting the window to its content keeps that dead area down to the
  /// lyrics themselves.
  ///
  /// The size comes from the backdrop's *intrinsic* width rather than the size it
  /// currently has. Measuring the laid-out box would not work: text wraps to
  /// whatever width the window happens to be, so a line measured inside a narrow
  /// window reports that narrow width and the window could never grow back out.
  /// An intrinsic width is the width the text wants when nothing constrains it,
  /// which is what the window must be sized to.
  ///
  /// Only the size is set here. The window's position is decided once, when the
  /// Only the size is set here, plus the position on the very first fit (see
  /// [desktopLyricsPosition]). Later fits preserve the bottom edge and
  /// horizontal centre, so the lyrics stay put while lines come and go.
  Future<void> _syncWindowGeometry() async {
    if (_applyingGeometry) {
      return;
    }
    final renderObject = _backdropKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) {
      return;
    }

    final width = renderObject
        .getMaxIntrinsicWidth(double.infinity)
        .ceilToDouble()
        .clamp(_minWidth, _maxWidth);
    final target = Size(
      width,
      renderObject
          .getMinIntrinsicHeight(width)
          .ceilToDouble()
          .clamp(_minHeight, _maxHeight),
    );
    if (target == _windowSize) {
      return;
    }

    _applyingGeometry = true;
    try {
      final bounds = await windowManager.getBounds();
      if (_windowSize == null) {
        // First fit: this is where the window actually lands, so use the
        // resolved position outright. Anchoring to the current box instead
        // would offset the window by however much the initial size differs
        // from the fitted one, so it would not reopen where it was left.
        if (!desktopLyricsSetting.loaded) {
          await desktopLyricsSetting.load();
        }
        final origin = await resolveDesktopLyricsPosition(target);
        await windowManager.setBounds(
          origin == null
              // no display information: keep the current centre and bottom
              ? _anchoredBounds(bounds, target)
              : Rect.fromLTWH(origin.dx, origin.dy, target.width, target.height),
        );
      } else {
        // Later fits only change the size as lyric lines come and go, so the
        // bottom edge and horizontal centre are preserved and the lyrics stay
        // put instead of creeping around the desktop.
        await windowManager.setBounds(_anchoredBounds(bounds, target));
      }
      _windowSize = target;
    } catch (_) {
      // Window geometry is cosmetic: failing to fit must never break lyrics.
    } finally {
      _applyingGeometry = false;
    }
  }

  /// [target]-sized bounds that keep [bounds]' bottom edge and centre.
  Rect _anchoredBounds(Rect bounds, Size target) => Rect.fromLTWH(
    bounds.left + bounds.width / 2 - target.width / 2,
    bounds.top + bounds.height - target.height,
    target.width,
    target.height,
  );

  /// Stores where the window was dragged to.
  ///
  /// `startDragging` hands the move to the OS and returns once the drag has
  /// finished, so the final position can be read here. The saved position is
  /// restored on the next launch, provided it still falls on a connected
  /// display (see [desktopLyricsPosition]).
  Future<void> _rememberPosition() async {
    try {
      final position = await windowManager.getPosition();
      desktopLyricsSetting.positionNotifier.value = position;
      desktopLyricsSetting.save();
    } catch (_) {
      // a failed read only costs the saved position, not playback
    }
  }

  /// Localised tooltip for the lock button.
  ///
  /// This window is its own engine with no [AppLocalizations] in scope, so the
  /// strings are looked up from the current locale the same way the tray menu
  /// does it.
  String _lockLabel(bool locked) {
    late AppLocalizations l10n;
    final locale = localeNotifier.value;
    try {
      l10n = locale != null
          ? lookupAppLocalizations(locale)
          : lookupAppLocalizations(PlatformDispatcher.instance.locale);
    } catch (_) {
      l10n = AppLocalizationsEn();
    }
    return locked ? l10n.unlock : l10n.lock;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: Platform.isWindows
          ? ThemeData(fontFamily: 'Microsoft YaHei')
          : null,

      home: ValueListenableBuilder(
        valueListenable: _hoveredNotifier,
        builder: (context, hovered, child) {
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (details) async {
              // Locked pins the window so it cannot be nudged by accident while
              // working underneath it. Locking only disables dragging: it
              // deliberately does not use setIgnoreMouseEvents, which would also
              // clear WS_EX_LAYERED and break this window's transparency.
              if (desktopLyricsSetting.lockedNotifier.value) {
                return;
              }
              _isDragging = true;
              await windowManager.startDragging();
              _isDragging = false;
              await _rememberPosition();
            },
            child: MouseRegion(
              onEnter: (_) {
                _hoveredNotifier.value = true;
              },
              onExit: (_) {
                if (_isDragging) {
                  return;
                }
                _hoveredNotifier.value = false;
              },
              // The window itself stays transparent: the backdrop only wraps the
              // lyric line plus the controls, so it hugs the text instead of
              // filling a fixed window.
              child: Center(
                child: Material(
                  key: _backdropKey,
                  color: hovered ? Colors.black45 : Colors.transparent,
                  shape: SmoothRectangleBorder(
                    smoothness: 1,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ConstrainedBox(
                    // A line longer than the window may be wide would otherwise
                    // overflow the backdrop; wrapping it keeps the box hugging
                    // the text.
                    constraints: const BoxConstraints(maxWidth: _maxWidth),
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
                              // The controls keep their space even while hidden,
                              // so the backdrop is always sized for both rows and
                              // the lyrics never jump when the buttons fade in.
                              // They stop taking clicks while faded out.
                              SizedBox(
                                height: 50,
                                child: IgnorePointer(
                                  ignoring: !hovered,
                                  child: AnimatedOpacity(
                                    opacity: hovered ? 1 : 0,
                                    duration: const Duration(milliseconds: 150),
                                    child: controlsRow(color),
                                  ),
                                ),
                              ),
                              content(color),
                            ],
                          ),
                        );
                      },
                    ),
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
    // mainAxisSize.min keeps the row hugging the buttons: a Spacer would make it
    // as wide as the window and stretch the backdrop with it
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Lock pins the window so it cannot be nudged by accident while working
        // underneath it. The buttons stay clickable while locked, so this button
        // is itself the way back out.
        ValueListenableBuilder(
          valueListenable: desktopLyricsSetting.lockedNotifier,
          builder: (context, locked, child) {
            return IconButton(
              color: buttonColor,
              tooltip: _lockLabel(locked),
              onPressed: () {
                desktopLyricsSetting.lockedNotifier.value = !locked;
                desktopLyricsSetting.save();
              },
              icon: Icon(
                locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                size: 20,
              ),
            );
          },
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
      ],
    );
  }
}
