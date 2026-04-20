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
    final resolved = _resolveCollision(p.position, newPos, p.isGhost, playerId);
    p.position = resolved;
    _wrapPosition(p.position);

    // Pick up power-ups
    final cell = state.pixelToGrid(p.position);
    final tile = state.grid[cell.y][cell.x];
    if (tile.powerUp != null) {
      _applyPowerUp(p, tile.powerUp!);
      tile.powerUp = null;
      tile.powerUpTimer = null;
    }
  }

  Vector2 _resolveCollision(Vector2 current, Vector2 desired, bool ghost, int playerId) {
    const margin = 6.0; // shrink hitbox slightly
    final half = kTileSize / 2 - margin;

    // Try full movement
    if (_canOccupy(desired, half, ghost, playerId, current)) return desired;

    // Try X only
    final xOnly = Vector2(desired.x, current.y);
    if (_canOccupy(xOnly, half, ghost, playerId, current)) return xOnly;

    // Try Y only
    final yOnly = Vector2(current.x, desired.y);
    if (_canOccupy(yOnly, half, ghost, playerId, current)) return yOnly;

    return current;
  }

  bool _canOccupy(Vector2 pos, double radius, bool ghost, int playerId, Vector2 currentPos) {
    // Circle-vs-AABB: check every tile whose bounding box overlaps the circle.
    final minCol = ((pos.x - radius) / kTileSize).floor();
    final maxCol = ((pos.x + radius) / kTileSize).floor();
    final minRow = ((pos.y - radius) / kTileSize).floor();
    final maxRow = ((pos.y + radius) / kTileSize).floor();
    for (int row = minRow; row <= maxRow; row++) {
      for (int col = minCol; col <= maxCol; col++) {
        if (!state.isSolid(col, row, ghost: ghost)) continue;
        // Nearest point on the tile rect to the circle center
        final nearX = pos.x.clamp(col * kTileSize, (col + 1) * kTileSize);
        final nearY = pos.y.clamp(row * kTileSize, (row + 1) * kTileSize);
        final dx = pos.x - nearX;
        final dy = pos.y - nearY;
        if (dx * dx + dy * dy < radius * radius) return false;
      }
    }

    // Check bombs as solid obstacles (ghosts pass through freely).
    if (!ghost) {
      for (final bomb in state.bombs) {
        final bCol = bomb.position.x.toInt();
        final bRow = bomb.position.y.toInt();
        final tileLeft = bCol * kTileSize;
        final tileTop = bRow * kTileSize;
        // If the player's current circle already overlaps this bomb tile,
        // they are escaping it — don't block them further.
        final curNearX = currentPos.x.clamp(tileLeft, tileLeft + kTileSize);
        final curNearY = currentPos.y.clamp(tileTop, tileTop + kTileSize);
        final curDx = currentPos.x - curNearX;
        final curDy = currentPos.y - curNearY;
        if (curDx * curDx + curDy * curDy < radius * radius) continue;
        // Circle-vs-bomb tile for the desired position
        final nearX = pos.x.clamp(tileLeft, tileLeft + kTileSize);
        final nearY = pos.y.clamp(tileTop, tileTop + kTileSize);
        final dx = pos.x - nearX;
        final dy = pos.y - nearY;
        if (dx * dx + dy * dy < radius * radius) return false;
      }
    }

    return true;
  }

  // Returns false if bomb could not be placed (cooldown/max)
  bool deployBomb(int playerId) {
    final p = state.players[playerId];
    if (!p.alive) return false;

    // Timed-bomb super-weapon: detonate all live timed bombs first, then place a new one.
    if (p.superWeapon == PickupType.timedBomb) {
      final myTimedBombs =
          state.bombs.where((b) => b.playerId == playerId && b.isTimed).toList();
      for (final b in myTimedBombs) {
        _explodeBomb(b); // immediately detonates and frees the activeBombs slot
      }
      // Now try to place a fresh timed bomb that never auto-explodes.
      if (p.activeBombs >= p.maxBombs) return false;
      final cell = state.pixelToGrid(p.position);
      for (final b in state.bombs) {
        if (b.position.x == cell.x && b.position.y == cell.y) return false;
      }
      state.bombs.add(BombState(
        position: Vector2(cell.x.toDouble(), cell.y.toDouble()),
        playerId: playerId,
        timer: 9999.0, // never self-explodes; player detonates manually
        isTimed: true,
        isSuper: false,
        blastRadius: p.blastRadius,
      ));
      p.activeBombs++;
      return true;
    }

    if (p.activeBombs >= p.maxBombs) return false;

    final cell = state.pixelToGrid(p.position);
    // Don't stack bombs
    for (final b in state.bombs) {
      if (b.position.x == cell.x && b.position.y == cell.y) return false;
    }

    bool isSuper = p.superWeapon == PickupType.superBomb;
    if (isSuper) p.superWeapon = null;

    state.bombs.add(BombState(
      position: Vector2(cell.x.toDouble(), cell.y.toDouble()),
      playerId: playerId,
      timer: kBombFuse,
      isTimed: false,
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
      if (p.hasTimedBomb) {
        p.timedBombTimer -= dt;
        if (p.timedBombTimer <= 0) {
          p.hasTimedBomb = false;
          p.superWeapon = null;
          _convertTimedBombs(p.id);
        }
      } else {
        // Player lost the timed-bomb effect (died, respawned, etc.) — convert orphans.
        _convertTimedBombs(p.id);
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

    _updateEnemies(dt);
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
          if (_rng.nextDouble() < 0.75) {
            const weighted = [
              PickupType.bomb, PickupType.bomb,
              PickupType.fire, PickupType.fire,
              PickupType.timedBomb,
              PickupType.speed,
              PickupType.shield,
              PickupType.ghost,
              PickupType.superBomb,
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

    // Check if enemies are hit
    for (final e in state.enemies) {
      if (!e.alive) continue;
      final cell = state.pixelToGrid(e.position);
      if (cell.x == x && cell.y == y) {
        e.alive = false;
        state.players[killerId].kills++;
        if (state.players[killerId].kills >= kWinKills) {
          state.gameOver = true;
          state.winnerId = killerId;
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
    // No free adjacent cell — player is completely boxed in, kill them.
    p.die();
  }

  // Convert any timed bombs belonging to this player into normal fuse bombs.
  void _convertTimedBombs(int playerId) {
    for (final b in state.bombs) {
      if (b.playerId == playerId && b.isTimed) {
        b.isTimed = false;
        b.timer = kBombFuse;
      }
    }
  }

  // Wrap a position that has moved off-grid through a teleporter lane.
  void _wrapPosition(Vector2 pos) {
    final gridW = kGridCols * kTileSize;
    final gridH = kGridRows * kTileSize;
    if (pos.x < 0) pos.x += gridW;
    if (pos.x >= gridW) pos.x -= gridW;
    if (pos.y < 0) pos.y += gridH;
    if (pos.y >= gridH) pos.y -= gridH;
  }

  // Circle-vs-AABB collision check for enemies — blocks walls and bombs.
  bool _canOccupyEnemy(Vector2 pos, Vector2 currentPos) {
    const radius = kEnemyRadius;
    final minCol = ((pos.x - radius) / kTileSize).floor();
    final maxCol = ((pos.x + radius) / kTileSize).floor();
    final minRow = ((pos.y - radius) / kTileSize).floor();
    final maxRow = ((pos.y + radius) / kTileSize).floor();
    for (int row = minRow; row <= maxRow; row++) {
      for (int col = minCol; col <= maxCol; col++) {
        if (!state.isSolid(col, row)) continue;
        final nearX = pos.x.clamp(col * kTileSize, (col + 1) * kTileSize);
        final nearY = pos.y.clamp(row * kTileSize, (row + 1) * kTileSize);
        final dx = pos.x - nearX;
        final dy = pos.y - nearY;
        if (dx * dx + dy * dy < radius * radius) return false;
      }
    }
    // Bombs are solid for enemies too (with same escape-overlap exemption).
    for (final bomb in state.bombs) {
      final bCol = bomb.position.x.toInt();
      final bRow = bomb.position.y.toInt();
      final tileLeft = bCol * kTileSize;
      final tileTop = bRow * kTileSize;
      final curNearX = currentPos.x.clamp(tileLeft, tileLeft + kTileSize);
      final curNearY = currentPos.y.clamp(tileTop, tileTop + kTileSize);
      final curDx = currentPos.x - curNearX;
      final curDy = currentPos.y - curNearY;
      if (curDx * curDx + curDy * curDy < radius * radius) continue;
      final nearX = pos.x.clamp(tileLeft, tileLeft + kTileSize);
      final nearY = pos.y.clamp(tileTop, tileTop + kTileSize);
      final dx = pos.x - nearX;
      final dy = pos.y - nearY;
      if (dx * dx + dy * dy < radius * radius) return false;
    }
    return true;
  }

  void _updateEnemies(double dt) {
    for (final e in state.enemies) {
      if (!e.alive) continue;

      // Random direction-change timer
      e.dirChangeTimer -= dt;
      if (e.dirChangeTimer <= 0) {
        e.dirChangeTimer = 2.0 + _rng.nextDouble() * 3.0;
        if (_rng.nextDouble() < 0.25) {
          e.direction = Vector2(-e.direction.x, -e.direction.y);
        }
      }

      final newPos = e.position + e.direction * kEnemySpeed * dt;
      if (_canOccupyEnemy(newPos, e.position)) {
        e.position = newPos;
      } else {
        // Try a perpendicular direction (random order), then reverse.
        final perp1 = Vector2(-e.direction.y, e.direction.x);
        final perp2 = Vector2(e.direction.y, -e.direction.x);
        final reverse = Vector2(-e.direction.x, -e.direction.y);
        final choices = _rng.nextBool()
            ? [perp1, perp2, reverse]
            : [perp2, perp1, reverse];
        for (final d in choices) {
          final np = e.position + d * kEnemySpeed * dt;
          if (_canOccupyEnemy(np, e.position)) {
            e.direction = Vector2(d.x, d.y);
            e.position = np;
            break;
          }
        }
      }

      _wrapPosition(e.position);
    }

    // Player-enemy contact: kill player (unless shielded)
    for (final p in state.players) {
      if (!p.alive) continue;
      for (final e in state.enemies) {
        if (!e.alive) continue;
        final dx = p.position.x - e.position.x;
        final dy = p.position.y - e.position.y;
        const minDist = 16.0 + kEnemyRadius; // player visual radius + enemy radius
        if (dx * dx + dy * dy < minDist * minDist) {
          if (!p.hasShield) p.die();
        }
      }
    }
  }

  void _applyPowerUp(PlayerState p, PickupType pu) {
    switch (pu) {
      case PickupType.fire:
        p.blastRadius++;
        break;
      case PickupType.speed:
        p.hasSpeedBoost = true;
        p.speedBoostTimer = kSpeedBoostDuration;
        break;
      case PickupType.shield:
        p.hasShield = true;
        p.shieldTimer = kShieldDuration;
        break;
      case PickupType.bomb:
        p.maxBombs++;
        break;
      case PickupType.ghost:
        p.isGhost = true;
        p.ghostTimer = kGhostDuration;
        break;
      case PickupType.timedBomb:
        p.hasTimedBomb = true;
        p.timedBombTimer = kTimedBombDuration;
        p.superWeapon = PickupType.timedBomb;
        break;
      case PickupType.superBomb:
        p.superWeapon = PickupType.superBomb;
        break;
    }
  }
}
