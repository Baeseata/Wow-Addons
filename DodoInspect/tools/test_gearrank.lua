-- DodoInspect - tools/test_gearrank.lua
-- Offline test for GearRank.lua. Run from the addon folder:
--
--     lua tools/test_gearrank.lua
--
-- Not shipped. It loads the real Data/Loot.lua and the generated item
-- shape fixture, stubs the two client APIs GearRank touches, and checks
-- the ranking rules that would otherwise only be observable in game.

local failures = 0
local checks = 0

local function check(condition, label)
    checks = checks + 1
    if not condition then
        failures = failures + 1
        print("FAIL  " .. label)
    end
end

local function checkEqual(actual, expected, label)
    checks = checks + 1
    if actual ~= expected then
        failures = failures + 1
        print(string.format("FAIL  %s (got %s, expected %s)",
                            label, tostring(actual), tostring(expected)))
    end
end

-- Load addon files the way the client does: as chunks receiving
-- (addonName, namespace) through the vararg.
local ns = {}
local function loadAddonFile(path)
    local chunk = assert(loadfile(path))
    chunk("DodoInspect", ns)
end

local shapes = assert(loadfile("tools/fixture_itemshape.lua"))()

-- Stub the only two client entry points GearRank uses.
_G.GetItemInfoInstant = function(itemID)
    local shape = shapes[itemID]
    if not shape then return nil end
    -- itemID, itemType, itemSubType, equipLoc, icon, classID, subclassID
    return itemID, nil, nil, shape[1], nil, shape[2], shape[3]
end
_G.C_Item = {}

ns.Config = { STAT_PRIORITY_FEATURE_ENABLED = true }
loadAddonFile("Data/Loot.lua")
loadAddonFile("GearRank.lua")

-- Stand in for StatPriority's resolver so the test states the order it
-- is ranking against instead of depending on shipped spec data.
local orderUnderTest
ns.StatPriorityOrder = function() return orderUnderTest end

--------------------------------------------------------------------
-- Weights: a tie group must consume as many positions as it has
-- members, otherwise the notation silently changes the ranking.
--------------------------------------------------------------------
-- Asserted WITHOUT hardcoding the curve. The numbers in POSITION_WEIGHT
-- are a tuning decision that has already moved once; the position mapping
-- is the invariant. Restating the values here just means a retune shows
-- up as two failing tests that are not actually about tie groups.
local flat = ns.StatWeights({ "crit", "haste", "mastery", "versatility" })
checkEqual(flat.crit, 1.00, "flat order: first stat is the reference 1.00")
check(flat.crit > flat.haste, "flat order: 1st outweighs 2nd")
check(flat.haste > flat.mastery, "flat order: 2nd outweighs 3rd")
check(flat.mastery > flat.versatility, "flat order: 3rd outweighs 4th")

local tied = ns.StatWeights({ { "crit", "haste" }, "mastery", "versatility" })
checkEqual(tied.crit, flat.crit, "tie group: both members share first weight")
checkEqual(tied.haste, flat.crit, "tie group: second member shares it too")
-- The point of the whole section: mastery lands on the THIRD weight, the
-- one it would get in a flat order -- not the second. Comparing against
-- flat says that without naming a number.
checkEqual(tied.mastery, flat.mastery, "tie group consumes two positions")
check(tied.mastery ~= flat.haste,
      "tie group: the stat after it does NOT land on the second weight")

-- The curve's SHAPE, which is a design decision (owner, 2026-08-14): the
-- last stat is distinctly worse while the top three sit comparatively
-- close. Encoded as "the drop into last place is bigger than any gap
-- inside the top three". The old evenly-decaying 1.00/0.70/0.45/0.25
-- fails this check, which is exactly why versatility rings outranked
-- crit rings -- see the POSITION_WEIGHT comment in GearRank.lua.
local gap12 = flat.crit - flat.haste
local gap23 = flat.haste - flat.mastery
local gap34 = flat.mastery - flat.versatility
check(gap34 > gap12 and gap34 > gap23,
      "curve shape: last position is pulled further away than any gap "
      .. "inside the top three")

--------------------------------------------------------------------
-- Fit: normalise against the item's own budget, not a constant.
--------------------------------------------------------------------
weights = ns.StatWeights({ "crit", "haste", "mastery", "versatility" })
local pureCrit = ns.StatFit({ 0, 0, 0, nil, "crit", 7000 }, weights)
local mostlyCrit = ns.StatFit({ 0, 0, 0, nil, "crit", 4997, "haste", 2003 },
                              weights)
check(pureCrit > mostlyCrit, "all-in on the top stat outranks a split")

-- A ring carries roughly 17500 of budget against armor's 7000. Same
-- split, same score: the score must not reward the bigger budget.
local ringSplit = ns.StatFit({ 0, 0, 0, nil, "crit", 12493, "haste", 5007 },
                             weights)
local armorSplit = ns.StatFit({ 0, 0, 0, nil, "crit", 4997, "haste", 2003 },
                              weights)
check(math.abs(ringSplit - armorSplit) < 0.001,
      "ring and armor with the same ratio score the same")

checkEqual(ns.StatFit({ 0, 0, 0, nil, nil, nil }, weights), nil,
           "item with no secondary stats is unrankable, not zero")

--------------------------------------------------------------------
-- Candidate lists against the real season data.
--------------------------------------------------------------------
orderUnderTest = { "crit", "haste", "mastery", "versatility" }

local ARMOR_SLOTS = {
    "INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_WRIST",
    "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET",
}
local SPECS = {
    arms = 71,     -- Plate / STR
    holyPal = 65,  -- Plate / INT, the only plate healer
    arcane = 62,   -- Cloth / INT
    havoc = 577,   -- Leather / AGI
}

-- Anti-vacuum assertion: an empty list and a correct-but-filtered list
-- look identical from the outside. If the equipLoc mapping or the armor
-- filter breaks, this is what catches it.
for _, slot in ipairs(ARMOR_SLOTS) do
    for label, specID in pairs(SPECS) do
        local list = ns.SlotCandidates(slot, specID, nil, "raid")
        check(list and #list > 0,
              string.format("%s has candidates for %s", label, slot))
    end
end

