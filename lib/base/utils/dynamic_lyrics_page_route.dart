import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/utils/media_query.dart';
import 'package:sylvakru/base/design/app_tokens.dart';

class DynamicLyricsPageRoute<T> extends PageRouteBuilder<T> {
  DynamicLyricsPageRoute({required super.pageBuilder});

  @override
  Duration get transitionDuration => AppDuration.page;

  @override
  Duration get reverseTransitionDuration => AppDuration.page;

  void revealRoutesBelow() {
    if (overlayEntries.isNotEmpty) {
      overlayEntries.first.opaque = false;
    }
  }

  void concealRoutesBelow() {
    if (overlayEntries.isNotEmpty &&
        animation != null &&
        animation!.isCompleted) {
      overlayEntries.first.opaque = true;
    }
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppCurve.standard,
      reverseCurve: AppCurve.standard,
    );
    if (isTooNarrow(context)) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    }
    return FadeTransition(opacity: curved, child: child);
  }
}
