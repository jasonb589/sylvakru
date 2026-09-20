import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/asset_images.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/widgets/collection_list.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/layer/layers_manager.dart';

final GlobalKey<NavigatorState> recentlyAddedKey = GlobalKey();
final recentlyAddedVisibleNotifier = ValueNotifier(true);

/// The "recently added" albums as a full collection list.
///
/// This is the module shown on the songs page, without the
/// [ArtistAlbumManager.recentlyAddedLimit] cap.
class RecentlyAddedLayer extends CollectionList {
  const RecentlyAddedLayer({super.key});

  @override
  State<StatefulWidget> createState() => _RecentlyAddedLayerState();
}

class _RecentlyAddedLayerState extends CollectionListState {
  @override
  GlobalKey<NavigatorState> get globalKey => recentlyAddedKey;

  @override
  ValueNotifier<bool> get visibleNotifier => recentlyAddedVisibleNotifier;

  @override
  AssetImage get image => albumImage;

  @override
  String Function(int) get countFunction =>
      AppLocalizations.of(context).albumCount;

  @override
  String get label => 'recentlyAdded';

  List<Album> get _albumList => artistAlbumManager.recentlyAddedAlbums;

  @override
  void updateCurrentList() {
    preparing = false;
    final value = textController.text;
    final list = _albumList
        .where((e) => (e.name.toLowerCase().contains(value.toLowerCase())))
        .toList();
    currentPictureList = list.map((e) => e.picture).toList();
    currentTextList = list.map((e) => e.name).toList();
    currentOnTapList = list
        .map(
          (e) => () {
            if (e.picture.isLoaded) {
              layersManager.pushDetail('recentlyAdded', e);
            }
          },
        )
        .toList();
    changeNotifier.value++;
  }

  @override
  Future<void> fetchCollectionList() async {
    // stream sources have to ask the server for the newest albums, non-stream
    // sources already own their whole album list
    await artistAlbumManager.loadRecentlyAdded();
    reachEnd = true;
    updateCurrentList();
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (isStreamSource || _albumList.isEmpty) {
        await artistAlbumManager.loadRecentlyAdded();
      }
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    title = l10n.recentlyAdded;
    searchHint = l10n.searchAlbums;
    return super.build(context);
  }
}
