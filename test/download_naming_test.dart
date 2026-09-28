import 'dart:convert';
import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/utils/path.dart';

/// Downloads used to be named after the song id. A readable name has to stay
/// derivable from the song alone (nothing stores it), legal on Windows and
/// unique — otherwise two songs would fight over one file.
void main() {
  late Directory support;

  setUpAll(() async {
    support = Directory.systemTemp.createTempSync('sylvakru_naming');
    appSupportDir = support;
    await logger.init();
  });

  setUp(() async {
    sourceType = SourceType.navidrome;
    isStreamSource = true;
    isNotStreamSource = false;
    library.id2Song.clear();
    await setting.load();
    downloadNamingNotifier.value = DownloadNaming.hash;
    downloadRootDir = null;

    for (final path in [
      getCachesPath(sourceType),
      getDownloadsPath(sourceType),
    ]) {
      final directory = Directory(path);
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
  });

  MyAudioMetadata song({
    required String id,
    String title = 'Title',
    String artist = 'Artist',
    String album = 'Album',
    int? track,
  }) {
    final item =
        MyAudioMetadata(
            AudioMetadata(title: title),
            id: id,
            path: '/music/$id.flac',
          )
          ..artist = artist
          ..album = album;
    if (track != null) {
      item.track = track;
    }
    library.id2Song[id] = item;
    return item;
  }

  test('the default name is the hash old releases wrote', () {
    final item = song(id: 'abc');
    final digest = md5.convert(utf8.encode('abc')).toString();

    expect(
      item.computeDownloadPath(),
      p.join(getDownloadsPath(sourceType), digest),
    );
  });

  test('a readable name carries the format as its extension', () {
    final relative = downloadRelativePath(
      id: 'abc',
      naming: DownloadNaming.artistTitle,
      artist: 'Daft Punk',
      title: 'Something About Us',
      album: 'Discovery',
      format: 'FLAC',
    );

    expect(relative, startsWith('Daft Punk - Something About Us ('));
    expect(relative, endsWith('.flac'));
    expect(p.extension(relative), '.flac');
  });

  test(
    'nothing the file system refuses survives, and no name is left empty',
    () {
      final relative = downloadRelativePath(
        id: 'abc',
        naming: DownloadNaming.artistTitle,
        artist: 'AC/DC',
        title: 'Back: In   Black.',

        album: 'Album',
      );

      expect(relative, startsWith('AC_DC - Back_ In Black ('));
      expect(relative.contains('/'), isFalse);
      expect(relative.contains(':'), isFalse);
    },
  );

  test('two songs with the same artist and title get their own file', () {
    String name(String id) => downloadRelativePath(
      id: id,
      naming: DownloadNaming.artistTitle,
      artist: 'Twice',
      title: 'Candy',
      album: 'Album',
    );

    expect(name('one'), isNot(name('two')));
  });

  test('without a format the name simply has no extension', () {
    final relative = downloadRelativePath(
      id: 'abc',
      naming: DownloadNaming.artistTitle,
      artist: 'Artist',
      title: 'Title',
      album: 'Album',
    );

    expect(p.extension(relative), isEmpty);
  });

  test('the album layout numbers the track and uses folders', () {
    final relative = downloadRelativePath(
      id: 'abc',
      naming: DownloadNaming.artistAlbumTrack,
      artist: 'Radiohead',
      title: 'Airbag',
      album: 'OK Computer',
      track: 1,
      format: 'mp3',
    );

    expect(
      relative,
      startsWith(p.join('Radiohead', 'OK Computer', '01 Airbag (')),
    );
    expect(relative, endsWith('.mp3'));
  });

  test('switching the naming renames what is already downloaded', () async {
    final item = song(id: 'kept', title: 'Kept', artist: 'Someone');
    final oldPath = item.computeDownloadPath()!;
    File(oldPath).createSync(recursive: true);
    item.downloadExist = true;

    downloadNamingNotifier.value = DownloadNaming.artistTitle;
    final target = item.computeDownloadPath()!;
    expect(target, isNot(oldPath));

    final renamed = await library.renameDownloadsToNaming();

    expect(renamed, 1);
    expect(File(oldPath).existsSync(), isFalse);
    expect(File(target).existsSync(), isTrue);
    expect(item.downloadPath, target);
    expect(item.downloadExist, isTrue);
    expect(library.offlineMusicSongs.map((song) => song.id), ['kept']);
  });
}
