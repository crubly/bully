import 'package:hive_flutter/hive_flutter.dart';

/// One persisted chat message. Stored decrypted (this is the whole point —
/// history lives locally on-device, the server never keeps plaintext).
class MessageRecord {
  final String id;
  final String conversationId;
  final String senderId;
  final String text;
  final bool isMine;
  final int timestampMs;

  MessageRecord({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.text,
    required this.isMine,
    required this.timestampMs,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'text': text,
        'is_mine': isMine,
        'ts': timestampMs,
      };

  static MessageRecord fromMap(Map map) => MessageRecord(
        id: map['id'] as String,
        conversationId: map['conversation_id'] as String,
        senderId: map['sender_id'] as String,
        text: map['text'] as String,
        isMine: map['is_mine'] as bool,
        timestampMs: map['ts'] as int,
      );
}

/// Local-only chat history. Nothing here is ever sent to the relay server —
/// it's read/written straight to an on-device Hive box, and is also what
/// the LAN device-transfer/sync feature reads from and writes into.
class ChatHistoryStore {
  static late Box _box;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter('bully');
    _box = await Hive.openBox('chat_messages');
    _initialized = true;
  }

  static List<MessageRecord> messagesFor(String conversationId) {
    final raw = (_box.get(conversationId) as List?) ?? [];
    return raw.map((m) => MessageRecord.fromMap(Map<String, dynamic>.from(m as Map))).toList();
  }

  static Future<void> append(MessageRecord message) async {
    final existing = messagesFor(message.conversationId);
    if (existing.any((m) => m.id == message.id)) return; // dedupe (offline replay / LAN sync)
    existing.add(message);
    existing.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    await _box.put(message.conversationId, existing.map((m) => m.toMap()).toList());
  }

  /// Merges a batch of records (e.g. from LAN sync) in one write, deduping
  /// by message id.
  static Future<void> mergeAll(String conversationId, List<MessageRecord> incoming) async {
    final existing = messagesFor(conversationId);
    final seen = existing.map((m) => m.id).toSet();
    final merged = [...existing, ...incoming.where((m) => !seen.contains(m.id))];
    merged.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    await _box.put(conversationId, merged.map((m) => m.toMap()).toList());
  }

  static List<String> allConversationIds() => _box.keys.cast<String>().toList();

  /// Full local history export/import for the LAN device-transfer feature.
  static Map<String, List<Map<String, dynamic>>> exportAll() {
    return {
      for (final id in allConversationIds()) id: messagesFor(id).map((m) => m.toMap()).toList(),
    };
  }

  static Future<void> importAll(Map<String, dynamic> data) async {
    for (final entry in data.entries) {
      final records = (entry.value as List).map((m) => MessageRecord.fromMap(Map<String, dynamic>.from(m as Map))).toList();
      await mergeAll(entry.key, records);
    }
  }
}
