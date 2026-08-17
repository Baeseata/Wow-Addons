# Gotchas - DodoNameplate

> Current guard catalogue for Retail Midnight 12.1. Historical investigations remain in `SESSION-LOG.md`.

## S1. Secret Values

A secret is truthy and non-nil but errors when addon Lua compares it, boolean-tests it, indexes with it, calls it, or performs arithmetic on it. Receiving, storing, and passing it to an approved sink is allowed.

The order of a guard matters:

```lua
if issecretvalue(value) or value == nil then return end
local present = issecretvalue(value) or value ~= nil
```

Do not reverse either expression. `value == nil`, `value ~= nil`, `value and ...`, and `not value` are already operations on the value.

In 12.1, `UnitClassBase` and `UnitInRaid` can be secret when unit identity is restricted. All maybe-secret booleans go through `Guards.Bool`; class tokens must be checked before nil/table lookup. The same secret-first rule applies to cast targets, raid markers, health-percent results, threat state, classification, and important-cast flags.

Safe sinks used by this addon include `FontString:SetText`, `StatusBar:SetValue`, `StatusBar:SetMinMaxValues`, `Frame:SetAlphaFromBoolean`, `Texture:SetAlphaFromBoolean`, `SetRaidTargetIconTexture`, and the display elements bound to a custom aura button.

## S2. Restricted enemy data that remains unavailable

- Lua-side enemy health arithmetic, execute logic, and K/M abbreviation where health is secret.
- NPC-ID, arbitrary spell-ID, enemy healer, cooldown, diminishing-return, or combat-log intelligence.
- Lua branching on cast interruptibility or important-cast flags; drive approved widget sinks instead.
- Custom children or alpha changes on forbidden friendly party/raid nameplates inside PvE instances.

Use `C_NamePlate.GetNamePlateForUnit(unit)` without the `includeForbidden` fallback and bail on `plate:IsForbidden()`.

## S3. WoW 12.1 aura containers

12.1 requires unit-aura access for `C_UnitAuras.GetUnitAuras`, `C_UnitAuras.IsAuraFilteredOutByInstanceID`, and `C_UnitAuras.GetAuraDuration`; `UNIT_AURA` itself is secret when auras are restricted. Addon Lua must not enumerate, inspect, or manually route these auras.

`CustomAuraContainerTemplate` is the supported path:

- At `PLAYER_LOGIN`, preallocate main, CC, and buff containers for every permanent `nameplate1` through `nameplate40` token.
- Every group preallocates a batch of ten `CustomAuraButton` frames, and `maxFrameCount` cannot suppress that: `CreateFrameBatch` runs two lines before `RegisterAuraGroup` ever reads the cap. The batch exists to obfuscate aura counts.
- Adding the groups at login is a cost-placement choice, **not** an API requirement. `AddAuraGroup` has no login gate, and Blizzard's provider allocates further batches on demand while auras are secret. (An earlier version of this file and of `Auras.lua` asserted a "preallocation contract" that the 12.1 source does not contain.)
- Bind the icon, duration cooldown, and application-count font string in `initializeFrame`.
- Set each container's unit exactly once to its permanent string token. Never call `SetUnit(nil)`.
- Disable a container with `SetEnabled(false)`. Disable an individual group with `SetAuraGroupMaxFrameCount(key, 0)`.
- Do not call methods on a preallocated AuraButton while `C_Secrets.ShouldAurasBeSecret()` or combat restrictions apply. Container inbound methods remain the configuration path.
- Track the current plate owner for each token so a recycled frame's late clear cannot disable a newly attached container.

