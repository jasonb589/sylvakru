import 'dart:io';

import 'package:sylvakru/base/services/exit.dart';
import 'package:sylvakru/base/services/my_window_listener.dart';
import 'package:sylvakru/base/services/taskbar_service.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class MyTrayListener extends TrayListener {
  @override
  void onTrayIconMouseDown() async {
    await windowManager.show();
    windowIsClosed = false;
    if (Platform.isWindows) {
      await Future.delayed(Duration(milliseconds: 300));
      setupTaskbar();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    // ignore: deprecated_member_use
    trayManager.popUpContextMenu(bringAppToFront: true);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show') {
      await windowManager.show();
      windowIsClosed = false;
      if (Platform.isWindows) {
        await Future.delayed(Duration(milliseconds: 300));
        setupTaskbar();
      }
    } else if (menuItem.key == 'exit') {
      exitApp();
    }
  }
}
