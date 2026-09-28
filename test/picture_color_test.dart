import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/services/picture_load_scheduler.dart';
import 'package:sylvakru/base/services/picture_service.dart';
import 'package:sylvakru/base/utils/path.dart';

/// An unknown colour must never be remembered as a picture's colour.
///
/// Remembering grey is what turned a cover that had not arrived yet — or a
/// library that had just been re-read after clearing the cache — into a grey
/// theme for the rest of the session. The bytes are stubbed here: the rules
/// around them are what matters, and none of them needs a server.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    appSupportDir = Directory.systemTemp.createTempSync('sylvakru_colour');
    await logger.init();
  });

  setUp(() {
    sourceType = SourceType.navidrome;
    isStreamSource = true;
    isNotStreamSource = false;
    final pictures = Directory(getPicturesPath(sourceType));
    if (!pictures.existsSync()) {
      pictures.createSync(recursive: true);
    }
  });

  group('computeColor', () {
    test('never remembers grey for a cover that is not there yet', () async {
      pictureBytesLoader = (_) async => null;
      final picture = MyPicture('album-without-a-file');

      final colour = await computeColor(picture);

      expect(colour, Colors.grey);
      expect(
        picture.color,
        isNull,
        reason: 'a grey that was remembered is grey forever',
      );
    });

    test('asks again while the attempts last, then gives up', () async {
      var fetches = 0;
      pictureBytesLoader = (_) async {
        fetches++;
        return null;
      };
      final picture = MyPicture('album-that-keeps-failing');

      await computeColor(picture);
      expect(fetches, 1);
      expect(
        picture.isLoaded,
        isFalse,
        reason: 'the next page still gets a chance',
      );

      await computeColor(picture);
      expect(fetches, 2);

      await computeColor(picture);
      expect(picture.loadAttempts, MyPicture.maxLoadAttempts);
      expect(picture.isLoaded, isTrue);

      await computeColor(picture);
      expect(
        fetches,
        MyPicture.maxLoadAttempts,
        reason: 'a song with no artwork is not a request per rebuild',
      );
    });

    test('remembers a cover that arrived, and says so', () async {
      pictureBytesLoader = (_) async => Uint8List.fromList([1, 2, 3, 4]);
      final picture = MyPicture('album-with-artwork');
      var arrivals = 0;
      pictureLoadedNotifier.addListener(() => arrivals++);

      await computeColor(picture);

      expect(picture.isLoaded, isTrue);
      expect(picture.isExist, isTrue);
      expect(File(picture.path).existsSync(), isTrue);
      expect(
        arrivals,
        1,
        reason: 'the page painted from this cover has to hear about it',
      );
    });

    test('reuses a colour it already knows', () async {
      var fetches = 0;
      pictureBytesLoader = (_) async {
        fetches++;
        return null;
      };
      final picture = MyPicture('album-with-a-known-colour')
        ..color = const Color(0xFF123456);

      expect(await computeColor(picture), const Color(0xFF123456));
      expect(fetches, 0);
    });

    test('a cover that cannot be decoded is not remembered as grey', () async {
      pictureBytesLoader = (_) async => null;
      final picture = MyPicture('broken-artwork');
      File(picture.path).writeAsBytesSync(List<int>.generate(64, (i) => i * 7));

      final colour = await computeColor(picture);

      expect(colour, Colors.grey);
      expect(
        picture.color,
        isNull,
        reason: 'an unreadable file may be readable later',
      );
    });
  });

  group('PictureLoadScheduler', () {
    test(
      'lets its caller go when the widget that asked for it is gone',
      () async {
        final scheduler = PictureLoadScheduler();
        final gates = <Completer<void>>[];
        final running = <Future<void>>[];
        for (var i = 0; i < scheduler.maxConcurrent; i++) {
          final gate = Completer<void>();
          gates.add(gate);
          running.add(scheduler.load('block$i', () => gate.future, 100 + i));
        }

        var fetched = false;
        final queued = scheduler.load('queued', () async {
          fetched = true;
        }, 999);
        scheduler.cancel(999);

        gates.first.complete();
        await running.first;

        // Without the release this never returns: the future a page joined would
        // stay pending for the rest of the session.
        await queued.timeout(const Duration(seconds: 2));
        expect(fetched, isFalse);

        for (final gate in gates.skip(1)) {
          gate.complete();
        }
        await Future.wait(running.skip(1));
      },
    );
  });
}
