# DodoRush

A single-player **crowd-runner** (Count Masters / Join Clash style) minigame for World of
Warcraft, built entirely with native WoW UI primitives (no custom textures or audio files).
Part of the **Dodo** addon series.

![Interface](https://img.shields.io/badge/WoW-Retail%2012.0.5-blue) ![Type](https://img.shields.io/badge/type-minigame-orange)

## How it plays

Your blue crowd runs forward on its own; you only strafe left and right. Every stage throws
a pair of gates at you -- green gates grow the crowd (+N or xK), red gates shrink it (-N or
divide by 2) -- and the dashed center line decides which one you take. Behind the gates wait
the red enemies: contact trades one of yours for one of theirs until one side is gone, so
you need the numbers to grind through. Small skirmish packs can be dodged entirely; the
full-width walls cannot. Every 5th stage is a BOSS wall, with a fat bonus gate right after.
The pressure keeps climbing, so every run ends eventually -- you play for the furthest
stage and distance.

## Features

- Pick-a-gate math built around the add/multiply crossover: +N is the better deal when your
  crowd is small, xK takes over once it grows -- with trap gates and lose-lose pairs later on
- Fights resolve as an honest one-for-one trade, ground out over a couple of seconds while
  you keep running (engaged enemies get pinned and pushed back)
- Dodgeable skirmish blobs for free savings, mandatory walls, and a BOSS wall every 5 stages
- Endless mode with a best-stage / best-distance record
- Sound effects via WoW's built-in SoundKit, with an on/off toggle and a volume slider
- Automatically pauses when you enter combat and resumes when you drop out

## How to play

- Open the game with the **minimap button** (pink D icon) or the slash command `/rush` (also `/dodorush`).
- Hold **A / D** (or the left/right arrow keys) to strafe. That is the whole control scheme.
- Keep your crowd's center on the half of the road with the better gate; the dashed line is the split.
- `ESC` closes the window. Closing the window keeps the current run alive ("Continue Run"
  on the start screen); a `/reload` discards it.

## Installation

1. Copy the `DodoRush` folder into `World of Warcraft\_retail_\Interface\AddOns\`.
2. Restart the game (a brand-new addon folder is only picked up on a full restart).

DodoRush runs standalone. The `Dodo` package from the same repository is optional - it only
groups the Dodo-series addons together in the addon list and provides the shared icon.

## License

Personal project, shared as-is. Author: **Doodo**.
