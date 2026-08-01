import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:window_manager/window_manager.dart';

class DesktopWindow {
  static bool get isDesktop => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  static Future<void> ensureInitialized() async {
    if (!isDesktop) return;
    await windowManager.ensureInitialized();
  }

  static Future<void> setTitle(String title) async {
    if (!isDesktop) return;
    await windowManager.setTitle(title);
  }
}
