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

  PlayerState({
    required this.id,
    required this.position,
  })  : alive = true,        respawnTimer = 0,
        kills = 0,        blastRadius = kDefaultBlastRadius,
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
          if ((sp.x - c).abs() <= clearRadius && (sp.y - r).abs() <= clearRadius) {
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
      return [
        Point(kGridCols - 2, kGridRows - 2),
        Point(1, 1),
      ];
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
    return Vector2(col * kTileSize + kTileSize / 2, row * kTileSize + kTileSize / 2);
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
          if ((sp.x - c).abs() <= clearRadius && (sp.y - r).abs() <= clearRadius) {
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
      [1.0, 0.0], [-1.0, 0.0], [0.0, 1.0], [0.0, -1.0],
    ];

    enemies = List.generate(take, (i) {
      final cell = candidates[i];
      final d = cardinalDirs[_rng.nextInt(4)];
      return EnemyState(
        position: Vector2(cell.x * kTileSize + kTileSize / 2, cell.y * kTileSize + kTileSize / 2),
        direction: Vector2(d[0], d[1]),
      );
    });
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
          PickupType.fire, PickupType.fire,
          PickupType.speed,
          PickupType.shield,
          PickupType.bomb, PickupType.bomb,
          PickupType.ghost,
        ];
        grid[cell.y][cell.x].powerUp = regularPickups[_rng.nextInt(regularPickups.length)];
        grid[cell.y][cell.x].powerUpTimer = kPowerUpLifetime;
      }
    }
  }
}
