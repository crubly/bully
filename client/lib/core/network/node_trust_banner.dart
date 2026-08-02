import 'package:flutter/material.dart';

import 'node_trust_monitor.dart';

class NodeTrustBanner extends StatelessWidget {
  const NodeTrustBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NodeTrustMonitor.instance,
      builder: (context, _) {
        if (!NodeTrustMonitor.instance.compromised) return const SizedBox.shrink();
        return Material(
          color: Colors.red.shade900,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.gpp_bad, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Нода скомпрометирована или небезопасна: ${NodeTrustMonitor.instance.reason ?? 'нарушение протокола'}. '
                      'Отправка сообщений и звонки с этой нодой заблокированы.',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
