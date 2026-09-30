import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/data/config.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/loader.dart';
import 'package:sylvakru/base/design/window_backplate.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/base/services/keyboard.dart';
import 'package:sylvakru/base/services/system_ui_service.dart';
import 'package:sylvakru/base/services/taskbar_service.dart';
import 'package:sylvakru/base/utils/media_query.dart';
import 'package:sylvakru/base/utils/source_type.dart';
import 'package:sylvakru/base/widgets/connect_client_widget.dart';
import 'package:sylvakru/base/widgets/manage_music_folders.dart';
import 'package:sylvakru/big_picture_view/big_picture_view.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/landscape_view/landscape_view.dart';
import 'package:sylvakru/landscape_view/sidebar.dart';
import 'package:sylvakru/layer/layers_manager.dart';
import 'package:sylvakru/mini_view/mini_view.dart';
import 'package:sylvakru/portrait_view/portrait_view.dart';

class ViewEntry extends StatefulWidget {
  const ViewEntry({super.key});

  @override
  State<StatefulWidget> createState() => _ViewEntryState();
}

class _ViewEntryState extends State<ViewEntry> with WidgetsBindingObserver {
  bool systemCanPop = false;
  Timer? _exitTimer;
  int keyValue = 0;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addObserver(this);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (Platform.isIOS) {
        if (!firstLaunch) {
          await Future.delayed(Duration(milliseconds: 500));
          await NativeMenu.init();
        }
        await NativeMenu.initIcons();
      } else if (Platform.isMacOS) {
        await NativeMenu.initIcons();
      } else if (Platform.isWindows) {
        setupTaskbar();
      }
    });
  }

  @override
  void dispose() {
    if (Platform.isAndroid) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Platform.isAndroid) {
      if (state == .resumed) {
        systemCanPop = false;
        _exitTimer?.cancel();
        applySystemUiMode(forceApply: true);
        // rebuild PopScope to allow it to handle pop
        setState(() {
          keyValue++;
        });
      } else if (isTV && state == .paused) {
        audioHandler.pause();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return view();
    }
    return PopScope(
      canPop: false,
      key: ValueKey(keyValue),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop | isTyping | isTV) {
          return;
        }
        if (portraitKey.currentState?.isDrawerOpen ?? false) {
          portraitKey.currentState?.closeDrawer();
          return;
        }
        if (await layersManager.popDetail(sidebarHighlighLabel.value)) {
          return;
        }

        if (systemCanPop) {
          systemCanPop = false;
          _exitTimer?.cancel();
          SystemNavigator.pop();
        } else {
          systemCanPop = true;
          if (context.mounted) {
            showCenterMessage(AppLocalizations.of(context).tapAgain);
          }
          _exitTimer = Timer(const Duration(seconds: 2), () {
            systemCanPop = false;
          });
        }
      },
      child: view(),
    );
  }

  Widget view() {
    if (firstLaunch) {
      return backplate(firstLaunchView());
    }
    return ValueListenableBuilder(
      valueListenable: viewModeNotifier,
      builder: (context, viewMode, child) {
        if (viewMode == .mini) {
          return MiniView();
        }
        if (viewMode == .bigPicture) {
          applySystemUiMode(
            mode: immersiveWideLayoutNotifier.value
                ? .immersiveSticky
                : .edgeToEdge,
          );

          if (immersiveWideLayoutNotifier.value) {
            return backplate(BigPictureView());
          }
          SystemChrome.setSystemUIOverlayStyle(
            const SystemUiOverlayStyle(
              statusBarIconBrightness: Brightness.light,
            ),
          );
          return backplate(SafeArea(child: BigPictureView()));
        }
        if (isTooNarrow(context)) {
          applySystemUiMode(mode: .manual);
          return backplate(PortraitView());
        }
        // immersiveSticky：上滑临时显示的系统栏是透明浮层、不派发 insets
        // 变化也会自动隐藏，全面屏手势可正常完成；immersive 被唤出后会常驻
        applySystemUiMode(
          mode: immersiveWideLayoutNotifier.value
              ? .immersiveSticky
              : .edgeToEdge,
        );

        if (immersiveWideLayoutNotifier.value) {
          return backplate(LandscapeView());
        }
        SystemChrome.setSystemUIOverlayStyle(
          const SystemUiOverlayStyle(statusBarIconBrightness: Brightness.light),
        );
        return backplate(SafeArea(child: LandscapeView()));
      },
    );
  }

  /// Wraps a full-size surface in the app's own opaque base.
  ///
  /// The window may be composited with alpha (on Windows a transparent window
  /// background colour becomes an accent-transparentgradient), so a surface
  /// that leaves anything translucent would show the desktop behind the
  /// player. The mini view is deliberately left out: it is meant to be
  /// see-through, and it is the reason the window is allowed to be transparent
  /// at all.
  Widget backplate(Widget surface) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        layersManager.backgroundChangeNotifier,
        mainPageThemeNotifier,
      ]),
      builder: (context, _) => WindowBackplate(
        color: colorManager.getWindowBackplateColor(),
        child: surface,
      ),
    );
  }

  Widget firstLaunchView() {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 650;

              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.only(
                      left: 20,
                      right: 20,
                      top: MediaQuery.of(context).padding.top == 0
                          ? 20
                          : MediaQuery.of(context).padding.top,
                      bottom: 20,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        Center(
                          child: Text(
                            l10n.chooseMusicSource,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),

                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    sliver: SliverGrid(
                      delegate: SliverChildListDelegate([
                        _buildSourceCard(
                          thisSourceType: .local,
                          color: iconColor.value,
                        ),
                        _buildSourceCard(
                          thisSourceType: .webdav,
                          color: iconColor.value,
                        ),
                        _buildSourceCard(thisSourceType: .navidrome),
                        _buildSourceCard(thisSourceType: .emby),
                        _buildSourceCard(thisSourceType: .feiniu),
                      ]),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: isCompact ? 2 : 4,
                        mainAxisSpacing: 5,
                        crossAxisSpacing: 5,
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 10)),

                  if (sourceType != .local) ...[
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      sliver: SliverToBoxAdapter(
                        child: Card(
                          child: ConnectClientWidget(
                            key: ValueKey(sourceType),
                            sourceType: sourceType,
                          ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 10)),
                  ],

                  if (isNotStreamSource) ...[
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      sliver: SliverToBoxAdapter(
                        child: Card(
                          child: ManageMusicFolders(key: ValueKey(sourceType)),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 10)),
                  ],

                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    sliver: SliverToBoxAdapter(
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          mouseCursor: SystemMouseCursors.click,
                          onTap: () async {
                            setState(() {
                              firstLaunch = false;
                            });

                            if (Platform.isIOS) {
                              WidgetsBinding.instance.addPostFrameCallback((
                                _,
                              ) async {
                                await NativeMenu.init();
                              });
                            }

                            config.save();
                            await Loader.firstSync();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            child: Center(child: Text(l10n.getStart)),
                          ),
                        ),
                      ),
                    ),
                  ),

                  SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSourceCard({required SourceType thisSourceType, Color? color}) {
    return AspectRatio(
      aspectRatio: 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          onTap: () async {
            sourceType = thisSourceType;
            isStreamSource =
                sourceType == .navidrome ||
                sourceType == .emby ||
                sourceType == .feiniu;
            isNotStreamSource = !isStreamSource;
            library = Library();
            if (isNotStreamSource) {
              await library.initFolders();
            }
            if (mounted) {
              setState(() {});
            }
          },
          child: Stack(
            children: [
              Transform.scale(
                scale: 0.6,
                child: Center(
                  child: Column(
                    children: [
                      Expanded(
                        child: Image(
                          image: getSourceTypeImage(thisSourceType),
                          color: color,
                        ),
                      ),
                      Text(
                        getSourceTypeDisplayName(
                          AppLocalizations.of(context),
                          thisSourceType,
                        ),
                        style: .new(fontSize: 22),
                      ),
                    ],
                  ),
                ),
              ),

              if (sourceType == thisSourceType)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(Icons.check_circle, color: Colors.black),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
