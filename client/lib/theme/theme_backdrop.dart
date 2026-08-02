import 'package:flutter/material.dart';

import 'mesh_gradient.dart';
import 'theme_controller.dart';

class ThemeBackdrop extends StatelessWidget {
  const ThemeBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final points = ThemeController.instance.themeGradient;
        if (points == null) return const SizedBox.shrink();
        final dark = Theme.of(context).brightness == Brightness.dark;
        return Stack(
          children: [
            Positioned.fill(child: MeshGradientBox(points: points, fallbackColor: points.first.color)),
            Positioned.fill(
              child: Container(color: (dark ? Colors.black : Colors.white).withValues(alpha: dark ? 0.45 : 0.35)),
            ),
          ],
        );
      },
    );
  }
}
