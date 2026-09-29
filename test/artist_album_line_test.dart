import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/widgets/artist_album_line.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/services/picture_service.dart';
import 'package:sylvakru/layer/layers_manager.dart';

/// The playback screens carry the way into an artist page: in "Artist - Album"
/// the artist is a tap target and the album beside it is not, so a tap meant
/// for the album cannot land on the artist.
///
/// The bottom bar deliberately does not use this widget. There the whole row
/// opens the playback screen, and the artist name inside it is plain text that
/// goes nowhere.
void main() {
  // Building a song touches the app's support folder (cover and cache paths),
  // so point it at a temporary directory first.
  setUpAll(() {
    appSupportDir = Directory.systemTemp.createTempSync('sylvakru_aa_line');
    // The layer machine behind the artist page asks for cover colours: with no
    // bytes to read it settles on grey instead of reaching for a server.
    pictureBytesLoader = (_) async => null;
  });

  MyAudioMetadata buildSong() => MyAudioMetadata(
    AudioMetadata(
      title: 'Know Better',
      artist: 'Tinashe',
      album: 'Songs for You',
    ),
    id: 'know-better',
  );

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('the artist is a target and the album is not', (tester) async {
    await tester.pumpWidget(
      wrap(
        ArtistAlbumLine(
          song: buildSong(),
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );

    final line = find.byType(ArtistAlbumLine);
    final artist = find.text('Tinashe');
    final album = find.text(' - Songs for You');
    expect(artist, findsOneWidget);
    expect(album, findsOneWidget);

    // Exactly one tap target on the line: the artist.
    expect(
      find.descendant(of: line, matching: find.byType(GestureDetector)),
      findsOneWidget,
    );

    // A pointer that turns into a hand is what marks the artist as the target.
    expect(
      find.ancestor(of: artist, matching: find.byType(MouseRegion)),
      findsWidgets,
    );
    expect(
      find.ancestor(of: album, matching: find.byType(MouseRegion)),
      findsNothing,
    );
  });

  testWidgets('a line without a song has no target at all', (tester) async {
    await tester.pumpWidget(
      wrap(ArtistAlbumLine(song: null, style: const TextStyle(fontSize: 14))),
    );

    // The placeholder name and album are still drawn, but nothing on the line
    // is tappable and no pointer changes: there is no artist to open.
    final line = find.byType(ArtistAlbumLine);
    expect(
      find.descendant(of: line, matching: find.byType(Text)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: line, matching: find.byType(GestureDetector)),
      findsNothing,
    );
    expect(
      find.descendant(of: line, matching: find.byType(MouseRegion)),
      findsNothing,
    );
  });

  // The bars that open the playback screen must not carry the artist link
  // themselves: tapping one used to jump straight to the artist page, which
  // skipped the screen the bar is there to open.
  test('the bottom bars leave the artist to the playback screen', () {
    for (final path in const [
      'lib/base/widgets/big_play_bar.dart',
      'lib/landscape_view/bottom_control.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source.contains('goToArtist'), isFalse, reason: path);
    }

    for (final path in const [
      'lib/landscape_view/pages/landscape_lyrics_page.dart',
      'lib/portrait_view/pages/portrait_lyrics_page.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source.contains('ArtistAlbumLine('), isTrue, reason: path);
    }
  });

  // The playback screen is a route above the layer stack, and its artist link
  // switches layers underneath: without stepping out of that route first the
  // artist page opened hidden behind the screen and only appeared once the
  // screen was closed, which is what this pins down.
  testWidgets('the artist takes you off the playback screen, not under it', (
    tester,
  ) async {
    artistAlbumManager.artistMap['Tinashe'] = Artist('Tinashe');
    addTearDown(() => artistAlbumManager.artistMap.remove('Tinashe'));

    await tester.pumpWidget(
      MaterialApp(home: const Scaffold(body: Text('the layers'))),
    );

    final navigator = Navigator.of(tester.element(find.text('the layers')));
    final playback = navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          body: Center(
            child: ArtistAlbumLine(
              song: buildSong(),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ArtistAlbumLine), findsOneWidget);

    await tester.tap(find.text('Tinashe'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    // The screen the artist was tapped on is gone: the artist page, opened on
    // the layers underneath it, is what is left to look at.
    expect(find.byType(ArtistAlbumLine), findsNothing);
    expect(
      layersManager.topRootLayer,
      isNotNull,
      reason: 'the artist page opened on the layers',
    );
    expect(playback, completes);
  });
}
