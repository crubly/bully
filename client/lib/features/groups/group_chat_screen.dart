import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_services.dart';
import '../../core/calls/call_controller.dart';
import '../../core/crypto/security/peer_identity_store.dart';
import '../../core/network/node_trust_monitor.dart';
import '../../core/network/ws_client.dart';
import '../../core/storage/chat_history_store.dart';
import '../../core/storage/secure_store.dart';
import '../../theme/bully_theme.dart';
import '../calls/call_screen.dart';
import '../calls/compact_call_bar.dart';
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
  StreamSubscription<CallState>? _callStateSub;
  String? _myUserId;
  List<String> _memberIds = [];
  bool _ready = false;
  String? _initError;
  CallState _callState = CallState.idle;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _initError = null);
    try {
      final services = AppServices.of(context);
      await services.crypto.ensureIdentity();
      _myUserId = await SecureStore.getUserId(services.api.baseUrl);

      _memberIds = (await services.api.conversationMembers(widget.conversationId)).cast<String>();
      final otherMemberIds = _memberIds.where((id) => id != _myUserId).toList();

      services.calls.registerGroup(widget.conversationId, widget.groupId);
      _callState = services.calls.activeConversationId == widget.conversationId ? services.calls.state : CallState.idle;
      _callStateSub?.cancel();
      _callStateSub = services.calls.stateStream.listen((s) {
        if (!mounted) return;
        setState(() => _callState = services.calls.activeConversationId == widget.conversationId ? s : CallState.idle);
      });

      await services.groupCrypto.restore(widget.groupId, otherMemberIds);

      final history = ChatHistoryStore.messagesFor(widget.conversationId);
      _messages.clear();
      _messages.addAll(history.map((m) => ChatMessage(m.senderId, m.text, m.isMine)));

      _sub?.cancel();
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
        try {
          await services.groupCrypto.rekeyAndDistribute(
            groupId: widget.groupId,
            myUserId: _myUserId!,
            otherMemberIds: otherMemberIds,
            passphrase: passphrase,
          );
        } on PeerIdentityChangedException catch (e) {
          if (!mounted) return;
          final trust = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              backgroundColor: BullyPalette.of(context).bgSecondary,
              title: const Text('Ключ участника изменился', style: TextStyle(color: BullyColors.danger)),
              content: Text(
                'Ключ шифрования одного из участников (${e.peerUserId}) не совпадает с тем, что был раньше. '
                'Это нормально при переустановке приложения — но так же выглядит подмена ключа атакующим.',
                style: TextStyle(color: BullyPalette.of(context).textNormal),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Отмена')),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Доверять новому ключу', style: TextStyle(color: BullyColors.danger)),
                ),
              ],
            ),
          );
          if (trust != true) {
            if (mounted) Navigator.of(context).pop();
            return;
          }
          final bundle = await services.api.fetchKeyBundle(e.peerUserId);
          final peerPublicKey = Uint8List.fromList(base64Decode(bundle['signed_public_key'] as String));
          await PeerIdentityStore.trust(e.peerUserId, peerPublicKey);
          await services.groupCrypto.rekeyAndDistribute(
            groupId: widget.groupId,
            myUserId: _myUserId!,
            otherMemberIds: otherMemberIds,
            passphrase: passphrase,
          );
        }
      }

      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _initError = '$e');
    }
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
    if (NodeTrustMonitor.instance.compromised) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(NodeTrustMonitor.instance.reason ?? 'Нода скомпрометирована — действие заблокировано.'),
        backgroundColor: BullyColors.danger,
      ));
      return;
    }
    try {
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось отправить: $e'), backgroundColor: BullyColors.danger));
      }
    }
  }

  Future<void> _startGroupCall({required bool video}) async {
    if (NodeTrustMonitor.instance.compromised) return;
    final services = AppServices.of(context);
    final otherMemberIds = _memberIds.where((id) => id != _myUserId).toList();
    final compact = useCompactCallUi(context);
    await services.calls.joinGroupCall(
      conversationId: widget.conversationId,
      groupId: widget.groupId,
      myUserId: _myUserId ?? '',
      otherMemberIds: otherMemberIds,
      video: video,
    );
    if (mounted && !compact) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CallScreen()));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _callStateSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BullyPalette.of(context).bgPrimary,
      appBar: AppBar(
        backgroundColor: BullyPalette.of(context).bgPrimary,
        title: Text('# ${widget.groupName}'),
        actions: [
          IconButton(icon: const Icon(Icons.call), tooltip: 'Аудиозвонок', onPressed: () => _startGroupCall(video: false)),
          IconButton(icon: const Icon(Icons.videocam), tooltip: 'Видеозвонок', onPressed: () => _startGroupCall(video: true)),
        ],
      ),
      body: _ready
          ? Column(
              children: [
                if (_callState != CallState.idle && _callState != CallState.ended && useCompactCallUi(context))
                  CompactCallBar(calls: AppServices.of(context).calls, labelFor: (id) => id),
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
                            color: m.isMine ? BullyColors.blurple : BullyPalette.of(context).bgSecondary,
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
                      IconButton(icon: Icon(Icons.send, color: BullyColors.blurple), onPressed: _send),
                    ],
                  ),
                ),
              ],
            )
          : _initError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Не удалось открыть чат:\n$_initError',
                          style: TextStyle(color: BullyPalette.of(context).textMuted, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _init, child: const Text('Повторить')),
                      ],
                    ),
                  ),
                )
              : const Center(child: CircularProgressIndicator()),
    );
  }
}
