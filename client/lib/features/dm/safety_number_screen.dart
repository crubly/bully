import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_services.dart';
import '../../core/crypto/safety_number.dart';
import '../../core/desktop_window.dart';
import '../../theme/bully_theme.dart';

const _qrPrefix = 'bully-safety:';

class SafetyNumberScreen extends StatefulWidget {
  final String peerUserId;
  final String peerUsername;
  const SafetyNumberScreen({super.key, required this.peerUserId, required this.peerUsername});

  @override
  State<SafetyNumberScreen> createState() => _SafetyNumberScreenState();
}

class _SafetyNumberScreenState extends State<SafetyNumberScreen> {
  String? _safetyNumber;
  String? _error;
  bool? _matchResult;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    try {
      final services = AppServices.of(context);
      await services.crypto.ensureIdentity();
      final ownKey = services.crypto.identity.publicKeyBytes;
      final bundle = await services.api.fetchKeyBundle(widget.peerUserId);
      final peerKey = Uint8List.fromList(base64Decode(bundle['signed_public_key'] as String));
      final number = await SafetyNumber.compute(ownKey, peerKey);
      if (mounted) setState(() => _safetyNumber = number);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _scanAndCompare() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _SafetyQrScannerScreen()),
    );
    if (scanned == null || !mounted) return;
    final theirNumber = scanned.substring(_qrPrefix.length);
    setState(() => _matchResult = theirNumber == _safetyNumber);
  }

  @override
  Widget build(BuildContext context) {
    final number = _safetyNumber;
    return Scaffold(
      backgroundColor: BullyPalette.of(context).bgPrimary,
      appBar: AppBar(backgroundColor: BullyPalette.of(context).bgPrimary, title: const Text('Проверка безопасности')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Сравните этот код с ${widget.peerUsername} лично, голосом или отсканировав QR друг у друга. '
                'Если код совпадает — никто не подменил ключи шифрования между вами (в том числе роутер или провайдер).',
                style: TextStyle(color: BullyPalette.of(context).textMuted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (_error != null) Text(_error!, style: const TextStyle(color: BullyColors.danger)),
              if (number == null && _error == null) const CircularProgressIndicator(),
              if (number != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: BullyPalette.of(context).bgSecondary,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: BullyPalette.of(context).cardBorder),
                  ),
                  child: Text(
                    number,
                    style: TextStyle(color: BullyPalette.of(context).textNormal, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: QrImageView(data: '$_qrPrefix$number', version: QrVersions.auto, size: 200),
                ),
                if (!DesktopWindow.isDesktop) ...[
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _scanAndCompare,
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: const Text('Сканировать код собеседника'),
                  ),
                ],
                if (_matchResult != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_matchResult! ? Icons.verified : Icons.gpp_bad, color: _matchResult! ? BullyColors.online : BullyColors.danger),
                      const SizedBox(width: 8),
                      Text(
                        _matchResult! ? 'Коды совпадают — безопасно' : 'Коды НЕ совпадают — возможна подмена ключей!',
                        style: TextStyle(color: _matchResult! ? BullyColors.online : BullyColors.danger, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SafetyQrScannerScreen extends StatelessWidget {
  const _SafetyQrScannerScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сканировать код проверки')),
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
