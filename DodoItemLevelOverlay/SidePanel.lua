-- DodoItemLevelOverlay - SidePanel.lua
-- Gear summary panel docked to the right side of the character
-- frame. One row per equipment slot:
--   [slot] [stat grid] [ilvl] [item name] [enchant] [sockets]
--
-- - slot:      localized slot abbreviation (same words as the bags)
-- - stat grid: fixed four-column grid (vers / haste / mastery /
--              crit), a column lights up when the item has that
--              secondary stat
-- - ilvl:      gradient colored, same ramp as everywhere else
-- - name:      localized by the game client, quality colored
-- - enchant:   green tag when enchanted (Death Knight runeforges
--              count), red tag when an enchantable slot is empty,
--              nothing on slots that take no enchant this season
-- - sockets:   gem icons for filled sockets, a bright empty socket
--              for unfilled ones, and a dim outline on slots that
--              could take a socket but have none yet

local _, ns = ...

-- Inventory slot IDs in display order, with the inventory type key
-- used to look up the localized slot abbreviation.
local SLOTS = {
    { id = 1,  key = "INVTYPE_HEAD" },
    { id = 2,  key = "INVTYPE_NECK" },
    { id = 3,  key = "INVTYPE_SHOULDER" },
    { id = 15, key = "INVTYPE_CLOAK" },
    { id = 5,  key = "INVTYPE_CHEST" },
    { id = 9,  key = "INVTYPE_WRIST" },
    { id = 10, key = "INVTYPE_HAND" },
    { id = 6,  key = "INVTYPE_WAIST" },
    { id = 7,  key = "INVTYPE_LEGS" },
    { id = 8,  key = "INVTYPE_FEET" },
    { id = 11, key = "INVTYPE_FINGER" },
    { id = 12, key = "INVTYPE_FINGER" },
    { id = 13, key = "INVTYPE_TRINKET" },
    { id = 14, key = "INVTYPE_TRINKET" },
    { id = 16, key = "INVTYPE_WEAPONMAINHAND" },
    { id = 17, key = "INVTYPE_WEAPONOFFHAND" },
}

local STAT_ORDER = { "versatility", "haste", "mastery", "crit" }
local STAT_KEYS = {
    versatility = "ITEM_MOD_VERSATILITY",
    haste       = "ITEM_MOD_HASTE_RATING_SHORT",
    mastery     = "ITEM_MOD_MASTERY_RATING_SHORT",
    crit        = "ITEM_MOD_CRIT_RATING_SHORT",
}

local MAX_SOCKETS = 3
local EMPTY_SOCKET_TEXTURE = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic"

local panel, rows

-- Off-hand weapons take enchants; shields and held-in-off-hand
-- items do not.
local OFFHAND_WEAPON_LOCS = {
    INVTYPE_WEAPON         = true,
    INVTYPE_WEAPONOFFHAND  = true,
    INVTYPE_2HWEAPON       = true,
}

local function IsEnchantableSlot(slotID, itemLink)
    if ns.Config.ENCHANTABLE_SLOTS[slotID] then return true end
    if slotID == 17 and itemLink then
        local _, _, _, equipLoc = GetItemInfoInstant(itemLink)
        return OFFHAND_WEAPON_LOCS[equipLoc] or false
    end
    return false
end

