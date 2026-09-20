import 'dart:math' as math;

import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';

/// Why something was recommended, so the UI can caption it honestly.
enum RecommendReason {
  /// By an artist the listener plays a lot.
  favoriteArtist,

  /// Matches a genre the listener plays a lot.
  similarGenre,

  /// Played often before, but not for a while.
  rediscover,

  /// Outside the usual taste, to keep the list from going stale.
  explore,
}

class SongRecommendation {
  final MyAudioMetadata song;
  final RecommendReason reason;

  /// The artist or genre this is based on, for the caption.
  final String? basis;

  const SongRecommendation(this.song, this.reason, [this.basis]);
}

class ArtistRecommendation {
  final Artist artist;
  final RecommendReason reason;

  /// The genre this is based on, for the caption.
  final String? basis;

  /// How many of this artist's songs the listener has already played.
  final int playedSongs;

  /// How many songs of this artist are known.
  final int totalSongs;

  const ArtistRecommendation(
    this.artist,
    this.reason, {
    this.basis,
    this.playedSongs = 0,
    this.totalSongs = 0,
  });
}

/// A snapshot of what the listener seems to like.
///
/// Built purely from the local library, so it works for every source type
/// (local, WebDAV, Navidrome, Emby, FnOS) without asking any server.
class Taste {
  /// artist name -> weight
  final Map<String, double> artists = {};

  /// genre -> weight
  final Map<String, double> genres = {};

  /// release year -> weight, used for era affinity
  final Map<int, double> years = {};

  /// artist name -> when it was last played
  final Map<String, DateTime> artistLastPlayed = {};

  /// artist name -> number of distinct songs already played
  final Map<String, int> artistPlayedSongs = {};

  bool get isEmpty => artists.isEmpty && genres.isEmpty;

  double get _artistMax => artists.values.fold(0, math.max);
  double get _genreMax => genres.values.fold(0, math.max);

  /// Normalised 0..1 affinity for an artist.
  double artistAffinity(String? name) {
    if (name == null || _artistMax <= 0) {
      return 0;
    }
    return (artists[name] ?? 0) / _artistMax;
  }

  /// Normalised 0..1 affinity for a genre tag.
  ///
  /// A tag may hold several genres ("Rock/Pop"), so every part counts.
  double genreAffinity(String? genre) {
    if (genre == null || _genreMax <= 0) {
      return 0;
    }
    double best = 0;
    for (final part in splitGenres(genre)) {
      final value = (genres[part] ?? 0) / _genreMax;
      if (value > best) {
        best = value;
      }
    }
    return best;
  }

  /// The strongest genre for a tag, used as the caption basis.
  String? topGenreOf(String? genre) {
    if (genre == null) {
      return null;
    }
    String? best;
    double bestValue = 0;
    for (final part in splitGenres(genre)) {
      final value = genres[part] ?? 0;
      if (value > bestValue) {
        bestValue = value;
        best = part;
      }
    }
    return best;
  }

