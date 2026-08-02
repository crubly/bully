import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/security/app_lock.dart';
import '../../theme/bully_theme.dart';

class PrivacyScreen extends StatefulWidget {
  final bool embedded;
  const PrivacyScreen({super.key, this.embedded = false});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  Future<void> _enable(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const _SetPasswordDialog(),
    );
    if (result == null) return;
    await AppLock.instance.setup(result, AutoLockDuration.fiveMinutes);
    if (context.mounted) await AppServices.of(context).crypto.rewrapIdentity();
  }

  Future<void> _disable(BuildContext context) async {
    final password = await showDialog<String>(
      context: context,
      builder: (context) => const _EnterPasswordDialog(title: 'Отключить локальный пароль'),
    );
    if (password == null) return;
    final ok = await AppLock.instance.disable(password);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Неверный пароль')));
      return;
    }
    await AppServices.of(context).crypto.rewrapIdentity();
  }

  Widget _body(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLock.instance,
      builder: (context, _) {
        final enabled = AppLock.instance.enabled;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BullyPalette.of(context).bgSecondary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: BullyPalette.of(context).cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Локальный пароль', style: TextStyle(color: BullyPalette.of(context).textNormal)),
                    subtitle: Text(
                      'Требовать пароль/PIN для доступа к приложению на этом устройстве',
                      style: TextStyle(color: BullyPalette.of(context).textMuted),
                    ),
                    value: enabled,
                    onChanged: (v) => v ? _enable(context) : _disable(context),
                  ),
                  if (enabled) ...[
                    Divider(color: BullyPalette.of(context).cardBorder),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Автоблокировка', style: TextStyle(color: BullyPalette.of(context).textNormal)),
                      subtitle: Text(AppLock.instance.autoLock.label, style: TextStyle(color: BullyPalette.of(context).textMuted)),
                      trailing: DropdownButton<AutoLockDuration>(
                        value: AppLock.instance.autoLock,
                        dropdownColor: BullyPalette.of(context).bgSecondary,
                        items: AutoLockDuration.values
                            .map((d) => DropdownMenuItem(value: d, child: Text(d.label)))
                            .toList(),
                        onChanged: (d) {
                          if (d != null) AppLock.instance.setAutoLock(d);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Ключ шифрования переписки хранится отдельно и шифруется этим паролем — сам пароль не используется '
                'как ключ напрямую, только для разблокировки доступа к уже сгенерированному ключу.',
                style: TextStyle(color: BullyPalette.of(context).textMuted, fontSize: 12),
              ),
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
      appBar: AppBar(backgroundColor: BullyPalette.of(context).bgPrimary, title: const Text('Конфиденциальность')),
      body: _body(context),
    );
  }
}

class _SetPasswordDialog extends StatefulWidget {
  const _SetPasswordDialog();

  @override
  State<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends State<_SetPasswordDialog> {
  final _controller = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: BullyPalette.of(context).bgSecondary,
      title: Text('Задать локальный пароль', style: TextStyle(color: BullyPalette.of(context).textNormal)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _controller,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Пароль или PIN'),
              validator: (v) => (v == null || v.length < 4) ? 'Минимум 4 символа' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Повторите'),
              validator: (v) => v != _controller.text ? 'Не совпадает' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) Navigator.of(context).pop(_controller.text);
          },
          child: const Text('Включить'),
        ),
      ],
    );
  }
}

class _EnterPasswordDialog extends StatefulWidget {
  final String title;
  const _EnterPasswordDialog({required this.title});

  @override
  State<_EnterPasswordDialog> createState() => _EnterPasswordDialogState();
}

class _EnterPasswordDialogState extends State<_EnterPasswordDialog> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: BullyPalette.of(context).bgSecondary,
      title: Text(widget.title, style: TextStyle(color: BullyPalette.of(context).textNormal)),
      content: TextField(
        controller: _controller,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Текущий пароль'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        ElevatedButton(onPressed: () => Navigator.of(context).pop(_controller.text), child: const Text('Подтвердить')),
      ],
    );
  }
}
