import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart' as app;
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/widgets/lyric_list_view.dart';

/// Playback speed and the lyric offset are both "set once, remembered" values.
/// What matters is that the picker can only offer speeds the player can run,
/// and that both are written to setting.json, which is what the next launch
/// reads back. `Setting.load` may only run once per process, so the file is
/// inspected directly instead of loading twice.
void main() {
  test('clamping keeps a speed inside what the picker can ask for', () {
    expect(clampPlaybackRate(1.25), 1.25);
    expect(clampPlaybackRate(1.0), 1.0);
    expect(clampPlaybackRate(0.1), playbackRateOptions.first);
    expect(clampPlaybackRate(9), playbackRateOptions.last);
  });

  test('the speed picker offers every speed it can ask the player for', () {
    expect(playbackRateOptions, contains(1.0));
    expect(
      playbackRateOptions,
      orderedEquals([...playbackRateOptions]..sort()),
      reason: 'the menu is rendered in list order',
    );
    expect(playbackRateOptions.first, lessThan(1.0));
    expect(playbackRateOptions.last, greaterThan(1.0));
  });

  test('speed and lyric offset are written to the settings file', () async {
    app.appSupportDir = await Directory.systemTemp.createTemp(
      'sylvakru_settings',
    );

    await setting.load();
    playbackRateNotifier.value = 1.5;
    lyricsTimeOffsetNotifier.value = -300;
    setting.save();

    final saved =
        jsonDecode(await File(setting.file.path).readAsString())
            as Map<String, dynamic>;

    expect(saved['playbackRate'], 1.5);
    expect(saved['lyricsTimeOffsetMs'], -300);
  });
}
