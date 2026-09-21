import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/utils/contrast_color_generator.dart';

/// Relative luminance, used to assert that text stays readable.
double luminanceOf(Color color) => color.computeLuminance();

void main() {
  group('ContrastColorGenerator', () {
    test('keeps text light when the backdrop is pinned dark', () {
      // a bright cover: inferring from the colour itself would pick near-black
      // text, which is unreadable on the desktop lyrics window
      final onDark = ContrastColorGenerator.generate(
        const Color(0xFFF5E9A0),
        darkBackground: true,
      );

      expect(luminanceOf(onDark.regular), greaterThan(0.5));
      expect(luminanceOf(onDark.accent), greaterThan(0.5));
    });

    test('infers the backdrop from the colour when not pinned', () {
      final onLight = ContrastColorGenerator.generate(const Color(0xFFF5E9A0));
      final onDarkColor = ContrastColorGenerator.generate(
        const Color(0xFF101010),
      );

      expect(luminanceOf(onLight.regular), lessThan(0.5));
      expect(luminanceOf(onDarkColor.regular), greaterThan(0.5));
    });

    test('pinning the backdrop overrides the colour luminance', () {
      // same bright colour, opposite results
      final inferred = ContrastColorGenerator.generate(
        const Color(0xFFF5E9A0),
      );
      final pinned = ContrastColorGenerator.generate(
        const Color(0xFFF5E9A0),
        darkBackground: true,
      );

      expect(luminanceOf(inferred.regular), lessThan(luminanceOf(pinned.regular)));
    });

    test('accent differs from regular', () {
      final theme = ContrastColorGenerator.generate(
        const Color(0xFF3355AA),
        darkBackground: true,
      );

      expect(theme.accent, isNot(theme.regular));
    });
  });
}
