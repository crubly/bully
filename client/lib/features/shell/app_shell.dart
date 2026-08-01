import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/calls/call_controller.dart';
import '../../core/storage/secure_store.dart';
import '../../theme/bully_theme.dart';
import '../calls/call_screen.dart';
import '../dm/dm_chat_screen.dart';
import '../dm/new_dm_dialog.dart';
import '../groups/group_chat_screen.dart';
import '../groups/new_group_dialog.dart';
import '../settings/settings_screen.dart';

class _ConversationEntry {
  final String conversationId;
  final String kind;
  final String? groupId;
  final String label;
  final String? peerUserId;

  _ConversationEntry({
    required this.conversationId,
    required this.kind,
    required this.label,
    this.groupId,
    this.peerUserId,
  });
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  List<_ConversationEntry> _entries = [];
  bool _loading = true;
  String? _loadError;
  StreamSubscription<IncomingCall>? _incomingCallSub;
  String? _myUsername;
  bool _micMuted = false;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _loadCurrentUser();
    WidgetsBinding.instance.addPostFrameCallback((_) => _listenForIncomingCalls());
  }

  Future<void> _loadCurrentUser() async {
    try {
      final services = AppServices.of(context);
      final username = await SecureStore.getUsername(services.api.baseUrl);
      if (mounted) setState(() => _myUsername = username);
    } catch (e) {
      if (mounted) setState(() => _myUsername = '?');
    }
  }

  void _toggleMic() {
    setState(() => _micMuted = !_micMuted);

    AppServices.of(context).calls.setMuted(_micMuted);
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    if (bytes.length > 2 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Файл слишком большой (максимум 2 МБ) — выбери картинку поменьше.')),
        );
      }
      return;
    }

    final services = AppServices.of(context);
    await services.avatars.setOwnAvatar(bytes);
    if (mounted) setState(() {});

    // Avatars are local-only and E2E — push the new one straight to every
    // DM contact you already have open, instead of waiting for their next
    // chat-open to notice a version mismatch.
    for (final entry in _entries.where((e) => e.kind == 'dm' && e.peerUserId != null)) {
      unawaited(services.avatars.shareWithPeer(conversationId: entry.conversationId, peerUserId: entry.peerUserId!));
    }
  }

  void _listenForIncomingCalls() {
    _incomingCallSub = AppServices.of(context).calls.incomingCalls.listen((call) async {
      final peer = await AppServices.of(context).api.getUser(call.fromUserId);
      if (!mounted) return;
      final accept = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: BullyPalette.of(context).bgSecondary,
          title: Text('Входящий звонок от @${peer['username']}', style: TextStyle(color: BullyPalette.of(context).textNormal)),
          content: Text(call.video ? 'Видеозвонок' : 'Аудиозвонок', style: TextStyle(color: BullyPalette.of(context).textMuted)),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Отклонить')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Принять')),
          ],
        ),
      );
      final services = AppServices.of(context);
      if (accept == true) {
        await services.calls.acceptCall(call);
        if (mounted) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(incoming: call)));
        }
      } else {
        await services.calls.declineCall(call);
      }
    });
  }

  @override
  void dispose() {
    _incomingCallSub?.cancel();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final services = AppServices.of(context);
      final myId = await SecureStore.getUserId(services.api.baseUrl);
      final raw = await services.api.listConversations();
      final entries = <_ConversationEntry>[];
      for (final c in raw) {
        final id = c['id'] as String;
        final kind = c['kind'] as String;
        if (kind == 'dm') {
          final members = (await services.api.conversationMembers(id)).cast<String>();
          final peerId = members.firstWhere((m) => m != myId, orElse: () => members.first);
          final peer = await services.api.getUser(peerId);
          entries.add(_ConversationEntry(
            conversationId: id,
            kind: 'dm',
            label: peer['username'] as String,
            peerUserId: peerId,
          ));
        } else {
          entries.add(_ConversationEntry(
            conversationId: id,
            kind: 'group',
            groupId: c['group_id'] as String,
            label: (c['group_name'] as String?) ?? 'Группа',
          ));
        }
      }
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openNewDm() async {
    final peer = await showNewDmDialog(context);
    if (peer == null) return;
    final services = AppServices.of(context);
    final convo = await services.api.createDm(peer['id'] as String);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DmChatScreen(
        conversationId: convo['id'] as String,
        peerUserId: peer['id'] as String,
        peerUsername: peer['username'] as String,
      ),
    ));
    _loadConversations();
  }

  Future<void> _openNewGroup() async {
    final group = await showNewGroupDialog(context);
    if (group == null) return;
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupChatScreen(
        conversationId: group['conversation_id'] as String,
        groupId: group['id'] as String,
        groupName: group['name'] as String,
      ),
    ));
    _loadConversations();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 72,
            color: BullyPalette.of(context).bgTertiary,
            child: Column(
              children: [
                const SizedBox(height: 12),
                ..._entries.where((e) => e.kind == 'group').map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => GroupChatScreen(
                            conversationId: e.conversationId,
                            groupId: e.groupId!,
                            groupName: e.label,
                          ),
                        )),
                        child: CircleAvatar(
                          backgroundColor: BullyColors.blurple,
                          child: Text(e.label.isNotEmpty ? e.label[0].toUpperCase() : '?'),
                        ),
                      ),
                    )),
                const SizedBox(height: 6),
                IconButton(
                  icon: CircleAvatar(backgroundColor: BullyPalette.of(context).bgSecondary, child: Icon(Icons.add, color: BullyColors.online)),
                  onPressed: _openNewGroup,
                  tooltip: 'Новая группа',
                ),
              ],
            ),
          ),
          Container(
            width: 240,
            color: BullyPalette.of(context).bgSecondary,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(child: Text('Личные сообщения', style: TextStyle(color: BullyPalette.of(context).textMuted))),
                      IconButton(icon: Icon(Icons.edit, size: 18, color: BullyPalette.of(context).textMuted), onPressed: _openNewDm),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _loadError != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Не удалось загрузить чаты:\n$_loadError',
                                      style: TextStyle(color: BullyPalette.of(context).textMuted, fontSize: 12),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 12),
                                    ElevatedButton(onPressed: _loadConversations, child: const Text('Повторить')),
                                  ],
                                ),
                              ),
                            )
                          : ListView(
                          children: _entries
                              .where((e) => e.kind == 'dm')
                              .map((e) {
                                final avatarBytes =
                                    e.peerUserId == null ? null : AppServices.of(context).avatars.peerAvatarBytes(e.peerUserId!);
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: BullyColors.blurple,
                                    backgroundImage: avatarBytes != null ? MemoryImage(avatarBytes) : null,
                                    child: avatarBytes == null ? const Icon(Icons.person, color: Colors.white) : null,
                                  ),
                                  title: Text(e.label, style: TextStyle(color: BullyPalette.of(context).textNormal)),
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => DmChatScreen(
                                      conversationId: e.conversationId,
                                      peerUserId: e.peerUserId ?? '',
                                      peerUsername: e.label,
                                    ),
                                  )),
                                );
                              })
                              .toList(),
                        ),
                ),
                _UserBar(
                  username: _myUsername,
                  micMuted: _micMuted,
                  avatarBytes: AppServices.of(context).avatars.ownAvatarBytes(),
                  onAvatarTap: _pickAvatar,
                  onToggleMic: _toggleMic,
                  onOpenSettings: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: BullyPalette.of(context).bgPrimary,
              child: Center(
                child: Text('Выберите чат слева или начните новый', style: TextStyle(color: BullyPalette.of(context).textMuted)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserBar extends StatelessWidget {
  final String? username;
  final bool micMuted;
  final Uint8List? avatarBytes;
  final VoidCallback onAvatarTap;
  final VoidCallback onToggleMic;
  final VoidCallback onOpenSettings;

  const _UserBar({
    required this.username,
    required this.micMuted,
    required this.avatarBytes,
    required this.onAvatarTap,
    required this.onToggleMic,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      color: BullyPalette.of(context).bgTertiary,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          InkWell(
            onTap: onAvatarTap,
            customBorder: const CircleBorder(),
            child: Tooltip(
              message: 'Сменить аватарку — видна только тем, с кем вы переписываетесь',
              child: CircleAvatar(
                radius: 16,
                backgroundColor: BullyColors.blurple,
                backgroundImage: avatarBytes != null ? MemoryImage(avatarBytes!) : null,
                child: avatarBytes == null
                    ? Text(
                        (username?.isNotEmpty ?? false) ? username![0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              username ?? '...',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: BullyPalette.of(context).textNormal, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: Icon(Icons.mic, size: 18, color: micMuted ? BullyColors.danger : BullyPalette.of(context).textMuted),
            onPressed: onToggleMic,
            tooltip: micMuted ? 'Включить микрофон' : 'Выключить микрофон',
          ),
          IconButton(
            icon: Icon(Icons.settings, size: 18, color: BullyPalette.of(context).textMuted),
            onPressed: onOpenSettings,
            tooltip: 'Настройки',
          ),
        ],
      ),
    );
  }
}
