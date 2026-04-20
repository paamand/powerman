import 'dart:math';
import 'package:flame/components.dart';
import 'constants.dart';

enum TileType { empty, permanent, wood }

enum PickupType { fire, speed, shield, bomb, ghost, timedBomb, superBomb }

class GameTile {
  TileType type;
  PickupType? powerUp;
  double? powerUpTimer;

  GameTile(this.type);
}

class BombState {
  Vector2 position; // grid position
  int playerId;
  double timer;
  bool isTimed; // timed bomb super-weapon
  bool isSuper; // super bomb
  int blastRadius;

  BombState({
    required this.position,
    required this.playerId,
    required this.timer,
    required this.isTimed,
    required this.isSuper,
    required this.blastRadius,
  });
}

class ExplosionCell {
  int x, y;
  double lifetime;
  ExplosionCell(this.x, this.y, this.lifetime);
}

class EnemyState {
  Vector2 position; // pixel center
  Vector2 direction; // normalized cardinal direction
  bool alive;
  double dirChangeTimer;

  EnemyState({required this.position, required this.direction})
    : alive = true,
      dirChangeTimer = 0;
}

class PlayerState {
  int id;
  Vector2 position; // pixel position (center)
  bool alive;
  double respawnTimer; // counts down when dead; 0 = not pending respawn
  int kills;
  int blastRadius;
  double speed;
  bool hasSpeedBoost;
  double speedBoostTimer;
  bool hasShield;
  double shieldTimer;
  bool isGhost;
  double ghostTimer;
  bool hasTimedBomb;
  double timedBombTimer;
  int maxBombs;
  int activeBombs;
  PickupType? superWeapon;

  PlayerState({required this.id, required this.position})
    : alive = true,
      respawnTimer = 0,
      kills = 0,
      blastRadius = kDefaultBlastRadius,
      speed = kPlayerSpeed,
      hasSpeedBoost = false,
      speedBoostTimer = 0,
      hasShield = false,
      shieldTimer = 0,
      isGhost = false,
      ghostTimer = 0,
      hasTimedBomb = false,
      timedBombTimer = 0,
      maxBombs = 1,
      activeBombs = 0,
      superWeapon = null;

  double get effectiveSpeed =>
      hasSpeedBoost ? kPlayerSpeed * kPlayerSpeedBoostMultiplier : kPlayerSpeed;

  void die() {
    alive = false;
    respawnTimer = kRespawnDelay;
    blastRadius = kDefaultBlastRadius;
    hasSpeedBoost = false;
    hasShield = false;
    isGhost = false;
    hasTimedBomb = false;
    timedBombTimer = 0;
    maxBombs = 1;
    activeBombs = 0;
    superWeapon = null;
  }

  void respawn(Vector2 spawnPos) {
    alive = true;
    respawnTimer = 0;
    position = spawnPos;
    blastRadius = kDefaultBlastRadius;
    hasSpeedBoost = false;
    hasShield = false;
    isGhost = false;
    hasTimedBomb = false;
    timedBombTimer = 0;
    maxBombs = 1;
    activeBombs = 0;
    superWeapon = null;
  }
}

class GameState {
  List<List<GameTile>> grid;
  List<PlayerState> players;
  List<BombState> bombs;
  List<ExplosionCell> explosions;
  List<EnemyState> enemies;
  int numPlayers;
  bool gameOver;
  int? winnerId;
  double powerUpTimer;
  final Random _rng = Random();

  GameState({required this.numPlayers})
    : grid = [],
      players = [],
      bombs = [],
      explosions = [],
      enemies = [],
      gameOver = false,
      winnerId = null,
      powerUpTimer = kPowerUpSpawnInterval {
    _initGrid();
    _initPlayers();
    _initEnemies(count: kEnemyCount);
  }

  factory GameState.fromNetworkMap(Map<String, dynamic> data) {
    final n = (data['numPlayers'] as num?)?.toInt() ?? 4;
    final state = GameState(numPlayers: n);
    state.applyNetworkMap(data);
    return state;
  }

