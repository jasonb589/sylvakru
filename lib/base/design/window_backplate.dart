import 'package:material_ui/material_ui.dart';

/// The opaque base a full-size surface sits on.
///
/// The window is not guaranteed to be opaque. On Windows, a transparent window
/// background colour makes the window manager ask DWM for an
/// accent-transparentgradient, and from then on every translucent pixel in the
/// scene composites against the desktop instead of a solid surface. One
/// cross-fade left mid-flight - the cover backdrop, whose layer is the bottom
/// of the client - was therefore enough for the window behind the player to
/// show through.
///
/// Painting this base underneath every full-size surface (see `ViewEntry`)
/// removes that dependency: whatever the window does, the client has an opaque
/// bottom of its own, so nothing behind the player can be seen through it.
class WindowBackplate extends StatelessWidget {
  const WindowBackplate({super.key, required this.color, required this.child});

  /// An opaque colour, see `ColorManager.getWindowBackplateColor`.
  final Color color;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: color, child: child);
  }
}
