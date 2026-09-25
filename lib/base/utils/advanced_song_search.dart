import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';

enum SongSearchField { title, artist, album, albumArtist, genre }

/// Reusable keyword and metadata-range filters for song lists.
class SongSearchCriteria {
  final Set<SongSearchField> fields;
  final String query;
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
    this.query = '',
    this.exactMatch = false,
    this.minYear,
    this.maxYear,
    this.minDurationSeconds,
    this.maxDurationSeconds,
    this.minBitrateKbps,
    this.maxBitrateKbps,
  }) : fields = Set.unmodifiable(fields);

  factory SongSearchCriteria.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'];
    final fields = <SongSearchField>{};
    if (rawFields is List) {
      for (final name in rawFields.whereType<String>()) {
        for (final field in SongSearchField.values) {
          if (field.name == name) {
            fields.add(field);
            break;
          }
        }
      }
    } else {
      fields.addAll(SongSearchCriteria().fields);
    }

    int? readInt(String key) {
      final value = json[key];
      return value is num ? value.toInt() : null;
    }

    final rawQuery = json['query'];
    final rawExactMatch = json['exactMatch'];

    return SongSearchCriteria(
      fields: fields,
      query: rawQuery is String ? rawQuery : '',
      exactMatch: rawExactMatch is bool ? rawExactMatch : false,
      minYear: readInt('minYear'),
      maxYear: readInt('maxYear'),
      minDurationSeconds: readInt('minDurationSeconds'),
      maxDurationSeconds: readInt('maxDurationSeconds'),
      minBitrateKbps: readInt('minBitrateKbps'),
      maxBitrateKbps: readInt('maxBitrateKbps'),
    );
  }

  Map<String, Object?> toJson() => {
    'query': query,
    'fields': fields.map((field) => field.name).toList(),
    'exactMatch': exactMatch,
    'minYear': minYear,
    'maxYear': maxYear,
    'minDurationSeconds': minDurationSeconds,
    'maxDurationSeconds': maxDurationSeconds,
    'minBitrateKbps': minBitrateKbps,
    'maxBitrateKbps': maxBitrateKbps,
  };

  bool get hasFilters =>
      minYear != null ||
      maxYear != null ||
      minDurationSeconds != null ||
      maxDurationSeconds != null ||
      minBitrateKbps != null ||
      maxBitrateKbps != null;

  bool get isDefault =>
      query.trim().isEmpty &&
      !exactMatch &&
      !hasFilters &&
      fields.length == SongSearchField.values.length &&
      fields.containsAll(SongSearchField.values);

  bool matches(MyAudioMetadata song, [String? queryOverride]) {
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

    final normalizedQuery = (queryOverride ?? query).trim().toLowerCase();
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

class SmartPlaylistDefinition {
  final String name;
  final SongSearchCriteria criteria;
  final int sortType;

  const SmartPlaylistDefinition({
    required this.name,
    required this.criteria,
    this.sortType = 1,
  });

  factory SmartPlaylistDefinition.fromJson(Map<String, dynamic> json) {
    final rawName = json['name'];
    final rawCriteria = json['criteria'];
    final rawSortType = json['sortType'];
    return SmartPlaylistDefinition(
      name: rawName is String ? rawName : '',
      criteria: rawCriteria is Map
          ? SongSearchCriteria.fromJson(Map<String, dynamic>.from(rawCriteria))
          : SongSearchCriteria(),
      sortType: rawSortType is num ? rawSortType.toInt() : 1,
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'criteria': criteria.toJson(),
    'sortType': sortType,
  };

  List<MyAudioMetadata> apply(List<MyAudioMetadata> songs) {
    final result = filterSongListAdvanced(
      songs,
      query: criteria.query,
      criteria: criteria,
    );
    result.sort((a, b) {
      return switch (sortType) {
        1 => a.compareTitle.compareTo(b.compareTitle),
        2 => b.compareTitle.compareTo(a.compareTitle),
        3 => a.compareArtist.compareTo(b.compareArtist),
        4 => b.compareArtist.compareTo(a.compareArtist),
        5 => a.compareAlbum.compareTo(b.compareAlbum),
        6 => b.compareAlbum.compareTo(a.compareAlbum),
        _ => 0,
      };
    });
    return result;
  }
}
