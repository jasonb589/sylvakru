import 'dart:convert';
import 'dart:io';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:drift/drift.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
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
import 'package:sylvakru/base/utils/download_tags.dart';
import 'package:sylvakru/base/data/folder.dart';
import 'package:sylvakru/layer/layers_manager.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:pool/pool.dart';

Library library = Library();

final ValueNotifier<double> cacheSizeNotifier = ValueNotifier(0);
final ValueNotifier<double> downloadSizeNotifier = ValueNotifier(0);

/// Bytes of the downloads folder that no library song claims: files the
/// listener dropped in, or leftovers of songs that are gone.

/// How far over the configured download limit the folder is, in MB. Zero means
/// "within the limit".
final ValueNotifier<double> downloadOverLimitMbNotifier = ValueNotifier(0);
final ValueNotifier<double> otherDownloadSizeNotifier = ValueNotifier(0);

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

    // Playing a song used to move its cache file into downloads/ and mark it a
    // download. Put those files back where they belong, once.
    await repairDownloadCacheMixUp();

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
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total / (1024 * 1024);
  }

  Future<void> _accumulateCache() async {
    cacheSizeNotifier.value = await _directorySize(getCachesPath(sourceType));
  }

  /// Splits the downloads folder into what belongs to the library and what
  /// does not.
  ///
  /// The figure shown for "downloaded" used to be the raw folder size, which
  /// also counted files the library knows nothing about: dropped in by hand, or
  /// left behind by a song that is no longer in the library. That is why the
  /// number never matched the list underneath it. Both figures come from one
  /// walk, so claimed + other is always the folder.
  Future<void> _accumulateDownloads() async {
    final sizes = await _fileSizes(getDownloadsPath(sourceType));

    final claimedNames = <String>{};
    var claimedBytes = 0;
    for (final song in id2Song.values) {
      final path = song.downloadPath;
      if (path == null) {
        continue;
      }
      final name = _fileNameOf(path);
      if (!claimedNames.add(name)) {
        continue;
      }
      claimedBytes += sizes[name] ?? 0;
    }

    var totalBytes = 0;
    for (final size in sizes.values) {
      totalBytes += size;
    }

    downloadSizeNotifier.value = claimedBytes / (1024 * 1024);
    otherDownloadSizeNotifier.value =
        (totalBytes - claimedBytes) / (1024 * 1024);
  }

  /// File name to size for every file under [path], subfolders included, so a
  /// future per-album layout cannot fall out of the accounting.
  Future<Map<String, int>> _fileSizes(String path) async {
    final sizes = <String, int>{};
    final directory = Directory(path);
    if (!await directory.exists()) {
      return sizes;
    }
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        sizes[_fileNameOf(entity.path)] = await entity.length();
      }
    }
    return sizes;
  }

  Future<void> refreshStorageStats() async {
    await _accumulateCache();
    await _accumulateDownloads();
  }

  /// Notes how far the downloads folder is over the configured limit.
  ///
  /// Exceeding the limit used to delete the least recently used downloads on
  /// its own. The files belong to the listener, so the number is now reported
  /// and the removal stays an action they take ([cleanUpToLimit]).
  Future<void> checkDownloadBudget() async {
    final limitMb = offlineMusicLimitMbNotifier.value;
    if (limitMb <= 0) {
      downloadOverLimitMbNotifier.value = 0;
      return;
    }
    await _accumulateDownloads();
    final used = downloadSizeNotifier.value + otherDownloadSizeNotifier.value;
    downloadOverLimitMbNotifier.value = used > limitMb ? used - limitMb : 0;
  }

  /// Old name for [cleanUpToLimit], kept so existing callers — including the
  /// tests that pin the limit behaviour — keep working.
  Future<void> enforceDownloadLimit({
    String? keepSongId,
    Set<String> keepSongIds = const {},
  }) => cleanUpToLimit(keepSongId: keepSongId, keepSongIds: keepSongIds);

  /// Points every downloaded song at the folder the listener just picked, and
  /// optionally moves the files there.
  ///
  /// Files keep their names, so this is a move per file with a copy fallback
  /// for a different volume. The per-song paths are recomputed either way,
  /// which is what makes the centre show the new folder immediately.
  Future<int> relocateDownloads({
    required String oldFolder,
    required bool moveFiles,
  }) async {
    if (sourceType == .local) {
      return 0;
    }

    final newFolder = getDownloadsPath(sourceType);
    if (newFolder == oldFolder) {
      return 0;
    }

    var moved = 0;
    final oldDirectory = Directory(oldFolder);
    if (moveFiles && await oldDirectory.exists()) {
      final newDirectory = Directory(newFolder);
      await newDirectory.create(recursive: true);
      await for (final entity in oldDirectory.list(recursive: true)) {
        if (entity is! File) {
          continue;
        }
        // Keep the folder part of the name: a naming template can put files in
        // per-artist folders, and flattening them here would lose the layout.
        final target = p.join(
          newDirectory.path,
          p.relative(entity.path, from: oldDirectory.path),
        );
        try {
          if (await File(target).exists()) {
            continue;
          }
          await File(target).parent.create(recursive: true);
          try {
            await entity.rename(target);
          } on FileSystemException {
            await entity.copy(target);
            if (await File(target).exists()) {
              await entity.delete();
            }
          }
          moved++;
        } catch (error) {
          logger.output('Failed to move ${entity.path}: $error');
        }
      }
    }

    await repointDownloads(renameFiles: true);

    await refreshStorageStats();
    return moved;
  }

  /// Points every song at the path the naming setting asks for.
  ///
  /// With [renameFiles] the files on disk are moved to those names as well: the
  /// library is the only thing that knows where a download went, so switching
  /// templates has to take the files along. A file that cannot be moved, or
  /// whose new name is already taken, keeps its old path — the one the listener
  /// can still play and remove. Nothing here deletes anything.
  Future<int> repointDownloads({bool renameFiles = false}) async {
    var renamed = 0;
    for (final song in id2Song.values) {
      final current = song.downloadPath;
      final target = song.computeDownloadPath();
      if (target == null) {
        continue;
      }

      if (renameFiles && current != null && current != target) {
        final file = File(current);
        if (await file.exists()) {
          try {
            final destination = File(target);
            await destination.parent.create(recursive: true);
            if (await destination.exists()) {
              logger.output('$target is taken; keeping ${file.path}');
            } else {
              try {
                await file.rename(target);
              } on FileSystemException {
                await file.copy(target);
                if (await destination.exists()) {
                  await file.delete();
                }
              }
              if (await destination.exists()) {
                renamed++;
              }
            }
          } catch (error) {
            logger.output('Failed to rename ${song.id}: $error');
          }
        }
      }

      final path = File(target).existsSync() ? target : current;
      song.downloadPath = path;
      song.downloadExist = path != null && File(path).existsSync();
      song.updateNotifier.value++;
    }

    await refreshStorageStats();
    return renamed;
  }

  /// Applies the naming setting to downloads that are already on disk.
  Future<int> renameDownloadsToNaming() => repointDownloads(renameFiles: true);

  /// Moves playback cache that earlier builds promoted into downloads/ back
  /// into caches/, once.
  ///
  /// Until 4.15.1 every file in caches/ whose name belonged to a loaded song
  /// was taken for an explicit download and renamed into downloads/, so simply
  /// listening to a song could turn it into a "download": the centre filled up
  /// with music nobody downloaded while the temporary cache fell to 0 MB. Only
  /// [downloadForOffline] writes downloads/ and only [tryAddCache] writes
  /// caches/, so a file in downloads/ without a cache copy next to it is one
  /// this build would not have put there. A song that has both copies keeps its
  /// download: the cache copy is the playback one, the download is the
  /// listener's.
  ///
  /// The marker in setting.json keeps the pass from running a second time, and
  /// a crash half-way through is harmless because it is idempotent.
  Future<void> repairDownloadCacheMixUp() async {
    if (sourceType == .local || downloadSplitRepaired) {
      return;
    }

    final cacheDir = Directory(getCachesPath(sourceType));
    var moved = 0;

    for (final song in id2Song.values) {
      final downloadPath = song.downloadPath;
      final cachePath = song.cachePath;
      if (downloadPath == null || cachePath == null) {
        continue;
      }

      final downloadFile = File(downloadPath);
      if (!await downloadFile.exists() || await File(cachePath).exists()) {
        continue;
      }

      try {
        await cacheDir.create(recursive: true);
        var relocated = false;
        try {
          await downloadFile.rename(cachePath);
          relocated = true;
        } on FileSystemException {
          // A rename fails across volumes: copy first and only drop the
          // download once the cache copy is known to be there.
          await downloadFile.copy(cachePath);
          relocated = await File(cachePath).exists();
          if (relocated && await downloadFile.exists()) {
            await downloadFile.delete();
          }
        }

        if (relocated) {
          song.downloadExist = false;
          song.cacheExist = true;
          song.updateNotifier.value++;
          moved++;
        }
      } catch (error) {
        logger.output('Failed to move ${song.id} back to the cache: $error');
      }
    }

    downloadSplitRepaired = true;
    setting.save();
    await _accumulateCache();
    await _accumulateDownloads();
    if (moved > 0) {
      changeNotifier.value++;
    }
  }

  Future<bool> _downloadToPath(
    MyAudioMetadata song,
    String savePath, {
    SongDownloader? downloader,
    bool delayForPlayback = false,
    void Function(int received, int total)? onProgress,
    DownloadCancellation? cancellation,
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
              onReceiveProgress: onProgress,
              cancellation: cancellation,
            ) ??
            false;
      } else if (isStreamSource) {
        success =
            await streamClient?.downloadSong(
              song.id,
              savePath,
              onProgress: onProgress,
              cancellation: cancellation,
            ) ??
            false;
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
    void Function(int received, int total)? onProgress,
    DownloadCancellation? cancellation,
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

    final success = await _downloadToPath(
      song,
      path,
      downloader: downloader,
      onProgress: onProgress,
      cancellation: cancellation,
    );
    song.downloadExist = success && await File(path).exists();
    song.updateNotifier.value++;
    if (!song.downloadExist) {
      return false;
    }

    if (writeDownloadTagsNotifier.value) {
      // The file is the listener's now, so it should say what it is even in a
      // player that never heard of this app.
      tagDownloadedFile(song, path);
    }

    await _accumulateDownloads();
    // Reaching the limit does not delete anything by itself: the centre shows
    // it and the listener decides, through [cleanUpToLimit].
    await checkDownloadBudget();
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
  Future<void> cleanUpToLimit({
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
