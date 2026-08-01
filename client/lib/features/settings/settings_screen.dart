import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../theme/bully_theme.dart';
import '../transfer/transfer_screen.dart';
import 'appearance_screen.dart';
import 'data_usage_screen.dart';
import 'nodes_screen.dart';
import 'sessions_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BullyPalette.of(context).bgPrimary,
      appBar: AppBar(backgroundColor: BullyPalette.of(context).bgPrimary, title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _SettingsTile(
            icon: Icons.dns,
            title: 'Нода',
            subtitle: AppServices.of(context).api.baseUrl,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NodesScreen())),
          ),
          _SettingsTile(
            icon: Icons.palette,
            title: 'Оформление',
            subtitle: 'Тёмная, светлая или системная тема',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AppearanceScreen())),
          ),
          _SettingsTile(
            icon: Icons.phonelink,
            title: 'Перенос чатов',
            subtitle: 'Скопировать чаты на новое устройство по локальной сети',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TransferScreen())),
          ),
          _SettingsTile(
            icon: Icons.devices,
            title: 'Сессии',
            subtitle: 'Активные входы в аккаунт на разных устройствах',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SessionsScreen())),
          ),
          _SettingsTile(
            icon: Icons.data_usage,
            title: 'Данные и память',
            subtitle: 'Трафик, автосохранение и автоудаление медиа',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DataUsageScreen())),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: BullyPalette.of(context).bgSecondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: BullyColors.blurple),
        title: Text(title, style: TextStyle(color: BullyPalette.of(context).textNormal, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(color: BullyPalette.of(context).textMuted)),
        trailing: Icon(Icons.chevron_right, color: BullyPalette.of(context).textMuted),
        onTap: onTap,
      ),
    );
  }
}