**Ownership transfer is synchronous — configure the widget fully BEFORE handing it over.** `SetApplicationCount`
stores the font string and then calls `UpdateAuraDisplay` in the same call, reaching `SetText` on it before the
call returns. A font string created as `CreateFontString(nil, "OVERLAY")` has no font, so registering it and
fonting it afterwards raises `FontString:SetText(): Font not set`. `SetIcon` and `SetDurationCooldown` end in the
same `UpdateAuraDisplay`. Register every sink LAST, after sizing/fonting. Two errors fire per button: the first is
swallowed by `securecallfunction` around `initializeFrame`, the second comes from the provider's unconditional
`UpdateAuraDisplay` and PROPAGATES out through `AddAuraGroup` — so one bad button aborts the entire login path.
Styling inside `initializeFrame` is always legal: it runs before `ApplyAccessRestrictions`, even when auras are
secret. ☐ no guard — there is no build step and `luacheck` cannot see a runtime ordering contract; the smoke test
is that `/reload` prints the "loaded" line and `/dnp` opens.

**Login cost, and the lever if it ever matters** (recorded here rather than in PENDING-WORK, since nothing is
owed until someone measures): 40 bundles x 7 groups x a hardcoded batch of 10 = roughly 2800 `CustomAuraButton`
frames built inside the `PLAYER_LOGIN` handler; Plater builds about 1600 for comparison. Measure with
`debugprofilestop()` around the `CreateBundle` loop before touching anything — this path had never run to
completion before v0.9.1, so every number about it is an estimate. The largest single lever is the per-button
`BackdropTemplate` border: it costs 1 frame plus 9 nine-slice textures each (~70% of everything created) to draw
a 1px outline that a single `SetColorTexture` backing plate would also produce, since the icon is already inset
1px. Second lever: skip the `purge` and `generic` groups at build time when `ns.playerCanPurge` is false or
generic buffs are off — both are known before `Auras.Initialize` runs.

Two smaller known divergences, deliberately left alone in v0.9.1 because none of this code had ever executed:
`CanTouchAuraButtons` also gates on `InCombatLockdown`, but the real restriction is secrecy-keyed only (nothing in
the 12.1 `Blizzard_AuraContainer` package mentions combat) — the extra gate only defers restyles, so it is safe,
just unnecessary. And `groupSpacing` is now 0 so `RowWidth()` stays exact; the side effect is that icons from
adjacent groups touch, while icons within a group keep their 1px gap.

### Fixed group map

| Row | Key | Filter and candidate rules | Dedupe rule |
|---|---|---|---|
| Main | `priority` | `HARMFUL|PLAYER`, plus `!CROWD_CONTROL` while CC is enabled; `nameplateShowPersonal=true`, `isPriorityAura=true` | Mine excludes priority while this group is enabled |
| Main | `mine` | Same filter; `nameplateShowPersonal=true`; `isPriorityAura=false` only while priority is enabled | Omitting the priority candidate when priority is off lets mine show the full curated personal set |
| CC | `cc` | `HARMFUL|CROWD_CONTROL` | Separate any-caster row; when disabled, main no longer excludes personal CC |
| Buff | `purge` | `HELPFUL|RAID_PLAYER_DISPELLABLE` | Other enabled buff groups exclude purgeable auras |
| Buff | `bigDefensive` | `HELPFUL|BIG_DEFENSIVE` | Excludes purgeable when purge is active |
| Buff | `externalDefensive` | `HELPFUL|EXTERNAL_DEFENSIVE|!BIG_DEFENSIVE` | Excludes BIG and purgeable matches |
| Buff | `generic` | `HELPFUL` | Negatively excludes every enabled higher-priority buff category |

Every filter string must carry `INCLUDE_NAME_PLATE_ONLY`. Blizzard's own wording: "When not set, nameplate-only auras will be filtered out" — i.e. its absence actively excludes exactly the set a nameplate addon wants, and Blizzard's own nameplate filters carry it. `Auras.lua` appends it at the only two chokepoints (`AddAuraGroup` and `SetAuraGroupFilterString`), so the table above lists the raw filters without it. Do not also append it in the per-row builders or it is emitted twice.

Do not combine `BIG_DEFENSIVE` and `EXTERNAL_DEFENSIVE` as two positive components in one filter. Positive filter components are intersected, so OR-equivalent presentation requires two groups.

