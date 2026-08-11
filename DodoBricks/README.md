# DodoBricks

A single-player **numbered brick-breaker** (Ballz / Bricks-n-Balls style) minigame for World of
Warcraft, built entirely with native WoW UI primitives (no custom textures or audio files).
Part of the **Dodo** addon series.

![Interface](https://img.shields.io/badge/WoW-Retail%2012.1.0-blue) ![Type](https://img.shields.io/badge/type-minigame-orange)

## How it plays

Each round you launch a stream of balls at a fixed angle. They bounce around at constant speed
(no gravity, no friction) chipping away at the bricks. Every brick shows a number = its HP; a ball
takes one off per hit, and the brick shatters at zero. When every ball is back, the whole board
**drops one row** and a fresh row spawns on top. Let the bricks reach the bottom line and it's over.
There's no win condition - you play for the highest level **and the highest score** you can reach.

## Features

- 8x12 board with square **and** triangle bricks, plus tougher **double- and triple-HP** bricks -
  the spawn density and brick toughness keep ramping as you go deeper, so it never turns into autopilot
- **Scoring**: every point of damage scores, bricks in the bottom two rows pay **double** (danger pay),
  and chaining **full clears** builds a multiplier up to x10 - one sloppy round breaks the chain
- Seven pickups, each ring showing a **miniature preview of its effect**: +1 ball, row / column /
  **diagonal** lasers, a rare **cross laser**, a 3x3 bomb, and a **split** that doubles every ball
  that touches it for the round. They persist for the whole round and every ball can trigger them
  once - more balls means more power. The first time you trigger a new pickup, a brief slow-motion
  moment shows you what it does
- Special bricks: golden **treasure bricks** (crack the "?" for a bonus pickup) and green
  **healer bricks** that patch up their neighbors every round - kill the medic first!
- **Double-drop events**: when the top row starts pulsing red, the next drop pushes TWO rows -
  clear your low bricks while you can
- A 3x3 **boss brick** every 25 levels that swallows whatever it lands on and rains pickups when it
  dies; late-game bosses heal the whole board every round
- Brick palette rotates every 10 levels, combo hits climb a sound ladder, and clutch moments
  (final brick of a clear, boss kills) land in slow motion
- Comet trails on the balls, and a smooth **speed ramp** so long late-game rounds don't drag
- Autosaves between rounds (continue right where you left off) and tracks your best level **and score**
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
2. Restart the game (a brand-new addon folder is only picked up on a full restart).

DodoBricks runs standalone. The `Dodo` package from the same repository is optional - it only
groups the Dodo-series addons together in the addon list.

## License

Personal project, shared as-is. Author: **Doodo**.
