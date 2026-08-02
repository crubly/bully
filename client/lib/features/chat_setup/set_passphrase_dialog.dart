import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/desktop_window.dart';
import '../../theme/bully_theme.dart';

const _qrPrefix = 'bully-pass:';

Future<String?> showSetPassphraseDialog(BuildContext context, {required String otherPartyLabel}) {
  final controller = TextEditingController();
  final confirmController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  Future<void> showQr(BuildContext context) async {
    if (controller.text.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BullyPalette.of(context).bgSecondary,
        title: Text('QR-код пароля', style: TextStyle(color: BullyPalette.of(context).textNormal)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: QrImageView(
                data: '$_qrPrefix${controller.text}',
                version: QrVersions.auto,
                size: 220,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Покажите этот код собеседнику — пусть отсканирует его вместо ввода пароля вручную.',
              style: TextStyle(color: BullyPalette.of(context).textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Закрыть')),
        ],
      ),
    );
  }

  Future<void> scanQr(BuildContext context) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScannerScreen()),
    );
    if (result != null && result.startsWith(_qrPrefix)) {
      final passphrase = result.substring(_qrPrefix.length);
      controller.text = passphrase;
      confirmController.text = passphrase;
    }
  }

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: BullyPalette.of(context).bgSecondary,
        title: Text('Пароль шифрования чата', style: TextStyle(color: BullyPalette.of(context).textNormal)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Придумайте пароль и сообщите его собеседнику ($otherPartyLabel) любым другим способом '
                '(голосом, лично, QR-кодом, в другом мессенджере). Сервер этот пароль никогда не увидит — '
                'им шифруется только ваша переписка на устройствах.',
                style: TextStyle(color: BullyPalette.of(context).textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Пароль шифрования'),
                validator: (v) => (v == null || v.length < 8) ? 'Минимум 8 символов' : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Повторите пароль'),
                validator: (v) => v != controller.text ? 'Пароли не совпадают' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: controller.text.isEmpty ? null : () => showQr(context),
                      icon: const Icon(Icons.qr_code, size: 18),
                      label: const Text('Показать QR'),
                    ),
                  ),
                  if (!DesktopWindow.isDesktop) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => scanQr(context),
                        icon: const Icon(Icons.qr_code_scanner, size: 18),
                        label: const Text('Сканировать'),
                      ),
                    ),
                  ],
                ],
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
    ),
  );
}

class _QrScannerScreen extends StatelessWidget {
  const _QrScannerScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сканировать QR пароля')),
      body: MobileScanner(
        onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            final value = barcode.rawValue;
            if (value != null && value.startsWith(_qrPrefix)) {
              Navigator.of(context).pop(value);
              return;
            }
          }
        },
      ),
    );
  }
}
