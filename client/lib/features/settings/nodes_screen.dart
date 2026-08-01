import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/node_store.dart';
import '../../theme/bully_theme.dart';
import '../nodes/node_picker_screen.dart';

class NodesScreen extends StatefulWidget {
  final bool embedded;
  const NodesScreen({super.key, this.embedded = false});

  @override
  State<NodesScreen> createState() => _NodesScreenState();
}

class _NodesScreenState extends State<NodesScreen> {
  List<BullyNode> _nodes = [];

  @override
  void initState() {
    super.initState();
    _nodes = NodeStore.list();
  }

  Future<void> _addNode() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NodePickerScreen(
        onNodeReady: (node) => Navigator.of(context).pop(),
      ),
    ));
    setState(() => _nodes = NodeStore.list());
  }

  Future<void> _switchTo(BullyNode node) async {
    await NodeStore.setActive(node.url);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BullyPalette.of(context).bgSecondary,
        title: Text('Нода изменена', style: TextStyle(color: BullyPalette.of(context).textNormal)),
        content: Text('Активная нода теперь ${node.name}. Перезапустите приложение, чтобы подключиться к ней.',
            style: TextStyle(color: BullyPalette.of(context).textMuted)),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Ок'))],
      ),
    );
  }

  Widget _list(BuildContext context, String activeUrl) {
    return ListView(
      children: _nodes
          .map((n) => ListTile(
                leading: Icon(Icons.dns, color: n.url == activeUrl ? BullyColors.online : BullyColors.blurple),
                title: Text(n.name, style: TextStyle(color: BullyPalette.of(context).textNormal)),
                subtitle: Text(n.url, style: TextStyle(color: BullyPalette.of(context).textMuted)),
                trailing: n.url == activeUrl ? const Text('текущая', style: TextStyle(color: BullyColors.online)) : null,
                onTap: n.url == activeUrl ? null : () => _switchTo(n),
              ))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeUrl = AppServices.of(context).api.baseUrl;
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: Text('Ноды', style: TextStyle(color: BullyPalette.of(context).textNormal, fontSize: 20, fontWeight: FontWeight.bold))),
                IconButton(icon: const Icon(Icons.add), onPressed: _addNode, tooltip: 'Добавить ноду'),
              ],
            ),
          ),
          Expanded(child: _list(context, activeUrl)),
        ],
      );
    }
    return Scaffold(
      backgroundColor: BullyPalette.of(context).bgPrimary,
      appBar: AppBar(
        backgroundColor: BullyPalette.of(context).bgPrimary,
        title: const Text('Ноды'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _addNode, tooltip: 'Добавить ноду')],
      ),
      body: _list(context, activeUrl),
    );
  }
}
