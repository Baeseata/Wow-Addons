-- DodoInspect - BIS.lua
-- Best-in-slot comparison window, shown to the right of the item
-- tooltip when the mouse is over a gear name in the character side
-- panel (SidePanel.lua calls ns.ShowBISForSlot / ns.HideBIS).
--
-- For the player's current spec it answers, per slot, two questions
-- independently: is the equipped item the raid BiS, and is it the M+
-- BiS. When it is not, it names the BiS item and where it drops.
--
-- Data: ns.BIS (Data/BIS.lua, generated from Archon.gg). Item names
-- and the drop source (instance + boss) are resolved in game from the
-- item id and the Encounter Journal, so they come out in the client
-- language and never need to ship in the addon.
--
-- Only the PLAYER's own equipped items are read here, so unlike
-- TargetInfo this file never touches secret values.

local _, ns = ...

------------------------------------------------------------------
-- Colors / icons
------------------------------------------------------------------
local C_GOLD  = "|cffffd100"
local C_GREEN = "|cff46d369"
local C_RED   = "|cffff5555"
local C_GRAY  = "|cff9d9d9d"
local C_OFF   = "|r"
local TICK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
local CROSS = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t"

local function HexFromRGB(r, g, b)
    return string.format("|cff%02x%02x%02x",
        math.floor((r or 1) * 255 + 0.5),
        math.floor((g or 1) * 255 + 0.5),
        math.floor((b or 1) * 255 + 0.5))
end

------------------------------------------------------------------
-- Spec + data lookup
------------------------------------------------------------------
-- Current spec id and localized name (12.0-preferred API, with the
-- still-present globals as a fallback). Returns nil outside a spec.
local function GetPlayerSpec()
    local idx
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        idx = C_SpecializationInfo.GetSpecialization()
    elseif GetSpecialization then
        idx = GetSpecialization()
    end
    if not idx or idx < 1 then return nil end
    local id, name
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
        id, name = C_SpecializationInfo.GetSpecializationInfo(idx)
    elseif GetSpecializationInfo then
        id, name = GetSpecializationInfo(idx)
    end
    return id, name
end

-- Rings (11/12) and trinkets (13/14) share one BiS pair; every other
-- slot is keyed by its inventory slot id. Returns the list of BiS
-- item ids for a slot in one content type, or nil when none is known.
local FINGER  = { [11] = true, [12] = true }
local TRINKET = { [13] = true, [14] = true }

local function BisListFor(slots, slotID)
    if not slots then return nil end
    if FINGER[slotID]  then return slots.finger end
    if TRINKET[slotID] then return slots.trinket end
    local id = slots[slotID]
    if id then return { id } end
    return nil
end

local function Contains(list, id)
    if not list or not id then return false end
    for i = 1, #list do
        if list[i] == id then return true end
    end
    return false
end

-- Quality-colored item name for an item id (may be uncached the first
-- time it is seen; we ask the client to load it and show a placeholder
-- so the next hover is complete).
local function ColoredItemName(itemID)
    if not itemID then return "?" end
    local name, _, quality = C_Item.GetItemInfo(itemID)
    if not name then
        if C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return C_GRAY .. "..." .. C_OFF
    end
    local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
    local hex = qc and (qc.hex or HexFromRGB(qc.r, qc.g, qc.b)) or "|cffffffff"
    if hex:sub(1, 2) ~= "|c" then hex = "|c" .. hex end
    return hex .. name .. C_OFF
end

------------------------------------------------------------------
-- Drop source via the Encounter Journal (lazy, fault-tolerant)
------------------------------------------------------------------
-- itemID -> { instance = name, boss = name, isRaid = bool }. Built once,
-- shortly after login (and lazily on first hover as a fallback).
local sourceBuilt, sourceMap = false, {}