  void _initGrid() {
    grid = List.generate(
      kGridRows,
      (r) => List.generate(kGridCols, (c) {
        if (r == 0 || r == kGridRows - 1 || c == 0 || c == kGridCols - 1) {
          // Open teleporter corridors in the mid-point of each outer wall
          if ((r == 0 || r == kGridRows - 1) && c == kTeleportCol) {
            return GameTile(TileType.empty);
          }
          if ((c == 0 || c == kGridCols - 1) && r == kTeleportRow) {
            return GameTile(TileType.empty);
          }
          return GameTile(TileType.permanent);
        }
        if (r % 2 == 0 && c % 2 == 0) {
          return GameTile(TileType.permanent);
        }
        return GameTile(TileType.empty);
      }),
    );

    // Fill interior non-permanent, non-corner-clearance tiles with wood
    const clearRadius = 2; // keep spawn areas clear
    final spawnCells = spawnPositions();

    for (int r = 1; r < kGridRows - 1; r++) {
      for (int c = 1; c < kGridCols - 1; c++) {
        if (grid[r][c].type == TileType.permanent) continue;
        bool nearSpawn = false;
        for (final sp in spawnCells) {
          if ((sp.x - c).abs() <= clearRadius &&
              (sp.y - r).abs() <= clearRadius) {
            nearSpawn = true;
            break;
          }
        }
        if (!nearSpawn && _rng.nextDouble() < 0.65) {
          grid[r][c].type = TileType.wood;
        }
      }
    }
  }

  List<Point<int>> spawnPositions() {
    if (numPlayers <= 2) {
      return [Point(kGridCols - 2, kGridRows - 2), Point(1, 1)];
    } else {
      return [
        Point(1, kGridRows - 2),
        Point(kGridCols - 2, kGridRows - 2),
        Point(1, 1),
        Point(kGridCols - 2, 1),
      ];
    }
  }

  void _initPlayers() {
    final spawns = spawnPositions();
    players = List.generate(numPlayers, (i) {
      final sp = spawns[i];
      return PlayerState(
        id: i,
        position: Vector2(
          sp.x * kTileSize + kTileSize / 2,
          sp.y * kTileSize + kTileSize / 2,
        ),
      );
    });
  }

  Point<int> pixelToGrid(Vector2 pos) {
    return Point((pos.x / kTileSize).floor(), (pos.y / kTileSize).floor());
  }

  Vector2 gridCenter(int col, int row) {
    return Vector2(
      col * kTileSize + kTileSize / 2,
      row * kTileSize + kTileSize / 2,
    );
  }

  bool isSolid(int col, int row, {bool ghost = false}) {
    if (col < 0 || col >= kGridCols) {
      // Out-of-bounds left/right: passable only in the horizontal teleporter lane
      return row != kTeleportRow;
    }
    if (row < 0 || row >= kGridRows) {
      // Out-of-bounds top/bottom: passable only in the vertical teleporter lane
      return col != kTeleportCol;
    }
    final t = grid[row][col].type;
    if (t == TileType.permanent) return true;
    if (t == TileType.wood && !ghost) return true;
    return false;
  }

  void _initEnemies({required int count}) {
    final spawnCells = spawnPositions();
    const clearRadius = 3;
    final candidates = <Point<int>>[];

    for (int r = 1; r < kGridRows - 1; r++) {
      for (int c = 1; c < kGridCols - 1; c++) {
        if (grid[r][c].type != TileType.empty) continue;
        bool nearSpawn = false;
        for (final sp in spawnCells) {
          if ((sp.x - c).abs() <= clearRadius &&
              (sp.y - r).abs() <= clearRadius) {
            nearSpawn = true;
            break;
          }
        }
        if (!nearSpawn) candidates.add(Point(c, r));
      }
    }

    candidates.shuffle(_rng);
    final take = min(count, candidates.length);
    final cardinalDirs = [
      [1.0, 0.0],
      [-1.0, 0.0],
      [0.0, 1.0],
      [0.0, -1.0],
    ];

    enemies = List.generate(take, (i) {
      final cell = candidates[i];
      final d = cardinalDirs[_rng.nextInt(4)];
      return EnemyState(
        position: Vector2(
          cell.x * kTileSize + kTileSize / 2,
          cell.y * kTileSize + kTileSize / 2,
        ),
        direction: Vector2(d[0], d[1]),
      );
    });
  }

