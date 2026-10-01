import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/utils/search.dart';
import 'package:sylvakru/layer/search_layer.dart';

MyAudioMetadata _song(
  String id, {
  String? title,
  String? artist,
  String? album,
}) => MyAudioMetadata(
  AudioMetadata(title: title, artist: artist, album: album),
  id: id,
);

/// Three songs, one album and one artist, arranged so that a keyword can be
/// asked for that names an album or an artist and no song at all.
List<MyAudioMetadata> _songs() => [
  _song(
    'train',
    title: 'Blue Train',
    artist: 'John Coltrane',
    album: 'Classic Jazz',
  ),
  _song('kind', title: 'So What', artist: 'Miles Davis', album: 'Kind of Blue'),
  _song('untitled', title: 'Untitled', artist: 'Nobody', album: 'Untitled'),
];

Album _neonAlbum() => Album('Neon', id: 'al-neon')
  ..songList.add(_song('afterglow', title: 'Afterglow', artist: 'Neon Lights'));

void main() {
  setUpAll(() {
    appSupportDir = Directory.systemTemp.createTempSync('sylvakru_search');
  });

  setUp(() {
    sourceType = SourceType.local;
    isStreamSource = false;
    isNotStreamSource = true;
  });

  group('matchesSearchQuery', () {
    test('ignores case and the space around the keyword', () {
      expect(matchesSearchQuery('blue', ['Blue Train']), isTrue);
      expect(matchesSearchQuery('BLUE', ['Blue Train']), isTrue);
      expect(matchesSearchQuery('  blue  ', ['Blue Train']), isTrue);
      expect(matchesSearchQuery('green', ['Blue Train']), isFalse);
    });

    test('an empty keyword matches nothing', () {
      expect(matchesSearchQuery('', ['Blue Train']), isFalse);
      expect(matchesSearchQuery('   ', ['Blue Train']), isFalse);
      expect(matchesSearchQuery('', []), isFalse);
    });

    test('a field with no value never matches', () {
      expect(matchesSearchQuery('blue', [null, '', 'Blue Train']), isTrue);
      expect(matchesSearchQuery('blue', [null, '']), isFalse);
    });
  });

  group('searchSongsIn', () {
    test('looks at the title, the artist and the album', () {
      expect(searchSongsIn(_songs(), 'blue train').map((song) => song.id), [
        'train',
      ]);
      expect(searchSongsIn(_songs(), 'coltrane').map((song) => song.id), [
        'train',
      ]);
      expect(searchSongsIn(_songs(), 'kind of blue').map((song) => song.id), [
        'kind',
      ]);
    });

    test('ignores case across every field', () {
      expect(searchSongsIn(_songs(), 'BLUE').map((song) => song.id), [
        'train',
        'kind',
      ]);
    });

    test('an empty keyword finds nothing', () {
      expect(searchSongsIn(_songs(), ''), isEmpty);
      expect(searchSongsIn(_songs(), '   '), isEmpty);
    });

    test('a keyword that only names an album or an artist invents no song', () {
      expect(searchSongsIn(_songs(), 'neon'), isEmpty);
      expect(searchSongsIn(_songs(), 'kind of blue neon'), isEmpty);

      // the keyword itself is fine: the album and the artist answer for it
      expect(searchAlbumsIn([_neonAlbum()], 'neon').single.name, 'Neon');
      expect(
        searchArtistsIn([Artist('Neon', id: 'ar-neon')], 'neon').single.name,
        'Neon',
      );
    });

    test('a section stops at the cap', () {
      final many = [
        for (var index = 0; index < searchResultLimit + 10; index++)
          _song('$index', title: 'Blue $index'),
      ];

      expect(searchResultLimit, 50);
      expect(searchSongsIn(many, 'blue').length, searchResultLimit);
    });
  });

  group('searchAlbumsIn', () {
    test('looks at the album name and the artist on it', () {
      expect(searchAlbumsIn([_neonAlbum()], 'NEO').map((album) => album.name), [
        'Neon',
      ]);
      expect(
        searchAlbumsIn([_neonAlbum()], 'neon lights').map(albumArtistLine),
        ['Neon Lights'],
      );
      expect(searchAlbumsIn([_neonAlbum()], 'nothing here'), isEmpty);
      expect(searchAlbumsIn([_neonAlbum()], ''), isEmpty);
    });
  });

  group('searchArtistsIn', () {
    test('looks at the artist name', () {
      final artists = [Artist('Neon', id: 'ar-neon')];

      expect(searchArtistsIn(artists, 'ne').map((artist) => artist.name), [
        'Neon',
      ]);
      expect(searchArtistsIn(artists, 'NEON').map((artist) => artist.name), [
        'Neon',
      ]);
      expect(searchArtistsIn(artists, 'elsewhere'), isEmpty);
      expect(searchArtistsIn(artists, ''), isEmpty);
    });
  });

  group('where the search field lives', () {
    String source(String path) => File(path).readAsStringSync();

    bool has(String path, String pattern) =>
        RegExp(pattern).hasMatch(source(path));

    test('no advanced-search (tune button) symbol is left under lib', () {
      const symbols = [
        'advancedSearch',
        'AdvancedSongSearchDialog',
        'onAdvancedSearch',
        'hasAdvancedSearch',
        'SongSearchCriteria',
        'filterSongListAdvanced',
        'advanced_song_search',
        'tune_rounded',
      ];

      final offenders = <String>[];
      var scanned = 0;
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))) {
        scanned++;
        final text = file.readAsStringSync();
        for (final symbol in symbols) {
          if (text.contains(symbol)) {
            offenders.add('${file.path.replaceAll('\\', '/')}: $symbol');
          }
        }
      }

      // A guard that read no sources would pass without checking anything.
      expect(scanned, greaterThan(100));

      expect(
        offenders,
        isEmpty,
        reason: 'the advanced search is gone:\n${offenders.join('\n')}',
      );
    });

    test('the sidebar field drives the search layer', () {
      const sidebar = 'lib/landscape_view/sidebar.dart';

      expect(has(sidebar, r'_SidebarSearchField'), isTrue);
      expect(has(sidebar, r'searchQueryNotifier'), isTrue);
      expect(has(sidebar, r"switchRootLayer\('search'\)"), isTrue);
      expect(
        has(sidebar, r'searchFieldColor'),
        isFalse,
        reason:
            'the sidebar is flat rows: the field must not paint a colour '
            'block above them',
      );
    });

    test('the search layer is registered', () {
      const manager = 'lib/layer/layers_manager.dart';

      expect(has(manager, r"label == 'search'"), isTrue);
      expect(has(manager, r'SearchLayer\(key: GlobalKey\(\)\)'), isTrue);
    });

    test('the songs page has no search field of its own', () {
      expect(
        has(
          'lib/base/widgets/song_list.dart',
          r'showSearchField => !isLibrary && artist == null',
        ),
        isTrue,
      );
      expect(
        has(
          'lib/landscape_view/panels/song_list_panel.dart',
          r'hintText: showSearchField \? l10n\.searchSongs : null',
        ),
        isTrue,
      );
      expect(
        has(
          'lib/portrait_view/pages/song_list_page.dart',
          r'if \(showSearchField\)',
        ),
        isTrue,
      );
    });

    test('the artists page has no search field of its own', () {
      expect(
        has(
          'lib/base/widgets/collection_list.dart',
          r'showSearchField => true',
        ),
        isTrue,
      );
      expect(
        has('lib/layer/artists_layer.dart', r'showSearchField => false'),
        isTrue,
      );
      expect(
        has(
          'lib/landscape_view/panels/collection_list_panel.dart',
          r'hintText: showSearchField \? searchHint : null',
        ),
        isTrue,
      );
      expect(
        has(
          'lib/portrait_view/pages/collection_list_page.dart',
          r'if \(showSearchField\) searchField\(searchHint\)',
        ),
        isTrue,
      );
    });
  });
}
