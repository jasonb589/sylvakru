import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
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

  group('splitGenres', () {
    test('splits the separators taggers actually write', () {
      expect(splitGenres('Rock/Pop'), ['Rock', 'Pop']);
      expect(splitGenres('Rock; Pop'), ['Rock', 'Pop']);
      expect(splitGenres('Rock, Pop'), ['Rock', 'Pop']);
      expect(splitGenres('  Rock  '), ['Rock']);
      expect(splitGenres(''), isEmpty);
    });
  });

  group('buildTaste', () {
    test('ignores songs that were never played and never favourited', () {
      final taste = Recommender.buildTaste([
        song('a', artist: 'X', genre: 'Rock', playCount: 0),
      ]);
      expect(taste.isEmpty, isTrue);
    });

    test('weights artists and genres by play count', () {
      final taste = Recommender.buildTaste([
        song('a', artist: 'A', genre: 'Rock', playCount: 10),
        song('b', artist: 'B', genre: 'Jazz', playCount: 1),
      ]);

      expect(taste.artistAffinity('A'), 1.0);
      expect(taste.artistAffinity('B'), lessThan(1.0));
      expect(taste.artistAffinity('Nobody'), 0);
      expect(taste.genreAffinity('Rock'), 1.0);
      expect(taste.genreAffinity('Jazz'), lessThan(1.0));
    });

    test('a favourite outranks a plain play count', () {
      final taste = Recommender.buildTaste(
        [
          song('plain', artist: 'A', genre: 'Rock', playCount: 5),
          song('star', artist: 'B', genre: 'Jazz', playCount: 1),
        ],
        favoriteIds: {'star'},
      );
      expect(taste.artistAffinity('B'), greaterThan(taste.artistAffinity('A')));
    });

    test('splits a multi-genre tag so every part counts', () {
      final taste = Recommender.buildTaste([
        song('a', artist: 'A', genre: 'Rock/Pop', playCount: 3),
      ]);
      expect(taste.genreAffinity('Rock'), greaterThan(0));
      expect(taste.genreAffinity('Pop'), greaterThan(0));
    });

    test('nearby years count partially, distant ones do not', () {
      final taste = Recommender.buildTaste([
        song('a', artist: 'A', year: 2005, playCount: 5),
      ]);
      expect(taste.yearAffinity(2005), greaterThan(taste.yearAffinity(2007)));
      expect(taste.yearAffinity(2007), greaterThan(0));
      expect(taste.yearAffinity(1990), 0);
    });
  });

  group('recommendSongs', () {
    final now = DateTime(2026, 9, 20);

    test('returns nothing before any listening history exists', () {
      final songs = [song('a', artist: 'A', genre: 'Rock')];
      final result = Recommender.recommendSongs(
        songs: songs,
        taste: Recommender.buildTaste(songs),
      );
      expect(result, isEmpty);
    });

    test('prefers more of what the listener already plays', () {
      final liked = song(
        'liked',
        artist: 'A',
        genre: 'Rock',
        playCount: 20,
        lastPlayed: now,
      );
      final sameArtist = song('sameArtist', artist: 'A', genre: 'Rock');
      final unrelated = song('unrelated', artist: 'Z', genre: 'Polka');

      final taste = Recommender.buildTaste([liked]);
      final result = Recommender.recommendSongs(
        songs: [unrelated, sameArtist],
        taste: taste,
        now: now,
      );

      expect(result, isNotEmpty);
      expect(result.first.song.id, 'sameArtist');
      expect(result.first.reason, RecommendReason.favoriteArtist);
    });

    test('never suggests something just played', () {
      final liked = song(
        'liked',
        artist: 'A',
        genre: 'Rock',
        playCount: 20,
        lastPlayed: now,
      );
      final taste = Recommender.buildTaste([liked]);

      final result = Recommender.recommendSongs(
        songs: [liked, song('other', artist: 'A', genre: 'Rock')],
        taste: taste,
        playedRecently: {'liked'},
        now: now,
      );

      expect(result.map((e) => e.song.id), isNot(contains('liked')));
    });

    test('keeps a song that was played long ago as a rediscovery', () {
      final old = song(
        'old',
        artist: 'A',
        genre: 'Rock',
        playCount: 8,
        lastPlayed: now.subtract(const Duration(days: 200)),
      );
      final taste = Recommender.buildTaste([old]);

      final result = Recommender.recommendSongs(
        songs: [old],
        taste: taste,
        now: now,
      );

      expect(result, hasLength(1));
      expect(result.first.reason, RecommendReason.rediscover);
    });

    test('respects the limit', () {
      final liked = song('liked', artist: 'A', genre: 'Rock', playCount: 9);
      final candidates = List.generate(
        80,
        (i) => song('s$i', artist: 'A', genre: 'Rock'),
      );
      final result = Recommender.recommendSongs(
        songs: candidates,
        taste: Recommender.buildTaste([liked]),
        limit: 10,
      );
      expect(result, hasLength(10));
    });

    test('is stable for a given seed', () {
      final liked = song('liked', artist: 'A', genre: 'Rock', playCount: 9);
      final candidates = List.generate(
        30,
        (i) => song('s$i', artist: 'A', genre: 'Rock'),
      );
      final taste = Recommender.buildTaste([liked]);
      final first = Recommender.recommendSongs(
        songs: candidates,
        taste: taste,
        seed: 7,
      );
      final second = Recommender.recommendSongs(
        songs: candidates,
        taste: taste,
        seed: 7,
      );
      expect(
        first.map((e) => e.song.id),
        orderedEquals(second.map((e) => e.song.id)),
      );
    });
  });
}
