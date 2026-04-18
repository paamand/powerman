import 'dart:math';
import 'package:flame/components.dart';
import 'game_state.dart';
import 'constants.dart';

class GameEngine {
  final GameState state;
  final Random _rng = Random();

  GameEngine(this.state);

  // Move player in direction (dx, dy) normalized over dt seconds
  void movePlayer(int playerId, Vector2 direction, double dt) {
    final p = state.players[playerId];
    if (!p.alive) return;

    final speed = p.effectiveSpeed * dt;
    final newPos = p.position + direction * speed;

    // Resolve collision axis by axis
    final resolved = _resolveCollision(p.position, newPos, p.isGhost);
    p.position = resolved;

    // Pick up power-ups
    final cell = state.pixelToGrid(p.position);
    final tile = state.grid[cell.y][cell.x];
    if (tile.powerUp != null) {
      _applyPowerUp(p, tile.powerUp!);
      tile.powerUp = null;
      tile.powerUpTimer = null;
    }
  }

  Vector2 _resolveCollision(Vector2 current, Vector2 desired, bool ghost) {
    const margin = 6.0; // shrink hitbox slightly
    final half = kTileSize / 2 - margin;

    // Try full movement
    if (_canOccupy(desired, half, ghost)) return desired;

    // Try X only
    final xOnly = Vector2(desired.x, current.y);
    if (_canOccupy(xOnly, half, ghost)) return xOnly;

    // Try Y only
    final yOnly = Vector2(current.x, desired.y);
    if (_canOccupy(yOnly, half, ghost)) return yOnly;

    return current;
  }

  bool _canOccupy(Vector2 pos, double half, bool ghost) {
    // Check all four corners
    final corners = [
      Vector2(pos.x - half, pos.y - half),
      Vector2(pos.x + half, pos.y - half),
      Vector2(pos.x - half, pos.y + half),
      Vector2(pos.x + half, pos.y + half),
    ];
    for (final c in corners) {
      final col = (c.x / kTileSize).floor();
      final row = (c.y / kTileSize).floor();
      if (state.isSolid(col, row, ghost: ghost)) return false;
    }
    return true;
  }

  // Returns false if bomb could not be placed (cooldown/max)
  bool deployBomb(int playerId) {
    final p = state.players[playerId];
    if (!p.alive) return false;
    if (p.activeBombs >= p.maxBombs) return false;

    final cell = state.pixelToGrid(p.position);
    // Don't stack bombs
    for (final b in state.bombs) {
      if (b.position.x == cell.x && b.position.y == cell.y) return false;
    }

    bool isTimed = p.superWeapon == SuperWeaponType.timedBomb;
    bool isSuper = p.superWeapon == SuperWeaponType.superBomb;
    if (isSuper || isTimed) p.superWeapon = null;

    state.bombs.add(BombState(
      position: Vector2(cell.x.toDouble(), cell.y.toDouble()),
      playerId: playerId,
      timer: kBombFuse,
      isTimed: isTimed,
      isSuper: isSuper,
      blastRadius: p.blastRadius,
    ));
    p.activeBombs++;
    return true;
  }

  // Trigger timed bomb for player (long press)
  void triggerTimedBombs(int playerId) {
    for (final b in state.bombs) {
      if (b.playerId == playerId && b.isTimed) {
        b.timer = 0;
      }
    }
  }

  void update(double dt) {
    if (state.gameOver) return;

    // Update power-up timers
    for (int r = 0; r < kGridRows; r++) {
      for (int c = 0; c < kGridCols; c++) {
        final tile = state.grid[r][c];
        if (tile.powerUpTimer != null) {
          tile.powerUpTimer = tile.powerUpTimer! - dt;
          if (tile.powerUpTimer! <= 0) {
            tile.powerUp = null;
            tile.powerUpTimer = null;
          }
        }
      }
    }

    state.trySpawnPowerUp(dt);

    // Update player boost timers
    for (final p in state.players) {
      if (!p.alive) continue;
      if (p.hasSpeedBoost) {
        p.speedBoostTimer -= dt;
        if (p.speedBoostTimer <= 0) p.hasSpeedBoost = false;
      }
      if (p.hasShield) {
        p.shieldTimer -= dt;
        if (p.shieldTimer <= 0) p.hasShield = false;
      }
      if (p.isGhost) {
        p.ghostTimer -= dt;
        if (p.ghostTimer <= 0) {
          p.isGhost = false;
          // Push out of walls if inside one
          _pushOutOfWall(p);
        }
      }
    }

    // Update bombs
    final explodingBombs = <BombState>[];
    for (final b in state.bombs) {
      b.timer -= dt;
      if (b.timer <= 0) {
        explodingBombs.add(b);
      }
    }
    for (final b in explodingBombs) {
      _explodeBomb(b);
    }

    // Update explosion lifetimes
    state.explosions.removeWhere((e) {
      e.lifetime -= dt;
      return e.lifetime <= 0;
    });

    // Tick respawn timers
    final spawns = state.spawnPositions();
    for (final p in state.players) {
      if (!p.alive && p.respawnTimer > 0) {
        p.respawnTimer -= dt;
        if (p.respawnTimer <= 0) {
          final sp = spawns[p.id];
          p.respawn(state.gridCenter(sp.x, sp.y));
        }
      }
    }
  }

