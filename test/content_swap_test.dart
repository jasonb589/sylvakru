import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/design/app_tokens.dart';
import 'package:sylvakru/base/design/content_swap.dart';

/// Two things matter about a swap, and both are about the wait, which is the
/// part the listener actually sees: the content is already there while the
/// skeleton leaves, and leaving takes a fade rather than a frame.
void main() {
  Widget swap({required bool loading}) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 200,
        child: ContentSwap(
          loading: loading,
          placeholder: const Text('skeleton'),
          child: const Text('content'),
        ),
      ),
    ),
  );

  testWidgets('the content waits underneath while the skeleton leaves', (
    tester,
  ) async {
    await tester.pumpWidget(swap(loading: true));
    expect(find.text('skeleton'), findsOneWidget);
    // Built either way: this is what lets a scroll view keep its position, and
    // what a plain cross-fade cannot do.
    expect(find.text('content'), findsOneWidget);

    await tester.pumpWidget(swap(loading: false));
    await tester.pump(const Duration(milliseconds: 100));
    // Mid-fade both are on screen; that is the fade.
    expect(find.text('skeleton'), findsOneWidget);
    expect(find.text('content'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('skeleton'), findsNothing);
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('a plain fade takes the same step', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ContentFade(
            loading: true,
            placeholder: Text('skeleton'),
            child: Text('content'),
          ),
        ),
      ),
    );

    // Nothing to keep here: while the wait lasts, only the placeholder is up.
    expect(find.text('skeleton'), findsOneWidget);
    expect(find.text('content'), findsNothing);

    // The step comes from the tokens, so every swap of this kind runs at the
    // same speed as every other state change in the client.
    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, AppDuration.normal);
    expect(switcher.switchInCurve, AppCurve.enter);
    expect(switcher.switchOutCurve, AppCurve.exit);
  });
}
