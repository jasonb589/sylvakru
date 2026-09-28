import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/services/picture_load_scheduler.dart';
import 'package:sylvakru/base/services/stream_client.dart';
import 'package:sylvakru/base/services/webdav_client.dart';
import 'package:http/http.dart' as http;
import 'package:sylvakru/base/utils/path.dart';

final _httpClient = http.Client();
List<MyPicture> globalPictureList = [];

/// Bumped when a picture's bytes have landed.
///
/// The page colours are derived from the background picture, and that colour
/// cannot be computed before the file is there. Without this the theme kept the
/// grey it had painted while the cover was still loading.
final pictureLoadedNotifier = ValueNotifier(0);

class MyPicture {
  String id;
  bool isLoaded = false;
  bool isExist = false;
  String path = '';

  /// Set when the picture should be fetched from an absolute URL (an artist
  /// image reported by the server's metadata provider) instead of the source's
  /// own cover-art lookup.
  String? imageUrl;
  Color? color;
  Color? lowerLuminance;

  final changeNotifier = ValueNotifier(0);

  /// How many times the bytes have been asked for. A fetch that came back
  /// empty is worth another try - the server may simply have been busy - but
  /// not forever.
  int loadAttempts = 0;

  /// Attempts after which a picture that keeps coming back empty is taken as
  /// having nothing to show.
  static const int maxLoadAttempts = 3;

  MyPicture(this.id, {String? md5Hash}) {
    if (id.isEmpty) {
      isExist = false;
      isLoaded = true;
      color = Colors.grey;
      return;
    }
    md5Hash ??= md5.convert(utf8.encode(id)).toString();
    path = '${getPicturesPath(sourceType)}/$md5Hash';
    if (File(path).existsSync()) {
      isLoaded = true;
      isExist = true;
    } else {
      isExist = false;
    }
  }

  factory MyPicture.form(String id) {
    final md5Hash = md5.convert(utf8.encode(id)).toString();
    final picture = MyPicture(id, md5Hash: md5Hash);
    globalPictureList.add(picture);
    return picture;
  }

  /// Switches this picture to an absolute [url] reported by the server's
  /// metadata provider, and schedules the download.
  ///
  /// Used for artist images: the library itself has no artist cover art, so the
  /// only image available comes from the server's Last.fm integration.
  void useImageUrl(String url) {
    if (imageUrl == url) {
      return;
    }
    imageUrl = url;
    isLoaded = false;
    isExist = false;
    color = null;
    lowerLuminance = null;
    loadAttempts = 0;
    pictureLoadScheduler.resetPicture(this);
    loadPictureSafe(this);
  }

  void reset() {
    isLoaded = false;
    isExist = false;
    color = null;
    lowerLuminance = null;
    loadAttempts = 0;
    pictureLoadScheduler.resetPicture(this);
  }
}

Future<void> loadPictureSafe(MyPicture picture, {int? widgetId}) async {
  if (picture.isLoaded) {
    return;
  }
  return pictureLoadScheduler.load(
    picture.id,
    () => _loadPicture(picture),
    widgetId,
  );
}


/// Downloads raw bytes from an absolute URL.
Future<Uint8List?> downloadBytes(String url) async {
  try {
    final response = await _httpClient.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
  } catch (e) {
    logger.output(e.toString());
  }
  return null;
}

/// Where a picture's bytes come from.
///
/// The switch over the source types used to sit inside [_loadPicture]; it is a
/// seam now because the rules around it - an empty answer is not an answer,
/// attempts are capped, a colour is never remembered as grey - are what has to
/// be checkable, and none of them need a server to be tested.
Future<Uint8List?> Function(MyPicture picture) pictureBytesLoader =
    _fetchPictureBytes;

Future<Uint8List?> _fetchPictureBytes(MyPicture picture) async {
  switch (sourceType) {
    case _ when picture.imageUrl != null:
      // an absolute URL from the server's metadata provider, fetched with the
      // same HTTP client the stream sources use
      return await downloadBytes(picture.imageUrl!);
    case .local:
      return await readPictureAsync(picture.id);
    case .webdav:
      final tmpPath = await covertToRedirectPathIfNeed(picture.id);
      if (tmpPath == null) {
        return await readPictureAsync(
          picture.id,
          headers: webdavClient?.headers,
        );
      }
      return await readPictureAsync(tmpPath);
    default:
      return await streamClient?.getPictureBytes(picture.id);
  }
}

