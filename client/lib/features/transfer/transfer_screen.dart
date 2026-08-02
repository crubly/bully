import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_services.dart';
import '../../core/desktop_window.dart';
import '../../core/device_info.dart';
import '../../core/security/screen_privacy.dart';
import '../../core/storage/secure_store.dart';
import '../../core/transfer/device_transfer_service.dart';
import '../../theme/bully_theme.dart';

const _transferQrPrefix = 'bully-transfer:';

class TransferScreen extends StatefulWidget {
  final bool embedded;
  const TransferScreen({super.key, this.embedded = false});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

enum _Mode { choose, hosting, joining }

class _TransferScreenState extends State<TransferScreen> {
  _Mode _mode = _Mode.choose;

  Widget _body(BuildContext context) {
    return switch (_mode) {
      _Mode.choose => _ChooseView(onHost: () => setState(() => _mode = _Mode.hosting), onJoin: () => setState(() => _mode = _Mode.joining)),
      _Mode.hosting => const _HostView(),
      _Mode.joining => const _JoinView(),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _body(context);
    return Scaffold(
      backgroundColor: BullyPalette.of(context).bgPrimary,
      appBar: AppBar(backgroundColor: BullyPalette.of(context).bgPrimary, title: const Text('Перенос чатов')),
      body: _body(context),
    );
  }
}

class _ChooseView extends StatelessWidget {
  final VoidCallback onHost;
  final VoidCallback onJoin;
  const _ChooseView({required this.onHost, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Оба устройства должны быть в одной локальной сети и войти в один и тот же аккаунт.',
                style: TextStyle(color: BullyPalette.of(context).textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onHost,
                  child: const Text('У меня уже есть чаты на этом устройстве'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onJoin,
                  child: const Text('Это новое устройство — получить чаты'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HostView extends StatefulWidget {
  const _HostView();

  @override
  State<_HostView> createState() => _HostViewState();
}

class _HostViewState extends State<_HostView> {
  TransferHost? _host;
  StreamSubscription<void>? _sub;
  bool _done = false;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final baseUrl = AppServices.of(context).api.baseUrl;
    final username = await SecureStore.getUsername(baseUrl) ?? 'device';
    final host = TransferHost();
    await host.start(deviceLabel: '$username-${DeviceInfo.platform()}');
    _sub = host.onTransferComplete.listen((_) => setState(() => _done = true));
    setState(() => _host = host);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _host?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_host == null) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_done) ...[
            const Icon(Icons.check_circle, color: BullyColors.online, size: 48),
            const SizedBox(height: 12),
            Text('Перенос завершён', style: TextStyle(color: BullyPalette.of(context).textNormal, fontSize: 18)),
          ] else ...[
            Text('Введите этот код на новом устройстве или отсканируйте QR:', style: TextStyle(color: BullyPalette.of(context).textMuted)),
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: ScreenPrivacy.instance,
              builder: (context, _) {
                final hidden = ScreenPrivacy.instance.hideTransferCodes && !_revealed;
                if (hidden) {
                  return OutlinedButton.icon(
                    onPressed: () => setState(() => _revealed = true),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Показать код и QR'),
                  );
                }
                return Column(
                  children: [
                    SelectableText(
                      _host!.code,
                      style: TextStyle(color: BullyPalette.of(context).textNormal, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2, fontFamily: 'monospace'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: QrImageView(
                        data: '$_transferQrPrefix${_host!.code}',
                        version: QrVersions.auto,
                        size: 200,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text('Ожидание подключения...', style: TextStyle(color: BullyPalette.of(context).textMuted)),
          ],
        ],
      ),
    );
  }
}

class _JoinView extends StatefulWidget {
  const _JoinView();

  @override
  State<_JoinView> createState() => _JoinViewState();
}

class _JoinViewState extends State<_JoinView> {
  final TransferJoin _join = TransferJoin();
  StreamSubscription<DiscoveredHost>? _sub;
  final _hosts = <DiscoveredHost>[];
  bool _transferring = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _join.startDiscovery();
    _sub = _join.onHostFound.listen((h) {
      if (_hosts.any((existing) => existing.host == h.host && existing.port == h.port)) return;
      setState(() => _hosts.add(h));
    });
  }

  Future<void> _pick(DiscoveredHost h) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: BullyPalette.of(context).bgSecondary,
          title: Text('Введите код', style: TextStyle(color: BullyPalette.of(context).textNormal)),
          content: Row(
            children: [
              Expanded(
                child: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: '32-значный код')),
              ),
              if (!DesktopWindow.isDesktop)
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Сканировать QR',
                  onPressed: () async {
                    final scanned = await Navigator.of(context).push<String>(
                      MaterialPageRoute(builder: (_) => const _TransferQrScannerScreen()),
                    );
                    if (scanned != null) {
                      final code = scanned.startsWith(_transferQrPrefix) ? scanned.substring(_transferQrPrefix.length) : scanned;
                      setState(() => controller.text = code);
                    }
                  },
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Перенести')),
          ],
        ),
      ),
    );
    if (code == null || code.isEmpty) return;

    setState(() {
      _transferring = true;
      _error = null;
    });
    try {
      await _join.pullSnapshot(host: h.host, port: h.port, code: code);
      if (!mounted) return;
      final services = AppServices.of(context);
      await services.crypto.reloadAfterTransfer();
      services.groupCrypto.clearCaches();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = 'Не удалось перенести чаты: неверный код или обрыв соединения.';
        _transferring = false;
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _join.stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_transferring) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        if (_error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: BullyColors.danger))),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('Устройства, найденные в сети:', style: TextStyle(color: BullyPalette.of(context).textMuted)),
        ),
        Expanded(
          child: _hosts.isEmpty
              ? Center(child: Text('Поиск...', style: TextStyle(color: BullyPalette.of(context).textMuted)))
              : ListView(
                  children: _hosts
                      .map((h) => ListTile(
                            leading: Icon(Icons.devices, color: BullyColors.blurple),
                            title: Text(h.name, style: TextStyle(color: BullyPalette.of(context).textNormal)),
                            onTap: () => _pick(h),
                          ))
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _TransferQrScannerScreen extends StatelessWidget {
  const _TransferQrScannerScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сканировать QR переноса')),
      body: MobileScanner(
        onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            final value = barcode.rawValue;
            if (value != null) {
              Navigator.of(context).pop(value);
              return;
            }
          }
        },
      ),
    );
  }
}
