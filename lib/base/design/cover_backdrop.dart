import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/design/app_tokens.dart';
import 'package:sylvakru/base/services/picture_service.dart';
import 'package:sylvakru/base/widgets/cover_art_widget.dart';

/// The blurred, cover-derived backdrop behind a full-screen surface.
///
/// The recipe is measured rather than invented. The web player's own rule for
/// this surface is
///
///   `.song-header-page__artwork-radiosity { filter: blur(20px) saturate(2);
///    opacity: .4; transform: scale(.88) }`
///
/// - a copy of the artwork, blurred and pushed past its recorded saturation,
/// laid over the surface colour. Blurring the artwork alone leaves the surface
/// grey and flat, which is what this looked like before: the saturation is what
/// keeps the cover's own hues in the backdrop instead of averaging them away.
///
/// The web player has no idle background motion either - none of its 41
/// keyframes moves a backdrop - so neither has this. A track change is a
/// crossfade, at the player's own 0.8s `cubic-bezier(.04,.04,.12,.96)`.
class CoverBackdrop extends StatelessWidget {
  const CoverBackdrop({super.key, required this.colour, this.picture});

  /// The colour derived from the current cover art: the tint under the bloom,
  /// and the colour the text on this surface was chosen for.
  final Color colour;

  /// The artwork the bloom is made from. Without it the surface keeps the
  /// tint-over-blur look that predates the bloom.
  final MyPicture? picture;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final side = size.width < size.height ? size.width : size.height;

    // ClipRect keeps the blur inside the surface; the RepaintBoundary gives the
    // always-visible blur its own layer so a resize cannot repaint the tree
    // behind it in the same frame as the blur recompute.
    return ClipRect(
      child: RepaintBoundary(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: AppBlur.backdropSigma(side),
            sigmaY: AppBlur.backdropSigma(side),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedContainer(
                duration: AppDuration.backdrop,
                curve: AppCurve.crossfade,
                color: colour.withValues(alpha: AppBlur.backdropAlpha / 255),
              ),

              if (picture != null)
                Opacity(
                  opacity: AppBlur.bloomAlpha,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: AppBlur.bloomSigma(side),
                      sigmaY: AppBlur.bloomSigma(side),
                    ),
                    child: ColorFiltered(
                      colorFilter: _saturation(AppBlur.bloomSaturation),
                      child: Transform.scale(
                        scale: AppBlur.bloomScale,
                        child: CoverArtWidget(picture: picture, color: colour),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The equivalent of CSS's `saturate()`, as a luminance-preserving matrix.
///
/// `1` leaves the colours alone, `0` collapses them to grey, and values above
/// `1` push them apart - the web player asks for `2` on this layer.
ColorFilter _saturation(double amount) {
  // Rec. 709 weights, the same ones CSS filters use.
  const redWeight = 0.2126;
  const greenWeight = 0.7152;
  const blueWeight = 0.0722;

  final red = (1 - amount) * redWeight;
  final green = (1 - amount) * greenWeight;
  final blue = (1 - amount) * blueWeight;

  return ColorFilter.matrix(<double>[
    red + amount, green, blue, 0, 0, //
    red, green + amount, blue, 0, 0, //
    red, green, blue + amount, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);
}
