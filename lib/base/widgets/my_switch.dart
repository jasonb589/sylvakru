import 'package:material_ui/material_ui.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/base/widgets/scale_widget.dart';

class MySwitch extends StatelessWidget {
  final String? trueText;
  final String? falseText;
  final ValueNotifier<bool> valueNotifier;
  final void Function()? onToggleCallBack;
  final bool inLyricsPage;

  const MySwitch({
    super.key,
    this.trueText,
    this.falseText,
    required this.valueNotifier,
    this.onToggleCallBack,
    this.inLyricsPage = false,
  });

  @override
  Widget build(BuildContext context) {
    if (trueText == null) {
      return switcher();
    }
    return Row(
      mainAxisSize: .min,
      children: [
        ValueListenableBuilder(
          valueListenable: valueNotifier,
          builder: (context, value, child) {
            return Text(
              value ? trueText! : falseText!,
              style: TextStyle(
                color: inLyricsPage ? lyricsPageForegroundColor.value : null,
              ),
            );
          },
        ),
        SizedBox(width: 5),
        switcher(),
      ],
    );
  }

  Widget switcher() {
    return ValueListenableBuilder(
      valueListenable: valueNotifier,
      builder: (context, value, child) {
        return ValueListenableBuilder(
          valueListenable: switchColor.valueNotifier,
          builder: (_, _, _) {
            return ScaleWidget(
              onTap: () {
                valueNotifier.value = !valueNotifier.value;
                onToggleCallBack?.call();
              },
              child: FlutterSwitch(
                width: 45,
                height: 20,
                toggleSize: 15,
                activeColor: switchColor.value,
                // Derived from the switch's own colour rather than a fixed
                // grey, which read as a different material on a dark theme.
                inactiveColor: switchColor.value.withValues(alpha: 0.25),
                value: value,
                onToggle: (value) {
                  tryVibrate();
                  valueNotifier.value = !valueNotifier.value;
                  onToggleCallBack?.call();
                },
              ),
            );
          },
        );
      },
    );
  }
}
