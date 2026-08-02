import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_services.dart';
import '../../core/crypto/security/peer_identity_store.dart';
import '../../core/network/node_trust_monitor.dart';
import '../../core/network/ws_client.dart';
import '../../core/storage/chat_history_store.dart';
import '../../core/storage/secure_store.dart';
import '../../theme/bully_theme.dart';
import '../calls/call_screen.dart';
import '../chat_setup/set_passphrase_dialog.dart';
import 'safety_number_screen.dart';

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
  StreamSubscription<String>? _inboxSub;
  StreamSubscription<String>? _avatarSub;
  String? _myUserId;
  bool _ready = false;
  String? _initError;

  void _reloadFromHistory() {
    final history = ChatHistoryStore.messagesFor(widget.conversationId);
    _messages
      ..clear()
      ..addAll(history.map((m) => ChatMessage(m.senderId, m.text, m.isMine)));
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _initError = null);
    try {
      final services = AppServices.of(context);
      _myUserId = await SecureStore.getUserId(services.api.baseUrl);

      _reloadFromHistory();

      _inboxSub?.cancel();
      _inboxSub = services.inbox.onConversationUpdated.listen((conversationId) {
        if (conversationId != widget.conversationId || !mounted) return;
        setState(_reloadFromHistory);
      });

      if (!(await services.crypto.hasSession(widget.conversationId))) {
        final passphrase = await showSetPassphraseDialog(context, otherPartyLabel: widget.peerUsername);
        if (passphrase == null) {
          if (mounted) Navigator.of(context).pop();
          return;
        }

        final iAmInitiator = (_myUserId ?? '').compareTo(widget.peerUserId) < 0;
        if (iAmInitiator) {
          try {
            await services.crypto.startAsSender(
              conversationId: widget.conversationId,
              peerUserId: widget.peerUserId,
              passphrase: passphrase,
            );
          } on PeerIdentityChangedException {
            if (!mounted) return;
            final trust = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                backgroundColor: BullyPalette.of(context).bgSecondary,
                title: const Text('Ключ собеседника изменился', style: TextStyle(color: BullyColors.danger)),
                content: Text(
                  'Ключ шифрования @${widget.peerUsername} не совпадает с тем, что был при первом контакте. '
                  'Это нормально, если собеседник переустановил приложение — но так же выглядит подмена ключа '
                  'атакующим. Сверьте код безопасности лично перед тем, как доверять новому ключу.',
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
            final bundle = await services.api.fetchKeyBundle(widget.peerUserId);
            final peerPublicKey = base64Decode(bundle['signed_public_key'] as String);
            await services.crypto.trustNewPeerIdentity(widget.peerUserId, peerPublicKey);
            await services.crypto.startAsSender(
              conversationId: widget.conversationId,
              peerUserId: widget.peerUserId,
              passphrase: passphrase,
            );
          }
        } else {
          await services.crypto.prepareAsReceiver(conversationId: widget.conversationId, passphrase: passphrase);
        }
      }
      unawaited(services.avatars.shareWithPeer(conversationId: widget.conversationId, peerUserId: widget.peerUserId));
      _avatarSub?.cancel();
      _avatarSub = services.avatars.onPeerAvatarUpdated.listen((userId) {
        if (userId == widget.peerUserId && mounted) setState(() {});
      });

      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _initError = '$e');
    }
  }

  Future<void> _resetEncryption() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BullyPalette.of(context).bgSecondary,
        title: Text('Сбросить шифрование?', style: TextStyle(color: BullyPalette.of(context).textNormal)),
        content: Text(
          'Локальная сессия шифрования этого чата будет забыта. При следующем открытии чата с обеих сторон '
          'нужно будет заново ввести пароль шифрования (одинаковый на обоих устройствах). Используйте, если '
          'сообщения перестали доставляться или расшифровываться.',
          style: TextStyle(color: BullyPalette.of(context).textNormal),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Сбросить', style: TextStyle(color: BullyColors.danger))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await AppServices.of(context).crypto.resetSession(widget.conversationId);
    if (mounted) Navigator.of(context).pop();
  }

  bool _blockIfCompromised() {
    if (!NodeTrustMonitor.instance.compromised) return false;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(NodeTrustMonitor.instance.reason ?? 'Нода скомпрометирована — действие заблокировано.'),
      backgroundColor: BullyColors.danger,
    ));
    return true;
  }

  Future<void> _startCall({required bool video}) async {
    if (_blockIfCompromised()) return;
    final services = AppServices.of(context);
    await services.calls.startCall(conversationId: widget.conversationId, peerUserId: widget.peerUserId, video: video);
    if (mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CallScreen()));
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || !_ready) return;
    if (_blockIfCompromised()) return;
    try {
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось отправить: $e'), backgroundColor: BullyColors.danger));
      }
    }
  }

  @override
  void dispose() {
    _inboxSub?.cancel();
    _avatarSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BullyPalette.of(context).bgPrimary,
      appBar: AppBar(
        backgroundColor: BullyPalette.of(context).bgPrimary,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PeerAvatar(peerUserId: widget.peerUserId, label: widget.peerUsername),
            const SizedBox(width: 10),
            Text('@${widget.peerUsername}'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.verified_user_outlined),
            tooltip: 'Проверка безопасности',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SafetyNumberScreen(peerUserId: widget.peerUserId, peerUsername: widget.peerUsername),
            )),
          ),
          IconButton(icon: const Icon(Icons.call), tooltip: 'Аудиозвонок', onPressed: () => _startCall(video: false)),
          IconButton(icon: const Icon(Icons.videocam), tooltip: 'Видеозвонок', onPressed: () => _startCall(video: true)),
          PopupMenuButton<void>(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              PopupMenuItem(
                onTap: _resetEncryption,
                child: const Text('Сбросить шифрование чата'),
              ),
            ],
          ),
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
                          decoration: const InputDecoration(hintText: 'Написать сообщение...'),
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

class _PeerAvatar extends StatelessWidget {
  final String peerUserId;
  final String label;
  const _PeerAvatar({required this.peerUserId, required this.label});

  @override
  Widget build(BuildContext context) {
    final bytes = AppServices.of(context).avatars.peerAvatarBytes(peerUserId);
    return CircleAvatar(
      radius: 14,
      backgroundColor: BullyColors.blurple,
      backgroundImage: bytes != null ? MemoryImage(bytes) : null,
      child: bytes == null ? Text(label.isNotEmpty ? label[0].toUpperCase() : '?', style: const TextStyle(fontSize: 12, color: Colors.white)) : null,
    );
  }
}
