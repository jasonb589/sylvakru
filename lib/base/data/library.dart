import 'dart:convert';
import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:drift/drift.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/database.dart';
import 'package:sylvakru/base/extensions/metadata_extension.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/services/picture_load_scheduler.dart';
import 'package:sylvakru/base/services/picture_service.dart';
import 'package:sylvakru/base/services/stream_client.dart';
import 'package:sylvakru/base/services/webdav_client.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/utils/path.dart';
import 'package:sylvakru/base/data/folder.dart';
import 'package:sylvakru/layer/layers_manager.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:pool/pool.dart';

Library library = Library();

final ValueNotifier<double> cacheSizeNotifier = ValueNotifier(0);

class Library {
  MetadataDB? _metadataDB;

  Map<String, MyAudioMetadata> id2Song = {};
  List<MyAudioMetadata> songList = [];

  final changeNotifier = ValueNotifier(0);

  File? _folderIdListFile;
  List<Folder> folderList = [];
  final folderListChangeNotifier = ValueNotifier(0);

  bool canModify = false;

  Library() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    _metadataDB = MetadataDB(openMetadataDB('${sourceType.name}/metadata.db'));
    if (isNotStreamSource) {
      _folderIdListFile = File(
        "${getFolderConfigPath(sourceType)}/folder_id_list.json",
      );
      initFile(_folderIdListFile!, true);
    }
  }

  Future<bool> updateFolders(List<String> idList) async {
    bool needUpdate = false;
    if (idList.length == folderList.length) {
      for (int i = 0; i < idList.length; i++) {
        if (idList[i] != folderList[i].id) {
          needUpdate = true;
          break;
        }
      }
    } else {
      needUpdate = true;
    }

    if (!needUpdate) {
      return false;
    }

    List<Folder> newFolderList = [];
    for (int i = 0; i < idList.length; i++) {
      String id = idList[i];
      bool exist = false;
      for (final folder in folderList) {
        if (id == folder.id) {
          newFolderList.add(folder);
          exist = true;
          break;
        }
      }
      if (!exist) {
        newFolderList.add(await Folder.create(id, sourceType == .webdav));
      }
    }

    for (final folder in folderList) {
      if (newFolderList.contains(folder)) {
        continue;
      }
      folder.delete();
      layersManager.removeLayerIfNeed(folder);
    }

    folderList = newFolderList;
    await _folderIdListFile!.writeAsString(
      jsonEncode(folderList.map((e) => e.id).toList()),
    );

    folderListChangeNotifier.value++;
    return true;
  }

  Folder? getFolderById(String id) {
    for (final folder in folderList) {
      if (folder.id == id) {
        return folder;
      }
    }

    return null;
  }

  Future<void> initFolders() async {
    // must execute before loading metadata(set ios path)
    for (final id in await readJsonListFile(_folderIdListFile!)) {
      final folder = await Folder.from(id, sourceType == .webdav);
      folderList.add(folder);
    }
  }

  Future<void> load() async {
    if (isNotStreamSource) {
      await initFolders();
    }

    do {
      final rows = await (_metadataDB!.select(
        _metadataDB!.metadataItems,
      )..limit(1000, offset: songList.length)).get();

      if (rows.isEmpty) {
        break;
      }

      for (final row in rows) {
        final song = row.toMetadata();
        id2Song.putIfAbsent(row.id, () => song);
        songList.add(song);
      }

      if (songList.length == 1000 || songList.length % 10000 == 0) {
        changeNotifier.value++;
        layersManager.updateBackground();
      }
    } while (true);

    canModify = true;
    changeNotifier.value++;
    layersManager.updateBackground();

    for (final folder in folderList) {
      await folder.load();
    }

    await _accumulateCache();
  }

  Future<void> _accumulateCache() async {
    cacheSizeNotifier.value = 0;
    Directory cacheDir = Directory(getCachesPath(sourceType));
    if (!await cacheDir.exists()) {
      return;
    }
    int total = 0;
    await for (final file in cacheDir.list()) {
      if (file is File) {
        total += await file.length();
      }
    }
    cacheSizeNotifier.value += total / (1024 * 1024);
  }

  Future<void> tryAddCache(MyAudioMetadata song) async {
    if (sourceType == .local || song.cacheExist) {
      return;
    }
    final savePath = song.cachePath!;
    late bool success;
    // delay download to prevent it from running at the same time as audio loading
    await Future.delayed(Duration(seconds: 3));

    if (sourceType == .webdav) {
      success =
          await webdavClient?.download(
            remotePath: song.path!,
            localPath: savePath,
          ) ??
          false;
    } else {
      success = await streamClient?.downloadSong(song.id, savePath) ?? false;
    }
    final tmp = File(savePath);
    if (await tmp.exists()) {
      if (success) {
        song.cacheExist = true;
        cacheSizeNotifier.value += await tmp.length() / (1024 * 1024);
        // keep the folder inside the configured bound; without this the cache
        // only ever grew
        await enforceCacheLimit(keepSongId: song.id);
      } else {
        await tmp.delete();
      }
    }
  }

  Future<void> clearCache() async {
    Directory cacheDir = Directory(getCachesPath(sourceType));
    if (await cacheDir.exists()) {
      await for (final file in cacheDir.list()) {
        if (file is File) {
          await file.delete();
        }
      }
    }

    cacheSizeNotifier.value = 0;
    for (final song in library.id2Song.values) {
      song.cacheExist = false;
    }
  }

  /// Deletes the least recently used cache files until the cache fits
  /// [cacheLimitMbNotifier].
  ///
  /// Cached songs were never evicted, so the folder grew without bound. The
  /// limit is what keeps it in check; 0 means "no limit" and does nothing.
  /// The currently playing song is skipped so playback never loses its file.
  Future<void> enforceCacheLimit({String? keepSongId}) async {
    final limitMb = cacheLimitMbNotifier.value;
    if (limitMb <= 0) {
      return;
    }

    final cacheDir = Directory(getCachesPath(sourceType));
    if (!await cacheDir.exists()) {
      return;
    }

    final files = <File>[];
    var totalBytes = 0;
    await for (final entity in cacheDir.list()) {
      if (entity is! File) {
        continue;
      }
      files.add(entity);
      totalBytes += await entity.length();
    }

    final limitBytes = limitMb * 1024 * 1024;
    if (totalBytes <= limitBytes) {
      return;
    }

    // the cached file name is the md5 of the song id, so the playing song's
    // path identifies exactly the file to spare. Compare file names rather than
    // whole paths: cachePath is built with forward slashes ('<dir>/<md5>') while
    // Directory.list() yields the platform's own separators, so a string
    // comparison silently never matched on Windows and the playing song's file
    // could be evicted mid-playback.
    final keepPath = keepSongId == null ? null : id2Song[keepSongId]?.cachePath;
    final keepName = keepPath == null ? null : _fileNameOf(keepPath);

    final entries = <({File file, DateTime time, int size})>[];
    for (final file in files) {
      entries.add((
        file: file,
        time: await _lastUsed(file),
        size: await file.length(),
      ));
    }
    // oldest first, so the head is what gets removed
    entries.sort((a, b) => a.time.compareTo(b.time));

    var removedBytes = 0;
    for (final entry in entries) {
      if (totalBytes - removedBytes <= limitBytes) {
        break;
      }
      if (keepName != null && _fileNameOf(entry.file.path) == keepName) {
        continue;
      }
      try {
        await entry.file.delete();
        removedBytes += entry.size;
        _markCacheMissing(entry.file.path);
      } catch (e) {
        logger.output('Failed to evict ${entry.file.path}: $e');
      }
    }

    if (removedBytes > 0) {
      logger.output(
        'Cache limit ${limitMb}MB: evicted '
        '${(removedBytes / (1024 * 1024)).toStringAsFixed(1)}MB',
      );
      cacheSizeNotifier.value = (totalBytes - removedBytes) / (1024 * 1024);
    }
  }

  /// The file name part of [path], accepting either separator.
  String _fileNameOf(String path) {
    final slash = path.lastIndexOf('/');
    final backslash = path.lastIndexOf('\\');
    final cut = slash > backslash ? slash : backslash;
    return cut < 0 ? path : path.substring(cut + 1);
  }

  /// When a cache file was last read.
  ///
  /// `lastAccessed` is not maintained by every platform, so a zero timestamp
  /// would make that file look like the oldest; falling back to the
  /// modification time keeps the order meaningful.
  Future<DateTime> _lastUsed(File file) async {
    try {
      final stat = await file.stat();
      return stat.accessed.isAfter(stat.modified)
          ? stat.accessed
          : stat.modified;
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  /// Clears [MyAudioMetadata.cacheExist] for the song whose file was removed.
  void _markCacheMissing(String path) {
    for (final song in id2Song.values) {
      if (song.cachePath == path) {
        song.cacheExist = false;
        break;
      }
    }
  }

  Future<void> clearPicture() async {
    Directory pictureDir = Directory(getPicturesPath(sourceType));
    if (await pictureDir.exists()) {
      await for (final file in pictureDir.list()) {
        await file.delete();
      }
    }
    pictureLoadScheduler.clear();
    for (final picture in globalPictureList) {
      picture.reset();
    }

    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    imageCache.clearLiveImages();
  }

  Future<void> _saveMetadata() async {
    final db = _metadataDB!;
    await db.transaction(() async {
      await db.delete(db.metadataItems).go();

      await db.batch((batch) {
        batch.insertAll(
          db.metadataItems,
          songList.map((e) => e.toCompanion()).toList(),
        );
      });
    });
  }

  Future<void> _saveBatchMetadata(List<MyAudioMetadata> songs) async {
    final db = _metadataDB!;
    await db.transaction(() async {
      await db.batch((batch) {
        batch.insertAll(
          db.metadataItems,
          songs.map((e) => e.toCompanion()).toList(),
        );
      });
    });
  }

  Future<void> _clearMetadata() async {
    final db = _metadataDB!;
    db.transaction(() async {
      await db.delete(db.metadataItems).go();
    });
  }

  Future<void> updatePlayCount(MyAudioMetadata song) async {
    final db = _metadataDB!;
    await (db.update(
      db.metadataItems,
    )..where((t) => t.id.equals(song.id))).write(
      MetadataItemsCompanion(
        playCount: Value(song.playCount),
        lastPlayed: Value(song.lastPlayed!.millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> updateDuration(MyAudioMetadata song, Duration duration) async {
    final db = _metadataDB!;
    await (db.update(
      db.metadataItems,
    )..where((t) => t.id.equals(song.id))).write(
      MetadataItemsCompanion(duration: Value(duration.inMilliseconds)),
    );
    song.duration = duration;
    song.updateNotifier.value++;
  }

  Future<void> updateMetadata(MyAudioMetadata song) async {
    final db = _metadataDB!;
    await (db.update(
      db.metadataItems,
    )..where((t) => t.id.equals(song.id))).write(
      MetadataItemsCompanion(
        title: Value(song.title),
        artist: Value(song.artist),
        album: Value(song.album),
        genre: Value(song.genre),
        lyrics: Value(song.lyrics),
        year: Value(song.year),
        track: Value(song.track),
        disc: Value(song.disc),
      ),
    );
  }

  void shuffle() {
    songList.shuffle();
    update();
  }

  void update() {
    changeNotifier.value++;
    layersManager.updateBackground();
    if (isNotStreamSource) {
      _saveMetadata();
    }
  }

  void _syncNotify() {
    changeNotifier.value++;
    layersManager.updateBackground();
  }

  Future<MyAudioMetadata?> _parseMetadataIfNeed(
    String id,
    String path,
    DateTime modified,
  ) async {
    MyAudioMetadata? song = library.id2Song[id];

    if ((song?.modified?.difference(modified).inSeconds.abs() ?? 2) > 1) {
      String readPath = path;
      Map<String, String>? headers;
      bool isWebdav = path.startsWith('http://') || path.startsWith('https://');
      if (isWebdav) {
        final tmpPath = await covertToRedirectPathIfNeed(path);
        if (tmpPath == null) {
          headers = webdavClient?.headers;
        } else {
          readPath = tmpPath;
        }
      }
      AudioMetadata? tmp;
      try {
        tmp = await readMetadataAsync(readPath, false, headers: headers);
      } catch (e) {
        logger.output("$path: $e");
      }

      if (tmp != null) {
        song = MyAudioMetadata(tmp, id: id, path: path, modified: modified);
      } else {
        song = null;
      }
    }
    if (song != null) {
      library.id2Song[id] = song;
    } else {
      library.id2Song.remove(id);
    }
    return song;
  }

  Future<void> sync() async {
    canModify = false;

    switch (sourceType) {
      case .local:
      case .webdav:
        Map<String, DateTime> pathAndModified = {};

        final updateCount = sourceType == .local ? 1000 : 25;

        for (final folder in folderList) {
          folder.songList.clear();
          folder.changeNotifier.value++;
          await folder.setFileAndModified();
          pathAndModified.addAll(folder.pathAndModified);
        }

        final pool = Pool(6);

        final tasks = <Future>[];

        Set<String> validId = {};

        Future<void> syncOne(String id, String path, DateTime modified) async {
          final song = await _parseMetadataIfNeed(id, path, modified);
          if (song != null) {
            validId.add(id);
            songList.add(song);
            if (validId.length % updateCount == 0) {
              _syncNotify();
            }
          }
        }

        final songIdList = songList.map((e) => e.id).toList();
        songList.clear();

        changeNotifier.value++;

        for (final id in songIdList) {
          String path = id;

          DateTime? modified;
          if (sourceType == .local) {
            if (Platform.isIOS) {
              path = revertIOSPath(path);
            }
            modified = pathAndModified.remove(path);
          } else {
            if (webdavClient != null) {
              modified = pathAndModified.remove(
                path.substring(webdavClient!.cleanBaseUrl.length),
              );
            }
          }

          if (modified != null) {
            tasks.add(
              pool.withResource(() async {
                await syncOne(id, path, modified!);
              }),
            );
          }
        }

        await Future.wait(tasks);

        for (final entry in pathAndModified.entries) {
          String path = entry.key;
          String id = path;
          if (sourceType == .webdav) {
            path = webdavClient!.cleanBaseUrl + path;
            id = path;
          } else if (Platform.isIOS) {
            id = convertIOSPath(path);
          }
          tasks.add(pool.withResource(() => syncOne(id, path, entry.value)));
        }

        await Future.wait(tasks);

        await pool.close();

        id2Song.removeWhere((id, song) => !validId.contains(id));

        for (final folder in folderList) {
          await folder.sync();
          folder.clearPathAndModified();
        }

        await _saveMetadata();
      default:
        Map<String, MyAudioMetadata> id2SongTmp = {};

        // feiniu does not contain playcount field, we keep it.
        if (sourceType == .feiniu) {
          id2SongTmp = Map.fromEntries(
            id2Song.entries.where((entry) => entry.value.playCount > 0),
          );
        }

        id2Song.clear();
        songList.clear();

        await _clearMetadata();

        int songCount = await streamClient?.getSongCount() ?? 0;

        int nextIndex = 0;
        final results = <int, List<MyAudioMetadata>>{};

        final pool = Pool(6);
        final tasks = <Future>[];
        final batchSize = 1000;
        for (int i = 0; i * batchSize < songCount; i++) {
          tasks.add(
            pool.withResource(() async {
              final songs =
                  await streamClient?.getSongs(batchSize, i * batchSize) ?? [];

              results[i] = songs;

              while (results.containsKey(nextIndex)) {
                final songs = results.remove(nextIndex)!;

                if (sourceType == .feiniu) {
                  for (final song in songs) {
                    song.playCount = id2SongTmp[song.id]?.playCount ?? 0;
                    song.lastPlayed = id2SongTmp[song.id]?.lastPlayed;
                  }
                }
                songList.addAll(songs);

                await _saveBatchMetadata(songs);

                if (songList.length == batchSize ||
                    songList.length % 10000 == 0) {
                  _syncNotify();
                }

                nextIndex++;
              }
            }),
          );
        }
        await Future.wait(tasks);
        await pool.close();
    }

    canModify = true;
    _syncNotify();
  }
}
