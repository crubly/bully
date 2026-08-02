import 'package:flutter/material.dart';

import 'ws_client.dart';

class ConnectionBanner extends StatelessWidget {
  final WsClient ws;
  const ConnectionBanner({super.key, required this.ws});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ws.connected,
      builder: (context, connected, _) {
        if (connected) return const SizedBox.shrink();
        return ValueListenableBuilder<String?>(
          valueListenable: ws.lastError,
          builder: (context, error, _) => Material(
            color: Colors.orange.shade900,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error == null ? 'Нет соединения с нодой — переподключение...' : 'Нет соединения с нодой: $error',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
