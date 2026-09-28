import 'package:sylvakru/base/my_audio_metadata.dart';

/// What downloading a song will actually get, as far as the source says.
///
/// Stream sources report the file they would send, so the bitrate and the exact
/// length are known before anything is transferred: enough to decide whether a
/// download is worth it, without asking the server to transcode anything.
///
/// Bitrate is kbps everywhere in the app (Navidrome reports kbps, 飞牛 is
/// converted on the way in), which is what makes this arithmetic honest.
int? estimateDownloadBytes(MyAudioMetadata song) {
  final bitrate = song.bitrate;
  final duration = song.duration;
  if (bitrate == null || bitrate <= 0) {
    return null;
  }
  if (duration == null || duration.inMilliseconds <= 0) {
    return null;
  }
  return (bitrate * 1000 * duration.inMilliseconds / 8000).round();
}

/// Size the way the rest of the app writes it: MB, and GB once it is big
/// enough that nobody wants to read four digits of megabytes.
String formatBytes(int bytes) {
  final mb = bytes / (1024 * 1024);
  if (mb >= 1024) {
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
  return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
}

/// "FLAC · 1411 kbps · ≈ 38.2 MB" for one song.
///
/// Null when the source said nothing about it: a line that reads "unknown" is
/// not worth the space in a menu.
String? describeDownloadQuality(MyAudioMetadata song) {
  final parts = <String>[];

  final format = song.format?.trim().toUpperCase();
  if (format != null && format.isNotEmpty) {
    parts.add(format);
  }

  final bitrate = song.bitrate;
  if (bitrate != null && bitrate > 0) {
    parts.add('$bitrate kbps');
  }

  final bytes = estimateDownloadBytes(song);
  if (bytes != null) {
    parts.add('≈ ${formatBytes(bytes)}');
  }

  return parts.isEmpty ? null : parts.join(' · ');
}

/// "FLAC × 12, MP3 × 3 · ≈ 620 MB" for an album, playlist or selection.
///
/// The size is only added when every song has one: half a total would be worse
/// than none, because it reads as the real figure.
String? describeBatchQuality(Iterable<MyAudioMetadata> songs) {
  final formats = <String, int>{};
  int? totalBytes = 0;
  var songsWithSize = 0;
  var count = 0;

  for (final song in songs) {
    count++;
    final format = song.format?.trim().toUpperCase();
    if (format != null && format.isNotEmpty) {
      formats[format] = (formats[format] ?? 0) + 1;
    }
    final bytes = estimateDownloadBytes(song);
    if (bytes == null) {
      totalBytes = null;
    } else {
      songsWithSize++;
      totalBytes = totalBytes == null ? null : totalBytes + bytes;
    }
  }

  if (count == 0) {
    return null;
  }

  final parts = <String>[
    for (final entry in formats.entries) '${entry.key} × ${entry.value}',
  ];
  if (totalBytes != null && songsWithSize == count) {
    parts.add('≈ ${formatBytes(totalBytes)}');
  }

  return parts.isEmpty ? null : parts.join(' · ');
}
