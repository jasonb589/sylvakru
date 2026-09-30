import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';

/// The About page, the update check and the Emby client all report
/// [versionNumber], so it has to be the version that was actually built - it
/// sat at 4.7.0 for a long stretch of releases because nothing compared it with
/// `pubspec.yaml`. This is that comparison.
void main() {
  test('versionNumber tracks the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml has no parseable version');
    expect(
      versionNumber,
      match!.group(1),
      reason: 'bump lib/base/app.dart together with pubspec.yaml',
    );
  });
}
