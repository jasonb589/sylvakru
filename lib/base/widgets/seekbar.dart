import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/design/app_tokens.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/utils/common_utils.dart';
import 'package:sylvakru/base/utils/media_query.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:sylvakru/base/widgets/full_width_track_shape.dart';

/// The progress bar, and how it answers a pointer.
///
/// On a desktop the pointer is over the bar long before anything is pressed, so
/// hovering counts as a question - "where would this land?" - and the bar
/// answers it: the time under the pointer, and a thumb and track that take hold
/// of the spot as it arrives - one 150 ms step, the same one a drag gets - so
/// arriving, dragging and leaving read as one bar changing its mind rather than
/// three separate reactions.
class SeekBar extends StatefulWidget {
  final Color? color;
  final bool isMiniMode;
  final double widgetHeight;
  final double seekBarHeight;

  const SeekBar({
    super.key,
    this.color,
    this.isMiniMode = false,
    required this.widgetHeight,
    required this.seekBarHeight,
  });
  @override
  State<SeekBar> createState() => SeekBarState();
}

class SeekBarState extends State<SeekBar> {
  double? dragValue;
  bool isDragging = false; // track if user is touching the thumb
  double horizontalPadding = 0;

  /// Where the pointer is, in milliseconds into the song. Null when it is not
  /// over the bar.
  double? hoverValue;

  /// The preview the bubble is fading out with. Held so it stays where the
  /// pointer left it instead of jumping back to the song's own position as it
  /// goes.
  double? _bubbleValue;

  /// Smallest vertical touch target the seekbar accepts.
  static const double _minTouchTarget = 24;

  /// The bar needs this much height before a time bubble fits above the track.
  /// The compact bars in the control rows are shorter than this, and there the
  /// preview is shown by the left-hand readout instead.
  static const double _bubbleHeightNeeded = 30;

  /// The value a pointer at [dx] points at, with the bar's horizontal padding
  /// taken out and the ends clamped.
  ///
  /// Kept as a plain function of the numbers so the mapping can be checked
  /// without a player, a window or a pointer.
  static double previewValue({
    required double dx,
    required double width,
    required double durationMs,
    required double padding,
  }) {
    final usable = width - padding * 2;
    if (usable <= 0 || durationMs <= 0) {
      return 0;
    }
    final relative = ((dx - padding) / usable).clamp(0.0, 1.0);
    return relative * durationMs;
  }

  /// What the bar is showing right now: the drag if there is one, otherwise the
  /// pointer, otherwise nothing.
  double? get _previewValue => dragValue ?? hoverValue;

  bool get _isEmphasised => isDragging || hoverValue != null;

  @override
  Widget build(BuildContext context) {
    horizontalPadding = 0;
    if (!isTooNarrow(context) && !widget.isMiniMode) {
      horizontalPadding = 45;
    }

    // Never let the touch target collapse to the visual track height.
    final touchHeight = widget.widgetHeight < _minTouchTarget
        ? widget.widgetHeight
        : _minTouchTarget;

    return StreamBuilder(
      stream: audioHandler.getDurationStream(),
      builder: (context, asyncSnapshot) {
        Duration duration = getDuration(currentSongNotifier.value);
        if (duration <= Duration.zero) {
          duration = audioHandler.getCurrentDuration();
        }
        final durationMs = duration.inMilliseconds.toDouble();

        return StreamBuilder<Duration>(
          stream: audioHandler.getPositionStream(),
          builder: (context, snapshot) {
            final position = snapshot.data ?? audioHandler.getPosition();
            double sliderValue =
                dragValue ?? position.inMilliseconds.toDouble();
            if (playQueue.isEmpty) {
              sliderValue = 0;
            }

            // The value the readout and the bubble show: while the pointer or a
            // drag is on the bar, that is where the song would be.
            final preview = playQueue.isEmpty ? null : _previewValue;
            final shownValue = preview ?? sliderValue;

            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final accent = widget.color ?? seekBarColor.value;

                return SizedBox(
                  height: widget.widgetHeight,
                  // The bubble floats above the track, so nothing is clipped.
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    clipBehavior: Clip.none,
                    children: [
                      // Duration labels, the left one carrying the preview.
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: isMobile ? 0 : 2,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              formatDuration(
                                Duration(milliseconds: shownValue.toInt()),
                              ),
                              style: TextStyle(
                                color: widget.color,
                                fontWeight: preview == null
                                    ? null
                                    : FontWeight.bold,
                                fontSize: isMobile
                                    ? null
                                    : widget.isMiniMode
                                    ? 10.5
                                    : 12.5,
                              ),
                            ),
                            Text(
                              formatDuration(duration),
                              style: TextStyle(
                                color: widget.color,
                                fontSize: isMobile
                                    ? null
                                    : widget.isMiniMode
                                    ? 10.5
                                    : 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Slider visuals: the track and the thumb take hold of
                      // the spot together, over one step - a pointer arriving
                      // and a drag starting read as the same bar.
                      SizedBox(
                        height: widget.seekBarHeight,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: _isEmphasised ? 1 : 0),
                          duration: AppDuration.quick,
                          curve: AppCurve.enter,
                          builder: (context, emphasis, child) {
                            return SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                thumbColor: accent,
                                trackHeight: 2 + 2 * emphasis,
                                trackShape: const FullWidthTrackShape(),
                                thumbShape: RoundSliderThumbShape(
                                  enabledThumbRadius: 5 * emphasis,
                                ),
                                overlayShape: SliderComponentShape.noOverlay,
                                activeTrackColor: accent,
                                // Derived from the track colour instead of a
                                // fixed black tint, which disappeared on a dark
                                // theme.
                                inactiveTrackColor: accent.withValues(
                                  alpha: 0.25,
                                ),
                              ),
                              child: child!,
                            );
                          },
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding,
                            ),
                            child: ExcludeFocus(
                              child: Slider(
                                min: 0.0,
                                max: durationMs,
                                value: sliderValue.clamp(0.0, durationMs),
                                onChanged: (value) {},
                              ),
                            ),
                          ),
                        ),
                      ),

                      // The time under the pointer, where the bar has room for
                      // it: the compact bars show it in the readout instead.
                      // The time under the pointer, where the bar has room for
                      // it. It leaves over the same step the thumb does, from
                      // the place the pointer left it.
                      if (widget.widgetHeight >= _bubbleHeightNeeded &&
                          _bubbleValue != null)
                        Positioned(
                          left: _bubbleLeft(
                            width,
                            durationMs <= 0
                                ? 0.0
                                : (_bubbleValue! / durationMs).clamp(0.0, 1.0),
                          ),
                          top: 0,
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: preview == null ? 0 : 1,
                              duration: prefersReducedMotion(context)
                                  ? AppDuration.none
                                  : AppDuration.quick,
                              curve: AppCurve.enter,
                              child: _TimeBubble(
                                text: formatDuration(
                                  Duration(milliseconds: _bubbleValue!.toInt()),
                                ),
                                accent: accent,
                              ),
                            ),
                          ),
                        ),

