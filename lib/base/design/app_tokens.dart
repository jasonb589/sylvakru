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

  /// The loading skeleton pulse. Slow and low contrast: it should read as
  /// "content is coming" without competing with the content itself.
  static const Duration pulse = Duration(milliseconds: 1200);
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

/// Text styles, by the role the text plays.
abstract final class AppText {
  /// The title of a dialog, sheet or popup.
  ///
  /// One tier for all of them. They used to range from 16 to 25 bold, so a
  /// "delete" confirmation shouted louder than the page title behind it.
  static const TextStyle sheetTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
  );
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

/// The lyrics pages: how a line takes over from the one before it, and how the
/// list follows the music.
///
/// A song changes line every couple of seconds, so everything here is short.
/// The line switch is the only thing that lands on the beat; the scroll starts
/// before it, so the new line has arrived by the time it is sung.
abstract final class AppLyrics {
  /// The line switch: the old line dims while the new one brightens.
  static const Duration lineSwitch = Duration(milliseconds: 260);

  /// Following the music, by how far the list has to travel.
  ///
  /// A single line takes about half a second on purpose: the old 265 ms step
  /// started fast and stopped hard, which read as the list being yanked rather
  /// than following. A long jump is still not worth flying across.
  static const int scrollBaseMs = 400;
  static const int scrollPerLineMs = 70;
  static const int scrollMinMs = 420;
  static const int scrollMaxMs = 640;

  /// Beyond this many lines a jump lands in place instead of travelling, and
  /// the list fades in where it arrived.
  static const int jumpLines = 4;

  /// Coming back to the current line after the listener scrolled away, and the
  /// fade used when the list lands somewhere far away.
  static const Duration scrollReturn = Duration(milliseconds: 420);
  static const Duration resetFade = Duration(milliseconds: 160);

  /// How long the listener may look away before the list follows the music
  /// again. Crossing a line brings it back sooner: the song moved on, so the
  /// view should.
  static const Duration idleBeforeReturn = Duration(milliseconds: 2500);

  /// Following is a settle, never a bounce: lyrics that overshoot read as a
  /// mistake rather than as flow.
  static const Curve scrollCurve = Curves.easeInOutCubic;

  /// Opacity by distance from the current line: the line being sung, then the
  /// one after it, then further, and everything beyond at the floor.
  static const List<double> lineOpacities = [1.0, 0.72, 0.48, 0.30];

  /// The current line grows by this much. Small on purpose: a line that wraps
  /// onto a second row would visibly jump at a larger factor.
  static const double currentScale = 1.02;

  /// How much of a word the fill has to have covered before that word is
  /// painted, as a multiple of the font size. A hard cut read as a progress bar
  /// crossing the words.
  static const double fillEdgeEm = 0.6;

  /// How many lines away from the switch still take part in it.
  ///
  /// Everything beyond the third step looks the same - the opacity has already
  /// reached its floor - so animating those lines was work with no pixels to
  /// show for it, on every line of the page at once.
  static const int switchAnimationMaxDistance = 2;

  /// How far the fill may run past the last reported position. The player
  /// reports a few times a second and the ticker smooths between those, but the
  /// wipe must not get ahead of the voice.
  static const int interpolationLeadMs = 40;

  /// A gap between reports larger than this is a seek, not drift: the fill
  /// takes the reported position instead of easing towards it.
  static const int seekSnapMs = 400;

  /// How much the smoothed position may sit behind the player's report before
  /// it is pulled up to it. A frame of lag is invisible and absorbs the jitter
  /// of the reports; more than that is the page reading the song late.
  static const int lagToleranceMs = 16;

  /// A tap on a line: a short acknowledgement, not a bounce.
  static const Duration tapPulse = Duration(milliseconds: 240);

  /// The bar that marks the line under the pointer, instead of a tint over the
  /// whole row.
  static const double hoverBarWidth = 2;
  static const double hoverBarAlpha = 0.55;

  /// How far a line far from the one being sung is blurred, when the listener
  /// asked for it: enough at the edge of the view to read as depth rather than
  /// as damage.
  static const double farBlurSigma = 0.45;
}
