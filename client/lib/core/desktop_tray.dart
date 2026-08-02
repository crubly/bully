import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Keeps background sync alive on desktop: a tray icon so the app stays
/// running (and reachable) after the window is closed instead of quitting,
/// plus (macOS only) registering as a login item so sync survives a reboot.
class DesktopTray with TrayListener, WindowListener {
  static final DesktopTray instance = DesktopTray._();
  DesktopTray._();

  bool get _isDesktop => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  Future<void> init() async {
    if (!_isDesktop) return;

    trayManager.addListener(this);
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);

    await trayManager.setIcon(Platform.isWindows ? 'assets/tray/icon.ico' : 'assets/tray/icon.png');
    await trayManager.setToolTip('Bully');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: 'Открыть Bully'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Выйти'),
    ]));

    if (Platform.isMacOS) {
      await _registerLoginItem();
    }
  }

  Future<void> _registerLoginItem() async {
    try {
      launchAtStartup.setup(
        appName: 'Bully',
        appPath: Platform.resolvedExecutable,
      );
      await launchAtStartup.enable();
    } catch (_) {

    }
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
        windowManager.focus();
        break;
      case 'quit':
        windowManager.setPreventClose(false);
        windowManager.close();
        break;
    }
  }

  @override
  void onWindowClose() async {
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    }
  }
}
