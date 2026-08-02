import 'package:flutter/material.dart';

import '../../theme/color_wheel.dart';
import '../../theme/mesh_gradient.dart';
import '../../theme/theme_controller.dart';

class GradientEditor extends StatefulWidget {
  final List<AccentPoint> initial;
  final ValueChanged<List<AccentPoint>> onChanged;
  final double size;

  const GradientEditor({super.key, required this.initial, required this.onChanged, this.size = 260});

  @override
  State<GradientEditor> createState() => _GradientEditorState();
}

bool _samePoints(List<AccentPoint> a, List<AccentPoint> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].position != b[i].position || a[i].color.toARGB32() != b[i].color.toARGB32()) return false;
  }
  return true;
}

class _GradientEditorState extends State<GradientEditor> {
  late List<AccentPoint> _points = List.of(widget.initial);
  List<AccentPoint>? _lastReported;
  final _squareKey = GlobalKey();

  @override
  void didUpdateWidget(covariant GradientEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_samePoints(widget.initial, _points) && (_lastReported == null || !_samePoints(widget.initial, _lastReported!))) {
      _points = List.of(widget.initial);
    }
  }

  void _report() {
    _lastReported = List.of(_points);
    widget.onChanged(_points);
  }

  void _addPoint() {
    setState(() => _points = [..._points, AccentPoint(const Offset(0.5, 0.5), _points.last.color)]);
    _report();
  }

  void _removePoint(int i) {
    if (_points.length <= 2) return;
    setState(() => _points = [..._points]..removeAt(i));
    _report();
  }

  void _movePoint(int i, Offset newPos) {
    final clamped = Offset(newPos.dx.clamp(0.0, 1.0), newPos.dy.clamp(0.0, 1.0));
    setState(() => _points = [..._points]..[i] = AccentPoint(clamped, _points[i].color));
    _report();
  }

  Future<void> _pickColor(int i) async {
    final color = await showDialog<Color>(
      context: context,
      builder: (context) => _PointColorDialog(initial: _points[i].color),
    );
    if (color == null) return;
    setState(() => _points = [..._points]..[i] = AccentPoint(_points[i].position, color));
    _report();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          key: _squareKey,
          width: widget.size,
          height: widget.size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: MeshGradientBox(points: _points, fallbackColor: _points.first.color),
                ),
              ),
              for (var i = 0; i < _points.length; i++)
                Positioned(
                  left: _points[i].position.dx * widget.size - 14,
                  top: _points[i].position.dy * widget.size - 14,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerMove: (e) {
                      final box = _squareKey.currentContext!.findRenderObject() as RenderBox;
                      final local = box.globalToLocal(e.position);
                      _movePoint(i, Offset(local.dx / widget.size, local.dy / widget.size));
                    },
                    child: GestureDetector(
                      onTap: () => _pickColor(i),
                      onLongPress: () => _removePoint(i),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _points[i].color,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: _addPoint, icon: const Icon(Icons.add, size: 18), label: const Text('Добавить точку')),
        const SizedBox(height: 4),
        Text(
          'Перетащите точку — переместить, нажмите — цвет, зажмите — удалить',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color),
        ),
      ],
    );
  }
}

class _PointColorDialog extends StatefulWidget {
  final Color initial;
  const _PointColorDialog({required this.initial});

  @override
  State<_PointColorDialog> createState() => _PointColorDialogState();
}

class _PointColorDialogState extends State<_PointColorDialog> {
  late Color _color = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Цвет точки'),
      content: HsvColorWheel(initial: _color, onChanged: (c) => _color = c),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        ElevatedButton(onPressed: () => Navigator.of(context).pop(_color), child: const Text('Применить')),
      ],
    );
  }
}
