import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/storage/secure_store.dart';
import '../../theme/bully_theme.dart';
import '../auth/auth_screen.dart';
import '../transfer/transfer_screen.dart';
import 'appearance_screen.dart';
import 'data_usage_screen.dart';
import 'nodes_screen.dart';
import 'sessions_screen.dart';

const _wideBreakpoint = 700.0;

class _SettingsSection {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;
  final WidgetBuilder builder;
  final VoidCallback? onTap;

  _SettingsSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
    this.iconColor,
    this.onTap,
  });
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _selected = 0;

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
          icon: Icons.phonelink,
          title: 'Перенос чатов',
          subtitle: 'Скопировать чаты на новое устройство по локальной сети',
          builder: (_) => const TransferScreen(embedded: true),
        ),
        _SettingsSection(
          icon: Icons.devices,
          title: 'Сессии',
          subtitle: 'Активные входы в аккаунт на разных устройствах',
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

  @override
  Widget build(BuildContext context) {
    final sections = _sections(context);
    return Scaffold(
      backgroundColor: BullyPalette.of(context).bgPrimary,
      appBar: AppBar(backgroundColor: BullyPalette.of(context).bgPrimary, title: const Text('Настройки')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _wideBreakpoint;
          if (!wide) {
            return ListView(
              padding: const EdgeInsets.all(12),
              children: sections
                  .map((s) => _SettingsTile(
                        icon: s.icon,
                        iconColor: s.iconColor,
                        title: s.title,
                        subtitle: s.subtitle,
                        onTap: s.onTap ??
                            () => Navigator.of(context).push(MaterialPageRoute(builder: s.builder)),
                      ))
                  .toList(),
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
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Icon(s.icon, size: 20, color: s.iconColor ?? (isSelected ? BullyColors.blurple : BullyPalette.of(context).textMuted)),
                        title: Text(
                          s.title,
                          style: TextStyle(
                            color: s.iconColor ?? (isSelected ? BullyColors.blurple : BullyPalette.of(context).textNormal),
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        onTap: s.onTap ?? () => setState(() => _selected = i),
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
      ),
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: iconColor ?? BullyColors.blurple),
        title: Text(title, style: TextStyle(color: iconColor ?? BullyPalette.of(context).textNormal, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(color: BullyPalette.of(context).textMuted)),
        trailing: iconColor == null ? Icon(Icons.chevron_right, color: BullyPalette.of(context).textMuted) : null,
        onTap: onTap,
      ),
    );
  }
}
