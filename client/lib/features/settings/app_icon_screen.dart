import 'package:flutter/material.dart';

import '../../core/app_icon_controller.dart';
import '../../theme/bully_theme.dart';

class AppIconScreen extends StatefulWidget {
  const AppIconScreen({super.key});

  @override
  State<AppIconScreen> createState() => _AppIconScreenState();
}

class _AppIconScreenState extends State<AppIconScreen> {
  String _current = 'default';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AppIconController.currentIcon().then((v) {
      if (mounted) {
        setState(() {
          _current = v;
          _loading = false;
        });
      }
    });
  }

  Future<void> _select(String name) async {
    await AppIconController.setIcon(name);
    if (mounted) setState(() => _current = name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BullyPalette.of(context).bgPrimary,
      appBar: AppBar(backgroundColor: BullyPalette.of(context).bgPrimary, title: const Text('Иконка приложения')),
      body: !AppIconController.isSupported
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Смена значка приложения на рабочем столе/экране не поддерживается на этой платформе.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: BullyPalette.of(context).textMuted),
                ),
              ),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _IconOption(
                      label: 'Стандартная',
                      color: BullyColors.blurple,
                      selected: _current == 'default',
                      onTap: () => _select('default'),
                    ),
                    _IconOption(
                      label: 'Альтернативная',
                      color: const Color(0xFFEB459E),
                      selected: _current == 'alt',
                      onTap: () => _select('alt'),
                    ),
                  ],
                ),
    );
  }
}

class _IconOption extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _IconOption({required this.label, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: BullyPalette.of(context).bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: selected ? Border.all(color: BullyColors.blurple, width: 2) : null,
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10))),
        title: Text(label, style: TextStyle(color: BullyPalette.of(context).textNormal)),
        trailing: selected ? Icon(Icons.check_circle, color: BullyColors.blurple) : null,
        onTap: onTap,
      ),
    );
  }
}
