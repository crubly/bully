import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_services.dart';
import '../../core/network/ws_client.dart';
import '../../core/storage/chat_history_store.dart';
import '../../core/storage/secure_store.dart';
import '../../theme/discord_theme.dart';
import '../calls/call_screen.dart';
import '../chat_setup/set_passphrase_dialog.dart';

class ChatMessage {
  final String senderId;
  final String text;
  final bool isMine;
  ChatMessage(this.senderId, this.text, this.isMine);
}

const _uuid = Uuid();

class DmChatScreen extends StatefulWidget {
  final String conversationId;
  final String peerUserId;
  final String peerUsername;

  const DmChatScreen({
    super.key,
    required this.conversationId,
    required this.peerUserId,
    required this.peerUsername,
  });

  @override
  State<DmChatScreen> createState() => _DmChatScreenState();
}

class _DmChatScreenState extends State<DmChatScreen> {
  final _messages = <ChatMessage>[];
  final _input = TextEditingController();
  StreamSubscription<RelayEnvelope>? _sub;
  String? _myUserId;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final services = AppServices.of(context);
    _myUserId = await SecureStore.getUserId(services.api.baseUrl);

    final history = ChatHistoryStore.messagesFor(widget.conversationId);
    _messages.addAll(history.map((m) => ChatMessage(m.senderId, m.text, m.isMine)));

    _sub = services.ws.messages.listen((env) async {
      if (env.conversationId != widget.conversationId || env.type != 'message') return;

      if (env.messageId != null && ChatHistoryStore.messagesFor(widget.conversationId).any((m) => m.id == env.messageId)) {
        return;
      }
      await _handleInbound(env);
    });

    if (!services.crypto.hasSession(widget.conversationId)) {

      final passphrase = await showSetPassphraseDialog(context, otherPartyLabel: widget.peerUsername);
      if (passphrase == null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }

      final iAmInitiator = (_myUserId ?? '').compareTo(widget.peerUserId) < 0;
      if (iAmInitiator) {
        await services.crypto.startAsSender(
          conversationId: widget.conversationId,
          peerUserId: widget.peerUserId,
          passphrase: passphrase,
        );
      } else {
        await services.crypto.prepareAsReceiver(conversationId: widget.conversationId, passphrase: passphrase);
      }
    }
    setState(() => _ready = true);
  }

  Future<void> _handleInbound(RelayEnvelope env) async {
    try {
      final services = AppServices.of(context);
      final header = base64Decode(env.header!);
      final ciphertext = base64Decode(env.ciphertext!);
      final plaintext = await services.crypto.decrypt(widget.conversationId, header, ciphertext);
      await ChatHistoryStore.append(MessageRecord(
        id: env.messageId ?? _uuid.v4(),
        conversationId: widget.conversationId,
        senderId: env.fromUserId,
        text: plaintext,
        isMine: false,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ));
      setState(() => _messages.add(ChatMessage(env.fromUserId, plaintext, false)));
    } catch (e) {
      setState(() => _messages.add(ChatMessage(env.fromUserId, '[не удалось расшифровать сообщение]', false)));
    }
  }

  Future<void> _startCall({required bool video}) async {
    final services = AppServices.of(context);
    await services.calls.startCall(conversationId: widget.conversationId, peerUserId: widget.peerUserId, video: video);
    if (mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CallScreen()));
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || !_ready) return;
    final services = AppServices.of(context);
    final message = await services.crypto.encrypt(widget.conversationId, text);
    services.ws.send(RelayEnvelope(
      type: 'message',
      conversationId: widget.conversationId,
      fromUserId: _myUserId ?? '',
      ciphertext: base64Encode(message.ciphertext),
      header: base64Encode(message.header),
    ));

    await ChatHistoryStore.append(MessageRecord(
      id: _uuid.v4(),
      conversationId: widget.conversationId,
      senderId: _myUserId ?? '',
      text: text,
      isMine: true,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    ));
    setState(() {
      _messages.add(ChatMessage(_myUserId ?? '', text, true));
      _input.clear();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DiscordColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: DiscordColors.bgPrimary,
        title: Text('@${widget.peerUsername}'),
        actions: [
          IconButton(icon: const Icon(Icons.call), tooltip: 'Аудиозвонок', onPressed: () => _startCall(video: false)),
          IconButton(icon: const Icon(Icons.videocam), tooltip: 'Видеозвонок', onPressed: () => _startCall(video: true)),
        ],
      ),
      body: _ready
          ? Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      return Align(
                        alignment: m.isMine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: m.isMine ? DiscordColors.blurple : DiscordColors.bgSecondary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(m.text, style: const TextStyle(color: Colors.white)),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          decoration: const InputDecoration(hintText: 'Написать сообщение...'),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(icon: const Icon(Icons.send, color: DiscordColors.blurple), onPressed: _send),
                    ],
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
