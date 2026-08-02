import 'package:flutter/material.dart';

import '../../theme/bully_theme.dart';
import '../../theme/theme_controller.dart';
import 'app_icon_screen.dart';

const _presetAccents = [
  defaultAccentColor,
  Color(0xFFEB459E),
  Color(0xFFDA373C),
  Color(0xFFF0B232),
  Color(0xFF23A559),
  Color(0xFF00A8FC),
  Color(0xFF9B59B6),
];

class AppearanceScreen extends StatelessWidget {
  final bool embedded;
  const AppearanceScreen({super.key, this.embedded = false});

  Future<void> _pickCustomColor(BuildContext context) async {
    final color = await showDialog<Color>(
      context: context,
      builder: (context) => const _ColorPickerDialog(),
    );
    if (color != null) await ThemeController.instance.setAccentColor(color);
  }

  Future<void> _pickGradient(BuildContext context) async {
    final result = await showDialog<List<Color>>(
      context: context,
      builder: (context) => const _GradientPickerDialog(),
    );
    if (result != null) await ThemeController.instance.setAccentGradient(result[0], result[1]);
  }

  Widget _body(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final accentGradient = ThemeController.instance.accentGradient;
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
                  Container(
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: accentGradient == null ? accentColor : null,
                      gradient: accentGradient != null
                          ? LinearGradient(colors: accentGradient, begin: Alignment.centerLeft, end: Alignment.centerRight)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: const Text('Bully', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final c in _presetAccents)
                        _ColorSwatch(
                          color: c,
                          selected: accentGradient == null && accentColor.toARGB32() == c.toARGB32(),
                          onTap: () => ThemeController.instance.setAccentColor(c),
                        ),
                      _CustomSwatchButton(onTap: () => _pickCustomColor(context)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickGradient(context),
                          icon: const Icon(Icons.gradient, size: 18),
                          label: const Text('Градиент'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => ThemeController.instance.resetAccent(),
                          icon: const Icon(Icons.restart_alt, size: 18),
                          label: const Text('Сбросить'),
                        ),
                      ),
                    ],
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
    if (embedded) return _body(context);
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

class _CustomSwatchButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CustomSwatchButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: BullyPalette.of(context).textMuted),
        ),
        child: Icon(Icons.add, size: 18, color: BullyPalette.of(context).textMuted),
      ),
    );
  }
}

class _RgbSliders extends StatefulWidget {
  final Color initial;
  final ValueChanged<Color> onChanged;
  const _RgbSliders({required this.initial, required this.onChanged});

  @override
  State<_RgbSliders> createState() => _RgbSlidersState();
}

class _RgbSlidersState extends State<_RgbSliders> {
  late double _r = widget.initial.r * 255;
  late double _g = widget.initial.g * 255;
  late double _b = widget.initial.b * 255;

  Color get _color => Color.fromARGB(255, _r.round(), _g.round(), _b.round());

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 48, width: double.infinity, decoration: BoxDecoration(color: _color, borderRadius: BorderRadius.circular(8))),
        const SizedBox(height: 12),
        _slider('R', _r, Colors.red, (v) => setState(() => _r = v)),
        _slider('G', _g, Colors.green, (v) => setState(() => _g = v)),
        _slider('B', _b, Colors.blue, (v) => setState(() => _b = v)),
      ],
    );
  }

  Widget _slider(String label, double value, Color color, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 16, child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold))),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            activeColor: color,
            onChanged: (v) {
              onChanged(v);
              widget.onChanged(_color);
            },
          ),
        ),
      ],
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog();

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  Color _color = ThemeController.instance.accentColor;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: BullyPalette.of(context).bgSecondary,
      title: Text('Свой цвет', style: TextStyle(color: BullyPalette.of(context).textNormal)),
      content: _RgbSliders(initial: _color, onChanged: (c) => _color = c),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        ElevatedButton(onPressed: () => Navigator.of(context).pop(_color), child: const Text('Применить')),
      ],
    );
  }
}

class _GradientPickerDialog extends StatefulWidget {
  const _GradientPickerDialog();

  @override
  State<_GradientPickerDialog> createState() => _GradientPickerDialogState();
}

class _GradientPickerDialogState extends State<_GradientPickerDialog> {
  Color _start = ThemeController.instance.accentGradient?.first ?? ThemeController.instance.accentColor;
  Color _end = ThemeController.instance.accentGradient?.last ?? const Color(0xFFEB459E);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: BullyPalette.of(context).bgSecondary,
      title: Text('Градиент', style: TextStyle(color: BullyPalette.of(context).textNormal)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(colors: [_start, _end]),
              ),
            ),
            const SizedBox(height: 12),
            Text('Начало', style: TextStyle(color: BullyPalette.of(context).textMuted, fontSize: 12)),
            _RgbSliders(initial: _start, onChanged: (c) => setState(() => _start = c)),
            const SizedBox(height: 8),
            Text('Конец', style: TextStyle(color: BullyPalette.of(context).textMuted, fontSize: 12)),
            _RgbSliders(initial: _end, onChanged: (c) => setState(() => _end = c)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        ElevatedButton(onPressed: () => Navigator.of(context).pop([_start, _end]), child: const Text('Применить')),
      ],
    );
  }
}
