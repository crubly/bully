import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/desktop_window.dart';
import '../../core/security/app_lock.dart';
import '../../theme/bully_theme.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _passwordController = TextEditingController();
  String _pin = '';
  String? _error;
  bool _checking = false;

  Future<void> _submit(String value) async {
    if (value.isEmpty) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final ok = await AppLock.instance.unlock(value);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _checking = false;
        _error = 'Неверный пароль';
        _pin = '';
        _passwordController.clear();
      });
    }
  }

  void _onDigit(String digit) {
    if (_pin.length >= 12) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            color: (dark ? Colors.black : Colors.white).withValues(alpha: 0.55),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock, size: 48, color: BullyColors.blurple),
                      const SizedBox(height: 16),
                      Text(
                        'Bully заблокирован',
                        style: TextStyle(color: BullyPalette.of(context).textNormal, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 24),
                      if (_error != null) ...[
                        Text(_error!, style: const TextStyle(color: BullyColors.danger)),
                        const SizedBox(height: 12),
                      ],
                      if (DesktopWindow.isDesktop)
                        _DesktopUnlock(controller: _passwordController, checking: _checking, onSubmit: _submit)
                      else
                        _PinUnlock(pin: _pin, checking: _checking, onDigit: _onDigit, onBackspace: _onBackspace, onSubmit: () => _submit(_pin)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopUnlock extends StatelessWidget {
  final TextEditingController controller;
  final bool checking;
  final ValueChanged<String> onSubmit;

  const _DesktopUnlock({required this.controller, required this.checking, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Локальный пароль'),
          onSubmitted: onSubmit,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: checking ? null : () => onSubmit(controller.text),
            child: Text(checking ? 'Проверка...' : 'Разблокировать'),
          ),
        ),
      ],
    );
  }
}

class _PinUnlock extends StatelessWidget {
  final String pin;
  final bool checking;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;

  const _PinUnlock({
    required this.pin,
    required this.checking,
    required this.onDigit,
    required this.onBackspace,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            pin.length.clamp(0, 12),
            (i) => Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(shape: BoxShape.circle, color: BullyColors.blurple),
            ),
          ),
        ),
        const SizedBox(height: 24),
        for (final row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row.map((d) => _PinButton(label: d, onTap: () => onDigit(d))).toList(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 64, height: 64),
              _PinButton(label: '0', onTap: () => onDigit('0')),
              SizedBox(
                width: 64,
                height: 64,
                child: IconButton(icon: const Icon(Icons.backspace_outlined), onPressed: onBackspace),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: checking || pin.isEmpty ? null : onSubmit,
            child: Text(checking ? 'Проверка...' : 'Разблокировать'),
          ),
        ),
      ],
    );
  }
}

class _PinButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PinButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        width: 64,
        height: 64,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(shape: const CircleBorder()),
          child: Text(label, style: const TextStyle(fontSize: 22)),
        ),
      ),
    );
  }
}
