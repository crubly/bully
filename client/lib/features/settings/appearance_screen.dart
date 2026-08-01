import 'package:flutter/material.dart';

import '../../theme/bully_theme.dart';
import '../../theme/theme_controller.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BullyPalette.of(context).bgPrimary,
      appBar: AppBar(backgroundColor: BullyPalette.of(context).bgPrimary, title: const Text('Оформление')),
      body: ListenableBuilder(
        listenable: ThemeController.instance,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _ThemeOption(
              label: 'Тёмная',
              icon: Icons.dark_mode,
              selected: ThemeController.instance.mode == ThemeMode.dark,
              onTap: () => ThemeController.instance.setMode(ThemeMode.dark),
            ),
            _ThemeOption(
              label: 'Светлая',
              icon: Icons.light_mode,
              selected: ThemeController.instance.mode == ThemeMode.light,
              onTap: () => ThemeController.instance.setMode(ThemeMode.light),
            ),
            _ThemeOption(
              label: 'Как в системе',
              icon: Icons.settings_suggest,
              selected: ThemeController.instance.mode == ThemeMode.system,
              onTap: () => ThemeController.instance.setMode(ThemeMode.system),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: BullyPalette.of(context).bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: selected ? Border.all(color: BullyColors.blurple, width: 2) : null,
      ),
      child: ListTile(
        leading: Icon(icon, color: selected ? BullyColors.blurple : BullyPalette.of(context).textMuted),
        title: Text(label, style: TextStyle(color: BullyPalette.of(context).textNormal)),
        trailing: selected ? const Icon(Icons.check_circle, color: BullyColors.blurple) : null,
        onTap: onTap,
      ),
    );
  }
}
