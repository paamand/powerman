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
      body: widget.numPlayers <= 2
          ? _buildTwoPlayerLayout()
          : _buildFourPlayerLayout(),
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

  Widget _buildHUD() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: Colors.black54,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(widget.numPlayers, (i) {
            final p = _state.players[i];
            return _buildPlayerHUD(p);
          }),
        ),
      ),
    );
  }

  Widget _buildPlayerHUD(PlayerState p) {
    final color = GamePainter.kPlayerColors[p.id];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(4),
        color: p.alive ? color.withOpacity(0.15) : Colors.transparent,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'P${p.id + 1}',
            style: TextStyle(
              color: p.alive ? color : Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          if (!p.alive)
            const Text(' 💀', style: TextStyle(fontSize: 12))
          else ...[
            const SizedBox(width: 4),
            Text('🔥${p.blastRadius}',
                style: const TextStyle(fontSize: 10, color: Colors.white70)),
            Text(' 💣${p.maxBombs}',
                style: const TextStyle(fontSize: 10, color: Colors.white70)),
            if (p.hasShield)
              const Text(' 🛡', style: TextStyle(fontSize: 10)),
            if (p.hasSpeedBoost)
              const Text(' ⚡', style: TextStyle(fontSize: 10)),
            if (p.isGhost)
              const Text(' 👻', style: TextStyle(fontSize: 10)),
          ],
        ],
      ),
    );
  }

  Widget _buildTwoPlayerLayout() {
    // P1 bottom (normal), P2 top (180° flipped)
    return Column(
      children: [
        Expanded(
          flex: 2,
          child: PlayerControlArea(
            playerId: 1,
            playerColor: GamePainter.kPlayerColors[1],
            onMove: _onMove,
            onBomb: _onBomb,
            onSuperWeapon: _onSuperWeapon,
            label: 'P2  TAP=BOMB  HOLD=SUPER',
          ),
        ),
        Expanded(
          flex: 5,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildGameCanvas(),
              _buildHUD(),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: PlayerControlArea(
            playerId: 0,
            playerColor: GamePainter.kPlayerColors[0],
            onMove: _onMove,
            onBomb: _onBomb,
            onSuperWeapon: _onSuperWeapon,
            label: 'P1  TAP=BOMB  HOLD=SUPER',
          ),
        ),
      ],
    );
  }

  Widget _buildFourPlayerLayout() {
    // P1 bottom, P2 top (180°), P3 left side (90°), P4 right side (270°)
    const sideW = 130.0;  // left/right control strip width
    const topBotH = 120.0; // top/bottom control strip height
    return Stack(
      children: [
        Container(color: const Color(0xFF1A1A1A)),
        // Game canvas in center (inset from all 4 sides)
        Positioned(
          top: topBotH,
          bottom: topBotH,
          left: sideW,
          right: sideW,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildGameCanvas(),
              _buildHUD(),
            ],
          ),
        ),
        // P1 - bottom strip (normal orientation)
        Positioned(
          bottom: 0,
          left: sideW,
          right: sideW,
          height: topBotH,
          child: PlayerControlArea(
            playerId: 0,
            playerColor: GamePainter.kPlayerColors[0],
            onMove: _onMove,
            onBomb: _onBomb,
            onSuperWeapon: _onSuperWeapon,
            label: 'P1  TAP=BOMB  HOLD=SUPER',
          ),
        ),
        // P2 - top strip (180° flipped)
        Positioned(
          top: 0,
          left: sideW,
          right: sideW,
          height: topBotH,
          child: PlayerControlArea(
            playerId: 1,
            playerColor: GamePainter.kPlayerColors[1],
            onMove: _onMove,
            onBomb: _onBomb,
            onSuperWeapon: _onSuperWeapon,
            label: 'P2  TAP=BOMB  HOLD=SUPER',
          ),
        ),
        // P3 - left strip
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          width: sideW,
          child: PlayerControlArea(
            playerId: 2,
            playerColor: GamePainter.kPlayerColors[2],
            onMove: _onMove,
            onBomb: _onBomb,
            onSuperWeapon: _onSuperWeapon,
            label: 'P3  TAP=BOMB',
          ),
        ),
        // P4 - right strip
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: sideW,
          child: PlayerControlArea(
            playerId: 3,
            playerColor: GamePainter.kPlayerColors[3],
            onMove: _onMove,
            onBomb: _onBomb,
            onSuperWeapon: _onSuperWeapon,
            label: 'P4  TAP=BOMB',
          ),
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
