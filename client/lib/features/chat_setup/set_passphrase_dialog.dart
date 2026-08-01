import 'package:flutter/material.dart';

import '../../theme/discord_theme.dart';

/// Shown before the first message in a new DM/group. Returns the passphrase
/// the user chose, or null if cancelled. The caller must have already told
/// the human to share this passphrase with the other participant(s) through
/// a different channel (voice call, in person, etc.) — the server never
/// sees it.
Future<String?> showSetPassphraseDialog(BuildContext context, {required String otherPartyLabel}) {
  final controller = TextEditingController();
  final confirmController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      backgroundColor: DiscordColors.bgSecondary,
      title: const Text('Пароль шифрования чата', style: TextStyle(color: DiscordColors.textNormal)),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Придумайте пароль и сообщите его собеседнику ($otherPartyLabel) любым другим способом '
              '(голосом, лично, в другом мессенджере). Сервер этот пароль никогда не увидит — '
              'им шифруется только ваша переписка на устройствах.',
              style: const TextStyle(color: DiscordColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Пароль шифрования'),
              validator: (v) => (v == null || v.length < 8) ? 'Минимум 8 символов' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: confirmController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Повторите пароль'),
              validator: (v) => v != controller.text ? 'Пароли не совпадают' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.of(context).pop(controller.text);
            }
          },
          child: const Text('Начать чат'),
        ),
      ],
    ),
  );
}
