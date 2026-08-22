# DodoGrid — Project Notes

> **Claude entry point**. New session / new task → read this FIRST, then skim `Core.lua` (the engine) before changing code.

## 🔴 Moved into the Wow-Addons monorepo (2026-08-17) — how you push changed

This addon used to live in its own repo `Baeseata/DodoGrid`. It is now a folder in the
**`Baeseata/Wow-Addons`** monorepo — one repo, one `main`.

- **The live AddOns folder is NOT a git tree any more.** `D:\World of Warcraft\_retail_\Interface\AddOns\DodoGrid`
  has no `.git`. Editing in place still works (edit → `/reload` → test), but to **push** you clone
  `Baeseata/Wow-Addons` to a temp dir, copy the changed files in, commit, push — same as every
  other Dodo addon. `git log` from the live folder no longer exists; run it in the clone.
- Compare live-vs-repo with `git diff --no-index --ignore-cr-at-eol` (clone checkout is CRLF, the
  live folder is LF — naive hash compares claim everything differs). Export back with
  `git -c core.autocrlf=false archive` to keep LF.
- The old standalone repo is **archived / read-only since 2026-08-17** (not deleted; it still reads
  at `c1f32a0` = v0.5.0). If some clone of it turns out to have unpushed work you **cannot push it
  back** — archived repos reject writes. Copy those files straight into this folder and commit here,
  or `gh repo unarchive Baeseata/DodoGrid` first. Do not assume this folder is newer without diffing.
- DodoGrid is **not on CurseForge**: the monorepo release workflow only fires on a `<Addon>-vX.Y.Z`
  tag, so it never touches this addon.

> **CONTEXT HANDOFF**: Developed + tested on the HOME machine, directly in the live AddOns folder
(edit → `/reload` → test). Do NOT re-research the 12.1 Secret Values / secure-aura rules — they
are distilled below and in the sibling addon's `..\DodoNameplate\GOTCHAS.md` (in-game-verified
ground truth).

---

## What it is

Healer-focused party/raid unit frames (like Cell/Grid) for WoW Retail **Midnight / 12.1** (`## Interface: 120005, 120007, 120100`). Standalone (own `CopyDefaults`, no hard `_G.Dodo` dep; nests under the Dodo package via `## Group: Dodo`).

**Status: v0.6.0, 12.1 aura migration implemented; live restricted-instance smoke test pending.** Party (player+party1-4) and Raid (1-40, grouped by subgroup into 小队 columns, Blizzard-style cells). Flat class-color health bars, health %, 死亡/离线/鬼魂 status, role icon, out-of-range dim, left-click target + right-click menu. **Aura indicators** are owned by Blizzard's `CustomAuraContainerTemplate`: ① my buffs (`HELPFUL|PLAYER`) small icon row; ② important debuffs (`HARMFUL|RAID`/`RAID_IN_COMBAT`/`CROWD_CONTROL`) one overlaid center slot with configurable category priority; ③ dispellable (`HARMFUL|RAID_PLAYER_DISPELLABLE`) full-cell school-colored slot. **Click-to-dispel** remains a configurable secure `/cast [@<token>]` binding (default Shift+Left). ESC options panel (General + 布局 + 光环 + 驱散 sub-pages). Hides Blizzard's default party/raid frames (taint-free).

---

## Architecture (decided 2026-06-25 — do not relitigate)

**Route A: self-rolled `SecureUnitButton`, one per STATIC unit token** — NOT Blizzard's `SecureGroupHeaderTemplate` (Route B). Two A/B spike addons (`DodoGridSpikeA/B`) in the AddOns folder proved this; A won for a healer-custom frame (flat code, easy indicator attachment, debuggable). A scales to raid by adding a roster/layout manager, not a rewrite.

