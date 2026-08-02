import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'theme_controller.dart';

const _resolution = 40;

Color _blendAt(List<AccentPoint> points, double x, double y) {
  double totalWeight = 0;
  double r = 0, g = 0, b = 0;
  for (final p in points) {
    final dx = x - p.position.dx;
    final dy = y - p.position.dy;
    final distSq = dx * dx + dy * dy;
    final weight = 1 / (distSq + 0.0001);
    totalWeight += weight;
    r += p.color.r * weight;
    g += p.color.g * weight;
    b += p.color.b * weight;
  }
  return Color.from(alpha: 1, red: r / totalWeight, green: g / totalWeight, blue: b / totalWeight);
}

Future<ui.Image> renderMeshGradient(List<AccentPoint> points) {
  final data = Uint8List(_resolution * _resolution * 4);
  for (var py = 0; py < _resolution; py++) {
    final ny = py / (_resolution - 1);
    for (var px = 0; px < _resolution; px++) {
      final nx = px / (_resolution - 1);
      final color = _blendAt(points, nx, ny);
      final i = (py * _resolution + px) * 4;
      data[i] = (color.r * 255).round();
      data[i + 1] = (color.g * 255).round();
      data[i + 2] = (color.b * 255).round();
      data[i + 3] = 255;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(data, _resolution, _resolution, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}

class _MeshImagePainter extends CustomPainter {
  final ui.Image image;
  _MeshImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(canvas: canvas, rect: Offset.zero & size, image: image, fit: BoxFit.cover, filterQuality: FilterQuality.medium);
  }

  @override
  bool shouldRepaint(covariant _MeshImagePainter oldDelegate) => oldDelegate.image != image;
}

class MeshGradientBox extends StatefulWidget {
  final List<AccentPoint>? points;
  final Color fallbackColor;
  final Widget? child;
  final BorderRadius? borderRadius;

  const MeshGradientBox({super.key, required this.points, required this.fallbackColor, this.child, this.borderRadius});

  @override
  State<MeshGradientBox> createState() => _MeshGradientBoxState();
}

class _MeshGradientBoxState extends State<MeshGradientBox> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(covariant MeshGradientBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.points, widget.points)) _render();
  }

  Future<void> _render() async {
    final pts = widget.points;
    if (pts == null || pts.isEmpty) {
      if (mounted) setState(() => _image = null);
      return;
    }
    final image = await renderMeshGradient(pts);
    if (mounted) setState(() => _image = image);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.zero,
      child: Container(
        color: widget.points == null || _image == null ? widget.fallbackColor : null,
        child: widget.points != null && _image != null
            ? CustomPaint(painter: _MeshImagePainter(_image!), child: widget.child)
            : widget.child,
      ),
    );
  }
}
