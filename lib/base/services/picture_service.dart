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

  factory MyPicture.form(String id, {String? md5Hash}) {
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
    pictureLoadScheduler.resetPicture(this);
    loadPictureSafe(this);
  }

  void reset() {
    isLoaded = false;
    isExist = false;
    color = null;
    lowerLuminance = null;
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
Future<void> _loadPicture(MyPicture picture) async {
  try {
    Uint8List? bytes;

    switch (sourceType) {
      case _ when picture.imageUrl != null:
        // an absolute URL from the server's metadata provider, fetched with the
        // same HTTP client the stream sources use
        bytes = await downloadBytes(picture.imageUrl!);
        break;
      case .local:
        bytes = await readPictureAsync(picture.id);
        break;
      case .webdav:
        final tmpPath = await covertToRedirectPathIfNeed(picture.id);
        if (tmpPath == null) {
          bytes = await readPictureAsync(
            picture.id,
            headers: webdavClient?.headers,
          );
        } else {
          bytes = await readPictureAsync(tmpPath);
        }
        break;
      default:
        bytes = await streamClient?.getPictureBytes(picture.id);
        break;
    }

    if (bytes != null) {
      File pictureFile = File(picture.path);
      if (!await pictureFile.exists()) {
        await pictureFile.create(recursive: true);
      }
      await pictureFile.writeAsBytes(bytes);
      picture.isExist = true;
    }
  } catch (e) {
    logger.output(e.toString());
  }
  picture.isLoaded = true;
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
    File pictureFile = File(picture!.path);
    if (await pictureFile.exists()) {
      bytes = await pictureFile.readAsBytes();
    }
  }

  if (bytes == null) {
    picture?.color = Colors.grey;
    return Colors.grey;
  }

  final color = await _calculateAverageColor(bytes);
  picture!.color = color;

  double r = color.r;
  double g = color.g;
  double b = color.b;
  final luminance = 0.299 * r + 0.587 * g + 0.114 * b;

  const maxLuminance = 200 / 255.0;

  if (luminance > maxLuminance) {
    final factor = maxLuminance / luminance;

    picture.lowerLuminance = Color.from(
      alpha: color.a,
      red: r * factor,
      green: g * factor,
      blue: b * factor,
    );
  }

  return color;
}

Future<Color> _calculateAverageColor(Uint8List bytes) async {
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
      return Colors.grey;
    }

    buffer = byteData.buffer.asUint8List();
  } catch (e) {
    logger.output(e.toString());
    return Colors.grey;
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
    return Colors.grey;
  }
  return Color.fromARGB(
    255,
    (r / count).round(),
    (g / count).round(),
    (b / count).round(),
  );
}

Color _calculateWithImagePackage(Uint8List bytes) {
  final image = img.decodeImage(bytes);

  if (image == null) {
    return Colors.grey;
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
    return Colors.grey;
  }

  return Color.fromARGB(
    255,
    (r / count).round(),
    (g / count).round(),
    (b / count).round(),
  );
}
