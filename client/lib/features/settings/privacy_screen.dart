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
  Future<void> _onTapLocalPassword(BuildContext context) async {
    if (!AppLock.instance.enabled) {
      final result = await showDialog<String>(
        context: context,
        builder: (context) => const _SetPasswordDialog(),
      );
      if (result == null) return;
      await AppLock.instance.setup(result, AutoLockDuration.fiveMinutes);
      if (context.mounted) await AppServices.of(context).crypto.rewrapIdentity();
      return;
    }

    final password = await showDialog<String>(
      context: context,
      builder: (context) => const _EnterPasswordDialog(title: 'Введите текущий пароль'),
    );
    if (password == null) return;
    final ok = await AppLock.instance.unlock(password);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Неверный пароль')));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _LocalPasswordSettingsScreen()));
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
              decoration: BoxDecoration(
                color: BullyPalette.of(context).bgSecondary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: BullyPalette.of(context).cardBorder),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: Icon(Icons.lock_outline, color: enabled ? BullyColors.online : BullyPalette.of(context).textMuted),
                title: Text('Локальный пароль', style: TextStyle(color: BullyPalette.of(context).textNormal)),
                subtitle: Text(
                  enabled ? 'Включён — нажмите для настройки' : 'Выключен — нажмите, чтобы включить',
                  style: TextStyle(color: BullyPalette.of(context).textMuted),
                ),
                trailing: Icon(Icons.chevron_right, color: BullyPalette.of(context).textMuted),
                onTap: () => _onTapLocalPassword(context),
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

class _LocalPasswordSettingsScreen extends StatelessWidget {
  const _LocalPasswordSettingsScreen();

  Future<void> _changePassword(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const _SetPasswordDialog(title: 'Новый пароль/PIN'),
    );
    if (result == null) return;
    await AppLock.instance.changePassword(result);
    if (context.mounted) await AppServices.of(context).crypto.rewrapIdentity();
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Пароль изменён')));
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
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BullyPalette.of(context).bgPrimary,
      appBar: AppBar(backgroundColor: BullyPalette.of(context).bgPrimary, title: const Text('Локальный пароль')),
      body: ListenableBuilder(
        listenable: AppLock.instance,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: BullyPalette.of(context).bgSecondary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: BullyPalette.of(context).cardBorder),
              ),
              child: Column(
                children: [
                  ListTile(
                    title: Text('Блокировать после бездействия', style: TextStyle(color: BullyPalette.of(context).textNormal)),
                    subtitle: Text(AppLock.instance.autoLock.label, style: TextStyle(color: BullyPalette.of(context).textMuted)),
                    trailing: DropdownButton<AutoLockDuration>(
                      value: AppLock.instance.autoLock,
                      dropdownColor: BullyPalette.of(context).bgSecondary,
                      items: AutoLockDuration.values.map((d) => DropdownMenuItem(value: d, child: Text(d.label))).toList(),
                      onChanged: (d) {
                        if (d != null) AppLock.instance.setAutoLock(d);
                      },
                    ),
                  ),
                  Divider(color: BullyPalette.of(context).cardBorder, height: 1),
                  ListTile(
                    leading: Icon(Icons.password, color: BullyPalette.of(context).textMuted),
                    title: Text('Сменить пароль/PIN', style: TextStyle(color: BullyPalette.of(context).textNormal)),
                    onTap: () => _changePassword(context),
                  ),
                  Divider(color: BullyPalette.of(context).cardBorder, height: 1),
                  ListTile(
                    leading: const Icon(Icons.lock_open, color: BullyColors.danger),
                    title: const Text('Отключить локальный пароль', style: TextStyle(color: BullyColors.danger)),
                    onTap: () => _disable(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetPasswordDialog extends StatefulWidget {
  final String title;
  const _SetPasswordDialog({this.title = 'Задать локальный пароль'});

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
      title: Text(widget.title, style: TextStyle(color: BullyPalette.of(context).textNormal)),
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
          child: const Text('Сохранить'),
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
