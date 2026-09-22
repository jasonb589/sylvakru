import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/widgets/cover_art_widget.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/layer/layers_manager.dart';

/// The "recently added" module shown on top of the songs page.
///
/// Local and WebDAV libraries are sorted by the newest file modification time
/// of each album, stream sources ask the server for their newest albums.
class RecentlyAdded extends StatefulWidget {
  final EdgeInsetsGeometry padding;
  final double itemSize;

  const RecentlyAdded({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 30),
    this.itemSize = 130,
  });

  @override
  State<StatefulWidget> createState() => _RecentlyAddedState();
}

class _RecentlyAddedState extends State<RecentlyAdded> {
  @override
  void initState() {
    super.initState();

    artistAlbumManager.recentlyAddedNotifier.addListener(_onUpdate);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // no-op while the cached list is still fresh; this is what picks up
      // albums added on the server without restarting the app
      artistAlbumManager.loadRecentlyAdded();
    });
  }

  @override
  void dispose() {
    artistAlbumManager.recentlyAddedNotifier.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final albumList = artistAlbumManager.recentlyAddedAlbumList;
    if (albumList.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: widget.padding,
          child: Text(
            AppLocalizations.of(context).recentlyAdded,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          // cover + two lines of text
          height: widget.itemSize + 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: widget.padding,
            itemCount: albumList.length,
            separatorBuilder: (_, _) => const SizedBox(width: 15),
            itemBuilder: (context, index) {
              return albumCard(albumList[index]);
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget albumCard(Album album) {
    return SizedBox(
      width: widget.itemSize,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          layersManager.pushDetail('albums', album);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListenableBuilder(
              listenable: Listenable.merge([album.picture.changeNotifier]),
              builder: (_, _) {
                return CoverArtWidget(
                  size: widget.itemSize,
                  borderRadius: 10,
                  picture: album.picture,
                );
              },
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ClipRect(
                child: Text(
                  album.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
