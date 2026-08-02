import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

class AppIconController {
  static const _channel = MethodChannel('bully/app_icon');

  static bool get isSupported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  static Future<String> currentIcon() async {
    if (!isSupported) return 'default';
    final result = await _channel.invokeMethod<String>('currentIcon');
    return result ?? 'default';
  }

  static Future<void> setIcon(String name) async {
    if (!isSupported) return;
    await _channel.invokeMethod('setIcon', {'name': name});
  }
}
