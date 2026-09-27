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
final ValueNotifier<double> downloadSizeNotifier = ValueNotifier(0);

/// Songs currently being downloaded for offline playback or temporary cache.
final ValueNotifier<Set<String>> downloadingSongIdsNotifier = ValueNotifier({});

typedef SongDownloader = Future<bool> Function(MyAudioMetadata song);

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
    final folderIds = await readJsonListFile(_folderIdListFile!);
    final validFolderIds = <String>[];
    for (final id in folderIds) {
      if (id is! String || id.isEmpty) {
        continue;
      }
      final folder = await Folder.from(id, sourceType == .webdav);
      if (folder.path.isEmpty) {
        continue;
      }
      folderList.add(folder);
      validFolderIds.add(id);
    }
    if (validFolderIds.length != folderIds.length) {
      await _folderIdListFile!.writeAsString(jsonEncode(validFolderIds));
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

    // Legacy releases stored explicit offline copies in caches/. Only files
    // whose md5 name belongs to a loaded song are eligible for migration;
    // every other cache file remains temporary playback data.
    await migrateLegacyOfflineCopies();

    canModify = true;
    changeNotifier.value++;
    layersManager.updateBackground();

    for (final folder in folderList) {
      await folder.load();
    }

    await _accumulateCache();
    await _accumulateDownloads();
  }

  Future<double> _directorySize(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      return 0;
    }
    var total = 0;
    await for (final entity in directory.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total / (1024 * 1024);
  }

  Future<void> _accumulateCache() async {
    cacheSizeNotifier.value = await _directorySize(getCachesPath(sourceType));
  }

  Future<void> _accumulateDownloads() async {
    downloadSizeNotifier.value = await _directorySize(
      getDownloadsPath(sourceType),
    );
  }

  Future<void> refreshStorageStats() async {
    await _accumulateCache();
    await _accumulateDownloads();
  }

  /// Moves known legacy offline copies out of the temporary cache directory.
  ///
  /// The source and destination have the same md5 filename. Unknown files are
  /// deliberately untouched because they are temporary playback cache. The
  /// operation is idempotent and never overwrites an existing destination.
  Future<void> migrateLegacyOfflineCopies() async {
    if (sourceType == .local) {
      return;
    }

    final cacheDir = Directory(getCachesPath(sourceType));
    if (!await cacheDir.exists()) {
      return;
    }

    final downloadsDir = Directory(getDownloadsPath(sourceType));
    for (final song in id2Song.values) {
      final oldPath = song.cachePath;
      final newPath = song.downloadPath;
      if (oldPath == null || newPath == null) {
        continue;
      }

      final oldFile = File(oldPath);
      final newFile = File(newPath);
      if (!await oldFile.exists() || await newFile.exists()) {
        continue;
      }

      try {
        await downloadsDir.create(recursive: true);
        var moved = false;
        try {
          await oldFile.rename(newPath);
          moved = true;
        } on FileSystemException {
          // A rename can fail on a different filesystem. Copy first and only
          // remove the old cache after the destination is known to exist.
          if (!await newFile.exists()) {
            await oldFile.copy(newPath);
          }
          moved = await newFile.exists();
          if (moved && await oldFile.exists()) {
            await oldFile.delete();
          }
        }

        if (moved && await newFile.exists()) {
          song.cacheExist = false;
          song.downloadExist = true;
          song.updateNotifier.value++;
        }
      } catch (error) {
        logger.output(
          'Failed to migrate legacy offline copy for ${song.id}: $error',
        );
      }
    }
    await _accumulateCache();
    await _accumulateDownloads();
  }

  Future<bool> _downloadToPath(
    MyAudioMetadata song,
    String savePath, {
    SongDownloader? downloader,
    bool delayForPlayback = false,
  }) async {
    if (downloadingSongIdsNotifier.value.contains(song.id)) {
      return false;
    }

    downloadingSongIdsNotifier.value = {
      ...downloadingSongIdsNotifier.value,
      song.id,
    };
    final outputFile = File(savePath);
    var success = false;
    try {
      if (delayForPlayback) {
        await Future.delayed(const Duration(seconds: 3));
      }
      await outputFile.parent.create(recursive: true);
      if (downloader != null) {
        success = await downloader(song);
      } else if (sourceType == .webdav) {
        success =
            await webdavClient?.download(
              remotePath: song.path!,
              localPath: savePath,
            ) ??
            false;
      } else if (isStreamSource) {
        success = await streamClient?.downloadSong(song.id, savePath) ?? false;
      }

      if (!success || !await outputFile.exists()) {
        if (await outputFile.exists()) {
          await outputFile.delete();
        }
        return false;
      }
      return true;
    } catch (error) {
      logger.output('Audio download failed for ${song.id}: $error');
      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      return false;
    } finally {
      final remaining = {...downloadingSongIdsNotifier.value}..remove(song.id);
      downloadingSongIdsNotifier.value = remaining;
    }
  }

  Future<bool> downloadForOffline(
    MyAudioMetadata song, {
    SongDownloader? downloader,
    Set<String> keepSongIds = const {},
  }) async {
    if (sourceType == .local ||
        song.downloadPath == null ||
        (sourceType == .webdav && song.path == null)) {
      return false;
    }
    final path = song.downloadPath!;
    if (song.downloadExist && await File(path).exists()) {
      return true;
    }

    final success = await _downloadToPath(song, path, downloader: downloader);
    song.downloadExist = success && await File(path).exists();
    song.updateNotifier.value++;
    if (!song.downloadExist) {
      return false;
    }

    await _accumulateDownloads();
    await enforceDownloadLimit(keepSongId: song.id, keepSongIds: keepSongIds);
    return song.downloadExist;
  }

  Future<bool> removeOfflineCopy(
    MyAudioMetadata song, {
    bool currentlyPlaying = false,
    bool currentlyQueued = false,
  }) async {
    final path = song.downloadPath;
    if (path == null || currentlyPlaying || currentlyQueued) {
      return false;
    }

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      song.downloadExist = false;
      song.updateNotifier.value++;
      await _accumulateDownloads();
      return true;
    } catch (error) {
      logger.output('Failed to remove offline copy for ${song.id}: $error');
      return false;
    }
  }

  List<MyAudioMetadata> get offlineMusicSongs =>
      id2Song.values
          .where((song) => song.downloadPath != null && song.downloadExist)
          .toList()
        ..sort((a, b) => a.compareTitle.compareTo(b.compareTitle));

  Future<void> tryAddCache(
    MyAudioMetadata song, {
    Set<String> keepSongIds = const {},
  }) async {
    if (sourceType == .local || song.cachePath == null || song.downloadExist) {
      return;
    }
    final path = song.cachePath!;
    if (song.cacheExist && await File(path).exists()) {
      return;
    }

    final success = await _downloadToPath(song, path, delayForPlayback: true);
    song.cacheExist = success && await File(path).exists();
    song.updateNotifier.value++;
    await _accumulateCache();
  }

  /// Removes only temporary playback cache. Offline music lives in downloads/
  /// and is intentionally not touched by this operation.
  Future<void> clearCache() async {
    final cacheDir = Directory(getCachesPath(sourceType));
    if (await cacheDir.exists()) {
      await for (final entity in cacheDir.list()) {
        if (entity is File) {
          await entity.delete();
        }
      }
    }

    cacheSizeNotifier.value = 0;
    for (final song in id2Song.values) {
      if (song.cacheExist) {
        song.cacheExist = false;
        song.updateNotifier.value++;
      }
    }
  }

  /// Deletes least-recently-used offline music until it fits the configured
  /// [offlineMusicLimitMbNotifier]. The persisted setting keeps its legacy key
  /// for compatibility with older installations.
  Future<void> enforceDownloadLimit({
    String? keepSongId,
    Set<String> keepSongIds = const {},
  }) async {
    final limitMb = offlineMusicLimitMbNotifier.value;
    if (limitMb <= 0) {
      return;
    }

    final downloadDir = Directory(getDownloadsPath(sourceType));
    if (!await downloadDir.exists()) {
      return;
    }

    final files = <File>[];
    var totalBytes = 0;
    await for (final entity in downloadDir.list()) {
      if (entity is! File) {
        continue;
      }
      files.add(entity);
      totalBytes += await entity.length();
    }

    final limitBytes = limitMb * 1024 * 1024;
    if (totalBytes <= limitBytes) {
      downloadSizeNotifier.value = totalBytes / (1024 * 1024);
      return;
    }

    final keepIds = {...keepSongIds, ?keepSongId};
    final keepNames = keepIds
        .map((id) => id2Song[id]?.downloadPath)
        .whereType<String>()
        .map(_fileNameOf)
        .toSet();

    final entries = <({File file, DateTime time, int size})>[];
    for (final file in files) {
      entries.add((
        file: file,
        time: await _lastUsed(file),
        size: await file.length(),
      ));
    }
    entries.sort((a, b) => a.time.compareTo(b.time));

    var removedBytes = 0;
    for (final entry in entries) {
      if (totalBytes - removedBytes <= limitBytes) {
        break;
      }
      if (keepNames.contains(_fileNameOf(entry.file.path))) {
        continue;
      }
      try {
        await entry.file.delete();
        removedBytes += entry.size;
        _markDownloadMissing(entry.file.path);
      } catch (error) {
        logger.output('Failed to evict ${entry.file.path}: $error');
      }
    }

    // If the queue itself exceeds the limit, retain only the currently playing
    // copy. A queued song can be downloaded again, but deleting the playing
    // file would interrupt playback.
    if (totalBytes - removedBytes > limitBytes) {
      final playingName = switch (keepSongId) {
        final String id => switch (id2Song[id]?.downloadPath) {
          final String path => _fileNameOf(path),
          _ => null,
        },
        _ => null,
      };

      for (final entry in entries) {
        if (totalBytes - removedBytes <= limitBytes) {
          break;
        }
        if (_fileNameOf(entry.file.path) == playingName) {
          continue;
        }
        try {
          await entry.file.delete();
          removedBytes += entry.size;
          _markDownloadMissing(entry.file.path);
        } catch (error) {
          logger.output('Failed to evict ${entry.file.path}: $error');
        }
      }
    }

    if (removedBytes > 0) {
      logger.output(
        'Offline music limit ${limitMb}MB: evicted '
        '${(removedBytes / (1024 * 1024)).toStringAsFixed(1)}MB',
      );
    }
    downloadSizeNotifier.value = (totalBytes - removedBytes) / (1024 * 1024);
  }

  /// The file name part of [path], accepting either separator.
  String _fileNameOf(String path) {
    final slash = path.lastIndexOf('/');
    final backslash = path.lastIndexOf('\\');
    final cut = slash > backslash ? slash : backslash;
    return cut < 0 ? path : path.substring(cut + 1);
  }

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

  /// Clears [MyAudioMetadata.downloadExist] for an evicted offline copy.
  void _markDownloadMissing(String path) {
    final removedName = _fileNameOf(path);
    for (final song in id2Song.values) {
      if (song.downloadPath != null &&
          _fileNameOf(song.downloadPath!) == removedName) {
        song.downloadExist = false;
        song.updateNotifier.value++;
        break;
      }
    }
  }

  Future<void> clearPicture() async {
    Directory pictureDir = Directory(getPicturesPath(sourceType));
    if (await pictureDir.exists()) {
      await for (final file in pictureDir.list()) {
        if (file is File) {
          await file.delete();
        }
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
