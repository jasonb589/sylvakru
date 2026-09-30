import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/widgets/seekbar.dart';

/// Where a point on the bar lands in the song.
///
/// The pointer previewing a time and a finger dragging the thumb both go through
/// [SeekBarState.previewValue], so hovering and dragging cannot disagree about
/// where a point on the bar is - which is the whole reason the mapping is a
/// plain function of the numbers.
void main() {
  const padding = 45.0;
  const width = 445.0; // 355 px of usable track
  const durationMs = 200000.0; // 3:20

  double valueAt(double dx) => SeekBarState.previewValue(
    dx: dx,
    width: width,
    durationMs: durationMs,
    padding: padding,
  );

  test('the middle of the track is the middle of the song', () {
    expect(
      valueAt(padding + (width - padding * 2) / 2),
      closeTo(durationMs / 2, 1),
    );
    expect(valueAt(padding + (width - padding * 2) / 4), closeTo(50000, 1));
    expect(valueAt(padding + (width - padding * 2) * 0.75), closeTo(150000, 1));
  });

  test('the ends are the ends, and the padding is not part of the song', () {
    expect(valueAt(padding), 0);
    expect(valueAt(width - padding), durationMs);
    // A pointer in the padding, or past either end, clamps instead of running
    // off the song.
    expect(valueAt(0), 0);
    expect(valueAt(padding - 20), 0);
    expect(valueAt(width + 50), durationMs);
    expect(valueAt(width - padding + 20), durationMs);
  });

  test('a bar with nothing to point at answers zero', () {
    expect(
      valueAt(100),
      isNot(0),
      reason: 'the guard below must not swallow a working bar',
    );
    // Nothing loaded yet.
    expect(
      SeekBarState.previewValue(
        dx: 100,
        width: width,
        durationMs: 0,
        padding: padding,
      ),
      0,
    );
    // The padding eats the whole bar.
    expect(
      SeekBarState.previewValue(
        dx: 100,
        width: 60,
        durationMs: durationMs,
        padding: padding,
      ),
      0,
    );
    expect(
      SeekBarState.previewValue(
        dx: 100,
        width: 90,
        durationMs: durationMs,
        padding: padding,
      ),
      0,
      reason: 'exactly zero usable length is still nothing to point at',
    );
  });
}
