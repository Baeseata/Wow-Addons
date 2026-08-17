# DodoNameplate - Project Notes

> Session entry point. Read this file, [`DESIGN.md`](DESIGN.md), and [`GOTCHAS.md`](GOTCHAS.md) before changing runtime code. Historical decisions remain in `SESSION-LOG.md`; current work remains in `PENDING-WORK.md`.

## 🔴 Moved into the Wow-Addons monorepo (2026-08-12) — releasing changed

This addon used to live in its own repo `Baeseata/DodoNameplate` and publish through
`BigWigsMods/packager`. It is now a folder in the **`Baeseata/Wow-Addons`** monorepo and
publishes through that repo's own workflow (`.github/workflows/curseforge-release.yml`).

**What this changes for you:**

- **Release tag is now `DodoNameplate-vX.Y.Z`, not `vX.Y.Z`.** The monorepo workflow only
  fires on `Dodo*-v*` and reads the addon folder name back out of the tag. A bare `v0.9.2`
  tag here triggers **nothing at all** — it fails silently, which is exactly how you would
  not notice it.
- `.pkgmeta` is gone (the monorepo workflow uses its own allowlist) and a per-addon
  `.github/` would be dead config — GitHub only reads workflows from the repo root.
- The CurseForge project id (`1587138`) stays in the `.toc` as `## X-Curse-Project-ID`;
  the workflow reads it from there. Keep that line.
- The old standalone repo is **not deleted** — if you have unpushed work in a clone of it,
  push it there first and hand-merge, do not assume this folder is newer.

⛔ **Do not add `## Group: Dodo` or repoint `Media/Dodo.tga` at the parent `Dodo` addon**
just to match the other folders. This addon is distributed standalone on CurseForge and its
users need not have the parent pack installed. `DodoInspect` is the precedent: same pattern,
shipping for months.

Full migration notes: `PUBLISHING.md` §10 in the monorepo root (local-only, gitignored).

## Current status

- **Product**: WoW Retail Midnight nameplate replacement with category-specific layouts and secret-safe state displays.
- **Release**: v0.9.1, Interface 120100, patch 12.1. (v0.9.0 was dead on arrival — see GOTCHAS S3.)
- **Scope**: groups 2-6 are styled; group 1 stays on Blizzard's personal-resource path. Enemy auras apply to hostile creatures and enemy players.
- **Aura architecture**: `Auras.lua` preallocates three `CustomAuraContainerTemplate` containers for each permanent `nameplate1` through `nameplate40` token at `PLAYER_LOGIN`. Main, CC, and buff groups are precreated; `maxFrameCount=0` disables a group. The addon never enumerates restricted aura data or handles `UNIT_AURA`.
- **Aura display**: main priority + personal nameplate debuffs, shared CC, purgeable buffs, big defensives, external defensives, and optional generic buffs. Wrapper frames clip each row to the configured aggregate icon limit.
- **Bar tinting**: `Tint.lua` recolours the health-bar fill from a spec's spell rules (Shadow Priest ships: SW:P orange, VT purple, both blue) by handing Blizzard a texture per spell and letting it switch the texture on. It reads no aura data. Spec-gated; no options page yet, kill switch is `ns.db.tint.enabled`. `/dnp tint` reports it.

## Load order

1. `Guards.lua` - secret-value helpers.
2. `Locale.lua` - English/Chinese option strings.
3. `Classification.lua` - six identity groups and overlays.
4. `Plate.lua` - health/name/cast/marker/target presentation.
5. `Auras.lua` - secure 12.1 aura containers.
6. `Tint.lua` - per-spellID health-bar tinting (needs `ns.LEVEL_*` from `Plate.lua`).
7. `Core.lua` - events, SavedVariables, role and purge capability.
8. `Options.lua` - Settings pages.

## Invariants

- Never compare, boolean-test, index with, call, or perform arithmetic on a maybe-secret value before checking `issecretvalue(value)`. The secret check must come before even a nil comparison.
- A maybe-secret value may be passed directly only to a documented secret-safe sink.
- `UnitClassBase` and `UnitInRaid` can be secret when unit identity is restricted in 12.1; keep their guards.
- Restricted aura data is owned by `CustomAuraContainerTemplate`. Do not restore `C_UnitAuras.GetUnitAuras`, `IsAuraFilteredOutByInstanceID`, `GetAuraDuration`, Blizzard debuff-frame scraping, or `UNIT_AURA` handling.
- Any widget handed to a container sink (`SetApplicationCount`, `SetIcon`, `SetDurationCooldown`) is written to synchronously inside that call — configure it fully first, register it last. Groups are built at login by choice, not by API requirement. Keep each container's unit token permanently set to its `nameplateN` string; clearing a plate only disables the containers.
- `BIG_DEFENSIVE` and `EXTERNAL_DEFENSIVE` are separate groups. Positive filter components in one filter are an intersection, not an OR.
- Tint layers are painted by Blizzard, not by us. A tint texture's parent is a `CustomAuraButton` and it is created inside `initializeFrame` at that instant; the addon never learns which aura is up. Never `SetFrameLevel` an aura button, and never anchor one of our objects to one of theirs (the reverse is fine).
- Everything drawn over the health bar shares one frame-level stack, declared as `ns.LEVEL_TINT` / `ns.LEVEL_IMPORTANT` / `ns.LEVEL_TEXT` in `Plate.lua`. Name, health percent and the elite icon live on `f.fg` above the tints; the important-cast recolour is `f.impTint`, not a vertex colour on the fill.
- Never build children on forbidden friendly nameplates in PvE instances.
- Target client is Retail Midnight only; no Classic compatibility burden.

## Workflow

1. Preserve the current design unless a requirement explicitly changes it.
2. Keep runtime facts in these current docs and historical narrative in `SESSION-LOG.md`.
3. Parse all Lua as 5.1 and run `luacheck . --std=lua51` when available.
4. Smoke-test `/reload`, open world, restricted PvE, and PvP. Watch BugSack for secret-value and forbidden-object errors.

## Development environment

- Live development normally happens in the Retail AddOns folder; there is no build step.
- Plater and Blizzard FrameXML are reference implementations. For aura behavior, use the 12.1 `Blizzard_AuraContainer` implementation rather than 12.0 manual enumeration patterns.
- `.toc` load order is intentional.

## Documentation routing

| Need | File |
|---|---|
| Current design and group/state matrix | [`DESIGN.md`](DESIGN.md) |
| Secret Values and secure-aura guard rules | [`GOTCHAS.md`](GOTCHAS.md) |
| Current work queue | `PENDING-WORK.md` |
| Historical decisions | `SESSION-LOG.md` |
