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
- The old standalone repo is **not deleted** — if some clone of it still has unpushed work, push it
  there first and hand-merge; do not assume this folder is newer.
- DodoGrid is **not on CurseForge**: the monorepo release workflow only fires on a `<Addon>-vX.Y.Z`
  tag, so it never touches this addon.

> **CONTEXT HANDOFF**: Developed + tested on the HOME machine, directly in the live AddOns folder
(edit → `/reload` → test). Do NOT re-research the 12.0 "Secret Values" / secure-frame rules — they
are distilled below and in the sibling addon's `..\DodoNameplate\GOTCHAS.md` (in-game-verified
ground truth).

---

## What it is

Healer-focused party/raid unit frames (like Cell/Grid) for WoW Retail **Midnight / 12.0.7** (`## Interface: 120005, 120007`). Standalone (own `CopyDefaults`, no hard `_G.Dodo` dep; nests under the Dodo package via `## Group: Dodo`).

**Status: v0.5.0, working in-game.** Party (player+party1-4) and Raid (1-40, grouped by subgroup into 小队 columns, Blizzard-style cells). Flat class-color health bars, health %, 死亡/离线/鬼魂 status, role icon, out-of-range dim, left-click target + right-click menu. **M2 aura indicators DONE** (`Auras.lua`): ① my buffs (`HELPFUL|PLAYER`) small icon row bottom-left + 隐藏常驻增益 toggle; ② important debuffs (`HARMFUL|RAID`/`RAID_IN_COMBAT`/`CROWD_CONTROL`) one center icon, slot priority user-configurable (中心优先: 重要减益/可驱散/CC presets, default 重要减益; v0.4.1); ③ dispellable (`HARMFUL|RAID_PLAYER_DISPELLABLE`) full-cell border school-colored via `GetAuraDispelTypeColor`. **Click-to-dispel DONE** (`Dispel.lua`, v0.5.0): a configurable modifier+button click (default Shift+Left) casts your auto-detected dispel spell on that unit via a secure `/cast [@<token>]` macro — pairs with the ③ border. ESC options panel (General + 布局 + 光环 + 驱散 sub-pages). Hides Blizzard's default party/raid frames (taint-free). All secret-safe and combat-safe; M2 + click-dispel each passed a multi-lens adversarial pre-load review.

---

## Architecture (decided 2026-06-25 — do not relitigate)

**Route A: self-rolled `SecureUnitButton`, one per STATIC unit token** — NOT Blizzard's `SecureGroupHeaderTemplate` (Route B). Two A/B spike addons (`DodoGridSpikeA/B`) in the AddOns folder proved this; A won for a healer-custom frame (flat code, easy indicator attachment, debuggable). A scales to raid by adding a roster/layout manager, not a rewrite.

