import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:material_ui/material_ui.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/desktop_lyrics_setting.dart';
import 'package:sylvakru/base/extensions/window_controller_extension.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/services/lyric.dart';
import 'package:sylvakru/base/utils/contrast_color_generator.dart';
import 'package:sylvakru/base/widgets/lyric_list_view.dart';
import 'package:window_manager/window_manager.dart';

WindowController? lyricsWindowController;
bool lyricsWindowVisible = false;

Duration desktopLyricsCurrentPosition = Duration.zero;

LyricLine? currentLyricLine;
bool currentLyricLineIsKaraoke = false;
final updateDesktopLyricsNotifier = ValueNotifier(0);

/// The initial native window size. It is only a hidden startup size; the first
/// rendered lyric line immediately resizes the window to its own bounds.
const Size desktopLyricsInitialSize = Size(360, 70);

/// Set by the lyrics engine after its first valid position and size are applied.
/// The main engine waits for this before revealing the child window, so it never
/// flashes at the old centre position.
final desktopLyricsReadyNotifier = ValueNotifier(false);

/// Distance between the bottom of the lyric window and the taskbar/work-area
/// edge. A little more than the old 12px keeps the text visually clear.
const double desktopLyricsTaskbarGap = 24;

/// Top-left corner that centres a window of [size] just above the taskbar.
Offset desktopLyricsCenteredPosition(Rect workArea, Size size) => Offset(
  workArea.left + (workArea.width - size.width) / 2,
  workArea.bottom - size.height - desktopLyricsTaskbarGap,
);

bool _windowFitsWorkArea(Rect area, Offset position, Size size) {
  return position.dx >= area.left &&
      position.dy >= area.top &&
      position.dx + size.width <= area.right &&
      position.dy + size.height <= area.bottom;
}

/// Where a desktop lyrics window of [size] should open.
///
/// A saved position is honoured only when the complete window still fits on a
/// connected display. This prevents a monitor unplug from leaving lyrics at an
/// unreachable off-screen coordinate.
Offset desktopLyricsPosition({
  required Size size,
  required Offset? saved,
  required Rect primaryWorkArea,
  required List<Rect> workAreas,
}) {
  if (saved != null &&
      workAreas.any((area) => _windowFitsWorkArea(area, saved, size))) {
    return saved;
  }
  return desktopLyricsCenteredPosition(primaryWorkArea, size);
}

Rect _workAreaOf(Display display) {
  final position = display.visiblePosition ?? Offset.zero;
  final size = display.visibleSize ?? display.size;
  return Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
}

