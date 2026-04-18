import 'dart:math';
import 'package:flutter/material.dart';
import 'game_state.dart';
import 'constants.dart';

class GamePainter extends CustomPainter {
  final GameState state;
  final double animTime;
  final int numPlayers;

  GamePainter(this.state, this.animTime, this.numPlayers);

  /// Rotation angle (radians) so each player sees their powerman upright.
  /// 2P: P1(bottom)=π, P2(top)=0
  /// 4P: P1(bottom)=π, P2(top)=0, P3(left)=-π/2, P4(right)=π/2
  double _playerAngle(int id) {
    if (numPlayers <= 2) {
      return id == 0 ? 0 : pi;
    }
    switch (id) {
      case 0:
        return pi/3; // bottom
      case 1:
        return -pi/3; // top
      case 2:
        return pi - pi / 3; // left
      default:
        return pi + pi / 3; // right
    }
  }

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
          ..color = _powerUpColor(tile.powerUp!).withValues(alpha:0.85)
          ..style = PaintingStyle.fill;
        final strokePaint = Paint()
          ..color = _powerUpColor(tile.powerUp!).withValues(alpha:0.3)
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
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));

        // Lifetime progress bar along bottom of box
        if (tile.powerUpTimer != null) {
          final frac = (tile.powerUpTimer! / kPowerUpLifetime).clamp(0.0, 1.0);
          final barW = kTileSize * 0.65;
          final barH = 4.0;
          final barX = cx - barW / 2;
          final barY = cy + kTileSize * 0.3;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(barX, barY, barW, barH), const Radius.circular(2)),
            Paint()..color = Colors.black26,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(barX, barY, barW * frac, barH),
                const Radius.circular(2)),
            Paint()
              ..color = _powerUpColor(tile.powerUp!)
              ..style = PaintingStyle.fill,
          );
        }
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

      // Fuse arc (depletes as bomb ticks down, starts full)
      final arcRadius = radius + 7;
      final fuseProgress = (bomb.timer / kBombFuse).clamp(0.0, 1.0);
      final arcBg = Paint()
        ..color = const Color(0x33FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final arcFg = Paint()
        ..color = bomb.timer < 1.0 ? const Color(0xFFFF4444) : const Color(0xFFFFDD00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: arcRadius),
        -pi / 2,
        2 * pi,
        false,
        arcBg,
      );
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: arcRadius),
        -pi / 2,
        2 * pi * fuseProgress,
        false,
        arcFg,
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
      if (!p.alive && p.respawnTimer <= 0) continue;

      final isRespawning = !p.alive && p.respawnTimer > 0;
      final cx = p.position.x;
      final cy = p.position.y;
      final color = kPlayerColors[p.id];
      final alpha = (p.isGhost || isRespawning) ? 0.35 : 1.0;
      final angle = _playerAngle(p.id);

      // Shield glow (not rotated, always circular)
      if (p.hasShield) {
        canvas.drawCircle(
          Offset(cx, cy),
          22,
          Paint()
            ..color = const Color(0x883D85C8)
            ..style = PaintingStyle.fill,
        );
      }

      // Rotate canvas around player center so character faces toward their seat
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);

      // Body
      canvas.drawCircle(Offset.zero, 16,
          Paint()
            ..color = color.withValues(alpha:alpha)
            ..style = PaintingStyle.fill);
      canvas.drawCircle(Offset.zero, 16,
          Paint()
            ..color = Colors.black.withValues(alpha:alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);

      // Eyes (in local frame — eyes always "above" center before rotation)
      final eyePaint = Paint()
        ..color = Colors.white.withValues(alpha:alpha)
        ..style = PaintingStyle.fill;
      final pupilPaint = Paint()
        ..color = Colors.black.withValues(alpha:alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(const Offset(-5, -4), 4, eyePaint);
      canvas.drawCircle(const Offset(5, -4), 4, eyePaint);
      canvas.drawCircle(const Offset(-5, -4), 2, pupilPaint);
      canvas.drawCircle(const Offset(5, -4), 2, pupilPaint);

      // Player label below face
      final tp = TextPainter(
        text: TextSpan(
          text: 'P${p.id + 1}',
          style: TextStyle(
            color: Colors.white.withValues(alpha:alpha),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(-tp.width / 2, 18));

      canvas.restore();

      // Respawn countdown overlay
      if (isRespawning) {
        final secs = p.respawnTimer.ceil().toString();
        final tp = TextPainter(
          text: TextSpan(
            text: secs,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
      }

      // Effect cooldown arcs (drawn un-rotated, around the player)
      if (!isRespawning) _drawEffectArcs(canvas, p, cx, cy);
    }
  }

  /// Small cooldown arcs around the player for timed effects.
  void _drawEffectArcs(Canvas canvas, PlayerState p, double cx, double cy) {
    const arcR = 26.0;
    const stroke = 3.5;
    const gap = 0.15; // radians gap between arcs

    // Layout: shield (top arc), speed (right arc), ghost (left arc)
    // Each occupies a sector; only draw active ones
    final effects = <_EffectArc>[];
    if (p.hasShield) {
      effects.add(_EffectArc(
          frac: (p.shieldTimer / kShieldDuration).clamp(0.0, 1.0),
          color: const Color(0xFF3D85C8),
          startAngle: -pi * 0.8));
    }
    if (p.hasSpeedBoost) {
      effects.add(_EffectArc(
          frac: (p.speedBoostTimer / kSpeedBoostDuration).clamp(0.0, 1.0),
          color: const Color(0xFF4ECDC4),
          startAngle: -pi * 0.1));
    }
    if (p.isGhost) {
      effects.add(_EffectArc(
          frac: (p.ghostTimer / kGhostDuration).clamp(0.0, 1.0),
          color: const Color(0xFF95A5A6),
          startAngle: pi * 0.6));
    }

    final sectorSize = effects.isEmpty ? 0.0 : (2 * pi - gap * effects.length) / effects.length;
    for (int i = 0; i < effects.length; i++) {
      final e = effects[i];
      final bgPaint = Paint()
        ..color = e.color.withValues(alpha:0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      final fgPaint = Paint()
        ..color = e.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: arcR),
          e.startAngle,
          sectorSize,
          false,
          bgPaint);
      canvas.drawArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: arcR),
          e.startAngle,
          sectorSize * e.frac,
          false,
          fgPaint);
    }
  }

  @override
  bool shouldRepaint(GamePainter oldDelegate) => true;
}

class _EffectArc {
  final double frac;
  final Color color;
  final double startAngle;
  _EffectArc({required this.frac, required this.color, required this.startAngle});
}
