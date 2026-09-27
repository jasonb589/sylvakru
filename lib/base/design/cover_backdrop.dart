import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/design/app_tokens.dart';

/// The blurred, cover-derived backdrop behind a full-screen surface.
///
/// This replaces four near-copies that had drifted apart: two used a radius
/// proportional to the window while two used a fixed sigma, three animated the
/// colour over 500ms/300ms and one changed it instantly, and only one isolated
/// its repaint. Sharing one widget means a track change fades the same way on
/// every screen, and a resize cannot repaint the tree behind the blur in the
/// same frame as the blur recompute.
///
/// It also carries the two motions the surface used to lack. The colours drift
/// along slow, unrelated paths - one lap takes [AppDuration.drift] - so a still
/// cover never reads as a still screen, and they breathe while the player is
/// running, which gives the surface a pulse without pretending to know the
/// track's tempo. A track change blends two whole palettes rather than easing
/// one flat colour into another.
///
/// The tint stays at [AppBlur.backdropAlpha] underneath the drift: the text on
/// these surfaces was picked for that contrast, and the movement must not take
/// it away.
///
/// The caller listens to whatever signals a colour change and builds this with
/// the new values.
class CoverBackdrop extends StatefulWidget {
  const CoverBackdrop({super.key, required this.colour, this.palette});

  /// The colour derived from the current cover art: the tint the surface is
  /// read against, and the colour the text on it was chosen for.
  final Color colour;

  /// The colours to drift between, [colour] first. A shorter list - or none at
  /// all - simply drifts less, which is how this looked before the palette
  /// existed.
  final List<Color>? palette;

  @override
  State<CoverBackdrop> createState() => _CoverBackdropState();
}

class _CoverBackdropState extends State<CoverBackdrop>
    with TickerProviderStateMixin {
  late final AnimationController _drift;
  late final AnimationController _fade;
  late final AnimationController _breath;

  /// The palette being left behind and the one arriving. Keeping both means a
  /// track change is a blend of two gradients, not a jump between two.
  late List<Color> _target;
  List<Color> _previous = const [];

  @override
  void initState() {
    super.initState();
    _target = _resolved(widget.palette);
    _drift = AnimationController(vsync: this, duration: AppDuration.drift)
      ..repeat();
    _fade = AnimationController(
      vsync: this,
      duration: AppDuration.backdrop,
      value: 1,
    );
    _breath = AnimationController(vsync: this, duration: AppDuration.breath);
    isPlayingNotifier.addListener(_syncBreath);
    _syncBreath();
  }

  @override
  void didUpdateWidget(covariant CoverBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _resolved(widget.palette);
    if (_sameColours(next, _target)) {
      return;
    }
    _previous = _displayed();
    _target = next;
    _fade.forward(from: 0);
  }

  @override
  void dispose() {
    isPlayingNotifier.removeListener(_syncBreath);
    _drift.dispose();
    _fade.dispose();
    _breath.dispose();
    super.dispose();
  }

  List<Color> _resolved(List<Color>? palette) {
    if (palette == null || palette.isEmpty) {
      return [widget.colour];
    }
    return palette;
  }

  /// The palette as it is on screen right now, so a change that starts mid-fade
  /// continues from what the listener is looking at.
  List<Color> _displayed() {
    if (_previous.isEmpty || _fade.value >= 1) {
      return _target;
    }
    return _blend(_previous, _target, AppCurve.colour.transform(_fade.value));
  }

  void _syncBreath() {
    if (isPlayingNotifier.value) {
      if (!_breath.isAnimating) {
        _breath.repeat(reverse: true);
      }
    } else if (_breath.isAnimating) {
      // Come to rest rather than freeze mid-breath.
      _breath.animateBack(
        0,
        duration: AppDuration.calm,
        curve: AppCurve.standard,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final sigma = AppBlur.backdropSigma(
      size.width < size.height ? size.width : size.height,
    );

    // ClipRect keeps the blur inside the surface; the RepaintBoundary gives the
    // always-visible blur its own layer so a resize does not force the tree
    // behind it to repaint in the same frame. Painting through a CustomPaint
    // keeps each drift frame to one boundaried repaint.
    return ClipRect(
      child: RepaintBoundary(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: AnimatedBuilder(
            animation: Listenable.merge([_drift, _fade, _breath]),
            builder: (context, child) {
              return CustomPaint(
                size: Size.infinite,
                painter: _BackdropPainter(
                  colours: _displayed(),
                  phase: _drift.value,
                  breath: _breath.value,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Paints the flat tint followed by the drifting colours.
class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({
    required this.colours,
    required this.phase,
    required this.breath,
  });

  final List<Color> colours;

  /// 0-1, one slow lap of the drifting colours.
  final double phase;

  /// 0-1, with the colours pushed outwards at the top of a breath.
  final double breath;

  /// Where each drifting colour wanders: centre, amplitude and frequency for x,
  /// then the same for y, as fractions of the surface. The six numbers are
  /// deliberately unrelated - sharing a period would line the colours up and
  /// the motion would read as a pulse instead of a drift.
  static const List<List<double>> _paths = [
    [0.30, 0.22, 0.31, 0.32, 0.20, 0.47],
    [0.72, 0.18, 0.53, 0.30, 0.24, 0.29],
    [0.34, 0.24, 0.23, 0.70, 0.18, 0.41],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = colours.first.withValues(alpha: AppBlur.backdropAlpha / 255),
    );

    final radius = size.longestSide * 0.62 * (1 + AppBlur.breathScale * breath);
    final alpha = AppBlur.driftAlpha / 255;

    for (var i = 1; i < colours.length; i++) {
      final path = _paths[(i - 1) % _paths.length];
      // The per-colour offsets keep two colours that happen to share a
      // frequency from travelling as a pair.
      final centre = Offset(
        (path[0] +
                path[1] *
                    math.sin(2 * math.pi * (phase * path[2] + i * 0.17))) *
            size.width,
        (path[3] +
                path[4] *
                    math.cos(2 * math.pi * (phase * path[5] + i * 0.11))) *
            size.height,
      );
      final colour = colours[i];
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(centre, radius, [
            colour.withValues(alpha: alpha),
            colour.withValues(alpha: 0),
          ]),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.breath != breath ||
        !_sameColours(oldDelegate.colours, colours);
  }
}

/// Blends two palettes colour by pair, so a track change cross-fades the whole
/// gradient instead of jumping between two.
List<Color> _blend(List<Color> from, List<Color> to, double t) {
  final length = math.max(from.length, to.length);
  return List<Color>.generate(
    length,
    (i) => Color.lerp(from[i % from.length], to[i % to.length], t)!,
  );
}

bool _sameColours(List<Color> a, List<Color> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
