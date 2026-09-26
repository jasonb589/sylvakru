import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/design/app_tokens.dart';
import 'package:sylvakru/base/services/color_manager.dart';

/// Derives the placeholder tone from the icon colour the surrounding surface
/// already uses, so a loading surface never introduces a new colour.
Color _placeholderColour() => iconColor.value.withAlpha(45);

/// A placeholder block for content that has not arrived yet.
///
/// It takes the place the real content will occupy and the size it will have,
/// so the surface keeps its layout instead of jumping when the data lands.
/// Wrap it in a [SkeletonPulse] to read as "loading" rather than as an empty
/// grey box.
class SkeletonBox extends StatelessWidget {
  /// Block width. Null lets the block fill the available width.
  final double? width;

  /// Block height. Null lets the block fill the available height.
  final double? height;

  /// Corner radius. Leave at zero inside the cover art widget, which already
  /// clips its own [Material].
  final double radius;

  /// Overrides the derived placeholder colour.
  final Color? color;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = 0,
    this.color,
  });

  /// A square block, for a cover.
  const SkeletonBox.square(
    double size, {
    super.key,
    this.radius = 0,
    this.color,
  }) : width = size,
       height = size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color ?? _placeholderColour(),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// Pulses [child] slowly between two opacities.
///
/// One controller per surface rather than one per block: a skeleton row of six
/// blocks still costs a single ticker.
class SkeletonPulse extends StatefulWidget {
  final Widget child;

  const SkeletonPulse({super.key, required this.child});

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDuration.pulse,
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(
    begin: 0.45,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: AppCurve.standard));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}

/// The placeholder for a loading list of songs: cover plus two text bars, on
/// the row metrics the song lists use.
class SkeletonList extends StatelessWidget {
  /// How many rows to draw.
  final int rows;

  /// Row height, matching the list this stands in for.
  final double rowHeight;

  /// Cover size inside a row.
  final double coverSize;

  const SkeletonList({
    super.key,
    this.rows = 8,
    this.rowHeight = 60,
    this.coverSize = 45,
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemExtent: rowHeight,
        itemCount: rows,
        itemBuilder: (context, index) => Row(
          children: [
            const SizedBox(width: 20),
            SkeletonBox.square(coverSize, radius: AppRadius.coverRow),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                mainAxisAlignment: .center,
                crossAxisAlignment: .start,
                children: [
                  SkeletonBox(
                    width: 220,
                    height: 12,
                    radius: AppRadius.coverTiny,
                  ),
                  const SizedBox(height: 8),
                  SkeletonBox(
                    width: 130,
                    height: 10,
                    radius: AppRadius.coverTiny,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
          ],
        ),
      ),
    );
  }
}

/// The placeholder for a loading grid of album or artist cards.
///
/// The cross axis extent only approximates the real grid: this stands in for
/// one, and is on screen only until the collection arrives.
class SkeletonGrid extends StatelessWidget {
  /// How many cards to draw.
  final int cards;

  /// Upper bound for the width of a card.
  final double maxExtent;

  /// Width over height of a card.
  final double aspectRatio;

  /// Horizontal inset, matching the grid this stands in for.
  final double horizontalPadding;

  const SkeletonGrid({
    super.key,
    this.cards = 12,
    this.maxExtent = 190,
    this.aspectRatio = 0.78,
    this.horizontalPadding = 40,
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 10,
        ),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: maxExtent,
          childAspectRatio: aspectRatio,
        ),
        itemCount: cards,
        itemBuilder: (context, index) => Column(
          crossAxisAlignment: .start,
          children: [
            Expanded(child: SkeletonBox(radius: AppRadius.coverCard)),
            const SizedBox(height: 8),
            SkeletonBox(width: 90, height: 10, radius: AppRadius.coverTiny),
          ],
        ),
      ),
    );
  }
}
