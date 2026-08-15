-- DodoInspect - StatPriorityConfig.lua
-- Player-authored overrides for the stat priority line, plus the window
-- that edits them. The shipped guidance in Data/StatPriority.lua stays
-- the default; anything the player saves here wins for that exact
-- (specID, hero tree) pair and nothing else.
--
-- Why the key is spec X hero tree: the shipped data is already split
-- that way (Blood DK's two trees disagree completely), so a single
-- per-spec override would flatten a distinction the defaults make. It
-- also makes the inspect case fall out for free -- look the VIEWED
-- unit's (spec, tree) up in this table, use it when it is there. Same
-- spec and tree gets your setting, a different tree gets the default,
-- and there is never a need to ask "is this me".
--
-- Specs the player has NOT touched store nothing at all. That is what
-- makes "your setting survives an addon update" and "untouched specs
-- follow the updated data" both true: absence means read the defaults.
--
-- This file stays ASCII. All display strings come from ns.L.

local _, ns = ...

local SCHEMA_VERSION = 1
local NO_TREE = 0

local STAT_KEYS = { "crit", "haste", "mastery", "versatility" }
local VALID_STAT = {
    crit = true, haste = true, mastery = true, versatility = true,
}
ns.CUSTOM_STAT_KEYS = STAT_KEYS

------------------------------------------------------------------
-- Storage
------------------------------------------------------------------

-- Hero tree ids arrive from C_Traits by way of ns.InspectHeroSubTree.
-- That data is documented as non-secret for inspectable units, but this
-- addon has already been burned once by treating an audit conclusion as
-- an invariant (see the fourth landmine in CLAUDE.md), and the guard is
-- free. issecretvalue leads because type() reports "number" for a
-- secret and the throw would land on the comparison below it.
local function TreeKey(subTreeID)
    if issecretvalue and issecretvalue(subTreeID) then return NO_TREE end
    if type(subTreeID) ~= "number" then return NO_TREE end
    if subTreeID <= 0 then return NO_TREE end
    return subTreeID
end
ns.StatPriorityTreeKey = TreeKey

-- The saved-variables root, created on demand. Returns nil before the
-- DB exists (ADDON_LOADED has not fired), which reads as "no overrides".
local function Root(create)
    local db = DodoInspectDB
    if not db then return nil end
    local root = db.statPriorityCustom
    if not root then
        if not create then return nil end
        root = { version = SCHEMA_VERSION, specs = {} }
        db.statPriorityCustom = root
    end
    root.specs = root.specs or {}
    return root
end

-- The player's override for one (spec, tree), or nil. Shaped like an
-- entry in Data/StatPriority.lua so StatPriority's Resolve can hand it
-- straight to the renderer: `raid` is required, `mythic` optional.
function ns.StatPriorityCustomFor(specID, subTreeID)
    if type(specID) ~= "number" then return nil end
    local root = Root(false)
    if not root then return nil end
    local bySpec = root.specs[specID]
    if not bySpec then return nil end
    local entry = bySpec[TreeKey(subTreeID)]
    if type(entry) ~= "table" or type(entry.raid) ~= "table" then return nil end
    return entry
end

-- Does this spec have any override at all, on any tree? Used by the
-- window's "copy to the other hero talents" affordance.
function ns.StatPriorityCustomTrees(specID)
    local root = Root(false)
    if not root or type(specID) ~= "number" then return nil end
    return root.specs[specID]
end

function ns.SaveStatPriorityCustom(specID, subTreeID, entry)
    if type(specID) ~= "number" or type(entry) ~= "table" then return false end
    if type(entry.raid) ~= "table" then return false end
    local root = Root(true)
    if not root then return false end
    root.specs[specID] = root.specs[specID] or {}
    root.specs[specID][TreeKey(subTreeID)] = entry
    return true
end

-- Restore defaults == forget. Deleting the key is what puts this
-- (spec, tree) back on the shipped data permanently, including future
-- updates to it; a "copy of the current default" would freeze instead.
function ns.ClearStatPriorityCustom(specID, subTreeID)
    local root = Root(false)
    if not root or type(specID) ~= "number" then return false end
    local bySpec = root.specs[specID]
    if not bySpec then return false end
    local key = TreeKey(subTreeID)
    if bySpec[key] == nil then return false end
    bySpec[key] = nil
    if next(bySpec) == nil then root.specs[specID] = nil end
    return true
end

------------------------------------------------------------------
-- Order shape
------------------------------------------------------------------

-- Validate and tidy an order produced by the window: elements are stat
-- keys or tie-group sub-arrays, and all four secondaries appear exactly
-- once between them. Returns the cleaned order, or nil when the input
-- could not be one -- callers must not save a nil.
--
-- Tidying is not cosmetic. A one-element tie group renders as a group
-- and a zero-element one renders as a stray separator, so both are
-- collapsed here rather than in the renderer, which is shared with the
-- shipped data and has no business knowing about half-built input.
function ns.NormalizeStatOrder(order)
    if type(order) ~= "table" then return nil end
    local seen, out = {}, {}
    for _, element in ipairs(order) do
        if type(element) == "string" then
            if not VALID_STAT[element] or seen[element] then return nil end
            seen[element] = true
            out[#out + 1] = element
        elseif type(element) == "table" then
            local group = {}
            for _, key in ipairs(element) do
                if type(key) ~= "string" then return nil end
                if not VALID_STAT[key] or seen[key] then return nil end
                seen[key] = true
                group[#group + 1] = key
            end
            if #group == 1 then
                out[#out + 1] = group[1]
            elseif #group > 1 then
                out[#out + 1] = group
            end
        else
            return nil
        end
    end
    for _, key in ipairs(STAT_KEYS) do
        if not seen[key] then return nil end
    end
    return out
end

-- Flatten an order to a plain stat list plus the tie flags between
-- neighbours: flat[i] is a stat key, tied[i] is true when flat[i] and
-- flat[i+1] sit in the same tie group. This is the shape the window
-- edits (four rows, three relation toggles); BuildOrder below is its
-- exact inverse, and the round trip is asserted in the offline test.
function ns.FlattenStatOrder(order)
    local flat, tied = {}, {}
    if type(order) ~= "table" then return flat, tied end
    for _, element in ipairs(order) do
        if type(element) == "table" then
            for index, key in ipairs(element) do
                flat[#flat + 1] = key
                if index < #element then tied[#flat] = true end
            end
        else
            flat[#flat + 1] = element
        end
    end
    return flat, tied
end

-- Inverse of FlattenStatOrder: rebuild the nested order from the flat
-- list and the tie flags.
function ns.BuildStatOrder(flat, tied)
    local out = {}
    if type(flat) ~= "table" then return out end
    local index = 1
    while index <= #flat do
        local last = index
        while tied and tied[last] and last < #flat do last = last + 1 end
        if last == index then
            out[#out + 1] = flat[index]
        else
            local group = {}
            for i = index, last do group[#group + 1] = flat[i] end
            out[#out + 1] = group
        end
        index = last + 1
    end
    return out
end

------------------------------------------------------------------
-- Seeding a fresh override from the shipped data
------------------------------------------------------------------

-- Deep copy, because everything below seeds from Data/StatPriority.lua
-- and that table is shared, live and NOT ours to write into. Storing a
-- reference would mean the first edit in the window silently rewrites
-- the shipped defaults for the rest of the session -- and "restore
-- defaults" would then restore the edit.
local function CopyOrder(order)
    local out = {}
    if type(order) ~= "table" then return out end
    for _, element in ipairs(order) do
        if type(element) == "table" then
            local group = {}
            for _, key in ipairs(element) do group[#group + 1] = key end
            out[#out + 1] = group
        else
            out[#out + 1] = element
        end
    end
    return out
end
ns.CopyStatOrder = CopyOrder

-- Neutral order for specs the shipped data does not cover (or that are
-- marked stale). Character-sheet order, so it reads as "nothing is
-- claimed here" rather than as advice.
local function NeutralOrder()
    local out = {}
    for _, key in ipairs(STAT_KEYS) do out[#out + 1] = key end
    return out
end

-- Translate one shipped goal into the shape this file stores:
--
--   goals[content][statKey] = { unit = "percent"|"rating",
--                               min = <number>, max = <number> }
--
-- One unit per STAT, not per bound. The window shows a single unit
-- switch per row, and a stored shape that could disagree with that
-- ("min in percent, max in rating") would be a difference nothing on
-- screen could express.
--
-- The shipped goals were written to be READ, not edited, so they carry
-- five shapes; this is the only place that knows about them. A bare
-- "target ~N" becomes a MINIMUM -- that guidance means "get this stat
-- up to N", and the sources only ever phrase a ceiling as "at most".
local function SeedGoal(goal, into)
    local stat = goal and goal.stat
    if not stat or not VALID_STAT[stat] then return end
    -- Percentage-flavoured guidance is SKIPPED, not carried over. With
    -- the unit gone from the window, seeding a 23 into a box that sits
    -- in the same column as rating targets of 1600 is not less
    -- information -- it is wrong information. An empty box the player
    -- fills in themselves is the honest version.
    if goal.unit == "percent" then return end
    local slot = into[stat] or {}
    into[stat] = slot
    if goal.min and goal.max then
        slot.min, slot.max = goal.min, goal.max
    elseif goal.max then
        slot.max = goal.max
    elseif goal.value then
        slot.min = goal.value
    end
end

local function SeedGoalSet(goals)
    local out = {}
    if type(goals) ~= "table" then return out end
    for _, goal in ipairs(goals) do SeedGoal(goal, out) end
    return out
end

-- A fresh override pre-filled from whatever the addon currently ships
-- for this (spec, tree): the orders, and the rough targets when that
-- spec has any. This is what the window opens on, and what "restore
-- defaults" resets the window to before the entry is deleted.
function ns.DefaultStatPriorityEntry(specID, subTreeID)
    local data, specData
    if ns.StatPriorityDefault then
        data, specData = ns.StatPriorityDefault(specID, subTreeID)
    end
    local raid = data and data.raid
    local entry = {
        raid = raid and CopyOrder(raid) or NeutralOrder(),
        mythic = CopyOrder((data and (data.mythic or data.raid)) or NeutralOrder()),
        goals = { raid = {}, mythic = {} },
    }

    -- goalBuilds is keyed by hero tree and replaces the flat goals when
    -- present; ns.StatPriorityGoalData already resolves that choice.
    local goalData
    if ns.StatPriorityGoalData then
        goalData = ns.StatPriorityGoalData(specData, subTreeID)
    end
    if goalData then
        if goalData.goals then
            entry.goals.raid = SeedGoalSet(goalData.goals)
            entry.goals.mythic = SeedGoalSet(goalData.goals)
        elseif goalData.contentGoals then
            entry.goals.raid = SeedGoalSet(goalData.contentGoals.raid)
            entry.goals.mythic = SeedGoalSet(goalData.contentGoals.mythic)
        end
    end
    return entry
end

-- Full copy of an override. Needed by "copy to the other hero talents":
-- storing the same table under several tree keys would make the trees
-- share one order, so editing any of them would edit all of them --
-- exactly the flattening that keying by tree exists to avoid.
function ns.CopyStatPriorityEntry(entry)
    if type(entry) ~= "table" then return nil end
    local out = {
        raid = CopyOrder(entry.raid),
        mythic = CopyOrder(entry.mythic),
        goals = { raid = {}, mythic = {} },
    }
    for _, content in ipairs({ "raid", "mythic" }) do
        local source = entry.goals and entry.goals[content]
        if type(source) == "table" then
            for stat, bounds in pairs(source) do
                if type(bounds) == "table" then
                    out.goals[content][stat] = {
                        unit = bounds.unit,
                        min = bounds.min,
                        max = bounds.max,
                    }
                end
            end
        end
    end
    return out
end

------------------------------------------------------------------
-- No percent <-> rating conversion. This is deliberate.
------------------------------------------------------------------
--
-- 1.13.0 shipped with one, then it was pulled the same day (owner's
-- call, after seeing it on screen: "the numbers might not be right --
-- let the player work it out, we don't do the arithmetic").
--
-- The arithmetic itself was not wrong; the CLAIM was too broad. The
-- scale is GetCombatRatingBonus(cr) / GetCombatRating(cr) -- Blizzard's
-- own paper doll derives every secondary that way -- with mastery
-- needing the spec coefficient from GetMasteryEffect's SECOND return
-- value on top. What that answers is "what percentage do these rating
-- points buy", which is NOT the number on the character sheet: that one
-- also carries base values and auras, and haste stacks multiplicatively
-- on top. A player reading "20% = 5800" would stack to 5800 and see 23%.
--
-- The unit briefly survived as a label the player could switch. That
-- went too (owner's call, same session): the row is now just a stat and
-- two numbers, and what those numbers mean is the player's business.
--
-- Recording the formula here rather than keeping an uncalled function
-- around -- a green test standing behind a feature nobody uses is worse
-- than a comment, and this is the part that was expensive to find.

-- Display form of a stored target. With no unit to render, this only
-- decides decimals: a rating target of 1600 must not come back as
-- "1600.0", and a typed 20.5 must not be rounded away behind the
-- player's back.
function ns.FormatStatTarget(value)
    if type(value) ~= "number" then return "" end
    if math.abs(value - math.floor(value + 0.5)) < 0.05 then
        return tostring(math.floor(value + 0.5))
    end
    return string.format("%.1f", value)
end

------------------------------------------------------------------
-- The editor window
------------------------------------------------------------------

-- Everything below is UI and is not reachable from the offline test
-- (it needs real frames). The rules it edits all live above this line
-- for exactly that reason -- ordering, seeding and conversion are
-- testable, and this file's job down here is only to drive them.

-- Now driven by the widest thing left, which is the pair of buttons
-- along the bottom -- the target rows are just a label and two boxes.
-- It has come down twice: 430 with a conversion cell, 320 without it,
-- and now this once the unit buttons went too.
local WINDOW_W = 290
local PAD = 12
local ROW_H = 22
local HEADER_H = 46

-- Shared by the target rows and their column headers. Two hand-written
-- copies of these offsets would drift the moment one side is nudged.
local GOAL_LABEL_W = 96
local GOAL_BOX_W = 60
local GOAL_GAP = 8

local cfg
local editing = { specID = nil, subTreeID = nil, heroName = nil,
                  content = "raid", entry = nil, dirty = false }

local function L(key, fallback)
    local t = ns.L
    local value = t and t[key]
    if type(value) == "string" and value ~= "" then return value end
    return fallback
end

local function StatLabel(statKey)
    local names = ns.L and ns.L.statNames
    return (names and names[statKey]) or statKey
end

local function StatColorHex(statKey)
    local c = ns.Config and ns.Config.STAT_COLORS
        and ns.Config.STAT_COLORS[statKey]
    if not c then return "ffffff" end
    return string.format("%02x%02x%02x",
        math.floor(c[1] * 255 + 0.5),
        math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

-- Persist the working copy. Called after every edit rather than behind
-- an Apply button, because every other setting in this addon takes
-- effect as you change it and a lone Apply here would be the odd one.
local function Commit()
    if not editing.entry or not editing.specID then return end
    editing.entry.raid = ns.NormalizeStatOrder(editing.entry.raid)
        or editing.entry.raid
    editing.entry.mythic = ns.NormalizeStatOrder(editing.entry.mythic)
        or editing.entry.mythic
    ns.SaveStatPriorityCustom(editing.specID, editing.subTreeID, editing.entry)
    editing.dirty = true
    if ns.UpdateSidePanel then ns.UpdateSidePanel() end
    if ns.UpdateInspectPanel then ns.UpdateInspectPanel() end
    if ns.RefreshGearPanelIfShown then ns.RefreshGearPanelIfShown() end
end

local Refresh -- forward declaration; the row handlers below call it

-- The order currently being edited, as the flat list + tie flags the
-- rows work in. Kept as a pair of locals rather than re-derived on
-- every click so a drag of several moves stays stable.
local function CurrentOrder()
    if not editing.entry then return {}, {} end
    local order = (editing.content == "mythic") and editing.entry.mythic
        or editing.entry.raid
    return ns.FlattenStatOrder(order)
end

local function StoreOrder(flat, tied)
    if not editing.entry then return end
    local order = ns.BuildStatOrder(flat, tied)
    if editing.content == "mythic" then
        editing.entry.mythic = order
    else
        editing.entry.raid = order
    end
    Commit()
    Refresh()
end

-- Swap a stat with its neighbour. The tie flags belong to the GAPS, not
-- to the stats, so they are rebuilt from the moved list rather than
-- carried along -- carrying them would make a stat drag its "=" across
-- a boundary it no longer sits on.
local function MoveStat(index, delta)
    local flat, tied = CurrentOrder()
    local target = index + delta
    if target < 1 or target > #flat then return end
    flat[index], flat[target] = flat[target], flat[index]
    StoreOrder(flat, tied)
end

local function ToggleTie(index)
    local flat, tied = CurrentOrder()
    if index < 1 or index >= #flat then return end
    tied[index] = not tied[index] or nil
    StoreOrder(flat, tied)
end

local function CreateOrderRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WINDOW_W - PAD * 2, ROW_H)

    row.up = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.up:SetSize(20, 18)
    row.up:SetText("^")
    row.up:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.up:SetScript("OnClick", function() MoveStat(index, -1) end)

    row.down = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.down:SetSize(20, 18)
    row.down:SetText("v")
    row.down:SetPoint("LEFT", row.up, "RIGHT", 2, 0)
    row.down:SetScript("OnClick", function() MoveStat(index, 1) end)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.label:SetPoint("LEFT", row.down, "RIGHT", 8, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWidth(150)

    -- The relation to the row BELOW, so the last row never has one.
    row.rel = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.rel:SetSize(26, 18)
    row.rel:SetPoint("LEFT", row.label, "RIGHT", 4, 0)
    row.rel:SetScript("OnClick", function() ToggleTie(index) end)

    return row
end

------------------------------------------------------------------
-- Targets
------------------------------------------------------------------

local function CurrentGoals()
    if not editing.entry then return {} end
    editing.entry.goals = editing.entry.goals or {}
    local key = (editing.content == "mythic") and "mythic" or "raid"
    editing.entry.goals[key] = editing.entry.goals[key] or {}
    return editing.entry.goals[key]
end

-- Returns value, cleared. An empty box means "remove this bound", which
-- has to be distinguishable from "that was not a number" -- otherwise
-- clearing a field would silently keep the old target.
local function ParseInput(text)
    if type(text) ~= "string" then return nil, false end
    text = text:gsub("%%", ""):gsub("%s+", "")
    if text == "" then return nil, true end
    local value = tonumber(text)
    if not value or value < 0 then return nil, false end
    return value, false
end

local function SetBound(statKey, which, value, cleared)
    local goals = CurrentGoals()
    local bounds = goals[statKey]
    if cleared then
        if not bounds then return end
        bounds[which] = nil
        -- Drop the whole row once neither bound is set, so an emptied
        -- target does not linger as an empty table in saved variables.
        if bounds.min == nil and bounds.max == nil then
            goals[statKey] = nil
        end
    elseif value then
        bounds = bounds or {}
        goals[statKey] = bounds
        bounds[which] = value
    else
        return -- unparseable: leave the stored value alone
    end
    Commit()
    Refresh()
end

local function CreateGoalRow(parent, statKey)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WINDOW_W - PAD * 2, ROW_H)
    row.statKey = statKey

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetWidth(GOAL_LABEL_W)
    row.label:SetJustifyH("LEFT")
    if row.label.SetWordWrap then row.label:SetWordWrap(false) end

    local function NewBox(which, anchorTo, dx)
        local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        box:SetSize(GOAL_BOX_W, 18)
        box:SetPoint("LEFT", anchorTo, "RIGHT", dx, 0)
        box:SetAutoFocus(false)
        box:SetMaxLetters(8)
        box:SetJustifyH("CENTER")
        -- ClearFocus fires OnEditFocusLost, which is bound to this same
        -- handler -- without the latch, committing with Enter would run
        -- the whole save-and-refresh twice.
        local function Apply(self)
            if self.applying then return end
            self.applying = true
            local value, cleared = ParseInput(self:GetText())
            self:ClearFocus()
            SetBound(statKey, which, value, cleared)
            self.applying = false
        end
        box:SetScript("OnEnterPressed", Apply)
        box:SetScript("OnEditFocusLost", Apply)
        box:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            Refresh()
        end)
        return box
    end

    row.min = NewBox("min", row.label, GOAL_GAP)
    row.max = NewBox("max", row.min, GOAL_GAP)

    return row
end

------------------------------------------------------------------
-- Window
------------------------------------------------------------------

-- Which hero trees this spec has. Defaults to the player's active
-- config and spec, which is the only thing this window ever edits.
-- MayReturnNothing per the API docs, hence the type check.
local function HeroTreesForPlayerSpec()
    if not (C_ClassTalents and C_ClassTalents.GetHeroTalentSpecsForClassSpec) then
        return nil
    end
    local ok, ids = pcall(C_ClassTalents.GetHeroTalentSpecsForClassSpec, nil, nil)
    if not ok or type(ids) ~= "table" or #ids == 0 then return nil end
    return ids
end

local function CopyToOtherTrees()
    if not editing.entry or not editing.specID then return end
    local trees = HeroTreesForPlayerSpec()
    if not trees then return end
    local here = ns.StatPriorityTreeKey(editing.subTreeID)
    for _, subTreeID in ipairs(trees) do
        if ns.StatPriorityTreeKey(subTreeID) ~= here then
            ns.SaveStatPriorityCustom(editing.specID, subTreeID,
                ns.CopyStatPriorityEntry(editing.entry))
        end
    end
    Commit()
    Refresh()
end

local function ResetToDefaults()
    if not editing.specID then return end
    ns.ClearStatPriorityCustom(editing.specID, editing.subTreeID)
    -- The window stays open on a fresh seed of the shipped data, which
    -- is now what the panel shows too. Nothing is written back until the
    -- next edit -- that absence is what keeps this spec following future
    -- updates to the shipped guidance.
    editing.entry = ns.DefaultStatPriorityEntry(editing.specID, editing.subTreeID)
    editing.dirty = false
    if ns.UpdateSidePanel then ns.UpdateSidePanel() end
    if ns.UpdateInspectPanel then ns.UpdateInspectPanel() end
    if ns.RefreshGearPanelIfShown then ns.RefreshGearPanelIfShown() end
    Refresh()
end

local function BuildWindow()
    if cfg then return cfg end

    local f = CreateFrame("Frame", "DodoInspectStatPriorityConfig",
        UIParent, "BackdropTemplate")
    f:SetSize(WINDOW_W, 312)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -10)

    -- Which hero tree this override belongs to, stated on screen rather
    -- than implied: the same spec on another tree opens on the defaults,
    -- and without this line that reads as the setting having been lost.
    f.tree = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.tree:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)

    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    f.close:SetScript("OnClick", function() ns.CloseStatPriorityConfig() end)

    -- Same control the candidate window uses, because it selects the
    -- same thing there.
    f.content = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.content:SetSize(56, 20)
    f.content:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -10)
    f.content:SetScript("OnClick", function()
        editing.content = (editing.content == "raid") and "mythic" or "raid"
        Refresh()
    end)

    f.orderRows = {}
    for index = 1, 4 do
        local row = CreateOrderRow(f, index)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD,
            -(HEADER_H + (index - 1) * ROW_H))
        f.orderRows[index] = row
    end

    local sepY = HEADER_H + 4 * ROW_H + 4
    f.sep = f:CreateTexture(nil, "OVERLAY")
    f.sep:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    f.sep:SetHeight(1)
    f.sep:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -sepY)
    f.sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -sepY)

    -- Column headers over the two boxes. Positions come from the shared
    -- GOAL_* constants the rows use, so they cannot drift apart. (These
    -- were built but never given any text in the first cut -- the
    -- target block shipped with a blank strip above it.)
    local headY = sepY + 6
    local minX = PAD + GOAL_LABEL_W + GOAL_GAP
    local maxX = minX + GOAL_BOX_W + GOAL_GAP

    f.minHead = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.minHead:SetPoint("TOPLEFT", f, "TOPLEFT", minX, -headY)
    f.minHead:SetWidth(GOAL_BOX_W)
    f.minHead:SetJustifyH("CENTER")

    f.maxHead = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.maxHead:SetPoint("TOPLEFT", f, "TOPLEFT", maxX, -headY)
    f.maxHead:SetWidth(GOAL_BOX_W)
    f.maxHead:SetJustifyH("CENTER")

    -- Target rows keep the character-sheet order no matter how the
    -- priority above is arranged. A ceiling on Haste is a fact about
    -- Haste, and having it jump around while the priority is being
    -- dragged would make both halves harder to read.
    f.goalRows = {}
    local goalTop = sepY + 22
    for index, statKey in ipairs(STAT_KEYS) do
        local row = CreateGoalRow(f, statKey)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD,
            -(goalTop + (index - 1) * ROW_H))
        f.goalRows[index] = row
    end

    local noteY = goalTop + 4 * ROW_H + 6

    f.treeNote = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.treeNote:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -noteY)
    f.treeNote:SetWidth(WINDOW_W - PAD * 2)
    f.treeNote:SetJustifyH("LEFT")
    if f.treeNote.SetWordWrap then f.treeNote:SetWordWrap(false) end
    if f.treeNote.SetMaxLines then f.treeNote:SetMaxLines(1) end

    f.reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.reset:SetSize(110, 22)
    f.reset:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
    f.reset:SetScript("OnClick", ResetToDefaults)

    f.copy = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.copy:SetSize(140, 22)
    f.copy:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    f.copy:SetScript("OnClick", CopyToOtherTrees)

    cfg = f
    return f
end

-- Assigns to the local declared near the top of the UI section.
function Refresh()
    if not cfg then return end

    cfg.title:SetText(L("priCfgTitle", "Stat Priority"))
    if editing.heroName then
        cfg.tree:SetText(string.format(
            L("priCfgTree", "Hero talent: %s"), editing.heroName))
    else
        cfg.tree:SetText(L("priCfgNoTree", "No hero talent selected"))
    end
    cfg.content:SetText(editing.content == "raid"
        and L("priRaid", "Raid") or L("priMythic", "M+"))

    local flat, tied = CurrentOrder()
    for index, row in ipairs(cfg.orderRows) do
        local statKey = flat[index]
        row:SetShown(statKey ~= nil)
        if statKey then
            row.label:SetText(string.format("|cff%s%s|r",
                StatColorHex(statKey), StatLabel(statKey)))
            row.up:SetEnabled(index > 1)
            row.down:SetEnabled(index < #flat)
            row.rel:SetShown(index < #flat)
            if index < #flat then
                row.rel:SetText(tied[index] and "=" or ">")
            end
        end
    end

    local goals = CurrentGoals()
    for _, row in ipairs(cfg.goalRows) do
        local bounds = goals[row.statKey]
        row.label:SetText(string.format("|cff%s%s|r",
            StatColorHex(row.statKey), StatLabel(row.statKey)))
        row.min:SetText(bounds and bounds.min
            and ns.FormatStatTarget(bounds.min) or "")
        row.max:SetText(bounds and bounds.max
            and ns.FormatStatTarget(bounds.max) or "")
    end

    cfg.minHead:SetText(L("priCfgMin", "Min"))
    cfg.maxHead:SetText(L("priCfgMax", "Max"))
    cfg.treeNote:SetText(L("priCfgTreeNote", ""))
    cfg.reset:SetText(L("priCfgReset", "Restore defaults"))
    cfg.copy:SetText(L("priCfgCopy", "Copy to other hero talents"))
    -- Hidden rather than disabled when there is no other tree to copy
    -- to: a greyed button invites the question "why not", and the answer
    -- here is simply that this spec has nowhere else to put it.
    local trees = HeroTreesForPlayerSpec()
    cfg.copy:SetShown(trees ~= nil and #trees > 1)
end

function ns.CloseStatPriorityConfig()
    editing.specID, editing.subTreeID, editing.heroName = nil, nil, nil
    editing.entry, editing.dirty = nil, false
    if cfg then cfg:Hide() end
end

-- Open the editor for one (spec, hero tree), or close it when it is
-- already showing that exact pair.
function ns.ToggleStatPriorityConfig(specID, subTreeID, heroName)
    if not ns.StatPriorityActive or not ns.StatPriorityActive() then return end
    if type(specID) ~= "number" then return end

    if cfg and cfg:IsShown() and editing.specID == specID
        and ns.StatPriorityTreeKey(editing.subTreeID)
            == ns.StatPriorityTreeKey(subTreeID) then
        ns.CloseStatPriorityConfig()
        return
    end

    editing.specID = specID
    editing.subTreeID = subTreeID
    editing.heroName = heroName
    -- Opens on whichever content the candidate panel is showing, so the
    -- two windows agree about what is being looked at. Read, not
    -- written: switching here must not silently re-sort that panel.
    editing.content = (ns.GearPanelContent and ns.GearPanelContent()) or "raid"

    -- The existing override, or a working copy seeded from the shipped
    -- data. The seed is deliberately NOT saved here -- an override comes
    -- into existence only once the player changes something, and that
    -- absence is what keeps untouched specs following future updates.
    local saved = ns.StatPriorityCustomFor(specID, subTreeID)
    editing.entry = (saved and ns.CopyStatPriorityEntry(saved))
        or ns.DefaultStatPriorityEntry(specID, subTreeID)
    editing.dirty = (saved ~= nil)

    BuildWindow()
    -- Hooked once, here rather than at login, because the window is
    -- built lazily and there is nothing to close before that.
    if not cfg.hookedCharacterFrame and CharacterFrame
        and CharacterFrame.HookScript then
        CharacterFrame:HookScript("OnHide", ns.CloseStatPriorityConfig)
        cfg.hookedCharacterFrame = true
    end
    cfg:Show()
    Refresh()
end

-- Spec changes invalidate what is on screen outright; entering or
-- leaving combat only changes whether the conversion can be read, which
-- the cells and the note line report.
local watcher = CreateFrame("Frame")
watcher:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        ns.CloseStatPriorityConfig()
    elseif cfg and cfg:IsShown() then
        Refresh()
    end
end)
