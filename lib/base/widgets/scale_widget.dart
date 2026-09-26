import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/design/app_tokens.dart';

class ScaleWidget extends StatefulWidget {
  final Widget child;
  final void Function()? onTap;
  final void Function()? onFocus;

  final bool needFocusColor;
  final bool autoFocus;
  const ScaleWidget({
    super.key,
    required this.child,
    this.onTap,
    this.onFocus,
    this.needFocusColor = false,
    this.autoFocus = false,
  });

  @override
  State<StatefulWidget> createState() => _ScaleWidgetState();
}

class _ScaleWidgetState extends State<ScaleWidget> {
  final focusNotifier = ValueNotifier(false);
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: focusNotifier,
      builder: (context, value, child) {
        // Animated rather than an instant jump: in big picture mode this is the
        // primary focus affordance, and a keyboard or remote user has no
        // cursor telling them where focus just moved to.
        return AnimatedScale(
          scale: value ? 1.1 : 1,
          duration: AppDuration.quick,
          curve: AppCurve.standard,
          child: InkWell(
            autofocus: widget.autoFocus,
            mouseCursor: SystemMouseCursors.click,
            hoverColor: Colors.transparent,
            focusColor: widget.needFocusColor ? null : Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            onFocusChange: (value) {
              focusNotifier.value = !focusNotifier.value;
              if (value) {
                widget.onFocus?.call();
              }
            },
            onTap: widget.onTap ?? () {},

            child: widget.child,
          ),
        );
      },
    );
  }
}
