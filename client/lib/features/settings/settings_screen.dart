import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/desktop_window.dart';
import '../../core/storage/secure_store.dart';
import '../../theme/bully_theme.dart';
import '../../theme/mesh_gradient.dart';
import '../../theme/theme_controller.dart';
import '../auth/auth_screen.dart';
import 'appearance_screen.dart';
import 'data_usage_screen.dart';
import 'nodes_screen.dart';
import 'profile_screen.dart';
import 'sessions_screen.dart';

const _wideBreakpoint = 700.0;

class _SettingsSection {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;
  final WidgetBuilder builder;
  final VoidCallback? onTap;
  final bool isProfile;

  _SettingsSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
    this.iconColor,
    this.onTap,
    this.isProfile = false,
  });
}

class SettingsScreen extends StatefulWidget {
  final bool embedded;
  const SettingsScreen({super.key, this.embedded = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _selected = 0;
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

  void _selectSection(int i) {
    setState(() => _selected = i);
  }

  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BullyPalette.of(context).bgSecondary,
        title: Text('Выйти из аккаунта?', style: TextStyle(color: BullyPalette.of(context).textNormal)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Выйти', style: TextStyle(color: BullyColors.danger))),
        ],
      ),
    );
    if (confirm != true) return;
    if (!context.mounted) return;

    final services = AppServices.of(context);
    services.ws.close();
    await SecureStore.clearAuthToken(services.api.baseUrl);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  List<_SettingsSection> _sections(BuildContext context) => [
        _SettingsSection(
          icon: Icons.person,
          title: _username ?? '...',
          subtitle: 'Профиль и аватарка',
          isProfile: true,
          builder: (_) => const ProfileScreen(embedded: true),
        ),
        _SettingsSection(
          icon: Icons.dns,
          title: 'Нода',
          subtitle: AppServices.of(context).api.baseUrl,
          builder: (_) => const NodesScreen(embedded: true),
        ),
        _SettingsSection(
          icon: Icons.palette,
          title: 'Оформление',
          subtitle: 'Тёмная, светлая или системная тема',
          builder: (_) => const AppearanceScreen(embedded: true),
        ),
        _SettingsSection(
          icon: Icons.devices,
          title: 'Сессии',
          subtitle: 'Устройства, автозавершение сессий, перенос чатов',
          builder: (_) => const SessionsScreen(embedded: true),
        ),
        _SettingsSection(
          icon: Icons.data_usage,
          title: 'Данные и память',
          subtitle: 'Трафик, автосохранение и автоудаление медиа',
          builder: (_) => const DataUsageScreen(embedded: true),
        ),
        _SettingsSection(
          icon: Icons.logout,
          iconColor: BullyColors.danger,
          title: 'Выйти',
          subtitle: 'Выйти из аккаунта на этом устройстве',
          builder: (_) => const SizedBox.shrink(),
          onTap: () => _logout(context),
        ),
      ];

  Widget _body(BuildContext context) {
    final sections = _sections(context);
    return LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _wideBreakpoint;
          if (!wide) {
            final profile = sections.first;
            final rest = sections.skip(1);
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _ProfileHeaderTile(
                  username: _username,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: profile.builder)),
                ),
                const SizedBox(height: 8),
                ...rest.map((s) => _SettingsTile(
                      icon: s.icon,
                      iconColor: s.iconColor,
                      title: s.title,
                      subtitle: s.subtitle,
                      onTap: s.onTap ??
                          () => Navigator.of(context).push(MaterialPageRoute(builder: s.builder)),
                    )),
              ],
            );
          }

          return Row(
            children: [
              SizedBox(
                width: 260,
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: sections.length,
                  itemBuilder: (context, i) {
                    final s = sections[i];
                    final isSelected = i == _selected && s.onTap == null;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        color: isSelected ? BullyColors.blurple.withValues(alpha: 0.15) : null,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        leading: s.isProfile
                            ? CircleAvatar(
                                radius: 14,
                                backgroundColor: BullyColors.blurple,
                                backgroundImage: AppServices.of(context).avatars.ownAvatarBytes() != null
                                    ? MemoryImage(AppServices.of(context).avatars.ownAvatarBytes()!)
                                    : null,
                                child: AppServices.of(context).avatars.ownAvatarBytes() == null
                                    ? Text(
                                        (s.title.isNotEmpty ? s.title[0].toUpperCase() : '?'),
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                      )
                                    : null,
                              )
                            : Icon(s.icon, size: 20, color: s.iconColor ?? (isSelected ? BullyColors.blurple : BullyPalette.of(context).textMuted)),
                        title: Text(
                          s.title,
                          style: TextStyle(
                            color: s.iconColor ?? (isSelected ? BullyColors.blurple : BullyPalette.of(context).textNormal),
                            fontSize: 14,
                            fontWeight: isSelected || s.isProfile ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        onTap: s.onTap ?? () => _selectSection(i),
                      ),
                    );
                  },
                ),
              ),
              VerticalDivider(width: 1, color: BullyPalette.of(context).bgTertiary),
              Expanded(
                child: Container(
                  color: BullyPalette.of(context).bgSecondary,
                  child: sections[_selected].builder(context),
                ),
              ),
            ],
          );
        },
      );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _body(context);
    final desktop = DesktopWindow.isDesktop;
    return Scaffold(
      backgroundColor: BullyPalette.of(context).bgPrimary,
      appBar: AppBar(
        backgroundColor: BullyPalette.of(context).bgPrimary,
        title: desktop ? null : const Text('Настройки'),
        leadingWidth: desktop ? 40 : null,
        leading: desktop
            ? IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.arrow_back, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: _body(context),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({required this.icon, required this.title, required this.subtitle, required this.onTap, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: BullyPalette.of(context).bgSecondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(icon, color: iconColor ?? BullyColors.blurple),
        title: Text(title, style: TextStyle(color: iconColor ?? BullyPalette.of(context).textNormal, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(color: BullyPalette.of(context).textMuted)),
        trailing: iconColor == null ? Icon(Icons.chevron_right, color: BullyPalette.of(context).textMuted) : null,
        onTap: onTap,
      ),
    );
  }
}

class _ProfileHeaderTile extends StatelessWidget {
  final String? username;
  final VoidCallback onTap;

  const _ProfileHeaderTile({required this.username, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final avatarBytes = AppServices.of(context).avatars.ownAvatarBytes();
    final gradient = ThemeController.instance.themeGradient;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          if (gradient != null)
            Positioned.fill(child: MeshGradientBox(points: gradient, fallbackColor: BullyColors.blurple))
          else
            Positioned.fill(child: Container(color: BullyPalette.of(context).bgSecondary)),
          if (gradient != null) Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.35))),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              radius: 28,
              backgroundColor: BullyColors.blurple,
              backgroundImage: avatarBytes != null ? MemoryImage(avatarBytes) : null,
              child: avatarBytes == null
                  ? Text(
                      (username?.isNotEmpty ?? false) ? username![0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 22),
                    )
                  : null,
            ),
            title: Text(
              username ?? '...',
              style: TextStyle(
                color: gradient != null ? Colors.white : BullyPalette.of(context).textNormal,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              'Профиль и аватарка',
              style: TextStyle(color: gradient != null ? Colors.white70 : BullyPalette.of(context).textMuted),
            ),
            trailing: Icon(Icons.chevron_right, color: gradient != null ? Colors.white70 : BullyPalette.of(context).textMuted),
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}