                      // Full-track GestureDetector to capture touches anywhere
                      // on the track, wrapped so the pointer is reported too.
                      Positioned.fill(
                        top: (widget.widgetHeight - touchHeight) / 2,
                        bottom: (widget.widgetHeight - touchHeight) / 2,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onHover: (event) {
                            if (currentSongNotifier.value == null) {
                              return;
                            }
                            setState(() {
                              hoverValue = _bubbleValue = previewValue(
                                dx: event.localPosition.dx,
                                width: width,
                                durationMs: durationMs,
                                padding: horizontalPadding,
                              );
                            });
                          },
                          onExit: (_) {
                            if (hoverValue == null) {
                              return;
                            }
                            setState(() => hoverValue = null);
                          },
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onVerticalDragStart: (_) {
                              setState(() => isDragging = false);
                            },
                            onTapDown: (_) {
                              if (currentSongNotifier.value == null) {
                                return;
                              }
                              setState(() => isDragging = true);
                            },
                            onHorizontalDragUpdate: (details) {
                              if (currentSongNotifier.value == null) {
                                return;
                              }
                              seekByTouch(
                                details.localPosition.dx,
                                width,
                                durationMs,
                              );
                              setState(() {
                                isDragging = true;
                              });
                            },
                            onHorizontalDragEnd: (_) async {
                              if (currentSongNotifier.value == null) {
                                return;
                              }
                              if (dragValue != null) {
                                await audioHandler.seek(
                                  Duration(milliseconds: dragValue!.toInt()),
                                );
                              }
                              setState(() {
                                dragValue = null;
                                isDragging = false;
                              });
                            },
                            onTapUp: (details) async {
                              if (currentSongNotifier.value == null) {
                                return;
                              }
                              seekByTouch(
                                details.localPosition.dx,
                                width,
                                durationMs,
                              );
                              await audioHandler.seek(
                                Duration(milliseconds: dragValue!.toInt()),
                              );
                              setState(() {
                                dragValue = null;
                                isDragging = false;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// Keeps the bubble inside the bar: half a bubble's width from either end.
  double _bubbleLeft(double width, double valueFraction) {
    const halfBubble = 30.0;
    final centre =
        horizontalPadding + valueFraction * (width - horizontalPadding * 2);
    return (centre - halfBubble).clamp(
      0.0,
      (width - halfBubble * 2).clamp(0.0, width),
    );
  }

  /// Map a position on the bar to a value. The pointer and the finger both go
  /// through here, so hovering and dragging cannot disagree about where a point
  /// on the bar is.
  void seekByTouch(double dx, double width, double durationMs) {
    dragValue = _bubbleValue = previewValue(
      dx: dx,
      width: width,
      durationMs: durationMs,
      padding: horizontalPadding,
    );
  }
}

/// The small readout that follows the pointer along the bar.
///
/// Coloured like the bar itself on the surface colour, so it belongs to the
/// track and needs no colour of its own.
class _TimeBubble extends StatelessWidget {
  final String text;
  final Color accent;

  const _TimeBubble({required this.text, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colorManager.getSpecificBgColor(),
        borderRadius: BorderRadius.circular(AppRadius.coverTiny),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        boxShadow: AppShadow.card(accent),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: accent,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
