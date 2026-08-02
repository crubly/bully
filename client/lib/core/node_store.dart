import 'package:hive_flutter/hive_flutter.dart';

class BullyNode {
  final String name;
  final String url;
  final bool flaggedCompromised;
  final String? flagReason;
  BullyNode(this.name, this.url, {this.flaggedCompromised = false, this.flagReason});

  Map<String, dynamic> toMap() => {
        'name': name,
        'url': url,
        'flagged_compromised': flaggedCompromised,
        'flag_reason': flagReason,
      };

  static BullyNode fromMap(Map map) => BullyNode(
        map['name'] as String,
        map['url'] as String,
        flaggedCompromised: (map['flagged_compromised'] as bool?) ?? false,
        flagReason: map['flag_reason'] as String?,
      );
}

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
    final existing = list();
    BullyNode? previous;
    for (final n in existing) {
      if (n.url == node.url) previous = n;
    }
    final merged = previous != null && !node.flaggedCompromised
        ? BullyNode(node.name, node.url, flaggedCompromised: previous.flaggedCompromised, flagReason: previous.flagReason)
        : node;
    final nodes = existing.where((n) => n.url != node.url).toList()..add(merged);
    await _box.put('list', nodes.map((n) => n.toMap()).toList());
  }

  static Future<void> setFlagged(String url, bool flagged, {String? reason}) async {
    final nodes = list();
    final updated = nodes
        .map((n) => n.url == url ? BullyNode(n.name, n.url, flaggedCompromised: flagged, flagReason: flagged ? reason : null) : n)
        .toList();
    await _box.put('list', updated.map((n) => n.toMap()).toList());
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
