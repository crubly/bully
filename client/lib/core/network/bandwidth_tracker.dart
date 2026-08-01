import 'package:hive_flutter/hive_flutter.dart';

/// Tracks actual bytes moved over the relay WS connection (LAN sync/transfer
/// traffic is excluded — that's local-network, not the user's internet
/// data plan). Because of constant-rate padding, usage is fairly
/// predictable: roughly `frameSize * (1000ms / tickIntervalMs)` bytes/sec
/// per direction whether or not anything real is being sent — that
/// predictability (and the ability to *see* it here) is itself the tradeoff
/// being made for the "no observable timing" privacy property.
class BandwidthTracker {
  static late Box _box;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _box = await Hive.openBox('bandwidth');
    _initialized = true;
  }

  static String _todayKey() {
    // Stamped from wall-clock at call time by the caller-independent host
    // (DateTime.now() is fine here — this isn't inside a Workflow script).
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static void recordSent(int bytes) => _add('out:${_todayKey()}', bytes);
  static void recordReceived(int bytes) => _add('in:${_todayKey()}', bytes);

  static void _add(String key, int bytes) {
    final current = (_box.get(key) as int?) ?? 0;
    _box.put(key, current + bytes);
  }

  /// Total bytes (in + out) over the last [days] calendar days, including today.
  static int totalOverLastDays(int days) {
    var total = 0;
    final now = DateTime.now();
    for (var i = 0; i < days; i++) {
      final day = now.subtract(Duration(days: i));
      final key = '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      total += (_box.get('out:$key') as int?) ?? 0;
      total += (_box.get('in:$key') as int?) ?? 0;
    }
    return total;
  }
}
