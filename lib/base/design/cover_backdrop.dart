import 'dart:ui';

import 'package:material_ui/material_ui.dart';
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
/// The caller listens to whatever signals a colour change and builds this with
/// the new value; the [AnimatedContainer] inside then eases from the previous
/// colour.
class CoverBackdrop extends StatelessWidget {
  const CoverBackdrop({super.key, required this.colour});

  /// The colour derived from the current cover art.
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final sigma = AppBlur.backdropSigma(
      size.width < size.height ? size.width : size.height,
    );

    // ClipRect keeps the blur inside the surface; the RepaintBoundary gives the
    // always-visible blur its own layer so a resize does not force the tree
    // behind it to repaint in the same frame.
    return ClipRect(
      child: RepaintBoundary(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: AnimatedContainer(
            duration: AppDuration.backdrop,
            curve: AppCurve.colour,
            color: colour.withValues(alpha: AppBlur.backdropAlpha / 255),
          ),
        ),
      ),
    );
  }
}
