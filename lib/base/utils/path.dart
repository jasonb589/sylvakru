import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:http/http.dart' as http;
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/services/webdav_client.dart';

void setIOSFileProviderStorageIfNeed(String? iosPath) {
  if (iosFileProviderStorage == null && iosPath != null) {
    final tmp = iosPath.split('File Provider Storage/').first;
    iosFileProviderStorage = "${tmp}File Provider Storage/";
  }
}

bool isFileProviderStorePath(String path) {
  return path.contains('File Provider Storage/');
}

// full path to short path
String convertIOSPath(String path) {
  if (path.contains('File Provider Storage/')) {
    return path.split('File Provider Storage/').last;
  } else {
    path = path.substring(path.indexOf('Documents'));
    return path.replaceFirst('Documents', 'Sylvakru');
  }
}

// short path to full path
String revertIOSPath(String path) {
  if (path.startsWith('Sylvakru')) {
    return "${appDocsDir.parent.path}/${path.replaceFirst('Sylvakru', 'Documents')}";
  } else {
    if (iosFileProviderStorage == null) {
      return '';
    }
    return iosFileProviderStorage! + path;
  }
}

// full path to short path
String convertIOSSupportPath(String path) {
  return path.split('Application Support/').last;
}

// short path to full path
String revertIOSSupportPath(String path) {
  return "${appSupportDir.path}/$path";
}

void initFile(File file, bool isList) {
  if (!file.existsSync()) {
    file.createSync(recursive: true);
    file.writeAsStringSync(isList ? '[]' : '{}');
  }
}

/// Decodes [file] as a JSON list, resetting it to `[]` and returning an
/// empty list if the content is missing or corrupted (e.g. a crash mid-write)
/// instead of letting the exception crash startup.
List<dynamic> readJsonListFileSync(File file) {
  try {
    return jsonDecode(file.readAsStringSync()) as List<dynamic>;
  } catch (e) {
    logger.output('Corrupted JSON file ${file.path}, resetting: $e');
    file.writeAsStringSync('[]');
    return [];
  }
}

/// Async counterpart of [readJsonListFileSync].
Future<List<dynamic>> readJsonListFile(File file) async {
  try {
    return jsonDecode(await file.readAsString()) as List<dynamic>;
  } catch (e) {
    logger.output('Corrupted JSON file ${file.path}, resetting: $e');
    await file.writeAsString('[]');
    return [];
  }
}

/// Decodes [file] as a JSON map, resetting it to `{}` and returning an empty
/// map if the content is missing or corrupted, instead of letting the
/// exception crash startup.
Map<String, dynamic> readJsonMapFileSync(File file) {
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    logger.output('Corrupted JSON file ${file.path}, resetting: $e');
    file.writeAsStringSync('{}');
    return {};
  }
}

/// Async counterpart of [readJsonMapFileSync].
Future<Map<String, dynamic>> readJsonMapFile(File file) async {
  try {
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  } catch (e) {
    logger.output('Corrupted JSON file ${file.path}, resetting: $e');
    await file.writeAsString('{}');
    return {};
  }
}

String getFolderConfigPath(SourceType sourceType) {
  return '${appSupportDir.path}/${sourceType.name}/folder_config';
}

String getPlaylistConfigPath(SourceType sourceType) {
  return '${appSupportDir.path}/${sourceType.name}/playlist_config';
}

String getCachesPath(SourceType sourceType) {
  return '${appSupportDir.path}/${sourceType.name}/caches';
}

/// The root the listener picked for downloads, or null for the app's own
/// folder. Kept here rather than in the settings file so that every path
/// helper sees it without importing the data layer.
String? downloadRootDir;

