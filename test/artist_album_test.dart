import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/stream_client.dart';

MyAudioMetadata song(String id, {String? artist, String? album}) {
  return MyAudioMetadata(
    AudioMetadata(title: id, artist: artist, album: album),
    id: id,
  );
}

/// Stands in for a stream source: only the artist list is needed here.
class FakeClient extends StreamClient {
  FakeClient(this.artists)
    : super(baseUrl: 'http://server', username: 'u', password: 'p');

  final List<Artist> artists;

  @override
  Future<List<Artist>?> getArtistList() async => artists;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  // appSupportDir is a late final, so it can only be assigned once per process
  setUpAll(() {
    appSupportDir = Directory.systemTemp.createTempSync('sylvakru_aa');
  });

  setUp(() {
    sourceType = SourceType.navidrome;
    isStreamSource = true;
    isNotStreamSource = false;

    artistAlbumManager.clear();
    library.songList = [];
  });

  group('classify', () {
    test('groups songs under their artist', () {
      library.songList = [
        song('s1', artist: '温奕心', album: '破茧'),
        song('s2', artist: '温奕心', album: '破茧'),
        song('s3', artist: '王菲', album: '但愿人长久'),
      ];

      artistAlbumManager.classify();

      final artist = artistAlbumManager.artistMap['温奕心']!;
      expect(artist.songList.map((e) => e.id), ['s1', 's2']);
      expect(artist.albumList.single.name, '破茧');
    });

    test('is idempotent instead of duplicating songs', () {
      library.songList = [song('s1', artist: '温奕心', album: '破茧')];

      artistAlbumManager.classify();
      artistAlbumManager.classify();
      artistAlbumManager.classify();

      final artist = artistAlbumManager.artistMap['温奕心']!;
      // appending to the previous pass used to grow this on every call
      expect(artist.songList.map((e) => e.id), ['s1']);
      expect(artistAlbumManager.artistList, hasLength(1));
      expect(artistAlbumManager.albumList, hasLength(1));
    });

    test('drops entries for songs that are gone', () {
      library.songList = [song('s1', artist: '温奕心', album: '破茧')];
      artistAlbumManager.classify();
      expect(artistAlbumManager.artistList, hasLength(1));

      library.songList = [];
      artistAlbumManager.classify();

      expect(artistAlbumManager.artistList, isEmpty);
      expect(artistAlbumManager.albumList, isEmpty);
    });
  });

  group('loadArtists', () {
    test('merges a server artist into the classified one by name', () async {
      library.songList = [song('s1', artist: '温奕心', album: '破茧')];
      artistAlbumManager.classify();

      // what getArtists.view returns: no songs, but an id, a cover art id and
      // an album count
      streamClient = FakeClient([
        Artist(
          '温奕心',
          id: 'srv-温奕心',
          coverArtId: 'cov-温奕心',
          serverAlbumCount: 1,
        ),
      ]);

      await artistAlbumManager.loadArtists();

      // the old behaviour appended a second artist of the same name and let it
      // overwrite the map, so the page opened on an object with no songs
      final matches = artistAlbumManager.artistList
          .where((a) => a.name == '温奕心')
          .toList();
      expect(matches, hasLength(1));

      final artist = matches.single;
      expect(artist.songList.map((e) => e.id), ['s1']);
      expect(identical(artistAlbumManager.artistMap['温奕心'], artist), isTrue);
      expect(artist.id, 'srv-温奕心');
      expect(artist.serverAlbumCount, 1);
    });

    test('keeps the songs after a later classify', () async {
      library.songList = [song('s1', artist: '温奕心', album: '破茧')];
      artistAlbumManager.classify();
      streamClient = FakeClient([Artist('温奕心', id: 'srv-温奕心')]);
      await artistAlbumManager.loadArtists();

      artistAlbumManager.classify();

      final artist = artistAlbumManager.artistMap['温奕心']!;
      expect(artist.songList.map((e) => e.id), ['s1']);
      expect(artist.id, 'srv-温奕心');
    });

    test('still lists an artist the library has no song for', () async {
      library.songList = [song('s1', artist: '王菲', album: '但愿人长久')];
      artistAlbumManager.classify();

      streamClient = FakeClient([
        Artist('베일드뮤지션', id: 'srv-1', serverAlbumCount: 2),
      ]);
      await artistAlbumManager.loadArtists();

      final artist = artistAlbumManager.artistMap['베일드뮤지션']!;
      expect(artist.songList, isEmpty);
      expect(artist.serverAlbumCount, 2);
    });

    test('does not ask the server twice', () async {
      final client = FakeClient([Artist('温奕心', id: 'srv-温奕心')]);
      streamClient = client;
      library.songList = [song('s1', artist: '温奕心', album: '破茧')];
      artistAlbumManager.classify();

      await artistAlbumManager.loadArtists();
      await artistAlbumManager.loadArtists();

      expect(artistAlbumManager.artistList, hasLength(1));
    });
  });
}
