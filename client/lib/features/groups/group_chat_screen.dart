import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_services.dart';
import '../../core/network/ws_client.dart';
import '../../core/storage/chat_history_store.dart';
import '../../core/storage/secure_store.dart';
import '../../theme/discord_theme.dart';
import '../chat_setup/set_passphrase_dialog.dart';
import '../dm/dm_chat_screen.dart' show ChatMessage;

const _uuid = Uuid();

class GroupChatScreen extends StatefulWidget {
  final String conversationId;
  final String groupId;
  final String groupName;

  const GroupChatScreen({
    super.key,
    required this.conversationId,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _messages = <ChatMessage>[];
  final _input = TextEditingController();
  StreamSubscription<RelayEnvelope>? _sub;
  String? _myUserId;
  List<String> _memberIds = [];
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final services = AppServices.of(context);
    await services.crypto.ensureIdentity();
    _myUserId = await SecureStore.getUserId(services.api.baseUrl);

    _memberIds = (await services.api.conversationMembers(widget.conversationId)).cast<String>();
    final otherMemberIds = _memberIds.where((id) => id != _myUserId).toList();

    await services.groupCrypto.restore(widget.groupId, otherMemberIds);

    final history = ChatHistoryStore.messagesFor(widget.conversationId);
    _messages.addAll(history.map((m) => ChatMessage(m.senderId, m.text, m.isMine)));

    _sub = services.ws.messages.listen((env) async {
      if (env.type == 'direct' && env.conversationId.startsWith('group-kx:${widget.groupId}:')) {
        await _handleDistribution(env);
      } else if (env.type == 'message' &&
          env.conversationId == widget.conversationId &&
          !(env.messageId != null && ChatHistoryStore.messagesFor(widget.conversationId).any((m) => m.id == env.messageId))) {

        await _handleInbound(env);
      }
    });

    if (!(await services.groupCrypto.hasPersistedOwnKey(widget.groupId))) {
      final passphrase = await showSetPassphraseDialog(context, otherPartyLabel: 'участников группы');
      if (passphrase == null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      await services.groupCrypto.rekeyAndDistribute(
        groupId: widget.groupId,
        myUserId: _myUserId!,
        otherMemberIds: otherMemberIds,
        passphrase: passphrase,
      );
    }

    setState(() => _ready = true);
  }

  Future<void> _handleDistribution(RelayEnvelope env) async {

    final services = AppServices.of(context);
    try {
      await services.groupCrypto.handleDistribution(
        groupId: widget.groupId,
        fromUserId: env.fromUserId,
        myUserId: _myUserId!,
        header: base64Decode(env.header!),
        ciphertext: base64Decode(env.ciphertext!),
        passphrase: await _passphraseForGroup(),
      );
    } catch (_) {

    }
  }

  String? _cachedPassphrase;
  Future<String> _passphraseForGroup() async {
    if (_cachedPassphrase != null) return _cachedPassphrase!;
    final entered = await showSetPassphraseDialog(context, otherPartyLabel: 'участников группы');
    _cachedPassphrase = entered ?? '';
    return _cachedPassphrase!;
  }

  Future<void> _handleInbound(RelayEnvelope env) async {
    final services = AppServices.of(context);
    try {
      final iterationAndCiphertext = jsonDecode(utf8.decode(base64Decode(env.header!))) as Map<String, dynamic>;
      final iteration = iterationAndCiphertext['n'] as int;
      final ciphertext = base64Decode(env.ciphertext!);
      final plaintext = await services.groupCrypto.decrypt(widget.groupId, env.fromUserId, iteration, ciphertext);
      if (plaintext != null) {
        await ChatHistoryStore.append(MessageRecord(
          id: env.messageId ?? _uuid.v4(),
          conversationId: widget.conversationId,
          senderId: env.fromUserId,
          text: plaintext,
          isMine: false,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ));
      }
      setState(() => _messages.add(ChatMessage(env.fromUserId, plaintext ?? '[ожидание ключа отправителя...]', false)));
    } catch (_) {
      setState(() => _messages.add(ChatMessage(env.fromUserId, '[не удалось расшифровать сообщение]', false)));
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || !_ready) return;
    final services = AppServices.of(context);
    final group = await services.groupCrypto.encrypt(widget.groupId, text);
    services.ws.send(RelayEnvelope(
      type: 'message',
      conversationId: widget.conversationId,
      fromUserId: _myUserId ?? '',
      ciphertext: base64Encode(group.ciphertext),
      header: base64Encode(utf8.encode(jsonEncode({'n': group.iteration}))),
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
      appBar: AppBar(backgroundColor: DiscordColors.bgPrimary, title: Text('# ${widget.groupName}')),
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
                          decoration: const InputDecoration(hintText: 'Написать в группу...'),
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
