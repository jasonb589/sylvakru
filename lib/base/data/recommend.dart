import 'dart:math' as math;

import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';

/// A song picked for the "For You" list.
class SongRecommendation {
  final MyAudioMetadata song;

  const SongRecommendation(this.song);
}

/// An artist picked for the "For You" list.
class ArtistRecommendation {
  final Artist artist;

  /// How many of this artist's songs the listener has already played.
  final int playedSongs;

  /// How many songs of this artist are known.
  final int totalSongs;

  const ArtistRecommendation(
    this.artist, {
    this.playedSongs = 0,
    this.totalSongs = 0,
  });
}

/// Builds the "For You" lists as a straight random draw.
///
/// This deliberately does not model the listener's taste. It used to score every
/// candidate by play count, favourites, genre and era, but the listener asked
/// for a plain random pick instead, so all the scoring was removed: every song
/// and every artist now has the same chance, and the seed only decides the
/// order. The seed starts from the clock and "refresh" bumps it, which is what
/// makes each launch and each refresh show a different set.
class Recommender {
  static const int songLimit = 50;
  static const int artistLimit = 24;
  static const int albumLimit = 20;

  /// Picks up to [limit] songs at random.
  ///
  /// Picks up to [limit] songs at random.
  static List<SongRecommendation> randomSongs({
    required List<MyAudioMetadata> songs,
    int limit = songLimit,
    int seed = 0,
  }) {
    final pool = List<MyAudioMetadata>.from(songs);
    pool.shuffle(math.Random(seed));
    return pool.take(limit).map(SongRecommendation.new).toList();
  }

  /// Picks up to [limit] artists at random.
  ///
  /// The played/total counts are still reported so a card can say how much of
  /// the artist is unheard, but they only describe the library — they no longer
  /// influence who gets picked.
  static List<ArtistRecommendation> randomArtists({
    required List<Artist> artists,
    int limit = artistLimit,
    int seed = 0,
  }) {
    final pool = List<Artist>.from(artists);
    pool.shuffle(math.Random(seed));
    return pool.take(limit).map((artist) {
      return ArtistRecommendation(
        artist,
        playedSongs: artist.songList.where((song) => song.playCount > 0).length,
        totalSongs: artist.songList.isNotEmpty
            ? artist.songList.length
            : artist.albumCount,
      );
    }).toList();
  }

  /// Picks up to [limit] albums at random.
  ///
  /// Same plain random draw as [randomSongs] and [randomArtists]: the home page
  /// used to list the alphabetically first albums, so it always opened on the
  /// same handful ("'The Story of Light'", "0-1", "10年朋友4", ...).
  static List<Album> randomAlbums({
    required List<Album> albums,
    int limit = albumLimit,
    int seed = 0,
  }) {
    final pool = List<Album>.from(albums);
    pool.shuffle(math.Random(seed));
    return pool.take(limit).toList();
  }
}
