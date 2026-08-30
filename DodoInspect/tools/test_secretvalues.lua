-- DodoInspect - tools/test_secretvalues.lua
-- Static source guard for the secret-value family. Run from the addon
-- folder:
--
--     lua tools/test_secretvalues.lua
--
-- Not shipped (packaging excludes tools/).
--
-- WHY: this family has now produced six separate in-game crashes, and
-- the recurring shape is never "nobody knew the rule" -- it is "a
-- second implementation of the same read was written without the
-- guard" (CLAUDE.md, bomb #4 reason 2 and bomb #6). A rule that lives
-- only in prose cannot fire. This one can.
--
-- WHAT IT DOES *NOT* COVER -- read this before trusting a green run:
-- it checks exactly one API (UnitGUID). It says nothing about
-- UnitClass, GetInspectSpecialization, C_PvP score fields, or any
-- other secret source; those are still guarded by hand at their call
-- sites. Green here means "no raw UnitGUID escaped", not "no secret
-- value escaped".

local failures, checks = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    end
end

-- Shipped files only: tools/ is excluded from the CurseForge zip.
local SHIPPED = {
    "Bags.lua", "Bank.lua", "Config.lua", "Core.lua", "Durability.lua",
    "Equipment.lua", "GearPanel.lua", "GearRank.lua", "Gradient.lua",
    "Inspect.lua", "InspectPanel.lua", "ItemInfo.lua", "Locales.lua",
    "LootPanel.lua", "LootSource.lua", "Minimap.lua", "Options.lua",
    "Overlay.lua", "SidePanel.lua", "StatPriority.lua",
    "StatPriorityConfig.lua", "StatRatings.lua", "TargetInfo.lua",
    "Data/Loot.lua", "Data/StatPriority.lua", "Data/Trinkets.lua",
}

-- Frontier pattern, NOT a plain substring: "ReadableUnitGUID(" ends
-- with "UnitGUID(" and would match a substring search, so every call
-- through the helper would read as a violation.
local RAW = "%f[%w_]UnitGUID%s*%("
local HOME = "InspectPanel.lua" -- the one file allowed to call it raw

local seen = {}
for _, name in ipairs(SHIPPED) do
    local f = io.open(name, "r")
    check(f ~= nil, "listed file exists: " .. name)
    if f then
        local src = f:read("*a")
        f:close()
        local n = 0
        for _ in src:gmatch(RAW) do n = n + 1 end
        if n > 0 then seen[name] = n end
    end
end

for name, n in pairs(seen) do
    check(name == HOME, string.format(
        "raw UnitGUID( only in %s -- found %d in %s. Route it through "
        .. "ns.ReadableUnitGUID so a secret GUID becomes nil at the "
        .. "boundary (CLAUDE.md bomb #6)", HOME, n, name))
end
check(seen[HOME] == 1, string.format(
    "%s holds exactly one raw call (the helper itself), saw %s",
    HOME, tostring(seen[HOME])))

-- The export the other files depend on. Without it every caller gets
-- "attempt to call a nil value" instead of a nil GUID.
local ip = io.open(HOME, "r"):read("*a")
check(ip:find("ns.ReadableUnitGUID%s*=%s*ReadableUnitGUID") ~= nil,
    HOME .. " still exports ns.ReadableUnitGUID")

-- Negative control: the pattern must reject the helper-call form, or
-- the check above would be vacuously green everywhere.
check(("    local g = ns.ReadableUnitGUID(\"target\")"):find(RAW) == nil,
    "pattern does not match ns.ReadableUnitGUID( (no false positives)")
check(("    inspectPendingGUID = UnitGUID(\"target\")"):find(RAW) ~= nil,
    "pattern does match a real raw call (no false negatives)")

print(string.format("\n%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
