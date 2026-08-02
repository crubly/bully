import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../crypto/session_manager.dart';
import '../network/ws_client.dart';
import '../storage/chat_history_store.dart';

const _uuid = Uuid();

/// Decrypts and persists incoming DM messages as soon as they arrive over
/// the WebSocket, regardless of whether a DmChatScreen for that
/// conversation happens to be open. Without this, a message that arrived
/// while the recipient was anywhere else in the app (chat list, settings,
/// a different chat) was silently dropped — nothing was listening for it,
/// so it never reached ChatHistoryStore and looked "lost" even though the
/// server had delivered it correctly.
class MessageInbox {
  final WsClient ws;
  final CryptoSessionManager crypto;
  final _updates = StreamController<String>.broadcast();
  StreamSubscription<RelayEnvelope>? _sub;

  MessageInbox(this.ws, this.crypto) {
    _sub = ws.messages.listen(_handle);
  }

  /// Fires with the conversationId whenever a new DM message was persisted.
  Stream<String> get onConversationUpdated => _updates.stream;

  Future<void> _handle(RelayEnvelope env) async {
    if (env.type != 'message') return;
    if (env.header == null || env.ciphertext == null) return;
    if (env.messageId != null && ChatHistoryStore.messagesFor(env.conversationId).any((m) => m.id == env.messageId)) {
      return;
    }
    if (!(await crypto.hasSession(env.conversationId))) return;

    try {
      final header = base64Decode(env.header!);
      final ciphertext = base64Decode(env.ciphertext!);
      final plaintext = await crypto.decrypt(env.conversationId, header, ciphertext);
      await ChatHistoryStore.append(MessageRecord(
        id: env.messageId ?? _uuid.v4(),
        conversationId: env.conversationId,
        senderId: env.fromUserId,
        text: plaintext,
        isMine: false,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (_) {
      return;
    }
    _updates.add(env.conversationId);
  }

  void dispose() {
    _sub?.cancel();
    _updates.close();
  }
}
