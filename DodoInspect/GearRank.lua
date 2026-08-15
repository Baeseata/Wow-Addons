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
--
-- The SHAPE matters more than the numbers (owner's call 2026-08-14). The
-- honest answer here is a sim per spec, which we are not going to run, so
-- this curve is an admitted approximation of one. What it encodes: a
-- spec's top three secondaries are usually worth roughly similar amounts
-- while the last one is worth distinctly less -- hence a compressed front
-- (1.00/0.80/0.60) and a tail pulled well away (0.15).
--
-- The previous curve { 1.00, 0.70, 0.45, 0.25 } decayed evenly, which
-- overstated how much worse the 2nd and 3rd stats are. Symptom: for a
-- haste>mastery>crit>versatility spec, a ring with 78% haste + 22%
-- VERSATILITY (its worst stat) outranked one with 64% haste + 36% crit,
-- because crit was only worth 0.45 there.
-- 🔴 Lowering the last weight alone does NOT fix this -- measured:
-- 0.25 -> 0.10 moved that list by exactly zero positions (at 0.10 the two
-- scores land on 0.802 each). Raising the MIDDLE is what moves it.
local POSITION_WEIGHT = { 1.00, 0.80, 0.60, 0.15 }
local MIN_WEIGHT = 0.15

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

-- The one slot whose order comes from simulation instead of stat fit.
--
-- 33 of the 42 trinkets in Data/Loot.lua have no secondary stats at all, so
-- ns.StatFit returns nil for them and the sort that orders every other slot
-- has nothing to work with. Their value sits in the on-item effect, which a
-- simulation prices and a stat sort structurally cannot see. Data/Trinkets.lua
-- carries that order; see TRINKET_DATA_RESEARCH_2026-08-14.md.
ns.TRINKET_SLOT = "INVTYPE_TRINKET"

-- specID -> { [itemID] = rank }, or nil when the source has no data for
-- this spec. nil and "ranked nothing" are different answers and the panel
-- says different things about them, so this never returns an empty table.
function ns.TrinketOrder(specID)
    if not specID or not ns.TrinketRank then return nil end
    local order = ns.TrinketRank[specID]
    if not order or #order == 0 then return nil end
    local rank = {}
    for i = 1, #order do
        -- First listing wins: the generator already collapsed a trinket's
        -- several simulated configurations down to its best-placed one, and
        -- a second pass here would silently prefer the worst.
        if rank[order[i]] == nil then rank[order[i]] = i end
    end
    return rank
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

------------------------------------------------------------------
-- Weapon shape -- what a spec actually puts in each hand
------------------------------------------------------------------
-- Two halves here, and confusing them is the whole trap:
--   CAN    ns.SpecWeapons / ns.SpecShield in Data/Loot.lua, DERIVED from
--          SkillLine + SkillLineAbility.ClassMask. Never hand-edit those.
--   SHOULD the table below, HAND-WRITTEN and not derivable from anything:
--          an arms warrior CAN equip a one-hander and a shield, he just
--          must not, and no DB2 column says so.
--
-- Shapes, written as (main hand / off hand):
--   ONEHAND_SHIELD  1H / shield
--   DUAL_1H         1H / 1H
--   DUAL_2H         2H / 2H            fury warrior, Titan's Grip
--   TWOHAND         2H / nothing
--   RANGED          bow, gun, crossbow / nothing
--   DUAL_OR_2H      1H or 2H; off hand takes a 1H, empty when two-handed
--   OFFHAND_OR_2H   1H or 2H; off hand takes a held item, empty when 2H
--   SHIELD_OR_2H    as above, and the off hand may also be a shield
--
-- The last three are AMBIGUOUS and the two panel rows are COUPLED: pick a
-- two-hander and the off-hand row has no answer at all. The panel offers a
-- two-hand / one-hand switch and moves both rows together, because ranking
-- them independently recommends a staff in one row and a held item in the
-- other -- a pair that cannot exist on a character.
local WEAPON_SHAPE = {
    [65]   = "ONEHAND_SHIELD", -- Holy paladin
    [66]   = "ONEHAND_SHIELD", -- Protection paladin
    [73]   = "ONEHAND_SHIELD", -- Protection warrior
    [259]  = "DUAL_1H",        -- Assassination
    [260]  = "DUAL_1H",        -- Outlaw
    [261]  = "DUAL_1H",        -- Subtlety
    [263]  = "DUAL_1H",        -- Enhancement
    [577]  = "DUAL_1H",        -- Havoc
    [581]  = "DUAL_1H",        -- Vengeance
    [1480] = "DUAL_1H",        -- Devourer
    [72]   = "DUAL_2H",        -- Fury
    [70]   = "TWOHAND",        -- Retribution
    [71]   = "TWOHAND",        -- Arms
    [103]  = "TWOHAND",        -- Feral
    [104]  = "TWOHAND",        -- Guardian
    [250]  = "TWOHAND",        -- Blood
    [252]  = "TWOHAND",        -- Unholy
    [253]  = "RANGED",         -- Beast Mastery
    [254]  = "RANGED",         -- Marksmanship
    [251]  = "DUAL_OR_2H",     -- Frost death knight
    [255]  = "DUAL_OR_2H",     -- Survival
    [268]  = "DUAL_OR_2H",     -- Brewmaster
    [269]  = "DUAL_OR_2H",     -- Windwalker
    [62]   = "OFFHAND_OR_2H",  -- Arcane
    [63]   = "OFFHAND_OR_2H",  -- Fire
    [64]   = "OFFHAND_OR_2H",  -- Frost mage
    [102]  = "OFFHAND_OR_2H",  -- Balance
    [105]  = "OFFHAND_OR_2H",  -- Restoration druid
    [256]  = "OFFHAND_OR_2H",  -- Discipline
    [257]  = "OFFHAND_OR_2H",  -- Holy priest
    [258]  = "OFFHAND_OR_2H",  -- Shadow
    [265]  = "OFFHAND_OR_2H",  -- Affliction
    [266]  = "OFFHAND_OR_2H",  -- Demonology
    [267]  = "OFFHAND_OR_2H",  -- Destruction
    [270]  = "OFFHAND_OR_2H",  -- Mistweaver
    [1467] = "OFFHAND_OR_2H",  -- Devastation
    [1468] = "OFFHAND_OR_2H",  -- Preservation
    [1473] = "OFFHAND_OR_2H",  -- Augmentation
    [262]  = "SHIELD_OR_2H",   -- Elemental
    [264]  = "SHIELD_OR_2H",   -- Restoration shaman
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

-- Which panel row is which hand. These two slot keys are the reason
-- MatchesSlot is not enough on its own: for armor the character slot and
-- the item's equipLoc are the same string, for weapons they are not
-- (a one-hander is INVTYPE_WEAPON, never INVTYPE_WEAPONMAINHAND, and
-- INVTYPE_WEAPONOFFHAND has zero items in the whole season).
local WEAPON_SLOT_HAND = {
    INVTYPE_WEAPONMAINHAND = "main",
    INVTYPE_WEAPONOFFHAND  = "off",
}

local LOC = {
    ONE_MAIN    = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true },
    ONE_OFF     = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true },
    TWO         = { INVTYPE_2HWEAPON = true },
    -- Ranged locations belong to the RANGED shape ONLY. Rogues and
    -- warriors do have bow/gun proficiency, but a ranged weapon takes the
    -- main hand and costs them dual wield, so nobody equips one -- listing
    -- them would be a worse error than the one this costs, which is that
    -- the season's single caster wand never appears.
    RANGED      = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true },
    SHIELD      = { INVTYPE_SHIELD = true },
    HELD        = { INVTYPE_HOLDABLE = true },
    SHIELD_HELD = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true },
}

