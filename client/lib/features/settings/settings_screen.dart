import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../theme/discord_theme.dart';
import '../transfer/transfer_screen.dart';
import 'data_usage_screen.dart';
import 'nodes_screen.dart';
import 'sessions_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DiscordColors.bgPrimary,
      appBar: AppBar(backgroundColor: DiscordColors.bgPrimary, title: const Text('Настройки')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.dns, color: DiscordColors.blurple),
            title: const Text('Нода', style: TextStyle(color: DiscordColors.textNormal)),
            subtitle: Text(AppServices.of(context).api.baseUrl, style: const TextStyle(color: DiscordColors.textMuted)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NodesScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.phonelink, color: DiscordColors.blurple),
            title: const Text('Перенос чатов', style: TextStyle(color: DiscordColors.textNormal)),
            subtitle: const Text('Скопировать чаты на новое устройство по локальной сети', style: TextStyle(color: DiscordColors.textMuted)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TransferScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.devices, color: DiscordColors.blurple),
            title: const Text('Сессии', style: TextStyle(color: DiscordColors.textNormal)),
            subtitle: const Text('Активные входы в аккаунт на разных устройствах', style: TextStyle(color: DiscordColors.textMuted)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SessionsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.data_usage, color: DiscordColors.blurple),
            title: const Text('Данные и память', style: TextStyle(color: DiscordColors.textNormal)),
            subtitle: const Text('Трафик, автосохранение и автоудаление медиа', style: TextStyle(color: DiscordColors.textMuted)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DataUsageScreen())),
          ),
        ],
      ),
    );
  }
}
