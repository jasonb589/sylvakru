import 'dart:convert';

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
    desktopLyricsSetting.positionNotifier.value = null;
  });

  test('defaults to an unpositioned text-only layout', () async {
    await desktopLyricsSetting.load();

    expect(desktopLyricsSetting.positionNotifier.value, isNull);
  });

  test('round-trips the position and current layout version', () async {
    await desktopLyricsSetting.load();
    desktopLyricsSetting.positionNotifier.value = const Offset(120, 340);
    desktopLyricsSetting.save();

    desktopLyricsSetting.loaded = false;
    desktopLyricsSetting.positionNotifier.value = null;
    await desktopLyricsSetting.load();

    expect(
      desktopLyricsSetting.positionNotifier.value,
      const Offset(120, 340),
    );
    final json = jsonDecode(
      File('${support.path}/desktop_lyrics.json').readAsStringSync(),
    ) as Map;
    expect(json['layout'], desktopLyricsLayoutVersion);
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

  test('resets old control-bar layout data', () async {
    File('${support.path}/desktop_lyrics.json').writeAsStringSync(
      '{"layout": 2, "locked": true, "dx": 120, "dy": 340}',
    );

    await desktopLyricsSetting.load();

    expect(desktopLyricsSetting.positionNotifier.value, isNull);
    final json = jsonDecode(
      File('${support.path}/desktop_lyrics.json').readAsStringSync(),
    ) as Map;
    expect(json['layout'], desktopLyricsLayoutVersion);
    expect(json.containsKey('locked'), isFalse);
  });

  test('survives a corrupt file', () async {
    File(
      '${support.path}/desktop_lyrics.json',
    ).writeAsStringSync('{ this is not json');

    await desktopLyricsSetting.load();

    expect(desktopLyricsSetting.positionNotifier.value, isNull);
    expect(desktopLyricsSetting.loaded, isTrue);
  });
}
