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

  /// The colours this picture's backdrop drifts between, set by
  /// [computePalette] and reset with [color] wherever that is reset.
  List<Color>? palette;

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
    palette = null;
    pictureLoadScheduler.resetPicture(this);
    loadPictureSafe(this);
  }

  void reset() {
    isLoaded = false;
    isExist = false;
    color = null;
    lowerLuminance = null;
    palette = null;
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

/// Sampling resolution and bucket count for [computePalette]: small enough to
/// stay cheap next to decoding the artwork itself.
const int _paletteSampleSize = 48;
const int _paletteBuckets = 512;

/// The colours a backdrop can be built from: the [computeColor] average first,
/// then up to three that are visibly different from it.
///
/// One flat tint made the full-screen backdrop read as a solid panel; a cover
/// with several colours deserves several, and a drifting gradient needs
/// somewhere to drift to. Cached beside [MyPicture.color] and reset with it, so
/// the palette always belongs to the artwork currently on screen.
Future<List<Color>> computePalette(MyPicture? picture) async {
  if (picture?.palette != null) {
    return picture!.palette!;
  }

  Uint8List? bytes;
  if (picture != null) {
    await loadPictureSafe(picture);
    if (picture.isExist) {
      final file = File(picture.path);
      if (await file.exists()) {
        bytes = await file.readAsBytes();
      }
    }
  }

  if (bytes == null) {
    final fallback = [picture?.color ?? Colors.grey];
    picture?.palette = fallback;
    return fallback;
  }

  final palette = await _calculatePalette(bytes);
  picture?.palette = palette;
  return palette;
}

/// The average colour first, then the busiest colours far enough from it to be
/// told apart.
Future<List<Color>> _calculatePalette(Uint8List bytes) async {
  final base = await _calculateAverageColor(bytes);

  if (Platform.isIOS &&
      WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
    // The codec path below needs a resumed app; a surface nobody can see does
    // not need more than its tint.
    return [base];
  }

  Uint8List buffer;
  ui.Codec? codec;
  try {
    codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: _paletteSampleSize,
      targetHeight: _paletteSampleSize,
    );
    final frameInfo = await codec.getNextFrame();
    final image = frameInfo.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (byteData == null) {
      return [base];
    }
    buffer = byteData.buffer.asUint8List();
  } catch (e) {
    logger.output(e.toString());
    return [base];
  } finally {
    codec?.dispose();
  }

  // Three bits per channel, so a gradient in the artwork lands in one bucket
  // instead of smearing over several.
  final redTotal = List<double>.filled(_paletteBuckets, 0);
  final greenTotal = List<double>.filled(_paletteBuckets, 0);
  final blueTotal = List<double>.filled(_paletteBuckets, 0);
  final count = List<int>.filled(_paletteBuckets, 0);

  for (int i = 0; i + 3 < buffer.length; i += 4) {
    final alpha = buffer[i + 3];
    // Fully transparent pixels are not part of the artwork; the average above
    // treats them as mid grey, and so does this.
    final red = alpha == 0 ? 128 : buffer[i];
    final green = alpha == 0 ? 128 : buffer[i + 1];
    final blue = alpha == 0 ? 128 : buffer[i + 2];
    final key = (red >> 5) * 64 + (green >> 5) * 8 + (blue >> 5);
    redTotal[key] += red;
    greenTotal[key] += green;
    blueTotal[key] += blue;
    count[key]++;
  }

  final order = List<int>.generate(_paletteBuckets, (i) => i)
    ..sort((a, b) => count[b].compareTo(count[a]));

  // Two nearly identical colours would drift without anything appearing to
  // move, so each extra colour has to be a visible step away from the ones
  // already picked.
  const minDistanceSquared = 70.0 * 70.0;
  final colours = <Color>[base];
  for (final key in order) {
    if (count[key] == 0 || colours.length == 4) {
      break;
    }
    final candidate = Color.fromARGB(
      255,
      (redTotal[key] / count[key]).round(),
      (greenTotal[key] / count[key]).round(),
      (blueTotal[key] / count[key]).round(),
    );
    final distinct = colours.every(
      (colour) => _distanceSquared(colour, candidate) >= minDistanceSquared,
    );
    if (distinct) {
      colours.add(candidate);
    }
  }

  return colours;
}

/// The squared distance between two colours, in 0-255 channel units.
double _distanceSquared(Color a, Color b) {
  final red = (a.r - b.r) * 255;
  final green = (a.g - b.g) * 255;
  final blue = (a.b - b.b) * 255;
  return red * red + green * green + blue * blue;
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