Each group's cap is independent. Main and buff wrapper frames therefore use `SetClipsChildren(true)` and a fixed configured width so the visible aggregate still cannot exceed the row limit.

`Core.lua` does not register `UNIT_AURA`. It preallocates at login and refreshes secure group configuration after spellbook, specialization, and restriction changes.

## S4. Other supported state paths

- Health fill: pass secret health/max directly to status bar sinks. Health-percent text uses the integer step curve and `SetText` without concatenating `%`; the percent sign is a separate font string.
- Threat: guard `UnitThreatSituation` before nil or numeric comparisons.
- Casts: use duration objects and `SetTimerDuration`; drive interrupt/importance visuals with `SetAlphaFromBoolean` or `EvaluateColorValueFromBoolean`.
- Raid marker: secret-first presence test, then pass the index directly to `SetRaidTargetIconTexture`.
- Target/focus: compare the plate frame returned for `target`/`focus`, not a maybe-secret `UnitIsUnit` result.

## S5. Per-spellID bar tinting — visibility inheritance, never reading

Verified end-to-end on a live plate 2026-08-17 (build 12.1.0.69299, Shadow Priest, four states correct).
**S2's "arbitrary spell-ID" line and DESIGN §6 both used to say this was dead. That was a 12.0
conclusion.** What is dead is *reading* which aura is up; *filtering* by spell ID is permitted.

The mechanism is not "read the aura, then pick a colour" — it is **hand a texture to Blizzard and let
it switch that texture on**. A texture whose parent is a `CustomAuraButton` draws exactly while that
button is shown, and `Blizzard_CustomAuraButton.lua` sets shown as `secretwrap(auraData ~= nil)`.
The addon performs zero comparisons.

- **AND = nesting.** A container created with the aura button as its parent only renders while that
  button is shown, so ancestry is the conjunction. Verified: SW:P-only, VT-only, and both-DoTs each
  produce their own colour.
- **NOT is free when the "neither" state is the bar's own colour** — a lower layer does not need to
  know the higher one is up, because the higher layer covers it. Absence has no direct expression
  (PlateTweaks builds it by occlusion with an opaque replica of the bar); avoid needing it.
- Measured: `C_Secrets.GetSpellAuraSecrecy` is **2 (not NeverSecret)** for 589 / 34914 / 335467, so
  the plaintext path is closed and the container route is mandatory. `AddAuraSlot` /
  `SetAuraSlotCandidateFilters` **exist** on this client.

Four constraints, each one a real crash or a silent no-op:

1. **Attach the texture inside `initializeFrame`, at that instant.** `Blizzard_AuraContainerFrameProviders.lua`
   calls `securecallfunction(initializeFrame, …)` and applies `DenyTaintedAccessWhenAurasAreSecret`
   on the very next line. Late attachment is refused **everywhere auras are hidden — a whole dungeon,
   not just its fights**, so the failure looks like "works at the target dummy, does nothing in M+".
2. **Order layers by draw sublevel; never `SetFrameLevel`.** Aura buttons report a secret frame strata
   and refuse `SetFrameLevel` while auras are secret. OVERLAY sublevels run -8..7.
3. **A nested container anchors to the health bar, never to its parent button.** Ours-to-theirs
   anchoring is refused (`UntrustedLayoutScriptExecution`); theirs-to-ours is fine. Same asymmetry
   DodoProbe hit in 2026-08-15 from the other direction.
4. **Probe `AddAuraSlot` on the real container at the moment of use — never cache the answer.**
   `Blizzard_AuraContainer` may not be loaded at `ADDON_LOADED`; an early probe fails, caches
   "unavailable", and the session silently runs the 10-frame `AddAuraGroup` path while the feature
   looks switched on. A slot pools ONE frame; a group pools ten
   (`CustomAuraContainerConstants.FrameCreationBatchSize`, deliberately high to obfuscate aura counts).

