import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

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

/// Whether lines far from the one being sung are blurred, for depth at the
/// edges of the view. Off by default: it costs a layer per line.
final lyricsFarBlurNotifier = ValueNotifier<bool>(false);

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
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final ItemScrollController itemScrollController = ItemScrollController();
  final ValueNotifier<int> currentIndexNotifier = ValueNotifier<int>(-1);

  /// Bumped when the list lands somewhere far away instead of travelling there
  /// (a seek, a return from the other end of the song). Each bump fades the
  /// list back in where it arrived.
  final ValueNotifier<int> resetFadeNotifier = ValueNotifier<int>(0);

  /// The clock the whole page is laid out from: the player's reports, carried
  /// forward between them. The line that is highlighted and the fill that sweeps
  /// through it both read this one, so they cannot disagree about where the
  /// voice is.
  final ValueNotifier<Duration> drawPositionNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );

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

  /// The player's last word on where the voice is, and when it arrived. The
  /// position is carried forward in real time from there, so a line changes on
  /// the frame it is due rather than on the next property notification: those
  /// arrive about every 50 ms, which on its own is a visible delay between the
  /// voice and the words.
  late final Ticker _clock;
  Duration _reported = Duration.zero;
  Duration _drawPosition = Duration.zero;
  DateTime _lastSync = DateTime.now();

  /// The anchor a line rests at: the current line sits above the middle, so the
  /// next one is already in view and the list reads as moving forward.
  double get _alignment => widget.expanded ? 0.30 : 0.42;

  /// Drives the crossfade of the lines that take part in a switch.
  late final AnimationController switchClock;

  /// The line that was being sung before the current one, so every line knows
  /// which two steps it is crossing.
  int _previousIndex = -1;

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
    if (current != previous) {
      // One clock for the switch: the lines near the one being sung cross their
      // steps together instead of each carrying a tween of its own.
      _previousIndex = previous;
      switchClock.forward(from: 0);
    }
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
    } else if (lyricListNeedsCatchUp(
      lineChanged: current != previous,
      scrolledTo: _scrolledTo,
      target: target,
    )) {
      // The list is not on this line and the head start did not bring it here:
      // a seek, a stalled frame, or a return from the listener's own scrolling.
      // While the next line's scroll is under way the list is one item ahead on
      // purpose, which is not "behind" and must not be corrected.
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
      duration: prefersReducedMotion(context)
          ? AppDuration.none
          : Duration(milliseconds: lyricScrollMs(distance)),
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
    positionSub = audioHandler.getPositionStream().listen(_onPosition);
  }

  /// The player spoke: from here on that position is the truth, and the clock
  /// only has to carry it across the gap until the next report.
  void _onPosition(Duration position) {
    _reported = position;
    _lastSync = DateTime.now();
    _advance();
  }

  /// Moves the clock on by the elapsed time and lays the list out from it.
  void _advance() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastSync);
    _lastSync = now;
    _drawPosition = lyricDrawPosition(
      reported: _reported,
      smoothed: _drawPosition + elapsed,
    );
    drawPositionNotifier.value = _drawPosition;
    scroll2CurrentIndex(_drawPosition);
  }

  void _playStateListener() {
    if (isPlayingNotifier.value) {
      _lastSync = DateTime.now();
      if (!_clock.isActive) {
        _clock.start();
      }
    } else if (_clock.isActive) {
      _clock.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    lines = widget.lines;
    _clock = createTicker((_) => _advance());
    switchClock = AnimationController(
      vsync: this,
      duration: AppLyrics.lineSwitch,
      value: 1,
    );
    isPlayingNotifier.addListener(_playStateListener);
    _reported = audioHandler.getPosition();
    _drawPosition = _reported;
    _lastSync = DateTime.now();
    scroll2CurrentIndex(_drawPosition);
    _listen();
    if (isPlayingNotifier.value) {
      _clock.start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Stop listening when lyrics page is closed
    positionSub?.cancel();
    positionSub = null;
    isPlayingNotifier.removeListener(_playStateListener);
    _clock.dispose();
    switchClock.dispose();

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
          _reported = audioHandler.getPosition();
          _drawPosition = _reported;
          _lastSync = DateTime.now();
          scroll2CurrentIndex(_drawPosition);
          _listen();
          if (isPlayingNotifier.value && !_clock.isActive) {
            _clock.start();
          }
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
                  clock: drawPositionNotifier,
                  switchClock: switchClock,
                  previousIndex: _previousIndex,
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
///
/// The two things a listener can do to a line are answered here. The pointer
/// marks the line under it with a bar at the row's left edge rather than with a
/// tint across the whole row, and a tap answers with a short pulse before the
/// seek it starts moves the view anyway.
class LyricLineWidget extends StatefulWidget {
  final int index;
  final LyricLine line;
  final ValueNotifier<int> currentIndexNotifier;

  /// The page's clock, handed down so the fill sweeps on the same position the
  /// highlight changed on.
  final ValueListenable<Duration>? clock;

  /// The page's switch clock, so the lines near the one being sung cross their
  /// steps together instead of each carrying a tween of its own.
  final Animation<double>? switchClock;

  /// The line that was being sung before the current one: which two steps this
  /// line is crossing.
  final int? previousIndex;
  final bool expanded;
  final bool isKaraoke;

  const LyricLineWidget({
    super.key,
    required this.line,
    required this.index,
    required this.currentIndexNotifier,
    required this.expanded,
    required this.isKaraoke,
    this.switchClock,
    this.previousIndex,
    this.clock,
  });

  @override
  State<LyricLineWidget> createState() => _LyricLineWidgetState();
}

class _LyricLineWidgetState extends State<LyricLineWidget>
    with SingleTickerProviderStateMixin {
  /// Built on the first tap rather than for every line on screen: a page of
  /// twenty lines should not carry twenty controllers for one thing each.
  AnimationController? _pulse;

  bool _hovered = false;

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  void _tapLine() {
    final pulse = _pulse ??= AnimationController(
      vsync: this,
      duration: AppLyrics.tapPulse,
    );
    pulse.forward(from: 0);
    // The seek target has to be the one the offset is applied back onto, or a
    // tap lands on the line before the one that was tapped. See
    // [lyricSeekTarget].
    audioHandler.seek(
      lyricSeekTarget(widget.line, lyricsTimeOffsetNotifier.value),
    );
  }

  /// [build] with the tap pulse, or with no pulse at all while this line has
  /// never been tapped.
  Widget _withPulse(Widget Function(double pulse) build) {
    final pulse = _pulse;
    if (pulse == null || prefersReducedMotion(context)) {
      return build(0);
    }
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) => build(lyricTapPulse(pulse.value)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expanded = widget.expanded;
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
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          hoverColor: Colors.transparent,
          onTap: _tapLine,
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
                widget.currentIndexNotifier,
                lyricsFarBlurNotifier,
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

                // Only the lines next to the one being sung cross their steps,
                // and they cross them together on the page's switch clock.
                // Every other line looks the same at either distance, so
                // animating it was a rebuild per frame with nothing to show.
                final current = widget.currentIndexNotifier.value;
                final oldDistance = lyricDistance(
                  widget.index,
                  widget.previousIndex ?? current,
                );
                final newDistance = lyricDistance(widget.index, current);
                final switchClock = widget.switchClock;
                if (switchClock == null ||
                    !lyricLineNeedsSwitchAnimation(oldDistance, newDistance)) {
                  return _line(
                    newDistance.toDouble(),
                    textColor,
                    highlightTextColor,
                    fontSize,
                    expanded,
                    settled: true,
                  );
                }
                return AnimatedBuilder(
                  animation: switchClock,
                  builder: (context, _) => _line(
                    lyricSwitchDistance(
                      oldDistance,
                      newDistance,
                      AppCurve.enter.transform(switchClock.value),
                    ),
                    textColor,
                    highlightTextColor,
                    fontSize,
                    expanded,
                    settled: switchClock.value >= 1,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// One line at [distance] steps from the one being sung.
  ///
  /// [settled] is false while the line is still crossing its steps: the blur
  /// waits until it has arrived, because a line in motion already has the eye
  /// and a filter would add a layer per frame on top of that.
  Widget _line(
    double distance,
    Color textColor,
    Color highlightTextColor,
    double fontSize,
    bool expanded, {
    required bool settled,
  }) {
    final line = widget.line;
    final near = distance.clamp(0.0, 1.0);
    final colour = Color.lerp(textColor, highlightTextColor, 1 - near)!;
    final opacity = lyricLineOpacity(distance);
    final weight = lyricLineWeight(lyricsFontWeightNotifier.value, distance);
    // The platform's "less motion" turns off what is only decoration: a line
    // that grows as it moves away from the one being sung.
    final reduced = prefersReducedMotion(context);

    return _withPulse((pulse) {
      // A tap lifts the line a little, on top of where it already stands for
      // its distance.
      final strength = (opacity + 0.25 * pulse).clamp(0.0, 1.0);
      Widget content = Transform.scale(
        scale: reduced ? 1.0 : lyricLineScale(distance) * (1 + 0.02 * pulse),
        alignment: expanded ? .centerLeft : .center,
        // Inside the transform: a scale is then composited over the cached
        // raster instead of drawing the text again on every frame.
        child: RepaintBoundary(
          child: Column(
            crossAxisAlignment: expanded ? .start : .center,
            children: [
              if (near < 1)
                // Being sung, or about to be: the fill sweeps across it. Every
                // other line is text at its own strength.
                LyricFillText(
                  line: line,
                  position: audioHandler.getPosition(),
                  clock: widget.clock,
                  fontSize: fontSize,
                  expanded: expanded,
                  colour: colour.withValues(alpha: strength),
                )
              else
                Text(
                  line.text,
                  textAlign: expanded ? .start : .center,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: weight,
                    color: colour.withValues(alpha: strength),
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
                      alpha: strength * (near >= 1 ? 0.85 : 0.8),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

      final sigma = settled && lyricsFarBlurNotifier.value && !reduced
          ? lyricFarBlurSigma(distance)
          : 0.0;
      if (sigma > 0.01) {
        content = ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: content,
        );
      }

      return Stack(
        alignment: expanded ? .topStart : .topCenter,
        clipBehavior: Clip.none,
        children: [
          content,
          Positioned(
            left: -12,
            top: 0,
            bottom: 0,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: _hovered ? 1 : 0),
              duration: AppDuration.quick,
              curve: AppCurve.enter,
              builder: (context, value, child) =>
                  Opacity(opacity: value, child: child),
              child: Center(
                child: Container(
                  width: AppLyrics.hoverBarWidth,
                  height: fontSize * 1.2,
                  decoration: BoxDecoration(
                    color: colour.withValues(alpha: AppLyrics.hoverBarAlpha),
                    borderRadius: BorderRadius.circular(
                      AppLyrics.hoverBarWidth / 2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// One line of lyrics with the fill that sweeps across it.
///
/// Also used by the desktop lyrics window, which draws it on its own dark
/// backdrop and therefore brings its own colour.
class LyricFillText extends StatefulWidget {
  final LyricLine line;
  final Duration position;

  /// The page's clock. When one is handed in, this widget stops keeping its own:
  /// the highlight and the fill then read the same position, which is what keeps
  /// the words with the voice. The desktop lyrics window has no page to hand one
  /// over, so it keeps its own.
  final ValueListenable<Duration>? clock;
  final double fontSize;
  final bool expanded;
  final bool isDesktopLyrics;

  /// The colour the line is drawn in. The page hands in the colour a line has
  /// at its distance from the one being sung - so the fill keeps the same
  /// colour while a line takes over from another - and the desktop lyrics
  /// window brings the one its own dark backdrop needs.
  final Color? colour;

  const LyricFillText({
    super.key,
    required this.line,
    required this.position,
    required this.fontSize,
    required this.expanded,
    this.clock,
    this.isDesktopLyrics = false,
    this.colour,
  });

  @override
  State<LyricFillText> createState() => KaraokeTextState();
}

/// Kept under its previous name: the desktop lyrics window builds it directly.
typedef KaraokeText = LyricFillText;

class KaraokeTextState extends State<LyricFillText>
    with SingleTickerProviderStateMixin {
  Ticker? ticker;

  /// The position the fill is drawn at, when this widget keeps its own clock:
  /// the player's reports, smoothed between them so the wipe moves every frame
  /// instead of stepping.
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
    final ticker = this.ticker;
    if (ticker == null) {
      return;
    }
    if (isPlayingNotifier.value) {
      lastSyncTime = DateTime.now();
      if (!ticker.isActive) {
        ticker.start();
      }
    } else if (ticker.isActive) {
      ticker.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.clock != null) {
      return;
    }
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
      ticker!.start();
    }
  }

  @override
  void didUpdateWidget(covariant LyricFillText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.clock != null) {
      return;
    }
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
    ticker?.dispose();
    drawPosition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The page hands in the colour a line has at its distance from the one
    // being sung, so a line taking over keeps its colour while it crosses; the
    // desktop lyrics window brings the colour of its own backdrop.
    final played =
        widget.colour ??
        (widget.isDesktopLyrics
            ? Colors.white
            : viewModeNotifier.value == .mini
            ? miniViewHighlightTextColor.value
            : lyricsPageHighlightTextColor.value);

    final lineStyle = TextStyle(
      fontSize: widget.fontSize,
      fontWeight: lyricsFontWeightNotifier.value,
    );
    final painter = LyricFillPainter(
      line: widget.line,
      position: widget.clock ?? drawPosition,
      playedColor: played,
      // What has not been sung yet is the same colour, held back: the line
      // reads as one line with a voice moving through it, rather than as a
      // bright half and a grey half. The desktop window recedes further,
      // because there the reveal is the only thing moving.
      pendingColor: played.withValues(
        alpha: widget.isDesktopLyrics ? 0.35 : 0.6,
      ),
      style: lineStyle,
      textAlign: widget.expanded ? TextAlign.left : TextAlign.center,
      offsetMs: lyricsTimeOffsetNotifier.value,
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
    // The transparent copy of the line is the box the fill is drawn in, and it
    // is what tells a window that sizes itself from intrinsics - the desktop
    // lyrics window does - how wide the line wants to be. Without it, and with
    // the LayoutBuilder that used to sit here, the line answered every intrinsic
    // query with zero: the window closed itself to its minimum width and cut the
    // rest of the line off.
    return CustomPaint(
      painter: painter,
      child: Text(
        widget.line.text,
        textAlign: widget.expanded ? TextAlign.left : TextAlign.center,
        style: lineStyle.copyWith(color: Colors.transparent),
      ),
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
  final List<Shadow>? shadows;

  /// The two layouts, rebuilt only when the width this line is drawn at changes.
  ///
  /// The width used to be handed in from a LayoutBuilder, which sizes the line
  /// correctly but answers every intrinsic query with zero - and the desktop
  /// lyrics window measures exactly that way, so it kept closing itself to its
  /// minimum and cutting the tail off the line. The width now comes from the
  /// box the line is painted in, which the transparent measuring child defines.
  TextPainter? _pendingCache;
  TextPainter? _playedCache;
  double _laidOutWidth = -1;

  LyricFillPainter({
    required this.line,
    required this.position,
    required this.playedColor,
    required this.pendingColor,
    required this.style,
    required this.textAlign,
    required this.offsetMs,
    this.shadows,
  }) : super(repaint: position);

  void _ensureLaidOut(double width) {
    final target = width.isFinite && width > 0 ? width : double.infinity;
    if (_laidOutWidth == target && _pendingCache != null) {
      return;
    }
    _laidOutWidth = target;
    _pendingCache = _layout(pendingColor, target);
    _playedCache = _layout(playedColor, target);
  }

  TextPainter get _pending => _pendingCache!;

  TextPainter get _played => _playedCache!;

  TextPainter _layout(Color colour, double width) {
    return TextPainter(
      text: TextSpan(
        text: line.text,
        style: style.copyWith(color: colour, shadows: shadows),
      ),
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
    )..layout(maxWidth: width);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _ensureLaidOut(size.width);
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
        oldDelegate.shadows != shadows;
  }
}
