import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/design/app_tokens.dart';
import 'package:sylvakru/base/design/empty_state.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/utils/media_query.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:sylvakru/base/utils/search.dart';
import 'package:sylvakru/base/widgets/cover_art_widget.dart';
import 'package:sylvakru/base/widgets/my_navigator.dart';
import 'package:sylvakru/base/widgets/my_scaffold.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/landscape_view/title_bar.dart';
import 'package:sylvakru/layer/layers_manager.dart';

/// What the sidebar search field currently holds.
///
/// The field writes it and the search page reads it, so typing in the sidebar
/// and the results are one thing rather than two.
final searchQueryNotifier = ValueNotifier<String>('');

final GlobalKey<NavigatorState> searchKey = GlobalKey();
final searchVisibleNotifier = ValueNotifier(true);

/// The songs of [songs] whose title, artist or album carries [query].
List<MyAudioMetadata> searchSongsIn(List<MyAudioMetadata> songs, String query) {
  return filterBySearchQuery(
    songs,
    query: query,
    fields: (song) => [getTitle(song), getArtist(song), getAlbum(song)],
  );
}

/// The albums of [albums] whose name or artist carries [query].
List<Album> searchAlbumsIn(List<Album> albums, String query) {
  return filterBySearchQuery(
    albums,
    query: query,
    fields: (album) => [album.name, albumArtistLine(album)],
  );
}

/// The artists of [artists] whose name carries [query].
List<Artist> searchArtistsIn(List<Artist> artists, String query) {
  return filterBySearchQuery(
    artists,
    query: query,
    fields: (artist) => [artist.name],
  );
}

/// The artists an album is credited to, one line.
///
/// The album's own grouping is filled while classifying the library; a stream
/// album that has not been loaded yet has none, so its first song answers
/// instead.
String albumArtistLine(Album album) {
  if (album.artist2SongList.isNotEmpty) {
    return album.artist2SongList.keys.join(', ');
  }
  if (album.songList.isNotEmpty) {
    return getArtist(album.songList.first);
  }
  return '';
}

/// The search page: what the sidebar field's keyword finds in songs, albums
/// and artists.
///
/// It only reads [searchQueryNotifier] - the field is what drives it, so the
/// page itself has no input of its own and never navigates away on its own.
class SearchLayer extends StatefulWidget {
  const SearchLayer({super.key});

  @override
  State<SearchLayer> createState() => _SearchLayerState();
}

class _SearchLayerState extends State<SearchLayer> {
  @override
  Widget build(BuildContext context) {
    return myNavigator(
      key: searchKey,
      visibleNotifier: searchVisibleNotifier,
      pageViewBuilder: () => pageView(context),
      panelViewBuilder: () => panelView(context),
    );
  }

  Widget panelView(BuildContext context) {
    return Column(
      children: [
        TitleBar(),
        Expanded(child: results(context, horizontalPadding: 30)),
      ],
    );
  }

  Widget pageView(BuildContext context) {
    return myScaffold(
      context: context,
      body: results(context, horizontalPadding: 20),
      title: AppLocalizations.of(context).searchEverything,
    );
  }

  Widget results(BuildContext context, {required double horizontalPadding}) {
    final l10n = AppLocalizations.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        searchQueryNotifier,
        library.changeNotifier,
        artistAlbumManager.updateNotifier,
      ]),
      builder: (context, _) {
        final query = searchQueryNotifier.value;
        final songs = searchSongsIn(library.songList, query);
        final albums = searchAlbumsIn(artistAlbumManager.albumList, query);
        final artists = searchArtistsIn(artistAlbumManager.artistList, query);

        if (songs.isEmpty && albums.isEmpty && artists.isEmpty) {
          return EmptyState(
            icon: query.trim().isEmpty
                ? Icons.search_rounded
                : Icons.search_off_rounded,
            // An empty page is either a keyword that found nothing or no
            // keyword at all, and the two ask for different things.
            title: query.trim().isEmpty
                ? l10n.searchStartTyping
                : l10n.searchNoResults,
          );
        }

        return ListView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            10 + getTopOffset(context),
            horizontalPadding,
            20,
          ),
          children: [
            if (songs.isNotEmpty) ...[
              sectionHeader(l10n.songs),
              for (var index = 0; index < songs.length; index++)
                songRow(songs, index),
            ],
            if (albums.isNotEmpty) ...[
              sectionHeader(l10n.albums),
              for (final album in albums) albumRow(album),
            ],
            if (artists.isNotEmpty) ...[
              sectionHeader(l10n.artists),
              for (final artist in artists) artistRow(artist),
            ],
          ],
        );
      },
    );
  }

  Widget sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Text(title, style: AppText.sheetTitle),
    );
  }

  Widget songRow(List<MyAudioMetadata> songs, int index) {
    final song = songs[index];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CoverArtWidget(
        size: 42,
        borderRadius: AppRadius.coverRow,
        picture: song.picture,
      ),
      title: Text(getTitle(song), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${getArtist(song)} - ${getAlbum(song)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        // The queue is what the search found, so the next song is the next
        // search result rather than whatever page the listener came from.
        audioHandler.setPlayQueue(songs, 0, targetIndex: index);
      },
    );
  }

  Widget albumRow(Album album) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CoverArtWidget(
        size: 42,
        borderRadius: AppRadius.coverRow,
        picture: album.picture,
      ),
      title: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        albumArtistLine(album),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => layersManager.openAlbumDetail(album),
    );
  }

  Widget artistRow(Artist artist) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CoverArtWidget(
        size: 42,
        borderRadius: AppRadius.coverRow,
        picture: artist.picture,
      ),
      title: Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => layersManager.openArtistDetail(artist),
    );
  }
}