local AMBIGUOUS_SHAPE = {
    DUAL_OR_2H = true, OFFHAND_OR_2H = true, SHIELD_OR_2H = true,
}

-- The shape name, or nil for an unknown spec. Exported so a test can tell
-- "this spec has one configuration" apart from "this spec is missing from
-- the table" -- WeaponShapeAmbiguous deliberately answers false to both,
-- which is right for callers and useless for coverage checking.
function ns.WeaponShape(specID)
    return WEAPON_SHAPE[specID or -1]
end

-- Does this spec get the two-hand / one-hand switch? nil spec, unknown
-- spec and unambiguous spec all answer false, so the caller never has to
-- distinguish "no switch" from "no data".
function ns.WeaponShapeAmbiguous(specID)
    return AMBIGUOUS_SHAPE[WEAPON_SHAPE[specID or -1] or ""] == true
end

function ns.IsWeaponSlot(slotKey)
    return WEAPON_SLOT_HAND[slotKey or ""] ~= nil
end

-- Equip locations allowed in one hand for one spec, or nil when that hand
-- holds nothing at all in this configuration (a two-hander leaves the off
-- hand with no answer, and that is a different thing from an empty list).
-- mode is "twohand" or "onehand" and is ignored by unambiguous shapes.
function ns.WeaponPool(specID, slotKey, mode)
    local hand = WEAPON_SLOT_HAND[slotKey or ""]
    if not hand then return nil end
    local shape = WEAPON_SHAPE[specID or -1]
    if not shape then return nil end
    local twoHanded = (mode ~= "onehand")
    if shape == "ONEHAND_SHIELD" then
        return hand == "main" and LOC.ONE_MAIN or LOC.SHIELD
    elseif shape == "DUAL_1H" then
        return hand == "main" and LOC.ONE_MAIN or LOC.ONE_OFF
    elseif shape == "DUAL_2H" then
        return LOC.TWO
    elseif shape == "TWOHAND" then
        return hand == "main" and LOC.TWO or nil
    elseif shape == "RANGED" then
        return hand == "main" and LOC.RANGED or nil
    elseif shape == "DUAL_OR_2H" then
        if twoHanded then return hand == "main" and LOC.TWO or nil end
        return hand == "main" and LOC.ONE_MAIN or LOC.ONE_OFF
    elseif shape == "OFFHAND_OR_2H" then
        if twoHanded then return hand == "main" and LOC.TWO or nil end
        return hand == "main" and LOC.ONE_MAIN or LOC.HELD
    elseif shape == "SHIELD_OR_2H" then
        if twoHanded then return hand == "main" and LOC.TWO or nil end
        return hand == "main" and LOC.ONE_MAIN or LOC.SHIELD_HELD
    end
    return nil
