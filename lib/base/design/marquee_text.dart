import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/design/app_tokens.dart';

/// A single line of text that scrolls itself when it does not fit.
///
/// Play bar titles were cut off with an ellipsis, so a long song name was
/// unreadable in exactly the place it matters most. Text that fits is rendered
/// as plain text and the animation is stopped, so the common case costs nothing
/// and this never animates off screen.
class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
    this.gap = 48,
  });

  final String text;

  /// How the line sits when it fits: the playback pages centre their titles.
  final TextAlign? textAlign;
  final TextStyle? style;

  /// Space between the end of one pass and the start of the next.
  final double gap;

  /// Seconds spent travelling the length of one copy of the text.
  static const Duration _secondsPerPass = Duration(seconds: 9);

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MarqueeText._secondsPerPass,
  );

  bool _scrolling = false;

  @override
  void initState() {
    super.initState();
    // The setting can be changed while this is on screen: a title in the bar
    // should stop travelling the moment it is switched on, not at the next song.
    reducedMotionModeNotifier.addListener(_onMotionSettingChanged);
  }

  void _onMotionSettingChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    reducedMotionModeNotifier.removeListener(_onMotionSettingChanged);
    _controller.dispose();
    super.dispose();
  }

  /// Starts or stops the loop to match what is being rendered.
  void _setScrolling(bool value) {
    if (value == _scrolling) {
      return;
    }
    _scrolling = value;
    if (value) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();

        final available = constraints.maxWidth;
        if (!available.isFinite || painter.width <= available) {
          _setScrolling(false);
          return Text(
            widget.text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.clip,
            textAlign: widget.textAlign,
          );
        }

        if (prefersReducedMotion(context)) {
          // The title does not fit and the platform asked for less movement: an
          // ellipsis is quieter than a line that keeps travelling, and the full
          // name is still a click away on the playback screen.
          _setScrolling(false);
          return Text(
            widget.text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: widget.textAlign,
          );
        }

        _setScrolling(true);
        final distance = painter.width + widget.gap;
        final second = ExcludeSemantics(
          child: Text(widget.text, style: style, maxLines: 1),
        );

        return ClipRect(
          // The travelling row is wider than the slot it travels through, so it
          // is laid out unbounded and then clipped: without this the row reports
          // an overflow on every rebuild in a debug build.
          child: OverflowBox(
            maxWidth: double.infinity,
            alignment: AlignmentDirectional.centerStart,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(-_controller.value * distance, 0),
                  child: child,
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.text, style: style, maxLines: 1),
                  SizedBox(width: widget.gap),
                  // The second copy is what makes the loop read as continuous;
                  // it is hidden from screen readers so the title is announced
                  // once.
                  second,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
