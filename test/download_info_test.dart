import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/utils/download_info.dart';

/// Before downloading, the app should say what the download is: the format and
/// bitrate the source reports, and the size those imply. The arithmetic has to
/// stay honest — a wrong estimate is worse than no estimate, so anything the
/// source does not report is left out rather than guessed.
void main() {
  // Building a song touches the app's support folder (cover and cache paths),
  // so the tests point it at a temporary directory first.
  setUpAll(() {
    appSupportDir = Directory.systemTemp.createTempSync('sylvakru_info');
  });

  MyAudioMetadata song({
    String id = 'song',
    String? format,
    int? bitrate,
    Duration? duration,
  }) {
    return MyAudioMetadata(
      AudioMetadata(
        title: id,
        format: format,
        bitrate: bitrate,
        duration: duration,
      ),
      id: id,
    );
  }

  test('the estimate comes from the bitrate and the length', () {
    final item = song(
      format: 'flac',
      bitrate: 1411,
      duration: const Duration(seconds: 200),
    );

    // 1411 kbps for 200 s is about 33.6 MB of audio.
    final bytes = estimateDownloadBytes(item)!;
    expect(bytes / (1024 * 1024), closeTo(33.6, 0.5));
  });

  test('half a fact is not an estimate', () {
    expect(estimateDownloadBytes(song(bitrate: 320)), isNull);
    expect(
      estimateDownloadBytes(song(duration: const Duration(seconds: 60))),
      isNull,
    );
    expect(
      estimateDownloadBytes(
        song(bitrate: 0, duration: const Duration(seconds: 60)),
      ),
      isNull,
    );
  });

  test('one song reads as format, bitrate and size', () {
    final line = describeDownloadQuality(
      song(
        format: 'flac',
        bitrate: 1411,
        duration: const Duration(seconds: 200),
      ),
    );

    expect(line, startsWith('FLAC · 1411 kbps · ≈ '));
    expect(line, endsWith('MB'));
  });

  test('a song the source knows nothing about gets no line at all', () {
    expect(describeDownloadQuality(song()), isNull);
  });

  test('a batch counts formats and adds the sizes up', () {
    final line = describeBatchQuality([
      song(
        id: 'a',
        format: 'flac',
        bitrate: 1411,
        duration: const Duration(seconds: 200),
      ),
      song(
        id: 'b',
        format: 'flac',
        bitrate: 1411,
        duration: const Duration(seconds: 100),
      ),
      song(
        id: 'c',
        format: 'mp3',
        bitrate: 320,
        duration: const Duration(seconds: 100),
      ),
    ]);

    expect(line, contains('FLAC × 2'));
    expect(line, contains('MP3 × 1'));
    expect(line, contains('≈ '));
  });

  test('a batch with an unknown size shows the formats and no total', () {
    final line = describeBatchQuality([
      song(
        id: 'a',
        format: 'flac',
        bitrate: 1411,
        duration: const Duration(seconds: 200),
      ),
      song(id: 'b', format: 'mp3'),
    ]);

    expect(line, contains('FLAC × 1'));
    expect(line, contains('MP3 × 1'));
    expect(line, isNot(contains('≈')));
  });

  test('sizes switch to GB when megabytes stop being readable', () {
    expect(formatBytes(38 * 1024 * 1024), '38.0 MB');
    expect(formatBytes(2 * 1024 * 1024 * 1024), '2.00 GB');
  });
}
