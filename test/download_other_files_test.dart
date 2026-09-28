import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/utils/path.dart';
import 'package:sylvakru/base/utils/reveal_in_file_manager.dart';

/// The downloads folder holds two kinds of files: the copies the library made
/// and whatever else ended up there. The centre lists the others so the
/// listener can look at them, and deletes one only when asked — never one of
/// the library's own, and never anything outside the folder.
void main() {
  setUpAll(() async {
    appSupportDir = Directory.systemTemp.createTempSync('sylvakru_other');
    await logger.init();
  });

  setUp(() async {
    sourceType = SourceType.navidrome;
    isStreamSource = true;
    isNotStreamSource = false;
    library.id2Song.clear();
    await setting.load();
    final directory = Directory(getDownloadsPath(sourceType));
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  MyAudioMetadata song(String id) {
    final item = MyAudioMetadata(AudioMetadata(title: id), id: id);
    library.id2Song[id] = item;
    return item;
  }

  test('only the files that belong to no song are listed', () async {
    final kept = song('kept');
    final keptFile = File(kept.computeDownloadPath()!)
      ..createSync(recursive: true)
      ..writeAsStringSync('audio');
    final stray = File(p.join(getDownloadsPath(sourceType), 'hand-dropped'))
      ..createSync(recursive: true)
      ..writeAsStringSync('other');

    final files = await library.otherDownloadFiles();

    expect(files, hasLength(1));
    expect(files.single.path, stray.path);
    expect(files.single.bytes, 5);
    expect(keptFile.existsSync(), isTrue);
  });

  test('the library refuses to delete what it did not put there', () async {
    final kept = song('kept');
    final keptFile = File(kept.computeDownloadPath()!)
      ..createSync(recursive: true)
      ..writeAsStringSync('audio');
    final outside = File(p.join(appSupportDir.path, 'outside.flac'))
      ..createSync(recursive: true)
      ..writeAsStringSync('outside');

    expect(await library.deleteOtherDownload(keptFile.path), isFalse);
    expect(keptFile.existsSync(), isTrue);

    expect(await library.deleteOtherDownload(outside.path), isFalse);
    expect(outside.existsSync(), isTrue);
  });

  test('a file the centre listed can be deleted', () async {
    final stray = File(p.join(getDownloadsPath(sourceType), 'stray'))
      ..createSync(recursive: true)
      ..writeAsStringSync('other');

    expect(await library.deleteOtherDownload(stray.path), isTrue);
    expect(stray.existsSync(), isFalse);
    expect(await library.otherDownloadFiles(), isEmpty);
  });

  test('the file manager command is shaped per platform', () {
    expect(revealCommand(r'C:\music\a.flac', isWindows: true), [
      'explorer',
      r'/select,C:\music\a.flac',
    ]);
    expect(revealCommand('/music/a.flac', isMacOS: true), [
      'open',
      '-R',
      '/music/a.flac',
    ]);
    expect(revealCommand('/music/a.flac'), ['xdg-open', '/music']);
  });

  test('a file deleted outside the app stops counting as a download', () async {
    final item = song('gone');
    final file = File(item.computeDownloadPath()!)
      ..createSync(recursive: true)
      ..writeAsStringSync('audio');
    item.downloadExist = true;

    // What the listener does in Explorer while the app is running; the centre
    // re-reads the folder when it comes into view.
    file.deleteSync();
    await library.repointDownloads();

    expect(item.downloadExist, isFalse);
    expect(library.offlineMusicSongs, isEmpty);
  });
}
