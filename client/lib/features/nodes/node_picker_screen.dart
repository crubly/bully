import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/node_store.dart';
import '../../theme/bully_theme.dart';

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
    final stored = NodeStore.active() ?? node;
    if (!mounted) return;
    if (stored.flaggedCompromised) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: BullyPalette.of(context).bgSecondary,
          title: const Text('Нода помечена как скомпрометированная', style: TextStyle(color: BullyColors.danger)),
          content: Text(
            stored.flagReason ?? 'Эта нода ранее нарушала протокол шифрования/паддинга. Продолжать небезопасно.',
            style: TextStyle(color: BullyPalette.of(context).textNormal),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Отмена')),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Всё равно продолжить', style: TextStyle(color: BullyColors.danger)),
            ),
          ],
        ),
      );
      if (proceed != true) {
        setState(() => _checking = false);
        return;
      }
    }
    widget.onNodeReady(node);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BullyPalette.of(context).bgPrimary,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Подключение к ноде', style: TextStyle(color: BullyPalette.of(context).textNormal, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  'Bully не хостит общий сервер — укажите адрес ноды, к которой хотите подключиться.',
                  style: TextStyle(color: BullyPalette.of(context).textMuted),
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
                  Text(_error!, style: const TextStyle(color: BullyColors.danger)),
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
                  Align(alignment: Alignment.centerLeft, child: Text('Известные ноды:', style: TextStyle(color: BullyPalette.of(context).textMuted))),
                  ..._known.map((n) => ListTile(
                        leading: Icon(n.flaggedCompromised ? Icons.gpp_bad : Icons.dns, color: n.flaggedCompromised ? BullyColors.danger : BullyColors.blurple),
                        title: Text(n.name, style: TextStyle(color: BullyPalette.of(context).textNormal)),
                        subtitle: Text(
                          n.flaggedCompromised ? 'Скомпрометирована — ${n.url}' : n.url,
                          style: TextStyle(color: n.flaggedCompromised ? BullyColors.danger : BullyPalette.of(context).textMuted),
                        ),
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
