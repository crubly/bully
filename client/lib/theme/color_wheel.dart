import 'dart:math' as math;

import 'package:flutter/material.dart';

class _WheelPainter extends CustomPainter {
  final double value;
  _WheelPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    const segments = 360;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var i = 0; i < segments; i++) {
      final hue = i * 360 / segments;
      final startAngle = (i / segments) * 2 * math.pi - math.pi / 2;
      final sweep = 2 * math.pi / segments + 0.02;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [HSVColor.fromAHSV(1, hue, 0, value).toColor(), HSVColor.fromAHSV(1, hue, 1, value).toColor()],
        ).createShader(rect);
      canvas.drawArc(rect, startAngle, sweep, true, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) => oldDelegate.value != value;
}

class HsvColorWheel extends StatefulWidget {
  final Color initial;
  final ValueChanged<Color> onChanged;
  final double size;

  const HsvColorWheel({super.key, required this.initial, required this.onChanged, this.size = 220});

  @override
  State<HsvColorWheel> createState() => _HsvColorWheelState();
}

class _HsvColorWheelState extends State<HsvColorWheel> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  void _handleTap(Offset local) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final d = local - center;
    final radius = widget.size / 2;
    final dist = d.distance.clamp(0, radius);
    final angle = math.atan2(d.dy, d.dx);
    var hue = (angle * 180 / math.pi + 90) % 360;
    if (hue < 0) hue += 360;
    final saturation = dist / radius;
    setState(() => _hsv = _hsv.withHue(hue).withSaturation(saturation.toDouble()));
    widget.onChanged(_hsv.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.size / 2;
    final angleRad = (_hsv.hue - 90) * math.pi / 180;
    final knobDist = _hsv.saturation * radius;
    final knobPos = Offset(radius + knobDist * math.cos(angleRad), radius + knobDist * math.sin(angleRad));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onPanDown: (d) => _handleTap(d.localPosition),
          onPanUpdate: (d) => _handleTap(d.localPosition),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              children: [
                CustomPaint(size: Size(widget.size, widget.size), painter: _WheelPainter(_hsv.value)),
                Positioned(
                  left: knobPos.dx - 10,
                  top: knobPos.dy - 10,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _hsv.toColor(),
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: widget.size,
          child: Slider(
            value: _hsv.value,
            activeColor: _hsv.toColor(),
            onChanged: (v) {
              setState(() => _hsv = _hsv.withValue(v));
              widget.onChanged(_hsv.toColor());
            },
          ),
        ),
      ],
    );
  }
}
