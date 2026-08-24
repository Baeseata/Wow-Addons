-- DodoInspect - LootSource.lua
-- Turns a Data/Loot.lua entry into a localized "where does this drop"
-- line, and adds that line to item tooltips.
--
-- No translated strings live here. Instance and boss names come from the
-- Encounter Journal (EJ_GetInstanceInfo / EJ_GetEncounterInfo), so every
-- client language is covered without the addon shipping a single name.
--
-- Raids print the boss: "The Venomous Abyss  #8 Ula'tek".
-- Mythic+ dungeons print the instance only -- which boss dropped it does
-- not change where you have to go, and the returning dungeons put the
-- same item on several bosses anyway.
--
-- Defaults ON like the addon's other display toggles (owner decision
-- 2026-08-14; he keeps Data/Loot.lua current by hand). It shipped opt-in
-- because the data is season-dated -- see Options.lua for that history.
--
-- This file also owns the DERIVED card list the loot browser (LootPanel.lua)
-- draws its left column from -- see ns.LootCardList below. It lives here
-- rather than in the panel because it is pure data shaping over
-- Data/Loot.lua with no frame in sight, which is also what makes it
-- reachable from tools/test_gearrank.lua.

local _, ns = ...

local ejLoadAttempted = false
local instanceNames = {}
local encounterNames = {}

function ns.LootSourceEnabled()
    return ns.IsEnabled("showLootSource")
end

-- The Encounter Journal is load-on-demand. Its EJ_* functions can answer
-- before the UI is loaded on some paths and not on others, so ask once,
-- lazily, and never block on the result.
local function EnsureEncounterJournal()
    if ejLoadAttempted then return end
    ejLoadAttempted = true
    if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
    end
end

-- GearPanel needs the journal loaded too, for its tooltip links.
ns.EnsureEncounterJournal = EnsureEncounterJournal

-- Both lookups can fail while the journal data is still cold. Return nil
-- and let the caller drop the line rather than printing a placeholder:
-- a missing line reads as "no data for this item", a placeholder reads
-- as a bug.
local function LookupName(cache, id, apiName)
    if cache[id] ~= nil then
        return cache[id] or nil
    end
    local api = _G[apiName]
    if type(api) ~= "function" then return nil end
    local ok, name = pcall(api, id)
    if not ok or type(name) ~= "string" or name == "" then
        EnsureEncounterJournal()
        return nil
    end
    cache[id] = name
    return name
end

function ns.LootEntry(itemID)
    if type(itemID) ~= "number" then return nil end
    return ns.LootData and ns.LootData[itemID] or nil
end

-- Localized source line for an item, or nil when the item is not part of
-- the current season's tables.
function ns.LootSourceText(itemID)
    local entry = ns.LootEntry(itemID)
    if not entry then return nil end

    local instanceID, encounterID, position = entry[1], entry[2], entry[3]
    local instanceName = LookupName(instanceNames, instanceID, "EJ_GetInstanceInfo")
    if not instanceName then return nil end

    if not (ns.LootMeta and ns.LootMeta.raids and ns.LootMeta.raids[instanceID]) then
        return instanceName
    end

    local bossName = LookupName(encounterNames, encounterID, "EJ_GetEncounterInfo")
    if not bossName then return instanceName end
    return string.format("%s  #%d %s", instanceName, position, bossName)
end

-- Localized names for the loot browser, which needs them one at a time
-- rather than folded into a source line. Same cache, same "nil until the
-- journal is warm" contract as above -- the browser redraws.
function ns.LootInstanceName(instanceID)
    if type(instanceID) ~= "number" then return nil end
    return LookupName(instanceNames, instanceID, "EJ_GetInstanceInfo")
end

function ns.LootBossName(encounterID)
    if type(encounterID) ~= "number" then return nil end
    return LookupName(encounterNames, encounterID, "EJ_GetEncounterInfo")
end

--------------------------------------------------------------------
-- Card list for the loot browser's left column
--------------------------------------------------------------------

