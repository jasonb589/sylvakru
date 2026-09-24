import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/landscape_view/desktop_lyrics.dart';

void main() {
  // A 1920x1080 primary display whose taskbar eats the bottom 40px, so the
  // work area ends at y=1040.
  const primary = Rect.fromLTWH(0, 0, 1920, 1040);
  const size = Size(360, 110);

  group('desktopLyricsCenteredPosition', () {
    test('centres horizontally on the work area', () {
      final position = desktopLyricsCenteredPosition(primary, size);

      expect(position.dx, (1920 - 360) / 2);
    });

    test('sits just above the taskbar, not touching it', () {
      final position = desktopLyricsCenteredPosition(primary, size);

      // bottom edge = work-area bottom - gap
      expect(
        position.dy + size.height,
        primary.bottom - desktopLyricsTaskbarGap,
      );
      expect(position.dy + size.height, lessThan(primary.bottom));
    });

    test('accounts for a work area that does not start at the origin', () {
      // a secondary display placed to the right of the primary one
      const secondary = Rect.fromLTWH(1920, 0, 1280, 984);
      final position = desktopLyricsCenteredPosition(secondary, size);

      expect(position.dx, 1920 + (1280 - 360) / 2);
      expect(position.dy + size.height, secondary.bottom - desktopLyricsTaskbarGap);
    });
  });

  group('desktopLyricsPosition', () {
    test('falls back to the centred default when nothing was saved', () {
      final position = desktopLyricsPosition(
        size: size,
        saved: null,
        primaryWorkArea: primary,
        workAreas: const [primary],
      );

      expect(position, desktopLyricsCenteredPosition(primary, size));
    });

    test('honours a saved position that is still on screen', () {
      const saved = Offset(100, 200);
      final position = desktopLyricsPosition(
        size: size,
        saved: saved,
        primaryWorkArea: primary,
        workAreas: const [primary],
      );

      expect(position, saved);
    });

    test('honours a saved position on a second monitor', () {
      const secondary = Rect.fromLTWH(1920, 0, 1280, 984);
      const saved = Offset(2000, 300);
      final position = desktopLyricsPosition(
        size: size,
        saved: saved,
        primaryWorkArea: primary,
        workAreas: const [primary, secondary],
      );

      expect(position, saved);
    });

    test('drops a saved position whose monitor is gone', () {
      // dragged onto a second monitor, which is then unplugged: the window must
      // not reopen off-screen where it can never be reached
      const saved = Offset(2000, 300);
      final position = desktopLyricsPosition(
        size: size,
        saved: saved,
        primaryWorkArea: primary,
        workAreas: const [primary],
      );

      expect(position, desktopLyricsCenteredPosition(primary, size));
    });

    test('drops a saved position that is off every work area', () {
      const saved = Offset(-5000, -5000);
      final position = desktopLyricsPosition(
        size: size,
        saved: saved,
        primaryWorkArea: primary,
        workAreas: const [primary],
      );

      expect(position, desktopLyricsCenteredPosition(primary, size));
    });
  });
}
