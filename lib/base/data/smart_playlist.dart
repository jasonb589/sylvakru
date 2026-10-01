import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';

/// The metadata field a smart playlist's keyword is looked for in.
enum SmartPlaylistField { title, artist, album, albumArtist, genre }

/// The rules of a smart playlist: a keyword, the fields it is looked for in,
/// and optional metadata ranges.
///
/// These rules belong to the smart-playlist feature - they are what the
/// editor writes, what [SmartPlaylistDefinition] applies and what is saved as
/// JSON beside the playlists. The field [name]s are therefore part of the
/// on-disk format and must not be renamed.
class SmartPlaylistCriteria {
  final Set<SmartPlaylistField> fields;
  final String query;
  final bool exactMatch;
  final int? minYear;
  final int? maxYear;
  final int? minDurationSeconds;
  final int? maxDurationSeconds;
  final int? minBitrateKbps;
  final int? maxBitrateKbps;

  SmartPlaylistCriteria({
    Set<SmartPlaylistField> fields = const {
      SmartPlaylistField.title,
      SmartPlaylistField.artist,
      SmartPlaylistField.album,
      SmartPlaylistField.albumArtist,
      SmartPlaylistField.genre,
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

  factory SmartPlaylistCriteria.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'];
    final fields = <SmartPlaylistField>{};
    if (rawFields is List) {
      for (final name in rawFields.whereType<String>()) {
        for (final field in SmartPlaylistField.values) {
          if (field.name == name) {
            fields.add(field);
            break;
          }
        }
      }
    } else {
      fields.addAll(SmartPlaylistCriteria().fields);
    }

    int? readInt(String key) {
      final value = json[key];
      return value is num ? value.toInt() : null;
    }

    final rawQuery = json['query'];
    final rawExactMatch = json['exactMatch'];

    return SmartPlaylistCriteria(
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

  /// Whether [song] sits inside every range these rules ask for and carries
  /// the keyword in one of the selected fields.
  ///
  /// An empty keyword matches everything: that is what makes a smart playlist
  /// with only a range in it the whole library narrowed by that range.
  bool matches(MyAudioMetadata song) {
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
        SmartPlaylistField.title => getTitle(song),
        SmartPlaylistField.artist => getArtist(song),
        SmartPlaylistField.album => getAlbum(song),
        SmartPlaylistField.albumArtist => getAlbumArtist(song),
        SmartPlaylistField.genre => getGenre(song),
      }.trim().toLowerCase();
      return exactMatch
          ? value == normalizedQuery
          : value.contains(normalizedQuery);
    });
  }

  /// The songs of [songs] these rules select, in their original order.
  List<MyAudioMetadata> applyToList(List<MyAudioMetadata> songs) {
    return songs.where(matches).toList();
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

/// A saved smart playlist: the rules, plus how its results are ordered.
class SmartPlaylistDefinition {
  final String name;
  final SmartPlaylistCriteria criteria;
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
          ? SmartPlaylistCriteria.fromJson(
              Map<String, dynamic>.from(rawCriteria),
            )
          : SmartPlaylistCriteria(),
      sortType: rawSortType is num ? rawSortType.toInt() : 1,
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'criteria': criteria.toJson(),
    'sortType': sortType,
  };

  List<MyAudioMetadata> apply(List<MyAudioMetadata> songs) {
    final result = criteria.applyToList(songs);
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