/// Resolves the initial position after the Flutter view exists.
///
/// screen_retriever reads `platformDispatcher.views.single`; calling it before
/// runApp is unreliable in a secondary engine. The caller therefore invokes
/// this from the first rendered frame and retries when the platform view has
/// not been published yet.
Future<Offset?> resolveDesktopLyricsPosition(Size size) async {
  try {
    final primary = await screenRetriever.getPrimaryDisplay();
    List<Display> displays;
    try {
      displays = await screenRetriever.getAllDisplays();
    } catch (_) {
      // A primary display is enough for a safe fallback. Multi-monitor support
      // becomes best effort instead of turning the whole position into null.
      displays = [primary];
    }
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

final desktopLyricsColorNotifier = ValueNotifier<Color>(
  ContrastColorGenerator.onDarkBackdrop(Colors.grey),
);

void setDesktopLyricsColor(int argb) {
  desktopLyricsColorNotifier.value = ContrastColorGenerator.onDarkBackdrop(
    Color(argb),
  );
}

/// Shows or hides the desktop lyrics window.
Future<void> toggleDesktopLyrics() async {
  final controller = lyricsWindowController;
  if (controller == null) {
    return;
  }
  if (lyricsWindowVisible) {
    await controller.hide();
    lyricsWindowVisible = false;
    return;
  }

  await updateDesktopLyrics();
  await controller.sendColor(currentCoverArtColor);

  // The secondary engine positions and sizes itself after its first frame. Do
  // not reveal it while it is still sitting at the native startup coordinate.
  if (!desktopLyricsReadyNotifier.value) {
    for (var i = 0; i < 50 && !desktopLyricsReadyNotifier.value; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }
  await controller.show();
  lyricsWindowVisible = true;
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
  static const double _minWidth = 180;
  static const double _maxWidth = 1200;
  static const double _minHeight = 48;
  static const double _maxHeight = 180;

  final GlobalKey _backdropKey = GlobalKey();

  bool _geometryScheduled = false;
  bool _applyingGeometry = false;
  bool _positionRetryScheduled = false;
  bool _positionResolved = false;
  Size? _windowSize;

  @override
  void initState() {
    super.initState();
    updateDesktopLyricsNotifier.addListener(_onContentChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onContentChanged());
  }

  @override
  void dispose() {
    updateDesktopLyricsNotifier.removeListener(_onContentChanged);
    super.dispose();
  }

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

  void _schedulePositionRetry() {
    if (_positionRetryScheduled || !mounted) {
      return;
    }
    _positionRetryScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      _positionRetryScheduled = false;
      if (mounted && !_positionResolved) {
        _onContentChanged();
      }
    });
  }

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

    _applyingGeometry = true;
    try {
      if (!_positionResolved) {
        final origin = await resolveDesktopLyricsPosition(target);
        if (origin == null) {
          // Do not mark the window fitted and do not call center: true. The
          // screen plugin may only need one more frame to expose its view.
          _schedulePositionRetry();
          return;
        }
        await windowManager.setBounds(
          Rect.fromLTWH(origin.dx, origin.dy, target.width, target.height),
        );
        _positionResolved = true;
        _windowSize = target;
        desktopLyricsReadyNotifier.value = true;
        // Each desktop_multi_window engine has its own globals. Find the main
        // engine (empty arguments) and notify it over that window's channel.
        for (final controller in await WindowController.getAll()) {
          if (controller.arguments.isEmpty) {
            await controller.invokeMethod('desktop_lyrics_ready');
            break;
          }
        }
        return;
      }
      if (target == _windowSize) {
        return;
      }
      final bounds = await windowManager.getBounds();
      await windowManager.setBounds(_anchoredBounds(bounds, target));
      _windowSize = target;
    } catch (_) {
      // Window geometry is cosmetic: failing to fit must never break lyrics.
    } finally {
      _applyingGeometry = false;
    }
  }

  Rect _anchoredBounds(Rect bounds, Size target) => Rect.fromLTWH(
    bounds.left + bounds.width / 2 - target.width / 2,
    bounds.top + bounds.height - target.height,
    target.width,
    target.height,
  );

  Future<void> _rememberPosition() async {
    try {
      final position = await windowManager.getPosition();
      desktopLyricsSetting.positionNotifier.value = position;
      desktopLyricsSetting.save();
    } catch (_) {
      // A failed read only costs the saved position, not playback.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: Platform.isWindows
          ? ThemeData(fontFamily: 'Microsoft YaHei')
          : null,
      home: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) async {
          await windowManager.startDragging();
          await _rememberPosition();
        },
        child: Center(
          // This window intentionally contains only the lyric text. There is
          // no hover toolbar, no lock button, and no reserved control-row area.
          child: Material(
            key: _backdropKey,
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              child: ValueListenableBuilder(
                valueListenable: desktopLyricsColorNotifier,
                builder: (context, color, child) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: content(color),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget content(Color color) {
    return ValueListenableBuilder(
      valueListenable: updateDesktopLyricsNotifier,
      builder: (context, value, child) {
        if (currentLyricLine == null) {
          return _plainText('Sylvakru', color, 30);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (currentLyricLineIsKaraoke)
              ValueListenableBuilder(
                valueListenable: updateLyricsNotifier,
                builder: (context, value, child) {
                  return KaraokeText(
                    key: ValueKey(currentLyricLine!.start),
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
              _plainText(currentLyricLine!.text, color, isMobile ? 20 : 30),
            for (final translate in currentLyricLine!.translates)
              _plainText(
                translate,
                color.withAlpha(140),
                isMobile ? 14 : 24,
              ),
          ],
        );
      },
    );
  }

  Widget _plainText(String text, Color color, double fontSize) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: fontSize,
        color: color,
        shadows: const [
          Shadow(offset: Offset(0, 1), blurRadius: 1, color: Colors.black87),
        ],
      ),
    );
  }
}
