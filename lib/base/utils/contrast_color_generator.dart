import 'package:material_ui/material_ui.dart';

class ContrastColorTextTheme {
  final Color regular;
  final Color accent;

  ContrastColorTextTheme({required this.regular, required this.accent});
}

class ContrastColorGenerator {
  /// Regular: High-contrast complementary tint for best readability.
  /// Accent: Subtle neighboring hue for a gentle highlight.
  ///
  /// [darkBackground] describes the surface the text will sit on. By default it
  /// is inferred from [backgroundColor]'s luminance, which is right when the
  /// colour *is* the background (the lyrics page tints itself with the cover
  /// art). Pass it explicitly when the text sits on a fixed backdrop: the
  /// desktop lyrics always draw on translucent black, so a light cover would
  /// otherwise produce near-black text on a black window.
  static ContrastColorTextTheme generate(
    Color backgroundColor, {
    bool? darkBackground,
  }) {
    final hsl = HSLColor.fromColor(backgroundColor);
    final double luminance = backgroundColor.computeLuminance();
    final bool isDark = darkBackground ?? luminance < 0.45;

    // --- 1. Regular Text (Optimized for Readability) ---
    // We use the 180° hue shift but keep saturation very low.
    // This "cuts" through the background color so it doesn't look blurry.
    Color regularColor = HSLColor.fromAHSL(
      1.0,
      (hsl.hue + 180) % 360,
      0.10, // Very low saturation to keep it clean
      isDark ? 0.90 : 0.15, // High contrast for clarity
    ).toColor();

    // --- 2. Subtle Accent Color ---
    // Logic: Instead of rotating 180°, we only rotate 15-30°.
    // We increase saturation slightly to make it "pop" without clashing.
    Color accentColor = HSLColor.fromAHSL(
      1.0,
      (hsl.hue + 20) % 360, // Slight shift to a neighboring hue
      (hsl.saturation + 0.3).clamp(0.4, 0.6), // Moderate saturation boost
      isDark
          ? 0.95
          : 0.15, // Make it slightly closer to white/black than the regular text
    ).toColor();

    return ContrastColorTextTheme(regular: regularColor, accent: accentColor);
  }
}
