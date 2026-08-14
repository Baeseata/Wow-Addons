-- DodoInspect - GearRank.lua
-- Ranks this season's loot for one slot against a spec's stat priority.
--
-- Everything here is a pure function of Data/Loot.lua plus the resolved
-- stat order, so it can be exercised outside the game. No frames, no
-- unit data, no secret values reach this file.
--
-- WHAT THIS IS NOT: it is not a best-in-slot list and must never be
-- labelled one. It ranks how well an item's secondary stats match the
-- spec's stat order. It does not know about tier set bonuses, on-item
-- effects, weapon damage or trinket procs -- those are surfaced as flags
-- next to a row, never folded into the score.
--
-- ONE EXCEPTION, added 2026-08-14 on the owner's call: item level does
-- enter the ordering, but only as a coarse tier, never inside the score.
-- Pieces that reach the Myth 9/6 equivalent (344) and carry a primary
-- stat sort above everything else in their slot; see NINE_SIX_SOURCES.
-- The score itself remains a pure stat-fit number, so "why is this
-- first" always has exactly one of two answers: better stat fit, or a
-- higher item level ceiling.

local _, ns = ...

-- Position weights. A tie group consumes as many positions as it has
-- members, so writing { "crit", "haste" } in first place gives both 1.0
-- and pushes the next stat to the third weight -- otherwise the choice
-- of notation would silently change the ranking.
local POSITION_WEIGHT = { 1.00, 0.70, 0.45, 0.25 }
local MIN_WEIGHT = 0.25

-- Items that can reach the Myth 9/6 equivalent (ilvl 344): the final two
-- bosses of the Venomous Abyss. Ten item levels above everything else in
-- the pool is worth more than any secondary-stat fit, so these sort to
-- the top of their slot -- but ONLY when the item carries a primary stat.
--
-- That condition is the whole point. Those ten item levels buy Strength /
-- Agility / Intellect on armor and weapons, which is the single largest
-- source of throughput. Rings and necks have no primary stat at all
-- (Data/Loot.lua field [4] is nil for them), so the same jump buys only
-- secondaries and stamina, and promoting them above a better-itemised
-- ring would be wrong.
--
-- KNOWN GAP: "Very Rare" drops also reach 344 and are not marked in the
-- data, so they are not promoted here. Adding them needs a generator
-- change, not a change to this rule.
local NINE_SIX_SOURCES = {
    [1320] = { [7] = true, [8] = true },  -- The Venomous Abyss
}

-- entry -> true when this item both reaches 344 and has a primary stat.
function ns.ReachesTopItemLevel(entry)
    if not entry or entry[4] == nil then return false end
    local positions = NINE_SIX_SOURCES[entry[1]]
    return (positions and positions[entry[3]]) == true
end

-- Which item primary stats a spec can actually use. An item tagged SI
-- (Strength or Intellect) is usable by both, so the plate healer and the
-- plate DPS share it, while a pure STR item is warriors-only.
local PRIMARY_FIT = {
    STR = { STR = true, SI = true, SA = true, SAI = true },
    AGI = { AGI = true, AI = true, SA = true, SAI = true },
    INT = { INT = true, SI = true, AI = true, SAI = true },
}

-- Slots whose items carry no primary stat at all, or carry all three.
-- Rings and necks have none; cloaks are always Strength/Agility/
-- Intellect. Both skip the primary filter rather than special-casing nil.
local ARMOR_SUBCLASS = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }

-- Only these slots may be filtered by armor type. Cloaks are the reason
-- this list exists: the client files them under the Cloth armor subclass
-- even though every class wears them, so filtering on subclass alone
-- hands cloaks to cloth wearers and gives everyone else an empty row --
-- which reads as missing data, not as a filter. Rings, necks and
-- trinkets sit in subclass 0 (Miscellaneous) and were never at risk.
local ARMOR_TYPE_SLOTS = {
    INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true,
    INVTYPE_ROBE = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
    INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true,
}

-- Chest is the one slot the game spells two ways.
local EQUIP_ALIASES = {
    INVTYPE_CHEST = { INVTYPE_CHEST = true, INVTYPE_ROBE = true },
    INVTYPE_ROBE  = { INVTYPE_CHEST = true, INVTYPE_ROBE = true },
}

-- Can a spec with this primary stat use an item tagged that way? Items
-- with no primary stat (rings, necks) fit everyone. Exported so the rule
-- is testable on its own: the current tier happens to give every plate
-- piece SI and every leather piece AI, so real data cannot exercise this
-- filter through SlotCandidates alone.
function ns.PrimaryFits(specPrimary, itemPrimary)
    if not itemPrimary then return true end
    local fits = PRIMARY_FIT[specPrimary]
    return (fits and fits[itemPrimary]) == true
end

-- stat key -> position weight, resolved once per ranking pass.
function ns.StatWeights(order)
    if type(order) ~= "table" then return nil end
    local weights, position = {}, 1
    for _, element in ipairs(order) do
        local weight = POSITION_WEIGHT[position] or MIN_WEIGHT
        if type(element) == "table" then
            for _, key in ipairs(element) do
                weights[key] = weight
            end
            position = position + #element
        else
            weights[element] = weight
            position = position + 1
        end
    end
    return weights