-- Map every loot item of one journal instance to its boss. Isolated and
-- called through pcall per instance so a single instance that errors out
-- (some old tiers misbehave) cannot abort the whole scan -- that was the
-- partial-scan bug that left most items without a source.
-- One boss's loot table -> sourceMap. pcall'd per encounter by the
-- caller so a single boss that errors out cannot abort the rest of the
-- instance (which previously hid every item from later bosses).
local function ScanEncounter(encounterID, instName, encName, isRaid)
    EJ_SelectEncounter(encounterID)
    local num = EJ_GetNumLoot() or 0
    for l = 1, num do
        local info = C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex
            and C_EncounterJournal.GetLootInfoByIndex(l)
        local iid = info and (info.itemID
            or (info.link and tonumber(info.link:match("item:(%d+)"))))
        if iid and not sourceMap[iid] then
            sourceMap[iid] = { instance = instName, boss = encName, isRaid = isRaid }
        end
    end
end

local function ScanInstance(instanceID, instName, isRaid)
    EJ_SelectInstance(instanceID)
    local e = 1
    while true do
        local encName, _, encounterID = EJ_GetEncounterInfoByIndex(e, instanceID)
        if not encName then break end
        if encounterID then
            pcall(ScanEncounter, encounterID, instName, encName, isRaid)
        end
        e = e + 1
    end
end

-- Walk EVERY tier's raids and dungeons (newest first so current sources
-- win ties). EJ_GetCurrentTier() proved unreliable -- it returned a
-- Classic tier, so the current Midnight raids were never scanned. Our BiS
-- itemIDs are current, so they only match current instances regardless.
local function BuildSourceMap()
    if sourceBuilt then return end
    sourceBuilt = true
    pcall(function()
        if C_AddOns and C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
        end
        if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex
            and EJ_SelectInstance and EJ_GetEncounterInfoByIndex
            and EJ_SelectEncounter and EJ_GetNumLoot) then return end

        local numTiers = EJ_GetNumTiers() or 0

        -- Pass 1, unfiltered: everything the journal lists directly --
        -- rings, trinkets, neck, non-set armor, and all dungeon loot.
        if EJ_ResetLootFilter then pcall(EJ_ResetLootFilter) end
        for tier = numTiers, 1, -1 do
            EJ_SelectTier(tier)
            for _, isRaid in ipairs({ false, true }) do
                local i = 1
                while true do
                    local instanceID, instName = EJ_GetInstanceByIndex(i, isRaid)
                    if not instanceID then break end
                    pcall(ScanInstance, instanceID, instName, isRaid)
                    i = i + 1
                end
            end
        end

        -- Pass 2, filtered to the player's class + spec: the loot-spec view
        -- resolves cross-class tier TOKENS into the actual class SET PIECES,
        -- so head/shoulder/chest/hands/legs map to their boss (same-slot
        -- tokens drop from a fixed boss this patch). Raids only; additive,
        -- so it only fills gaps pass 1 left, never removes a source.
        local _, _, classID = UnitClass("player")
        local specID = GetPlayerSpec()
        if EJ_SetLootFilter and classID and specID then
            pcall(EJ_SetLootFilter, classID, specID)
            for tier = numTiers, 1, -1 do
                EJ_SelectTier(tier)
                local i = 1
                while true do
                    local instanceID, instName = EJ_GetInstanceByIndex(i, true)
                    if not instanceID then break end
                    pcall(ScanInstance, instanceID, instName, true)
                    i = i + 1
                end
            end
            if EJ_ResetLootFilter then pcall(EJ_ResetLootFilter) end
        end
    end)
end

-- Localized "where it drops" string for a BiS item, or nil. Raid drops
-- show the boss; dungeon drops show only the dungeon (per design).
local function GetSourceText(itemID)
    BuildSourceMap()
    local s = sourceMap[itemID]
    if s then
        if s.isRaid and s.boss then
            return s.instance .. " - " .. s.boss
        end
        return s.instance
    end
    -- no boss source (tier from vault/catalyst, crafted necks, world...):
    -- fall back to the coarse hint baked from the item's Archon icon
    local hint = ns.BIS_SRC and ns.BIS_SRC[itemID]
    local labels = ns.L and ns.L.bis and ns.L.bis.src
    if hint and labels then
        return labels[hint] or labels.other
    end
    return nil
