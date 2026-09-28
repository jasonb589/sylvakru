import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/library.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/utils/download_tags.dart';
import 'package:sylvakru/base/utils/path.dart';

/// A downloaded file should say what it is even in a player that never heard of
/// this app — but only what the library really knows. A tag it does not have
/// must not overwrite the one already in the file, and playback cache is not
/// the listener's file to rewrite.
void main() {
  late Directory support;
  final calls = <({String path, Map<String, Object> tags})>[];

  setUpAll(() async {
    support = Directory.systemTemp.createTempSync('sylvakru_tags');
    appSupportDir = support;
    await logger.init();
  });

  setUp(() async {
    sourceType = SourceType.navidrome;
    isStreamSource = true;
    isNotStreamSource = false;
    library.id2Song.clear();
    await setting.load();
    writeDownloadTagsNotifier.value = true;
    calls.clear();
    downloadTagWriter = (path, tags) {
      calls.add((path: path, tags: tags));
      return true;
    };

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

  tearDown(() {
    downloadTagWriter = writeTagsWithLofty;
  });

  MyAudioMetadata song({
    required String id,
    String? title,
    String? artist,
    String? album,
    int? track,
  }) {
    final item = MyAudioMetadata(AudioMetadata(title: title ?? ''), id: id);
    item.title = title;
    item.artist = artist;
    item.album = album;
    item.track = track;
    library.id2Song[id] = item;
    return item;
  }

  SongDownloader writingAudio() => (item) async {
    await File(item.downloadPath!).writeAsString('audio');
    return true;
  };

  test('only what the library knows is handed to the writer', () {
    final item = song(id: 'known', title: 'Song', artist: 'Someone');

    final tags = downloadTagsFor(item);

    expect(tags['title'], 'Song');
    expect(tags['artist'], 'Someone');
    // No display fallback: "Unknown Artist" would replace a real tag that the
    // file already carries.
    expect(tags.containsKey('artist'), isTrue);
    expect(tags.containsKey('album'), isFalse);
    expect(tags.containsKey('lyrics'), isFalse);
  });

  test('a blank value counts as nothing to say', () {
    final item = song(id: 'blank', title: '  ', artist: '');

    expect(downloadTagsFor(item), isEmpty);
  });

  test('a finished download is tagged, and the switch can stop it', () async {
    final item = song(id: 'tagged', title: 'Tagged', artist: 'Someone');
    await library.downloadForOffline(item, downloader: writingAudio());

    expect(calls, hasLength(1));
    expect(calls.single.path, item.downloadPath);
    expect(calls.single.tags['title'], 'Tagged');

    writeDownloadTagsNotifier.value = false;
    final second = song(id: 'untouched', title: 'Untouched');
    await library.downloadForOffline(second, downloader: writingAudio());

    expect(calls, hasLength(1));
    expect(File(second.downloadPath!).existsSync(), isTrue);
  });

  test('a file the tagger cannot read is reported, not thrown', () {
    final file = File('${support.path}/not-audio.txt')
      ..writeAsStringSync('hello');

    expect(
      () => writeTagsWithLofty(file.path, {'title': 'x'}),
      returnsNormally,
    );
  });
}
