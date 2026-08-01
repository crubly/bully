import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../theme/discord_theme.dart';

/// Returns the picked user's {id, username} map, or null if cancelled.
Future<Map<String, dynamic>?> showNewDmDialog(BuildContext context) async {
  final services = AppServices.of(context);
  final controller = TextEditingController();
  List<dynamic> results = [];

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: DiscordColors.bgSecondary,
        title: const Text('Новое сообщение', style: TextStyle(color: DiscordColors.textNormal)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Имя пользователя'),
                onChanged: (q) async {
                  if (q.trim().isEmpty) {
                    setState(() => results = []);
                    return;
                  }
                  final found = await services.api.searchUsers(q.trim());
                  setState(() => results = found);
                },
              ),
              const SizedBox(height: 8),
              ...results.map((u) => ListTile(
                    title: Text('@${u['username']}', style: const TextStyle(color: DiscordColors.textNormal)),
                    onTap: () => Navigator.of(context).pop(u as Map<String, dynamic>),
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        ],
      ),
    ),
  );
}
