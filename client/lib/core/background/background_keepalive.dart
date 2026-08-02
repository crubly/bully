import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

const _channel = MethodChannel('bully/background');

/// Android: starts/stops a foreground service that keeps this process (and
/// its already-open WebSocket + call signaling) alive and unthrottled in
/// the background — no push notifications involved, the same connection
/// just keeps running. No-op on every other platform: desktop already
/// stays alive via the tray icon (DesktopTray), iOS has no equivalent API
/// without VoIP push, so background delivery there stays best-effort.
class BackgroundKeepAlive {
  static Future<void> start() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('start');
    } catch (_) {

    }
  }

  static Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {

    }
  }
}
