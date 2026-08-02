import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/bully_theme.dart';
import 'desktop_window.dart';

class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    if (!DesktopWindow.isDesktop) return const SizedBox.shrink();
    final showControls = Platform.isWindows || Platform.isLinux;
    final macos = Platform.isMacOS;

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
            if (macos) const SizedBox(width: 70),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: macos ? 0 : 12),
                child: ValueListenableBuilder<String>(
                  valueListenable: DesktopWindow.title,
                  builder: (context, title, _) => Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: palette.textNormal),
                  ),
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