  void _explodeBomb(BombState bomb) {
    state.bombs.remove(bomb);
    state.players[bomb.playerId].activeBombs =
        (state.players[bomb.playerId].activeBombs - 1).clamp(0, 999);

    final cx = bomb.position.x.toInt();
    final cy = bomb.position.y.toInt();

    // Add explosion at center
    _addExplosion(cx, cy, bomb.playerId);

    // Spread in 4 directions
    const dirs = [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1]
    ];

    for (final dir in dirs) {
      int maxR = bomb.isSuper ? 999 : bomb.blastRadius;
      for (int i = 1; i <= maxR; i++) {
        int nx = cx + dir[0] * i;
        int ny = cy + dir[1] * i;

        if (nx < 0 || nx >= kGridCols || ny < 0 || ny >= kGridRows) break;

        final tile = state.grid[ny][nx];

        if (tile.type == TileType.permanent) break; // stop at permanent wall

        _addExplosion(nx, ny, bomb.playerId);

        if (tile.type == TileType.wood) {
          tile.type = TileType.empty; // destroy wood
          // Maybe drop a power-up
          if (_rng.nextDouble() < 0.5) {
            const weighted = [
              PowerUpType.bomb, PowerUpType.bomb, PowerUpType.bomb,
              PowerUpType.fire, PowerUpType.fire, PowerUpType.fire,
              PowerUpType.speed,
              PowerUpType.shield,
              PowerUpType.ghost,
            ];
            tile.powerUp = weighted[_rng.nextInt(weighted.length)];
            tile.powerUpTimer = kPowerUpLifetime;
          }
          if (!bomb.isSuper) break; // super bomb passes through
        }

        // Chain explode other bombs
        final chainBombs = state.bombs
            .where((b) => b.position.x.toInt() == nx && b.position.y.toInt() == ny)
            .toList();
        for (final cb in chainBombs) {
          cb.timer = 0;
        }
      }
    }
  }

  void _addExplosion(int x, int y, int killerId) {
    state.explosions.add(ExplosionCell(x, y, 0.5));

    // Check if players are hit
    for (final p in state.players) {
      if (!p.alive) continue;
      final cell = state.pixelToGrid(p.position);
      if (cell.x == x && cell.y == y) {
        if (!p.hasShield) {
          p.die();
          // Credit kill — not self-kill
          if (killerId != p.id) {
            state.players[killerId].kills++;
            // Check win condition
            if (state.players[killerId].kills >= kWinKills) {
              state.gameOver = true;
              state.winnerId = killerId;
            }
          }
        }
      }
    }
  }

  void _pushOutOfWall(PlayerState p) {
    final cell = state.pixelToGrid(p.position);
    if (state.grid[cell.y][cell.x].type != TileType.wood) return;
    // Try adjacent cells
    final adj = [
      Point(cell.x + 1, cell.y),
      Point(cell.x - 1, cell.y),
      Point(cell.x, cell.y + 1),
      Point(cell.x, cell.y - 1),
    ];
    for (final a in adj) {
      if (!state.isSolid(a.x, a.y)) {
        p.position = state.gridCenter(a.x, a.y);
        return;
      }
    }
  }

  void _applyPowerUp(PlayerState p, PowerUpType pu) {
    switch (pu) {
      case PowerUpType.fire:
        p.blastRadius++;
        break;
      case PowerUpType.speed:
        p.hasSpeedBoost = true;
        p.speedBoostTimer = kSpeedBoostDuration;
        break;
      case PowerUpType.shield:
        p.hasShield = true;
        p.shieldTimer = kShieldDuration;
        break;
      case PowerUpType.bomb:
        p.maxBombs++;
        break;
      case PowerUpType.ghost:
        p.isGhost = true;
        p.ghostTimer = kGhostDuration;
        break;
    }
  }
}
