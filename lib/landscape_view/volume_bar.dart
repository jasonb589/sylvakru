import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/widgets/full_width_track_shape.dart';

class VolumeBar extends StatefulWidget {
  final Color activeColor;

  const VolumeBar({super.key, required this.activeColor});

  @override
  State<VolumeBar> createState() => _VolumeBarState();
}

class _VolumeBarState extends State<VolumeBar> {
  /// Drawn only while the knob is held, matching the seek bar: at rest both
  /// bars are meant to read as thin lines rather than as knobs on a track.
  bool isDragging = false;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: isDragging ? 4 : 2,
        trackShape: const FullWidthTrackShape(),
        thumbColor: widget.activeColor,
        thumbShape: RoundSliderThumbShape(
          enabledThumbRadius: isDragging ? 6 : 0,
        ),
        overlayShape: SliderComponentShape.noOverlay,
        activeTrackColor: widget.activeColor,
        // Derived from the track colour instead of a fixed black tint, which
        // disappeared on a dark theme. Same rule as the seek bar, so the two
        // sliders on one bar cannot disagree about their unfilled part.
        inactiveTrackColor: widget.activeColor.withValues(alpha: 0.25),
      ),
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            double step = 0.02;

            double newValue;

            if (event.scrollDelta.dy < 0) {
              newValue = volumeNotifier.value + step;
            } else {
              newValue = volumeNotifier.value - step;
            }

            newValue = newValue.clamp(0.0, 1.0);

            volumeNotifier.value = newValue;
            audioHandler.setVolume(newValue);
            audioHandler.savePlayState();
          }
        },
        child: ValueListenableBuilder(
          valueListenable: volumeNotifier,
          builder: (context, value, child) {
            return ExcludeFocus(
              child: Slider(
                value: value,
                min: 0,
                max: 1,
                onChangeStart: (value) {
                  setState(() => isDragging = true);
                },
                onChangeEnd: (value) {
                  setState(() => isDragging = false);
                  audioHandler.savePlayState();
                },
                onChanged: (value) {
                  volumeNotifier.value = value;
                  audioHandler.setVolume(value);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