Also: a container bound to `"target"` must refresh on `PLAYER_TARGET_CHANGED` itself — the container
only registers `UNIT_AURA` for its token, so without that the bar keeps showing the **previous**
target's state, which reads exactly like "the mechanism is laggy". Plates bind permanent `nameplateN`
tokens and are not affected; this bit us only in DodoProbe's rig.

Cast spell ID is not always the aura spell ID (Rend casts 772, applies 388539). A wrong ID never
lights up, which is indistinguishable from the mechanism not working.

☐ no-guard — there is no build step, and every failure mode here is a runtime contract in Blizzard
code that `luacheck` cannot see. The acceptance test is `/dp tint`: four DoT states, four colours,
run once out of combat and **once inside an instance** (the instance run is the one that matters).

### S5a. Wiring it onto a real plate (`Tint.lua`)

The probe painted a fake bar that existed before the containers did. A nameplate does not, and three
things follow that the probe never had to answer.

**A permanent per-token proxy stands in for the health bar.** The textures are created at login,
inside `initializeFrame`, when no plate is attached to the token — there is nothing to anchor to yet.
Each `nameplateN` therefore owns a proxy frame that the textures anchor to, and `Attach` re-points
that proxy at whichever plate now holds the token. The proxy anchors to
`hb:GetStatusBarTexture()`, **not to the bar**: anchoring to the whole bar would hide the health level
under a solid block. PlateTweaks does the same (`AnchorToFill`).

**Frame levels are a single declared stack, because two of the three painters are not ours to order.**
`Plate.lua` exports `ns.LEVEL_TINT` (2) / `ns.LEVEL_IMPORTANT` (24) / `ns.LEVEL_TEXT` (25) as offsets
from the health bar's level. The proxy takes LEVEL_TINT and everything Blizzard builds hangs below it,
two levels per AND-link — so the gap to LEVEL_IMPORTANT is what caps a chain at 11 spells. Name,
health percent and the elite icon **had to move off `hb` onto `f.fg`**: a tint covering the fill
covers whatever else is drawn on the fill, and they were.

**The important-cast recolour moved out of the vertex colour.** It used to be folded into the fill's
own colour via `EvaluateColorValueFromBoolean`; the tints are drawn on aura buttons *above* the fill,
so it would have been silently painted over. It is now `f.impTint`, a texture at LEVEL_IMPORTANT
driven by `SetAlphaFromBoolean` — same secret-safety, same `importantHpColor` setting, one
implementation. `ColorBar` no longer knows about casting at all.

**`SetParent` on the proxy DOES re-level Blizzard's aura buttons** — confirmed on live plates inside
an instance, 2026-08-17. This was the one step the probe could not answer: it built its containers
under `UIParent` and never moved them, whereas we move the proxy onto each plate's health bar and the
buttons' levels have to follow through the C-side cascade (we cannot set them ourselves — an aura
button reports a secret strata and refuses `SetFrameLevel`).

Worth keeping the reasoning, because it is why so little observation settled it: a visible tint inside
an instance is only possible if the cascade happened, the textures were attached in time, and the
fill anchoring held. Had the cascade not happened the tint would draw *behind* the bar and show
**nothing at all** — the same symptom as a wrong spell ID or a late attach, which is why `/dnp tint`
prints `hb / proxy / container` levels for the current target. `container > hb` separates them.

Acceptance test for future changes here: `/dnp tint` on an enemy target (expect `active:true`,
`slot>0`, `container > hb`), then eyeball the four states, then **once inside an instance** — and
check the mob's name and health percent are still readable on top of a tinted bar.

## S5b. Borrowing a value you are not allowed to compute

Untainted code reads secrets freely; only addon Lua is restricted. So **Blizzard's own widgets already
hold values derived from data we cannot read** — and a widget property can be read back out. What
comes back is a secret, which is still useful, because a secret may be handed to a sink.

