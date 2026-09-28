import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/logger.dart';

/// Tags to write onto a finished download.
///
/// Only values the library actually has: the writer leaves a null tag alone
/// rather than clearing it, and a display fallback like "Unknown Artist" would
/// overwrite a real tag the file already carries. A blank string counts as
/// nothing to say as well — a present-but-empty tag is worse than a missing one
/// in most players.
Map<String, Object> downloadTagsFor(MyAudioMetadata song) {
  final tags = <String, Object>{};

  void put(String key, Object? value) {
    if (value == null) {
      return;
    }
    if (value is String && value.trim().isEmpty) {
      return;
    }
    tags[key] = value;
  }

  put('title', song.title);
  put('artist', song.artist);
  put('album', song.album);
  put('albumArtist', song.albumArtist);
  put('genre', song.genre);
  put('lyrics', song.lyrics);
  put('year', song.year);
  put('track', song.track);
  put('disc', song.disc);

  return tags;
}

/// Signature of the tag writer, so a test can stand in for the real one.
typedef DownloadTagWriter =
    bool Function(String path, Map<String, Object> tags);

/// Writes [tags] onto [path]. Replaced only by tests: the real implementation
/// needs a valid audio file behind the path.
DownloadTagWriter downloadTagWriter = writeTagsWithLofty;

/// The real thing, kept out of the way so the seam above stays readable.
bool writeTagsWithLofty(String path, Map<String, Object> tags) {
  try {
    return writeMetadata(
      path: path,
      title: tags['title'] as String?,
      artist: tags['artist'] as String?,
      album: tags['album'] as String?,
      albumArtist: tags['albumArtist'] as String?,
      genre: tags['genre'] as String?,
      lyrics: tags['lyrics'] as String?,
      year: tags['year'] as int?,
      track: tags['track'] as int?,
      disc: tags['disc'] as int?,
    );
  } catch (error) {
    // Tagging is a bonus: a file that cannot be tagged is still a download.
    logger.output('Failed to tag $path: $error');
    return false;
  }
}

/// Tags a file the listener asked to download.
///
/// Playback cache never comes through here: it is temporary by definition, and
/// a rewritten file is no longer the one the server sent.
void tagDownloadedFile(MyAudioMetadata song, String path) {
  final tags = downloadTagsFor(song);
  if (tags.isEmpty) {
    return;
  }
  downloadTagWriter(path, tags);
}
