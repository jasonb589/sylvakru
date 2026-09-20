import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/services/picture_service.dart';
import 'package:sylvakru/base/utils/zoom_page_route.dart';
import 'package:sylvakru/big_picture_view/panels/big_collection_list_panel.dart';
import 'package:sylvakru/big_picture_view/panels/big_single_album_panel.dart';

/// The newest albums of the library, mirroring the "recently added" module of
/// the songs page.
class BigRecentlyAddedPanel extends StatelessWidget {
  const BigRecentlyAddedPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return _BigRecentlyAddedAlbumListPanel();
  }
}

class _BigRecentlyAddedAlbumListPanel extends BigCollectionListPanel {
  const _BigRecentlyAddedAlbumListPanel();

  @override
  State<StatefulWidget> createState() => _BigRecentlyAddedAlbumListPanelState();
}

class _BigRecentlyAddedAlbumListPanelState
    extends BigCollectionListPanelState {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await artistAlbumManager.loadRecentlyAdded();
      if (!mounted) {
        return;
      }
      updateCurrentList();
    });

    artistAlbumManager.recentlyAddedNotifier.addListener(updateCurrentList);
  }

  @override
  void dispose() {
    artistAlbumManager.recentlyAddedNotifier.removeListener(updateCurrentList);
    super.dispose();
  }

  @override
  void updateCurrentList() {
    preparing = false;
    final value = textController.text;
    final list = artistAlbumManager.recentlyAddedAlbums
        .where((e) => (e.name.toLowerCase().contains(value.toLowerCase())))
        .toList();

    pictureList = list.map((e) => e.picture).toList();
    textList = list.map((e) => e.name).toList();
    onTapList = list
        .map(
          (e) => () async {
            final baseColor = await computeColor(e.picture);
            if (mounted) {
              Navigator.of(context).push(
                ZoomPageRoute(
                  builder: (context) {
                    return BigSingleAlbumPanel(album: e, baseColor: baseColor);
                  },
                ),
              );
            }

            return;
          },
        )
        .toList();
    if (mounted) {
      setState(() {});
    }
  }
}
