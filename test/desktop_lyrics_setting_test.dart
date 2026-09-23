import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/desktop_lyrics_setting.dart';

void main() {
  late Directory support;

  // appSupportDir is a late final, so it can only be assigned once per process
  setUpAll(() {
    support = Directory.systemTemp.createTempSync('sylvakru_desklyr');
    appSupportDir = support;
  });

  setUp(() {
    final file = File('${support.path}/desktop_lyrics.json');
    if (file.existsSync()) {
      file.deleteSync();
    }
    desktopLyricsSetting.loaded = false;
    desktopLyricsSetting.lockedNotifier.value = false;
    desktopLyricsSetting.positionNotifier.value = null;
  });

  test('defaults to unlocked and unpositioned', () async {
    await desktopLyricsSetting.load();

    expect(desktopLyricsSetting.lockedNotifier.value, isFalse);
    expect(desktopLyricsSetting.positionNotifier.value, isNull);
  });

  test('round-trips the locked flag and position', () async {
    await desktopLyricsSetting.load();
    desktopLyricsSetting.lockedNotifier.value = true;
    desktopLyricsSetting.positionNotifier.value = const Offset(120, 340);
    desktopLyricsSetting.save();

    // a fresh load, as a later launch of the lyrics window would do
    desktopLyricsSetting.loaded = false;
    desktopLyricsSetting.lockedNotifier.value = false;
    desktopLyricsSetting.positionNotifier.value = null;
    await desktopLyricsSetting.load();

    expect(desktopLyricsSetting.lockedNotifier.value, isTrue);
    expect(
      desktopLyricsSetting.positionNotifier.value,
      const Offset(120, 340),
    );
  });

  test('does not write before load, so defaults cannot clobber the file',
      () async {
    await desktopLyricsSetting.load();
    desktopLyricsSetting.positionNotifier.value = const Offset(5, 6);
    desktopLyricsSetting.save();

    // simulate a save arriving before load on a later launch
    desktopLyricsSetting.loaded = false;
    desktopLyricsSetting.positionNotifier.value = const Offset(99, 99);
    desktopLyricsSetting.save();

    desktopLyricsSetting.loaded = false;
    desktopLyricsSetting.positionNotifier.value = null;
    await desktopLyricsSetting.load();

    expect(desktopLyricsSetting.positionNotifier.value, const Offset(5, 6));
  });

  test('survives a corrupt file', () async {
    File(
      '${support.path}/desktop_lyrics.json',
    ).writeAsStringSync('{ this is not json');

    await desktopLyricsSetting.load();

    expect(desktopLyricsSetting.lockedNotifier.value, isFalse);
    expect(desktopLyricsSetting.positionNotifier.value, isNull);
    // and it must still be usable afterwards
    expect(desktopLyricsSetting.loaded, isTrue);
  });
}
