import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/design/app_tokens.dart';

/// Swaps a placeholder for the content that replaces it, over one short fade -
/// and keeps the content built the whole time.
///
/// The placeholder is drawn *over* [child] and fades away. That is what makes
/// this work for a scroll view as well as for a box: the real list is already
/// laid out underneath while the skeleton goes, so nothing jumps when the wait
/// ends and the list keeps its scroll position. A plain cross-fade cannot do
/// that: it needs both children to be the same kind of widget, and a
/// `CustomScrollView` is not a skeleton.
///
/// Use [ContentFade] when there is nothing to keep underneath - a cover whose
/// file is still being fetched has no content to show early.
class ContentSwap extends StatelessWidget {
  /// Whether the content is still on its way. When it turns false the
  /// placeholder fades out and is then dropped from the tree.
  final bool loading;

  /// What to show while it is on its way: a skeleton, usually.
  final Widget placeholder;

  /// The content itself, built either way.
  final Widget child;

  const ContentSwap({
    super.key,
    required this.loading,
    required this.placeholder,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      // The child sees the same constraints it would have without the
      // placeholder above it, so a panel keeps its size and its scroll.
      fit: StackFit.passthrough,
      children: [
        child,
        ContentFade(
          loading: loading,
          placeholder: placeholder,
          // Nothing to show once the placeholder is gone: it fades out into an
          // empty box, not into a second copy of the content.
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Cross-fades [child] in and [placeholder] out when [loading] turns false.
///
/// One step for every swap of this kind - [AppDuration.normal] with the app's
/// enter and exit curves - so a skeleton, a cover and a state change all read
/// as the same client reacting, at the same speed.
class ContentFade extends StatelessWidget {
  final bool loading;
  final Widget placeholder;
  final Widget child;

  const ContentFade({
    super.key,
    required this.loading,
    required this.placeholder,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppDuration.normal,
      switchInCurve: AppCurve.enter,
      switchOutCurve: AppCurve.exit,
      child: loading
          ? KeyedSubtree(key: const ValueKey('placeholder'), child: placeholder)
          : KeyedSubtree(key: const ValueKey('content'), child: child),
    );
  }
}
