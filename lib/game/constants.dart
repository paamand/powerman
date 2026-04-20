// Game constants
const int kGridCols = 20;
const int kGridRows = 15;
const double kTileSize = 50.0;
// Teleporter: mid-point of each outer wall
const int kTeleportCol = kGridCols ~/ 2; // col 7
const int kTeleportRow = kGridRows ~/ 2; // row 6

// Enemies
const int kEnemyCount = 6;
const double kEnemySpeed = 80.0;
const double kEnemyRadius = 14.0;
const double kPlayerSpeed = 150.0;
const double kPlayerSpeedBoostMultiplier = 1.8;
const double kSpeedBoostDuration = 15.0;
const double kShieldDuration = 10.0;
const double kGhostDuration = 10.0;
const double kTimedBombDuration = 10.0;

const double kBombFuse = 5.0;
const int kDefaultBlastRadius = 1;

const double kPowerUpLifetime = 15.0;
const double kPowerUpSpawnInterval = 8.0;

const double kRespawnDelay = 5.0;
const int kWinKills = 5;

// Player colors (sketchy look - just stroke colors)
const List<String> kPlayerNames = ['P1', 'P2', 'P3', 'P4'];