  /// The single most-played genre overall.
  String? get dominantGenre {
    if (genres.isEmpty) {
      return null;
    }
    return genres.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  /// Normalised 0..1 affinity for the era a year belongs to.
  ///
  /// Nearby years count partially, so liking 2005 also favours 2003 and 2007.
  double yearAffinity(int? year) {
    if (year == null || years.isEmpty) {
      return 0;
    }
    double best = 0;
    for (final entry in years.entries) {
      final distance = (entry.key - year).abs();
      if (distance > 8) {
        continue;
      }
      // linear falloff over the 8 year window
      final proximity = 1 - distance / 8;
      final value = entry.value * proximity;
      if (value > best) {
        best = value;
      }
    }
    return best / _artistMax.clamp(1, double.infinity);
  }
}

/// Splits a genre tag into its parts ("Rock/Pop" -> ["Rock", "Pop"]).
List<String> splitGenres(String genre) {
  return genre
      .split(RegExp(r'[/;,]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

/// Builds "for you" recommendations from the local library.
///
/// Everything is derived from play counts, last-played times, favourites and
/// tags the app already holds, so no network call and no extra state is needed.
class Recommender {
  static const int songLimit = 50;
  static const int artistLimit = 24;

  /// How long a song has to be untouched to count as "rediscover".
  static const Duration rediscoverAfter = Duration(days: 30);

  /// Builds the taste profile from the songs the listener has played.
  ///
  /// Favourites weigh more than play counts, because an explicit star is a
  /// much stronger statement of intent than a background listen.
  static Taste buildTaste(
    List<MyAudioMetadata> songs, {
    Set<String> favoriteIds = const {},
  }) {
    final taste = Taste();

    for (final song in songs) {
      final favorite = favoriteIds.contains(song.id);
      if (song.playCount <= 0 && !favorite) {
        continue;
      }

      // logarithmic, so a song played 200 times does not drown out everything
      var weight = song.playCount > 0
          ? 1 + math.log(song.playCount.toDouble())
          : 0.0;
      if (favorite) {
        weight += 2.5;
      }
      if (weight <= 0) {
        continue;
      }

      for (final artist in getArtists(getArtist(song))) {
        taste.artists[artist] = (taste.artists[artist] ?? 0) + weight;
        taste.artistPlayedSongs[artist] =
            (taste.artistPlayedSongs[artist] ?? 0) + 1;
        final played = song.lastPlayed;
        if (played != null) {
          final previous = taste.artistLastPlayed[artist];
          if (previous == null || played.isAfter(previous)) {
            taste.artistLastPlayed[artist] = played;
          }
        }
      }

      final genre = song.genre;
      if (genre != null) {
        for (final part in splitGenres(genre)) {
          taste.genres[part] = (taste.genres[part] ?? 0) + weight;
        }
      }

      final year = song.year;
      if (year != null) {
        taste.years[year] = (taste.years[year] ?? 0) + weight;
      }
    }

    return taste;
  }

  /// Songs the listener has not heard recently, ranked by how well they match.
  ///
  /// [playedRecently] ids are excluded so the list always feels new.
  static List<SongRecommendation> recommendSongs({
    required List<MyAudioMetadata> songs,
    required Taste taste,
    Set<String> playedRecently = const {},
    Set<String> favoriteIds = const {},
    DateTime? now,
    int limit = songLimit,
    int seed = 0,
  }) {
    if (taste.isEmpty) {
      return const [];
    }

    final reference = now ?? DateTime.now();
    final scored = <_ScoredSong>[];
    // Per-candidate jitter: keeps the strongest matches on top while letting the
    // seed reorder candidates whose scores are close. Sorting after a plain
    // shuffle would discard the shuffle, which is why a refresh used to return
    // the very same list.
    final random = math.Random(seed);


    for (final song in songs) {
      if (playedRecently.contains(song.id)) {
        continue;
      }

      final artistAffinity = taste.artistAffinity(song.artist);
      final genreAffinity = taste.genreAffinity(song.genre);
      final yearAffinity = taste.yearAffinity(song.year);
      final favorite = favoriteIds.contains(song.id);

      final lastPlayed = song.lastPlayed;
      final untouched = lastPlayed == null
          ? 1.0
          : (reference.difference(lastPlayed).inDays /
                    rediscoverAfter.inDays)
                .clamp(0.0, 1.0);

      // affinity is what makes it a recommendation; untouched and a low play
      // count keep it from being the same songs over and over
      var score =
          artistAffinity * 3.0 +
          genreAffinity * 2.0 +
          yearAffinity * 0.8 +
          untouched * 1.2;
      score -= math.log(song.playCount + 1) * 0.6;
      if (favorite) {
        score -= 1.5;
      }
      if (score <= 0) {
        continue;
      }

      // Order matters: a long-untouched song is described as a rediscovery even
      // when its artist is a favourite, otherwise artistAffinity (which is
      // relative and therefore always 1.0 when there is only one artist) would
      // label everything "favourite artist" and the rediscovery bucket would
      // never be reachable.
      final RecommendReason reason;
      String? basis;
      if (song.playCount >= 3 && untouched >= 1) {
        reason = RecommendReason.rediscover;
        basis = song.artist;
      } else if (artistAffinity >= 0.6) {
        reason = RecommendReason.favoriteArtist;
        basis = song.artist;
      } else if (genreAffinity >= 0.5) {
        reason = RecommendReason.similarGenre;
        basis = taste.topGenreOf(song.genre);
      } else {
        reason = RecommendReason.explore;
        basis = taste.dominantGenre;
      }

      scored.add(_ScoredSong(song, score, reason, basis, random.nextDouble()));
    }

    // Rank by score, using the seed's jitter to break near-ties, so a new seed
    // reshuffles the close calls instead of returning an identical list.
    scored.sort(
      (a, b) => (b.score + b.jitter).compareTo(a.score + a.jitter),
    );

    return scored
        .take(limit)
        .map((e) => SongRecommendation(e.song, e.reason, e.basis))
        .toList();
  }

  /// Artists worth opening: either a lot of unheard material, or not played
  /// for a long time.
  static List<ArtistRecommendation> recommendArtists({
    required List<Artist> artists,
    required Taste taste,
    DateTime? now,
    int limit = artistLimit,
    int seed = 0,
  }) {
    if (taste.isEmpty) {
      return const [];
    }

    final reference = now ?? DateTime.now();
    final result = <ArtistRecommendation>[];
    final random = math.Random(seed);

    // seed-derived offset per artist, applied when ranking
    final jitter = <String, double>{};

    for (final artist in artists) {
      final affinity = taste.artistAffinity(artist.name);
      if (affinity <= 0.05) {
        continue;
      }
      final total = artist.songList.isNotEmpty
          ? artist.songList.length
          : artist.albumCount;
      final played = taste.artistPlayedSongs[artist.name] ?? 0;
      final lastPlayed = taste.artistLastPlayed[artist.name];

      // genres come from the artist's own songs
      String? basis;
      double genreScore = 0;
      for (final song in artist.songList.take(30)) {
        final value = taste.genreAffinity(song.genre);
        if (value > genreScore) {
          genreScore = value;
          basis = taste.topGenreOf(song.genre);
        }
      }

      final RecommendReason reason;
      if (lastPlayed != null &&
          reference.difference(lastPlayed) > rediscoverAfter &&
          affinity >= 0.4) {
        reason = RecommendReason.rediscover;
      } else if (total > 0 && played < total * 0.5) {
        // plenty of this artist still unexplored
        reason = RecommendReason.favoriteArtist;
      } else {
        reason = RecommendReason.similarGenre;
      }

      result.add(
        ArtistRecommendation(
          artist,
          reason,
          basis: basis,
          playedSongs: played,
          totalSongs: total,
        ),
      );
      // seed-derived offset, so a refresh reshuffles artists whose scores are
      // close instead of returning the same row every time
      jitter[artist.name] = random.nextDouble();
    }

    result.sort((a, b) {
      final aScore = taste.artistAffinity(a.artist.name) * 3 +
          (a.reason == RecommendReason.rediscover ? 1.5 : 0) +
          (a.totalSongs - a.playedSongs) / math.max(a.totalSongs, 1) +
          (jitter[a.artist.name] ?? 0);
      final bScore = taste.artistAffinity(b.artist.name) * 3 +
          (b.reason == RecommendReason.rediscover ? 1.5 : 0) +
          (b.totalSongs - b.playedSongs) / math.max(b.totalSongs, 1) +
          (jitter[b.artist.name] ?? 0);
      return bScore.compareTo(aScore);
    });

    return result.take(limit).toList();
  }
}

class _ScoredSong {
  final MyAudioMetadata song;
  final double score;
  final RecommendReason reason;
  final String? basis;

  /// Seed-derived offset applied when ranking, so equally good songs trade
  /// places between refreshes.
  final double jitter;

  const _ScoredSong(
    this.song,
    this.score,
    this.reason,
    this.basis,
    this.jitter,
  );
}
