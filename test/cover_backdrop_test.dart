import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/design/cover_backdrop.dart';

/// The backdrop is the one widget whose whole job is to repaint every frame, so
/// the things worth pinning down are that it keeps painting through the three
/// things that change underneath it - the drift running, a track change
/// swapping the palette mid-drift, and playback stopping.
void main() {
  const first = [Color(0xFF102030), Color(0xFF405060), Color(0xFF708090)];
  const second = [Color(0xFF3A1020), Color(0xFF60504A), Color(0xFF8A70A0)];

  Widget build(List<Color> palette) {
    return MaterialApp(
      home: Stack(
        children: [CoverBackdrop(colour: palette.first, palette: palette)],
      ),
    );
  }

  testWidgets('paints through drift, palette changes and playback state', (
    tester,
  ) async {
    await tester.pumpWidget(build(first));

    // Two thirds of a lap: the colours are somewhere in the middle of their
    // paths, which is the only state a listener ever sees.
    await tester.pump(const Duration(seconds: 24));
    expect(tester.takeException(), isNull);

    // A track change while the drift is running: the two palettes blend.
    await tester.pumpWidget(build(second));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    // Playback starts and stops: the breath is added and then settles.
    isPlayingNotifier.value = true;
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    isPlayingNotifier.value = false;
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);

    // Leaving the surface disposes all three controllers.
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('falls back to the single tint without a palette', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Stack(children: [CoverBackdrop(colour: Color(0xFF203040))]),
      ),
    );
    await tester.pump(const Duration(seconds: 12));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
