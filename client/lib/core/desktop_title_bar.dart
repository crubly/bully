import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/bully_theme.dart';
import 'desktop_window.dart';
import 'network/ws_client.dart';

class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    if (!DesktopWindow.isDesktop) return const SizedBox.shrink();
    final showControls = Platform.isWindows || Platform.isLinux;

    final palette = BullyPalette.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => DesktopWindow.startDragging(),
      onDoubleTap: DesktopWindow.toggleMaximize,
      child: Container(
        height: 32,
        color: palette.bgPrimary,
        child: Row(
          children: [
            Expanded(
              child: Center(
                child: ValueListenableBuilder<bool>(
                  valueListenable: WsClient.connected,
                  builder: (context, connected, _) {
                    if (connected) return const SizedBox.shrink();
                    return const Text(
                      'переподключение...',
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    );
                  },
                ),
              ),
            ),
            if (showControls) ...[
              _TitleBarButton(icon: Icons.remove, color: palette.textMuted, onTap: DesktopWindow.minimize),
              _TitleBarButton(icon: Icons.crop_square, color: palette.textMuted, onTap: DesktopWindow.toggleMaximize),
              _TitleBarButton(icon: Icons.close, color: palette.textMuted, onTap: DesktopWindow.close, danger: true),
            ],
          ],
        ),
      ),
    );
  }
}

class _TitleBarButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool danger;

  const _TitleBarButton({required this.icon, required this.color, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: danger ? Colors.red.withValues(alpha: 0.8) : null,
      child: SizedBox(
        width: 46,
        height: 32,
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}
