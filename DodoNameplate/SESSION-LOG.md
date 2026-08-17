# Session Log — DodoNameplate

> Append-only, newest first.

---

## Part A — Key Decisions

### 2026-08-17 (evening, OMEN): The seam returns at 4px; execute-threshold rule

- **Decision — the 1px seam comes BACK, and the reversal is the point.** The entry below records it
  being removed the same morning; that judgement was made when the split sat near the middle of the
  bar, where the colour edge alone read fine. Cutting the class strip to 4px **withdrew that
  premise** — a 4px band against an adjacent colour reads as a gradient, not a boundary. So
  `ns.TINT_CLASS_STRIP = 4` and `ns.TINT_SEAM = 1` are **coupled**: widen the strip again and the
  seam becomes noise again. `GOTCHAS.md` S5c states this so the older note cannot be used to delete
  the seam a second time.
- **Decision — charge the seam to the tint region** (`splitY = height - STRIP - SEAM`), so the class
  channel keeps a full 4px and the reserve costs 5px in total.
- **Decision — hide the seam in `Tint.Clear` BEFORE its early return.** A respec to a spec with no
  ruleset reaches `Attach -> not IsActive -> Clear`; below the bundle check, the plate would keep a
  black line across an otherwise plain class-coloured bar.
- **Decision — the execute rule reads NOTHING and must stay that way** (`Execute.lua`, new). The
  line sits at a fixed fraction of the bar's *width*; the fill retreating past it is the whole
  signal. So it needs none of the Secret Values machinery — and the moment it wants to know
  *whether* the target is below the threshold (to recolour, flash, or hide), it has to read health,
  which is secret. Blizzard's spell-button glow already answers "am I in range now"; this answers
  "how far away is it", which Blizzard does not.
- **Decision — anchor it to the BAR, not the fill** — the inverse of every other overlay here. The
  failure mode is nasty: anchored to the fill it becomes a line permanently at 20% *of current
  health*, which looks completely normal and means nothing. `test/test_execute.lua` asserts the
  anchor object identity, A/B'd.
- **Decision — a threshold we have not confirmed draws NOTHING.** The spec table carries a `state`:
  only `"on"` draws; `"unverified"` (plausible number, unconfirmed for 12.1) and `"dynamic"` (a
  talent or buff moves it — Warrior `Massacre`, Paladin `Avenging Wrath`) stay invisible on purpose.
  **A line in the wrong place is worse than no line**: it does not read as "unknown", it reads as
  "you cannot execute yet", and it is believed. Shipped confirmed: Shadow Priest SW:D 20% (12.1 also
  buffed its damage ~80%, which is what makes a pre-read worth having). `/dnp exec` distinguishes
  the four reasons for silence, or the honest ones would get "fixed".
- **Decision — 2px, not 1px.** A vertical hairline is much easier to lose against a busy bar than
  the horizontal seam, which has the whole bar width to announce itself. Centred on the threshold.
- **Note — execute thresholds are DB2 spell data.** Unlike the API contracts there is no machine
  generated file to grep, so promoting a spec means confirming it in game, not finding a better
  source. Every number except Shadow Priest's came from model training data and is marked as such.

### 2026-08-17: Per-spellID bar tinting; enemy class colour is BORROWED, not read

- **Decision — the tint is painted by Blizzard, not by us.** A texture whose parent is a `CustomAuraButton` draws exactly while Blizzard shows that button, so the addon supplies a spell filter and a colour and performs zero comparisons on aura data. AND is expressed by nesting containers, NOT by reading two auras; priority falls out of draw order because a longer AND-chain nests deeper and lands on a higher frame level. `Tint.lua`, rules in a `RULESETS[specID]` table — nothing in the module is Shadow-specific.
- **Decision — build for the CLASS at login, switch by spec.** Attaching a texture is only legal inside `initializeFrame`, and it is refused anywhere auras are hidden (a whole dungeon, not just its fights). So every ruleset belonging to the player's class is built at `PLAYER_LOGIN` and a respec only flips `SetEnabled`. Building lazily on spec change would have produced a feature that works at the target dummy and silently does nothing in M+.
- **Decision — Shadow drops threat colouring** (`flatThreat`). With a DoT on nearly everything in an instance the red/blue would be covered almost all the time, so the base holds still at normal red. Jerry's call.
- **Decision (reversed twice, landed on the third) — how class colour and DoT colour share one bar.** Alpha-blending was rejected outright: half-transparent orange over a blue Shaman is a third colour, so the DoT signal would look different on every class and neither channel could be read. Class-on-the-name was rejected by Jerry because outside a BG the bar is *already* class-coloured, making bar+text two channels saying one thing. Landed on separate pixels: the DoT tint takes everything except a **4px strip** along the top (`ns.TINT_CLASS_STRIP`). A 1px seam was built and then removed at Jerry's request. Hostile creatures reserve no strip — they have no class channel to protect.
- **Decision — borrow the class colour instead of computing it.** In a battleground `UnitClassBase` is `SecretWhenUnitIdentityRestricted`, and `UnitClassFromGUID` returns secret for **all three** returns when the GUID is secret. There is no number→colour sink either. But Blizzard's own nameplate paints that bar with plain `UnitClass` + `RAID_CLASS_COLORS` in **untainted** code, which needs no secret handling at all — so the colour is already on screen, under the bar we hide with `SetAlpha(0)`. We read it back off `healthBar:GetStatusBarColor()` (it comes back secret) and hand it straight to `SetVertexColor`. Scoped to `ENEMY_PLAYER`: for a creature it would hand back their threat tint, not a class colour.
- **Decision — the unverified step stays loud.** Whether `SetVertexColor` accepts a raw secret number (as opposed to the `SingleColorValue` it demonstrably accepts) was not verifiable without a live BG, so the call is `pcall`ed and a refusal prints once. A quiet fall back to red would be indistinguishable from "this player has no class colour".

### 2026-08-11: Contain aura failures instead of letting them kill login (v0.9.1)

