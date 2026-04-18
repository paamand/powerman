import 'package:flutter/material.dart';
import 'dart:math';

/// A single player's control area overlay.
/// Drag = move, tap = bomb, long-press = super weapon.
/// [rotationDeg]: 0 = bottom (normal), 90 = left side, 180 = top, 270 = right side
class PlayerControlArea extends StatefulWidget {
  final int playerId;
  final int rotationDeg;
  final void Function(int playerId, Offset direction) onMove;
  final void Function(int playerId) onBomb;
  final void Function(int playerId) onSuperWeapon;
  final String label;

  const PlayerControlArea({
    super.key,
    required this.playerId,
    required this.rotationDeg,
    required this.onMove,
    required this.onBomb,
    required this.onSuperWeapon,
    required this.label,
  });

  @override
  State<PlayerControlArea> createState() => _PlayerControlAreaState();
}

class _PlayerControlAreaState extends State<PlayerControlArea> {
  Offset? _dragStart;
  Offset _dragCurrent = Offset.zero;
  bool _isDragging = false;

  Offset get _direction {
    if (_dragStart == null || !_isDragging) return Offset.zero;
    final delta = _dragCurrent - _dragStart!;
    final len = delta.distance;
    if (len < 8) return Offset.zero;
    return Offset(delta.dx / len, delta.dy / len);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) {
        _dragStart = details.localPosition;
        _dragCurrent = details.localPosition;
        _isDragging = true;
      },
      onPanUpdate: (details) {
        _dragCurrent = details.localPosition;
        widget.onMove(widget.playerId, _applyRotation(_direction));
      },
      onPanEnd: (_) {
        _isDragging = false;
        _dragStart = null;
        widget.onMove(widget.playerId, Offset.zero);
      },
      onTap: () => widget.onBomb(widget.playerId),
      onLongPress: () => widget.onSuperWeapon(widget.playerId),
      child: _buildVisual(),
    );
  }

  /// Rotate raw screen-space drag direction into game-space direction.
  /// 0°: identity, 90°: left-side player, 180°: top player, 270°: right-side player
  Offset _applyRotation(Offset dir) {
    switch (widget.rotationDeg) {
      case 90:  return Offset(dir.dy, -dir.dx);  // left side
      case 180: return Offset(-dir.dx, -dir.dy); // top (opposite)
      case 270: return Offset(-dir.dy, dir.dx);  // right side
      default:  return dir;                      // bottom (normal)
    }
  }

  Widget _buildVisual() {
    return CustomPaint(
      painter: _ControlAreaPainter(
        label: widget.label,
        direction: _direction,
        isDragging: _isDragging,
        rotationDeg: widget.rotationDeg,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _ControlAreaPainter extends CustomPainter {
  final String label;
  final Offset direction;
  final bool isDragging;
  final int rotationDeg;

  _ControlAreaPainter({
    required this.label,
    required this.direction,
    required this.isDragging,
    required this.rotationDeg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Background
    final bgPaint = Paint()
      ..color = const Color(0x0A000000)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height).deflate(2), borderPaint);

    // Rotate canvas so all content appears upright for the player
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(rotationDeg * pi / 180);
    // Dimensions in rotated frame
    final rw = rotationDeg == 90 || rotationDeg == 270 ? size.height : size.width;
    final rh = rotationDeg == 90 || rotationDeg == 270 ? size.width : size.height;

    // Direction arrow (in player's local frame — raw drag direction)
    if (isDragging && direction.distance > 0.1) {
      final len = min(rw, rh) * 0.3;
      final arrowPaint = Paint()
        ..color = const Color(0x88000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset.zero,
        Offset(direction.dx * len, direction.dy * len),
        arrowPaint,
      );
    }

    // Label
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0x44000000),
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: rw * 0.9);
    tp.paint(canvas, Offset(-tp.width / 2, rh * 0.3));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ControlAreaPainter old) =>
      old.direction != direction || old.isDragging != isDragging;
}
