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

--------------------------------------------------------------------
-- What the player already owns
--------------------------------------------------------------------
-- Built fresh on every panel refresh rather than cached. A cache here
-- would need invalidating on equip, loot, mail, vendor, bank and
-- void-storage traffic, and the failure mode of missing one is a column
-- that quietly says you do not own something you are wearing. The scan
-- is one pass over about two hundred container slots and the panel
-- refreshes only when it is opened or clicked.
--
-- ONLY REAL ITEMS. The design's original fourth column wanted
-- "owned at Champion / owned at Hero", and that was abandoned with
-- evidence: there is no per-item-level collection API, and the
-- transmog tables cannot stand in -- 39 of the season's items
-- (trinkets, rings, necks) have no appearance at all, so 17.5% of the
-- column would have answered "no" when the truth was "cannot tell".
-- Reading the item level off the physical item's own link has no such
-- blind spot. See MPLUS_LOOT_PANEL_DESIGN_2026-08-22.md.
--
-- Bank containers are included and are allowed to answer nothing: the
-- client only knows their contents once the bank has been opened this
-- session. "Not found" and "not cached" therefore look the same here,
-- which is why the column says where an item IS and never claims an
-- item is missing.
-- Which containers to walk, and what to CALL each one -- DERIVED from
-- Enum.BagIndex rather than written out as numbers.
--
-- The numbers are not stable and are not guessable: character bank tabs
-- and warband (account) bank tabs live in one run of ids, and a
-- hand-written range that stops in the middle of it does something worse
-- than miss the warband bank -- it scans the FIRST warband tab (because
-- that id falls inside the character range) and misses the rest, so
-- whether the column finds your item depends on which tab you happened
-- to drop it in, and nothing on screen would let you learn that rule.
-- Nothing on this machine references Enum.BagIndex, so there was no
-- in-production example to copy the numbers from either.
--
-- Asking the client removes the guess: every name it does not have is
-- simply skipped, so this works on a client that has no warband bank at
-- all and picks it up on one that does.
local function OwnedContainers()
    local out = {}
    local function add(id, where)
        if type(id) == "number" then out[#out + 1] = { id = id, where = where } end
    end
    local bag = Enum and Enum.BagIndex
    if bag then
        add(bag.Backpack, "bags")
        add(bag.ReagentBag, "bags")
        for i = 1, 4 do add(bag["Bag_" .. i], "bags") end
        add(bag.Bank, "bank")
        add(bag.Reagentbank, "bank")
        add(bag.Reagentbank or bag.ReagentBank, "bank")
        for i = 1, 12 do
            add(bag["BankBag_" .. i], "bank")
            add(bag["CharacterBankTab_" .. i], "bank")
            add(bag["AccountBankTab_" .. i], "bank")
        end
    else
        -- Pre-Enum fallback: the classic layout only.
        add(0, "bags")
        for i = 1, 4 do add(i, "bags") end
        add(-1, "bank")
    end
    -- The loops above can name the same id twice (Reagentbank spelling,
    -- or a client where two names alias). Scanning it twice is harmless
    -- but the ranking below would compare a container against itself.
    local seen, unique = {}, {}
    for _, c in ipairs(out) do
        if not seen[c.id] then seen[c.id] = true; unique[#unique + 1] = c end
    end
    return unique
end

-- Equipment slots worth scanning: 1..19 covers head through off hand.
-- Shirt and tabard are in that range and never carry season loot, but
-- excluding them would be a hand-written list that has to stay in step
-- with a numbering Blizzard owns.
local EQUIP_SLOT_LAST = 19

local function LinkItemID(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function LinkItemLevel(link)
    if not (C_Item and type(C_Item.GetDetailedItemLevelInfo) == "function") then
        return nil
    end
    local ok, level = pcall(C_Item.GetDetailedItemLevelInfo, link)
    if ok and type(level) == "number" and level > 0 then return level end
    return nil
end

-- itemID -> { where = "equipped" | "bags" | "bank", ilvl = number|nil }
--
-- Equipped beats a bag copy, and a bag copy beats a bank copy: the
-- question the column answers is "have I got this", and the strongest
-- true answer is the useful one. Within one rank the first copy found
-- wins -- two copies of the same ring in two bags are the same answer.
function ns.LootOwnedIndex()
    local out = {}

    local function record(link, where, rank)
        local itemID = LinkItemID(link)
        if not itemID then return end
        -- Strongest place wins; within one place the BEST copy wins.
        -- Taking the first found would let physical bag-slot order decide
        -- the number: two copies of a ring at 285 and 311 would report
        -- whichever sat in the lower slot, and "Bags 285" against a 311
        -- ceiling reads as "you still need this".
        local ilvl = LinkItemLevel(link)
        local prior = out[itemID]
        if prior then
            if prior.rank < rank then return end
            if prior.rank == rank and (prior.ilvl or 0) >= (ilvl or 0) then return end
        end
        out[itemID] = { where = where, rank = rank, ilvl = ilvl }
    end

    local getInventory = _G.GetInventoryItemLink
    if type(getInventory) == "function" then
        for slotID = 1, EQUIP_SLOT_LAST do
            local ok, link = pcall(getInventory, "player", slotID)
            if ok and link then record(link, "equipped", 1) end
        end
    end

    if C_Container and type(C_Container.GetContainerNumSlots) == "function"
       and type(C_Container.GetContainerItemLink) == "function" then
        for _, container in ipairs(OwnedContainers()) do
            -- Bank ids answer 0 slots until the bank has been opened, so
            -- this doubles as the "is it readable yet" test.
            local ok, slots = pcall(C_Container.GetContainerNumSlots, container.id)
            if ok and type(slots) == "number" and slots > 0 then
                local where = container.where
                local rank = (where == "bags") and 2 or 3
                for slot = 1, slots do
                    local got, link = pcall(C_Container.GetContainerItemLink,
                                            container.id, slot)
                    if got and link then record(link, where, rank) end
                end
            end
        end
    end

    return out
end
