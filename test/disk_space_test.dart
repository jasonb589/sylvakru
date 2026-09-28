import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/services/disk_space_service.dart';
import 'package:sylvakru/base/utils/disk_space.dart';

/// The disk-space reminder behind the download centre.
///
/// The figure comes from the platform, so what matters here is the arithmetic
/// around it: reading `df` output correctly, and treating "cannot answer" as
/// unknown rather than as a full disk.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(() {
    appSupportDir = Directory.systemTemp.createTempSync('sylvakru_disk');
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(diskSpaceChannel, null);
  });

  group('parseDfFreeBytes', () {
    test('reads the available figure out of POSIX df output', () {
      const output =
          'Filesystem     1024-blocks      Used Available Capacity  Mounted on\n'
          '/dev/disk1s5s1   488245288 379123456  42246032      91%   /\n';

      expect(parseDfFreeBytes(output), 42246032 * 1024);
    });

    test('is not shifted by a space in a device name or a mount point', () {
      const output =
          'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
          'server:/my volume 976762584 100 976662484 1% /Volumes/My Stuff\n';

      expect(parseDfFreeBytes(output), 976662484 * 1024);
    });

    test('is unknown when there is no data line to read', () {
      expect(parseDfFreeBytes(''), isNull);
      expect(
        parseDfFreeBytes(
          'Filesystem 1024-blocks Used Available Capacity Mounted on\n',
        ),
        isNull,
      );
    });
  });

  group('isDiskSpaceLow', () {
    test('warns below the line and stays quiet above it', () {
      expect(
        isDiskSpaceLow(freeBytes: 900 * 1024 * 1024, thresholdMb: 1024),
        isTrue,
      );
      expect(
        isDiskSpaceLow(freeBytes: 4 * 1024 * 1024 * 1024, thresholdMb: 1024),
        isFalse,
      );
    });

    test('an unknown figure never warns', () {
      expect(isDiskSpaceLow(freeBytes: null, thresholdMb: 1024), isFalse);
    });

    test('a threshold of zero turns the reminder off', () {
      expect(isDiskSpaceLow(freeBytes: 0, thresholdMb: 0), isFalse);
    });
  });

  group('readFreeSpaceBytes', () {
    test('answers with what the platform reports', () async {
      messenger.setMockMethodCallHandler(diskSpaceChannel, (call) async {
        expect(call.method, 'freeSpace');
        expect((call.arguments as Map)['path'], r'C:\downloads');
        return 123456789;
      });

      final bytes = await readFreeSpaceBytes(r'C:\downloads');

      expect(bytes, 123456789);
    }, skip: !Platform.isWindows);

    test('a channel nobody implements is unknown, not an error', () async {
      // No handler at all: the platform cannot answer, and the reminder is
      // what has to give way, not the download.
      final bytes = await readFreeSpaceBytes(r'C:\no\such\place');

      expect(bytes, isNull);
    }, skip: !Platform.isWindows);
  });

  group('refreshDiskFreeSpace', () {
    test('reads the volume once and reuses the answer', () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(diskSpaceChannel, (call) async {
        calls++;
        return 42 * 1024 * 1024;
      });

      await refreshDiskFreeSpace(force: true);
      await refreshDiskFreeSpace();

      expect(calls, 1);
      expect(diskFreeSpaceBytesNotifier.value, 42 * 1024 * 1024);
    }, skip: !Platform.isWindows);

    test('keeps the last known figure when a later read fails', () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(diskSpaceChannel, (call) async {
        calls++;
        return calls == 1 ? 7 * 1024 * 1024 : null;
      });

      await refreshDiskFreeSpace(force: true);
      await refreshDiskFreeSpace(force: true);

      expect(calls, 2);
      expect(diskFreeSpaceBytesNotifier.value, 7 * 1024 * 1024);
    }, skip: !Platform.isWindows);

    test('names the folder that matters, not the app folder', () {
      expect(diskSpaceTargetPath(), appSupportDir.path);
    });
  });

  group('existingAncestor', () {
    test('walks up to a folder that is there', () {
      final root = Directory.systemTemp.createTempSync('sylvakru_disk_yet');
      addTearDown(() => root.deleteSync(recursive: true));

      final missing =
          '${root.path}${Platform.pathSeparator}not${Platform.pathSeparator}there';

      expect(existingAncestor(missing), root.path);
      expect(existingAncestor(root.path), root.path);
    });
  });
}
