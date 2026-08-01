import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/device_info.dart';
import '../../core/storage/secure_store.dart';
import '../../core/transfer/device_transfer_service.dart';
import '../../theme/discord_theme.dart';

/// "Перенести чаты" flow: either show a pairing code as the source device
/// (which already has chat data), or scan the LAN for a source and pull its
/// snapshot as the freshly-installed target device. Both devices must
/// already be logged into the same account and on the same local network.
class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

enum _Mode { choose, hosting, joining }

class _TransferScreenState extends State<TransferScreen> {
  _Mode _mode = _Mode.choose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DiscordColors.bgPrimary,
      appBar: AppBar(backgroundColor: DiscordColors.bgPrimary, title: const Text('Перенос чатов')),
      body: switch (_mode) {
        _Mode.choose => _ChooseView(onHost: () => setState(() => _mode = _Mode.hosting), onJoin: () => setState(() => _mode = _Mode.joining)),
        _Mode.hosting => const _HostView(),
        _Mode.joining => const _JoinView(),
      },
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
              const Text(
                'Оба устройства должны быть в одной локальной сети и войти в один и тот же аккаунт.',
                style: TextStyle(color: DiscordColors.textMuted),
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
            const Icon(Icons.check_circle, color: DiscordColors.online, size: 48),
            const SizedBox(height: 12),
            const Text('Перенос завершён', style: TextStyle(color: DiscordColors.textNormal, fontSize: 18)),
          ] else ...[
            const Text('Введите этот код на новом устройстве:', style: TextStyle(color: DiscordColors.textMuted)),
            const SizedBox(height: 16),
            SelectableText(
              _host!.code,
              style: const TextStyle(color: DiscordColors.textNormal, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2, fontFamily: 'monospace'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            const Text('Ожидание подключения...', style: TextStyle(color: DiscordColors.textMuted)),
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
    final code = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: DiscordColors.bgSecondary,
          title: const Text('Введите код', style: TextStyle(color: DiscordColors.textNormal)),
          content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: '32-значный код')),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Перенести')),
          ],
        );
      },
    );
    if (code == null || code.isEmpty) return;

    setState(() {
      _transferring = true;
      _error = null;
    });
    try {
      await _join.pullSnapshot(host: h.host, port: h.port, code: code);
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
          Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: DiscordColors.danger))),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Устройства, найденные в сети:', style: TextStyle(color: DiscordColors.textMuted)),
        ),
        Expanded(
          child: _hosts.isEmpty
              ? const Center(child: Text('Поиск...', style: TextStyle(color: DiscordColors.textMuted)))
              : ListView(
                  children: _hosts
                      .map((h) => ListTile(
                            leading: const Icon(Icons.devices, color: DiscordColors.blurple),
                            title: Text(h.name, style: const TextStyle(color: DiscordColors.textNormal)),
                            onTap: () => _pick(h),
                          ))
                      .toList(),
                ),
        ),
      ],
    );
  }
}
