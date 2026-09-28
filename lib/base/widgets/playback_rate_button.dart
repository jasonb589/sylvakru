import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/services/interaction.dart';

/// The playback speed picker: a readout of the current speed that opens the
/// client's own context menu of the speeds the player can be asked for.
///
/// Two things make it sit with the lyric page's other display controls rather
/// than beside them:
///
/// * it is an [IconButton] carrying text, so the tap target, spacing, hover and
///   press feedback and the glyph size all match the `A+` / `A-` next to it —
///   a bare `Text` with its own padding read as a different kind of control;
/// * the menu is [showContextMenu], the same surface the song and playlist
///   menus use (native on macOS and iOS, the client's own glass popup
///   elsewhere). A Material popup menu painted an opaque slab over the blurred
///   artwork, which is the mismatch this replaced.
class PlaybackRateButton extends StatelessWidget {
  /// Colour for the readout, matching whatever the surrounding controls use.
  final Color color;

  /// Glyph size for the readout, matching the neighbouring icons. Material
  /// icons carry padding inside their box, so the digits are drawn a little
  /// smaller than the box to come out the same size as the glyphs beside them.
  final double iconSize;

  const PlaybackRateButton({
    super.key,
    required this.color,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: playbackRateNotifier,
      builder: (context, rate, child) {
        return IconButton(
          color: color,
          onPressed: () => _showMenu(context),
          icon: Text(
            _label(rate),
            style: TextStyle(
              color: color,
              fontSize: iconSize * 0.8,
              // A speed other than 1.0 is a state worth noticing at a glance.
              fontWeight: rate == 1.0 ? .normal : .bold,
            ),
          ),
        );
      },
    );
  }

  void _showMenu(BuildContext context) {
    // Anchor the menu to this button. Reading the box rather than a tap
    // position keeps keyboard activation working the same way.
    final box = context.findRenderObject() as RenderBox?;
    final position = box != null && box.hasSize
        ? box.localToGlobal(box.size.bottomLeft(Offset.zero))
        : Offset.zero;

    showContextMenu(context, [
      for (final option in playbackRateOptions)
        MenuItem(
          text: _label(option),
          callback: () => audioHandler.setPlaybackRate(option),
        ),
    ], position);
  }

  /// `1.0×`, `1.25×`: whole speeds keep one decimal, the fractions are left as
  /// they are. Trailing zeroes in a readout this small are just noise.
  static String _label(double rate) {
    final text = rate == rate.roundToDouble()
        ? rate.toStringAsFixed(1)
        : rate.toString();
    return '$text×';
  }
}
