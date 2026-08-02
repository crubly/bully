import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/storage/secure_store.dart';
import '../../theme/bully_theme.dart';
import '../../theme/mesh_gradient.dart';
import '../../theme/theme_controller.dart';

class ProfileScreen extends StatefulWidget {
  final bool embedded;
  const ProfileScreen({super.key, this.embedded = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _username;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    try {
      final services = AppServices.of(context);
      final username = await SecureStore.getUsername(services.api.baseUrl);
      if (mounted) setState(() => _username = username);
    } catch (_) {
      if (mounted) setState(() => _username = '?');
    }
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.pickFiles(type: FileType.image, withData: true);
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;

    final services = AppServices.of(context);
    try {
      await services.avatars.setOwnAvatar(bytes);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (mounted) setState(() {});

    final conversations = await services.api.listConversations();
    for (final c in conversations) {
      if (c['kind'] != 'dm') continue;
      final id = c['id'] as String;
      final myId = await SecureStore.getUserId(services.api.baseUrl);
      final members = (await services.api.conversationMembers(id)).cast<String>();
      final peerId = members.firstWhere((m) => m != myId, orElse: () => members.first);
      unawaited(services.avatars.shareWithPeer(conversationId: id, peerUserId: peerId));
    }
  }

  Widget _avatar(BuildContext context, Uint8List? avatarBytes, Color avatarBgColor) {
    return InkWell(
      onTap: _pickAvatar,
      customBorder: const CircleBorder(),
      child: Tooltip(
        message: 'Сменить аватарку — видна только тем, с кем вы переписываетесь',
        child: CircleAvatar(
          radius: 56,
          backgroundColor: avatarBgColor,
          backgroundImage: avatarBytes != null ? MemoryImage(avatarBytes) : null,
          child: avatarBytes == null
              ? Text(
                  (_username?.isNotEmpty ?? false) ? _username![0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 40),
                )
              : null,
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final avatarBytes = AppServices.of(context).avatars.ownAvatarBytes();
    final gradient = ThemeController.instance.themeGradient;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (gradient != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: MeshGradientBox(
              points: gradient,
              fallbackColor: BullyColors.blurple,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(child: _avatar(context, avatarBytes, Colors.white24)),
              ),
            ),
          )
        else
          Center(child: _avatar(context, avatarBytes, BullyColors.blurple)),
        const SizedBox(height: 16),
        Center(
          child: Text(
            _username ?? '...',
            style: TextStyle(color: BullyPalette.of(context).textNormal, fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: OutlinedButton.icon(
            onPressed: _pickAvatar,
            icon: const Icon(Icons.image_outlined, size: 18),
            label: const Text('Изменить аватарку'),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Аватарка хранится только локально и передаётся напрямую (E2E) контактам, с которыми вы переписываетесь — '
            'сервер её никогда не видит.',
            textAlign: TextAlign.center,
            style: TextStyle(color: BullyPalette.of(context).textMuted, fontSize: 12),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _body(context);
    return Scaffold(
      backgroundColor: BullyPalette.of(context).bgPrimary,
      appBar: AppBar(backgroundColor: BullyPalette.of(context).bgPrimary, title: const Text('Профиль')),
      body: _body(context),
    );
  }
}
