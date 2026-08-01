import 'package:hive_flutter/hive_flutter.dart';

class BandwidthTracker {
  static late Box _box;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _box = await Hive.openBox('bandwidth');
    _initialized = true;
  }

  static String _todayKey() {

    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static void recordSent(int bytes) => _add('out:${_todayKey()}', bytes);
  static void recordReceived(int bytes) => _add('in:${_todayKey()}', bytes);

  static void _add(String key, int bytes) {
    final current = (_box.get(key) as int?) ?? 0;
    _box.put(key, current + bytes);
  }

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
