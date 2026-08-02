import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'mesh_gradient.dart';
import 'theme_controller.dart';

class ThemeBackdrop extends StatelessWidget {
  const ThemeBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final controller = ThemeController.instance;
        final points = controller.themeGradient;
        final imagePath = controller.backgroundImagePath;
        final videoPath = controller.backgroundVideoPath;
        if (points == null && imagePath == null && videoPath == null) return const SizedBox.shrink();

        final dark = Theme.of(context).brightness == Brightness.dark;
        final isMedia = imagePath != null || videoPath != null;
        final darken = isMedia ? controller.mediaDarken : (dark ? 0.45 : 0.35);
        final blur = isMedia ? controller.mediaBlur : 0.0;

        Widget media;
        if (points != null) {
          media = MeshGradientBox(points: points, fallbackColor: points.first.color);
        } else if (imagePath != null) {
          media = Image.file(File(imagePath), fit: BoxFit.cover);
        } else {
          media = _VideoBackdrop(key: ValueKey(videoPath), path: videoPath!);
        }

        return Stack(
          children: [
            Positioned.fill(child: media),
            if (blur > 0)
              Positioned.fill(
                child: BackdropFilter(filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: const SizedBox.expand()),
              ),
            Positioned.fill(
              child: Container(color: (dark ? Colors.black : Colors.white).withValues(alpha: darken)),
            ),
          ],
        );
      },
    );
  }
}

class _VideoBackdrop extends StatefulWidget {
  final String path;
  const _VideoBackdrop({super.key, required this.path});

  @override
  State<_VideoBackdrop> createState() => _VideoBackdropState();
}

class _VideoBackdropState extends State<_VideoBackdrop> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.file(File(widget.path));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (mounted) setState(() => _controller = controller);
    } catch (_) {
      controller.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return const SizedBox.shrink();
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}