end

-- Can this spec's CLASS equip the item at all? Answers the derived half.
-- Held off-hand items are armor subclass 0 and need no proficiency, which
-- is why this returns true rather than false for anything unrecognised --
-- the equip-location pool has already decided the item belongs in the row.
function ns.WeaponProficient(specID, classID, subclassID)
    if classID == 2 then
        local set = ns.SpecWeapons and ns.SpecWeapons[specID]
        return (set and set[subclassID]) == true
    end
    if classID == 4 and subclassID == 6 then -- shield
        return (ns.SpecShield and ns.SpecShield[specID]) == true
    end
    return true
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
-- mode ("twohand" / "onehand") only matters for the weapon rows and only
-- for the ambiguous shapes; everything else ignores it.
function ns.SlotCandidates(slotKey, specID, subTreeID, content, mode)
    if not ns.LootData or not ns.SpecGear then return nil end
    local spec = ns.SpecGear[specID]
    if not spec then return nil end
    local armorType, primaryStat = spec[1], spec[2]

    -- Weapon rows resolve their own equip locations from the spec's shape,
    -- because the character slot and the item's equipLoc are different
    -- vocabularies there. A nil pool means this hand holds nothing in this
    -- configuration, which is an answer, not missing data -- the panel
    -- asks ns.WeaponPool itself to tell those two apart.
    local weaponRow = ns.IsWeaponSlot(slotKey)
    local pool
    if weaponRow then
        pool = ns.WeaponPool(specID, slotKey, mode)
        if not pool then return {}, 0 end
    end

    local order = ns.StatPriorityOrder and
                  ns.StatPriorityOrder(specID, subTreeID, content)
    local weights = ns.StatWeights(order)
    if not weights then return nil end

    -- Trinkets rank from simulation, not stat fit. A nil table here means
    -- the source covers no data for this spec at all; the panel reports
    -- that in words rather than presenting an arbitrary order as a ranking.
    local trinketRow = (slotKey == ns.TRINKET_SLOT)
    local trinketRank = trinketRow and ns.TrinketOrder(specID) or nil

    local fits = PRIMARY_FIT[primaryStat]
    local out, unranked = {}, 0

    for itemID, entry in pairs(ns.LootData) do
        local equipLoc, classID, subclassID = ItemShape(itemID)
        local inSlot
        if weaponRow then
            inSlot = equipLoc ~= nil and pool[equipLoc] == true
        else
            inSlot = MatchesSlot(equipLoc, slotKey)
        end
        if inSlot then
            local keep = true
            -- Weapon rows filter twice as well, on the other two axes:
            -- proficiency (derived -- can this class hold it) and primary
            -- stat (an Intellect staff is not a rogue's problem). The
            -- handedness axis was already spent picking the pool above.
            if weaponRow then
                keep = ns.WeaponProficient(specID, classID, subclassID)
                       and ns.PrimaryFits(primaryStat, entry[4])
            -- Armor slots filter twice: the armor type keeps other classes
            -- out, the primary stat keeps the other users of the same
            -- armor type out. The second filter is currently a no-op on
            -- most slots because this tier gives plate SI and leather AI
            -- rather than pure stats, but it is the filter that armor type
            -- structurally cannot do, so it stays.
            elseif ARMOR_TYPE_SLOTS[equipLoc] and classID == 4
               and ARMOR_SUBCLASS[subclassID] then
                keep = ARMOR_SUBCLASS[subclassID] == armorType
                       and ns.PrimaryFits(primaryStat, entry[4])
            end
            if keep then
                local score = ns.StatFit(entry, weights)
                -- On the trinket row "unranked" has to mean "the simulation
                -- did not cover this one". Reusing the stat-fit meaning
                -- there would flag 33 of 42 trinkets as unrankable while
                -- they sit in a perfectly good simulated order.
                local simRank = trinketRank and trinketRank[itemID] or nil
                local isUnranked
                if trinketRow then
                    isUnranked = (simRank == nil)
                else
                    isUnranked = (score == nil)
                end
                if isUnranked then unranked = unranked + 1 end
                out[#out + 1] = {
                    id = itemID,
                    score = score,
                    entry = entry,
                    effect = entry[9] == 1,
                    unranked = isUnranked,
                    simRank = simRank,
                    topItemLevel = ns.ReachesTopItemLevel(entry),
                }
            end
        end
    end

    -- Unrankable items sink to the bottom. Ties break on how lopsided the
    -- top stat is, then on item id so the order never shuffles between
    -- two openings of the same panel.
    table.sort(out, function(a, b)
        -- Simulation rank outranks everything, including the item level
        -- tier below -- the simulation already compared each trinket at its
        -- own item level ceiling, so applying the 344 promotion on top
        -- would price those ten item levels in twice. Only the trinket row
        -- ever carries simRank, so no other slot can reach this branch.
        if a.simRank ~= b.simRank then
            if a.simRank and b.simRank then return a.simRank < b.simRank end
            return a.simRank ~= nil
        end
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
