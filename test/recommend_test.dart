import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/artist_album.dart';
import 'package:sylvakru/base/data/recommend.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';

MyAudioMetadata song(
  String id, {
  String? artist,
  String? genre,
  int? year,
  int playCount = 0,
  DateTime? lastPlayed,
}) {
  return MyAudioMetadata(
    AudioMetadata(
      title: id,
      artist: artist,
      genre: genre,
      year: year,
    ),
    id: id,
    path: '/music/$id.flac',
    playCount: playCount,
    lastPlayed: lastPlayed,
  );
}

void main() {
  setUpAll(() {
    appSupportDir = Directory.systemTemp.createTempSync('sylvakru_rec');
  });

  // building a song needs appSupportDir, so every list is built inside a test
  // rather than in the group body
  List<MyAudioMetadata> makeSongs([int count = 40]) =>
      List.generate(count, (i) => song('s$i', artist: 'A$i'));

  group('randomSongs', () {
    test('picks the requested number', () {
      final songs = makeSongs();
      expect(Recommender.randomSongs(songs: songs, limit: 10), hasLength(10));
      expect(Recommender.randomSongs(songs: songs), hasLength(40));
    });

    test('is stable for a given seed', () {
      final songs = makeSongs();
      final first = Recommender.randomSongs(songs: songs, seed: 7);
      final second = Recommender.randomSongs(songs: songs, seed: 7);
      expect(
        first.map((e) => e.song.id),
        orderedEquals(second.map((e) => e.song.id)),
      );
    });

    test('a different seed picks a different set', () {
      final songs = makeSongs();
      final first = Recommender.randomSongs(songs: songs, limit: 10, seed: 1);
      final second = Recommender.randomSongs(songs: songs, limit: 10, seed: 2);
      expect(
        first.map((e) => e.song.id),
        isNot(orderedEquals(second.map((e) => e.song.id))),
      );
    });

    test('does not depend on listening history', () {
      // the whole point of the change: play counts must not influence who comes
      // up, only the seed does
      final quiet = List.generate(30, (i) => song('q$i', artist: 'Quiet $i'));
      final loud = List.generate(
        30,
        (i) => song('l$i', artist: 'Loud $i', playCount: 500),
      );

      // same seed and same length -> the same positions are drawn from each pool
      final quietPicks = Recommender.randomSongs(
        songs: quiet,
        limit: 5,
        seed: 3,
      );
      final loudPicks = Recommender.randomSongs(songs: loud, limit: 5, seed: 3);

      expect(
        quietPicks.map((e) => e.song.id),
        orderedEquals(loudPicks.map((e) => e.song.id.replaceFirst('l', 'q'))),
      );
    });

    test('handles an empty library', () {
      expect(Recommender.randomSongs(songs: const []), isEmpty);
    });
  });

  group('randomArtists', () {
    List<Artist> makeArtists([int count = 30]) =>
        List.generate(count, (i) => Artist('Artist $i'));

    test('picks the requested number', () {
      expect(
        Recommender.randomArtists(artists: makeArtists(), limit: 8),
        hasLength(8),
      );
    });

    test('is stable for a given seed', () {
      final artists = makeArtists();
      final first = Recommender.randomArtists(artists: artists, seed: 5);
      final second = Recommender.randomArtists(artists: artists, seed: 5);
      expect(
        first.map((e) => e.artist.name),
        orderedEquals(second.map((e) => e.artist.name)),
      );
    });

    test('a different seed picks a different set', () {
      final artists = makeArtists();
      final first = Recommender.randomArtists(
        artists: artists,
        limit: 8,
        seed: 1,
      );
      final second = Recommender.randomArtists(
        artists: artists,
        limit: 8,
        seed: 2,
      );
      expect(
        first.map((e) => e.artist.name),
        isNot(orderedEquals(second.map((e) => e.artist.name))),
      );
    });

    test('reports how much of the artist is unheard', () {
      final artist = Artist('A');
      artist.songList.addAll([
        song('played', artist: 'A', playCount: 3),
        song('fresh', artist: 'A'),
      ]);

      final result = Recommender.randomArtists(artists: [artist]).single;
      expect(result.totalSongs, 2);
      expect(result.playedSongs, 1);
    });

    test('handles an empty artist list', () {
      expect(Recommender.randomArtists(artists: const []), isEmpty);
    });
  });

  group('randomAlbums', () {
    List<Album> makeAlbums([int count = 30]) =>
        List.generate(count, (i) => Album('Album $i'));

    test('picks the requested number', () {
      expect(
        Recommender.randomAlbums(albums: makeAlbums(), limit: 5),
        hasLength(5),
      );
      expect(Recommender.randomAlbums(albums: makeAlbums()), hasLength(20));
    });

    test('is stable for a given seed', () {
      final albums = makeAlbums();
      final first = Recommender.randomAlbums(albums: albums, seed: 3);
      final second = Recommender.randomAlbums(albums: albums, seed: 3);
      expect(
        first.map((e) => e.name),
        orderedEquals(second.map((e) => e.name)),
      );
    });

    test('a different seed picks a different set', () {
      final albums = makeAlbums();
      final first = Recommender.randomAlbums(albums: albums, seed: 1);
      final second = Recommender.randomAlbums(albums: albums, seed: 2);
      expect(
        first.map((e) => e.name),
        isNot(orderedEquals(second.map((e) => e.name))),
      );
    });

    test('does not just take the alphabetically first albums', () {
      // the bug being fixed: the row always showed albumList.take(n)
      final albums = makeAlbums();
      final picked = Recommender.randomAlbums(
        albums: albums,
        limit: 5,
        seed: 9,
      );
      expect(
        picked.map((e) => e.name),
        isNot(orderedEquals(albums.take(5).map((e) => e.name))),
      );
    });

    test('handles an empty album list', () {
      expect(Recommender.randomAlbums(albums: const []), isEmpty);
    });
  });
}
