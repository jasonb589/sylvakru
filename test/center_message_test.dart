import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/services/interaction.dart';

/// The centre message is one slot, and it used to be one slot by timing alone:
/// *any* message within two seconds of the previous one was dropped, whatever it
/// said. A different answer - "no duplicate songs" right after a sync - was
/// swallowed that way, and the listener saw nothing at all.
///
/// The spinner that goes with a slow step is checked here too: it owns an
/// overlay entry, and a step that threw used to leave it over everything with no
/// way back.
void main() {
  final start = DateTime(2026, 1, 1, 12);

  group('shouldShowCenterMessage', () {
    test('different words are not swallowed by the gap', () {
      expect(
        shouldShowCenterMessage(
          message: 'no duplicate songs',
          now: start.add(const Duration(milliseconds: 1500)),
          lastAt: start,
          lastMessage: 'sync finished',
        ),
        isTrue,
      );
    });

    test('the same words inside the gap are not worth repeating', () {
      expect(
        shouldShowCenterMessage(
          message: 'no duplicate songs',
          now: start.add(const Duration(milliseconds: 1500)),
          lastAt: start,
          lastMessage: 'no duplicate songs',
        ),
        isFalse,
      );
    });

    test('the same words after the gap can be shown again', () {
      expect(
        shouldShowCenterMessage(
          message: 'no duplicate songs',
          now: start.add(const Duration(seconds: 2)),
          lastAt: start,
          lastMessage: 'no duplicate songs',
        ),
        isTrue,
      );
    });

    test('the first message is always shown', () {
      expect(
        shouldShowCenterMessage(
          message: 'no duplicate songs',
          now: start,
          lastAt: null,
          lastMessage: null,
        ),
        isTrue,
      );
    });
  });

  group('withCenterLoading', () {
    test('the spinner comes down when the step throws', () async {
      var shown = 0;
      var hidden = 0;

      final result = await withCenterLoading<int>(
        () async => throw StateError('the step failed'),
        show: () => shown++,
        hide: () => hidden++,
      );

      expect(shown, 1);
      expect(hidden, 1, reason: 'a failure must not leave the spinner up');
      expect(result, isNull);
    });

    test('the spinner comes down and the answer comes back', () async {
      var hidden = 0;

      final result = await withCenterLoading(
        () async => 7,
        show: () {},
        hide: () => hidden++,
      );

      expect(result, 7);
      expect(hidden, 1);
    });
  });
}
