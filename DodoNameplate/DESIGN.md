# DodoNameplate - Design Spec

> Current product design for v0.9.0 / Retail Midnight 12.1. API constraints and exact guards live in [`GOTCHAS.md`](GOTCHAS.md).

## 0. Premise

DodoNameplate assigns every available nameplate to one identity group, gives each group its own look, and layers target, focus, threat, marker, cast, and aura states on top. Secret Values deliberately limit combat intelligence, so this is a category-based visual addon rather than an enemy-data analyzer.

## 1. Identity groups

| # | Group | Default | Main color | Notes |
|---|---|---|---|---|
| 1 | Self | Blizzard path | - | Personal-resource plate; not custom styled |
| 2 | Party / raid | On | Class | Protected PvE-instance plates are skipped |
| 3 | Other friendly player | On | Class | User-configurable clutter source |
| 4 | Friendly NPC | On | Reaction | Vendors, quest givers, and similar NPCs |
| 5 | Hostile creature / neutral | On | Role-aware threat; neutral yellow | Main PvE group |
| 6 | Enemy player | On | Class with reaction fallback | Cosmetic PvP support |
| overlay | Tapped | Dim | - | Layered on hostile creatures |
| overlay | Critter | Optional hide | - | Trivial ambient units |

Reaction and hostility changes recompute classification on `UNIT_FLAGS` and `UNIT_FACTION`.

## 2. State layer

| State | Implementation | Groups |
|---|---|---|
| Target/focus | Nameplate-frame comparison, border and target scale | All styled groups |
| Threat | Guarded role-aware `UnitThreatSituation` red/blue state | 5 |
| Health | Secret-safe status-bar fill and integer percentage text | All styled groups |
| Classification | Elite/rare border and icon | 5 |
| Raid marker | Secret-safe marker texture sink | All styled groups |
| Cast | Duration-object timer, important color/direction, interrupt shield/stripes, target name | Configured groups, especially 5/6 |
| Enemy auras | Three preallocated secure containers per `nameplate1..40` | 5 and 6 |

## 3. Aura presentation

The addon owns only layout and secure filter configuration. Blizzard's `CustomAuraContainerTemplate` owns aura reads, assignment, and restricted updates.

- **Main row above left**: personal priority debuffs first, then other personal nameplate debuffs. Shared CC is excluded only while the separate CC row is enabled.
- **CC row above right**: any-caster `HARMFUL|CROWD_CONTROL`, up to three icons.
- **Buff row below right**: purgeable, big defensive, external defensive, then optional generic buffs. Negative filters remove duplicates.
- **Caps**: groups have their own secure maximums; clipped fixed-width wrappers enforce the visible combined main/buff row caps.
- **Lifecycle**: all 120 containers and all fixed groups are built at login. Attach reparents the three containers for that permanent token; clear only disables them.

`BIG_DEFENSIVE` and `EXTERNAL_DEFENSIVE` remain distinct groups because two positive components in one filter are AND, not OR.

## 4. Configuration

- General: threat colors, target scale, raid-marker size, language, tapped/critter overlays.
- Per identity group: enable, health-bar dimensions, text, cast bar, cast-target display, and important-cast health recolor where applicable.
- Shared Auras page: enable, personal, CC, priority, generic buff, purge, defensive, row count, icon size, alpha/offset defaults, and countdown setting.

## 5. Threat rule

| Role | State | Color |
|---|---|---|
| Tank | Securely holding threat | Normal red |
| Tank | Loose/lost threat | Warning blue |
| DPS/healer | No aggro | Normal red |
| DPS/healer | Has/over threat | Warning blue |

Unknown, nil, or secret threat falls back to normal red.

## 6. Out of scope

- Enemy healer, cooldown, diminishing-return, or combat-log tracking.
- NPC-ID priority styling on restricted maps.
- Lua-side enemy health arithmetic and time-to-die logic.
- Precise off-tank/multi-tank threat.
- Arbitrary aura spell-ID whitelists or scripts for restricted enemy auras.
- Restyling forbidden friendly PvE-instance nameplates.

## 7. References

Use Blizzard's 12.1 `Blizzard_AuraContainer` implementation for aura contracts and Plater/ThreatPlates for proven Midnight secret-value patterns. Do not copy pre-12.1 manual aura enumeration back into the addon.
