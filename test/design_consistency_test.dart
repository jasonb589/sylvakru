import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Motion comes from the design tokens, and stays there.
///
/// Before the tokens existed the same decision was taken independently in every
/// file: four blurs, nine corner radii, and a backdrop that did not animate at
/// all. These two rules are what stops that from happening again - it always
/// starts with one hand-picked `Curves.easeOut` or one `Duration(milliseconds:
/// 470)` that looks right on its own screen.
void main() {
  final sources = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();

  // The file the names come from: it is the one place a curve is written down.
  const tokenFile = 'lib/base/design/app_tokens.dart';

  String pathOf(File file) => file.path.replaceAll('\\', '/');

  test('every animation curve comes from the design tokens', () {
    final offenders = <String>[];
    for (final file in sources) {
      final path = pathOf(file);
      if (path == tokenFile) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        if (lines[index].contains('Curves.')) {
          offenders.add('$path:${index + 1}: ${lines[index].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'use AppCurve.* instead:\n${offenders.join('\n')}',
    );
  });

  test('animation durations come from the design tokens', () {
    // Only a literal is a step that skipped the ladder. A duration worked out at
    // run time - the lyrics scroll from the distance to travel, the portrait
    // view from the height it was given - is not a decision taken away from the
    // tokens, so the scanner only looks for a number.
    //
    // Each file is read as one piece of text rather than line by line: a
    // literal that was wrapped across two lines was invisible to the scanner
    // that read one line at a time, which is exactly where the one byte that
    // got past it lived.
    final literal = RegExp(
      r'(duration|transitionDuration|reverseTransitionDuration)'
      r'\s*:\s*(const\s+)?Duration\(\s*milliseconds\s*:\s*\d',
      multiLine: true,
    );
    final offenders = <String>[];

    for (final file in sources) {
      final path = pathOf(file);
      if (path == tokenFile) {
        continue;
      }
      final text = file.readAsStringSync();
      for (final match in literal.allMatches(text)) {
        final line = text.substring(0, match.start).split('\n').length;
        offenders.add('$path:$line: ${match.group(0)}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'use AppDuration.* instead:\n${offenders.join('\n')}',
    );
  });
}
