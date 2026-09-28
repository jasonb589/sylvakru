import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/utils/genre_names.dart';

/// Genres arrive in English from every server and from the tags in local
/// files, so the app carries a table for them. It has to leave anything it does
/// not know — including Chinese already — exactly as it came: a wrong guess on
/// a tag is worse than an untranslated one.
void main() {
  test('a known genre gets its Chinese name', () {
    expect(genreLabel('Contemporary Folk'), '当代民谣');
    expect(genreLabel('Rock'), '摇滚');
  });

  test('the lookup ignores case and surrounding space', () {
    expect(genreLabel('  k-pop '), '韩国流行');
    expect(genreLabel('HIP HOP'), '嘻哈');
  });

  test('an unknown or already Chinese genre is left alone', () {
    expect(genreLabel('Bubblegum Bass'), 'Bubblegum Bass');
    expect(genreLabel('民谣'), '民谣');
    expect(genreLabel(''), '');
  });

  test('one tag can hold several genres', () {
    expect(splitGenreTag('Rock/Pop'), ['Rock', 'Pop']);
    expect(splitGenreTag('Rock, Pop; Jazz'), ['Rock', 'Pop', 'Jazz']);
  });

  test('a list reads as one line, without repeats', () {
    expect(genreNamesLabel(['Rock/Pop', 'Pop', 'Jazz']), '摇滚 / 流行 / 爵士');
    expect(genreNamesLabel([]), '');
  });
}