end

------------------------------------------------------------------
-- Window
------------------------------------------------------------------
local PAD, LINE_FS, LINE_STEP = 10, 14, 5
local frame

local function EnsureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "DodoInspectBISFrame", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
    frame:SetBackdropBorderColor(0.50, 0.45, 0.20, 1)
    frame.lines = {}
    return frame
end

local function GetLine(f, i)
    local fs = f.lines[i]
    if not fs then
        fs = f:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, LINE_FS, "OUTLINE")
        fs:SetJustifyH("LEFT")
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
        f.lines[i] = fs
    end
    return fs
end

-- Render an array of plain (already color-coded) strings, size the
-- frame to fit and dock it to the right of the anchoring tooltip.
local function Render(f, lines, anchor)
    local maxw, y = 0, -PAD
    for i, text in ipairs(lines) do
        local fs = GetLine(f, i)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
        fs:SetText(text)
        fs:SetTextColor(1, 1, 1, 1)
        fs:Show()
        local w = fs:GetStringWidth()
        if w > maxw then maxw = w end
        y = y - (LINE_FS + LINE_STEP)
    end
    for i = #lines + 1, #f.lines do f.lines[i]:Hide() end
    f:SetWidth(maxw + PAD * 2)
    f:SetHeight(-y + PAD - LINE_STEP)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
end

