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
