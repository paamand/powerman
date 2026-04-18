import 'package:flutter/material.dart';
import 'dart:math';

/// A single player's control area overlay.
/// Drag = move, tap = bomb, long-press = super weapon.
/// Direction is passed raw (no rotation) — drag "up" always moves up in game space.
class PlayerControlArea extends StatefulWidget {
  final int playerId;
  final Color playerColor;
  final void Function(int playerId, Offset direction) onMove;
  final void Function(int playerId) onBomb;
  final void Function(int playerId) onSuperWeapon;
  final String label;

  const PlayerControlArea({
    super.key,
    required this.playerId,
    required this.playerColor,
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
        widget.onMove(widget.playerId, _direction);
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

  Widget _buildVisual() {
    return CustomPaint(
      painter: _ControlAreaPainter(
        label: widget.label,
        direction: _direction,
        isDragging: _isDragging,
        playerColor: widget.playerColor,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _ControlAreaPainter extends CustomPainter {
  final String label;
  final Offset direction;
  final bool isDragging;
  final Color playerColor;

  _ControlAreaPainter({
    required this.label,
    required this.direction,
    required this.isDragging,
    required this.playerColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = playerColor.withValues(alpha:0.06)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final borderPaint = Paint()
      ..color = playerColor.withValues(alpha:0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height).deflate(1.5), borderPaint);

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Direction arrow (raw screen drag direction)
    if (isDragging && direction.distance > 0.1) {
      final len = min(size.width, size.height) * 0.3;
      final arrowPaint = Paint()
        ..color = playerColor.withValues(alpha:0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + direction.dx * len, cy + direction.dy * len),
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
    tp.layout(maxWidth: size.width * 0.9);
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_ControlAreaPainter old) =>
      old.direction != direction || old.isDragging != isDragging || old.playerColor != playerColor;
}
