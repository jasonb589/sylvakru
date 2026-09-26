import 'package:material_ui/material_ui.dart';

/// The InkWell overlay states, decided in one place.
///
/// Every interactive surface either shows the app's hover and focus tint, or it
/// shows its own feedback instead (a scale, a colour change) and turns the
/// overlay off. The four colours behind that choice used to be set per call
/// site, in a different combination each time, so what a surface did on hover
/// depended on where it happened to be.
abstract final class AppOverlay {
  /// An overlay state the app does not tint.
  static const Color off = Colors.transparent;

  /// A theme with the pointer and press overlay states turned off.
  ///
  /// [keepFocus] retains the keyboard focus tint for surfaces a remote or
  /// keyboard user reaches: without it they get no focus indicator at all.
  static ThemeData none(BuildContext context, {bool keepFocus = false}) {
    final theme = Theme.of(context);
    return theme.copyWith(
      hoverColor: off,
      splashColor: off,
      highlightColor: off,
      focusColor: keepFocus ? theme.focusColor : off,
    );
  }
}
