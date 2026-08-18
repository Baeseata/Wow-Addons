# DodoGrid

A healer-focused party & raid unit-frame addon for World of Warcraft Retail (Midnight / patch 12.0.x) — compact, Blizzard-style group frames built from the ground up around the 12.0 "Secret Values" API.

## Features

- **Party & raid frames** — 5-man party and full 1–40 raid, grouped by subgroup into 小队 columns, Blizzard-style compact cells.
- **Flat class-colored health bars** with health percent, plus 死亡 / 鬼魂 / 离线 status and a role icon.
- **Out-of-range fading**, left-click to target, right-click for the native unit menu.
- **Hides Blizzard's default party/raid frames** automatically (taint-free), so DodoGrid is your only group display. Toggle in options (needs a /reload).
- **Aura indicators** — buffs you cast (a small icon row), important debuffs (one center icon, with a configurable priority among 重要减益 / 可驱散 / 控制), and dispellable debuffs (a school-colored cell border). Category-driven and Secret-Values safe.
- **Click-to-dispel** — a configurable click (default Shift + Left) on a cell casts your dispel spell on that unit. The spell is auto-detected from your class & spec (with a manual override), and the bind is fully rebindable. Left-click-target and right-click-menu stay intact.
- **Options panel** (ESC → Options → AddOns → DodoGrid, or `/dg config`) — a General page plus 布局 (layout), 光环 (aura), and 驱散 (dispel) sub-pages, all applied live.
- **Secret-Values & combat safe** — health reads never taint, and all frame layout/movement is properly gated for combat.

## Install

Copy the `DodoGrid` folder into `World of Warcraft/_retail_/Interface/AddOns/`, then restart the client (a brand-new addon needs a full restart; later updates load on `/reload`).

## Commands

- `/dg` — toggle the move handle (unlock to drag, lock to fix in place)
- `/dg config` — open the options panel
- `/dg lock` / `/dg unlock` / `/dg reset`

## Status

In active development. Working: party + raid frames, styling, options, hide-Blizzard, aura indicators (with configurable center-icon priority), and click-to-dispel. Next: layout polish (column wrapping, texture/font options).
