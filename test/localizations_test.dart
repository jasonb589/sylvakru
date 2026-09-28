import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/utils/localizations.dart';

/// Strings that come out of the data layer have no BuildContext to ask, so they
/// follow the language the listener picked instead. They used to be English
/// literals: a listener on Chinese still read "Playlist exists" when a name was
/// taken.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    localeNotifier.value = null;
  });

  test('follows the language the listener picked', () {
    localeNotifier.value = const Locale('zh');
    final zh = appLocalizations.playlistExists;
    expect(zh, '歌单已存在');

    localeNotifier.value = const Locale('en');
    expect(appLocalizations.playlistExists, isNot(zh));
    expect(appLocalizations.playlistExists, 'Playlist already exists');
  });

  test('a language the app does not ship reads as English', () {
    localeNotifier.value = const Locale('de');

    expect(
      appLocalizations.playlistBusy,
      'The playlist is updating; try again in a moment',
    );
  });

  test('every message a playlist failure shows is one of them', () {
    // The point of the round: no user-facing message left as an English literal
    // in the data layer.
    for (final path in [
      'lib/base/data/playlist.dart',
      'lib/base/services/interaction.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        RegExp(r"showCenterMessage\('[A-Za-z]").hasMatch(source),
        isFalse,
        reason: '$path still hands a loose English sentence to the listener',
      );
    }
  });
}
