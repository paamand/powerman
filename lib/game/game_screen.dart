import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flame/components.dart' hide Timer;
import 'dart:async';
import 'game_state.dart';
import 'game_engine.dart';
import 'game_painter.dart';
import 'player_control.dart';

class GameScreen extends StatefulWidget {
  final int numPlayers;

  const GameScreen({super.key, required this.numPlayers});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  late GameState _state;
  late GameEngine _engine;
  late AnimationController _animController;

  // Per-player movement direction
  final List<Offset> _directions = List.filled(4, Offset.zero);

  Timer? _gameLoop;
  static const _kFPS = 60;
  static const _kDT = 1.0 / _kFPS;
  double _animTime = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _initGame();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(days: 1),
    )..forward();

    _gameLoop = Timer.periodic(
      const Duration(microseconds: 1000000 ~/ _kFPS),
      (_) => _tick(),
    );
  }

  void _initGame() {
    _state = GameState(numPlayers: widget.numPlayers);
    _engine = GameEngine(_state);
  }

  void _tick() {
    if (!mounted) return;
    for (int i = 0; i < widget.numPlayers; i++) {
      final d = _directions[i];
      if (d != Offset.zero) {
        _engine.movePlayer(i, _directionToVector(d), _kDT);
      }
    }
    _engine.update(_kDT);
    _animTime += _kDT;

    if (mounted) setState(() {});

    if (_state.gameOver) {
      _gameLoop?.cancel();
      _showGameOverDialog();
    }
  }

  void _showGameOverDialog() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Game Over!'),
          content: Text(
            _state.winnerId != null
                ? 'Player ${_state.winnerId! + 1} wins!'
                : 'Draw!',
            style: const TextStyle(fontSize: 22),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                setState(() {
                  _initGame();
                  _directions.fillRange(0, 4, Offset.zero);
                  _gameLoop = Timer.periodic(
                    const Duration(microseconds: 1000000 ~/ _kFPS),
                    (_) => _tick(),
                  );
                });
              },
              child: const Text('Play Again'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              child: const Text('Menu'),
            ),
          ],
        ),
      );
    });
  }

  @override
  void dispose() {
    _gameLoop?.cancel();
    _animController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Vector2 _directionToVector(Offset o) => Vector2(o.dx, o.dy);

  void _onMove(int playerId, Offset direction) {
    _directions[playerId] = direction;
  }

  void _onBomb(int playerId) {
    _engine.deployBomb(playerId);
  }

  void _onSuperWeapon(int playerId) {
    // First check if player has timed bomb super-weapon (long-press triggers it)
    final p = _state.players[playerId];
    if (p.superWeapon == SuperWeaponType.timedBomb) {
      _engine.triggerTimedBombs(playerId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildLayout(),
    );
  }

  Widget _buildGameCanvas() {
    return RepaintBoundary(
      child: CustomPaint(
        painter: GamePainter(_state, _animTime, widget.numPlayers),
        child: const SizedBox.expand(),
      ),
    );
  }

  /// HUD badge for a single player, placed inside their control strip.
  /// [flipped] rotates 180° so top-strip players can read it.
  Widget _buildPlayerHUDBadge(PlayerState p, {bool flipped = false}) {
    final color = GamePainter.kPlayerColors[p.id];
    Widget badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'P${p.id + 1}',
            style: TextStyle(
              color: p.alive ? color : Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          if (!p.alive)
            const Text(' 💀', style: TextStyle(fontSize: 12))
          else ...[
            const SizedBox(width: 4),
            Text('🔥${p.blastRadius}',
                style: const TextStyle(fontSize: 11, color: Colors.white)),
            Text(' 💣${p.maxBombs}',
                style: const TextStyle(fontSize: 11, color: Colors.white)),
            if (p.hasShield) const Text(' 🛡', style: TextStyle(fontSize: 11)),
            if (p.hasSpeedBoost) const Text(' ⚡', style: TextStyle(fontSize: 11)),
            if (p.isGhost) const Text(' 👻', style: TextStyle(fontSize: 11)),
          ],
        ],
      ),
    );
    if (flipped) {
      badge = RotatedBox(quarterTurns: 2, child: badge);
    }
    return badge;
  }

  /// A control strip for one player with their HUD badge near the game edge.
  /// [flipped]: true for top-strip players (badge at top of strip, rotated 180°).
  Widget _buildControlStrip(int playerId, {bool flipped = false}) {
    final p = _state.players[playerId];
    // For top-strip (flipped): game edge is at the BOTTOM of the strip,
    // badge is near the bottom so it's closest to game, but rotated 180° for readability.
    // For bottom-strip (normal): game edge is at the TOP of the strip,
    // badge is near the top.
    return Stack(
      fit: StackFit.expand,
      children: [
        PlayerControlArea(
          playerId: playerId,
          playerColor: GamePainter.kPlayerColors[playerId],
          onMove: _onMove,
          onBomb: _onBomb,
          onSuperWeapon: _onSuperWeapon,
          label: 'P${playerId + 1}  TAP=BOMB  HOLD=SUPER',
        ),
        Align(
          alignment: flipped ? Alignment.bottomCenter : Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: _buildPlayerHUDBadge(p, flipped: flipped),
          ),
        ),
      ],
    );
  }

  Widget _buildLayout() {
    final bool four = widget.numPlayers == 4;
    return Column(
      children: [
        // Top control strip — players P2 (2P) or P3+P4 (4P), flipped 180°
        Expanded(
          flex: 2,
          child: four
              ? Row(children: [
                  Expanded(child: _buildControlStrip(2, flipped: true)),
                  Expanded(child: _buildControlStrip(3, flipped: true)),
                ])
              : _buildControlStrip(1, flipped: true),
        ),
        // Game area (no shared HUD — each player has their own in the strip)
        Expanded(
          flex: 5,
          child: _buildGameCanvas(),
        ),
        // Bottom control strip — P1 (2P) or P1+P2 (4P), normal orientation
        Expanded(
          flex: 2,
          child: four
              ? Row(children: [
                  Expanded(child: _buildControlStrip(0, flipped: false)),
                  Expanded(child: _buildControlStrip(1, flipped: false)),
                ])
              : _buildControlStrip(0, flipped: false),
        ),
      ],
    );
  }
}

// Extension to fill a list range
extension ListFillRange<T> on List<T> {
  void fillRange(int start, int end, T value) {
    for (int i = start; i < end; i++) {
      this[i] = value;
    }
  }
}