/// Where a source's downloaded files live.
///
/// The default keeps each source in its own folder under the app's support
/// directory. A user-picked root is still split per source, so two libraries
/// never land in one folder and a file name collision cannot cross sources.
String getDownloadsPath(SourceType sourceType) {
  final root = downloadRootDir;
  // Joined rather than concatenated so Windows gets one consistent separator
  // in the path the settings row shows.
  return root == null || root.isEmpty
      ? p.join(appSupportDir.path, sourceType.name, 'downloads')
      : p.join(root, sourceType.name);
}

/// How a downloaded file is named inside the downloads folder.
///
/// Nothing stores the name: it is derived from the song, so a restart
/// recomputes the same path and a switch can rename what is already there.
/// [hash] is what every release before 4.15.4 wrote.
enum DownloadNaming {
  /// The md5 of the song id, without an extension.
  hash,

  /// "Artist - Title (a1b2c3d4).flac".
  artistTitle,

  /// "Artist/Album/01 Title (a1b2c3d4).flac".
  artistAlbumTrack,
}

/// Characters Windows refuses in a file name. Folders come from [p.joinAll]
/// rather than from a template, so a title can never create one by accident.
final _unsafeNameChars = RegExp(r'[\\/:*?"<>|]');
final _controlChars = RegExp(r'[\x00-\x1f]');

/// One readable, legal file name segment.
///
/// Trailing dots and spaces go because Windows drops them anyway, and a name
/// that differs from the one on disk is a file the app cannot find again.
String safeNameSegment(String value, {int maxLength = 96}) {
  var name = value
      .replaceAll(_unsafeNameChars, '_')
      .replaceAll(_controlChars, '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  while (name.isNotEmpty && (name.endsWith('.') || name.endsWith(' '))) {
    name = name.substring(0, name.length - 1);
  }
  if (name.length > maxLength) {
    name = name.substring(0, maxLength).trim();
  }
  return name;
}

/// Path of a download relative to the downloads folder.
///
/// The short hash is what keeps two songs with the same artist and title
/// apart: without it a second download would overwrite the first, and the app
/// would play one song while the list showed another.
String downloadRelativePath({
  required String id,
  required DownloadNaming naming,
  required String artist,
  required String title,
  required String album,
  int? track,
  String? format,
}) {
  final digest = md5.convert(utf8.encode(id)).toString();
  switch (naming) {
    case DownloadNaming.hash:
      return digest;
    case DownloadNaming.artistTitle:
      return '${safeNameSegment('$artist - $title')} '
          '(${digest.substring(0, 8)})${downloadExtension(format)}';
    case DownloadNaming.artistAlbumTrack:
      final segments = <String>[
        safeNameSegment(artist),
        safeNameSegment(album),
      ].where((segment) => segment.isNotEmpty).toList();
      final number = track == null
          ? ''
          : '${track.toString().padLeft(2, '0')} ';
      segments.add(
        '$number${safeNameSegment(title)} '
        '(${digest.substring(0, 8)})${downloadExtension(format)}',
      );
      return p.joinAll(segments);
  }
}

/// ".flac" when the source tells us the format, nothing when it does not.
String downloadExtension(String? format) {
  var extension = format?.trim().toLowerCase() ?? '';
  while (extension.startsWith('.')) {
    extension = extension.substring(1);
  }
  return extension.isEmpty
      ? ''
      : '.${safeNameSegment(extension, maxLength: 10)}';
}

String getPicturesPath(SourceType sourceType) {
  return '${appSupportDir.path}/${sourceType.name}/pictures';
}

String getSyncedFilePath(SourceType sourceType) {
  return '${appSupportDir.path}/${sourceType.name}/synced.keep';
}

final _httpClient = http.Client();

Future<String?> covertToRedirectPathIfNeed(String path) async {
  final request = http.Request('HEAD', Uri.parse(path))
    ..followRedirects = false
    ..headers.addAll(webdavClient?.headers ?? {});

  final response = await _httpClient.send(request);

  if (response.statusCode == 302) {
    final redirectLocation = response.headers['location'];
    if (redirectLocation != null) {
      return redirectLocation;
    }
  }
  return null;
}