-- DERIVED from ns.LootMeta / ns.LootData / ns.ChallengeMap, never written
-- out by hand. A hand-kept roster sitting beside a generated loot table is
-- a second copy of one fact: the two drift, both read as correct on their
-- own, and nothing in the addon can say which one is right.
--
-- Mythic+ mode lists DUNGEONS (8 this season). Raid mode lists BOSSES
-- (9 this season, across two instances) -- a raid is not one card, because
-- what a player is asking is "what does THIS boss drop".
--
-- `groupFirst` marks the first boss of each instance so the panel can put
-- the raid name above it. Nine boss names with no headings read as one
-- raid, and this season they are not.
--
-- A boss that drops nothing we know about gets no card. That is right for
-- a loot browser and worth saying out loud: "9 bosses" here means "9
-- bosses that drop gear in our table", not "9 bosses in the raid".
--
-- Order is derived and total: instance id, then boss position, then
-- encounter id. pairs() order is unspecified, and a card list that
-- reshuffles between two openings is a bug nobody can reproduce on demand.
local cardLists = {}

function ns.LootCardList(mode)
    if not (ns.LootData and ns.LootMeta) then return nil end
    mode = (mode == "raid") and "raid" or "mythic"
    if cardLists[mode] then return cardLists[mode] end

    local list = {}
    if mode == "mythic" then
        local ids = {}
        for instanceID in pairs(ns.LootMeta.dungeons or {}) do
            ids[#ids + 1] = instanceID
        end
        table.sort(ids)
        for _, instanceID in ipairs(ids) do
            list[#list + 1] = {
                kind = "dungeon",
                key = "d" .. instanceID,
                instanceID = instanceID,
                mapID = ns.ChallengeMap and ns.ChallengeMap[instanceID] or nil,
                groupFirst = false,
            }
        end
    else
        local seen, rows = {}, {}
        for _, entry in pairs(ns.LootData) do
            local instanceID, encounterID, position = entry[1], entry[2], entry[3]
            local pair = tostring(instanceID) .. ":" .. tostring(encounterID)
            if (ns.LootMeta.raids or {})[instanceID] and not seen[pair] then
                seen[pair] = true
                rows[#rows + 1] = {
                    kind = "boss",
                    key = "b" .. encounterID,
                    instanceID = instanceID,
                    encounterID = encounterID,
                    position = position,
                }
            end
        end
        table.sort(rows, function(a, b)
            if a.instanceID ~= b.instanceID then
                return a.instanceID < b.instanceID
            end
            if a.position ~= b.position then return a.position < b.position end
            return a.encounterID < b.encounterID
        end)
        local lastInstance
        for _, row in ipairs(rows) do
            row.groupFirst = (row.instanceID ~= lastInstance)
            lastInstance = row.instanceID
            list[#list + 1] = row
        end
    end

    cardLists[mode] = list
    return list
end

-- Tooltip line. TooltipDataProcessor fires for every item tooltip, which
-- is what we want: bags, the character frame, the inspect window, chat
-- links and the auction house all get the same line for free.
--
-- The id is guarded even though item ids are not unit data: the addon's
-- standing rule is that issecretvalue comes first on anything that
-- reaches an arithmetic or comparison, and a tainted tooltip on an
-- enemy player's gear is exactly the path that has bitten this addon
-- before.
local function OnItemTooltip(tooltip, data)
    if not ns.LootSourceEnabled() then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end

    local itemID = data and data.id
    if issecretvalue(itemID) then return end
    if type(itemID) ~= "number" then return end

    local text = ns.LootSourceText(itemID)
    if not text then return end

    local color = ns.Config.LOOT_SOURCE_COLOR
    tooltip:AddLine(text, color[1], color[2], color[3])
end

function ns.SetupLootSource()
    if not TooltipDataProcessor or not Enum or not Enum.TooltipDataType then
        return
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,
                                            OnItemTooltip)
end
