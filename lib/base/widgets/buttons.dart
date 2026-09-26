import 'dart:math';
import 'package:rive_animated_icon/rive_animated_icon.dart';
import 'package:sylvakru/base/data/library.dart';

import 'package:sylvakru/base/design/app_tokens.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/asset_images.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/base/widgets/play_queue_sheet.dart';
import 'package:sylvakru/base/data/playlist.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/landscape_view/pages/play_queue_page.dart';
import 'package:smooth_corner/smooth_corner.dart';

Widget playModeButton(double? size, {Color? iconColor}) {
  return ValueListenableBuilder(
    valueListenable: playModeNotifier,
    builder: (context, playMode, _) {
      final l10n = AppLocalizations.of(context);

      return IconButton(
        color: iconColor,
        icon: ImageIcon(
          playMode == 0
              ? loopImage
              : playMode == 1
              ? shuffleImage
              : repeatImage,
          size: size,
        ),
        onPressed: () {
          if (playQueue.isEmpty) {
            return;
          }

          showAnimationDialog(
            context: context,

            child: SizedBox(
              width: 300,
              height: isMobile ? 190 : 170,
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: ValueListenableBuilder(
                  valueListenable: currentSongNotifier,
                  builder: (context, value, child) {
                    final iconColor = colorManager.getSpecificIconColor();
                    final textColor = colorManager.getSpecificTextColor();
                    return Column(
                      children: [
                        ListTile(
                          leading: ImageIcon(loopImage, color: iconColor),
                          title: Text(
                            l10n.loop,
                            style: TextStyle(color: textColor),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            audioHandler.changePlayMode(0);
                          },
                          trailing: playModeNotifier.value == 0
                              ? Icon(Icons.check, color: iconColor)
                              : null,
                        ),
                        ListTile(
                          leading: ImageIcon(shuffleImage, color: iconColor),

                          title: Text(
                            l10n.shuffle,
                            style: TextStyle(color: textColor),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            audioHandler.changePlayMode(1);
                          },
                          trailing: playModeNotifier.value == 1
                              ? Icon(Icons.check, color: iconColor)
                              : null,
                        ),
                        ListTile(
                          leading: ImageIcon(repeatImage, color: iconColor),

                          title: Text(
                            l10n.repeat,
                            style: TextStyle(color: textColor),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            audioHandler.changePlayMode(2);
                          },
                          trailing: playModeNotifier.value == 2
                              ? Icon(Icons.check, color: iconColor)
                              : null,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Widget rewindButton(double size, {Color? iconColor}) {
  return IconButton(
    color: iconColor,
    icon: ImageIcon(rewindImage, size: size),
    onPressed: () {
      if (playQueue.isEmpty) {
        return;
      }
      if (audioHandler.getPosition() > Duration(seconds: 15)) {
        audioHandler.seek(audioHandler.getPosition() - Duration(seconds: 15));
      } else {
        audioHandler.seek(Duration.zero);
      }
    },
  );
}

Widget skip2PreviousButton(double size, {Color? iconColor}) {
  return IconButton(
    color: iconColor,
    icon: ImageIcon(previousButtonImage, size: size),
    onPressed: () {
      audioHandler.skipToPrevious();
    },
  );
}

Widget playOrPauseButton(double size, {Color? iconColor}) {
  return IconButton(
    autofocus: viewModeNotifier.value == .bigPicture,
    color: iconColor,
    icon: ValueListenableBuilder(
      valueListenable: isPlayingNotifier,
      builder: (_, isPlaying, _) {
        // The most used control in the app; a hard swap between two glyphs
        // reads as a flicker, so the two states cross fade and scale.
        return AnimatedSwitcher(
          duration: AppDuration.quick,
          switchInCurve: AppCurve.enter,
          switchOutCurve: AppCurve.exit,
          transitionBuilder: (child, animation) {
            return ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            key: ValueKey(isPlaying),
            size: size,
          ),
        );
      },
    ),
    onPressed: () {
      if (playQueue.isEmpty) {
        return;
      }
      audioHandler.togglePlay();
    },
  );
}

Widget forwardButton(double size, {Color? iconColor}) {
  return IconButton(
    color: iconColor,
    icon: ImageIcon(forwardImage, size: size),
    onPressed: () {
      if (playQueue.isEmpty) {
        return;
      }
      if (audioHandler.getPosition() + Duration(seconds: 15) <
          currentSongNotifier.value!.duration!) {
        audioHandler.seek(audioHandler.getPosition() + Duration(seconds: 15));
      } else {
        audioHandler.seek(currentSongNotifier.value!.duration!);
      }
    },
  );
}

Widget skip2NextButton(double size, {Color? iconColor}) {
  return IconButton(
    color: iconColor,
    icon: ImageIcon(nextButtonImage, size: size),
    onPressed: () {
      audioHandler.skipToNext();
    },
  );
}

Widget showPlayQueueButton(double size, {Color? iconColor}) {
  return Builder(
    builder: (context) {
      return IconButton(
        color: iconColor,
        icon: ImageIcon(playQueueImage, size: size),
        onPressed: () {
          if (playQueue.isEmpty) {
            return;
          }
          if (!isMobile || isTV) {
            Navigator.push(
              context,
              _NoSecondaryAnimationPageRoute(
                opaque: false,
                barrierColor: Colors.black.withAlpha(25),
                barrierDismissible: true,
                pageBuilder: (_, _, _) {
                  return Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 75, bottom: 100),
                      child: ValueListenableBuilder(
                        valueListenable: currentSongNotifier,
                        builder: (context, value, child) {
                          return Material(
                            elevation: 1,
                            color: Colors.transparent,
                            shape: SmoothRectangleBorder(
                              smoothness: 1,
                              borderRadius: BorderRadius.horizontal(
                                left: Radius.circular(10),
                              ),
                            ),
                            clipBehavior: Clip.antiAliasWithSaveLayer,
                            child: AnimatedContainer(
                              duration: Duration(milliseconds: 250),
                              color: Color.alphaBlend(
                                colorManager.getSpecificBgColor(),
                                colorManager.getSpecificBgBaseColor(),
                              ),
                              width: max(
                                350,
                                MediaQuery.widthOf(context) * 0.2,
                              ),
                              child: PlayQueuePage(),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
                transitionsBuilder: (_, animation, _, child) {
                  return SlideTransition(
                    position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                        .animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                    child: child,
                  );
                },
              ),
            );
            return;
          }
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (context) {
              return PlayQueueSheet();
            },
          );
        },
      );
    },
  );
}

/// Star toggle for the song that is playing right now.
///
/// Shared by the bottom bars and the lyrics pages so the affordance is the same
/// everywhere. Renders nothing when the queue is empty.
Widget favoriteButton(double size, {Color? color}) {
  return Builder(
    builder: (context) {
      return ValueListenableBuilder(
        valueListenable: currentSongNotifier,
        builder: (_, currentSong, _) {
          if (currentSong == null) {
            return const SizedBox.shrink();
          }
          return ValueListenableBuilder(
            valueListenable: currentSong.isFavoriteNotifier,
            builder: (_, isFavorite, _) {
              return IconButton(
                tooltip: AppLocalizations.of(context).favorites,
                onPressed: () {
                  tryVibrate();
                  toggleFavoriteState(currentSong);
                },
                icon: Icon(
                  isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: isFavorite ? Colors.red : null,
                  size: size,
                ),
              );
            },
          );
        },
      );
    },
  );
}

/// Download the current song for offline playback, or remove its copy.
///
/// The states are kept distinct on purpose: a finished copy offers to remove
/// itself, an in-flight one animates so the button does not look idle, and the
/// rest offer to download. A local library has nothing to download, so the
/// button is not shown there at all.
Widget downloadButton(double size) {
  if (sourceType == .local) {
    return const SizedBox.shrink();
  }

  return ValueListenableBuilder(
    valueListenable: currentSongNotifier,
    builder: (context, currentSong, child) {
      if (currentSong == null) {
        return const SizedBox.shrink();
      }

      return ListenableBuilder(
        listenable: Listenable.merge([
          currentSong.updateNotifier,
          downloadingSongIdsNotifier,
          isPlayingNotifier,
        ]),
        builder: (context, child) {
          final l10n = AppLocalizations.of(context);

          if (downloadingSongIdsNotifier.value.contains(currentSong.id)) {
            return Tooltip(
              message: l10n.downloading,
              child: RiveAnimatedIcon(
                key: const ValueKey('downloading'),
                riveIcon: .cloud,
                width: size,
                height: size,
                loopAnimation: true,
                color: IconTheme.of(context).color ?? iconColor.value,
              ),
            );
          }

          final exists = currentSong.cacheExist;

          return IconButton(
            tooltip: exists ? l10n.removeDownload : l10n.downloadForOffline,
            onPressed: () async {
              if (exists) {
                final removed = await library.removeOfflineCopy(
                  currentSong,
                  currentlyPlaying:
                      currentSongNotifier.value?.id == currentSong.id &&
                      isPlayingNotifier.value,
                  currentlyQueued: playQueue.any(
                    (item) => item.id == currentSong.id,
                  ),
                );
                if (!removed && context.mounted) {
                  showCenterMessage(l10n.downloadInUse);
                }
                return;
              }

              final downloaded = await library.downloadForOffline(
                currentSong,
                keepSongIds: {...playQueue.map((item) => item.id)},
              );
              if (!downloaded && context.mounted) {
                showCenterMessage(l10n.downloadFailed);
              }
            },
            icon: Icon(
              exists ? Icons.download_done_rounded : Icons.download_rounded,
              size: size,
            ),
          );
        },
      );
    },
  );
}

class _NoSecondaryAnimationPageRoute<T> extends PageRouteBuilder {
  _NoSecondaryAnimationPageRoute({
    required super.pageBuilder,
    required super.transitionsBuilder,
    super.opaque,
    super.barrierColor,
    super.barrierDismissible,
  });

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      (context, animation, secondaryAnimation, allowSnapshotting, child) {
        return child;
      };
}
