import 'dart:math';
import 'package:flutter/material.dart';
import 'game_state.dart';
import 'constants.dart';

class GamePainter extends CustomPainter {
  final GameState state;
  final double animTime;

  GamePainter(this.state, this.animTime);

  @override
  void paint(Canvas canvas, Size size) {
    // Scale to fit
    final gridW = kGridCols * kTileSize;
    final gridH = kGridRows * kTileSize;
    final scaleX = size.width / gridW;
    final scaleY = size.height / gridH;
    final scale = min(scaleX, scaleY);

    final offsetX = (size.width - gridW * scale) / 2;
    final offsetY = (size.height - gridH * scale) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);

    _drawBackground(canvas);
    _drawGrid(canvas);
    _drawPowerUps(canvas);
    _drawBombs(canvas);
    _drawExplosions(canvas);
    _drawPlayers(canvas);

    canvas.restore();
  }

  void _drawBackground(Canvas canvas) {
    final bgPaint = Paint()..color = const Color(0xFFF5F5F0);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, kGridCols * kTileSize, kGridRows * kTileSize),
      bgPaint,
    );
  }

  void _drawGrid(Canvas canvas) {
    final permPaint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.fill;
    final woodPaint = Paint()
      ..color = const Color(0xFFD4B896)
      ..style = PaintingStyle.fill;
    final woodStroke = Paint()
      ..color = const Color(0xFF8B6540)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final gridPaint = Paint()
      ..color = const Color(0xFFCCCCBB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (int r = 0; r < kGridRows; r++) {
      for (int c = 0; c < kGridCols; c++) {
        final tile = state.grid[r][c];
        final rect = Rect.fromLTWH(c * kTileSize, r * kTileSize, kTileSize, kTileSize);

        switch (tile.type) {
          case TileType.permanent:
            canvas.drawRect(rect, permPaint);
            _drawSketchRect(canvas, rect, const Color(0xFF444444), 2.0);
            break;
          case TileType.wood:
            canvas.drawRect(rect, woodPaint);
            canvas.drawRect(rect, woodStroke);
            _drawWoodGrain(canvas, rect);
            break;
          case TileType.empty:
            canvas.drawRect(rect, gridPaint);
            break;
        }
      }
    }
  }

  void _drawWoodGrain(Canvas canvas, Rect rect) {
    final grainPaint = Paint()
      ..color = const Color(0x448B6540)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    // Few diagonal lines
    final path = Path();
    for (double offset = 0; offset < rect.width * 1.5; offset += 12) {
      path.moveTo(rect.left + offset, rect.top);
      path.lineTo(rect.left + offset - rect.height * 0.4, rect.bottom);
    }
    canvas.drawPath(path, grainPaint);
  }

  void _drawSketchRect(Canvas canvas, Rect rect, Color color, double strokeWidth) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawRect(rect.deflate(1), paint);
  }

  void _drawPowerUps(Canvas canvas) {
    for (int r = 0; r < kGridRows; r++) {
      for (int c = 0; c < kGridCols; c++) {
        final tile = state.grid[r][c];
        if (tile.powerUp == null) continue;

        final cx = c * kTileSize + kTileSize / 2;
        final cy = r * kTileSize + kTileSize / 2;
        final pulse = sin(animTime * 4) * 2;
        final _ = 14.0 + pulse; // pulse unused but kept for future

        final bgPaint = Paint()
          ..color = _powerUpColor(tile.powerUp!).withOpacity(0.85)
          ..style = PaintingStyle.fill;
        final strokePaint = Paint()
          ..color = _powerUpColor(tile.powerUp!).withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;

        // Draw crate box
        final boxRect = Rect.fromCenter(
            center: Offset(cx, cy), width: kTileSize * 0.7, height: kTileSize * 0.7);
        final rrect = RRect.fromRectAndRadius(boxRect, const Radius.circular(4));
        canvas.drawRRect(rrect, bgPaint);
        canvas.drawRRect(rrect, strokePaint);

        // Draw icon letter
        final tp = TextPainter(
          text: TextSpan(
            text: _powerUpLetter(tile.powerUp!),
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
      }
    }
  }

  Color _powerUpColor(PowerUpType pu) {
    switch (pu) {
      case PowerUpType.fire:
        return const Color(0xFFE84545);
      case PowerUpType.speed:
        return const Color(0xFF4ECDC4);
      case PowerUpType.shield:
        return const Color(0xFF3D85C8);
      case PowerUpType.bomb:
        return const Color(0xFF9B59B6);
      case PowerUpType.ghost:
        return const Color(0xFF95A5A6);
    }
  }

  String _powerUpLetter(PowerUpType pu) {
    switch (pu) {
      case PowerUpType.fire:
        return 'F';
      case PowerUpType.speed:
        return 'S';
      case PowerUpType.shield:
        return 'Sh';
      case PowerUpType.bomb:
        return 'B';
      case PowerUpType.ghost:
        return 'G';
    }
  }

  void _drawBombs(Canvas canvas) {
    for (final bomb in state.bombs) {
      final cx = bomb.position.x * kTileSize + kTileSize / 2;
      final cy = bomb.position.y * kTileSize + kTileSize / 2;

      // Pulsate based on fuse
      final progress = bomb.timer / kBombFuse;
      final pulse = sin(animTime * (2 + (1 - progress) * 10)) * 3;
      final radius = 16.0 + pulse;

      final bodyPaint = Paint()
        ..color = const Color(0xFF1A1A1A)
        ..style = PaintingStyle.fill;
      final highlightPaint = Paint()
        ..color = const Color(0xFF555555)
        ..style = PaintingStyle.fill;

      // Body
      canvas.drawCircle(Offset(cx, cy), radius, bodyPaint);
      // Highlight
      canvas.drawCircle(Offset(cx - radius * 0.3, cy - radius * 0.3), radius * 0.25,
          highlightPaint);

      // Fuse spark
      final fuseColor =
          bomb.timer < 1.0 ? const Color(0xFFFF4444) : const Color(0xFFFFAA00);
      final fusePaint = Paint()
        ..color = fuseColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(cx + radius * 0.5, cy - radius * 0.6),
        Offset(cx + radius * 0.9, cy - radius),
        fusePaint,
      );

      // Super bomb marker
      if (bomb.isSuper) {
        final sPaint = Paint()
          ..color = Colors.red
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(Offset(cx, cy), radius + 4, sPaint);
      }
    }
  }

  void _drawExplosions(Canvas canvas) {
    for (final exp in state.explosions) {
      final rect =
          Rect.fromLTWH(exp.x * kTileSize, exp.y * kTileSize, kTileSize, kTileSize);
      final alpha = (exp.lifetime * 2).clamp(0.0, 1.0);
      final inner = Rect.fromCenter(
          center: rect.center, width: kTileSize * 0.9, height: kTileSize * 0.9);

      final outerPaint = Paint()
        ..color = Color.fromARGB((alpha * 200).toInt(), 255, 200, 0)
        ..style = PaintingStyle.fill;
      final innerPaint = Paint()
        ..color = Color.fromARGB((alpha * 255).toInt(), 255, 80, 0)
        ..style = PaintingStyle.fill;

      canvas.drawRect(inner, outerPaint);
      canvas.drawRect(
          Rect.fromCenter(center: rect.center, width: kTileSize * 0.4, height: kTileSize * 0.4),
          innerPaint);
    }
  }

  static const List<Color> kPlayerColors = [
    Color(0xFF2C3E50),
    Color(0xFFC0392B),
    Color(0xFF27AE60),
    Color(0xFFE67E22),
  ];

  void _drawPlayers(Canvas canvas) {
    for (final p in state.players) {
      if (!p.alive) continue;

      final cx = p.position.x;
      final cy = p.position.y;
      final color = kPlayerColors[p.id];

      // Shield glow
      if (p.hasShield) {
        final shieldPaint = Paint()
          ..color = const Color(0x883D85C8)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(cx, cy), 22, shieldPaint);
      }

      // Ghost translucency
      final alpha = p.isGhost ? 0.45 : 1.0;

      // Body (circle)
      final bodyPaint = Paint()
        ..color = color.withOpacity(alpha)
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = Colors.black.withOpacity(alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(Offset(cx, cy), 16, bodyPaint);
      canvas.drawCircle(Offset(cx, cy), 16, strokePaint);

      // Eyes
      final eyePaint = Paint()
        ..color = Colors.white.withOpacity(alpha)
        ..style = PaintingStyle.fill;
      final pupilPaint = Paint()
        ..color = Colors.black.withOpacity(alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(cx - 5, cy - 4), 4, eyePaint);
      canvas.drawCircle(Offset(cx + 5, cy - 4), 4, eyePaint);
      canvas.drawCircle(Offset(cx - 5, cy - 4), 2, pupilPaint);
      canvas.drawCircle(Offset(cx + 5, cy - 4), 2, pupilPaint);

      // Player label
      final tp = TextPainter(
        text: TextSpan(
          text: 'P${p.id + 1}',
          style: TextStyle(
            color: Colors.white.withOpacity(alpha),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, cy + 18));

      // Speed indicator
      if (p.hasSpeedBoost) {
        _drawStatusIcon(canvas, cx - 16, cy - 28, '⚡', alpha);
      }
      if (p.isGhost) {
        _drawStatusIcon(canvas, cx, cy - 28, '👻', alpha);
      }
    }
  }

  void _drawStatusIcon(Canvas canvas, double x, double y, String icon, double alpha) {
    final tp = TextPainter(
      text: TextSpan(text: icon, style: TextStyle(fontSize: 12)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
  }

  @override
  bool shouldRepaint(GamePainter oldDelegate) => true;
}
