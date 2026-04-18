Goal: Implement the following "powerman" game for iPad written in Flutter.
Use flutter and the Flutter MCP to complete the entre coding task to produce a playable game.

# POWERMAN GAME

This game is an iPad version of the classic Bomberman game focused on same-device multiplayer battle for two or four players. You control a "powerman" and the objective is to eliminate the other powermans in a maze where some walls are destructible and others not.

## Layout
The game layout is the same as the classic bomberman with a maze of wood-walls connecting a grid of permanent walls.
The game is black/white and sketch-like with simple but clear graphics and animations.

## Game controls
The game features up to four control areas. For two-player it is the upper and lower third of the screen. For four players it is an area in each corner.
- You move your powerman by dragging in you control area
- You deploy a bomb by tapping your control area
- You fire a super-weapon by long-press in your control area

## Bombs
Boms are the primary weapon. When a bomb is deployed it explodes after 3 seconds. The blast is in all four directions, limited by other objects. You can only deploy the next bomb once your deployed bomb has exploded. I.e. a cooldown of 3 seconds.
- If a bomb hits a wood wall or a crate, it is destroyed (burned down)
- If a bomb hits a powerman, he dies. You can die of your own bombs.
- If a bomb hits another bomb, that bomb explodes immediately.

## Power-ups
On the playing maze there can be crates with super-weapons and power-ups that appear randomly and then disappears after 15 seconds. You pick up the crate by walking into it.
### Fire power-up
A "fire" power-up permanently increases your bombs blast-radius until next time you die. You start with a blast ratio of 1, which is the same size as a wall-segment.
### Speed power-up
A speed powerup increases your speed for the next 30 seconds or till you die.
### Shield power-up
A shield power-up makes you indestructable for 30 seconds.
### Bomb power-up
A bomb power-up gives you an additional bomb so that you can have one more bomb. Lasts until you die.
### Ghost power-up
A ghost power-up makes you a ghost that can go through wood walls. Lasts for 30 seconds. Once it ends you cannot *enter* a wall, but if you are already within a wall you can exit.

## Super-weapons
### Timed bomb super-weapon
A timer superweapon makes your bomb timed so that you can long-press to explode them. You deploy them as usual and the explode as usual, but long-press makes them explode instantly.

### Super bomb
The next bomb you deploy is a super-bomb with infinite blast radius and does not stop at any temporary obstacles (only permanent walls).
