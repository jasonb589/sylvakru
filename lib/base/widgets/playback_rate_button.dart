import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/services/color_manager.dart';

/// The playback speed picker: a small readout of the current speed that opens a
/// menu of the speeds the player can be asked for.
///
/// It sits with the lyric page's other display controls rather than in the
/// transport row, so the row of play controls keeps its shape, and a speed of
/// 1.0 costs nothing but one line of text. The readout is its own label: `1.0×`
/// needs no translating.
class PlaybackRateButton extends StatelessWidget {
  /// Colour for the readout, matching whatever the surrounding controls use.
  final Color color;

  const PlaybackRateButton({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: playbackRateNotifier,
      builder: (context, rate, child) {
        return PopupMenuButton<double>(
          onSelected: (value) => audioHandler.setPlaybackRate(value),
          color: menuColor.value,
          itemBuilder: (context) => [
            for (final option in playbackRateOptions)
              PopupMenuItem<double>(
                value: option,
                child: Text(
                  _label(option),
                  style: TextStyle(
                    fontWeight: option == rate ? .bold : .normal,
                    color: color,
                  ),
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              _label(rate),
              style: TextStyle(
                color: color,
                fontSize: 14,
                // A speed other than 1.0 is a state worth noticing at a glance.
                fontWeight: rate == 1.0 ? .normal : .bold,
              ),
            ),
          ),
        );
      },
    );
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
