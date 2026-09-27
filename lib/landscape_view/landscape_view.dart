import 'package:sylvakru/base/design/cover_backdrop.dart';
import 'package:sylvakru/base/design/app_tokens.dart';

import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/widgets/cover_art_widget.dart';
import 'package:sylvakru/landscape_view/bottom_control.dart';
import 'package:sylvakru/landscape_view/sidebar.dart';
import 'package:sylvakru/layer/layers_manager.dart';

class LandscapeView extends StatelessWidget {
  const LandscapeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,

      children: [
        ValueListenableBuilder(
          valueListenable: mainPageThemeNotifier,
          builder: (context, value, child) {
            if (value != .vivid) {
              return SizedBox.shrink();
            }
            return ValueListenableBuilder(
              valueListenable: layersManager.backgroundChangeNotifier,
              builder: (context, value, child) {
                return CoverArtWidget(
                  picture: backgroundPicture,
                  color: colorManager.getSpecificBgBaseColor(),
                );
              },
            );
          },
        ),
        ValueListenableBuilder(
          valueListenable: mainPageThemeNotifier,
          builder: (context, value, child) {
            if (value != .vivid) {
              return SizedBox.shrink();
            }
            return ValueListenableBuilder(
              valueListenable: layersManager.backgroundChangeNotifier,
              builder: (context, value, child) {
                return CoverBackdrop(
                  colour: backgroundCoverArtColor,
                  palette: backgroundCoverPalette,
                );
              },
            );
          },
        ),
        Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Sidebar(),

                  Expanded(
                    child: ValueListenableBuilder(
                      valueListenable: panelColor.valueNotifier,
                      builder: (context, value, child) {
                        return Material(color: value, child: child);
                      },
                      child: ValueListenableBuilder(
                        valueListenable: layersManager.switchNotifier,
                        builder: (context, value, child) {
                          return Stack(
                            children: layersManager.rootLayerMap.values.map((
                              layer,
                            ) {
                              final active =
                                  layer == layersManager.topRootLayer;
                              return Visibility(
                                visible: active,
                                maintainState: true,
                                child: _LayerFade(active: active, child: layer),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            BottomControl(),
          ],
        ),
      ],
    );
  }
}

/// Fades a root layer in when it becomes the visible one.
///
/// The layers all live in a Stack so their state survives switching, which
/// rules out an AnimatedSwitcher around them: they hold GlobalKeys, and the
/// outgoing child would build a second copy during its animation. Fading only
/// the incoming layer keeps every page's state intact and still removes the
/// hard cut.
class _LayerFade extends StatefulWidget {
  const _LayerFade({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_LayerFade> createState() => _LayerFadeState();
}

class _LayerFadeState extends State<_LayerFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDuration.calm,
    value: widget.active ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _LayerFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.forward(from: 0);
    } else if (!widget.active) {
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: AppCurve.enter),
      child: widget.child,
    );
  }
}
