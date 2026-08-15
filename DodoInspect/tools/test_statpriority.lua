-- DodoInspect - tools/test_statpriority.lua
-- Offline test for the player-authored stat priority overrides. Run
-- from the addon folder:
--
--     lua tools/test_statpriority.lua
--
-- Not shipped. Covers the parts of StatPriorityConfig.lua and
-- StatPriority.lua that are pure logic: order shape, seeding, the
-- saved-variables round trip, percent/rating conversion, and -- the
-- one that actually matters -- which answer Resolve hands back when a
-- player override and the shipped data disagree.
--
-- The window itself needs real frames and is not reachable from here.

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

-- Render an order to a comparable string so a whole priority can be
-- asserted in one line: "mastery > crit = haste > versatility".
local function orderText(order)
    if type(order) ~= "table" then return tostring(order) end
    local parts = {}
    for _, element in ipairs(order) do
        if type(element) == "table" then
            parts[#parts + 1] = table.concat(element, " = ")
        else
            parts[#parts + 1] = element
        end
    end
    return table.concat(parts, " > ")
end

------------------------------------------------------------------
-- Client stubs
------------------------------------------------------------------

-- Frames: StatPriorityConfig creates an event watcher at file scope, so
-- this has to exist before the file loads. Every method is a no-op.
local frameMeta = { __index = function() return function() end end }
_G.CreateFrame = function() return setmetatable({}, frameMeta) end

-- Secret values do not exist offline, but the guards call this on every
-- path, so it has to answer rather than be nil.
_G.issecretvalue = function() return false end

-- No combat-stat stubs here on purpose: nothing in this addon reads
-- GetCombatRating any more. See the "no conversion" note in
-- StatPriorityConfig.lua, and the two assertions further down that
-- keep it that way.

_G.DodoInspectDB = {}

local ns = {}
local function loadAddonFile(path)
    local chunk = assert(loadfile(path))
    chunk("DodoInspect", ns)
end

ns.Config = {
    STAT_PRIORITY_FEATURE_ENABLED = true,
    STAT_COLORS = {
        crit = { 1, 1, 1 }, haste = { 1, 1, 1 },
        mastery = { 1, 1, 1 }, versatility = { 1, 1, 1 },
    },
}
ns.L = { statNames = {}, stats = {} }
ns.IsEnabled = function() return true end

-- Snapshot the global namespace before loading. A `function Foo()` that
-- was meant to assign to a forward-declared local silently creates a
-- GLOBAL when that declaration is out of scope -- and the local stays
-- nil, so the first call fails at runtime, inside the UI, where nothing
-- else here can reach it.
local globalsBefore = {}
for key in pairs(_G) do globalsBefore[key] = true end

loadAddonFile("Data/StatPriority.lua")
loadAddonFile("StatPriority.lua")
loadAddonFile("StatPriorityConfig.lua")

local leaked = {}
for key in pairs(_G) do
    if not globalsBefore[key] then leaked[#leaked + 1] = key end
end
table.sort(leaked)
checkEqual(#leaked, 0, "load: the addon files create no globals (found: "
    .. table.concat(leaked, ", ") .. ")")

------------------------------------------------------------------
-- Order shape
------------------------------------------------------------------

local FLAT = { "crit", "haste", "mastery", "versatility" }

checkEqual(orderText(ns.NormalizeStatOrder(FLAT)),
    "crit > haste > mastery > versatility",
    "normalize: a flat order survives unchanged")

checkEqual(orderText(ns.NormalizeStatOrder(
        { "mastery", { "crit", "haste" }, "versatility" })),
    "mastery > crit = haste > versatility",
    "normalize: a tie group survives")

checkEqual(orderText(ns.NormalizeStatOrder(
        { { "crit" }, "haste", "mastery", "versatility" })),
    "crit > haste > mastery > versatility",
    "normalize: a one-element tie group collapses to a plain stat")

checkEqual(orderText(ns.NormalizeStatOrder(
        { {}, "crit", "haste", "mastery", "versatility" })),
    "crit > haste > mastery > versatility",
    "normalize: an empty tie group is dropped")

checkEqual(ns.NormalizeStatOrder({ "crit", "crit", "mastery", "haste" }), nil,
    "normalize: a repeated stat is rejected")
checkEqual(ns.NormalizeStatOrder({ "crit", "haste", "mastery" }), nil,
    "normalize: a missing stat is rejected")
checkEqual(ns.NormalizeStatOrder({ "crit", "haste", "mastery", "leech" }), nil,
    "normalize: a stat that is not a secondary is rejected")
checkEqual(ns.NormalizeStatOrder("crit > haste"), nil,
    "normalize: a non-table is rejected")

-- The window edits the flat form; the data layer stores the nested one.
-- A round trip that loses a tie group would silently rewrite a player's
-- "=" into ">" the next time anything refreshed.
local roundTrips = {
    { "crit", "haste", "mastery", "versatility" },
    { "mastery", { "crit", "haste" }, "versatility" },
    { { "crit", "haste", "mastery", "versatility" } },
    { { "crit", "haste" }, { "mastery", "versatility" } },
    { "crit", { "haste", "mastery", "versatility" } },
}
for _, order in ipairs(roundTrips) do
    local flat, tied = ns.FlattenStatOrder(order)
    checkEqual(orderText(ns.BuildStatOrder(flat, tied)), orderText(order),
        "round trip: " .. orderText(order))
end

------------------------------------------------------------------
-- Which answer wins: shipped data vs player override
------------------------------------------------------------------

-- 251 = Frost DK: shipped, current, no hero-tree split.
checkEqual(orderText(ns.StatPriorityOrder(251, nil, "raid")),
    "crit > mastery > haste > versatility",
    "shipped: Frost DK raid order resolves with no override present")

check(ns.SaveStatPriorityCustom(251, nil, {
        raid = { "versatility", "crit", "haste", "mastery" },
        mythic = { "haste", "crit", "mastery", "versatility" },
    }), "save: an override with a raid order is accepted")

checkEqual(orderText(ns.StatPriorityOrder(251, nil, "raid")),
    "versatility > crit > haste > mastery",
    "override: replaces the shipped raid order")
checkEqual(orderText(ns.StatPriorityOrder(251, nil, "mythic")),
    "haste > crit > mastery > versatility",
    "override: the M+ order is stored and read separately")

-- The whole reason the key includes the hero tree. An override saved
-- with no tree active must not answer for a tree that has one.
checkEqual(orderText(ns.StatPriorityOrder(251, 31, "raid")),
    "crit > mastery > haste > versatility",
    "tree isolation: a no-tree override does not leak onto tree 31")

-- 250 = Blood DK, the spec whose two trees disagree completely. This
-- pair is the machine-checkable form of "never show your San'layn order
-- on a Deathbringer".
checkEqual(orderText(ns.StatPriorityOrder(250, 33, "raid")),
    "crit > mastery = versatility > haste",
    "shipped: Blood DK Deathbringer raid order")
check(ns.SaveStatPriorityCustom(250, 33, {
        raid = { "versatility", "haste", "crit", "mastery" },
    }), "save: override for tree 33 accepted")
checkEqual(orderText(ns.StatPriorityOrder(250, 33, "raid")),
    "versatility > haste > crit > mastery",
    "override: tree 33 uses the player's order")
checkEqual(orderText(ns.StatPriorityOrder(250, 31, "raid")),
    "haste > mastery = crit = versatility",
    "tree isolation: tree 31 still gets the shipped San'layn order")

-- A spec whose shipped entry is not current does not resolve -- and a
-- player override for it does. That freshness gate exists to stop US
-- from showing stale advice, which is not what a line the player typed
-- in themselves is.
ns.StatPriority[9901] = {
    current = false,
    raid = { "crit", "haste", "mastery", "versatility" },
}
checkEqual(ns.StatPriorityOrder(9901, nil, "raid"), nil,
    "stale spec: shipped data does not resolve")
check(ns.SaveStatPriorityCustom(9901, nil, {
        raid = { "haste", "crit", "mastery", "versatility" },
    }), "save: override for a stale spec accepted")
checkEqual(orderText(ns.StatPriorityOrder(9901, nil, "raid")),
    "haste > crit > mastery > versatility",
    "stale spec: the player override resolves anyway")
check(ns.StatPrioritySpecCurrent(9901),
    "stale spec: the panels' pre-check reports it has something to show")

-- Restore defaults is a delete, not a snapshot: that is what keeps the
-- spec on future updates to the shipped data.
check(ns.ClearStatPriorityCustom(251, nil), "clear: reports it removed one")
checkEqual(orderText(ns.StatPriorityOrder(251, nil, "raid")),
    "crit > mastery > haste > versatility",
    "clear: falls back to the shipped order")
check(not ns.ClearStatPriorityCustom(251, nil),
    "clear: a second call reports there was nothing to remove")

------------------------------------------------------------------
-- Copying an override (used by "copy to other hero talents")
------------------------------------------------------------------

local source = {
    raid = { "crit", { "haste", "mastery" }, "versatility" },
    mythic = { "haste", "crit", "mastery", "versatility" },
    goals = { raid = { crit = { unit = "percent", min = 20 } }, mythic = {} },
}
local copied = ns.CopyStatPriorityEntry(source)
copied.raid[1] = "versatility"
copied.raid[2][1] = "versatility"
copied.goals.raid.crit.min = 99
checkEqual(source.raid[1], "crit",
    "copy: editing the copy leaves the source order alone")
checkEqual(source.raid[2][1], "haste",
    "copy: tie groups are copied, not shared by reference")
checkEqual(source.goals.raid.crit.min, 20,
    "copy: targets are copied, not shared by reference")

------------------------------------------------------------------
-- Seeding a fresh override from the shipped data
------------------------------------------------------------------

-- Built here rather than pointed at a live spec: the shipped goals get
-- rewritten every season, and a test that reds when the data is updated
-- would be reporting the wrong thing. The five shapes below are the
-- ones Data/StatPriority.lua actually uses.
ns.StatPriority[9902] = {
    current = true,
    raid = { "mastery", { "crit", "haste" }, "versatility" },
    goals = {
        { stat = "haste", value = 23, unit = "percent" },
        { stat = "crit", min = 800, max = 1200 },
        { stat = "versatility", max = 400 },
        { stat = "mastery", value = 1200, percent = 72, unit = "rating" },
    },
}
local seeded = ns.DefaultStatPriorityEntry(9902, nil)
checkEqual(orderText(seeded.raid), "mastery > crit = haste > versatility",
    "seed: the raid order comes from the shipped entry")
checkEqual(orderText(seeded.mythic), "mastery > crit = haste > versatility",
    "seed: a spec without a split M+ order seeds both from raid")
-- The window has no unit control, so a percentage-flavoured target must
-- not be seeded as a bare number next to four-digit rating targets.
checkEqual(seeded.goals.raid.haste, nil,
    "seed: a percent goal is skipped, not stored as a unitless number")
checkEqual(seeded.goals.raid.crit.min, 800, "seed: a range fills the floor")
checkEqual(seeded.goals.raid.crit.max, 1200, "seed: a range fills the ceiling")
checkEqual(seeded.goals.raid.versatility.max, 400,
    "seed: an at-most goal fills the ceiling")
checkEqual(seeded.goals.raid.versatility.min, nil,
    "seed: an at-most goal leaves the floor empty")
checkEqual(seeded.goals.raid.mastery.min, 1200,
    "seed: a bare target becomes a floor, not a ceiling")

ns.StatPriority[9903] = {
    current = true,
    raid = { "crit", "haste", "mastery", "versatility" },
    contentGoals = {
        raid = { { stat = "haste", value = 1100, unit = "rating" } },
        mythic = { { stat = "haste", min = 650, max = 700, unit = "rating" } },
    },
}
local split = ns.DefaultStatPriorityEntry(9903, nil)
checkEqual(split.goals.raid.haste.min, 1100, "seed: raid targets land in raid")
checkEqual(split.goals.mythic.haste.min, 650, "seed: M+ targets land in M+")
checkEqual(split.goals.mythic.haste.max, 700, "seed: M+ ceiling lands in M+")
checkEqual(split.goals.raid.haste.max, nil,
    "seed: raid and M+ targets do not bleed into each other")

local neutral = ns.DefaultStatPriorityEntry(9904, nil)
checkEqual(orderText(neutral.raid), "crit > haste > mastery > versatility",
    "seed: an uncovered spec opens on the neutral character-sheet order")

------------------------------------------------------------------
-- Target display (there is no conversion, and that is enforced)
------------------------------------------------------------------

-- 1.13.0 shipped a percent <-> rating conversion and it was pulled the
-- same day: the arithmetic was right but the claim was too broad (it
-- answers "what the rating buys", not the number on the character
-- sheet). These two assertions exist so it cannot come back as an
-- entry point nothing calls, with a green suite standing behind it. If
-- a future version genuinely reimplements conversion, delete these two
-- and write real tests for it -- do not just re-add the functions.
checkEqual(ns.StatPerPoint, nil,
    "conversion: no uncalled conversion entry point survives")
checkEqual(ns.ConvertStatTarget, nil,
    "conversion: nor its helper")

checkEqual(ns.FormatStatTarget(1600), "1600",
    "format: a whole target renders whole, not 1600.0")
checkEqual(ns.FormatStatTarget(20.5), "20.5",
    "format: a decimal the player typed is preserved")
checkEqual(ns.FormatStatTarget(1600.02), "1600",
    "format: floating-point noise collapses to the whole number")

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
