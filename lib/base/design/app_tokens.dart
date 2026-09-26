/// Design tokens for the presentation layer.
///
/// Before this existed the same visual decision was made independently in
/// several files: a cover thumbnail used one of nine different corner radii
/// depending on where it appeared, and the full-screen backdrop was blurred
/// four different ways with three different durations - one of which did not
/// animate at all. Screens therefore drifted apart one edit at a time.
///
/// Values are grouped by role rather than by size. A reviewer should be able to
/// ask "is this a row?" and get the right number without comparing pixels, and
/// a change here should move every surface that shares the role.
library;

import 'package:material_ui/material_ui.dart';

/// Corner radii, by the role a surface plays.
abstract final class AppRadius {
  /// List rows, sidebar entries, the title bar.
  static const double row = 10;

  /// Larger cards: big-picture rows, feature tiles.
  static const double card = 15;

  /// Dialogs, sheets and their contents.
  static const double sheet = 20;

  /// Fully rounded glass pills and chips.
  static const double pill = 25;

  /// Cover art at thumbnail size inside a dense list.
  static const double coverTiny = 4;

  /// Cover art in a normal list row.
  static const double coverRow = 5;

  /// Cover art on a card or panel header.
  static const double coverCard = 10;
}

/// Durations, by how much attention the change deserves.
abstract final class AppDuration {
  /// Hover, press, focus. Must feel instant.
  static const Duration quick = Duration(milliseconds: 150);

  /// Small state changes: a toggle, a check mark.
  static const Duration normal = Duration(milliseconds: 250);

  /// Page and panel transitions.
  static const Duration calm = Duration(milliseconds: 300);

  /// The cover backdrop. Slow enough that a track change reads as the whole
  /// surface shifting colour rather than a flicker.
  static const Duration backdrop = Duration(milliseconds: 500);
}

/// Curves, paired with the intent of the animation.
abstract final class AppCurve {
  /// Default for anything that moves between two resting states.
  static const Curve standard = Curves.easeInOutCubic;

  /// Coming into view.
  static const Curve enter = Curves.easeOutCubic;

  /// Leaving view.
  static const Curve exit = Curves.easeInCubic;

  /// Attention without motion, e.g. a colour change.
  static const Curve colour = Curves.easeInOut;
}

/// Blur radii.
abstract final class AppBlur {
  /// Sigma for the full-screen cover backdrop.
  ///
  /// Proportional to the surface so a maximised window keeps the same apparent
  /// softness as a small one; a fixed radius made the large layout look sharp.
  static double backdropSigma(double side) => side * 0.03;

  /// Alpha applied to the cover colour on top of the backdrop blur.
  static const int backdropAlpha = 180;
}

/// Elevation, expressed as the shadow a surface casts.
abstract final class AppShadow {
  /// A resting card.
  static List<BoxShadow> card(Color colour) => [
    BoxShadow(
      color: colour.withValues(alpha: 0.18),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];

  /// A surface that is lifted, e.g. a row being dragged.
  static List<BoxShadow> lifted(Color colour) => [
    BoxShadow(
      color: colour.withValues(alpha: 0.28),
      blurRadius: 28,
      offset: const Offset(0, 12),
    ),
  ];
}

/// Material elevation, for surfaces that should read as lifted.
///
/// This is Material's own dp scale rather than a pixel radius, so the numbers
/// sit at the low end: a thumbnail in a control bar only needs to separate
/// itself from the bar, while a full-size cover can carry a real shadow.
abstract final class AppElevation {
  /// Flush with its surface.
  static const double flat = 0;

  /// A cover sitting in a control bar or list tile.
  static const double control = 3;

  /// The large cover on a lyrics page or player hero area.
  static const double hero = 15;
}
