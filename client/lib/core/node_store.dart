import 'package:hive_flutter/hive_flutter.dart';

class BullyNode {
  final String name;
  final String url;
  BullyNode(this.name, this.url);

  Map<String, dynamic> toMap() => {'name': name, 'url': url};
  static BullyNode fromMap(Map map) => BullyNode(map['name'] as String, map['url'] as String);
}

/// Local-only list of known Bully nodes (backend instances) plus which one
/// is currently active. Node URLs aren't secret, so this lives in a plain
/// Hive box rather than secure storage.
class NodeStore {
  static late Box _box;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _box = await Hive.openBox('nodes');
    _initialized = true;
  }

  static List<BullyNode> list() {
    final raw = (_box.get('list') as List?) ?? [];
    return raw.map((n) => BullyNode.fromMap(Map<String, dynamic>.from(n as Map))).toList();
  }

  static Future<void> add(BullyNode node) async {
    final nodes = list().where((n) => n.url != node.url).toList()..add(node);
    await _box.put('list', nodes.map((n) => n.toMap()).toList());
  }

  static String? activeUrl() => _box.get('active') as String?;

  static Future<void> setActive(String url) => _box.put('active', url);

  static BullyNode? active() {
    final url = activeUrl();
    if (url == null) return null;
    for (final n in list()) {
      if (n.url == url) return n;
    }
    return null;
  }
}