Worked example, the one that shipped: enemy class colour in a battleground. `UnitClassBase` is
`SecretWhenUnitIdentityRestricted`, and `UnitClassFromGUID` returns secret for **all three** returns
when the GUID is secret (measured; the contract marks only `className` as `ConditionalSecret`, so it
understates this). There is no number→colour sink either — `C_CurveUtil` maps booleans only. Nothing
in addon Lua can produce that colour. But `CompactUnitFrame_UpdateHealthColor` does plain
`UnitClass` + `RAID_CLASS_COLORS[englishClass]` with no secret handling whatsoever, and
`NamePlateEnemyFrameOptions.useClassColors = true` — so the colour is on screen already, underneath
the bar we hide. `plate.UnitFrame.healthBar:GetStatusBarColor()` returns it as a secret, and
`SetVertexColor` takes it straight.

The three conditions, each measured rather than assumed:

1. **The frame must not be forbidden.** Enemy plates are fine (we already `SetAlpha(0)` them);
   friendly party/raid plates in PvE instances are forbidden and are skipped entirely (S2).
2. **It must keep updating while hidden.** `SetAlpha(0)` does not stop Blizzard's update path — every
   probe row read `a=0.00` and still returned a live colour, not `nil`. If it had stopped, the value
   would have gone stale invisibly.
3. **Never compare it.** Receive → store → pass to the sink. `Guards.IsSecret` first, before any nil
   compare, and the colour table is tagged `secret = true` so `ColorBar` routes it without testing
   the components.

🔴 **You borrow their decision, not your semantic.** In the same battleground, four teammates whose
class was fully readable *also* returned a SECRET colour — so the secrecy in that bar is not coming
from class identity at all, but from something else in Blizzard's colour path (threat/aggro). What
you get is "whatever Blizzard painted", which for a creature would be its threat tint, not a class
colour. Hence the borrow is scoped to `ENEMY_PLAYER` only.

✅ **VERIFIED IN-GAME 2026-08-17** — `SetVertexColor` **does** accept a **raw secret number** out of
`GetStatusBarColor`. Jerry ran the morning build and enemy players came out class-coloured **in the
open world and in a battleground**, DoT tint below, with no refusal message. That also settles the
branch S5b left open — a nameplate in a BG evidently does **not** get `pvpUseClassColors`, because
Blizzard's bar underneath was class-coloured and there was something to borrow.

This was worth measuring rather than assuming: `SetVertexColor` is known to accept the
`SingleColorValue` that `EvaluateColorValueFromBoolean` returns, but those are not the same type, and
"same family" is not "same conclusion".

**Keep the `pcall` and the print-once fallback anyway.** They cost nothing and this is an undocumented
runtime contract in Blizzard code — a patch can withdraw it, and a quiet fall back to red would be
indistinguishable from "this player has no class colour". ☐ no-guard: not statically checkable.

## S5c. The two-channel enemy-player bar

An opaque tint over a class-coloured bar hides the class colour completely, and alpha-blending the two
is worse than either alone: half-transparent orange over a blue Shaman is a third colour, so the DoT
signal would look different on every class and neither channel could be read. So the two channels get
separate pixels instead: the DoT tint takes the bar except a thin strip along the **top**, which stays
class-coloured. Both fully saturated.

- `ns.TINT_CLASS_STRIP` (Plate.lua) is that reserve, in **pixels — not a fraction**. It is the minimum
  needed to still register a hue, so it must not grow with the bar. `LayoutPlate` derives
  `f.splitY = height - strip` from the **configured** height and `Tint.Attach` reads that one number
  rather than deriving its own. Do not compute it from `hb:GetHeight()`: `hb` sizes itself through
  `SetAllPoints`, so its height is unresolved on the first frame and reads 0.
- **Nothing is conditional on a DoT being up** — it cannot be, only Blizzard knows. Nothing painted
  means the whole bar shows the class colour; a DoT painting the lower region leaves the strip behind.
  The "if dotted, only the strip stays class-coloured" behaviour is emergent, not branched.
