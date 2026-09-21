import 'package:material_ui/material_ui.dart';

class ContrastColorTextTheme {
  final Color regular;
  final Color accent;

  ContrastColorTextTheme({required this.regular, required this.accent});
}

class ContrastColorGenerator {
  /// Regular: High-contrast complementary tint for best readability.
  /// Accent: Subtle neighboring hue for a gentle highlight.
  static ContrastColorTextTheme generate(Color backgroundColor) {
    final hsl = HSLColor.fromColor(backgroundColor);
    final double luminance = backgroundColor.computeLuminance();
    final bool isDark = luminance < 0.45;

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

  /// A readable, hue-preserving version of [cover] for a fixed dark backdrop.
  ///
  /// [generate] is tuned for the lyrics page, where the text sits on a mid-tone
  /// blurred cover: its colours are pushed to lightness 0.90/0.95, and the
  /// regular tint is desaturated to 0.10 so it "cuts through" a coloured
  /// background. On the desktop lyrics window, which always draws on its own
  /// translucent black, both render as plain white - the album colour appeared
  /// not to apply at all.
  ///
  /// So the album's own hue is kept and only the lightness is pulled down to a
  /// level that stays legible on black while the tint remains visible. Greys
  /// stay grey rather than picking up an arbitrary hue.
  static Color onDarkBackdrop(Color cover) {
    final hsl = HSLColor.fromColor(cover);
    final saturation = hsl.saturation < 0.12
        ? 0.0
        : hsl.saturation.clamp(0.35, 0.80);
    return HSLColor.fromAHSL(1.0, hsl.hue, saturation, 0.72).toColor();
  }
}
