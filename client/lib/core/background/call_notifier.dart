import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Fires a high-priority local notification for an incoming call so it
/// still rings/alerts while the app is backgrounded (kept alive by
/// BackgroundKeepAlive on Android). Tapping it just brings the app back to
/// the foreground — the existing in-app accept/decline dialog (wired to
/// CallController.incomingCalls, which keeps running since the process
/// itself is never killed) handles the rest. There is no PushKit/FCM here,
/// so this only works while the process is alive, not after it's killed.
class CallNotifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    ));
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static Future<void> showIncomingCall({required String title, required String body}) async {
    await _plugin.show(
      1001,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'bully_calls',
          'Звонки',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
        ),
        iOS: DarwinNotificationDetails(presentSound: true, interruptionLevel: InterruptionLevel.timeSensitive),
      ),
    );
  }

  static Future<void> cancelIncomingCall() async {
    await _plugin.cancel(1001);
  }
}