- 45 buttons built ONCE at login (out of combat): player+party1-4 in `partyContainer`, raid1-40 in `raidContainer`. The `"unit"` attribute is STATIC and never mutates → the only combat-protected work is `Layout()` repositioning.
- A secure `RegisterStateDriver(container, "visibility", "[group:raid] …")` swaps the two containers in/out — this runs securely in combat AND structurally kills the player-duplicate (in a raid the player IS some raidN, so the party set is hidden). Never use `UnitIsUnit` to self-detect (it's secret-when-restricted).
- `RegisterUnitWatch` shows/hides each button by `UnitExists` (secure, combat-safe).

## Code layout (`.toc` load order)

- **`Core.lua`** — the engine. Secret-first shims (`IsSecret`/`Bool`), the `SCALE100` health-percent step curve, paint helpers (`UpdateHealth/Color/Name/Role/StatusText/Alpha`), `StyleButton`, `BuildButton`, `BuildRoster`, `Layout`, the anchor/mover, slash (`/dg`, `/dg config|lock|unlock|reset`), and boot. It never registers `UNIT_AURA`; aura creation/refresh is isolated so an aura-layer failure cannot abort the unit frames.
- **`Auras.lua`** — 12.1 secure aura engine. `Auras.Create/Layout/Refresh/Clear/FlushDeferred/IsSupported`. Every static cell owns Blizzard containers permanently bound to its `player`/`partyN`/`raidN` token. Addon Lua only declares filters, layout, and display sinks; it never enumerates or inspects restricted aura data. The mine row is one aura group; the four center categories and full-cell dispel indicator use one-button aura slots. Center priority is frame-level ordering among overlaid slots. Dispel colors are applied C-side through `CustomAuraButton:AddDispelTypeTexture` and a color curve.
- **`Dispel.lua`** — click-to-dispel engine. `DISPEL_CANDIDATES` (per-class friendly-dispel spell IDs) + `Resolve()` (first `IsSpellKnown` candidate's name, override wins, Warlock Singe Magic pet-special-cased) → `Apply(b)` sets a secure `<mod>-type<btn>` = `macro` + `/cast [@<token>] <spell>` per cell. OOC-only (`ApplyAll` gates `InCombatLockdown` → `dispelDirty` → flush on `PLAYER_REGEN_ENABLED`); re-resolves on spec/talent/spellbook/pet change. Exposes `ns.Dispel.Resolve/Current` + `ns.ApplyDispel`.
- **`HideBlizzard.lua`** — `ns.ApplyHideBlizzard` (called once at login) + `ns.PromptReload`.
- **`Options.lua`** — Settings canvas pages (mirrors `..\DodoNameplate\Options.lua`): General + 布局 + 光环 + 驱散 sub-pages. `ns.InitOptions`/`ns.OpenOptions`. 光环 binds `ns.db.auras` (live via debounced `ns.ApplyAuras`); 驱散 binds `ns.db.auras.dispelClick` (live via `ns.ApplyDispel`). Toolkit: `MakeCheck/MakeSlider/MakeCycle/MakeEdit`.

---

## IMMOVABLE INVARIANTS

1. **Never do a Lua-side op (compare / arith / boolean-test / table-key / `string.format`) on a maybe-Secret value.** Guard with `IsSecret(v)` first, or feed it straight to a widget SINK (`SetValue`/`SetText`/`SetStatusBarColor`). The health engine is forked verbatim from `DodoNameplate/Plate.lua` — keep its 3-way readable/secret/nil percent branch intact.
2. **Any frame that PARENTS or is ANCHORED-TO by a secure button is protected-by-propagation in combat.** Every `SetPoint/SetSize/Show/Hide/StartMoving/ClearAllPoints` on the anchor/containers MUST be `InCombatLockdown()`-gated and deferred (`dirty`/`posDirty` → flush on `PLAYER_REGEN_ENABLED`). The mover overlay is a `UIParent` child (NOT a child of the anchor) so its Show/Hide stays legal in combat.
3. **Hide-Blizzard is /reload-only to toggle OFF** — there is no taint-safe live un-hide. The pattern (reparent-to-hidden-holder + `UnregisterAllEvents` + mandatory `KeepHidden` Show/SetShown hooks + `CompactRaidFrameManager_SetSetting` before reparent, combat-gated) is the Cell/ElvUI shipping pattern; a naive `:Hide()` taints and blocks the player's abilities. Don't "simplify" it.
4. **Restricted aura data belongs to `CustomAuraContainerTemplate`.** Never restore `GetUnitAuras`, `GetAuraDataByIndex`, `IsAuraFilteredOutByInstanceID`, `GetAuraDuration`, or addon-owned `UNIT_AURA` routing. Build every button child and register every sink inside `initializeFrame`; configure fonts/sizes before `SetApplicationCount`/`SetIcon`/`SetDurationCooldown`/`AddDispelTypeTexture` transfers ownership.
5. **Target = Retail Midnight only.** No Classic burden.

---

## 12.1 FRIENDLY-AURA VERDICT

12.1 added `RequiresUnitAuraAccess` to the old enumeration/classification APIs. When auras are secret, tainted addon Lua cannot call them at all; `pcall` only hides the error and yields no usable display data.

- The only supported runtime path here is `CustomAuraContainerTemplate`: Blizzard selects an aura and drives icon, duration, applications, visibility, and dispel color into registered display objects.
- The mine row is one `HELPFUL|PLAYER` group. `candidateFilters.maxDuration = math.huge` excludes permanent buffs when requested and now truly reclaims their slots.
- The center is four overlapping one-button slots (`RAID`, `RAID_IN_COMBAT`, `RAID_PLAYER_DISPELLABLE`, `CROWD_CONTROL`). Category priority is expressed through frame levels, but `RAID` and `RAID_IN_COMBAT` have a fixed intra-category order rather than a Lua-side merged expiration sort.
- The full-cell dispel overlay is a `RAID_PLAYER_DISPELLABLE` slot whose border textures are registered with `AddDispelTypeTexture`; Blizzard evaluates the secret dispel type and applies the color curve.
- Keep single-result indicators as slots: every group preallocates ten buttons even at `maxFrameCount = 0`. The current shape is 10 mine buttons + 5 slots per cell (675 buttons across 45 cells), not 6 groups / 2700 buttons. Layout/config fingerprints and the Options debounce prevent redundant full-grid reconfiguration.
- The containers own updates. `Core.lua` does not subscribe to `UNIT_AURA` and never receives aura tables.

---

## CLICK-CASTING / DISPEL FEASIBILITY VERDICT (researched 2026-06-26, the core M3 finding)

Secure click-casting on friendly party/raid tokens **works in 12.x** — Secret Values restrict *reading* combat data on tainted paths, not the secure environment's ability to cast on a static friendly token (the `"unit"` string is set OOC, not secret). The sanctioned pattern remains `SecureUnitButtonTemplate` + `<mod>-type<N> = macro` + `/cast [@<token>] Spell`, with all attributes assigned out of combat.

## Done so far + what's next

- **12.1 aura migration** (v0.6.0) — replaced manual `GetUnitAuras`/`UNIT_AURA` logic with Blizzard-owned containers; retained all three indicator classes and made 隐藏常驻增益 reclaim its slot.
- **Center-priority config** (v0.4.1) — 中心优先 cycle on 光环 → `important.centerPriority` presets.
- **Click-to-dispel** (v0.5.0) — `Dispel.lua` + 驱散 page. Jerry heals via mouseover macros, so **general click-casting was deliberately dropped** in favor of just click-to-dispel (auto-detected spell + configurable bind). Passed a 3-lens pre-load review.

Backlog / next:
- Polish: per-row max-columns wrap when 8 full raid groups span too wide; texture/font options.
- (Deferred, not planned) general click-casting — feasibility proven above if ever wanted.

## Workflow

**Discuss every new requirement before writing code.** Jerry drives design. Dev loop: edit → `/reload` (a brand-new `.lua` added to the `.toc` loads on /reload; a brand-new addon folder needs a full client restart) → watch BugSack. Push gotcha: the live folder is no longer a git tree — clone `Baeseata/Wow-Addons` to a temp dir, copy changed files into `DodoGrid/`, commit, push (see the monorepo banner at the top).