  Map<String, dynamic> toNetworkMap() {
    return {
      'numPlayers': numPlayers,
      'gameOver': gameOver,
      'winnerId': winnerId,
      'powerUpTimer': powerUpTimer,
      'grid': [
        for (final row in grid)
          [
            for (final tile in row)
              {
                'type': tile.type.index,
                'powerUp': tile.powerUp?.index,
                'powerUpTimer': tile.powerUpTimer,
              },
          ],
      ],
      'players': [
        for (final p in players)
          {
            'id': p.id,
            'x': p.position.x,
            'y': p.position.y,
            'alive': p.alive,
            'respawnTimer': p.respawnTimer,
            'kills': p.kills,
            'blastRadius': p.blastRadius,
            'speed': p.speed,
            'hasSpeedBoost': p.hasSpeedBoost,
            'speedBoostTimer': p.speedBoostTimer,
            'hasShield': p.hasShield,
            'shieldTimer': p.shieldTimer,
            'isGhost': p.isGhost,
            'ghostTimer': p.ghostTimer,
            'hasTimedBomb': p.hasTimedBomb,
            'timedBombTimer': p.timedBombTimer,
            'maxBombs': p.maxBombs,
            'activeBombs': p.activeBombs,
            'superWeapon': p.superWeapon?.index,
          },
      ],
      'bombs': [
        for (final b in bombs)
          {
            'x': b.position.x,
            'y': b.position.y,
            'playerId': b.playerId,
            'timer': b.timer,
            'isTimed': b.isTimed,
            'isSuper': b.isSuper,
            'blastRadius': b.blastRadius,
          },
      ],
      'explosions': [
        for (final e in explosions)
          {'x': e.x, 'y': e.y, 'lifetime': e.lifetime},
      ],
      'enemies': [
        for (final e in enemies)
          {
            'x': e.position.x,
            'y': e.position.y,
            'dx': e.direction.x,
            'dy': e.direction.y,
            'alive': e.alive,
            'dirChangeTimer': e.dirChangeTimer,
          },
      ],
    };
  }

