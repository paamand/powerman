import 'dart:async';

import 'package:flame/components.dart' hide Timer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../lan/lan_network.dart';
import 'constants.dart';
import 'game_engine.dart';
import 'game_painter.dart';
import 'game_state.dart';
import 'player_control.dart';

class GameScreen extends StatefulWidget {
  final int numPlayers;
  final LanHostServer? lanHost;
  final LanClientConnection? lanClient;
  final int localPlayerId;

  const GameScreen({
    super.key,
    required this.numPlayers,
    this.lanHost,
    this.lanClient,
    this.localPlayerId = 0,
  });

  bool get isLan => lanHost != null || lanClient != null;
  bool get isLanHost => lanHost != null;
  bool get isLanClient => lanClient != null;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late GameState _state;
  late GameEngine _engine;
  late AnimationController _animController;

  final List<Offset> _directions = List.filled(4, Offset.zero);

  Timer? _gameLoop;
  static const _kFPS = 60;
  static const _kDT = 1.0 / _kFPS;
  double _animTime = 0;
  bool _gameOverDialogShown = false;

  StreamSubscription<Map<String, dynamic>>? _lanSnapshotSub;
  StreamSubscription<void>? _lanDisconnectSub;

  Offset? _lanDragStart;
  Offset _lanDragCurrent = Offset.zero;
  bool _lanDragging = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);

    _initGame();
    _bindLan();

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
    final players = widget.isLan ? 4 : widget.numPlayers;
    _state = GameState(numPlayers: players);
    _engine = GameEngine(_state);

    if (widget.isLanClient && widget.lanClient!.initialState != null) {
      _state.applyNetworkMap(widget.lanClient!.initialState!);
    }
  }

  void _bindLan() {
    if (!widget.isLan) return;

    if (widget.isLanHost) {
      final host = widget.lanHost!;
      host.snapshotProvider = () => _state.toNetworkMap();
      host.onMove = (playerId, direction) => _directions[playerId] = direction;
      host.onBomb = (playerId) => _engine.deployBomb(playerId);
      host.onSuper = (playerId) => _engine.triggerTimedBombs(playerId);
      host.onPlayerJoined = (playerId) {
        _activateLanPlayer(playerId);
        if (mounted) setState(() {});
      };
      host.onPlayerLeft = (playerId) {
        _deactivateLanPlayer(playerId);
        if (mounted) setState(() {});
      };

      for (int i = 0; i < _state.players.length; i++) {
        if (i == widget.localPlayerId) {
          _activateLanPlayer(i);
        } else {
          _deactivateLanPlayer(i);
        }
      }
    }

    if (widget.isLanClient) {
      final client = widget.lanClient!;
      _lanSnapshotSub = client.snapshots.listen((snapshot) {
        _state.applyNetworkMap(snapshot);
        if (mounted) setState(() {});
      });
      _lanDisconnectSub = client.disconnected.listen((_) {
        if (!mounted) return;
        _gameLoop?.cancel();
        Navigator.of(context).pop();
      });
    }
  }

  void _activateLanPlayer(int playerId) {
    if (playerId < 0 || playerId >= _state.players.length) return;
    final p = _state.players[playerId];
    final sp = _state.spawnPositions()[playerId];
    p.respawn(_state.gridCenter(sp.x, sp.y));
    p.kills = 0;
    _directions[playerId] = Offset.zero;
  }

  void _deactivateLanPlayer(int playerId) {
    if (playerId < 0 || playerId >= _state.players.length) return;

    final p = _state.players[playerId];
    p.alive = false;
    p.respawnTimer = 0;
    p.hasShield = false;
    p.hasSpeedBoost = false;
    p.isGhost = false;
    p.hasTimedBomb = false;
    p.superWeapon = null;
    p.activeBombs = 0;
    _directions[playerId] = Offset.zero;

    _state.bombs.removeWhere((b) => b.playerId == playerId);
  }

  void _tick() {
    if (!mounted) return;

    if (widget.isLanHost) {
      for (int i = 0; i < _state.players.length; i++) {
        final d = _directions[i];
        if (d != Offset.zero) {
          _engine.movePlayer(i, _directionToVector(d), _kDT);
        }
      }
      _engine.update(_kDT);
      widget.lanHost!.broadcastSnapshot(_state.toNetworkMap());
    } else if (!widget.isLanClient) {
      for (int i = 0; i < widget.numPlayers; i++) {
        final d = _directions[i];
        if (d != Offset.zero) {
          _engine.movePlayer(i, _directionToVector(d), _kDT);
        }
      }
      _engine.update(_kDT);
    }

    _animTime += _kDT;

    if (mounted) setState(() {});

    if (_state.gameOver && !_gameOverDialogShown) {
      _gameOverDialogShown = true;
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
        builder: (ctx) {
          final winnerText = _state.winnerId != null
              ? 'Player ${_state.winnerId! + 1} wins!\n(${_state.players[_state.winnerId!].kills} kills)'
              : 'Draw!';

          if (widget.isLan) {
            return AlertDialog(
              title: const Text('Game Over!'),
              content: Text(winnerText, style: const TextStyle(fontSize: 22)),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Leave LAN'),
                ),
              ],
            );
          }

          return AlertDialog(
            title: const Text('Game Over!'),
            content: Text(winnerText, style: const TextStyle(fontSize: 22)),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  setState(() {
                    _gameOverDialogShown = false;
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
          );
        },
      );
    });
  }

  @override
  void dispose() {
    _gameLoop?.cancel();
    _lanSnapshotSub?.cancel();
    _lanDisconnectSub?.cancel();
    if (widget.lanHost != null) unawaited(widget.lanHost!.close());
    if (widget.lanClient != null) unawaited(widget.lanClient!.close());
    _animController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Vector2 _directionToVector(Offset o) => Vector2(o.dx, o.dy);

  void _onMove(int playerId, Offset direction) {
    _directions[playerId] = direction;
    if (widget.isLanClient && playerId == widget.localPlayerId) {
      widget.lanClient!.sendMove(direction);
    }
  }

  void _onBomb(int playerId) {
    if (widget.isLanClient && playerId == widget.localPlayerId) {
      widget.lanClient!.sendBomb();
      return;
    }
    _engine.deployBomb(playerId);
  }

  void _onSuperWeapon(int playerId) {
    if (widget.isLanClient && playerId == widget.localPlayerId) {
      widget.lanClient!.sendSuper();
      return;
    }

    final p = _state.players[playerId];
    if (p.superWeapon == PickupType.timedBomb) {
      _engine.triggerTimedBombs(playerId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: widget.isLan ? _buildLanLayout() : _buildLocalLayout(),
    );
  }

  Widget _buildGameCanvas() {
    return RepaintBoundary(
      child: CustomPaint(
        painter: GamePainter(
          _state,
          _animTime,
          widget.isLan ? 4 : widget.numPlayers,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildOverlayButtonsLayer() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const buttonSize = 36.0;
        final gridW = kGridCols * kTileSize;
        final gridH = kGridRows * kTileSize;
        final scaleX = constraints.maxWidth / gridW;
        final scaleY = constraints.maxHeight / gridH;
        final scale = scaleX < scaleY ? scaleX : scaleY;
        final offsetX = (constraints.maxWidth - gridW * scale) / 2;
        final offsetY = (constraints.maxHeight - gridH * scale) / 2;

        final tileCenterY = offsetY + (kGridRows - 0.5) * kTileSize * scale;
        final leftTileCenterX = offsetX + 0.5 * kTileSize * scale;
        final rightTileCenterX =
            offsetX + (kGridCols - 0.5) * kTileSize * scale;

        final left = (leftTileCenterX - buttonSize / 2).clamp(
          0.0,
          constraints.maxWidth - buttonSize,
        );
        final right = (rightTileCenterX - buttonSize / 2).clamp(
          0.0,
          constraints.maxWidth - buttonSize,
        );
        final top = (tileCenterY - buttonSize / 2).clamp(
          0.0,
          constraints.maxHeight - buttonSize,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: left,
              top: top,
              child: _buildOverlayButton(
                icon: Icons.home_outlined,
                tooltip: 'Menu',
                onTap: () {
                  _gameLoop?.cancel();
                  Navigator.of(context).pop();
                },
              ),
            ),
            Positioned(
              left: right,
              top: top,
              child: _buildOverlayButton(
                icon: Icons.info_outline,
                tooltip: 'Info',
                onTap: _showInfoDialog,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOverlayButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xCC1A1A1A),
          border: Border.all(color: Colors.white24, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
    );
  }

  void _showInfoDialog() {
    final controls = widget.isLan
        ? const [
            Text('DRAG   -> Move your powerman (full battleground)'),
            Text('TAP    -> Drop a bomb'),
            Text('HOLD   -> Trigger super weapon'),
          ]
        : const [
            Text('DRAG   -> Move your powerman'),
            Text('TAP    -> Drop a bomb'),
            Text('HOLD   -> Trigger super weapon'),
          ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How to Play'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'CONTROLS',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ...controls,
              const SizedBox(height: 12),
              const Text(
                'POWER-UPS',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text('Fire    - bigger blast radius (permanent)'),
              const Text('Speed   - faster movement (15s)'),
              const Text('Shield  - invincible (10s)'),
              const Text('Bomb    - extra bomb slot (permanent)'),
              const Text('Ghost   - walk through walls (10s)'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildLanLayout() {
    final local = _state.players[widget.localPlayerId];

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildGameCanvas(),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              _lanDragStart = details.localPosition;
              _lanDragCurrent = details.localPosition;
              _lanDragging = true;
            },
            onPanUpdate: (details) {
              _lanDragCurrent = details.localPosition;
              if (_lanDragStart == null) return;
              final delta = _lanDragCurrent - _lanDragStart!;
              final len = delta.distance;
              if (len < 8) {
                _onMove(widget.localPlayerId, Offset.zero);
                return;
              }
              _onMove(
                widget.localPlayerId,
                Offset(delta.dx / len, delta.dy / len),
              );
            },
            onPanEnd: (_) {
              _lanDragging = false;
              _lanDragStart = null;
              _onMove(widget.localPlayerId, Offset.zero);
            },
            onTap: () => _onBomb(widget.localPlayerId),
            onLongPress: () => _onSuperWeapon(widget.localPlayerId),
            child: CustomPaint(
              painter: _LanDragPainter(
                start: _lanDragStart,
                current: _lanDragCurrent,
                dragging: _lanDragging,
                color: GamePainter.kPlayerColors[widget.localPlayerId],
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        _buildOverlayButtonsLayer(),
        Positioned(top: 14, left: 70, child: _buildPlayerHUDBadge(local)),
      ],
    );
  }

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
            Text(
              '  ${p.respawnTimer > 0 ? '${p.respawnTimer.ceil()}s' : 'OUT'}',
              style: const TextStyle(fontSize: 12, color: Colors.white),
            )
          else ...[
            const SizedBox(width: 4),
            Text(
              ' ${p.kills}',
              style: const TextStyle(fontSize: 11, color: Colors.amber),
            ),
            Text(
              ' ${p.blastRadius}',
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
            Text(
              ' ${p.maxBombs}',
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
            if (p.hasShield) const Text(' S', style: TextStyle(fontSize: 11)),
            if (p.hasSpeedBoost)
              const Text(' V', style: TextStyle(fontSize: 11)),
            if (p.isGhost) const Text(' G', style: TextStyle(fontSize: 11)),
          ],
        ],
      ),
    );
    if (flipped) {
      badge = RotatedBox(quarterTurns: 2, child: badge);
    }
    return badge;
  }

  Widget _buildControlStrip(int playerId, {bool flipped = false}) {
    final p = _state.players[playerId];
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

  Widget _buildLocalLayout() {
    final bool four = widget.numPlayers == 4;
    return Column(
      children: [
        Expanded(
          flex: 2,
          child: four
              ? Row(
                  children: [
                    Expanded(child: _buildControlStrip(2, flipped: true)),
                    Expanded(child: _buildControlStrip(3, flipped: true)),
                  ],
                )
              : _buildControlStrip(1, flipped: true),
        ),
        Expanded(
          flex: 5,
          child: Stack(
            fit: StackFit.expand,
            children: [_buildGameCanvas(), _buildOverlayButtonsLayer()],
          ),
        ),
        Expanded(
          flex: 2,
          child: four
              ? Row(
                  children: [
                    Expanded(child: _buildControlStrip(0, flipped: false)),
                    Expanded(child: _buildControlStrip(1, flipped: false)),
                  ],
                )
              : _buildControlStrip(0, flipped: false),
        ),
      ],
    );
  }
}

class _LanDragPainter extends CustomPainter {
  final Offset? start;
  final Offset current;
  final bool dragging;
  final Color color;

  _LanDragPainter({
    required this.start,
    required this.current,
    required this.dragging,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!dragging || start == null) return;
    final line = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start!, current, line);

    final head = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(current, 8, head);
  }

  @override
  bool shouldRepaint(_LanDragPainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.current != current ||
        oldDelegate.dragging != dragging ||
        oldDelegate.color != color;
  }
}
