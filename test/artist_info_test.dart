import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/stream_client.dart';
import 'package:sylvakru/base/widgets/artist_metadata.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';

import 'package:sylvakru/base/services/logger.dart';

/// The artist page showed a name, an album count and the songs, but no
/// biography, even though the server has one. The request for it used to ride
/// along with the song load, and an artist whose songs are already in the
/// library never loaded songs. These tests pin the request to the place that
/// actually displays the biography.
class FakeClient extends StreamClient {
  FakeClient({this.biography, this.fail = false})
    : super(baseUrl: 'http://server', username: 'u', password: 'p');

  final String? biography;
  final bool fail;
  int infoCalls = 0;

  @override
  Future<Artist?> getArtistInfo(Artist artist) async {
    infoCalls++;
    if (fail) {
      throw StateError('offline');
    }
    final text = biography;
    if (text != null) {
      artist.biography = text;
    }
    return artist;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  // appSupportDir is a late final, so it can only be assigned once per process
  setUpAll(() async {
    appSupportDir = Directory.systemTemp.createTempSync('sylvakru_artist_info');
    await logger.init();
  });

  setUp(() {
    sourceType = SourceType.navidrome;
    isStreamSource = true;
    isNotStreamSource = false;
  });

  test('the biography is asked for once and kept', () async {
    final client = FakeClient(biography: 'A singer from Seoul.');
    streamClient = client;
    final artist = Artist('Ejel', id: 'ar-1');

    await artist.loadInfo();

    expect(client.infoCalls, 1);
    expect(artist.biography, 'A singer from Seoul.');
    expect(artist.biographyLoaded, isTrue);

    await artist.loadInfo();

    expect(client.infoCalls, 1);
  });

  test('a failed attempt is tried again on the next visit', () async {
    final client = FakeClient(fail: true);
    streamClient = client;
    final artist = Artist('Ejel', id: 'ar-1');

    await artist.loadInfo();

    expect(client.infoCalls, 1);
    expect(artist.biography, isNull);
    expect(artist.biographyLoaded, isFalse);

    await artist.loadInfo();

    expect(client.infoCalls, 2);
  });

  test('local libraries never ask the server', () async {
    final client = FakeClient(biography: 'A singer from Seoul.');
    streamClient = client;
    sourceType = SourceType.local;
    isStreamSource = false;
    isNotStreamSource = true;

    await Artist('Ejel').loadInfo();

    expect(client.infoCalls, 0);
  });

  testWidgets('the metadata block asks for the biography itself', (
    tester,
  ) async {
    final client = FakeClient(biography: 'A singer from Seoul.');
    streamClient = client;
    final artist = Artist('Ejel', id: 'ar-1');
    // What the library hands the page: the artist already has its song, which
    // is exactly the case where the old code never asked the server.
    artist.songList.add(
      MyAudioMetadata(AudioMetadata(title: '의리소녀'), id: 's1'),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ArtistMetadata(artist: artist)),
      ),
    );
    await tester.pumpAndSettle();

    expect(client.infoCalls, 1);
    expect(find.textContaining('A singer from Seoul.'), findsOneWidget);
  });
}