Future<void> _loadPicture(MyPicture picture) async {
  picture.loadAttempts++;
  try {
    final bytes = await pictureBytesLoader(picture);

    if (bytes != null) {
      final pictureFile = File(picture.path);
      if (!await pictureFile.exists()) {
        await pictureFile.create(recursive: true);
      }
      await pictureFile.writeAsBytes(bytes);
      picture.isExist = true;
      picture.isLoaded = true;
      // Pages take their colours from this picture: say that it has arrived so
      // the one waiting on it can stop showing the colour of nothing.
      pictureLoadedNotifier.value++;
      return;
    }
  } catch (e) {
    logger.output(e.toString());
  }

  // Nothing came back. That is not "this song has no artwork" but "this try did
  // not work": leaving the picture unloaded lets the next page ask again, and
  // the attempts are capped so a song that really has nothing does not become
  // one request per rebuild.
  picture.isLoaded = picture.loadAttempts >= MyPicture.maxLoadAttempts;
  if (!picture.isLoaded) {
    // Another go has to be a fresh request: the scheduler remembers this id as
    // loaded and would otherwise hand back the wait that has already finished.
    pictureLoadScheduler.resetPicture(picture);
  }
}

Future<Color> computeColor(MyPicture? picture) async {
  if (picture?.color != null) {
    return picture!.color!;
  }
  Uint8List? bytes;
  if (picture != null) {
    await loadPictureSafe(picture);
  }

  if (picture?.isExist == true) {
    final pictureFile = File(picture!.path);
    if (await pictureFile.exists()) {
      bytes = await pictureFile.readAsBytes();
    }
  }

  final colour = bytes == null ? null : await _calculateAverageColor(bytes);
  if (colour == null || picture == null) {
    // Grey is what the pages fall back to while there is nothing, but it must
    // not be remembered as this picture's colour: a cover that has not arrived
    // yet - or a folder that has just been re-read - would then be grey for
    // the rest of the session, which is exactly what happened after clearing
    // the cache. Leaving the colour unset means the next call asks again.
    return Colors.grey;
  }

  picture.color = colour;

  double r = colour.r;
  double g = colour.g;
  double b = colour.b;
  final luminance = 0.299 * r + 0.587 * g + 0.114 * b;

  const maxLuminance = 200 / 255.0;

  if (luminance > maxLuminance) {
    final factor = maxLuminance / luminance;

    picture.lowerLuminance = Color.from(
      alpha: colour.a,
      red: r * factor,
      green: g * factor,
      blue: b * factor,
    );
  }

  return colour;
}

/// The average colour of [bytes], or null when it cannot be read.
///
/// Null rather than grey: a cover that cannot be decoded today — a file still
/// being written, a cache that has just been cleared — may be readable a
/// moment later, and a remembered grey is what made that permanent.
Future<Color?> _calculateAverageColor(Uint8List bytes) async {
  final state = WidgetsBinding.instance.lifecycleState;

  if (Platform.isIOS && state != AppLifecycleState.resumed) {
    return _calculateWithImagePackage(bytes);
  }

  Uint8List buffer = Uint8List(0);
  ui.Codec? codec;
  try {
    codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 20,
      targetHeight: 20,
    );
    final frameInfo = await codec.getNextFrame();
    final image = frameInfo.image;

    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

    image.dispose();

    if (byteData == null) {
      return null;
    }

    buffer = byteData.buffer.asUint8List();
  } catch (e) {
    logger.output(e.toString());
    return null;
  } finally {
    codec?.dispose();
  }

  double r = 0;
  double g = 0;
  double b = 0;
  int count = 0;

  for (int i = 0; i < buffer.length; i += 4) {
    final red = buffer[i];
    final green = buffer[i + 1];
    final blue = buffer[i + 2];
    final alpha = buffer[i + 3];

    if (alpha == 0) {
      r += 128;
      g += 128;
      b += 128;
    } else {
      r += red;
      g += green;
      b += blue;
    }

    count++;
  }

  if (count == 0) {
    return null;
  }
  return Color.fromARGB(
    255,
    (r / count).round(),
    (g / count).round(),
    (b / count).round(),
  );
}

Color? _calculateWithImagePackage(Uint8List bytes) {
  final image = img.decodeImage(bytes);

  if (image == null) {
    return null;
  }

  final thumb = img.copyResize(
    image,
    width: 20,
    height: 20,
    interpolation: img.Interpolation.average,
  );

  double r = 0;
  double g = 0;
  double b = 0;
  int count = 0;

  for (final pixel in thumb) {
    if (pixel.a == 0) {
      r += 128;
      g += 128;
      b += 128;
    } else {
      r += pixel.r;
      g += pixel.g;
      b += pixel.b;
    }

    count++;
  }

  if (count == 0) {
    return null;
  }

  return Color.fromARGB(
    255,
    (r / count).round(),
    (g / count).round(),
    (b / count).round(),
  );
}