  void applyNetworkMap(Map<String, dynamic> data) {
    numPlayers = (data['numPlayers'] as num?)?.toInt() ?? numPlayers;
    gameOver = data['gameOver'] == true;
    final winner = data['winnerId'];
    winnerId = winner == null ? null : (winner as num).toInt();
    powerUpTimer = (data['powerUpTimer'] as num?)?.toDouble() ?? powerUpTimer;

    final rawGrid = data['grid'];
    if (rawGrid is List) {
      grid = rawGrid.map<List<GameTile>>((row) {
        final rr = row as List;
        return rr.map<GameTile>((tileRaw) {
          final tile = tileRaw as Map<String, dynamic>;
          final typeIdx = (tile['type'] as num).toInt();
          final t = GameTile(TileType.values[typeIdx]);
          final puIdx = tile['powerUp'];
          if (puIdx != null) {
            t.powerUp = PickupType.values[(puIdx as num).toInt()];
          }
          t.powerUpTimer = (tile['powerUpTimer'] as num?)?.toDouble();
          return t;
        }).toList();
      }).toList();
    }

    final rawPlayers = data['players'];
    if (rawPlayers is List) {
      players = rawPlayers.map<PlayerState>((raw) {
        final p = raw as Map<String, dynamic>;
        final player = PlayerState(
          id: (p['id'] as num).toInt(),
          position: Vector2(
            (p['x'] as num).toDouble(),
            (p['y'] as num).toDouble(),
          ),
        );
        player.alive = p['alive'] == true;
        player.respawnTimer = (p['respawnTimer'] as num?)?.toDouble() ?? 0;
        player.kills = (p['kills'] as num?)?.toInt() ?? 0;
        player.blastRadius =
            (p['blastRadius'] as num?)?.toInt() ?? kDefaultBlastRadius;
        player.speed = (p['speed'] as num?)?.toDouble() ?? kPlayerSpeed;
        player.hasSpeedBoost = p['hasSpeedBoost'] == true;
        player.speedBoostTimer =
            (p['speedBoostTimer'] as num?)?.toDouble() ?? 0;
        player.hasShield = p['hasShield'] == true;
        player.shieldTimer = (p['shieldTimer'] as num?)?.toDouble() ?? 0;
        player.isGhost = p['isGhost'] == true;
        player.ghostTimer = (p['ghostTimer'] as num?)?.toDouble() ?? 0;
        player.hasTimedBomb = p['hasTimedBomb'] == true;
        player.timedBombTimer = (p['timedBombTimer'] as num?)?.toDouble() ?? 0;
        player.maxBombs = (p['maxBombs'] as num?)?.toInt() ?? 1;
        player.activeBombs = (p['activeBombs'] as num?)?.toInt() ?? 0;
        final sw = p['superWeapon'];
        player.superWeapon = sw == null
            ? null
            : PickupType.values[(sw as num).toInt()];
        return player;
      }).toList();
    }

    final rawBombs = data['bombs'];
    if (rawBombs is List) {
      bombs = rawBombs.map<BombState>((raw) {
        final b = raw as Map<String, dynamic>;
        return BombState(
          position: Vector2(
            (b['x'] as num).toDouble(),
            (b['y'] as num).toDouble(),
          ),
          playerId: (b['playerId'] as num).toInt(),
          timer: (b['timer'] as num).toDouble(),
          isTimed: b['isTimed'] == true,
          isSuper: b['isSuper'] == true,
          blastRadius: (b['blastRadius'] as num).toInt(),
        );
      }).toList();
    }

    final rawExplosions = data['explosions'];
    if (rawExplosions is List) {
      explosions = rawExplosions.map<ExplosionCell>((raw) {
        final e = raw as Map<String, dynamic>;
        return ExplosionCell(
          (e['x'] as num).toInt(),
          (e['y'] as num).toInt(),
          (e['lifetime'] as num).toDouble(),
        );
      }).toList();
    }

    final rawEnemies = data['enemies'];
    if (rawEnemies is List) {
      enemies = rawEnemies.map<EnemyState>((raw) {
        final e = raw as Map<String, dynamic>;
        final enemy = EnemyState(
          position: Vector2(
            (e['x'] as num).toDouble(),
            (e['y'] as num).toDouble(),
          ),
          direction: Vector2(
            (e['dx'] as num).toDouble(),
            (e['dy'] as num).toDouble(),
          ),
        );
        enemy.alive = e['alive'] == true;
        enemy.dirChangeTimer = (e['dirChangeTimer'] as num?)?.toDouble() ?? 0;
        return enemy;
      }).toList();
    }
  }

  void trySpawnPowerUp(double dt) {
    powerUpTimer -= dt;
    if (powerUpTimer <= 0) {
      powerUpTimer = kPowerUpSpawnInterval;
      // Find a random empty cell
      final empties = <Point<int>>[];
      for (int r = 1; r < kGridRows - 1; r++) {
        for (int c = 1; c < kGridCols - 1; c++) {
          if (grid[r][c].type == TileType.empty && grid[r][c].powerUp == null) {
            empties.add(Point(c, r));
          }
        }
      }
      if (empties.isNotEmpty) {
        final cell = empties[_rng.nextInt(empties.length)];
        // Only spawn regular (non-weapon) pickups via the timed spawner
        const regularPickups = [
          PickupType.fire,
          PickupType.fire,
          PickupType.speed,
          PickupType.shield,
          PickupType.bomb,
          PickupType.bomb,
          PickupType.ghost,
        ];
        grid[cell.y][cell.x].powerUp =
            regularPickups[_rng.nextInt(regularPickups.length)];
        grid[cell.y][cell.x].powerUpTimer = kPowerUpLifetime;
      }
    }
  }
}
