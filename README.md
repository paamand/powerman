# POWERMAN
A vibe-coded battle-ship inspired game to play 2-persons no wifi.

This is an experiment to hands-on create a playable game entirely vibe-coded using Claude Sonnet 4.6.

## PROMPT
Read the SPEC.md
Use flutter and the Flutter MCP to complete the entre coding task to produce a playable game.

## Additional adjustment prompts
1. Make the game control area work so that player2 to sits opposite of player1, i.e. 180 degree flipped. Same with player3 and player4 - looking from left and right side.

2. I realized that the controls should not be rotated at all - the player sitting opposite will drag "up" which in player1 and the games perspective is down. So just keeping the orientation of the control area for every player is the right thing.
Instead change the rotation of the powermen so that each player sees his own powerman the correct way.
Also add a timer-icon (or progressbar style cooldown) to the effects with cooldown. I.e. bombs and power-ups.

3. Show the control area with a border matching the player color.

4. For 2 and 4 players the game layout should be the same with only exception that for 4-player the control area is split in halves.  
Manual tweaks
  - Changed the rotation of the powermen to match the orientation of the player
  - Changed the spawn position to be closest to the control area

5. Move the info-windows for each player to be close to the players control-area, rotated so that the player reads it (i.e. 180deg for player2 in 2-player mode and 180deg for player3 and player4 in 4-player mode)

6. Add a home button in the left side of the screen and an "game info" button on the right side. The button should be on top of the middle permanent wall.

7. When a player is killed he should re-spawn after 5 seconds. The win-condition is 5 kills. Track the kills (points) in the HUD of each player.