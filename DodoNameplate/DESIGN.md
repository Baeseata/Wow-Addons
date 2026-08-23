# DodoNameplate - Design Spec

> Current product design for Retail Midnight 12.1. API constraints and exact guards live in [`GOTCHAS.md`](GOTCHAS.md).
> The shipped version is `## Version` in `DodoNameplate.toc`; published versions are `git tag -l 'DodoNameplate-*' | sort -V`. This file deliberately carries no version number — the one that used to be here was wrong on the day it was written (commit `9cad50f2` said 0.9.1 in its subject and 0.9.0 in this line).

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
| DoT tint | Per-spellID fill recolour via aura-button-parented textures (§3a) | 5 and 6, spec-gated |

## 3. Aura presentation

The addon owns only layout and secure filter configuration. Blizzard's `CustomAuraContainerTemplate` owns aura reads, assignment, and restricted updates.

- **Main row above left**: personal priority debuffs first, then other personal nameplate debuffs. Shared CC is excluded only while the separate CC row is enabled.
- **CC row above right**: any-caster `HARMFUL|CROWD_CONTROL`, up to three icons.
- **Buff row below right**: purgeable, big defensive, external defensive, then optional generic buffs. Negative filters remove duplicates.
- **Caps**: groups have their own secure maximums; clipped fixed-width wrappers enforce the visible combined main/buff row caps.
- **Lifecycle**: all 120 containers and all fixed groups are built at login. Attach reparents the three containers for that permanent token; clear only disables them.

`BIG_DEFENSIVE` and `EXTERNAL_DEFENSIVE` remain distinct groups because two positive components in one filter are AND, not OR.

## 3a. Health-bar tinting by spell

`Tint.lua` recolours the health-bar **fill** according to which of the player's own debuffs are on the
unit, without ever reading an aura. A texture whose parent is a `CustomAuraButton` draws exactly while
Blizzard shows that button, so the addon supplies filters and paint and Blizzard supplies the decision.
Mechanism and its four hard constraints: [`GOTCHAS.md`](GOTCHAS.md) S5.

- **Rules are data.** `RULESETS[specID]` is an ordered list of layers, lowest priority first; a layer is
  a set of spell IDs that must all be present, plus a colour. Nothing in the module is Shadow-specific.
- **Shipped ruleset — Shadow Priest (258)**: Shadow Word: Pain alone orange, Vampiric Touch alone
  purple, both blue, neither leaves the bar its own colour. Other specs are untouched.
- **Priority, high to low**: important cast > tapped > both DoTs > either DoT > base bar colour. It is
  expressed structurally, not by comparison — a longer AND-chain nests deeper and therefore lands on a
  higher frame level, and the important-cast layer sits above every tint.
- **Tapped** is the one plaintext branch: a mob somebody else has claimed keeps its dimmed base colour,
  implemented by disabling that token's containers rather than by painting grey over them.
- **Flat threat.** A ruleset may set `flatThreat`, which drops the role-aware red/blue for that spec
  (Shadow does): with a DoT on nearly everything in an instance the threat colour would be covered
  almost all of the time, so the bar holds still at normal red underneath.
- **Build once, switch by spec.** Every ruleset for the player's class is built at `PLAYER_LOGIN`,
  because attaching a texture is only legal inside `initializeFrame` and is refused wherever auras are
  hidden. A respec only flips `SetEnabled`.
- **Enemy players carry two channels on one bar**: a 4px strip along the top (`ns.TINT_CLASS_STRIP`)
  stays class-coloured, a 1px black rule (`ns.TINT_SEAM`) sits under it, and the DoT tint takes
  everything below — a 5px reserve in total, charged so that the class channel keeps its full 4px.
  Both channels stay fully saturated — alpha-blending them would make the DoT colour depend on the
  class and ruin both signals. The rule is what makes 4px readable; at a wider split the colour edge
  sufficed and the rule was noise, so the two constants are coupled (GOTCHAS S5c). With no DoT up
  nothing is painted, so the bar is class-coloured above *and* below the rule — the addon cannot know
  whether a DoT is present. Hostile creatures reserve nothing; they have no class-colour channel.
- **Class colour in a battleground is borrowed, not computed.** `UnitClassBase` is secret there, so the
  colour is read off Blizzard's own (hidden) nameplate health bar and passed straight to
  `SetVertexColor` as a secret. Scoped to enemy players. Mechanism and its conditions:
  [`GOTCHAS.md`](GOTCHAS.md) S5b.
- **Configuration**: none yet beyond the `ns.db.tint.enabled` kill switch. `/dnp tint` reports which
  path was taken and the frame levels of an attached plate.

## 6. Execute threshold rule (`Execute.lua`)

- **A 1px vertical line at the player's execute threshold**, on both enemy groups (hostile creatures
  and enemy players). It answers "how much health is left before I can execute" — the question
  Blizzard's spell-button glow does *not* answer, since the glow only fires once you are already
  in range.
- **Pure geometry, zero unit data.** The line sits at a fixed fraction of the bar's width; the fill
  retreating past it is the signal. Nothing here touches Secret Values, and it must stay that way —
  asking *whether* the target is below the threshold means reading health, which is secret.
- **Anchored to the bar frame, not the fill** — the inverse of every other overlay. See GOTCHAS S6;
  getting this wrong produces a line that looks fine and means nothing.
- **Spec table with a `state` field; only `"on"` draws.** `"unverified"` (plausible but unconfirmed
  for this patch) and `"dynamic"` (a talent or buff moves the threshold) draw nothing on purpose,
  because a line in the wrong place is worse than no line. Shipped confirmed: Shadow Priest, SW:D at
  20%. `/dnp exec` distinguishes the reasons for silence.
- **Configuration**: `ns.db.execute.enabled` kill switch only.

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
- Lua-side scripts or branching on restricted enemy aura identity.
  ⚠ Per-spellID **filtering** is NOT out of scope. This line used to read "arbitrary aura spell-ID
  whitelists or scripts", which was a 12.0 conclusion and is false on 12.1:
  `candidateFilters.includeSpellIDs` on **enemy HARMFUL** is explicitly permitted and was verified
  on a live plate 2026-08-17. What stays dead is *reading* which aura is up. See GOTCHAS S5.
- Restyling forbidden friendly PvE-instance nameplates.

## 7. References

Use Blizzard's 12.1 `Blizzard_AuraContainer` implementation for aura contracts and Plater/ThreatPlates for proven Midnight secret-value patterns. Do not copy pre-12.1 manual aura enumeration back into the addon.
