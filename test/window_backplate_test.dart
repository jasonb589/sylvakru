import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/design/window_backplate.dart';
import 'package:sylvakru/base/services/color_manager.dart';

/// The window is not guaranteed to be opaque: on Windows a transparent window
/// background colour becomes an accent-transparentgradient, so every
/// translucent pixel in the client composites against the desktop. These tests
/// keep the client's own base opaque, and keep the mini window the only one
/// that asks the system for a transparent window.
void main() {
  setUp(() {
    backgroundCoverArtColor = Colors.grey;
    mainPageThemeNotifier.value = .vivid;
  });

  tearDown(() {
    backgroundCoverArtColor = Colors.grey;
    mainPageThemeNotifier.value = .vivid;
  });

  group('the window backplate colour', () {
    test('is fully opaque in every theme', () {
      for (final theme in ThemeType.values) {
        mainPageThemeNotifier.value = theme;
        expect(
          colorManager.getWindowBackplateColor().a,
          1.0,
          reason: '$theme must not leave the window see-through',
        );
      }
    });

    test('stays opaque whatever the cover colour pipeline hands out', () {
      for (final cover in [
        Colors.grey,
        Colors.transparent,
        const Color(0xFF3A2B1F),
        Colors.white,
      ]) {
        backgroundCoverArtColor = cover;
        expect(colorManager.getWindowBackplateColor().a, 1.0, reason: '$cover');
      }
    });
  });

  testWidgets('WindowBackplate paints the opaque colour it is given', (
    tester,
  ) async {
    await tester.pumpWidget(
      const WindowBackplate(color: Color(0xFFF5F5F5), child: SizedBox.expand()),
    );

    final box = tester.widget<ColoredBox>(find.byType(ColoredBox));
    expect(box.color, const Color(0xFFF5F5F5));
    expect(box.color.a, 1.0);
  });

  group('source guards', () {
    String read(String path) => File(path).readAsStringSync();

    test('the main window only asks for transparency in mini mode', () {
      final source = read('lib/main.dart');
      final start = source.indexOf('Future<void> _setupWindow(');
      final end = source.indexOf('Future<void> _setupDesktopLyricsWindow(');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final setup = source.substring(start, end);

      expect(
        setup.contains('backgroundColor: Colors.transparent'),
        isFalse,
        reason:
            'a bare transparent value makes Windows composite the window '
            'with alpha, which is what showed the desktop behind the player',
      );
      expect(setup.contains('viewModeNotifier.value == .mini'), isTrue);
      expect(setup.contains('getWindowBackplateColor()'), isTrue);

      // The desktop lyrics window is a window of its own and is meant to be
      // transparent, so it keeps asking for it.
      final lyrics = source.substring(end);
      expect(lyrics.contains('backgroundColor: Colors.transparent'), isTrue);
    });

    test('every full-size surface sits on the backplate, mini does not', () {
      final source = read('lib/view_entry.dart');
      for (final surface in [
        'backplate(firstLaunchView())',
        'backplate(BigPictureView())',
        'backplate(SafeArea(child: BigPictureView()))',
        'backplate(PortraitView())',
        'backplate(LandscapeView())',
        'backplate(SafeArea(child: LandscapeView()))',
      ]) {
        expect(source.contains(surface), isTrue, reason: surface);
      }

      expect(source.contains('return MiniView();'), isTrue);
      expect(
        source.contains('backplate(MiniView())'),
        isFalse,
        reason: 'the mini window is meant to float on the desktop',
      );
    });

    test('switching mini mode keeps the window backplate in step', () {
      final titleBar = read('lib/landscape_view/title_bar.dart');
      expect(titleBar.contains('windowManager.setBackgroundColor'), isTrue);
      expect(titleBar.contains('Colors.transparent'), isTrue);

      final miniView = read('lib/mini_view/mini_view.dart');
      expect(miniView.contains('windowManager.setBackgroundColor'), isTrue);
      expect(miniView.contains('getWindowBackplateColor()'), isTrue);
    });
  });
}
