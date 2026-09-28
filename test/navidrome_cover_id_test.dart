import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';

/// Navidrome reports the artwork per song, and the client has to pass that id
/// on untouched: asking by the song id instead made the server answer with its
/// placeholder for every track whose art lives in the album's folder rather
/// than inside the file.
void main() {
  test('the song cover art id is used as-is', () {
    expect(subsonicCoverId({'coverArt': 'al-1234'}), 'al-1234');
    expect(subsonicCoverId({'coverArt': 'mf-abc'}), 'mf-abc');
  });

  test('a missing cover art id falls back to the album', () {
    expect(subsonicCoverId({'parent': '1234'}), 'al-1234');
    expect(subsonicCoverId({'coverArt': '', 'parent': '1234'}), 'al-1234');
  });

  test('nothing to ask for stays null', () {
    expect(subsonicCoverId({}), isNull);
    expect(subsonicCoverId({'coverArt': '', 'parent': ''}), isNull);
    expect(subsonicCoverId({'coverArt': 7, 'parent': 7}), isNull);
  });
}