-- Returns the enchant ID string (may be empty) and an array of
-- socketed gem item IDs from an item link.
local function ParseItemLink(itemLink)
    local itemString = itemLink:match("item:([^|]+)")
    if not itemString then return nil, {} end
    local parts = { strsplit(":", itemString) }
    local enchantID = parts[2]
    local gems = {}
    for i = 3, 6 do
        local gem = parts[i]
        if gem and gem ~= "" and gem ~= "0" then
            gems[#gems + 1] = tonumber(gem)
        end
    end
    return enchantID, gems
end

local function GetStatsTable(itemLink)
    if C_Item and type(C_Item.GetItemStats) == "function" then
        return C_Item.GetItemStats(itemLink)
    end
    if type(GetItemStats) == "function" then
        return GetItemStats(itemLink)
    end
    return nil
end

local function CountEmptySockets(stats)
    if not stats then return 0 end
    local count = 0
    for key, value in pairs(stats) do
        if key:find("EMPTY_SOCKET", 1, true) then
            count = count + (tonumber(value) or 0)
        end
    end
    return count
end

------------------------------------------------------------------
-- Row construction
------------------------------------------------------------------

local function CreateRow(parent, index, slotInfo)
    local cfg = ns.Config
    local row = CreateFrame("Frame", nil, parent)
    row.slotID = slotInfo.id
    row.slotKey = slotInfo.key
    row:SetSize(cfg.PANEL_WIDTH - 12, cfg.PANEL_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 6,
        -10 - (index - 1) * cfg.PANEL_ROW_HEIGHT)

    local function NewText(justify)
        local fs = row:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, cfg.PANEL_FONT_SIZE, "OUTLINE")
        fs:SetJustifyH(justify)
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
        return fs
    end

    -- slot abbreviation
    row.slot = NewText("LEFT")
    row.slot:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.slot:SetWidth(24)
    row.slot:SetTextColor(0.25, 0.85, 0.85, 1)

    -- four-column secondary stat grid
    row.stats = {}
    for i = 1, #STAT_ORDER do
        local fs = NewText("CENTER")
        fs:SetPoint("LEFT", row, "LEFT", 26 + (i - 1) * 15, 0)
        fs:SetWidth(15)
        row.stats[i] = fs
    end

    -- item level
    row.ilvl = NewText("RIGHT")
    row.ilvl:SetPoint("LEFT", row, "LEFT", 88, 0)
    row.ilvl:SetWidth(28)

    -- enchant state tag (right side, before the sockets)
    row.ench = NewText("RIGHT")
    row.ench:SetPoint("RIGHT", row, "RIGHT", -(MAX_SOCKETS * 15 + 2), 0)
    row.ench:SetWidth(22)

    -- socket icons
    row.sockets = {}
    for i = 1, MAX_SOCKETS do
        local tex = row:CreateTexture(nil, "OVERLAY")
        tex:SetSize(13, 13)
        tex:SetPoint("RIGHT", row, "RIGHT", -(MAX_SOCKETS - i) * 15, 0)
        row.sockets[i] = tex
    end

    -- item name, quality colored, clipped between ilvl and enchant
    row.name = NewText("LEFT")
    row.name:SetPoint("LEFT", row, "LEFT", 122, 0)
    row.name:SetPoint("RIGHT", row.ench, "LEFT", -4, 0)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    if row.name.SetMaxLines then row.name:SetMaxLines(1) end

    return row
end

------------------------------------------------------------------
-- Row refresh
------------------------------------------------------------------