end

-- Fit in 0..1. Normalised against the item's own secondary budget, which
-- is NOT constant across slots: armor totals about 7000 while rings and
-- necks total about 17500. Dividing by a fixed number would rank every
-- ring above every chest.
function ns.StatFit(entry, weights)
    if not entry or not weights then return nil end
    local firstStat, firstValue = entry[5], entry[6]
    local secondStat, secondValue = entry[7], entry[8]
    if not firstStat then return nil end -- azerite-era armor, no secondaries

    local total = (firstValue or 0) + (secondValue or 0)
    if total <= 0 then return nil end

    local score = (firstValue or 0) / total * (weights[firstStat] or MIN_WEIGHT)
    if secondStat then
        score = score + (secondValue or 0) / total
                        * (weights[secondStat] or MIN_WEIGHT)
    end
    return score
end

-- GetItemInfoInstant answers from the client's static item data and never
-- needs the item cached, so slot and armor type cost nothing at runtime
-- and stay out of the data file. Only the item NAME needs the async
-- GetItemInfo, and that is the display layer's problem.
local function ItemShape(itemID)
    local getter = _G.GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
    if type(getter) ~= "function" then return nil end
    local ok, _, _, _, equipLoc, _, classID, subclassID = pcall(getter, itemID)
    if not ok then return nil end
    return equipLoc, classID, subclassID
end

local function MatchesSlot(equipLoc, slotKey)
    if not equipLoc or equipLoc == "" then return false end
    local aliases = EQUIP_ALIASES[slotKey]
    if aliases then return aliases[equipLoc] == true end
    return equipLoc == slotKey
end

-- Candidate list for one slot, best stat fit first.
--
-- Returns an array of { id, score, entry, effect, unranked } and, as a
-- second value, the count of entries that could not be scored. Items
-- without secondary stats (Battle for Azeroth azerite head, shoulder and
-- chest, which return in the Mythic+ pool) are kept and flagged rather
-- than dropped: an item vanishing from a list reads as missing data,
-- while a flagged row tells the truth.
function ns.SlotCandidates(slotKey, specID, subTreeID, content)
    if not ns.LootData or not ns.SpecGear then return nil end
    local spec = ns.SpecGear[specID]
    if not spec then return nil end
    local armorType, primaryStat = spec[1], spec[2]

    local order = ns.StatPriorityOrder and
                  ns.StatPriorityOrder(specID, subTreeID, content)
    local weights = ns.StatWeights(order)
    if not weights then return nil end

    local fits = PRIMARY_FIT[primaryStat]
    local out, unranked = {}, 0

    for itemID, entry in pairs(ns.LootData) do
        local equipLoc, classID, subclassID = ItemShape(itemID)
        if MatchesSlot(equipLoc, slotKey) then
            local keep = true
            -- Armor slots filter twice: the armor type keeps other classes
            -- out, the primary stat keeps the other users of the same
            -- armor type out. The second filter is currently a no-op on
            -- most slots because this tier gives plate SI and leather AI
            -- rather than pure stats, but it is the filter that armor type
            -- structurally cannot do, so it stays.
            if ARMOR_TYPE_SLOTS[equipLoc] and classID == 4
               and ARMOR_SUBCLASS[subclassID] then
                keep = ARMOR_SUBCLASS[subclassID] == armorType
                       and ns.PrimaryFits(primaryStat, entry[4])
            end
            if keep then
                local score = ns.StatFit(entry, weights)
                if not score then unranked = unranked + 1 end
                out[#out + 1] = {
                    id = itemID,
                    score = score,
                    entry = entry,
                    effect = entry[9] == 1,
                    unranked = (score == nil),
                    topItemLevel = ns.ReachesTopItemLevel(entry),
                }
            end
        end
    end

    -- Unrankable items sink to the bottom. Ties break on how lopsided the
    -- top stat is, then on item id so the order never shuffles between
    -- two openings of the same panel.
    table.sort(out, function(a, b)
        -- Item level tier first: 344 beats any stat fit at 334. Applied
        -- before the unranked check so a statless 344 piece would still
        -- outrank a statless 334 one, and after nothing at all.
        if a.topItemLevel ~= b.topItemLevel then return a.topItemLevel end
        if (a.score == nil) ~= (b.score == nil) then return b.score == nil end
        if a.score and b.score and math.abs(a.score - b.score) > 0.0001 then
            return a.score > b.score
        end
        local aShare = (a.entry[6] or 0) / math.max(1, (a.entry[6] or 0) + (a.entry[8] or 0))
        local bShare = (b.entry[6] or 0) / math.max(1, (b.entry[6] or 0) + (b.entry[8] or 0))
        if math.abs(aShare - bShare) > 0.0001 then return aShare > bShare end
        return a.id < b.id
    end)

    return out, unranked
end