- **The 1px rule between the two regions went out and came back the same day (2026-08-17) — and the
  reversal is the point, not the flip-flop.** It was first removed at Jerry's request: with the split
  near the middle of the bar the colour edge alone read fine and the line was visual noise. The strip
  was then cut to 4px, which **withdrew the premise** — a 4px band against an adjacent colour reads
  as a gradient rather than a boundary, so the class channel stopped being legible. The rule went
  back in (`ns.TINT_SEAM`) as what makes 4px work.
  - ⇒ **If you ever widen the class strip again, the rule becomes noise again.** The two constants
    are coupled; neither is independently "correct". Do not delete the rule on the strength of the
    older note — check what `ns.TINT_CLASS_STRIP` currently is first.
  - The rule is charged to the tint region (`splitY = height - STRIP - SEAM`), so the class channel
    keeps its full 4px and the reserve costs 5px in total.
  - It is **unconditional**: whether a DoT is up is Blizzard's knowledge, not ours, so an undotted
    enemy player shows the class colour above *and* below the line. That is not a bug and cannot be
    branched away — see the bullet above about nothing being conditional on a DoT.
- **Hostile creatures are not split.** They have no class-colour channel, so it would only halve the
  tint. `Tint.Attach` branches on `f.group`; the tint textures never learn about any of this, because
  they only ever anchor to the per-token proxy.
- Text on the bar carries a black **drop shadow** on top of its outline. The outline alone sufficed
  against threat red; a class-coloured bar can be Rogue yellow or Priest white, and white text on that
  disappears. Shadow rather than `THICKOUTLINE` — thick outlines turn CJK glyphs to mush at nameplate
  font sizes, and names here can be Chinese.

## S6. The execute rule — geometry, not data

`Execute.lua` draws a 1px vertical rule at the player's execute threshold. It is the only decoration
on the bar that **reads nothing about any unit**, and that is a design constraint, not a coincidence.

- **It anchors to the BAR, every other overlay anchors to the FILL.** The fill crossing the line is
  the entire signal, so the line has to stay put while the fill retreats past it. Anchor it to the
  fill and you get a line permanently at 20% *of the current health* — which is to say, a line that
  never tells you anything, and which looks completely normal in a screenshot. `test/test_execute.lua`
  asserts the anchor object identity for exactly this reason; that assertion was A/B'd (breaking the
  position maths reddens it and nothing else).
- **Position comes from `f.barWidth`** (stashed by `LayoutPlate`), not `hb:GetWidth()` — same reason
  as `f.splitY`: `hb` sizes itself via `SetAllPoints`, so its width is 0 on the first frame, which
  would park every line against the left edge. A zero width hides the line rather than drawing it at
  x=0 (also asserted).
- 🔴 **Do not make it conditional on the target actually being below the threshold.** Recolouring it,
  flashing it, or hiding it once in range all require reading health — and health is secret. The
  moment this module wants to know *whether* the target is in range, it stops being free and inherits
  the whole Secret Values problem. Blizzard's own spell-button glow already answers "am I in range
  now"; this line answers the different question "how far away is it", which is the one Blizzard does
  not answer.
- **Thresholds are a spec table with a `state` field, and only `state = "on"` draws.** Two states
  deliberately draw nothing: `"unverified"` (the number is a plausible guess, unconfirmed for this
  patch) and `"dynamic"` (a talent or buff moves the real threshold — Warrior `Massacre`, Paladin
  `Avenging Wrath`). **A line in the wrong place is worse than no line**: it does not read as
  "unknown", it reads as "you cannot execute yet", and it is believed. `/dnp exec` exists so that the
  four different reasons for "no line" are distinguishable from a bug.
- Execute thresholds live in spell data (DB2). Unlike the API contracts there is **no machine
  generated file to grep**, so promoting a spec to `"on"` means confirming it in game — not finding
  a better source to read.
