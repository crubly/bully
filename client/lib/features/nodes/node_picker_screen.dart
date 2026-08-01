import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/node_store.dart';
import '../../theme/discord_theme.dart';

/// Shown before login (and reachable again from Settings to add another
/// node): the user types a node's address, we verify it's actually a Bully
/// node (GET /node/info) BEFORE ever showing a login form, and only then
/// move on. Every account lives on exactly one node — different nodes are
/// independent servers, not a federated pool.
class NodePickerScreen extends StatefulWidget {
  final void Function(BullyNode node) onNodeReady;
  const NodePickerScreen({super.key, required this.onNodeReady});

  @override
  State<NodePickerScreen> createState() => _NodePickerScreenState();
}

class _NodePickerScreenState extends State<NodePickerScreen> {
  final _urlController = TextEditingController(text: 'http://');
  bool _checking = false;
  String? _error;
  List<BullyNode> _known = [];

  @override
  void initState() {
    super.initState();
    _known = NodeStore.list();
  }

  Future<void> _check() async {
    var url = _urlController.text.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => _error = 'Укажите адрес с http:// или https://');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final name = await probeNode(url);
    if (!mounted) return;
    if (name == null) {
      setState(() {
        _checking = false;
        _error = 'Нода недоступна или это не Bully-сервер.';
      });
      return;
    }
    final node = BullyNode(name, url);
    await NodeStore.add(node);
    await NodeStore.setActive(url);
    widget.onNodeReady(node);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DiscordColors.bgPrimary,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Подключение к ноде', style: TextStyle(color: DiscordColors.textNormal, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'Bully не хостит общий сервер — укажите адрес ноды, к которой хотите подключиться.',
                  style: TextStyle(color: DiscordColors.textMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(labelText: 'Адрес ноды', hintText: 'http://192.168.1.10:8080'),
                  keyboardType: TextInputType.url,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: DiscordColors.danger)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _checking ? null : _check,
                    child: Text(_checking ? 'Проверка...' : 'Проверить и продолжить'),
                  ),
                ),
                if (_known.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Align(alignment: Alignment.centerLeft, child: Text('Известные ноды:', style: TextStyle(color: DiscordColors.textMuted))),
                  ..._known.map((n) => ListTile(
                        leading: const Icon(Icons.dns, color: DiscordColors.blurple),
                        title: Text(n.name, style: const TextStyle(color: DiscordColors.textNormal)),
                        subtitle: Text(n.url, style: const TextStyle(color: DiscordColors.textMuted)),
                        onTap: () {
                          _urlController.text = n.url;
                          _check();
                        },
                      )),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
