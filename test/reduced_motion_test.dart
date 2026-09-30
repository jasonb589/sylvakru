import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/design/marquee_text.dart';
import 'package:sylvakru/base/design/app_tokens.dart';

/// The platform's "less motion" is a request, and the client answers it: what
/// carries information keeps moving, what is only decoration stands still.
///
/// A title that will not fit is the clearest case: travelling text in a bar is
/// decoration, and the full name is always one click away on the playback
/// screen.
void main() {
  Widget title({required bool reduced}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: const Scaffold(
        body: SizedBox(
          width: 120,
          child: MarqueeText(text: 'A song title far too long to fit in here'),
        ),
      ),
    ),
  );

  testWidgets('a title travels when the platform allows movement', (
    tester,
  ) async {
    await tester.pumpWidget(title(reduced: false));

    // The looping copy is built twice: a title that fits is one line, one that
    // travels is two, which is how the behaviour can be spotted from a test.
    expect(
      find.text('A song title far too long to fit in here'),
      findsNWidgets(2),
    );
  });

  testWidgets('and stands still as one ellipsised line when it does not', (
    tester,
  ) async {
    await tester.pumpWidget(title(reduced: true));

    // The framework's own ExcludeSemantics wrappers make that type useless as a
    // signal here, so the count of the line itself is what is asserted.
    final text = tester.widget<Text>(find.byType(Text).first);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(
      find.text('A song title far too long to fit in here'),
      findsOneWidget,
    );
  });

  testWidgets('the app setting wins over the platform, both ways', (
    tester,
  ) async {
    addTearDown(
      () => reducedMotionModeNotifier.value = ReducedMotionMode.system,
    );

    Widget app({required bool reduced}) => MaterialApp(
      // A new key each time, so the tree is rebuilt rather than reused while
      // the setting changes underneath it.
      key: ValueKey('$reduced-${reducedMotionModeNotifier.value.name}'),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: const Scaffold(
          body: SizedBox(
            width: 120,
            child: MarqueeText(
              text: 'A song title far too long to fit in here',
            ),
          ),
        ),
      ),
    );

    // Still, even where the platform would allow movement.
    reducedMotionModeNotifier.value = ReducedMotionMode.always;
    await tester.pumpWidget(app(reduced: false));
    expect(
      find.text('A song title far too long to fit in here'),
      findsOneWidget,
    );

    // Moving, even where the platform asks for less.
    reducedMotionModeNotifier.value = ReducedMotionMode.never;
    await tester.pumpWidget(app(reduced: true));
    await tester.pump();
    expect(
      find.text('A song title far too long to fit in here'),
      findsNWidgets(2),
    );

    // Back to following the platform.
    reducedMotionModeNotifier.value = ReducedMotionMode.system;
    await tester.pumpWidget(app(reduced: true));
    await tester.pump();
    expect(
      find.text('A song title far too long to fit in here'),
      findsOneWidget,
    );
  });
}