- **Context**: the v0.9.0 12.1 rewrite shipped a crash that made the addon 100% dead while looking healthy. A font-less font string was handed to `SetApplicationCount`, which writes text synchronously — so it threw on the FIRST of 280 `AddAuraGroup` calls, and the error unwound the whole `PLAYER_LOGIN` handler.
- **Decision — blast radius is a design property, not an accident**: `Core.lua` now wraps `Auras.Initialize` in `xpcall(..., geterrorhandler())`. Deliberately NOT a bare `pcall`: that would swallow the traceback, and the traceback is exactly what made this diagnosable. An aura failure must degrade to "no auras", never to "no options panel, no locale, no version print".
- **Decision — flags must not outrun reality**: `supported` is now set AFTER the bundle loop. Setting it before meant a mid-loop error left `IsSupported()` returning true with an empty `bundles` table — the addon reported itself healthy while displaying nothing and logging nothing. A half-initialized module must report as unsupported.
- **Decision — measure before optimizing the batch cost**: login allocates ~2800 aura buttons (40 bundles x 7 groups x Blizzard's hardcoded batch of 10). Plater pays 1600 for comparison. Left alone deliberately: this code had never executed once on 12.1, and optimizing an untested estimate is the wrong order. The biggest lever, if it ever needs one, is the per-button `BackdropTemplate` border (1 frame + 9 textures each, ~70% of everything created, for a 1px outline).
- **Deferred (design, not bug)**: `nameplateShowPersonal` is currently a hard requirement, but Blizzard ORs it against the `nameplateShowAllPersonalAuras` CVar. Matching that is a behavior change to the mine-only row decided on 2026-06-26, so it waits for Jerry.

### 2026-06-26: Enemy debuff left row = mine-only; teammates show only CC/stun (v0.8.2)

- **Symptom (Jerry, raid DPS)**: other players' DoTs/debuffs showed on the mob's left aura row. Blizzard's default enemy plate never shows other players' auras.
- **Root cause**: the left/main HARMFUL row has THREE inclusion paths, only one of which was caster-gated. 'mine' = `HARMFUL|PLAYER` (intersect blizzSet) is self-only and was correct. The 'important' path = `HARMFUL|RAID` / `RAID_IN_COMBAT` is NOT caster-restricted (that category surfaces raid-flagged debuffs from ANY caster), and it had NO blizzSet gate -> teammates' debuffs leaked in via the gold-border branch. (The CC slot = `HARMFUL|CROWD_CONTROL` is intentionally any-caster.)
- **Decision (Jerry)**: teammates' auras on the mob should show ONLY control/stun, never their dots. We canNOT filter by caster ourselves under Secret Values (`UnitIsUnit(source,"player")` + `nameplateShowPersonal` are secret in instances); the only trustworthy "this is mine" signal is blizzSet (Blizzard's own DebuffListFrame, which holds only the player's own debuffs).
- **Fix (one line)**: gate the 'important' branch on blizzSet too, STRICT (`blizzSet and blizzSet[id]`), so it fires only for ids Blizzard itself curated (= mine). Net: the whole left row is now mine-only; teammates' dots / non-CC debuffs never appear. Teammates' control/stun still shows via the existing CC slot (unchanged). Coarse-bucket caveat accepted by Jerry: `CROWD_CONTROL` cannot split stun from slow/root (12.0 exposes no finer token).
- **Why strict, not the lenient `not blizzSet or blizzSet[id]` the 'mine' row uses**: if Blizzard's frame is momentarily unavailable (blizzSet nil), the lenient form would re-open the any-caster RAID path and leak teammate dots again. Strict closes that edge -- my own important debuff just falls back to mine's black border instead of gold. Leak-proof in all cases.
- **Implementation**: `Auras.lua` `Auras.Update` (important branch + the blizzSet comment block). GOTCHAS.md S3 "Match Blizzard" bullet updated.

### 2026-06-24: Forbidden friendly plates, name-in-bar, and the AURA feature (v0.8.0 cont.)

- **Forbidden friendly plates (root-caused + fixed)**: friendly party/raid nameplates INSIDE PvE instances (instanceType `party`/`raid`) are forbidden/protected frames (Blizzard patch-7.2 anti-coordination rule, still in 12.0; confirmed in-game -- `GetNamePlateForUnit("target")` = nil, `(..., true)` = a forbidden frame). Addons CANNOT restyle them; Plater can't either. `GetPlate` stopped opting into the forbidden form and `Style.Apply` early-returns on `plate:IsForbidden()`, so we no longer taint -- friendly instance plates show a clean Blizzard default. BG/arena (`pvp`) + open world are fine; the discriminator is CONTENT TYPE, not instanced-ness (which is why a battleground still works). GOTCHAS.md S2.
- **Name into the bar (enemy plates, groups 5+6)**: the mob / enemy-player name moved INSIDE the bar (after the elite icon, flush-left if none), auto-sized to bar height; the nameSize slider is removed for those groups. Frees the above-bar space for the aura row.
- **AURA feature (Jerry's headline ask)**: secret-safe, CATEGORY-based aura icons on enemy plates. Per-spellID curation is DEAD on Midnight (the by-id / by-name UNIT aura lookups are disabled while aura access is secret -- a whitelist cannot be matched on a mob in instances), so we mirror BLIZZARD'S nameplate categories: 个人减益 `HARMFUL|PLAYER`, 共享控制 `HARMFUL|CROWD_CONTROL` (any caster; a coarse bucket -- stun/root cannot be split from slow), 重要减益 `HARMFUL|RAID(_IN_COMBAT)`, 敌方增益 `HELPFUL`. Two displays: a main row (above-bar LEFT = my debuffs + important, capped) + a CC slot (above-bar RIGHT = shared crowd control). The TIMER NUMBER is drawn by Blizzard's Cooldown frame C-side (`SetHideCountdownNumbers(false)`) -- it renders under secret even though we cannot read the number. Shared `ns.db.auras` config + a dedicated bilingual "Auras"/光环 sub-page. Enemy-player auras work in BG/arena, NOT world PvP/war mode (Blizzard's own nameplate is broken there too). Full API + the categorical-vs-spellID wall: GOTCHAS.md S3.
- **Distribution polish**: addon icon (`## IconTexture` -> a copy of DodoInspect's `Dodo.tga` in `Media/`); Jerry's current live config BAKED into `ns.defaults` (fresh installs reproduce it exactly, adversarially verified field-by-field); shipped language default = English (`locale = "enUS"` -- "auto" follows client if ever preferred). Options panel verified 100% bilingual (54/54 keys).

### 2026-06-21: Phase 2 PvP scope -- enemy-player nameplate, no intel (v0.8.0)

- **Decision (Jerry)**: Phase 2 = style the ENEMY PLAYER nameplate (group 6) the SAME way as hostile creatures, in ALL of war mode / battleground / arena -- class-colored health bar + cast bar. Group 6 default ON. NO combat-intel (CD / buff / interrupt / DR / healer detection) -- walled by `SecretInActivePvPMatch` (GOTCHAS S2 + the PvP memory note).
- **Why small**: the engine already classifies group 6 (`Classify`: `isPlayer and canAttack -> ENEMY_PLAYER`) and `GroupColor` already routes ENEMY_PLAYER -> `ClassColor or ReactionColor or red`. Class color via `UnitClassBase` + `issecretvalue` guard falls back to red when class is secret (arena identity-restricted), so ONE path covers all three contexts with no zone branching. Only a `groups[6]` block + an options sub-page were missing.
- **Implementation**: `groups[6]` default (Core), "Enemy Player" sub-page (Options), `page_enemyPlayer` locale, cast-path hardening (`HasValue`), `/dnp test` class probe. See Part B.

### 2026-06-21: Important-cast health recolor + per-group cast config + options i18n (v0.7.0)

- **Decision (Jerry)**: (a) when a hostile unit casts an important spell, **recolor its health bar** (default WHITE, configurable) for the cast, revert after. Must be secret-safe (work in instances) -> fold the (maybe-secret) `important` flag into the bar vertex color via `EvaluateColorValueFromBoolean(castImportant, special, threat)`, never a Lua branch. Friendly-side equivalent deferred (its own settings later).
- (b) **Pre-coloring "dangerous caster" mobs by NPC-id BEFORE they cast is infeasible in instances** and was explicitly NOT pursued: `UnitGUID`/NPC-id is secret on restricted maps, and `IsSpellImportant`'s result + spellID are secret there, so neither a curated ID list nor a stored per-unit "is dangerous" memory can be matched/tested in Lua. `IsSpellImportant` (only live DURING the cast) is the one sanctioned channel -> the white-on-important-cast recolor is the feasible form. (Open-world GUID is readable but low value; a one-line `issecretvalue(UnitGUID)` probe could confirm if ever revisited.)
- (c) **All cast-bar settings decoupled per-group**, each on its own sub-page (width / height / normal color / important color / glow). Old GLOBAL cast settings migrated into each group block at login.
- (d) **Options panel bilingual (en/zh)**; a mutually-exclusive language radio on the General page changes ONLY the panel language (not in-game plate text); applies after `/reload`.
- **Implementation**: `Locale.lua` + `ns.L` + `ns.ApplyLocale`; `Plate.lua` ColorBar/StartCast/StopCast; `Core.lua` per-group defaults + migration; `Options.lua` per-group cast block + language radio.

### 2026-06-20: Look + behavior decisions (Phase 1 visual direction)

- **Decision**: (a) Visual style mirrors **Plater's defaults** (Plater is installed on the HOME machine; read it as the baseline). (b) Hostile-creature (group 5) bar color is **threat-state based, not health %** -- it does not change with health. (c) Hostile-creature names **always shown**. (d) Fonts + healthbar texture = **Blizzard defaults** for now (swap later via options). (e) **No minimap icon**; all settings live in the addon options panel, grouped by section/block.
- **Threat color rule** (group 5 bar):
  - Tank role: securely tanking (threat held) -> RED (normal); not secure -> BLUE (warning).
  - DPS / Healer role: no aggro (safe) -> RED (normal); has / over aggro -> BLUE (warning).
  - Red = "as it should be for your role"; Blue = high-contrast "wrong for your role" alert. Both colors individually adjustable. Healer treated as DPS (assumed; confirm). Threat unknown / solo / out of combat / secret -> RED.
  - Implemented via `UnitThreatSituation("player", unit)` (`issecretvalue`-guarded -- Plater guards it, Plater.lua ~7712) + role via `GetSpecializationRole`, refreshed on spec change.
- **Rationale**: red-as-normal keeps the familiar "enemy = red" look while blue is a high-contrast alert that the threat situation is wrong for the role. Health-% coloring dropped -- the threat signal is what Jerry wants to read at a glance.
- **Supersedes**: the health-gradient bar color in the original DESIGN (`UnitHealthPercent` + colorCurve) is no longer the group-5 bar driver.
- **Implementation**: DESIGN.md sections 1-3 (+ the threat-state color rule subsection).

### 2026-06-19: Addon scope, name, primary use

- **Decision**: Build "DodoNameplate", a Retail nameplate addon. Primary use = PvE (raid / Mythic+ / open world). PvP wanted but deferred to Phase 2.
- **Rationale**: Jerry's main play is PvE; PvP enemy-player styling is a clean separate layer on the same classification engine, so it rides along later.
- **Implementation**: DESIGN.md phasing.

### 2026-06-19: Midnight Secret Values reshapes the product

- **Decision**: Treat DodoNameplate as a per-category visual + basic-state nameplate, NOT a combat-intel addon.
- **Rationale**: WoW 12.0 Secret Values blocks tainted code from logic on enemy health / auras / cast / combat log, hardest exactly in instances (our main use). Verified via warcraft.wiki (Secret_Values + Patch 12.0.7/API_changes) and by reading Plater + ThreatPlates source (both Interface 120007).
- **Implementation**: full API reality in GOTCHAS.md.

### 2026-06-19: Classification is viable (make-or-break)

- **Decision**: The 6-group identity design is buildable.
- **Rationale**: `UnitReaction` / `UnitIsPlayer` / `UnitClassification` are NOT secret -- both reference addons branch on them raw on 12.0.7 (ThreatPlates uses UnitReaction as a table key; Plater compares with `>=`). Only `UnitIsUnit(unit,"player")` self-detection is secret (handled via the personal-resource path).
- **Implementation**: GOTCHAS.md S3.

### 2026-06-19: Final grouping decisions

- **Decision**: (a) Friendly players (party + other) default OFF, each its own toggle. (b) Neutral creatures share the hostile-creature style, only swapping reaction color -- no separate group. (c) Elite/rare/boss = border/icon distinction only. (d) Enemy-healer marking CUT (no feasible detection).
- **Rationale**: keep config lean; build only what 12.0 allows.
- **Implementation**: DESIGN.md sections 1 and 5.

---

## Part B — Session Narrative

### 2026-08-17 (evening, OMEN): Seam back at 4px, execute rule, first monorepo release

Started as a sync job — OMEN was 14 commits behind HOME — and turned into two features.

**A correction worth recording, because it nearly went into the docs as fact.** Asked whether the
class-colour split was done, I read the code (4px), saw `PENDING-WORK.md` describing "top half /
bottom half", and "corrected" the doc — including a claim that the code had *always* read the
constant. Then Jerry explained the actual history: the morning build really was half-and-half with
a 1px seam, he verified **that**, judged it ugly, and asked for 4px with no seam; that edit was
pushed unverified. Checking `git log -S TINT_CLASS_STRIP` had shown a single commit, and I took
that to mean a single version — but **`ab06948` squashes both iterations**, so git history cannot
say which one a human looked at. Two lessons, both now in the repo: the doc line was not stale (it
described what shipped at the time it was written), and *"which version was verified" is not a
question git can answer*. `PENDING-WORK.md` carries the warning next to that commit id.

That also un-blocked three question marks: the morning pass **did** confirm `SetVertexColor` accepts
a raw secret out of `GetStatusBarColor`, in the open world *and* in a battleground — which in turn
settles that a nameplate in a BG does not get `pvpUseClassColors` (there was a class colour there to
borrow). GOTCHAS S5b updated from "unverified at the time of writing" to measured; the `pcall` and
print-once fallback stay, now justified as "undocumented Blizzard contract, a patch can withdraw
it" rather than "we don't know".

**Then the execute rule.** New `Execute.lua`, ~180 lines, and the cheapest feature in the addon: it
reads no unit data, so none of the Secret Values apparatus applies. The design work was in what it
refuses to do — see Part A. Verification is `test/test_execute.lua`, which stubs the WoW API and
loads the **real** module (not a hand-rolled fixture); 15 assertions, and every one of them was A/B'd
by seeding real violations: marking Shadow Priest `unverified` reddens exactly the four assertions
that depend on it, breaking the position maths reddens only the geometry one (`got 50.0 want 20`),
reverting the width to 1 reddens only the width one. Undoing those probes needed care — `Execute.lua`
is untracked, and `git checkout --` on an untracked file is a silent no-op — so restores went through
file backups and were confirmed by **reading the line back**, not by trusting an exit code.

- **Built `Tint.lua`** to the design already verified by `/dp tint` (GOTCHAS S5): per-token permanent proxy frame standing in for a health bar that does not exist at login; textures anchored to the proxy and re-pointed at the bar's **fill** on attach (anchoring to the whole bar would bury the health level); one declared frame-level stack `ns.LEVEL_TINT / LEVEL_IMPORTANT / LEVEL_TEXT`. Name, health % and the elite icon **had to move off `hb` onto a new `f.fg` layer** — a tint covering the fill covers whatever else is drawn on the fill, and they were. The important-cast recolour moved out of `ColorBar`'s vertex colour into `f.impTint` above the tints, so there is one implementation rather than two.
- **In-instance acceptance passed**, which also answered the one thing the probe could not: `SetParent` on the proxy DOES re-level Blizzard's aura buttons through the C-side cascade. A visible tint inside an instance is only possible if that happened — had it not, the tint would draw behind the bar and show nothing at all, the same symptom as a wrong spell ID or a late attach. `/dnp tint` prints `hb / proxy / container` levels precisely to separate those. GOTCHAS S5a's red warning was rewritten into a conclusion rather than left standing as a falsified caveat.
- **Then Jerry's real complaint**: in a battleground every enemy bar is red, so he cannot tell classes apart. `/dnp test` printed `class: SECRET`, matching the contract annotation. Chased `UnitClassFromGUID` — the contract permits a secret argument and marks only the localized `className` as `ConditionalSecret`, so `classFilename` looked open. **My first extraction of that entry missed `ConditionalSecret` entirely** and read as "this function has no restrictions" — clean, quotable, and wrong; re-reading the entry verbatim caught it. Built `/dp class` (per-return three-state, identity pinned, negative control made visible rather than left to memory) and measured in a BG: **all three returns SECRET** for every identity-restricted enemy. `SecretArguments = "AllowedWhenTainted"` means *you may pass one in*, not *you may learn the answer*.
- 🎁 **The row that saved a trip**: one teammate in that same BG had a plaintext GUID and produced a valid colour — a positive control proving the probe worked and the wall is per-unit-identity, not "nil everywhere". The open-world negative control was therefore never needed.
- **Pivot to borrowing**: read Blizzard's own `CompactUnitFrame_UpdateHealthColor` — plain `UnitClass` + `RAID_CLASS_COLORS`, **zero secret handling**, because untainted code needs none. `NamePlateEnemyFrameOptions.useClassColors = true` and the gate consults no CVar. Jerry confirmed empirically that Blizzard's bare enemy plates ARE class-coloured in a BG (Druid orange, Priest white — not the `1,0,0` fallback). So the colour was on screen the whole time, under the bar we hide. Reading it back yields a secret; a secret may be handed to a sink. **I had called the feature dead one turn earlier — that was correct for reading and overstated for the feature**, and `PENDING-WORK`'s "do not re-attempt" line was corrected before it could stop a future session from taking a live path.
- **Jerry caught my own inconsistency**: I claimed the split-bar need was "automatically satisfied" once the base became the class colour. It was not — the tint is opaque and covers whatever is under it. That is what produced the 4px-strip design.
- **Two probe defects found and fixed, same root**: `cell()` printed `T:string` then `T:boolean` instead of values, so `name` / `cFile` / `player` / `atk` all came back as type names — a sampling probe reporting the type of the thing it measured instead of its identity. Fixed for strings, then **the same hole again for booleans** one round later; enemy-vs-teammate had to be *inferred* from GUID secrecy in the meantime.
- **Not verified**: whether `SetVertexColor` swallows a raw secret number. Guarded + prints once on refusal.

### 2026-08-11: v0.9.0 was dead on arrival on 12.1; root cause + four fixes (v0.9.1)

- **Report**: BugSack showed `2x FontString:SetText(): Font not set`, innermost frame `Blizzard_AuraContainerFrameProviders.lua:79`, unwinding through `AddAuraGroup` -> `Auras.lua:107/147/171` -> `Core.lua:324`.
- **Root cause** (verified against the 12.1.0 (69273) source; all four cited line numbers matched 4-of-4): `Auras.lua` created the count font string bare and called `SetApplicationCount` five lines before the only `SetFont`. `CustomAuraButton.lua:67` stores it, `:68` calls `UpdateAuraDisplay`, reaching `:368 fontString:SetText("")` — inside the addon's own call.
- **Why "2x" and not 280x**: two errors per UI load, not two logins. Error 1 (at the addon's line) is swallowed by `securecallfunction` at providers `:79` — which is why the stored stack has no DodoNameplate initializer frame. Error 2 comes from the provider's unconditional `UpdateAuraDisplay` at `:90`, hits the same still-font-less string (it was already registered before the first throw), and propagates, aborting `Initialize` on the first group of the first bundle. BugGrabber dedupes on message string alone, so both collapsed into one record.
- **Why 0.8.2 was fine with the identical `CreateFontString`**: it owned the font string end to end and always fonted it before writing. v0.9.0 transferred ownership and detonated a latent defect.
- **Fixes**: (1) register the sinks last, after `ApplyButtonAppearance`, plus a probed font template as a second line of defence; (2) `xpcall` at the `Core.lua` call site; (3) `supported` set after the loop; (4) `Options.lua` font fallback. Plus two real bugs found while auditing the never-executed paths: every filter string was missing `INCLUDE_NAME_PLATE_ONLY` (the client was actively filtering out nameplate-flagged auras), and `groupSpacing = GAP` clipped 1-3px off each row's last icon because `RowWidth()` does not model inter-group spacing.
- **Verification**: no Lua interpreter on this machine, so three independent readers plus a reconciler checked syntax; the reconciler seeded five breaks into its own checker first and confirmed all five reported at the right line before trusting the clean run. In game, the BugGrabber counter stayed at 4 across the patched session while a DodoInspect error advanced in that same session — a live negative control proving the channel was working and this error simply did not fire. Not verified: whether icons actually render (no combat test yet).
- **Process note**: v0.9.0 was authored and released through the GitHub API by another agent, bypassing the tag-triggered pipeline via a one-shot workflow that was deleted 40 seconds later, and the local AddOns folder lost its `.git`. Restored to the documented in-place working tree as part of this session.

### 2026-06-24: Forbidden-plate fix + name-in-bar + aura feature + config panel + icon + baked defaults (v0.8.0)

- **Forbidden fix**: `Core.lua` `GetPlate` returns `GetNamePlateForUnit(unit)` only (dropped the `or (..., true)` forbidden fallback); `Plate.lua` `Style.Apply` early-returns on `plate:IsForbidden()`. New GOTCHAS.md S2 entry. Found via a multi-agent root-cause + an in-game `/run C_NamePlate.GetNamePlateForUnit("target",true)` probe (normal getter nil, forbidden getter returns a frame, itype = raid/party).
- **Name-in-bar**: `Plate.lua` `AnchorName(f)` helper -- in-bar for `IsEnemyPlate(group)` (after the elite icon, or flush-left), above-bar otherwise; called from LayoutPlate + UpdateClassification (elite visibility decides the left anchor). Name font auto = `max(8, height-6)`. Options drops the nameSize slider for enemy groups.
- **Auras** (new `Auras.lua`, in the `.toc` after Plate.lua): `GetUnitAuras("HARMFUL"/"HELPFUL")` -> route each by `IsAuraFilteredOutByInstanceID(unit, auraInstanceID, "<CAT>")` -> secret-safe sinks (`Icon:SetTexture`, `Cooldown:SetCooldownFromDurationObject` + `SetHideCountdownNumbers(false)` for the C-side number, `SetText(C_StringUtil.TruncateWhenZero(count))`). Two icon rows per plate (main = mine+important, black/gold border; cc slot = shared CC, red border), driven on `UNIT_AURA`. Applies to groups 5+6 (`IsEnemyPlate`). Shared `ns.db.auras`; old per-group `auras` blocks nil-migrated at login.
- **Config panel**: dedicated "Auras"/光环 sub-page (`BuildAuraPage` in Options.lua) -- category toggles (个人减益 / 共享控制 / 重要减益 / 敌方增益) + max / width / height / show-timer; live via RefreshAll. New Locale keys (en + zh), verified 1:1.
- **Icon + defaults**: `.toc` `## IconTexture: ...\Media\Dodo.tga` (copied from DodoInspect, self-contained). `ns.defaults` re-baked from Jerry's live SavedVariables (markSize 40, group-2/3 widths 75/90, group-6 200x20, group-5 castTextSize 18); `locale = "enUS"`. Two field-match gaps caught by an adversarial verify (group-5 castTextSize, group-6 castImportantColor) and fixed. Vestigial save-only fields (`targetArrow*` -- zero code refs) intentionally NOT baked.
- All `luac -p` clean. In-game (Jerry): forbidden fix + name-in-bar + aura row/CC/timer + panel toggles tested OK; STILL pending = the 3-scenario PvP test (war / BG / arena, esp. enemy-player auras + class color) and a raid/M+ aura pass. Committed as v0.8.0.

### 2026-06-21: Phase 2 PvP base -- enemy-player nameplates (v0.8.0)

- Enabled group 6 (enemy player): added a `groups[6]` default block (enabled, width 130 / height 14 / cast on) + an "Enemy Player" options sub-page (`page_enemyPlayer`, inserted after Hostile creature). NO engine changes -- `Classify` already returns ENEMY_PLAYER for a hostile player, and `GroupColor` already colors group 6 by class (guarded) with a red fallback. Works war mode / BG / arena uniformly (classification is pure reaction-based, no zone gating).
- **Cast-path hardening for PvP**: a cast name can be SECRET for enemy players in an active PvP match, where `if not name` (StartCast) and `if UnitCastingInfo(unit)` (CheckCast) would error on the boolean test. Added `HasValue(v) = Guards.IsSecret(v) or v ~= nil` (secret = present, nil = absent) and routed both through it. No change for creatures (non-secret names).
- **PvP probe**: `/dnp test` now prints `class:` (SECRET / <token> / nil) for the target, so we can see in-game whether `UnitClassBase` is readable in BG vs arena vs war mode (that decides class-color vs red fallback).
- `luac -p` clean. In-game /reload + war mode / BG / arena test pending (Jerry). Watch: does the enemy cast bar populate (name/duration) in an active PvP match, and is class readable per-context.

### 2026-06-21: Raid marker above bar, elite inside bar, uninterruptible stripe overlay (v0.7.1)

- **Raid target marker** moved to centered DIRECTLY ABOVE the bar (`mark` anchored BOTTOM -> hb TOP); size is now a GLOBAL config `ns.db.markSize` (default 24, was a fixed 16). Drawn on `f` while the name is on `hb` (a child of f) -> the name renders ABOVE the marker (Jerry: "layer below the name"). **Secret fix**: `GetRaidTargetIndex` is SECRET in instances (Jerry's `/dnp test` -> `raidMark: SECRET`) -- the marker was being HIDDEN by an `IsSecret(idx)` guard (visible at range via Blizzard's own icon, gone once our plate took over). Fixed to mirror Plater: pass the maybe-secret index straight to `SetRaidTargetIconTexture` (a sink) + `:Show()`, guard only `if idx` (truthiness, nil = unmarked) -- never hide on secret. Also: cast spell icon now sized to the cast bar height; the stripe TGA was made bolder; `/dnp test` prints a `raidMark:` readout.
- **Elite/rare icon** moved INSIDE the bar, left-aligned (reparented from `f` to `hb` so it sits above the fill); auto-sized to the bar height (height - 2). Border gold/silver/black unchanged.
- **Uninterruptible ("steel") cast stripe**: a tiled gray diagonal-stripe overlay over the cast fill, BELOW the cast text. `Media/stripe.tga` = a generated 32x32 seamless TGA (period-8 diagonal, semi-transparent gray). Shown via `cb.noInterrupt:SetAlphaFromBoolean(notInterruptible, 1, 0)` -- secret-safe, never branched in Lua (same gate as the interrupt shield). Tiled undistorted with `SetTexCoord(0, w/32, 0, castHeight/32)` + REPEAT wrap. Plater has NO stripe texture (it just recolors uninterruptible casts via `cast_statusbar_color_nointerrupt`), so we ship our own asset.
- New binary asset: `Media/stripe.tga`. (Loads on /reload; if a brand-new texture ever fails to appear, a full client restart picks it up.)
- **Current-target arrows**: two white triangles FLANKING the bar (`Media/arrow.tga` is a right-pointing triangle; left arrow as-is points right, right arrow mirrored via `SetTexCoord(1,0,0,1)` points left), shown ONLY on the target plate (existing non-secret frame-compare `GetNamePlateForUnit("target")`). Size tracks the bar height; plain white; NO config. (First tried a single up-arrow BELOW the bar, but the cast bar covered it -- Jerry moved it to side flankers. The shipped white TGA tints/stays clean; Blizzard's built-in arrows are pre-shaded.)
- **Raid marker fix (the real one)**: the marker stayed invisible even after the secret-sink fix because `f.mark` had NO base texture -- `SetRaidTargetIconTexture` with a secret index sets only the texcoord, not the texture file. Pre-setting `mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")` at creation (as Plater does) made it show. `/dnp test` now also dumps the target plate's mark state (shown / width / texture).

### 2026-06-21: Important-cast health recolor, per-group cast config, options i18n (v0.7.0)

- **Health-bar recolor on important cast**: `f.castImportant` is stored at `StartCast` (storing a secret is fine; only fed to sinks) and folded into `ColorBar` via `EvaluateColorValueFromBoolean(castImportant, special, threat)` per r/g/b -> WHITE while important-casting, threat color otherwise; `StartCast`/`StopCast` each trigger an immediate `ColorBar`; `f.unit` is stored so `StopCast` can revert; reset on plate reuse (`Apply`/`Clear`). Only the hostile group (5) exposes the toggle + color (`importantHpRecolor` / `importantHpColor`).
- **Cast config decoupled**: `groups[g]` gained `castHeight` / `castColor` / `castImportantColor` (per group). `LayoutPlate` sizes the cast bar height from `cfg`, **width always follows the healthbar width** (not configurable -- Jerry); `ApplyCastColor` reads `cfg.castColor` / `cfg.castImportantColor`. The old GLOBAL `castHeight` / `castImportantColor` / `castGlow` were removed from defaults and migrated into each group block at login.
- **Important-cast look simplified (Jerry)**: dropped the additive glow halo (it flooded white once the important color was set to white) AND the gold border emphasis. Important casts are now just a clean **right-to-left reverse-fill bar** in `castImportantColor` over the dark track (black border, same as normal). `castGlow` + the glow texture + the cast-width slider were all removed.
- **Cast-target bar (hostile)**: below the cast bar, right-aligned, a **solid class-colored bar with the target name centered inside** -- NOT a health bar. Midnight exposes only `UnitSpellTargetName(unit)` + `UnitSpellTargetClass(unit)` (name + class) for a spell target -- there is NO unit token, so NO health (verified vs Plater HEAD, whose Midnight branch shows only the class-colored name, not a bar; its `unit.."target"` path is non-Midnight only). Player target -> class color; non-player -> a configurable fallback color. `Plate.lua` `UpdateCastTarget` (called from StartCast); per-group config `castTargetShow/Height/Width/TextSize/FallbackColor` (hostile only). Old below-bar `cb.targetName` FontString removed (superseded).
- **Cast text size**: per-group `castTextSize` now drives the spell name + countdown font (`LayoutPlate`). Spell name stays left-aligned.
- **Defaults rebaselined to Jerry's live config**: read his reload+logout-flushed `DodoNameplateDB` and set those values as `ns.defaults` (so a fresh download matches his look) -- all 4 groups enabled, hostile bar 214x24 / text 16, important cast color white, important->HP recolor purple, cast-target bar 70x18 / text 18 / color green. Vestigial saved keys (`castGlow`, `castWidth`, a stray group-5 `targetScale`) were NOT propagated. CopyDefaults only fills missing keys, so his (and anyone's) existing save is untouched.
- **`UnitSpellTargetClass` returns nil in practice**: in Jerry's instance tests the cast-target's class never came back, so the bar always used the configured color. Behavior unchanged (class color still applied IF the API ever returns one), but the option was relabeled "Non-player fallback color" -> "Cast target bar color" / "施法目标条颜色" (the db key stays `castTargetFallbackColor`).
- **i18n**: `Locale.lua` holds `enUS` + `zhCN` tables (zhCN metatable-falls-back to enUS, so enUS is the full key set). `ns.ApplyLocale()` resolves `ns.L` from `ns.db.locale` ("auto" follows `GetLocale()`) at PLAYER_LOGIN, before `InitOptions`. Every Options label routes through `ns.L`; group pages are now two-column (health left, cast right). Language = mutually-exclusive radio on General; changing it shows a red "/reload" note.
- Validated offline with `luac -p` on all 6 files (clean). In-game `/reload` + BugSack test pending (Jerry).

### 2026-06-20: Two-bar reverse-fill -- R->L important casts in instances too (v0.6.2)

- Cast bar restructured: a container Frame with **two overlapping fills** (forward L->R `fillL` + reverse R->L `fillR`, the latter `SetReverseFill(true)` once). Each cast: both get the same `SetTimerDuration`; the visible one is chosen by `SetAlphaFromBoolean(important)` -- **secret-safe, so important casts fill R->L even in instances** (where spellID is secret and SetReverseFill can't take it). Icon/text/time/target/shield moved to an overlay frame above the fills; glow/border kept.
- Watch item: both fills share one duration object -- if the reverse bar doesn't animate, give each its own `UnitCastingDuration` call.

### 2026-06-20: Important-cast prominence; CONFIRMED spellID is secret in instances (v0.6.1)

- **Field test (Magisters' Terrace, mob Polymorph)**: the important COLOR applied (orange, secret-safe) but the R->L flip did NOT -> **confirms the cast spellID / `IsSpellImportant` result is SECRET in 12.0.7 instances** (the `issecretvalue` guard correctly skipped `SetReverseFill`). So the direction flip only works where the flag is readable (open world); in instances it can't via SetReverseFill.
- Boosted prominence (secret-safe, works in instances): bigger/brighter additive glow (7px halo) + a **bright gold border** on important casts (`EvaluateColorValueFromBoolean`), black otherwise.
- **Open option**: a two-bar reverse-fill trick (two overlapping fills toggled by `SetAlphaFromBoolean(important)`) WOULD give the R->L flip in instances too -- not built yet (pending Jerry).

### 2026-06-20: Important (golden) casts -- color + reverse direction + glow (v0.6.0)

- `C_Spell.IsSpellImportant(spellID)` (Blizzard's important-cast flag; the API Plater uses on Midnight) now drives the cast bar: **color** via `C_CurveUtil.EvaluateColorValueFromBoolean(important, impColor, normalColor)` (secret-safe), optional **glow** via `SetAlphaFromBoolean`, and a **right-to-left fill** (`SetReverseFill`) -- guarded with `issecretvalue` since SetReverseFill is not a secret-safe sink, so it flips only where the flag is readable (always open world; instances iff spellID is not secret there -- TBD by testing).
- Normal casts stay gold and fill L->R; important casts go orange + glow + R->L. New options under General > Cast bar: "Important cast color" + "Important cast glow".
- Documented `C_Spell.IsSpellImportant` in GOTCHAS S3.

### 2026-06-20: Drop health amount (keep percent); level moved above-right (v0.5.3)

- After confirming (via Plater HEAD / ThreatPlates / DF calculator) that the absolute health amount can't be K/M-abbreviated under secret, **removed all health-AMOUNT display**. Only the **percent** remains inside the bar (right).
- **Level moved to the bar's TOP-RIGHT** (mirrors the name at top-left), leaving the whole area below the bar clear for the cast bar.
- Options: the "Health text size" slider is now "Percent size" (it only sizes the percent).

### 2026-06-20: Percent display fixes -- static % sign + integer step curve (v0.5.2)

- **Key 12.0.7 finding**: `UnitHealthPercent(unit, true, curve)` returns a **secret** number on 12.0.7 (unlike ThreatPlates' 120005 where it is plain). So it could only be shown via the SetText sink -> no "%" sign, and fractional (many decimals).
- Fixes: (1) the **"%" is now a separate static FontString** next to the number (cannot concat onto a secret); (2) the curve is a **0-100 integer STEP curve** so the secret value renders with **no decimals**.
- Reconfirmed Secret-Values limit: in restricted maps / combat the absolute health **amount** is secret, so it can't be K/M-abbreviated (math blocked) and shows raw; abbreviation only applies where health is readable (open world, out of combat). Percent works everywhere via the curve.

### 2026-06-20: Health text fixes -- robust percent, K/M abbrev, per-group font sizes (v0.5.1)

- **Percent was blank on restricted maps** (health is secret there even out of combat, and the curve was the only path). Now three-tier: direct `100*h/hmax` when readable -> `UnitHealthPercent(..., ScaleTo100)` curve -> raw `SetText` sink. Shows in all contexts.
- **Amount abbreviation = custom K/M/B** (`AbbrevKM`) since the locale `AbbreviateNumbers` is 万/亿 on zhCN. Only when readable; raw when secret.
- **Per-group font sizes**: name / level / health-text each have their own slider on the group's options sub-page (`ns.db.groups[g].nameSize / levelSize / healthSize`).
- **Known Secret-Values limit**: the absolute amount can't be K/M-abbreviated while health is secret (restricted maps) -- it shows raw there; percent is fine via the curve.

### 2026-06-20: Healthbar text -- name / level / HP amount + percent (v0.5.0)

**Done** (Phase 1 polish, Jerry's layout):
- Name now **left-aligned above the bar** (was centered).
- **Level below the bar, right-aligned**; hidden for Friendly NPCs (group 4), shown for the rest; "??" for -1 (boss). `UnitLevel` is non-secret; refreshed on UNIT_LEVEL.
- Inside the bar: **HP amount (left) + HP percent (right)**. Secret-safe: amount via `SetText` sink (shows the real value even when secret; `AbbreviateNumbers` only when readable); **percent via `UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)`** which returns a plain 0-100 number -- the sanctioned way to read enemy health % under Secret Values (ThreatPlates StatusText.lua). Updates on UNIT_HEALTH/MAXHEALTH.
- Confirmed with Jerry that none of these trip Secret Values: name/amount are sinks, percent uses the curve API, level + UnitClassification are non-secret.

### 2026-06-20: Neutral creatures yellow (until engaged) + dungeon validation (v0.4.2)

**Done**:
- Neutral creatures in the hostile group now color YELLOW (reaction color) until engaged; once you have a threat relationship (`UnitThreatSituation` non-nil) they switch to the hostile threat red/blue. `HostileColor()` in Plate.lua; recolors via the existing UNIT_THREAT_* events.
- **Validated in a 5-man dungeon (Jerry)**: health fill, threat colors, cast bars, borders all work in instanced combat with no Lua errors -- Secret Values handling confirmed in the hardest live context.
- Per Jerry: distance scaling dropped; empowered (Evoker) cast stages deferred.

### 2026-06-20: Fixes -- "Unknown" name + critter default (v0.4.1)

- Nameplate name could show `UNKNOWNOBJECT` (未知目标) when `UnitName` was not yet loaded at NAME_PLATE_UNIT_ADDED. Now refreshed on `UNIT_NAME_UPDATE` (`ns.Style.UpdateName`).
- Hide-critters overlay default flipped to OFF -- the `UnitClassification == "minus"` test also caught small trivial mobs (小爬爬) the user wanted to see. Existing saves keep their value; toggle in General. (Open question: replace the "minus" test with a true critter creature-type check if we re-enable by default.)

### 2026-06-20: Elite/rare borders + cast polish + focus highlight (v0.4.0)

**Done**:
- Classification borders on styled creatures via `UnitClassification`: gold (elite / rareelite / worldboss), silver (rare), black (normal); plus the gold/silver elite-dragon atlas icon when it exists (`C_Texture.GetAtlasInfo`-guarded).
- Border state unified with priority **target (white) > focus (cyan) > elite (gold) / rare (silver) > normal (black)**; scale only on target.
- Cast bar polish: right-aligned **countdown** (castbar OnUpdate reading the duration object's `GetRemainingDuration`, secret-guarded) + **cast-target name** below the bar (`UnitSpellTargetName`, SetText sink).
- **Focus highlight**: cyan border on the focus plate, detected via `C_NamePlate.GetNamePlateForUnit("focus")` (PLAYER_FOCUS_CHANGED) -- same secret-free frame-compare as target.

### 2026-06-20: All PvE groups + overlays + sub-page options (v0.3.0)

**Done**:
- Config restructured to per-group blocks `ns.db.groups[2..5]` (+ migration of the old single `hostile` block into groups[5]); global `targetScale`, `castHeight`, `overlays`, threat colors.
- Plate.lua generalized: any ENABLED group is styled; color source per group -- hostile = role-aware threat (red/blue), party/other players = class color (`UnitClassBase` + `GetClassColor`), friendly NPC = reaction (`UnitSelectionColor`). Disabled group -> hands off (Blizzard default).
- Overlays: dim tapped creatures (`UnitIsTapDenied`), hide critters (`UnitClassification == "minus"`).
- Options split into Blizzard sub-pages: General (threat colors, overlays, target scale, cast height) + a canvas sub-category per group (Hostile / Friendly NPC / Party-Raid / Other Players) via `Settings.RegisterCanvasLayoutSubcategory`. Defaults: only Hostile enabled; friendly groups off.
- Self (1) left as Blizzard's personal resource (self-detect is secret); enemy player (6) deferred to Phase 2.

### 2026-06-20: Options moved into the Blizzard settings UI

**Done**:
- Replaced the standalone `/dnp` window with a canvas category registered via `Settings.RegisterCanvasLayoutCategory` + `Settings.RegisterAddOnCategory` -> appears under Esc -> Options -> AddOns -> DodoNameplate. Chose canvas (not the native vertical-layout list) to keep the color pickers + section layout. Controls reused unchanged; `/dnp` now calls `Settings.OpenToCategory`. Registered at PLAYER_LOGIN via `ns.InitOptions()` (called from Core after ns.db is ready).
- Tradeoff agreed with Jerry: the full options frame covers the screen, so plate changes are not visible live while it is open (adjust -> close -> look). A test-plate preview inside the page is a possible later add.

### 2026-06-20: Options panel + config-driven rendering

**Done**:
- SavedVariables `DodoNameplateDB` with `ns.defaults` merged at login (CopyDefaults). Plate.lua now reads all sizes / colors / toggles from `ns.db` (fallbacks if unset); added `Style.RefreshAll()` to re-apply to open plates after a change.
- Standalone options panel (Options.lua), opened with `/dnp` (Esc-closes; draggable), no Blizzard Settings-API / template dependency. Hand-rolled controls (checkbox / slider / color-swatch via `ColorPickerFrame:SetupColorPickerAndShow`).
- Exposed (hostile / group 5): healthbar width + height, name size + show toggle, cast-bar show toggle, target scale, and the two threat colors (normal / warning).
- `/dnp` now opens options; `/dnp test` runs the old classification probe. TOC -> 0.2.0.

### 2026-06-20: Cast bar (group 5)

**Done**:
- Own cast bar below the healthbar (child of our frame, so it scales with the target highlight). Spell name + icon read raw (not secret on Midnight, per ThreatPlates reading them unguarded).
- Progress driven by `UnitCastingDuration(unit)` / `UnitChannelDuration(unit)` -> `StatusBar:SetTimerDuration(dur, Immediate, ElapsedTime|RemainingTime)` (C-side animation; casts fill, channels drain). No OnUpdate.
- Interrupt shield (`nameplates-InterruptShield` atlas) shown via `SetAlphaFromBoolean(notInterruptible, ...)` since notInterruptible may be secret; INTERRUPTIBLE/NOT_INTERRUPTIBLE events toggle it live.
- Core: registered the UNIT_SPELLCAST_* family. Restores the hostile cast bars that hiding the Blizzard plate had removed.

### 2026-06-20: Target highlight + raid marker + font fix (group 5)

**Done**:
- Name font -> `STANDARD_TEXT_FONT` (locale-correct; fixes CJK names rendering as tofu boxes -- the only issue from the first hostile-plate test).
- Target highlight: the current target's hostile plate scales up (1.18) + white border. Detected by comparing the plate to `C_NamePlate.GetNamePlateForUnit("target")` (frame compare), NOT the secret `UnitIsUnit`.
- Raid target marker via `GetRaidTargetIndex` + `SetRaidTargetIconTexture`, left of the bar.
- Core: added `PLAYER_TARGET_CHANGED` + `RAID_TARGET_UPDATE`.

**Confirmed in-game (Jerry, screenshot)**: hostile healthbar + red/blue threat color correct.

### 2026-06-20: Group 5 plate replacement (steps 4-6, hostile)

**Done**:
- Studied the reference plate-replacement approach (cloned ThreatPlates `feature/midnight` to `%TEMP%`; read local Plater). Confirmed: both addons HIDE the Blizzard plate and draw their own rather than fighting Blizzard's health system, so DodoNameplate does the same.
- Built `Plate.lua` (`ns.Style`): for hostile (group 5) plates, hide the Blizzard `UnitFrame` via `SetAlpha(0)` kept hidden by a `hooksecurefunc` on SetAlpha with a recursion lock (mirrors ThreatPlates ~888), and draw our own StatusBar healthbar + name (always on) parented to the plate base frame (inherits nameplate scale + range fade, not the UnitFrame alpha).
- Health fill via secret-safe `SetMinMaxValues`/`SetValue`; bar color via `GetStatusBarTexture():SetVertexColor` (the Midnight way, not SetStatusBarColor). Role-aware threat color (red normal / blue warning) via `UnitThreatSituation("player", unit)` (issecretvalue-guarded) + cached role from `GetSpecializationRole`.
- `Core.lua` now drives it: added UNIT_HEALTH/UNIT_MAXHEALTH, UNIT_THREAT_LIST_UPDATE/UNIT_THREAT_SITUATION_UPDATE, PLAYER_SPECIALIZATION_CHANGED; role cache; `/dnp` also prints role.

**Known WIP**: only group 5 styled (others = Blizzard default); hostile cast bars hidden until step 7; our bar is fixed-size (no target-scale yet); visual numbers + colors are first-pass.

**Pending -> next**: extend to other groups; target/focus highlight + raid marker; nameplate scale; cast bar. See PENDING-WORK.md.

### 2026-06-20: Phase 1 skeleton (steps 1-3) + dev env on HOME machine

**Done**:
- Decided to develop + test on the HOME desktop (big screen, primary gaming machine). Cloned the repo into `D:\World of Warcraft\_retail_\Interface\AddOns\DodoNameplate\` as the working tree (edit -> /reload -> test -> commit in one place). Confirmed BugSack + !BugGrabber installed for Lua errors; Plater installed locally as the live reference (ThreatPlates to be pulled from GitHub when needed).
- Renamed the GitHub repo DodoNamplate -> DodoNameplate and spelling-fixed all docs.
- Built Phase 1 steps 1-3: `DodoNameplate.toc` (Interface 120007); `Guards.lua` (issecretvalue/canaccessvalue shim + Bool/UnitIsUnit force-false-on-secret, mirroring Plater); `Classification.lua` (6-group sort via UnitIsPlayer/UnitCanAttack/UnitInParty-Raid + tapped overlay); `Core.lua` (NAME_PLATE_UNIT_ADDED/REMOVED/CREATED + UNIT_FACTION/UNIT_FLAGS hooks, re-classify on flip, `/dnp` test command). No reskin yet -- nothing visible in-game beyond the load message + `/dnp`.

**Pending -> next**: Phase 1 step 4 (per-group reskin, group 5 first), then step 5 (health fill) + step 6 (states incl. threat-state color). See PENDING-WORK.md.

### 2026-06-19: Design discussion + blueprint scaffold

**Done**:
- Worked the unit-grouping design from a rough 5 groups to a verified 6 groups + 2 overlays + a cross-cutting state layer.
- Researched the Midnight Secret Values system from authoritative sources; confirmed the client is on 12.0.7 (live).
- Read Plater + ThreatPlates source to verify what tainted code can still do; resolved the classification question (viable).
- Cut enemy-healer marking. Locked the final grouping.
- Scaffolded this repo (docs only, no code) as a context handoff for building on another machine.

**Pending -> next session**: Phase 1 PvE skeleton. See PENDING-WORK.md.