- 45 buttons built ONCE at login (out of combat): player+party1-4 in `partyContainer`, raid1-40 in `raidContainer`. The `"unit"` attribute is STATIC and never mutates → the only combat-protected work is `Layout()` repositioning.
- A secure `RegisterStateDriver(container, "visibility", "[group:raid] …")` swaps the two containers in/out — this runs securely in combat AND structurally kills the player-duplicate (in a raid the player IS some raidN, so the party set is hidden). Never use `UnitIsUnit` to self-detect (it's secret-when-restricted).
- `RegisterUnitWatch` shows/hides each button by `UnitExists` (secure, combat-safe).

## Code layout (`.toc` load order)

- **`Core.lua`** — the engine. Secret shims (`IsSecret`/`Bool`), the `SCALE100` health-percent step curve, paint helpers (`UpdateHealth/Color/Name/Role/StatusText/Alpha`), `StyleButton`, `BuildButton` (registers `UNIT_AURA` + creates aura widgets), `BuildRoster`, `Layout`, the anchor/mover, slash (`/dg`, `/dg config|lock|unlock|reset`), boot. Exposes `ns.Layout/RefreshAll/RestorePos/ApplyLock/RefreshLayout/ApplyAuras/ForEachButton` for Options + sibling modules.
- **`Auras.lua`** — M2 aura engine (ported + re-tokened from `..\DodoNameplate\Auras.lua`). `Auras.Create/Layout/Update/Clear(button)`. Widgets are CHILDREN of the secure button (combat-safe, see invariant #2). Category-driven only via `IsAuraFilteredOutByInstanceID`; dispel color via `GetAuraDispelTypeColor` + a Step `CreateColorCurve` (Plater's index→color shape). Center-slot priority among the categories an aura matches is config-driven via `CENTER_ORDERS[important.centerPriority]` (scores every matched category, highest rank wins — handles a debuff that is both RAID-flagged AND dispellable). Dropped the enemy-only `BlizzardDebuffSet` + `playerCanPurge`.
- **`Dispel.lua`** — click-to-dispel engine. `DISPEL_CANDIDATES` (per-class friendly-dispel spell IDs) + `Resolve()` (first `IsSpellKnown` candidate's name, override wins, Warlock Singe Magic pet-special-cased) → `Apply(b)` sets a secure `<mod>-type<btn>` = `macro` + `/cast [@<token>] <spell>` per cell. OOC-only (`ApplyAll` gates `InCombatLockdown` → `dispelDirty` → flush on `PLAYER_REGEN_ENABLED`); re-resolves on spec/talent/spellbook/pet change. Exposes `ns.Dispel.Resolve/Current` + `ns.ApplyDispel`.
- **`HideBlizzard.lua`** — `ns.ApplyHideBlizzard` (called once at login) + `ns.PromptReload`.
- **`Options.lua`** — Settings canvas pages (mirrors `..\DodoNameplate\Options.lua`): General + 布局 + 光环 + 驱散 sub-pages. `ns.InitOptions`/`ns.OpenOptions`. 光环 binds `ns.db.auras` (live via `ns.ApplyAuras`); 驱散 binds `ns.db.auras.dispelClick` (live via `ns.ApplyDispel`). Toolkit: `MakeCheck/MakeSlider/MakeCycle/MakeEdit`.

---

## IMMOVABLE INVARIANTS

1. **Never do a Lua-side op (compare / arith / boolean-test / table-key / `string.format`) on a maybe-Secret value.** Guard with `IsSecret(v)` first, or feed it straight to a widget SINK (`SetValue`/`SetText`/`SetStatusBarColor`). The health engine is forked verbatim from `DodoNameplate/Plate.lua` — keep its 3-way readable/secret/nil percent branch intact.
2. **Any frame that PARENTS or is ANCHORED-TO by a secure button is protected-by-propagation in combat.** Every `SetPoint/SetSize/Show/Hide/StartMoving/ClearAllPoints` on the anchor/containers MUST be `InCombatLockdown()`-gated and deferred (`dirty`/`posDirty` → flush on `PLAYER_REGEN_ENABLED`). The mover overlay is a `UIParent` child (NOT a child of the anchor) so its Show/Hide stays legal in combat.
3. **Hide-Blizzard is /reload-only to toggle OFF** — there is no taint-safe live un-hide. The pattern (reparent-to-hidden-holder + `UnregisterAllEvents` + mandatory `KeepHidden` Show/SetShown hooks + `CompactRaidFrameManager_SetSetting` before reparent, combat-gated) is the Cell/ElvUI shipping pattern; a naive `:Hide()` taints and blocks the player's abilities. Don't "simplify" it.
4. **Target = Retail Midnight only.** No Classic burden.

---

## 12.0 FRIENDLY-AURA FEASIBILITY VERDICT (the core M2 finding)

The 3 healer aura categories (**我施放的增益 / 重要减益 / 可驱散减益**) ship ONLY as **category-driven** inside instances, NOT per-spell hand-curated:
- Aura `spellId / name / dispelName / sourceUnit` are **SecretWhenUnitAuraRestricted** — state-based (combat/encounter/M+/rated-PvP/restricted maps), and **friendly units are NOT exempt**.
- In-instance survivors: the 6 NeverSecret bools (`isHelpful/isHarmful/isRaid/isFromPlayerOrPlayerPet/isNameplateOnly/auraInstanceID`) + `C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, token)` (non-secret bool) with tokens `HELPFUL|PLAYER` (my buffs), `HARMFUL|RAID_PLAYER_DISPELLABLE` (dispellable-by-me, already accounts for kit), `HARMFUL|RAID` / `HARMFUL|RAID_IN_COMBAT` (important), `HARMFUL|CROWD_CONTROL`, + `GetAuraDispelTypeColor` (color sink for school).
- Classic LibDispel `dispelName→table` and any custom `list[spellId]` DIE in instances (table-key on a secret = error). Custom per-spell curation works only open-world / OOC.
- **Health is NOT forced to percent for friendly** (player-controlled exemption; absolute numbers render via SetText/AbbreviateNumbers C sinks even when secret).
- The aura engine is ~80% portable from `DodoNameplate/Auras.lua` (re-token the enemy filters to the healer tokens above).

---

## CLICK-CASTING / DISPEL FEASIBILITY VERDICT (researched 2026-06-26, the core M3 finding)

Secure click-casting on friendly party/raid tokens **WORKS in 12.0** — Secret Values restrict *reading* combat data on tainted paths, NOT the secure environment's ability to *cast* on a static friendly token (the `"unit"` string is set OOC, not secret). Cell (PR #457)/Clique/VuhDo all ship it on Midnight. The sanctioned pattern: `SecureActionButtonTemplate` (our `SecureUnitButtonTemplate` already inherits it) + `<mod>-type<N>` = `macro` + `macrotext` `/cast [@<token>] Spell`, all `SetAttribute`s OUT OF COMBAT. Use the **macro form, not bare `type=spell`** (bare spell leaves a stuck grey/blue targeting cursor on invalid/too-far units). Modifier-prefixed attrs override the `*type1`/`*type2` wildcards for that modifier only → unbound clicks keep target/menu. `RegisterForClicks("AnyDown")` already covers modified clicks.

## Done so far + what's next

- **M2 aura indicators** (v0.4.0) — `Auras.lua` + 光环 page. Tradeoff: 隐藏常驻增益 DIMS in place (reclaiming the slot needs a Lua test on the secret duration), so a non-full mine row can show a trailing gap — accepted.
- **Center-priority config** (v0.4.1) — 中心优先 cycle on 光环 → `important.centerPriority` presets.
- **Click-to-dispel** (v0.5.0) — `Dispel.lua` + 驱散 page. Jerry heals via mouseover macros, so **general click-casting was deliberately dropped** in favor of just click-to-dispel (auto-detected spell + configurable bind). Passed a 3-lens pre-load review.

Backlog / next:
- Polish: per-row max-columns wrap when 8 full raid groups span too wide; texture/font options.
- (Deferred, not planned) general click-casting — feasibility proven above if ever wanted.

## Workflow

**Discuss every new requirement before writing code.** Jerry drives design. Dev loop: edit → `/reload` (a brand-new `.lua` added to the `.toc` loads on /reload; a brand-new addon folder needs a full client restart) → watch BugSack. Push gotcha: the live folder is no longer a git tree — clone `Baeseata/Wow-Addons` to a temp dir, copy changed files into `DodoGrid/`, commit, push (see the monorepo banner at the top).
