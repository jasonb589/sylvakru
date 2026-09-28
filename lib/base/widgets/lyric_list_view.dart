import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/design/app_tokens.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/services/lyric.dart';
import 'package:sylvakru/base/utils/lyric_motion.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:smooth_corner/smooth_corner.dart';

final lyricsFontSizeOffsetNotifier = ValueNotifier(0.0);
final lyricsTimeOffsetNotifier = ValueNotifier(0);
final lyricsFontWeightNotifier = ValueNotifier(FontWeight.bold);

final updateLyricsNotifier = ValueNotifier(0);

class LyricsListView extends StatefulWidget {
  final bool expanded;
  final List<LyricLine> lines;
  final bool isKaraoke;
  const LyricsListView({
    super.key,
    required this.expanded,
    required this.lines,
    required this.isKaraoke,
  });

  @override
  State<LyricsListView> createState() => LyricsListViewState();
}

class LyricsListViewState extends State<LyricsListView>
    with WidgetsBindingObserver {
  final ItemScrollController itemScrollController = ItemScrollController();
  final ValueNotifier<int> currentIndexNotifier = ValueNotifier<int>(-1);

  /// Bumped when the list lands somewhere far away instead of travelling there
  /// (a seek, a return from the other end of the song). Each bump fades the
  /// list back in where it arrived.
  final ValueNotifier<int> resetFadeNotifier = ValueNotifier<int>(0);

  StreamSubscription<Duration>? positionSub;

  List<LyricLine> lines = [];
  bool jump = true;

  /// False while the listener is dragging the list: the music must not fight
  /// them for it. [AppLyrics.idleBeforeReturn] after they stop, or as soon as
  /// the song moves on, it follows again.
  bool _following = true;
  Timer? _idleTimer;

  /// The line the list has been sent to. One line change starts one scroll, and
  /// a scroll that has already begun is not begun twice.
  int _scrolledTo = -1;

  double? _viewportHeight;

  /// The anchor a line rests at: the current line sits above the middle, so the
  /// next one is already in view and the list reads as moving forward.
  double get _alignment => widget.expanded ? 0.30 : 0.42;

  /// Which line is being sung, and where the list should be because of it.
  ///
  /// The scroll starts before the line does - a head start of its own duration
  /// - so the new line has arrived by the time it is sung rather than the list
  /// chasing it afterwards.
  void scroll2CurrentIndex(Duration position) {
    position += Duration(milliseconds: lyricsTimeOffsetNotifier.value);
    // it's weird that the position is sometimes negative
    if (audioHandler.isLoading || position < Duration.zero) {
      return;
    }

    final previous = currentIndexNotifier.value;
    final current = lyricIndexAt(lines, position);
    currentIndexNotifier.value = current;

    // The list carries one leading spacer, so a line's item index is one more.
    final target = current + 1;

    if (!_following) {
      if (current != previous) {
        // The song moved on while the listener was looking elsewhere: that is
        // the moment to come back, not a fixed wait after they stopped.
        _returnToCurrent();
      }
      return;
    }

    if (jump) {
      jump = false;
      _scrolledTo = target;
      _landAt(target);
    } else if (_scrolledTo != target) {
      // The list is behind: either there was no head start (a seek, a stalled
      // frame) or the listener just came back. Land or travel, by distance.
      _moveTo(target);
    }

    _getReadyForNext(current, position);
  }

  /// Starts the scroll for the line after the current one once it is due.
  void _getReadyForNext(int current, Duration position) {
    final next = current + 1;
    if (next >= lines.length) {
      return;
    }
    // The next line's item index, and the line after the current one.
    final target = next + 1;
    if (_scrolledTo == target) {
      return;
    }
    final distance = (target - _scrolledTo).abs();
    final duration = lyricScrollMs(distance);
    if (!lyricScrollDue(
      position: position,
      nextStart: lines[next].start,
      durationMs: duration,
    )) {
      return;
    }
    _moveTo(target);
  }

  /// Sends the list to [index], travelling or landing by how far it has to go.
  void _moveTo(int index) {
    if (!itemScrollController.isAttached) {
      return;
    }
    final distance = (index - _scrolledTo).abs();
    _scrolledTo = index;
    if (distance >= AppLyrics.jumpLines) {
      itemScrollController.jumpTo(index: index, alignment: _alignment);
      resetFadeNotifier.value++;
      return;
    }
    itemScrollController.scrollTo(
      index: index,
      duration: Duration(milliseconds: lyricScrollMs(distance)),
      curve: AppLyrics.scrollCurve,
      alignment: _alignment,
    );
  }

  /// Puts the current line where it belongs without travelling: how the page
  /// opens, and how it behaves when the window is resized.
  void _landAt(int index) {
    if (!itemScrollController.isAttached) {
      return;
    }
    itemScrollController.jumpTo(index: index, alignment: _alignment);
  }

  /// Follows the music again after the listener scrolled away.
  void _returnToCurrent() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _following = true;
    final target = currentIndexNotifier.value + 1;
    if (target <= 0 || !itemScrollController.isAttached) {
      return;
    }
    _scrolledTo = target;
    itemScrollController.scrollTo(
      index: target,
      duration: AppLyrics.scrollReturn,
      curve: AppLyrics.scrollCurve,
      alignment: _alignment,
    );
  }

  bool _onUserScroll(UserScrollNotification notification) {
    if (notification.direction != ScrollDirection.idle) {
      _following = false;
      _idleTimer?.cancel();
      _idleTimer = null;
    } else if (!_following) {
      _idleTimer ??= Timer(AppLyrics.idleBeforeReturn, () {
        _idleTimer = null;
        _returnToCurrent();
      });
    }
    return false;
  }

  void _listen() {
    positionSub?.cancel();
    positionSub = audioHandler.getPositionStream().listen(scroll2CurrentIndex);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    lines = widget.lines;
    scroll2CurrentIndex(audioHandler.getPosition());
    _listen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Stop listening when lyrics page is closed
    positionSub?.cancel();
    positionSub = null;

    _idleTimer?.cancel();
    _idleTimer = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (positionSub == null) {
          jump = true;
          scroll2CurrentIndex(audioHandler.getPosition());
          _listen();
        }
        break;
      case AppLifecycleState.paused:
        positionSub?.cancel();
        positionSub = null;
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final parentHeight = constraints.maxHeight; // height of the parent
        if (_viewportHeight != parentHeight) {
          _viewportHeight = parentHeight;
          // A resize moves every offset at once: land in place rather than
          // animating a scroll that would look like a jump with lag.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final current = currentIndexNotifier.value;
            if (current == -1) {
              return;
            }
            _scrolledTo = current + 1;
            _landAt(current + 1);
          });
        }
        return NotificationListener<UserScrollNotification>(
          onNotification: _onUserScroll,
          child: ValueListenableBuilder<int>(
            valueListenable: resetFadeNotifier,
            builder: (context, token, child) {
              // A new key restarts the fade each time the list lands far away.
              return TweenAnimationBuilder<double>(
                key: ValueKey(token),
                tween: Tween<double>(begin: 0, end: 1),
                duration: AppLyrics.resetFade,
                curve: AppCurve.enter,
                builder: (context, value, child) =>
                    Opacity(opacity: value, child: child),
                child: child,
              );
            },
            child: ScrollablePositionedList.builder(
              physics: ClampingScrollPhysics(),
              itemCount: lines.length + 2,
              itemScrollController: itemScrollController,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return SizedBox(
                    height: widget.expanded
                        ? parentHeight * 0.30
                        : parentHeight * 0.42,
                  );
                } else if (index == lines.length + 1) {
                  return SizedBox(
                    height: widget.expanded
                        ? parentHeight * 0.65
                        : parentHeight * 0.45,
                  );
                }
                return LyricLineWidget(
                  index: index - 1,
                  line: lines[index - 1],
                  currentIndexNotifier: currentIndexNotifier,
                  expanded: widget.expanded,
                  isKaraoke: widget.isKaraoke,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// One line, with the page's focus on it: the line being sung is at full
/// strength and the others step down by how far away they are.
class LyricLineWidget extends StatelessWidget {
  final int index;
  final LyricLine line;
  final ValueNotifier<int> currentIndexNotifier;
  final bool expanded;
  final bool isKaraoke;

  const LyricLineWidget({
    super.key,
    required this.line,
    required this.index,
    required this.currentIndexNotifier,
    required this.expanded,
    required this.isKaraoke,
  });

  @override
  Widget build(BuildContext context) {
    double paddingHeight = 15;
    double fontSizeOffset = 0;
    if (!isMobile) {
      final pageHeight = MediaQuery.heightOf(context);
      final pageWidth = MediaQuery.widthOf(context);
      paddingHeight += (pageHeight - 700) * 0.025;
      fontSizeOffset = min(
        (pageHeight - 700) * 0.075,
        (pageWidth - 1050) * 0.025,
      ).clamp(0, double.maxFinite);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: () {
          // add 1ms offset to avoid seeking to last lyric
          audioHandler.seek(line.start + Duration(milliseconds: 1));
        },
        customBorder: SmoothRectangleBorder(
          smoothness: 1,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: expanded
              ? EdgeInsets.fromLTRB(25, paddingHeight, 30, paddingHeight)
              : const EdgeInsets.symmetric(vertical: 5, horizontal: 15),
          child: ListenableBuilder(
            listenable: Listenable.merge([
              lyricsFontSizeOffsetNotifier,
              lyricsFontWeightNotifier,
              currentIndexNotifier,
            ]),
            builder: (context, _) {
              double fontSize = 16 + lyricsFontSizeOffsetNotifier.value;

              if (expanded) {
                fontSize += isMobile ? 16 : 8;
              }

              fontSize += fontSizeOffset;

              final textColor = viewModeNotifier.value == .mini
                  ? miniViewForegroundColor.value
                  : lyricsPageForegroundColor.value;
              final highlightTextColor = viewModeNotifier.value == .mini
                  ? miniViewHighlightTextColor.value
                  : lyricsPageHighlightTextColor.value;

              // The distance to the line being sung is animated, so a line that
              // takes over from another crosses the steps in between instead of
              // switching on: at 0 it is being sung, at 1 the one after it is.
              return TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  end: lyricDistance(
                    index,
                    currentIndexNotifier.value,
                  ).toDouble(),
                ),
                duration: AppLyrics.lineSwitch,
                curve: AppCurve.enter,
                builder: (context, distance, child) {
                  final near = distance.clamp(0.0, 1.0);
                  final colour = Color.lerp(
                    textColor,
                    highlightTextColor,
                    1 - near,
                  )!;
                  final opacity = lyricLineOpacity(distance);
                  final weight = lyricLineWeight(
                    lyricsFontWeightNotifier.value,
                    distance,
                  );

                  return Transform.scale(
                    scale: lyricLineScale(distance),
                    alignment: expanded ? .centerLeft : .center,
                    child: Column(
                      crossAxisAlignment: expanded ? .start : .center,
                      children: [
                        if (near < 1)
                          // Sung, or about to be: the fill sweeps across it.
                          LyricFillText(
                            line: line,
                            position: audioHandler.getPosition(),
                            fontSize: fontSize,
                            expanded: expanded,
                          )
                        else
                          Text(
                            line.text,
                            textAlign: expanded ? .start : .center,
                            style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: weight,
                              color: colour.withValues(alpha: opacity),
                            ),
                          ),
                        for (final translate in line.translates)
                          Text(
                            translate,
                            textAlign: expanded ? .start : .center,
                            style: TextStyle(
                              fontSize: fontSize - (expanded ? 8 : 4),
                              fontWeight: weight,
                              color: colour.withValues(
                                alpha: opacity * (near >= 1 ? 0.85 : 0.8),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One line of lyrics with the fill that sweeps across it.
///
/// Also used by the desktop lyrics window, which draws it on its own dark
/// backdrop and therefore brings its own colour.
class LyricFillText extends StatefulWidget {
  final LyricLine line;
  final Duration position;
  final double fontSize;
  final bool expanded;
  final bool isDesktopLyrics;

  /// Colour used for the desktop lyrics window, which draws on its own dark
  /// backdrop instead of following the app's lyrics page theme.
  final Color? desktopLyricsTextColor;

  const LyricFillText({
    super.key,
    required this.line,
    required this.position,
    required this.fontSize,
    required this.expanded,
    this.isDesktopLyrics = false,
    this.desktopLyricsTextColor,
  });

  @override
  State<LyricFillText> createState() => KaraokeTextState();
}

/// Kept under its previous name: the desktop lyrics window builds it directly.
typedef KaraokeText = LyricFillText;

class KaraokeTextState extends State<LyricFillText>
    with SingleTickerProviderStateMixin {
  late final Ticker ticker;

  /// The position the fill is drawn at: the player's reports, smoothed between
  /// them so the wipe moves every frame instead of stepping.
  final ValueNotifier<Duration> drawPosition = ValueNotifier<Duration>(
    Duration.zero,
  );

  Duration lastReported = Duration.zero;
  DateTime lastSyncTime = DateTime.now();
  StreamSubscription<Duration>? positionSub;

  /// The player reports the position a few times a second; the ticker carries
  /// the fill across the gaps without ever running ahead of the voice.
  void _onReported(Duration position) {
    lastReported = position;
    lastSyncTime = DateTime.now();
    drawPosition.value = lyricDrawPosition(
      reported: position,
      smoothed: drawPosition.value,
    );
  }

  void _onTick(Duration _) {
    final now = DateTime.now();
    final elapsed = now.difference(lastSyncTime);
    lastSyncTime = now;
    drawPosition.value = lyricDrawPosition(
      reported: lastReported,
      smoothed: drawPosition.value + elapsed,
    );
  }

  void _playStateListener() {
    if (isPlayingNotifier.value) {
      lastSyncTime = DateTime.now();
      if (!ticker.isActive) {
        ticker.start();
      }
    } else {
      if (ticker.isActive) {
        ticker.stop();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    lastReported = widget.position;
    drawPosition.value = widget.position;
    ticker = createTicker(_onTick);
    isPlayingNotifier.addListener(_playStateListener);
    // The desktop lyrics window is a window of its own and is fed the position
    // it should draw; only the page follows the player directly.
    if (!widget.isDesktopLyrics) {
      positionSub = audioHandler.getPositionStream().listen(_onReported);
    }
    if (isPlayingNotifier.value) {
      ticker.start();
    }
  }

  @override
  void didUpdateWidget(covariant LyricFillText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new line, a seek, or the next position handed in by the lyrics window.
    drawPosition.value = lyricDrawPosition(
      reported: widget.position,
      smoothed: drawPosition.value,
    );
    lastReported = widget.position;
    lastSyncTime = DateTime.now();
  }

  @override
  void dispose() {
    positionSub?.cancel();
    positionSub = null;
    isPlayingNotifier.removeListener(_playStateListener);
    ticker.dispose();
    drawPosition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final played = widget.isDesktopLyrics
        ? (widget.desktopLyricsTextColor ?? Colors.white)
        : viewModeNotifier.value == .mini
        ? miniViewHighlightTextColor.value
        : lyricsPageHighlightTextColor.value;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final painter = LyricFillPainter(
          line: widget.line,
          position: drawPosition,
          playedColor: played,
          // What has not been sung yet is the same colour, held back: the line
          // reads as one line with a voice moving through it, rather than as a
          // bright half and a grey half.
          pendingColor: played.withValues(alpha: 0.6),
          style: TextStyle(
            fontSize: widget.fontSize,
            fontWeight: lyricsFontWeightNotifier.value,
          ),
          textAlign: widget.expanded ? TextAlign.left : TextAlign.center,
          offsetMs: lyricsTimeOffsetNotifier.value,
          maxWidth: maxWidth,
          shadows: widget.isDesktopLyrics
              ? const [
                  Shadow(
                    offset: Offset(2, 2),
                    blurRadius: 1,
                    color: Colors.black54,
                  ),
                ]
              : null,
        );
        return CustomPaint(size: painter.size, painter: painter);
      },
    );
  }
}

/// Draws one lyric line with the fill that sweeps across it.
///
/// Two passes over one layout: the whole line in the colour of what has not
/// been sung yet, then the sung part on top, clipped to the boxes those
/// characters occupy - a line that wraps puts them on two rows, and a single
/// rectangle would smear the fill across both. The character the fill is inside
/// gets a soft edge, which is what turns a progress bar into a voice.
///
/// All of that is one widget and one layer, and the ticker only repaints: the
/// old version put every word in its own widget with its own shader and rebuilt
/// the lot each frame.
class LyricFillPainter extends CustomPainter {
  final LyricLine line;
  final ValueListenable<Duration> position;
  final Color playedColor;
  final Color pendingColor;
  final TextStyle style;
  final TextAlign textAlign;
  final int offsetMs;
  final double maxWidth;
  final List<Shadow>? shadows;

  late final TextPainter _pending = _layout(pendingColor);
  late final TextPainter _played = _layout(playedColor);

  LyricFillPainter({
    required this.line,
    required this.position,
    required this.playedColor,
    required this.pendingColor,
    required this.style,
    required this.textAlign,
    required this.offsetMs,
    required this.maxWidth,
    this.shadows,
  }) : super(repaint: position);

  TextPainter _layout(Color colour) {
    return TextPainter(
      text: TextSpan(
        text: line.text,
        style: style.copyWith(color: colour, shadows: shadows),
      ),
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
    )..layout(maxWidth: maxWidth);
  }

  Size get size => Size(_pending.width, _pending.height);

  @override
  void paint(Canvas canvas, Size size) {
    _pending.paint(canvas, Offset.zero);

    final fill = lyricFillFor(
      line,
      position.value + Duration(milliseconds: offsetMs),
    );
    final sung = fill.characters.clamp(0, line.text.length);
    if (sung > 0) {
      _paintSung(canvas, TextSelection(baseOffset: 0, extentOffset: sung));
    }
    if (sung >= line.text.length || fill.fraction <= 0) {
      return;
    }
    _paintEdge(canvas, sung, fill.fraction);
  }

  /// The part of the line the voice has been through.
  void _paintSung(Canvas canvas, TextSelection range) {
    final boxes = _pending.getBoxesForSelection(range);
    if (boxes.isEmpty) {
      return;
    }
    final clip = Path();
    for (final box in boxes) {
      clip.addRect(box.toRect().inflate(0.5));
    }
    canvas.save();
    canvas.clipPath(clip);
    _played.paint(canvas, Offset.zero);
    canvas.restore();
  }

  /// The character the fill is in the middle of, faded out towards its end.
  void _paintEdge(Canvas canvas, int index, double fraction) {
    final boxes = _pending.getBoxesForSelection(
      TextSelection(baseOffset: index, extentOffset: index + 1),
    );
    if (boxes.isEmpty) {
      return;
    }
    final box = boxes.first.toRect().inflate(0.5);
    if (box.width <= 0) {
      return;
    }
    final soft = AppLyrics.fillEdgeEm * (style.fontSize ?? 16);
    final edge = box.left + box.width * fraction.clamp(0.0, 1.0);
    final mask = LinearGradient(
      colors: const [Colors.white, Colors.white, Colors.transparent],
      stops: [
        0,
        ((edge - soft - box.left) / box.width).clamp(0.0, 1.0),
        ((edge - box.left) / box.width).clamp(0.0, 1.0),
      ],
    ).createShader(box);

    canvas.saveLayer(box, Paint());
    canvas.clipRect(box);
    _played.paint(canvas, Offset.zero);
    canvas.drawRect(
      box,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = mask,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LyricFillPainter oldDelegate) {
    return oldDelegate.line != line ||
        oldDelegate.playedColor != playedColor ||
        oldDelegate.pendingColor != pendingColor ||
        oldDelegate.style != style ||
        oldDelegate.textAlign != textAlign ||
        oldDelegate.offsetMs != offsetMs ||
        oldDelegate.maxWidth != maxWidth ||
        oldDelegate.shadows != shadows;
  }
}