local function UpdateRow(row)
    local cfg = ns.Config
    local slotID = row.slotID

    ns.SetOverlayFont(row.slot, cfg.PANEL_FONT_SIZE, "OUTLINE")
    row.slot:SetText((ns.L and ns.L.slots[row.slotKey]) or "")

    for i = 1, #STAT_ORDER do row.stats[i]:Hide() end
    row.ench:Hide()
    for i = 1, MAX_SOCKETS do row.sockets[i]:Hide() end

    local itemLink = GetInventoryItemLink("player", slotID)
    if not itemLink then
        row.ilvl:SetText("")
        row.name:SetText("")
        return
    end

    -- item level, gradient colored
    local itemLoc = ItemLocation:CreateFromEquipmentSlot(slotID)
    local ilvl = ns.GetItemLevel(itemLoc)
    if ilvl then
        local r, g, b = ns.ColorForItemLevel(ilvl)
        ns.SetOverlayFont(row.ilvl, cfg.PANEL_FONT_SIZE, "OUTLINE")
        row.ilvl:SetTextColor(r, g, b, 1)
        row.ilvl:SetText(tostring(ilvl))
    else
        row.ilvl:SetText("")
    end

    -- item name in the client language, quality colored; uncached
    -- items refresh via GET_ITEM_INFO_RECEIVED
    local name, _, quality = C_Item.GetItemInfo(itemLink)
    ns.SetOverlayFont(row.name, cfg.PANEL_FONT_SIZE, "OUTLINE")
    if name then
        local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if qc then
            row.name:SetTextColor(qc.r, qc.g, qc.b, 1)
        else
            row.name:SetTextColor(1, 1, 1, 1)
        end
        row.name:SetText(name)
    else
        row.name:SetTextColor(0.6, 0.6, 0.6, 1)
        row.name:SetText("...")
    end

    -- secondary stat grid
    local stats = GetStatsTable(itemLink)
    if stats then
        for i, statKey in ipairs(STAT_ORDER) do
            if stats[STAT_KEYS[statKey]] then
                local fs = row.stats[i]
                local c = cfg.STAT_COLORS[statKey]
                ns.SetOverlayFont(fs, cfg.PANEL_FONT_SIZE, "OUTLINE")
                fs:SetText((ns.L and ns.L.stats[statKey]) or "")
                fs:SetTextColor(c[1], c[2], c[3], c[4])
                fs:Show()
            end
        end
    end

    -- enchant state
    local enchantID, gems = ParseItemLink(itemLink)
    if IsEnchantableSlot(slotID, itemLink) then
        local enchanted = enchantID and enchantID ~= "" and enchantID ~= "0"
        local c = enchanted and cfg.ENCHANT_OK_COLOR or cfg.ENCHANT_MISSING_COLOR
        ns.SetOverlayFont(row.ench, cfg.PANEL_FONT_SIZE, "OUTLINE")
        row.ench:SetText((ns.L and ns.L.enchant) or "EN")
        row.ench:SetTextColor(c[1], c[2], c[3], c[4])
        row.ench:Show()
    end

    -- sockets: filled gems, then bright empty sockets, then a dim
    -- outline on slots that could be socketed but have no socket
    local shown = 0
    for _, gemID in ipairs(gems) do
        if shown >= MAX_SOCKETS then break end
        shown = shown + 1
        local tex = row.sockets[shown]
        local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(gemID)
        tex:SetTexture(icon or EMPTY_SOCKET_TEXTURE)
        tex:SetAlpha(1)
        tex:Show()
    end
    for _ = 1, CountEmptySockets(stats) do
        if shown >= MAX_SOCKETS then break end
        shown = shown + 1
        local tex = row.sockets[shown]
        tex:SetTexture(EMPTY_SOCKET_TEXTURE)
        tex:SetAlpha(1)
        tex:Show()
    end
    if shown == 0 and cfg.SOCKETABLE_SLOTS[slotID] then
        local tex = row.sockets[1]
        tex:SetTexture(EMPTY_SOCKET_TEXTURE)
        tex:SetAlpha(0.3)
        tex:Show()
    end
end

------------------------------------------------------------------
-- Panel lifecycle
------------------------------------------------------------------

function ns.SetupSidePanel()
    if panel or not ns.Config.PANEL_ENABLED then return end
    if not CharacterFrame then return end

    local cfg = ns.Config
    local height = #SLOTS * cfg.PANEL_ROW_HEIGHT + 20

    panel = CreateFrame("Frame", "DodoItemLevelOverlaySidePanel",
        CharacterFrame, "BackdropTemplate")
    panel:SetSize(cfg.PANEL_WIDTH, height)
    panel:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 2, 0)
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    rows = {}
    for index, slotInfo in ipairs(SLOTS) do
        rows[index] = CreateRow(panel, index, slotInfo)
    end

    panel:SetScript("OnShow", function()
        C_Timer.After(0, ns.UpdateSidePanel)
    end)
end

function ns.UpdateSidePanel()
    if not panel or not panel:IsShown() then return end
    for _, row in ipairs(rows) do
        UpdateRow(row)
    end
end
