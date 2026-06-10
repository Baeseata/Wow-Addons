# DodoBricks

A single-player **numbered brick-breaker** (Ballz / Bricks-n-Balls style) minigame for World of
Warcraft, built entirely with native WoW UI primitives (no custom textures or audio files).
Part of the **Dodo** addon series.

![Interface](https://img.shields.io/badge/WoW-Retail%2012.0.5-blue) ![Type](https://img.shields.io/badge/type-minigame-orange)

## How it plays

Each round you launch a stream of balls at a fixed angle. They bounce around at constant speed
(no gravity, no friction) chipping away at the bricks. Every brick shows a number = its HP; a ball
takes one off per hit, and the brick shatters at zero. When every ball is back, the whole board
**drops one row** and a fresh row spawns on top. Let the bricks reach the bottom line and it's over.
There's no win condition - you play for the highest level you can reach.

## Features

- Square **and** triangle bricks, plus tougher **double-HP** bricks
- Pickups that spawn each row: **+1 ball** (white ring), **row/column laser** (red ring),
  and a **3x3 bomb** (orange ring). Lasers and bombs persist for the whole round and every ball can
  trigger them once - more balls means more power
- Clear the entire board in a single round for a **bonus**
- Comet trails on the balls, and a smooth **speed ramp** so long late-game rounds don't drag
- Autosaves between rounds (continue right where you left off) and tracks your best level
- Sound effects via WoW's built-in SoundKit, with an on/off toggle and a volume slider
- Automatically pauses when you enter combat

## How to play

- Open the game with the **minimap button** (arcane-missiles icon) or the slash command `/bricks` (also `/dodobricks`).
- **Aim**: hold the **left mouse button** and point from the launcher toward where you want to shoot.
  A dotted line previews the first bounce. Release to launch; right-click (or aim too flat) to cancel.
- The **first ball's landing spot** becomes your next launch point.
- `ESC` closes the window.

## Installation

1. Copy the `DodoBricks` folder into `World of Warcraft\_retail_\Interface\AddOns\`.
2. This addon **requires the `Dodo` package** (shared library and icon) from the same repository -
   install `Dodo` alongside it.
3. Restart the game (a brand-new addon folder is only picked up on a full restart).

## License

Personal project, shared as-is. Author: **Doodo**.
