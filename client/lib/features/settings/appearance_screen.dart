import 'package:flutter/material.dart';

import '../../theme/bully_theme.dart';
import '../../theme/color_wheel.dart';
import '../../theme/mesh_gradient.dart';
import '../../theme/theme_controller.dart';
import 'app_icon_screen.dart';
import 'gradient_editor.dart';

enum _ThemeTab { gradient, presets }

class AppearanceScreen extends StatefulWidget {
  final bool embedded;
  const AppearanceScreen({super.key, this.embedded = false});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  _ThemeTab _tab = _ThemeTab.gradient;

  Widget _body(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final accentGradient = ThemeController.instance.themeGradient;
        final accentColor = ThemeController.instance.accentColor;
        return ListView(
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
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Акцентный цвет', style: TextStyle(color: BullyPalette.of(context).textMuted, fontSize: 12)),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: BullyPalette.of(context).bgSecondary, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: HsvColorWheel(
                      initial: accentColor,
                      onChanged: (c) => ThemeController.instance.setAccentColor(c),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: accentPresets
                        .where((p) => p.color != null)
                        .map((p) => _ColorSwatch(
                              color: p.color!,
                              selected: accentColor.toARGB32() == p.color!.toARGB32(),
                              onTap: () => ThemeController.instance.setAccentColor(p.color!),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => ThemeController.instance.resetAccentColor(),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Сбросить'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Тема', style: TextStyle(color: BullyPalette.of(context).textMuted, fontSize: 12)),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: BullyPalette.of(context).bgSecondary, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MeshGradientBox(
                    points: accentGradient,
                    fallbackColor: accentColor,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 56,
                      alignment: Alignment.center,
                      child: const Text('Bully', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<_ThemeTab>(
                    segments: const [
                      ButtonSegment(value: _ThemeTab.gradient, label: Text('Градиент'), icon: Icon(Icons.gradient, size: 16)),
                      ButtonSegment(value: _ThemeTab.presets, label: Text('Готовые'), icon: Icon(Icons.style, size: 16)),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                  const SizedBox(height: 16),
                  if (_tab == _ThemeTab.gradient)
                    Center(
                      child: GradientEditor(
                        initial: accentGradient ??
                            [
                              AccentPoint(const Offset(0, 0), accentColor),
                              AccentPoint(const Offset(1, 1), const Color(0xFFEB459E)),
                            ],
                        onChanged: (points) => ThemeController.instance.setThemeGradientPoints(points),
                      ),
                    ),
                  if (_tab == _ThemeTab.presets)
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: accentPresets
                          .map((p) => _PresetSwatch(
                                preset: p,
                                onTap: () => ThemeController.instance.applyPreset(p),
                              ))
                          .toList(),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => ThemeController.instance.resetThemeGradient(),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Сбросить'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ThemeOption(
              label: 'Иконка приложения',
              icon: Icons.apps,
              selected: false,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AppIconScreen())),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _body(context);
    return Scaffold(
      backgroundColor: BullyPalette.of(context).bgPrimary,
      appBar: AppBar(backgroundColor: BullyPalette.of(context).bgPrimary, title: const Text('Оформление')),
      body: _body(context),
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
        trailing: selected ? Icon(Icons.check_circle, color: BullyColors.blurple) : null,
        onTap: onTap,
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatch({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected ? Border.all(color: Colors.white, width: 2.5) : null,
          boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)] : null,
        ),
        child: selected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
      ),
    );
  }
}

class _PresetSwatch extends StatelessWidget {
  final AccentPreset preset;
  final VoidCallback onTap;

  const _PresetSwatch({required this.preset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            MeshGradientBox(
              points: preset.gradient,
              fallbackColor: preset.color ?? defaultAccentColor,
              borderRadius: BorderRadius.circular(12),
              child: const SizedBox(width: 56, height: 56),
            ),
            const SizedBox(height: 4),
            Text(preset.name, style: TextStyle(fontSize: 11, color: BullyPalette.of(context).textMuted), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