-- Build the two content lines (raid, then M+) for one slot.
local function BuildContentLines(lines, label, slots, slotID, equipped)
    local list = BisListFor(slots, slotID)
    if not list or #list == 0 then return end -- e.g. off-hand on a 2H spec

    if equipped and Contains(list, equipped) then
        local row = label .. "  " .. TICK .. " " .. C_GREEN .. ns.L.bis.isBis .. C_OFF
        local ilvl = ns.GetItemLevel(ItemLocation:CreateFromEquipmentSlot(slotID))
        if ilvl then
            local r, g, b = ns.ColorForItemLevel(ilvl)
            row = row .. "  " .. HexFromRGB(r, g, b) .. ilvl .. C_OFF
        end
        lines[#lines + 1] = row
    else
        lines[#lines + 1] = label .. "  " .. CROSS .. " " .. C_RED .. ns.L.bis.notBis .. C_OFF
        local names = {}
        for i = 1, #list do names[i] = ColoredItemName(list[i]) end
        lines[#lines + 1] = "   " .. C_GRAY .. ns.L.bis.bisLabel .. C_OFF .. " " .. table.concat(names, C_GRAY .. " / " .. C_OFF)
        -- source line for every BiS item that resolves (rings/trinkets
        -- are a pair, so there can be two), deduped
        local srcs, seen = {}, {}
        for i = 1, #list do
            local s = GetSourceText(list[i])
            if s and not seen[s] then
                seen[s] = true
                srcs[#srcs + 1] = s
            end
        end
        if #srcs > 0 then
            lines[#lines + 1] = "   " .. C_GRAY .. ns.L.bis.srcLabel .. " " .. table.concat(srcs, " / ") .. C_OFF
        end
    end
end

function ns.ShowBISForSlot(slotID, anchor)
    if not ns.IsEnabled("showBIS") then return end
    if not (ns.BIS and ns.L and ns.L.bis and anchor) then return end

    local specID, specName = GetPlayerSpec()
    local specData = specID and ns.BIS[specID]

    local lines = { C_GOLD .. ns.L.bis.title .. C_OFF
        .. (specName and ("  " .. C_GRAY .. specName .. C_OFF) or "") }

    if not specData then
        lines[#lines + 1] = C_GRAY .. ns.L.bis.noData .. C_OFF
    else
        local equipped = GetInventoryItemID("player", slotID)
        local before = #lines
        BuildContentLines(lines, ns.L.bis.raid,  specData.raid,  slotID, equipped)
        BuildContentLines(lines, ns.L.bis.mplus, specData.mplus, slotID, equipped)
        if #lines == before then return end -- nothing known for this slot
    end

    local f = EnsureFrame()
    Render(f, lines, anchor)
    f:Show()
end

function ns.HideBIS()
    if frame then frame:Hide() end
end

-- Pre-build the source map a few seconds after login so the first hover
-- already has sources. The lazy BuildSourceMap call inside GetSourceText
-- still covers the case where a hover happens before this fires.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    C_Timer.After(5, function() pcall(BuildSourceMap) end)
end)

-- Diagnostic: /run DodoInspectBISDebug()  -- reports the source-map size
-- and a few sample resolutions so any source-line gaps can be pinned down.
function DodoInspectBISDebug()
    BuildSourceMap()
    local n = 0
    for _ in pairs(sourceMap) do n = n + 1 end
    print(("DodoInspect BIS: %d items mapped, EJ tiers=%s"):format(
        n, tostring(EJ_GetNumTiers and EJ_GetNumTiers())))
    local specID, specName = GetPlayerSpec()
    print(("  spec=%s %s, hasData=%s"):format(
        tostring(specID), tostring(specName),
        tostring(ns.BIS and ns.BIS[specID] ~= nil)))
    local sd = specID and ns.BIS and ns.BIS[specID]
    if sd then
        for _, c in ipairs({ "raid", "mplus" }) do
            for _, sid in ipairs({ 1, 3, 5, 7, 10, 2, 6, 11, 13 }) do
                local list = BisListFor(sd[c], sid)
                if list and list[1] then
                    print(("  %s slot %d: bis=%d src=%s"):format(
                        c, sid, list[1], tostring(GetSourceText(list[1]))))
                end
            end
        end
    end
end

-- Diagnostic: /run DodoInspectBISDumpRaid()  -- lists, per current-raid
-- boss, the head/shoulder/chest/hands/legs items and any tokens (equipLoc
-- ""), so we can see whether bosses drop set PIECES or cross-class TOKENS.
function DodoInspectBISDumpRaid()
    pcall(function()
        if C_AddOns and C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
        end
        local numTiers = EJ_GetNumTiers() or 0
        print("numTiers=" .. numTiers .. " (scanning newest tier raids for tokens)")
        EJ_SelectTier(numTiers)
        local shownFields = false
        local i = 1
        while true do
            local instanceID, instName = EJ_GetInstanceByIndex(i, true)
            if not instanceID then break end
            print("RAID: " .. tostring(instName))
            EJ_SelectInstance(instanceID)
            local e = 1
            while true do
                local encName, _, encounterID = EJ_GetEncounterInfoByIndex(e, instanceID)
                if not encName then break end
                if encounterID then
                    EJ_SelectEncounter(encounterID)
                    local num = EJ_GetNumLoot() or 0
                    for l = 1, num do
                        local info = C_EncounterJournal.GetLootInfoByIndex(l)
                        local iid = info and info.itemID
                        if iid then
                            local _, _, _, equipLoc = GetItemInfoInstant(iid)
                            if equipLoc == "" then
                                if not shownFields then
                                    shownFields = true
                                    local ks = {}
                                    for k, v in pairs(info) do
                                        ks[#ks + 1] = k .. "=" .. tostring(v)
                                    end
                                    print("TOKEN FIELDS: " .. table.concat(ks, ", "))
                                end
                                print(("  %s | %d %s | slot=%s armor=%s"):format(
                                    encName, iid, tostring(info.name),
                                    tostring(info.slot), tostring(info.armorType)))
                            end
                        end
                    end
                end
                e = e + 1
            end
            i = i + 1
        end
    end)
end
