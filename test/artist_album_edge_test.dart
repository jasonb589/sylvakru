import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/stream_client.dart';

MyAudioMetadata song(String id, {String? artist, String? album}) =>
    MyAudioMetadata(
      AudioMetadata(title: id, artist: artist, album: album),
      id: id,
    );

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
  setUpAll(() {
    appSupportDir = Directory.systemTemp.createTempSync('sylvakru_edge');
  });

  setUp(() {
    sourceType = SourceType.navidrome;
    isStreamSource = true;
    isNotStreamSource = false;
    artistAlbumManager.clear();
    library.songList = [];
  });

  test('ghost artist is not duplicated by a later classify', () async {
    library.songList = [song('s1', artist: '王菲', album: '但愿人长久')];
    artistAlbumManager.classify();

    streamClient = FakeClient([Artist('Ghost', id: 'g1', serverAlbumCount: 2)]);
    await artistAlbumManager.loadArtists();

    expect(artistAlbumManager.artistList.where((a) => a.name == 'Ghost'), hasLength(1));

    // classify again, twice: the merge runs on each pass
    artistAlbumManager.classify();
    artistAlbumManager.classify();

    final ghosts = artistAlbumManager.artistList.where((a) => a.name == 'Ghost');
    expect(ghosts, hasLength(1), reason: 'Ghost must appear exactly once');
    expect(ghosts.single.serverAlbumCount, 2);

    // 王菲 must keep its song through every pass
    final faye = artistAlbumManager.artistMap['王菲']!;
    expect(faye.songList.map((e) => e.id), ['s1']);
  });

  test('server metadata survives classify and does not clobber local songs',
      () async {
    library.songList = [
      song('s1', artist: '温奕心', album: '破茧'),
      song('s2', artist: '温奕心', album: '破茧'),
    ];
    artistAlbumManager.classify();

    streamClient = FakeClient([
      Artist('温奕心', id: 'srv', coverArtId: 'cov', serverAlbumCount: 9),
    ]);
    await artistAlbumManager.loadArtists();

    artistAlbumManager.classify();

    final artist = artistAlbumManager.artistMap['温奕心']!;
    expect(artist.songList.map((e) => e.id), ['s1', 's2']);
    expect(artist.id, 'srv');
    expect(artist.serverAlbumCount, 9);
  });

  test('loadArtists after clear re-fetches from the server', () async {
    library.songList = [song('s1', artist: '王菲', album: '但愿人长久')];
    artistAlbumManager.classify();
    streamClient = FakeClient([Artist('Ghost', id: 'g1')]);
    await artistAlbumManager.loadArtists();
    expect(artistAlbumManager.artistMap.containsKey('Ghost'), isTrue);

    // a reload/sync path: clear() must reset the completer so the next
    // loadArtists actually asks again
    artistAlbumManager.clear();
    streamClient = FakeClient([Artist('Ghost2', id: 'g2')]);
    await artistAlbumManager.loadArtists();

    expect(artistAlbumManager.artistMap.containsKey('Ghost2'), isTrue);
  });
}
