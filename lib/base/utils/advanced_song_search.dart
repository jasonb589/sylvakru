import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';

enum SongSearchField { title, artist, album, albumArtist, genre }

/// Reusable keyword and metadata-range filters for song lists.
class SongSearchCriteria {
  final Set<SongSearchField> fields;
  final bool exactMatch;
  final int? minYear;
  final int? maxYear;
  final int? minDurationSeconds;
  final int? maxDurationSeconds;
  final int? minBitrateKbps;
  final int? maxBitrateKbps;

  SongSearchCriteria({
    Set<SongSearchField> fields = const {
      SongSearchField.title,
      SongSearchField.artist,
      SongSearchField.album,
      SongSearchField.albumArtist,
      SongSearchField.genre,
    },
    this.exactMatch = false,
    this.minYear,
    this.maxYear,
    this.minDurationSeconds,
    this.maxDurationSeconds,
    this.minBitrateKbps,
    this.maxBitrateKbps,
  }) : fields = Set.unmodifiable(fields);

  bool get hasFilters =>
      minYear != null ||
      maxYear != null ||
      minDurationSeconds != null ||
      maxDurationSeconds != null ||
      minBitrateKbps != null ||
      maxBitrateKbps != null;

  bool get isDefault =>
      !exactMatch &&
      !hasFilters &&
      fields.length == SongSearchField.values.length &&
      fields.containsAll(SongSearchField.values);


  bool matches(MyAudioMetadata song, String query) {
    if (!_matchesRange(song.year, minYear, maxYear)) {
      return false;
    }
    if (!_matchesRange(
      song.duration?.inSeconds,
      minDurationSeconds,
      maxDurationSeconds,
    )) {
      return false;
    }
    if (!_matchesRange(song.bitrate, minBitrateKbps, maxBitrateKbps)) {
      return false;
    }

    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }
    if (fields.isEmpty) {
      return false;
    }

    return fields.any((field) {
      final value = switch (field) {
        SongSearchField.title => getTitle(song),
        SongSearchField.artist => getArtist(song),
        SongSearchField.album => getAlbum(song),
        SongSearchField.albumArtist => getAlbumArtist(song),
        SongSearchField.genre => getGenre(song),
      }.trim().toLowerCase();
      return exactMatch
          ? value == normalizedQuery
          : value.contains(normalizedQuery);
    });
  }

  bool _matchesRange(int? value, int? minimum, int? maximum) {
    if (minimum == null && maximum == null) {
      return true;
    }
    if (value == null) {
      return false;
    }
    return (minimum == null || value >= minimum) &&
        (maximum == null || value <= maximum);
  }
}

List<MyAudioMetadata> filterSongListAdvanced(
  List<MyAudioMetadata> songs, {
  required String query,
  required SongSearchCriteria criteria,
}) {
  return songs.where((song) => criteria.matches(song, query)).toList();
}
