# DodoPool

A single-player **9-ball pool** minigame for World of Warcraft, built entirely with native WoW
UI primitives (no custom textures or audio files). Part of the **Dodo** addon series.

![Interface](https://img.shields.io/badge/WoW-Retail%20Midnight-blue) ![Type](https://img.shields.io/badge/type-minigame-orange)

## Features

- Full 2D pool physics: ball-on-ball collisions, cushion bounces, rolling friction, and pocketing
- Cue-ball spin done right: **follow / draw**, **side english** (with throw and english off the cushion),
  and **masse** curve shots
- A live, dynamic aiming line that previews the cue-ball path including curve
- **Strict 9-ball rules**: hit the lowest ball first, a ball must reach a cushion or be pocketed,
  fouls cost a stroke and award ball-in-hand; legally sinking the 9 wins
- Save / continue (1 slot) and a best-strokes record
- Sound effects via WoW's built-in SoundKit, with an on/off toggle and a volume slider
- Automatically pauses and releases the keyboard when you enter combat

## How to play

- Open the game with the **pink D minimap button** or the slash command `/pool` (also `/dodopool`).
- **Aim & charge**: hold the **left mouse button** and pull back from the cue ball, like drawing a bow.
  The direction sets your shot, the distance sets your power. Release to shoot; right-click to cancel.
- **Strike point (english)**: `W` / `S` for top/bottom (follow / draw), `A` / `D` for left/right side spin.
- **Cue elevation (masse)**: `Q` / `E` to raise the cue (0–45 degrees). Elevation + side spin curves the cue ball.
- After a foul you get **ball-in-hand**: move the mouse to place the cue ball, left-click to confirm.
- `ESC` closes the window.

## Installation

1. Copy the `DodoPool` folder into `World of Warcraft\_retail_\Interface\AddOns\`.
2. This addon **requires the `Dodo` package** (shared library and icon) from the same repository —
   install `Dodo` alongside it.
3. Restart the game (a brand-new addon folder is only picked up on a full restart).

## License

Personal project, shared as-is. Author: **Doodo**.
