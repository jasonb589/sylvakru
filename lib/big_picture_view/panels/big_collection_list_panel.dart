import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/design/content_swap.dart';
import 'package:sylvakru/base/design/app_tokens.dart';
import 'package:sylvakru/base/design/loading_skeleton.dart';
import 'package:flutter/rendering.dart';
import 'package:sylvakru/base/services/picture_service.dart';
import 'package:sylvakru/base/utils/media_query.dart';
import 'package:sylvakru/base/utils/my_gird_delegate.dart';
import 'package:sylvakru/base/widgets/cover_art_widget.dart';
import 'package:sylvakru/base/widgets/scale_widget.dart';

abstract class BigCollectionListPanel extends StatefulWidget {
  const BigCollectionListPanel({super.key});
}

abstract class BigCollectionListPanelState
    extends State<BigCollectionListPanel> {
  List<MyPicture?> pictureList = [];
  List<String> textList = [];
  List<Function> onTapList = [];

  final textController = TextEditingController();

  final randomizeNotifier = ValueNotifier(false);
  final isAscendingNotifier = ValueNotifier(false);

  final ValueNotifier<bool> isSearchNotifier = ValueNotifier(false);

  final scrollController = ScrollController();

  bool preparing = true;

  void updateCurrentList();

  @override
  void dispose() {
    textController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The skeleton is drawn over the grid rather than instead of it, so the
    // wait ends in a fade and the grid underneath never jumps.
    return ContentSwap(
      loading: preparing,
      placeholder: const SkeletonGrid(),
      child: collectionGrid(context),
    );
  }

  Widget collectionGrid(BuildContext context) {
    return GridView.builder(
      controller: scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: isTooNarrow(context) ? 20 : 40,
        vertical: 75 + getTopOffset(context),
      ),
      gridDelegate: MyGirdDelegate(
        maxCrossAxisExtent: 200,
        crossAxisSpacing: 20,
        mainAxisSpacing: 10,
        textExtent: 30,
      ),
      itemCount: pictureList.length,
      itemBuilder: (context, index) {
        final picture = pictureList[index];

        return Builder(
          builder: (context) {
            return ScaleWidget(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Column(
                    children: [
                      Hero(
                        tag: 'big${picture?.id ?? ''}${textList[index]}',
                        child: CoverArtWidget(
                          size: constraints.maxWidth,
                          borderRadius: constraints.maxWidth * 0.05,
                          picture: picture,
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(0, 5),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Align(
                            alignment: .centerLeft,
                            child: Text(
                              textList[index],
                              style: TextStyle(overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              onTap: () async {
                onTapList[index].call();
              },

              onFocus: () {
                final box = context.findRenderObject() as RenderBox;
                final viewport = RenderAbstractViewport.of(box);

                final target = viewport.getOffsetToReveal(box, 0.5).offset;

                scrollController.animateTo(
                  target.clamp(
                    scrollController.position.minScrollExtent,
                    scrollController.position.maxScrollExtent,
                  ),
                  duration: AppDuration.quick,
                  curve: AppCurve.enter,
                );
              },
            );
          },
        );
      },
    );
  }
}
