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
local weights = ns.StatWeights({ "crit", "haste", "mastery", "versatility" })
checkEqual(weights.crit, 1.00, "flat order: first stat weight")
checkEqual(weights.haste, 0.70, "flat order: second stat weight")

weights = ns.StatWeights({ { "crit", "haste" }, "mastery", "versatility" })
checkEqual(weights.crit, 1.00, "tie group: both members share first weight")
checkEqual(weights.haste, 1.00, "tie group: second member shares it too")
checkEqual(weights.mastery, 0.45, "tie group consumes two positions")

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

print(string.format("\n%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