for _, slot in ipairs({ "INVTYPE_CLOAK", "INVTYPE_FINGER", "INVTYPE_NECK" }) do
    local list = ns.SlotCandidates(slot, SPECS.arms, nil, "raid")
    check(list and #list > 0, "arms has candidates for " .. slot)
end

-- Armor type filter: plate and cloth must not share a single item.
local plateHead = ns.SlotCandidates("INVTYPE_HEAD", SPECS.arms, nil, "raid")
local clothHead = ns.SlotCandidates("INVTYPE_HEAD", SPECS.arcane, nil, "raid")
local plateIDs = {}
for _, row in ipairs(plateHead) do plateIDs[row.id] = true end
local overlap = 0
for _, row in ipairs(clothHead) do
    if plateIDs[row.id] then overlap = overlap + 1 end
end
checkEqual(overlap, 0, "plate and cloth head lists do not overlap")

-- Primary stat filter, tested directly. It cannot be exercised through
-- SlotCandidates on this tier's data: every plate piece is tagged SI and
-- every leather piece AI, so the plate healer and the plate DPS legitimately
-- see the same list and a list-level assertion would be testing nothing.
check(ns.PrimaryFits("STR", "SI"), "strength spec can use a Str/Int item")
check(ns.PrimaryFits("INT", "SI"), "intellect spec can use a Str/Int item")
check(not ns.PrimaryFits("STR", "INT"), "strength spec cannot use pure Int")
check(not ns.PrimaryFits("INT", "AGI"), "intellect spec cannot use pure Agi")
check(ns.PrimaryFits("AGI", "SAI"), "everyone can use an all-three item")
check(ns.PrimaryFits("STR", nil), "items with no primary stat fit everyone")

-- Same-armor-type specs currently share their list, which is a fact about
-- this tier rather than a rule. Assert what is actually guaranteed: both
-- get a non-empty list and neither leaks the other armor type.
local holyHead = ns.SlotCandidates("INVTYPE_HEAD", SPECS.holyPal, nil, "raid")
check(#holyHead > 0, "holy paladin gets plate head candidates")
for _, row in ipairs(holyHead) do
    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(row.id)
    checkEqual(classID == 4 and subclassID, 4,
               "holy paladin head list contains only plate")
end

-- Cloaks carry all three primary stats, so every spec sees the same set.
local cloakA = ns.SlotCandidates("INVTYPE_CLOAK", SPECS.arms, nil, "raid")
local cloakB = ns.SlotCandidates("INVTYPE_CLOAK", SPECS.arcane, nil, "raid")
checkEqual(#cloakA, #cloakB, "cloak list is identical across specs")

-- Chest must pull both INVTYPE_CHEST and INVTYPE_ROBE. Cloth is where
-- robes live, so a broken alias table halves this list.
local clothChest = ns.SlotCandidates("INVTYPE_CHEST", SPECS.arcane, nil, "raid")
local robes = 0
for _, row in ipairs(clothChest) do
    local _, _, _, equipLoc = GetItemInfoInstant(row.id)
    if equipLoc == "INVTYPE_ROBE" then robes = robes + 1 end
end
check(robes > 0, "cloth chest list includes robes, not just INVTYPE_CHEST")

-- Unrankable items sink, and the order is deterministic.
local shoulders = ns.SlotCandidates("INVTYPE_SHOULDER", SPECS.arms, nil, "raid")
local seenUnranked = false
local ordered = true
for _, row in ipairs(shoulders) do
    if row.unranked then
        seenUnranked = true
    elseif seenUnranked then
        ordered = false
    end
end
check(ordered, "unrankable items never appear above ranked ones")

local repeated = ns.SlotCandidates("INVTYPE_SHOULDER", SPECS.arms, nil, "raid")
local stable = #repeated == #shoulders
for i = 1, #shoulders do
    if repeated[i].id ~= shoulders[i].id then stable = false end
end
check(stable, "ranking is stable across calls")

--------------------------------------------------------------------
-- Top item level tier (Myth 9/6 == 344): the last two Venomous Abyss
-- bosses. Promoted only when the item carries a primary stat, because
-- that is what those ten item levels actually buy.
--------------------------------------------------------------------

local function fakeEntry(instance, position, primary)
    return { instance, 0, position, primary, "haste", 4000, "crit", 3000 }
end

check(ns.ReachesTopItemLevel(fakeEntry(1320, 8, "INT")),
      "344: armor from the final boss is promoted")
check(ns.ReachesTopItemLevel(fakeEntry(1320, 7, "STR")),
      "344: armor from the penultimate boss is promoted")
check(not ns.ReachesTopItemLevel(fakeEntry(1320, 8, nil)),
      "344: a ring/neck from the final boss is NOT promoted")
check(not ns.ReachesTopItemLevel(fakeEntry(1320, 6, "INT")),
      "344: an earlier raid boss is not promoted")
check(not ns.ReachesTopItemLevel(fakeEntry(1030, 8, "INT")),
      "344: a Mythic+ dungeon is never promoted")

-- End to end, over every armor slot: promoted rows must all sort above
-- unpromoted ones. Counted, not just asserted -- an ordering rule that
-- never fires would satisfy the ordering check while doing nothing.
local ARMOR_SLOTS = {
    "INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_HAND",
    "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST",
    "INVTYPE_CLOAK",
}
local promotedTotal, orderHolds = 0, true
for _, slot in ipairs(ARMOR_SLOTS) do
    local list = ns.SlotCandidates(slot, SPECS.arms, nil, "raid")
    local seenPlain = false
    for _, row in ipairs(list or {}) do
        if row.topItemLevel then
            promotedTotal = promotedTotal + 1
            if seenPlain then orderHolds = false end
        else
            seenPlain = true
        end
    end
end
check(orderHolds, "344 items never appear below a lower-ceiling item")
check(promotedTotal > 0,
      "at least one armor slot actually contains a 344 item")

-- The rule the owner asked for, stated where it bites: rings and necks
-- from those same two bosses must NOT be promoted, because they have no
-- primary stat to gain.
--
-- Would this row be promoted if the one thing holding it back -- having
-- no primary stat -- were taken away? Asks the shipped rule rather than
-- restating which bosses count, so the test cannot drift away from it.
local function wouldPromoteWithPrimary(row)
    local clone = {}
    for i = 1, 9 do clone[i] = row.entry[i] end
    clone[4] = "STR"
    return ns.ReachesTopItemLevel(clone) == true
end

local nineSixBySlot = {}
for _, slot in ipairs({ "INVTYPE_FINGER", "INVTYPE_NECK" }) do
    local list = ns.SlotCandidates(slot, SPECS.arms, nil, "raid")
    local promoted, nineSix = 0, 0
    for _, row in ipairs(list or {}) do
        if row.topItemLevel then promoted = promoted + 1 end
        if wouldPromoteWithPrimary(row) then nineSix = nineSix + 1 end
    end
    check(list and #list > 0, slot .. " has candidates at all")
    checkEqual(promoted, 0, slot .. " gets no item level promotion")
    nineSixBySlot[slot] = nineSix
end

-- The two slots above do NOT carry the same evidence, and saying so is
-- the point of these two checks. Without them "promoted == 0" reads as
-- one result twice, when really it is one live assertion and one that
-- holds no matter what the rule says.
check(nineSixBySlot.INVTYPE_NECK > 0,
      "NECK assertion is live: a 9/6 neck exists and is held back only "
      .. "by the primary-stat condition")
checkEqual(nineSixBySlot.INVTYPE_FINGER, 0,
      "FINGER assertion is known-vacuous: no 9/6 ring drops this season, "
      .. "so its 'no promotion' result proves nothing. This check is the "
      .. "tripwire -- a future season that adds one turns it red, which "
      .. "is exactly when the assertion above starts carrying weight")

--------------------------------------------------------------------
-- Derived weapon proficiency (ns.SpecWeapons / ns.SpecShield)
--
-- Generated from SkillLine + SkillLineAbility.ClassMask, so these checks
-- guard a DERIVATION, not a hand-written list. The failure mode they
-- exist for is quiet shrinkage: rename a skill line upstream and every
-- spec's weapon list silently gets shorter, which reads exactly like a
-- stricter filter working correctly. Hence both directions below --
-- things that must be present as well as things that must be absent.
--------------------------------------------------------------------
local WEAPON_SUB = { axe1h = 0, axe2h = 1, bow = 2, gun = 3, mace1h = 4,
                     mace2h = 5, polearm = 6, sword1h = 7, sword2h = 8,
                     warglaive = 9, staff = 10, fist = 13, dagger = 15,
                     crossbow = 18, wand = 19 }

local specCount, weaponCount = 0, 0
for _ in pairs(ns.SpecGear) do specCount = specCount + 1 end
for _ in pairs(ns.SpecWeapons or {}) do weaponCount = weaponCount + 1 end
checkEqual(weaponCount, specCount,
           "SpecWeapons covers exactly the specs SpecGear covers -- one "
           .. "spec with an armor filter and no weapon filter would change "
           .. "behaviour for that spec alone")

local function canUse(specID, weapon)
    local set = ns.SpecWeapons and ns.SpecWeapons[specID]
    return (set and set[WEAPON_SUB[weapon]]) == true
end

-- Present-direction anchors. Without these the whole block passes on an
-- empty table, which is the exact failure being guarded against.
check(canUse(261, "dagger"), "subtlety rogue can use daggers")
check(canUse(577, "warglaive"), "havoc demon hunter can use warglaives")
check(canUse(257, "staff"), "holy priest can use staves")
check(canUse(269, "polearm"), "windwalker monk can use polearms (its 2H)")

-- Absent-direction anchors, each a real "cannot equip" in game.
check(not canUse(261, "staff"), "rogues cannot use staves")
check(not canUse(261, "polearm"), "rogues cannot use polearms")
check(not canUse(261, "sword2h"), "rogues cannot use two-handed swords")
check(not canUse(257, "sword1h"), "priests cannot use swords")
check(not canUse(262, "sword1h"), "shamans cannot use swords")
check(not canUse(253, "mace1h"), "hunters cannot use maces")
check(not canUse(103, "sword1h"), "druids cannot use swords")
check(not canUse(71, "warglaive"),
      "warglaives are demon hunter only -- warriors can use everything "
      .. "else, so this is the one weapon that proves the filter bites")

-- Shields are armor, so they live in their own table.
local shieldCount = 0
for _ in pairs(ns.SpecShield or {}) do shieldCount = shieldCount + 1 end
checkEqual(shieldCount, 9,
           "exactly 9 specs have shield proficiency (warrior, paladin and "
           .. "shaman, three specs each)")
check(ns.SpecShield and ns.SpecShield[262] == true,
      "elemental shaman can use a shield")
check(not (ns.SpecShield and ns.SpecShield[257]),
      "holy priest cannot use a shield")

--------------------------------------------------------------------
-- Weapon shape and pools
--
-- The hand-written half. Its failure mode is a spec quietly missing from
-- the table, which makes both weapon rows empty for that spec only -- so
-- coverage is checked first, and against SpecGear rather than a literal
-- count, because SpecGear is itself derived and will grow on its own.
--------------------------------------------------------------------
local MAIN, OFF = "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND"

local shapeless = {}
for specID in pairs(ns.SpecGear) do
    if not ns.WeaponShape(specID) then shapeless[#shapeless + 1] = specID end
end
checkEqual(#shapeless, 0,
           "every spec has a weapon shape (missing: "
           .. table.concat(shapeless, ",") .. ")")

local ambiguous = 0
for specID in pairs(ns.SpecGear) do
    if ns.WeaponShapeAmbiguous(specID) then ambiguous = ambiguous + 1 end
end
checkEqual(ambiguous, 21,
           "21 specs have coupled weapon rows and get the two-hand / "
           .. "one-hand switch (4 dual-or-2H, 15 offhand-or-2H, 2 shaman)")

-- A hand that holds nothing must answer nil, NOT an empty pool: the panel
-- prints a different message for each, and conflating them tells a
-- two-hand spec that the season dropped no off-hands.
check(ns.WeaponPool(71, OFF, nil) == nil, "arms warrior has no off hand")
check(ns.WeaponPool(253, OFF, nil) == nil, "beast mastery has no off hand")
check(ns.WeaponPool(251, OFF, "twohand") == nil,
      "frost death knight two-handed has no off hand")
check(ns.WeaponPool(251, OFF, "onehand") ~= nil,
      "frost death knight one-handed does have an off hand")
check(ns.WeaponPool(261, OFF, "twohand") ~= nil,
      "an unambiguous dual-wield spec ignores the mode entirely")

--------------------------------------------------------------------
-- Weapon candidates end to end
--------------------------------------------------------------------
local function weaponsIn(specID, slotKey, mode)
    local list = ns.SlotCandidates(slotKey, specID, nil, "mythic", mode)
    local locs, subs, n = {}, {}, 0
    for _, row in ipairs(list or {}) do
        local _, _, _, loc, _, classID, sub = GetItemInfoInstant(row.id)
        locs[loc] = true
        if classID == 2 then subs[sub] = true end
        n = n + 1
    end
    return n, locs, subs
end

-- Reverse anchors first: every assertion below is about something being
-- ABSENT, and absence proves nothing from an empty list.
local n = weaponsIn(261, MAIN); check(n > 0, "subtlety has main hand candidates")
n = weaponsIn(253, MAIN); check(n > 0, "beast mastery has main hand candidates")
n = weaponsIn(64, MAIN, "twohand")
check(n > 0, "frost mage two-handed has main hand candidates")

local _, locs, subs = weaponsIn(261, MAIN)
check(not locs.INVTYPE_2HWEAPON, "a dual-wield spec is never shown a two-hander")
check(not locs.INVTYPE_RANGED and not locs.INVTYPE_RANGEDRIGHT,
      "rogues are not shown bows even though the class has the proficiency "
      .. "-- a ranged weapon costs them the off hand, so nobody equips one")
check(not subs[9], "rogues are not shown warglaives (proficiency filter bites)")

_, locs, subs = weaponsIn(577, MAIN)
check(subs[9], "havoc IS shown warglaives -- the same filter, other way up")

_, locs = weaponsIn(253, MAIN)
check(locs.INVTYPE_RANGED or locs.INVTYPE_RANGEDRIGHT,
      "beast mastery is shown ranged weapons")
check(not locs.INVTYPE_WEAPON and not locs.INVTYPE_2HWEAPON,
      "beast mastery is shown no melee weapons at all")

_, locs, subs = weaponsIn(64, MAIN, "twohand")
check(locs.INVTYPE_2HWEAPON, "frost mage two-handed sees two-handers")
check(not locs.INVTYPE_WEAPON, "frost mage two-handed sees no one-handers")
_, locs = weaponsIn(64, MAIN, "onehand")
check(locs.INVTYPE_WEAPON, "frost mage one-handed sees one-handers")
check(not locs.INVTYPE_2HWEAPON,
      "frost mage one-handed sees no two-handers -- this is the whole point "
      .. "of the switch: the two rows can never describe an impossible pair")

_, locs = weaponsIn(64, OFF, "onehand")
check(locs.INVTYPE_HOLDABLE, "frost mage one-handed off hand holds an item")
check(not locs.INVTYPE_SHIELD, "mages get no shields")

-- Shields are usable by Strength AND Intellect plate/mail, and the game
-- writes that as two separate primary-stat entries rather than one hybrid
-- id. The generator used to keep only the first, so every shield came out
-- Strength and holy paladins saw an empty off-hand row -- a filter doing
-- exactly what it was told, on data that had already lost the answer.
-- The Strength side is the reverse anchor: if BOTH went to zero the fix
-- would be "primary filtering turned off", which is not a fix.
local strShields = weaponsIn(73, OFF, "onehand")
local intShields = weaponsIn(65, OFF, "onehand")
check(strShields > 0, "protection warrior has shield candidates")
check(intShields > 0,
      "holy paladin has shield candidates too -- Intellect users must not "
      .. "lose shields to a multi-entry primary stat being read as one")

_, locs, subs = weaponsIn(269, MAIN, "twohand")
check(subs[6] or subs[10],
      "windwalker two-handed sees polearms or staves, its only 2H options")
check(not subs[8] and not subs[1],
      "windwalker sees no two-handed swords or axes -- monks cannot use them")

--------------------------------------------------------------------
-- Slot button unit resolution
--
-- The side panel attaches the literal "player" to a slot button; the
-- inspect panel attaches a RESOLVER FUNCTION, so the unit is read fresh
-- on every click (InspectFrame.unit is a token that follows the target).
-- That resolver answers nil whenever the current unit is not
-- inspectable, and the battleground case reaches it directly: inspect
-- window still open, target switched to a hostile player, click a slot.
--
-- Written as `type(u) == "function" and u() or u`, a nil answer falls
-- through the `or` and yields the FUNCTION ITSELF, which then travels on
-- in place of a unit token. Every secret-value guard in the addon is
-- blind to this -- the value is not secret, it is simply not a unit.
--------------------------------------------------------------------
loadAddonFile("GearPanel.lua")

checkEqual(ns.ResolveSlotUnit("player"), "player",
           "a literal unit token passes through unchanged")
checkEqual(ns.ResolveSlotUnit(function() return "target" end), "target",
           "a resolver that names a unit resolves to that unit")
checkEqual(ns.ResolveSlotUnit(function() return nil end), nil,
           "a resolver that cannot name a unit resolves to nil, NOT to "
           .. "the resolver itself -- this is the battleground path")
checkEqual(ns.ResolveSlotUnit(nil), nil,
           "no unit at all resolves to nil")
checkEqual(ns.ResolveSlotUnit(false), nil,
           "a non-string unit resolves to nil")

-- Same rule at the shared spec entry point, loaded into its own
-- namespace so the StatPriorityOrder stub above is not overwritten.
-- ns.InspectSpecID is the single door for every non-player spec lookup
-- (TargetInfo included), so the guard belongs there too and not only at
-- the one call site that was found to need it.
do
    local specNS = { Config = { STAT_PRIORITY_FEATURE_ENABLED = true } }
    -- The client API has to be stubbed or this whole block is vacuous:
    -- with no C_SpecializationInfo present InspectSpecID returns nil for
    -- every input, guard or no guard, and the checks below would pass
    -- while proving nothing. sawBadUnit is the live assertion -- it is
    -- what flips when the type guard is removed.
    local sawBadUnit = false
    -- Nothing offline is ever a secret value; this only stands in for the
    -- client global so the real guard chain can run to completion.
    _G.issecretvalue = function() return false end
    _G.C_SpecializationInfo = {
        GetInspectSpecialization = function(unit)
            if type(unit) ~= "string" then sawBadUnit = true return nil end
            return 258
        end,
    }
    assert(loadfile("StatPriority.lua"))("DodoInspect", specNS)

    checkEqual(specNS.InspectSpecID("target"), 258,
               "InspectSpecID answers for a real unit token -- this is the "
               .. "reverse assertion proving the stub is actually reached")
    checkEqual(specNS.InspectSpecID(function() return nil end), nil,
               "InspectSpecID rejects a resolver function")
    checkEqual(specNS.InspectSpecID(0), nil,
               "InspectSpecID rejects a truthy non-string unit (0 is truthy "
               .. "in Lua, so `if not unit` never sees it)")
    check(not sawBadUnit,
          "InspectSpecID never hands a non-string unit to the client API")
end

--------------------------------------------------------------------
-- Trinkets: the one slot ordered by simulation instead of stat fit.
--
-- The interesting cases are both about ABSENCE. The source covers only
-- part of the spec list, and 33 of the 42 trinkets carry no secondary
-- stats -- so "no rank" and "no stats" are two different states that the
-- old code would have collapsed into one.
--------------------------------------------------------------------
loadAddonFile("Data/Trinkets.lua")

do
    -- Every spec in the generated table must exist in ns.SpecGear. The two
    -- lists are written by different tools; this is the only place they meet.
    local unknown = {}
    for specID in pairs(ns.TrinketRank) do
        if not ns.SpecGear[specID] then unknown[#unknown + 1] = specID end
    end
    checkEqual(#unknown, 0,
               "every spec id in Data/Trinkets.lua exists in ns.SpecGear")

    -- Covered vs uncovered must be distinguishable, and "uncovered" must be
    -- nil rather than an empty table -- the panel says different things.
    local covered = ns.TrinketOrder(258)          -- shadow priest
    check(covered ~= nil, "TrinketOrder answers for a covered spec (258)")
    check(ns.TrinketOrder(71) == nil,
          "TrinketOrder returns nil, not an empty table, for an uncovered "
          .. "spec (71 arms warrior has no simulation data)")
    check(ns.TrinketOrder(nil) == nil, "TrinketOrder tolerates a nil specID")

    -- Reverse assertion: without this, an empty ns.TrinketRank would pass
    -- every check above while proving nothing.
    local ranks = 0
    for _ in pairs(covered) do ranks = ranks + 1 end
    check(ranks > 10,
          "the covered spec actually carries a substantial order "
          .. "(guards against an empty or truncated data file)")

    local first = ns.TrinketRank[258][1]
    checkEqual(covered[first], 1, "rank 1 maps to the first listed item id")
end

do
    orderUnderTest = { "haste", "crit", "mastery", "versatility" }

    local ranked = ns.SlotCandidates("INVTYPE_TRINKET", 258, nil, "raid")
    check(ranked and #ranked > 0, "trinket row returns candidates for 258")

    -- Simulation order drives the list, and it must beat the 344 item level
    -- promotion: the simulation already compared each trinket at its own
    -- ceiling, so letting topItemLevel jump the queue prices those ten item
    -- levels twice. A/B: delete the simRank branch in the comparator and
    -- this flips to the 344 piece.
    checkEqual(ranked[1].id, ns.TrinketRank[258][1],
               "the sim's best trinket sorts first, ahead of any 344 piece")
    checkEqual(ranked[1].simRank, 1, "first row carries simRank 1")

    local lastRanked, firstUnranked
    for i = 1, #ranked do
        if ranked[i].simRank then lastRanked = i
        elseif not firstUnranked then firstUnranked = i end
    end
    check(not firstUnranked or firstUnranked > lastRanked,
          "trinkets the simulation did not cover sink below the ranked ones")

    -- Most trinkets have no secondary stats, so scoring by stat fit would
    -- flag nearly the whole list. Under simulation they are properly ranked.
    local statless, flagged = 0, 0
    for i = 1, #ranked do
        if ranked[i].score == nil then statless = statless + 1 end
        if ranked[i].unranked then flagged = flagged + 1 end
    end
    check(statless > flagged,
          "a statless trinket is still ranked -- 'unranked' on this row "
          .. "means the sim skipped it, not that it has no secondaries")
end

do
    -- An uncovered spec gets NOTHING, and the panel says why. The first
    -- version listed the trinkets with every row flagged; on a live holy
    -- priest that still read as a ranking, because a list of items under
    -- this panel's header is what a ranking looks like. There is no
    -- second-best order to fall back on here.
    orderUnderTest = { "haste", "crit", "mastery", "versatility" }
    local rows, unranked = ns.SlotCandidates("INVTYPE_TRINKET", 71, nil, "raid")
    check(rows ~= nil,
          "uncovered spec returns a list rather than nil (nil means 'cannot "
          .. "rank this slot at all' and prints a different message)")
    checkEqual(#rows, 0, "uncovered spec returns no trinket rows at all")
    checkEqual(unranked, 0, "and reports no unranked count for rows it never built")
end

do
    -- Regression from live use (holy priest, 2026-08-14). `unranked` was
    -- quietly driving three unrelated things: the sort, the stat column's
    -- dash, and whether the tooltip gets an upgrade bonus id. On armor the
    -- three coincided, so nothing caught the overload -- on trinkets it
    -- stripped the bonus id off every row and the tooltip rendered the bare
    -- item, showing a returning trinket's original item level instead of
    -- this season's ceiling.
    orderUnderTest = { "haste", "crit", "mastery", "versatility" }

    local rows = ns.SlotCandidates("INVTYPE_TRINKET", 258, nil, "raid")
    local offTrack, statless, statlessOnTrack = 0, 0, 0
    for i = 1, #rows do
        if rows[i].offTrack then offTrack = offTrack + 1 end
        if rows[i].statless then statless = statless + 1 end
        if rows[i].statless and not rows[i].offTrack then
            statlessOnTrack = statlessOnTrack + 1
        end
    end
    checkEqual(offTrack, 0,
               "no trinket is ever off-track -- every one drops this season, "
               .. "so its tooltip must carry an upgrade bonus id")
    check(statless > 0,
          "the pool really does contain statless trinkets (without this the "
          .. "check below would pass on an empty set)")
    checkEqual(statlessOnTrack, statless,
               "statless and off-track are independent on the trinket row")

    -- The other half of 'fix the class, not the case': armor must be
    -- untouched, where both flags still mean 'no secondary stats'.
    local head = ns.SlotCandidates("INVTYPE_HEAD", 258, nil, "raid")
    local drift = 0
    for i = 1, #head do
        if head[i].statless ~= (head[i].score == nil) then drift = drift + 1 end
        if head[i].offTrack ~= (head[i].score == nil) then drift = drift + 1 end
    end
    check(#head > 0, "the armor control set is not empty")
    checkEqual(drift, 0,
               "on armor both flags still track 'no secondary stats' exactly "
               .. "as before -- the trinket split changed nothing here")
end

--------------------------------------------------------------------
-- Mythic+ side panel data: ns.ChallengeMap + the card labels
--
-- Two tables that have to agree without either being able to see the
-- other. ns.ChallengeMap is DERIVED (gen_loot.py joins JournalInstance
-- to MapChallengeMode); the labels are the one HAND-WRITTEN thing in
-- this feature and they live in Locales.lua. Nothing else in the addon
-- reads both, so this is the only place the two ever meet.
--
-- The Chinese labels are checked against the names the CLIENT ships,
-- not against names typed out a second time here -- that would only
-- prove the two typings agree with each other. gen_loot.py writes them
-- to tools/fixture_dungeonnames.lua on every run.
--------------------------------------------------------------------

loadAddonFile("Locales.lua")
local officialNames = assert(loadfile("tools/fixture_dungeonnames.lua"))()

--------------------------------------------------------------------
-- Every locale carries every key
--
-- A string added to en and forgotten in the other three does not throw
-- and does not log: ns.L.whatever is nil, the caller prints "" and the
-- label is simply absent. On a Chinese client that is a blank control
-- with no way to learn what it was for -- the failure mode where the
-- normal state and the broken one look identical.
--
-- Two keys really are per-locale, and they are named rather than
-- pattern-matched so the exemption cannot quietly widen to cover a
-- fourth. The reverse check below fails if either stops being needed,
-- because an exemption nobody removes is how this kind of guard turns
-- into a green light for the thing it was meant to catch.
--------------------------------------------------------------------

do
    local PER_LOCALE = {
        -- cn overrides the acronyms; every other locale falls through to
        -- the shared ns.DungeonShort on purpose.
        dungeonShort = true,
        -- Only cn needs a font the Latin client font cannot supply.
        font = true,
    }

    local locales = ns.LocaleOrder
    check(type(locales) == "table" and #locales >= 2,
          "there are at least two locales to compare")

    local everyKey = {}
    for _, key in ipairs(locales) do
        for name in pairs(ns.Locales[key]) do everyKey[name] = true end
    end
    local total = 0
    for _ in pairs(everyKey) do total = total + 1 end
    -- Reverse assertion: with an empty key set every loop below passes
    -- while comparing nothing at all.
    check(total > 20, "the locale tables actually carry keys (got "
          .. total .. ")")

    local missing, mistyped, exemptStillNeeded = 0, 0, {}
    for name in pairs(everyKey) do
        local shape
        for _, key in ipairs(locales) do
            local value = ns.Locales[key][name]
            if value == nil then
                if PER_LOCALE[name] then
                    exemptStillNeeded[name] = true
                else
                    missing = missing + 1
                    print("FAIL  locale '" .. key .. "' is missing '"
                          .. name .. "'")
                end
            else
                -- A key that is a string in one locale and a table in
                -- another reaches its caller as the wrong kind of thing,
                -- which is a crash rather than a blank.
                shape = shape or type(value)
                if type(value) ~= shape then
                    mistyped = mistyped + 1
                    print("FAIL  locale '" .. key .. "' has '" .. name
                          .. "' as " .. type(value) .. ", not " .. shape)
                end
            end
        end
    end
    checkEqual(missing, 0, "every locale carries every shared key")
    checkEqual(mistyped, 0, "a shared key has the same type in every locale")

    for name in pairs(PER_LOCALE) do
        check(exemptStillNeeded[name], "the per-locale exemption for '"
              .. name .. "' is still needed -- it is now present in every "
              .. "locale, so remove it rather than leaving a hole open")
    end
end

do
    local dungeons = {}
    for instanceID in pairs(ns.LootMeta.dungeons) do
        dungeons[#dungeons + 1] = instanceID
    end
    table.sort(dungeons)

    -- Reverse assertion first: every loop below runs over this list, so
    -- an empty one would let the whole section pass while proving
    -- nothing at all.
    checkEqual(#dungeons, 8,
               "the season has 8 Mythic+ dungeons to build cards from")

    -- Coverage, both directions. A dungeon with no challenge map id gets
    -- no card; a challenge map id with no dungeon is a stale row the
    -- generator should have dropped when the pool changed.
    local mapped, seenMapID = 0, {}
    for _, instanceID in ipairs(dungeons) do
        local mapID = ns.ChallengeMap and ns.ChallengeMap[instanceID]
        check(type(mapID) == "number",
              "dungeon " .. instanceID .. " has a challengeMapID")
        if type(mapID) == "number" then
            mapped = mapped + 1
            check(seenMapID[mapID] == nil,
                  "challengeMapID " .. mapID .. " is claimed by only one "
                  .. "dungeon (two cards on one map would render twice)")
            seenMapID[mapID] = instanceID
        end
    end
    checkEqual(mapped, #dungeons, "every dungeon resolved a challenge map")

    local extra = {}
    for instanceID in pairs(ns.ChallengeMap or {}) do
        if not ns.LootMeta.dungeons[instanceID] then
            extra[#extra + 1] = instanceID
        end
    end
    checkEqual(#extra, 0,
               "ChallengeMap carries no instance outside the dungeon pool "
               .. "(stale: " .. table.concat(extra, ",") .. ")")

    -- Labels. The budget is the one already stated at the top of
    -- Locales.lua for bag tags: 4 Latin characters, 2 CJK. Counted in
    -- CODE POINTS, not bytes -- one Chinese character is three bytes, so
    -- a byte count would wave through a six-character Chinese label.
    local function labelBudget(label)
        local codepoints = utf8.len(label)
        if not codepoints then return nil end -- not valid UTF-8
        return codepoints, (#label > codepoints) and 2 or 4
    end

    local seenLabel = {}
    for _, instanceID in ipairs(dungeons) do
        local label = ns.DungeonShort and ns.DungeonShort[instanceID]
        check(type(label) == "string" and #label > 0,
              "dungeon " .. instanceID .. " has a default card label")
        if type(label) == "string" then
            local size, budget = labelBudget(label)
            check(size ~= nil and size <= budget,
                  string.format("label %q for %d fits the card (%s of %d)",
                                label, instanceID, tostring(size), budget))
            check(seenLabel[label] == nil,
                  string.format("label %q belongs to one dungeon only -- "
                                .. "two cards reading the same word cannot "
                                .. "be told apart", label))
            seenLabel[label] = instanceID
        end
    end

    -- The Chinese override is the half with a checkable rule: every
    -- label must be a real substring of the dungeon official name, so a
    -- player reads a shortening rather than something we invented.
    -- (UTF-8 is self-synchronising, so a byte-level find between two
    -- valid strings can only land on a character boundary.)
    local cn = ns.Locales and ns.Locales.cn and ns.Locales.cn.dungeonShort
    check(cn ~= nil, "the cn locale carries its own card labels")

    local checkedCN = 0
    for _, instanceID in ipairs(dungeons) do
        local label = cn and cn[instanceID]
        local official = officialNames.zhCN[instanceID]
        check(type(label) == "string" and #label > 0,
              "dungeon " .. instanceID .. " has a Chinese card label")
        check(type(official) == "string" and #official > 0,
              "dungeon " .. instanceID .. " has an official Chinese name in "
              .. "the fixture (rerun tools/gen_loot.py)")
        if type(label) == "string" and type(official) == "string" then
            checkedCN = checkedCN + 1
            local size, budget = labelBudget(label)
            check(size ~= nil and size <= budget,
                  string.format("cn label %q for %d fits the card",
                                label, instanceID))
            check(string.find(official, label, 1, true) ~= nil,
                  string.format("cn label %q really is part of the official "
                                .. "name %q", label, official))
        end
    end
    checkEqual(checkedCN, #dungeons,
               "the substring rule was actually applied to every dungeon")
end

--------------------------------------------------------------------
-- Loot browser card list: ns.LootCardList (LootSource.lua)
--
-- The left column of the browser is DERIVED from Data/Loot.lua rather
-- than written out by hand, so what is checked here is that the
-- derivation agrees with the loot table in both directions and lands in
-- a TOTAL, stable order. pairs() is unordered: without the sort the
-- eight cards would reshuffle between two openings of the window, which
-- is a bug nobody can reproduce on demand and which no screenshot shows.
--
-- Properties, not a second copy of the algorithm: asserting the order
-- against an expected list computed the same way here would only prove
-- the two typings agree with each other.
--------------------------------------------------------------------

loadAddonFile("LootSource.lua")

do
    local mythic = ns.LootCardList("mythic")
    local raid = ns.LootCardList("raid")

    check(type(mythic) == "table", "the card list answers for mythic")
    check(type(raid) == "table", "the card list answers for raid")

    -- Reverse assertions first. Every loop below runs over these, so
    -- empty lists would let the whole section pass proving nothing.
    checkEqual(#mythic, 8, "mythic mode offers one card per dungeon")
    checkEqual(#raid, 9, "raid mode offers one card per boss that drops gear")

    -- An unknown mode must not answer with nothing. The window always
    -- has a mode; a nil list there would draw an empty left column and
    -- read as "this season has no dungeons".
    checkEqual(#ns.LootCardList("bogus"), #mythic,
               "an unrecognised mode falls back to mythic, not to empty")
    checkEqual(#ns.LootCardList(), #mythic,
               "a missing mode falls back to mythic, not to empty")

    -- Mythic: exactly the dungeon pool, each with the challenge map id
    -- the cards need for their icon, and no grouping (a flat list).
    local seenKey, dungeonSeen = {}, {}
    for _, card in ipairs(mythic) do
        checkEqual(card.kind, "dungeon", "mythic cards are dungeons")
        check(ns.LootMeta.dungeons[card.instanceID] == true,
              "card " .. tostring(card.instanceID) .. " is in the dungeon pool")
        check(type(card.mapID) == "number",
              "dungeon " .. tostring(card.instanceID) .. " carries a challengeMapID")
        check(card.groupFirst ~= true,
              "dungeon cards carry no group heading -- there is only one group")
        check(seenKey[card.key] == nil,
              "card key " .. tostring(card.key) .. " is used once")
        seenKey[card.key] = true
        dungeonSeen[card.instanceID] = true
    end
    local missingDungeon = 0
    for instanceID in pairs(ns.LootMeta.dungeons) do
        if not dungeonSeen[instanceID] then missingDungeon = missingDungeon + 1 end
    end
    checkEqual(missingDungeon, 0, "every dungeon in the pool got a card")

    -- Raid: one card per (instance, boss) pair that really drops
    -- something, counted straight off the loot table.
    local pairsInData, pairCount = {}, 0
    for _, entry in pairs(ns.LootData) do
        if ns.LootMeta.raids[entry[1]] then
            local key = entry[1] .. ":" .. entry[2]
            if not pairsInData[key] then
                pairsInData[key] = 0
                pairCount = pairCount + 1
            end
            pairsInData[key] = pairsInData[key] + 1
        end
    end
    check(pairCount > 1, "the raid pool has more than one boss to order")
    checkEqual(#raid, pairCount,
               "raid cards and raid bosses-with-loot are the same set size")

    local seenPair = {}
    for _, card in ipairs(raid) do
        checkEqual(card.kind, "boss", "raid cards are bosses")
        check(ns.LootMeta.raids[card.instanceID] == true,
              "boss card " .. tostring(card.encounterID) .. " belongs to a raid")
        local key = card.instanceID .. ":" .. card.encounterID
        check(seenPair[key] == nil,
              "boss " .. tostring(card.encounterID) .. " gets exactly one card")
        seenPair[key] = true
        -- The documented boundary: a boss with nothing in our table gets
        -- no card. Stated as an assertion so "9 bosses" cannot quietly
        -- start meaning "9 bosses in the raid" after a rewrite.
        check((pairsInData[key] or 0) > 0,
              "boss " .. tostring(card.encounterID) .. " actually drops something")
        check(seenKey[card.key] == nil,
              "card key " .. tostring(card.key) .. " does not collide with a dungeon key")
    end

    -- TOTAL order, asserted as a property. Cards must never step
    -- backwards in (instanceID, position) -- that is what makes the list
    -- the same on every opening.
    local ordered, lastInstance, lastPos = true, nil, nil
    for _, card in ipairs(raid) do
        if lastInstance then
            if card.instanceID < lastInstance then
                ordered = false
            elseif card.instanceID == lastInstance and card.position < lastPos then
                ordered = false
            end
        end
        lastInstance, lastPos = card.instanceID, card.position
    end
    check(ordered, "raid cards run in a fixed instance-then-position order")

    -- Group headings sit exactly on instance boundaries: one per raid,
    -- on its first boss and nowhere else.
    local instanceCount, groupCount, seenInstance = 0, 0, {}
    lastInstance = nil
    for _, card in ipairs(raid) do
        if not seenInstance[card.instanceID] then
            seenInstance[card.instanceID] = true
            instanceCount = instanceCount + 1
        end
        if card.groupFirst then groupCount = groupCount + 1 end
        check((card.groupFirst == true) == (card.instanceID ~= lastInstance),
              "boss " .. tostring(card.encounterID)
              .. " carries a heading only when its raid changes")
        lastInstance = card.instanceID
    end
    check(instanceCount > 1,
          "the raid pool spans more than one instance -- otherwise the "
          .. "grouping above is never exercised and proves nothing")
    checkEqual(groupCount, instanceCount, "one heading per raid, no more")
end

--------------------------------------------------------------------
-- Loot browser right column: ns.SourceCandidates (GearRank.lua)
--------------------------------------------------------------------
-- The sibling of SlotCandidates that keys on a SOURCE instead of a slot.
-- Every fixture below is FOUND in the season data rather than written
-- down, and each search asserts that it found something -- a guard that
-- quietly matches nothing is the one shape that can never go red.
do
    local MELEE, CASTER = 72, 258 -- fury (Plate/STR), shadow (Cloth/INT)
    orderUnderTest = { "crit", "haste", "mastery", "versatility" }

    local dungeon = ns.LootCardList("mythic")[1]
    local rows = ns.SourceCandidates(dungeon, MELEE, nil, "mythic")
    check(rows and #rows > 0, "a dungeon card returns candidates at all")
    local strayInstance = 0
    for _, row in ipairs(rows or {}) do
        if row.entry[1] ~= dungeon.instanceID then
            strayInstance = strayInstance + 1
        end
    end
    checkEqual(strayInstance, 0,
               "a dungeon card lists only items from that dungeon")

    -- A boss card must narrow to its own encounter. Picked from a raid
    -- with SIBLINGS: in the one-boss raid "filtered by boss" and
    -- "filtered by instance" give the same answer, so it proves nothing.
    local raidCards, multiBoss = ns.LootCardList("raid"), nil
    for _, card in ipairs(raidCards) do
        local siblings = 0
        for _, other in ipairs(raidCards) do
            if other.instanceID == card.instanceID then
                siblings = siblings + 1
            end
        end
        if siblings > 1 then multiBoss = card break end
    end
    check(multiBoss ~= nil,
          "found a raid with more than one boss to test the boss filter")
    if multiBoss then
        local bossRows = ns.SourceCandidates(multiBoss, MELEE, nil, "raid")
        check(bossRows and #bossRows > 0, "a boss card returns candidates")
        local strayEncounter, wholeRaid = 0, 0
        for _, row in ipairs(bossRows or {}) do
            if row.entry[2] ~= multiBoss.encounterID then
                strayEncounter = strayEncounter + 1
            end
        end
        for _, entry in pairs(ns.LootData) do
            if entry[1] == multiBoss.instanceID then
                wholeRaid = wholeRaid + 1
            end
        end
        checkEqual(strayEncounter, 0,
                   "a boss card lists only that boss's drops")
        check(#(bossRows or {}) < wholeRaid,
              "a boss card lists FEWER items than its whole raid -- "
              .. "otherwise it is filtering on the instance by mistake")
    end
end

-- unranked / statless / offTrack stay three separate answers.
--
-- This panel is the SECOND consumer of those fields. The first one
-- carried all three on a single `unranked` flag until 1.12.0, where the
-- trinket simulation gave it a fourth meaning and every uncovered
-- trinket lost its upgrade bonus id -- the tooltip then rendered the
-- bare item, which for a returning trinket understates it by hundreds
-- of item levels. SlotCandidates asks "is this the trinket ROW"; there
-- are no rows here, so this asks the item's equip location instead, and
-- these checks are what keep the two answers the same shape.
do
    local SPECS = { 72, 258 }
    orderUnderTest = { "crit", "haste", "mastery", "versatility" }

    local statlessTrinkets, statlessOthers = 0, 0
    local trinketOffTrack, otherOnTrack = 0, 0
    for _, mode in ipairs({ "mythic", "raid" }) do
        for _, card in ipairs(ns.LootCardList(mode)) do
            for _, spec in ipairs(SPECS) do
                for _, row in ipairs(ns.SourceCandidates(card, spec, nil, mode) or {}) do
                    checkEqual(row.statless, not ns.HasSecondaries(row.entry),
                               "statless answers the ITEM, not the ranking")
                    if row.statless then
                        if row.equipLoc == ns.TRINKET_SLOT then
                            statlessTrinkets = statlessTrinkets + 1
                            if row.offTrack then
                                trinketOffTrack = trinketOffTrack + 1
                            end
                        else
                            statlessOthers = statlessOthers + 1
                            if not row.offTrack then
                                otherOnTrack = otherOnTrack + 1
                            end
                        end
                    end
                end
            end
        end
    end

    check(statlessTrinkets > 0,
          "the season really does contain trinkets with no secondaries "
          .. "-- without one the next two checks prove nothing")
    check(statlessOthers > 0,
          "the season really does contain non-trinkets with no "
          .. "secondaries (the returning azerite pieces)")
    checkEqual(trinketOffTrack, 0,
               "a trinket with no secondaries is on this season's track "
               .. "and MUST keep its upgrade bonus id (the 1.12.0 bug)")
    checkEqual(otherOnTrack, 0,
               "a non-trinket with no secondaries is off-track and must "
               .. "lose its bonus id, or its tooltip invents a ceiling")
end

-- The primary-stat filter runs on every item, not just armor and
-- weapons. SlotCandidates leans on simulation coverage to keep unusable
-- trinkets off the trinket row; there is no simulation here to lean on.
do
    orderUnderTest = { "crit", "haste", "mastery", "versatility" }
    local CASTER = 258 -- shadow priest: Cloth / INT, cannot use Strength
    local strInPool, strShown = 0, 0
    for _, card in ipairs(ns.LootCardList("mythic")) do
        for _, entry in pairs(ns.LootData) do
            if entry[1] == card.instanceID and entry[4] == "STR" then
                strInPool = strInPool + 1
            end
        end
        for _, row in ipairs(ns.SourceCandidates(card, CASTER, nil, "mythic") or {}) do
            if row.entry[4] == "STR" then strShown = strShown + 1 end
        end
    end
    check(strInPool > 0,
          "the dungeons really do drop Strength items -- otherwise the "
          .. "filter below is being asked a question with no wrong answer")
    checkEqual(strShown, 0,
               "a Strength item is never offered to an Intellect spec")
end

-- No stat priority is not the same as no drops.
do
    local saved = orderUnderTest
    orderUnderTest = nil
    local card = ns.LootCardList("mythic")[1]
    local rows, _, ranked = ns.SourceCandidates(card, 72, nil, "mythic")
    check(rows and #rows > 0,
          "with no stat priority the drops are still LISTED -- an empty "
          .. "right column would read as 'this dungeon drops nothing'")
    checkEqual(ranked, false,
               "and it reports that it could not rank them, so the "
               .. "display knows not to number the rows")
    local allStatless = true
    for _, row in ipairs(rows or {}) do
        if not row.statless then allStatless = false break end
    end
    checkEqual(allStatless, false,
               "statless must still reflect the ITEMS -- reading it off "
               .. "the missing score would dash out every row")
    orderUnderTest = saved
end

-- The weapon axis is the union of both hands AND both modes.
--
-- Checked per SHAPE and over every spec, not on the first ambiguous one
-- found: an earlier version asserted only "2H and 1H are both there",
-- which a dual-wield spec satisfies from its main hand alone -- so
-- dropping the off hand entirely left the guard green. What the off
-- hand actually contributes is the shield and held-item half, and only
-- a shield-or-2H spec can show that.
do
    local WANT = {
        DUAL_OR_2H    = { "INVTYPE_2HWEAPON", "INVTYPE_WEAPON" },
        SHIELD_OR_2H  = { "INVTYPE_2HWEAPON", "INVTYPE_SHIELD" },
        OFFHAND_OR_2H = { "INVTYPE_2HWEAPON", "INVTYPE_HOLDABLE" },
        ONEHAND_SHIELD = { "INVTYPE_WEAPON", "INVTYPE_SHIELD" },
        DUAL_1H       = { "INVTYPE_WEAPON" },
        TWOHAND       = { "INVTYPE_2HWEAPON" },
        DUAL_2H       = { "INVTYPE_2HWEAPON" },
        RANGED        = { "INVTYPE_RANGED" },
    }
    local seenShapes, checkedSpecs = {}, 0
    for specID in pairs(ns.SpecGear) do
        local shape = ns.WeaponShape(specID)
        local want = shape and WANT[shape]
        if want then
            seenShapes[shape] = true
            checkedSpecs = checkedSpecs + 1
            local locs = ns.SpecWeaponLocations(specID) or {}
            for _, loc in ipairs(want) do
                check(locs[loc] == true, string.format(
                      "spec %d (%s) must see %s in a source list",
                      specID, shape, loc))
            end
        end
    end
    check(checkedSpecs > 30,
          "the weapon union was checked across the whole spec table")
    -- Without this the loop above could pass by covering only the easy
    -- shapes, which is exactly how the first version of this check
    -- missed the off hand.
    check(seenShapes.SHIELD_OR_2H or seenShapes.ONEHAND_SHIELD,
          "at least one shield-carrying shape was covered -- otherwise "
          .. "nothing here depends on the off hand at all")
end

-- ...and SourceCandidates actually USES that union.
--
-- The checks above prove ns.SpecWeaponLocations is right. They say
-- nothing about whether the candidate list calls it -- swapping it for a
-- single ns.WeaponPool call left them all green, because the seam
-- between "the helper is correct" and "the caller uses the helper" had
-- no assertion on either side of it. This walks it, through the real
-- entry point, and only reports what the season data can support.
do
    orderUnderTest = { "crit", "haste", "mastery", "versatility" }
    local shapesWanted = { SHIELD_OR_2H = "INVTYPE_SHIELD",
                           OFFHAND_OR_2H = "INVTYPE_HOLDABLE" }
    local tested = 0
    for specID in pairs(ns.SpecGear) do
        local shape = ns.WeaponShape(specID)
        local offHandLoc = shape and shapesWanted[shape]
        if offHandLoc then
            -- Does the season drop both halves for this spec at all? If
            -- not, this spec cannot answer the question and is skipped
            -- rather than passed -- `tested` is what keeps the whole
            -- block from silently covering nothing.
            local sawTwoHand, sawOffHand = false, false
            for _, mode in ipairs({ "mythic", "raid" }) do
                for _, card in ipairs(ns.LootCardList(mode)) do
                    for _, row in ipairs(ns.SourceCandidates(card, specID, nil, mode) or {}) do
                        if row.equipLoc == "INVTYPE_2HWEAPON" then sawTwoHand = true end
                        if row.equipLoc == offHandLoc then sawOffHand = true end
                    end
                end
            end
            if sawTwoHand then
                tested = tested + 1
                check(sawOffHand, string.format(
                      "spec %d (%s) is offered two-handers, so its %s "
                      .. "must be listed too -- one hand's pool is not "
                      .. "the whole answer here", specID, shape, offHandLoc))
            end
        end
    end
    check(tested > 0,
          "at least one either-way spec is offered both a two-hander "
          .. "and an off-hand item somewhere this season -- without "
          .. "that this block proves nothing")
end

-- Nothing is offered that this spec's shape does not hold.
--
-- The direction the block above cannot see. That one asks "is anything
-- MISSING"; this asks "is anything EXTRA", and extra is what actually
-- shipped a bug: shields and held items are filed as ARMOR by the
-- client, so they skipped the weapon gate entirely and were judged on
-- proficiency -- which asks CAN, not SHOULD. Every paladin CAN hold a
-- shield, so a two-hand retribution paladin was offered one, and so was
-- a fury warrior. Found 2026-08-25 by dumping the per-spec equip
-- locations, not by any assertion, which is why this one exists.
do
    orderUnderTest = { "crit", "haste", "mastery", "versatility" }
    local OFF_HAND_ARMOR = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }
    local inspected, stray, firstStray = 0, 0, nil
    local twoHandShields = 0
    for specID in pairs(ns.SpecGear) do
        local shape = ns.WeaponShape(specID)
        local allowed = ns.SpecWeaponLocations(specID) or {}
        for _, mode in ipairs({ "mythic", "raid" }) do
            for _, card in ipairs(ns.LootCardList(mode)) do
                for _, row in ipairs(ns.SourceCandidates(card, specID, nil, mode) or {}) do
                    local loc = row.equipLoc
                    local isWeaponish = loc and (loc:find("WEAPON")
                                        or loc:find("RANGED")
                                        or OFF_HAND_ARMOR[loc])
                    if isWeaponish then
                        inspected = inspected + 1
                        if not allowed[loc] then
                            stray = stray + 1
                            firstStray = firstStray or string.format(
                                "spec %d (%s) was offered %s",
                                specID, tostring(shape), loc)
                        end
                        -- The concrete bug, named. A general invariant
                        -- can drift into vacuity; this one cannot.
                        if OFF_HAND_ARMOR[loc]
                           and (shape == "TWOHAND" or shape == "DUAL_2H") then
                            twoHandShields = twoHandShields + 1
                        end
                    end
                end
            end
        end
    end
    check(inspected > 200,
          "weapon-shaped rows were actually inspected -- a zero here "
          .. "would make both checks below pass for free")
    checkEqual(stray, 0, "no spec is offered a weapon its shape does not "
               .. "hold" .. (firstStray and (" (" .. firstStray .. ")") or ""))
    checkEqual(twoHandShields, 0,
               "a two-hander-only spec is never offered a shield or a "
               .. "held item, however proficient its class is")
end

-- Nobody is offered another class's armor.
--
-- This filter had no assertion at all until 2026-08-25: seeding
-- `keep = true` on the armor-type line left BOTH suites green while a
-- shadow priest's Kings' Rest list went from 13 rows to 34, 21 of them
-- leather, mail and plate. ns.PrimaryFits cannot cover for it -- this
-- tier tags plate SI and leather AI, so a cloth Intellect spec "fits"
-- a plate piece on the primary-stat axis and armor type is the only
-- thing standing between them.
do
    orderUnderTest = { "crit", "haste", "mastery", "versatility" }
    local SUBCLASS = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }
    -- The slots the armor-type rule applies to. Cloaks are deliberately
    -- absent: the client files them under Cloth for everyone.
    local TYPED = {
        INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true,
        INVTYPE_ROBE = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
        INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true,
    }
    local inspected, wrong, example = 0, 0, nil
    for specID, spec in pairs(ns.SpecGear) do
        local want = spec[1]
        for _, mode in ipairs({ "mythic", "raid" }) do
            for _, card in ipairs(ns.LootCardList(mode)) do
                for _, row in ipairs(ns.SourceCandidates(card, specID, nil, mode) or {}) do
                    local shape = shapes[row.id]
                    local sub = shape and SUBCLASS[shape[3]]
                    if TYPED[row.equipLoc] and shape and shape[2] == 4 and sub then
                        inspected = inspected + 1
                        if sub ~= want then
                            wrong = wrong + 1
                            example = example or string.format(
                                "spec %d wants %s but was offered %s item %d",
                                specID, want, sub, row.id)
                        end
                    end
                end
            end
        end
    end
    check(inspected > 200, "armor rows were actually inspected (got "
          .. inspected .. ") -- a zero would pass the next check for free")
    checkEqual(wrong, 0, "no spec is offered another armor type"
               .. (example and (" (" .. example .. ")") or ""))
end

-- Trinkets lead the list, and are ordered among themselves.
--
-- Owner's call 2026-08-25. It reverses what the stat sort does on its
-- own: 33 of the season's 42 trinkets carry no secondaries, so they
-- score nil and sink to the bottom -- burying the drop people open a
-- boss card to look for.
do
    orderUnderTest = { "crit", "haste", "mastery", "versatility" }
    local mixed, outOfBlock, simInversions = 0, 0, 0
    for specID in pairs(ns.SpecGear) do
        for _, mode in ipairs({ "mythic", "raid" }) do
            for _, card in ipairs(ns.LootCardList(mode)) do
                local rows = ns.SourceCandidates(card, specID, nil, mode) or {}
                local trinkets, others, seenOther = 0, 0, false
                local lastRank
                for _, row in ipairs(rows) do
                    if row.equipLoc == ns.TRINKET_SLOT then
                        trinkets = trinkets + 1
                        -- A trinket AFTER a non-trinket is the failure.
                        if seenOther then outOfBlock = outOfBlock + 1 end
                        if row.simRank and lastRank and row.simRank < lastRank then
                            simInversions = simInversions + 1
                        end
                        lastRank = row.simRank or lastRank
                    else
                        others = others + 1
                        seenOther = true
                    end
                end
                -- Only a list holding BOTH kinds can answer the question.
                if trinkets > 0 and others > 0 then mixed = mixed + 1 end
            end
        end
    end
    check(mixed > 100, "lists holding both a trinket and something else "
          .. "were actually seen (got " .. mixed .. ") -- a zero would "
          .. "make the next check pass for free")
    checkEqual(outOfBlock, 0, "every trinket sorts ahead of every "
               .. "non-trinket in the same list")
    checkEqual(simInversions, 0, "inside the trinket block the "
               .. "simulation order is respected")
end

print(string.format("\n%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
