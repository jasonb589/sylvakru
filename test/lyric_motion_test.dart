import 'package:material_ui/material_ui.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/design/app_tokens.dart';
import 'package:sylvakru/base/widgets/lyric_list_view.dart';
import 'package:sylvakru/base/services/lyric.dart';
import 'package:sylvakru/base/utils/lyric_motion.dart';

/// The lyrics animation is arithmetic first: which line is being sung, how far
/// the fill has swept, and when the list has to start moving. All of it is
/// checked here, without a player and without a page.
void main() {
  LyricToken token(int startMs, String text, [int? endMs]) => LyricToken(
    Duration(milliseconds: startMs),
    text,
    endMs == null ? null : Duration(milliseconds: endMs),
  );

  LyricLine line(int startMs, String text, List<LyricToken> tokens) =>
      LyricLine(Duration(milliseconds: startMs), text, tokens);

  Duration ms(int value) => Duration(milliseconds: value);

  group('lyricIndexAt', () {
    final lines = [
      line(1000, 'one', [token(1000, 'one', 2000)]),
      line(2000, 'two', [token(2000, 'two', 3000)]),
      line(3000, 'three', [token(3000, 'three', 4000)]),
    ];

    test('is -1 before the first line', () {
      expect(lyricIndexAt(lines, ms(999)), -1);
    });

    test('lands on a line exactly at its start', () {
      expect(lyricIndexAt(lines, ms(2000)), 1);
    });

    test('keeps the line that is still being sung in between', () {
      expect(lyricIndexAt(lines, ms(2500)), 1);
    });

    test('stays on the last line afterwards', () {
      expect(lyricIndexAt(lines, ms(60000)), 2);
    });

    test('a translation line sharing a timestamp does not take over', () {
      final shared = [
        line(1000, 'one', [token(1000, 'one', 2000)]),
        line(1000, '翻译', [token(1000, '翻译', 2000)]),
      ];
      expect(lyricIndexAt(shared, ms(1500)), 0);
    });

    test('an empty list has no line', () {
      expect(lyricIndexAt([], ms(1500)), -1);
    });
  });

  group('lyricTokenOffsets', () {
    test('reads the tokens back out of the line in order', () {
      final lyrics = line(0, 'Bo Peep Bo', [
        token(0, 'Bo ', 100),
        token(100, 'Peep ', 200),
        token(200, 'Bo', 300),
      ]);
      expect(lyricTokenOffsets(lyrics), [0, 3, 8]);
    });

    test('keeps the offsets right when a space belongs to no token', () {
      final lyrics = line(0, 'A  B', [
        token(0, 'A', 100),
        token(100, 'B', 200),
      ]);
      expect(lyricTokenOffsets(lyrics), [0, 3]);
    });
  });

  group('lyricFillFor', () {
    test('a line without word timings fills across its own span', () {
      final lyrics = line(1000, 'hello world', [
        token(1000, 'hello world', 5000),
      ]);

      expect(lyricFillFor(lyrics, ms(3000)), const LyricFill(5, 0.5));
    });

    test('word timings drive the fill when the source has them', () {
      final lyrics = line(1000, 'Bo Peep Bo', [
        token(1000, 'Bo ', 1400),
        token(1400, 'Peep ', 2200),
        token(2200, 'Bo', 3000),
      ]);

      expect(lyricFillFor(lyrics, ms(1800)), const LyricFill(5, 0.5));
    });

    test('nothing is filled before the line starts', () {
      final lyrics = line(1000, 'Bo Peep', [
        token(1000, 'Bo ', 1400),
        token(1400, 'Peep', 2200),
      ]);

      expect(lyricFillFor(lyrics, ms(900)), const LyricFill(0, 0));
    });

    test('the whole line is filled once the voice is past it', () {
      final lyrics = line(1000, 'Bo Peep', [
        token(1000, 'Bo ', 1400),
        token(1400, 'Peep', 2200),
      ]);

      expect(lyricFillFor(lyrics, ms(9000)), const LyricFill(7, 0));
    });

    test('a gap between two words fills nothing of the next word yet', () {
      final lyrics = line(0, 'A  B', [
        token(0, 'A', 100),
        token(500, 'B', 900),
      ]);

      // Everything before the second token, which is where the voice is: it is
      // waiting on a word that has not started.
      expect(lyricFillFor(lyrics, ms(200)), const LyricFill(3, 0));
    });

    test('a token with no end fills at once rather than never', () {
      final lyrics = line(0, 'one', [token(0, 'one')]);

      expect(lyricFillFor(lyrics, ms(10)), const LyricFill(3, 0));
    });

    test('no tokens, nothing to fill', () {
      expect(lyricFillFor(line(0, 'plain text', []), ms(500)), LyricFill.empty);
    });
  });

  group('line strength', () {
    test('opacity steps down with distance and then stays at the floor', () {
      expect(lyricLineOpacity(0), 1.0);
      expect(lyricLineOpacity(1), 0.72);
      expect(lyricLineOpacity(2), 0.48);
      expect(lyricLineOpacity(3), 0.30);
      expect(lyricLineOpacity(9), 0.30);
    });

    test('opacity crosses the steps while a line takes over', () {
      expect(lyricLineOpacity(0.5), closeTo(0.86, 0.001));
    });

    test('only the current line is larger', () {
      expect(lyricLineScale(0), AppLyrics.currentScale);
      expect(lyricLineScale(1), 1.0);
      expect(lyricLineScale(4), 1.0);
      expect(lyricLineScale(0.5), lessThan(AppLyrics.currentScale));
    });

    test('a line away from the current one is a little lighter', () {
      expect(lyricLineWeight(FontWeight.bold, 0), FontWeight.bold);
      expect(lyricLineWeight(FontWeight.bold, 1), FontWeight.w500);
      expect(lyricLineWeight(FontWeight.bold, 0.5), FontWeight.w600);
      expect(lyricLineWeight(FontWeight.w100, 1), FontWeight.w100);
    });

    test('distance is measured from the line being sung', () {
      expect(lyricDistance(3, 1), 2);
      expect(lyricDistance(1, 3), 2);
      // Nothing current yet: every line is at the floor.
      expect(lyricDistance(0, -1), AppLyrics.lineOpacities.length - 1);
    });
  });

  group('following the music', () {
    test('a step is short and a long jump is not worth flying', () {
      expect(lyricScrollMs(1), 265);
      expect(lyricScrollMs(3), 355);
      expect(lyricScrollMs(0), AppLyrics.scrollMinMs);
      expect(lyricScrollMs(10), AppLyrics.scrollMaxMs);
    });

    test('the scroll starts before the line does', () {
      expect(
        lyricScrollDue(
          position: ms(1000),
          nextStart: ms(2000),
          durationMs: 260,
        ),
        isFalse,
      );
      expect(
        lyricScrollDue(
          position: ms(1740),
          nextStart: ms(2000),
          durationMs: 260,
        ),
        isTrue,
      );
      expect(
        lyricScrollDue(
          position: ms(2000),
          nextStart: ms(2000),
          durationMs: 260,
        ),
        isTrue,
      );
    });
  });

  group('lyricDrawPosition', () {
    test('keeps the smoothed position while it is close to the report', () {
      expect(
        lyricDrawPosition(reported: ms(1000), smoothed: ms(1030)),
        ms(1030),
      );
    });

    test('never runs more than the lead ahead of the voice', () {
      expect(
        lyricDrawPosition(reported: ms(1000), smoothed: ms(1200)),
        ms(1000 + AppLyrics.interpolationLeadMs),
      );
    });

    test('a smoothed value that fell behind is pulled up to the voice', () {
      // This is what kept the words behind the song: the player reports every
      // ~50 ms, and a smoothed value left behind stayed behind for good.
      expect(
        lyricDrawPosition(reported: ms(1000), smoothed: ms(900)),
        ms(1000),
      );
      expect(
        lyricDrawPosition(reported: ms(1000), smoothed: ms(700)),
        ms(1000),
      );
    });

    test('a lag of one frame is left alone', () {
      // It is invisible, and jumping for it would only add jitter.
      expect(
        lyricDrawPosition(
          reported: ms(1000),
          smoothed: ms(1000 - AppLyrics.lagToleranceMs + 4),
        ),
        ms(1000 - AppLyrics.lagToleranceMs + 4),
      );
    });

    test('a seek is not drift: the reported position wins', () {
      expect(
        lyricDrawPosition(reported: ms(1000), smoothed: ms(90000)),
        ms(1000),
      );
    });
  });

  group('LyricFillText', () {
    Widget wrap(Widget child, {double width = 300}) {
      return MaterialApp(
        home: Center(
          child: SizedBox(width: width, child: child),
        ),
      );
    }

    testWidgets('draws a line at any point of it', (tester) async {
      final lyrics = line(1000, 'Bo Peep Bo Peep', [
        token(1000, 'Bo ', 1400),
        token(1400, 'Peep ', 2200),
        token(2200, 'Bo Peep', 3000),
      ]);

      for (final position in [ms(0), ms(1000), ms(1500), ms(2500), ms(9000)]) {
        await tester.pumpWidget(
          wrap(
            LyricFillText(
              line: lyrics,
              position: position,
              fontSize: 16,
              expanded: true,
              isDesktopLyrics: true,
            ),
          ),
        );
        expect(
          tester.getSize(find.byType(LyricFillText)).height,
          greaterThan(0),
        );
      }
    });

    testWidgets('a line that wraps is drawn row by row', (tester) async {
      const text =
          'a line long enough that it cannot fit on one row of a narrow page';
      final lyrics = line(0, text, [token(0, text, 8000)]);

      await tester.pumpWidget(
        wrap(
          LyricFillText(
            line: lyrics,
            position: ms(4000),
            fontSize: 16,
            expanded: true,
            isDesktopLyrics: true,
          ),
          width: 120,
        ),
      );

      // More than one row, and the fill still painted inside it.
      expect(
        tester.getSize(find.byType(LyricFillText)).height,
        greaterThan(40),
      );
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('draws from the clock the page hands in', (tester) async {
      // With a clock there is no second clock and no player involved: the page
      // owns the position, so the highlight and the fill can never disagree.
      final clock = ValueNotifier<Duration>(ms(1500));
      addTearDown(clock.dispose);
      final lyrics = line(1000, 'Bo Peep Bo Peep', [
        token(1000, 'Bo ', 1400),
        token(1400, 'Peep ', 2200),
        token(2200, 'Bo Peep', 3000),
      ]);

      await tester.pumpWidget(
        wrap(
          LyricFillText(
            line: lyrics,
            position: Duration.zero,
            clock: clock,
            fontSize: 16,
            expanded: true,
          ),
        ),
      );

      clock.value = ms(2600);
      await tester.pump();

      expect(tester.getSize(find.byType(LyricFillText)).height, greaterThan(0));
    });
  });

  group('pointer and tap', () {
    test('a tap rises quickly and settles slowly', () {
      expect(lyricTapPulse(0), 0);
      expect(lyricTapPulse(0.35), 1);
      expect(lyricTapPulse(1), 0);
      // The rise is over sooner than the settle: a tap, not a bounce.
      expect(lyricTapPulse(0.2), greaterThan(lyricTapPulse(0.7)));
    });

    test('blur starts past the lines beside the current one', () {
      expect(lyricFarBlurSigma(0), 0);
      expect(lyricFarBlurSigma(1), 0);
      expect(lyricFarBlurSigma(2), 0);
      expect(lyricFarBlurSigma(3), greaterThan(0));
      expect(lyricFarBlurSigma(9), AppLyrics.farBlurSigma * 2);
    });

    testWidgets('a far line is blurred when the listener asked for it', (
      tester,
    ) async {
      lyricsFarBlurNotifier.value = true;
      addTearDown(() => lyricsFarBlurNotifier.value = false);

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              child: LyricLineWidget(
                index: 5,
                line: line(1000, 'a line far from the one being sung', [
                  token(1000, 'a line far from the one being sung', 2000),
                ]),
                currentIndexNotifier: ValueNotifier<int>(0),
                expanded: true,
                isKaraoke: false,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ImageFiltered), findsOneWidget);
      expect(
        tester.getSize(find.byType(LyricLineWidget)).height,
        greaterThan(0),
      );
    });
  });
}
