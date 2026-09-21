import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/utils/contrast_color_generator.dart';

/// Relative luminance, used to assert that text stays readable on black.
double luminanceOf(Color color) => color.computeLuminance();

void main() {
  group('ContrastColorGenerator.generate', () {
    test('infers the backdrop from the colour', () {
      // a light cover yields dark text, a dark one yields light text
      expect(
        luminanceOf(
          ContrastColorGenerator.generate(const Color(0xFFF5E9A0)).regular,
        ),
        lessThan(0.5),
      );
      expect(
        luminanceOf(
          ContrastColorGenerator.generate(const Color(0xFF101010)).regular,
        ),
        greaterThan(0.5),
      );
    });

    test('regular is deliberately near-white whatever the cover', () {
      // this is what made the desktop lyrics look like the album colour was
      // ignored: regular is desaturated to 0.10 for readability on a coloured
      // background, so every cover produces almost the same off-white
      final a = ContrastColorGenerator.generate(const Color(0xFF8B2E3C)).regular;
      final b = ContrastColorGenerator.generate(const Color(0xFF2E7D32)).regular;

      expect((a.computeLuminance() - b.computeLuminance()).abs(), lessThan(0.1));
    });
  });

  group('ContrastColorGenerator.onDarkBackdrop', () {
    test('keeps the album hue', () {
      final red = HSLColor.fromColor(
        ContrastColorGenerator.onDarkBackdrop(const Color(0xFF8B2E3C)),
      );
      final green = HSLColor.fromColor(
        ContrastColorGenerator.onDarkBackdrop(const Color(0xFF2E7D32)),
      );

      // both sit near the hue of their own cover, so the colours differ
      expect((red.hue - 351).abs() % 360, lessThan(15));
      expect((green.hue - 123).abs() % 360, lessThan(15));
      expect(red.hue, isNot(closeTo(green.hue, 30)));
    });

    test('stays legible on the black backdrop', () {
      for (final cover in const [
        Color(0xFF8B2E3C), // dark red
        Color(0xFF2E7D32), // green
        Color(0xFF1565C0), // blue
        Color(0xFFF5E9A0), // light yellow
        Color(0xFF101010), // near black
        Color(0xFF808080), // grey
      ]) {
        final text = ContrastColorGenerator.onDarkBackdrop(cover);
        expect(
          luminanceOf(text),
          greaterThan(0.35),
          reason: 'text on black must stay readable for $cover',
        );
      }
    });

    test('a grey cover stays grey instead of inventing a hue', () {
      final grey = ContrastColorGenerator.onDarkBackdrop(const Color(0xFF808080));

      expect(HSLColor.fromColor(grey).saturation, 0.0);
    });

    test('boosts a barely-tinted cover enough to be visible', () {
      // saturation 0.21: above the grey cut-off but below the minimum, so the
      // clamp has to lift it
      final tinted = ContrastColorGenerator.onDarkBackdrop(
        const Color(0xFF8A5A5A),
      );

      expect(HSLColor.fromColor(tinted).saturation, greaterThan(0.3));
    });
  });
}
