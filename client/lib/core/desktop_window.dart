import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:window_manager/window_manager.dart';

class DesktopWindow {
  static bool get isDesktop => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  static final title = ValueNotifier<String>('Bully');

  static Future<void> ensureInitialized() async {
    if (!isDesktop) return;
    await windowManager.ensureInitialized();
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
  }

  static Future<void> setTitle(String newTitle) async {
    if (!isDesktop) return;
    title.value = newTitle;
    await windowManager.setTitle(newTitle);
  }

  static Future<void> startDragging() => windowManager.startDragging();

  static Future<void> minimize() => windowManager.minimize();

  static Future<void> toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  static Future<void> close() => windowManager.close();
}
