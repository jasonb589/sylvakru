import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/design/marquee_text.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/widgets/bottom_bar_song_tile.dart';
import 'package:sylvakru/base/widgets/cover_art_widget.dart';
import 'package:sylvakru/landscape_view/bottom_control.dart';

/// The song tile in the bottom bar: one height whatever the line under the
/// title says, and a cover that fits inside the bar.
///
/// It did not hold that. A title that has to travel answered with the whole
/// height it was offered - the bar's 75 px - as its own height, so the list
/// tile measured a 75 px title, put the line under it at y 83 (below the bar,
/// over the window's bottom edge) and centred the 50 px cover for a tile that
/// was never drawn. That is the half cover and the missing lyric line in the
/// report; the artist - album bar looked right only because that title fitted.
void main() {
  /// Where the pieces of the tile ended up, in window coordinates.
  late Rect barRect;
  late Rect tileRect;
  late Rect coverRect;
  late Rect titleRect;
  late Rect subtitleRect;

  setUpAll(() {
    // Building a song touches the app's support folder (cover and cache paths).
    appSupportDir = Directory.systemTemp.createTempSync('sylvakru_bottom_tile');
  });

  MyAudioMetadata song({String title = 'Know Better'}) {
    final metadata = MyAudioMetadata(
      AudioMetadata(title: title, artist: 'Tinashe', album: 'Songs for You'),
      id: 'know-better',
    );
    // A cover that is known not to exist: the tile draws its note straight away
    // instead of waiting on a file, so no picture loading runs here.
    metadata.picture.isLoaded = true;
    metadata.picture.isExist = false;
    return metadata;
  }

  /// The line under the title as the lyrics bar draws it when it has a line of
  /// its own: one line of text at the tile's own size. The player behind
  /// [LyricsLineBar] is what keeps that widget itself out of a test; both lines
  /// it can show are one line at 13, which is what this stands in for.
  Widget lyricLine() => const Text(
    'the line being sung right now',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: BottomBarSongTile.subtitleFontSize,
      color: Color(0xFF888888),
    ),
  );

  /// The tile in a bar: the bar is 75 px and gives the tile two of its five
  /// columns, which is the width at which a long title has to travel.
  Widget inBar(Widget child, {VisualDensity? density}) {
    return MaterialApp(
      theme: ThemeData(visualDensity: density),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            child: SizedBox(
              key: const ValueKey('bar'),
              height: BottomControl.barHeight,
              child: Row(
                children: [
                  Expanded(flex: 2, child: child),
                  const Expanded(flex: 3, child: SizedBox()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  BottomBarSongTile tileOf(MyAudioMetadata currentSong, Widget line) {
    return BottomBarSongTile(
      song: currentSong,
      onTap: () {},
      subtitle: KeyedSubtree(key: const ValueKey('subtitle'), child: line),
    );
  }

  /// Pumps the tile into the bar and reads back where everything landed.
  Future<void> pumpTile(
    WidgetTester tester,
    BottomBarSongTile child, {
    VisualDensity? density,
  }) async {
    await tester.pumpWidget(inBar(child, density: density));
    barRect = tester.getRect(find.byKey(const ValueKey('bar')));
    tileRect = tester.getRect(find.byType(BottomBarSongTile));
    coverRect = tester.getRect(find.byType(CoverArtWidget));
    titleRect = tester.getRect(find.byType(MarqueeText));
    subtitleRect = tester.getRect(find.byKey(const ValueKey('subtitle')));
  }

  /// What the bar has to be able to show: all of it inside the bar, and the
  /// cover a whole square, centred.
  void expectFitsInsideTheBar(String when) {
    expect(
      coverRect.size,
      const Size(BottomBarSongTile.coverSize, BottomBarSongTile.coverSize),
      reason: 'the cover has to be a whole square $when',
    );
    expect(
      coverRect.top,
      greaterThanOrEqualTo(barRect.top),
      reason: 'the cover starts below the top of the bar $when',
    );
    expect(
      coverRect.bottom,
      lessThanOrEqualTo(barRect.bottom),
      reason: 'the cover is cut off by the bottom of the window $when',
    );
    expect(
      coverRect.center.dy,
      closeTo(tileRect.center.dy, 0.01),
      reason: 'the cover is centred on the tile $when',
    );
    expect(
      tileRect.top,
      greaterThanOrEqualTo(barRect.top),
      reason: 'the tile starts below the top of the bar $when',
    );
    expect(
      tileRect.bottom,
      lessThanOrEqualTo(barRect.bottom),
      reason: 'the tile overflows the bar $when',
    );
    expect(
      titleRect.top,
      greaterThanOrEqualTo(tileRect.top),
      reason: 'the title is inside the tile $when',
    );
    expect(
      titleRect.height,
      lessThan(barRect.height),
      reason: 'the title takes one line, not the whole bar $when',
    );
    expect(
      subtitleRect.bottom,
      lessThanOrEqualTo(tileRect.bottom),
      reason: 'the line under the title is inside the tile $when',
    );
  }

  testWidgets('the same tile for artist - album and for a lyric line', (
    tester,
  ) async {
    final currentSong = song();

    await pumpTile(
      tester,
      tileOf(currentSong, BottomBarSongTile.artistAlbumLine(currentSong)),
    );
    expectFitsInsideTheBar('with artist - album');
    final artistAlbum = (
      tile: tileRect,
      cover: coverRect,
      subtitle: subtitleRect,
    );

    // The same song and the same tile, with a lyric line under the title.
    await pumpTile(tester, tileOf(currentSong, lyricLine()));
    expectFitsInsideTheBar('with a lyric line');

    expect(tileRect, artistAlbum.tile, reason: 'the tile changed size');
    expect(coverRect, artistAlbum.cover, reason: 'the cover moved');
    expect(
      subtitleRect.top,
      artistAlbum.subtitle.top,
      reason: 'the line under the title moved',
    );
  });

  testWidgets('a packed platform does not pack the bar tile', (tester) async {
    // The desktop theme packs list rows eight pixels tighter than the test
    // platform does - VisualDensity.compact, -2 * 4 px. A packed row also
    // allows a leading widget only 48 px, which is where the 50 px cover was
    // being squashed into 50 x 48. The bar's tile is not a list row: it keeps
    // its own density, so the cover stays a square on a Windows bar.
    await pumpTile(
      tester,
      tileOf(song(), lyricLine()),
      density: VisualDensity.compact,
    );
    expectFitsInsideTheBar('on the packed desktop density');

    // The packed theme really is the one this tile sits under: the cover being
    // a whole square above is about the tile staying off the theme's density,
    // not about the density never arriving.
    expect(
      Theme.of(tester.element(find.byType(BottomBarSongTile))).visualDensity,
      VisualDensity.compact,
    );
  });

  testWidgets('a title that has to travel does not stretch the tile', (
    tester,
  ) async {
    await pumpTile(tester, tileOf(song(), lyricLine()));
    expectFitsInsideTheBar('with a title that fits');
    final fitted = (tile: tileRect, cover: coverRect);

    // Long enough that the marquee has to travel through its column.
    final long = song(title: 'A song title far too long for the bar to hold');
    await pumpTile(tester, tileOf(long, lyricLine()));
    expect(
      find.byType(OverflowBox),
      findsOneWidget,
      reason: 'the title has to be travelling for this to test anything',
    );
    expectFitsInsideTheBar('with a title that travels');

    expect(tileRect, fitted.tile, reason: 'the travelling title grew the tile');
    expect(
      coverRect,
      fitted.cover,
      reason: 'the travelling title moved the cover',
    );
  });

  testWidgets('a travelling title is one line tall, not its container', (
    tester,
  ) async {
    // The marquee used to answer with the height it was given: inside 75 px it
    // reported 75 px for a 24 px line, and everything stacked under it followed.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 75,
              // Loose, the way a list tile hands its title slot over: the
              // marquee may be a line tall, and used to take all 75 instead.
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: MarqueeText(
                  text: 'a title that cannot fit the width it is given here',
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(OverflowBox), findsOneWidget);
    expect(
      tester.getSize(find.byType(MarqueeText)).height,
      lessThan(75),
      reason: 'the marquee reports the line it draws, not the height on offer',
    );
  });
}
