import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/design/cover_backdrop.dart';
import 'package:sylvakru/base/services/picture_service.dart';

/// What the backdrop has to survive: a track change swapping the colour
/// underneath it mid-life, and an artwork that has no file yet.
void main() {
  Widget build(Color colour, {MyPicture? picture}) => MaterialApp(
    home: Stack(
      children: [CoverBackdrop(colour: colour, picture: picture)],
    ),
  );

  testWidgets('crossfades when the cover colour changes', (tester) async {
    await tester.pumpWidget(build(const Color(0xFF102030)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    // A track change part-way through: both colours are on screen at once,
    // which is the state the 0.8s crossfade exists for.
    await tester.pumpWidget(build(const Color(0xFFA03010)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('survives an artwork that has nothing on disk yet', (
    tester,
  ) async {
    // An empty id is the picture that never loads: it is the state every
    // surface starts in before the library reports its artwork.
    final picture = MyPicture('');
    await tester.pumpWidget(build(const Color(0xFF203040), picture: picture));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
