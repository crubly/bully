import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../theme/bully_theme.dart';

Future<Map<String, dynamic>?> showNewGroupDialog(BuildContext context) async {
  final services = AppServices.of(context);
  final nameController = TextEditingController();
  final searchController = TextEditingController();
  List<dynamic> results = [];
  final selected = <String, String>{};

  final created = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: BullyPalette.of(context).bgSecondary,
        title: Text('Новая группа', style: TextStyle(color: BullyPalette.of(context).textNormal)),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Название группы')),
              const SizedBox(height: 12),
              TextField(
                controller: searchController,
                decoration: const InputDecoration(labelText: 'Добавить участников'),
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
              ...results.map((u) => CheckboxListTile(
                    value: selected.containsKey(u['id']),
                    title: Text('@${u['username']}', style: TextStyle(color: BullyPalette.of(context).textNormal)),
                    onChanged: (checked) => setState(() {
                      if (checked == true) {
                        selected[u['id'] as String] = u['username'] as String;
                      } else {
                        selected.remove(u['id']);
                      }
                    }),
                  )),
              if (selected.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: selected.values.map((name) => Chip(label: Text('@$name'))).toList(),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: nameController.text.trim().isEmpty
                ? null
                : () async {
                    final group = await services.api.createGroup(nameController.text.trim(), selected.keys.toList());
                    if (context.mounted) Navigator.of(context).pop(group);
                  },
            child: const Text('Создать'),
          ),
        ],
      ),
    ),
  );
  return created;
}
