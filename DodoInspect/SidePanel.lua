-- DodoInspect - SidePanel.lua
-- Gear summary panel docked to the right side of the character
-- frame. One row per equipment slot, in fixed columns:
--   [slot] [stat grid] [ilvl] [item name] [enchant] [sockets]
--
-- - slot:      localized slot abbreviation (same words as the bags)
-- - stat grid: fixed four-column grid (vers / haste / mastery /
--              crit); a column lights up when the item has that
--              secondary stat, and the dominant stat (strictly
--              higher than the others) gets an underline
-- - ilvl:      gradient colored, same ramp as everywhere else
-- - name:      localized by the game client, quality colored, fixed
--              width with clipping; mouse over for the full tooltip
-- - enchant:   fixed column so the tags align vertically; green when
--              enchanted (Death Knight runeforges count), red when
--              an enchantable slot is empty, hidden on slots that
--              take no enchant this season. Mouse over a green tag
--              to see the actual enchant line.
-- - sockets:   fixed column after the enchant tag, exactly as many
--              icons as the item actually has sockets; mouse over a
--              gem for its tooltip
--
-- Rows are packed tight (row height follows the font size) and the
-- block is vertically centered; the panel height matches the
-- character frame and the width derives from the column layout.
-- The empty off-hand row is hidden entirely.

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

-- Sockets the layout reserves room for; rare items with more will
-- overflow to the right.
local SOCKET_COLUMNS = 2
local MAX_SOCKETS = 4 -- render cap, matches the gem fields in a link
local EMPTY_SOCKET_TEXTURE = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic"

-- Row geometry derived from the font size so the whole layout
-- scales when PANEL_FONT_SIZE changes.
local FS
local SLOT_W, STAT_X, STAT_STEP, ILVL_X, ILVL_W, NAME_X
local NAME_W, ENCH_X, ENCH_W, SOCKET_X
local SOCKET_SIZE, SOCKET_STEP, ROW_H, PANEL_W

local function ComputeGeometry()
    FS          = ns.Config.PANEL_FONT_SIZE
    SLOT_W      = math.floor(FS * 2.0)
    STAT_X      = SLOT_W + math.floor(FS * 0.7)
    STAT_STEP   = math.floor(FS * 1.6)
    ILVL_X      = STAT_X + STAT_STEP * 3 + math.floor(FS * 0.9)
    ILVL_W      = math.floor(FS * 2.2)
    NAME_X      = ILVL_X + ILVL_W + math.floor(FS * 0.5)
    NAME_W      = ns.Config.PANEL_NAME_WIDTH
    ENCH_X      = NAME_X + NAME_W + math.floor(FS * 0.45)
    ENCH_W      = math.floor(FS * 1.5)
    SOCKET_SIZE = FS - 1
    SOCKET_STEP = SOCKET_SIZE + 2
    SOCKET_X    = ENCH_X + ENCH_W + 4
    ROW_H       = FS + 8
    PANEL_W     = SOCKET_X + SOCKET_COLUMNS * SOCKET_STEP + 12
end

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

-- Despite the key names, EMPTY_SOCKET_* entries report the sockets
-- the item HAS (filled or not), so this is the total socket count.
local function CountTemplateSockets(stats)
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
-- Tooltips
------------------------------------------------------------------

-- The localized "Enchanted: ..." line from the equipped item's
-- tooltip, or nil (Death Knight runeforges may format differently;
-- the caller falls back to the full item tooltip).
local enchantLinePattern
local function GetEnchantTooltipLine(slotID)
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
    local data = C_TooltipInfo.GetInventoryItem("player", slotID)
    if not data or not data.lines then return nil end

    if not enchantLinePattern and type(ENCHANTED_TOOLTIP_LINE) == "string" then
        local p = ENCHANTED_TOOLTIP_LINE:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        enchantLinePattern = "^" .. p:gsub("%%%%s", "(.+)")
    end
    if not enchantLinePattern then return nil end

    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and text:match(enchantLinePattern) then
            return text
        end
    end
    return nil
end

local function OnEnchantEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    local line = GetEnchantTooltipLine(self.slotID)
    if line then
        GameTooltip:SetText(line, 0.3, 1.0, 0.3, 1, true)
    else
        -- fallback: the full item tooltip still shows the enchant
        GameTooltip:SetInventoryItem("player", self.slotID)
    end
    GameTooltip:Show()
end

local function OnNameEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetInventoryItem("player", self.slotID)
    GameTooltip:Show()
end

local function OnSocketEnter(self)
    if not self.gemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetItemByID(self.gemID)
    GameTooltip:Show()
end

local function OnHitLeave()
    GameTooltip:Hide()
end

------------------------------------------------------------------
-- Row construction
------------------------------------------------------------------

local function CreateRow(parent, slotInfo)
    local cfg = ns.Config
    local row = CreateFrame("Frame", nil, parent)
    row.slotID = slotInfo.id
    row.slotKey = slotInfo.key
    row:SetSize(PANEL_W - 12, ROW_H)

    local function NewText(justify)
        local fs = row:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, FS, "OUTLINE")
        fs:SetJustifyH(justify)
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
        return fs
    end

    local function NewHit(onEnter)
        local hit = CreateFrame("Frame", nil, row)
        hit.slotID = slotInfo.id
        hit:SetScript("OnEnter", onEnter)
        hit:SetScript("OnLeave", OnHitLeave)
        hit:EnableMouse(false)
        return hit
    end

    -- slot abbreviation
    row.slot = NewText("LEFT")
    row.slot:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.slot:SetWidth(SLOT_W)
    row.slot:SetTextColor(0.25, 0.85, 0.85, 1)

    -- four-column secondary stat grid; center-anchored with natural
    -- width so the labels never get truncated. Each label has an
    -- underline texture shown when it is the item's dominant stat.
    row.stats = {}
    row.statLines = {}
    for i = 1, #STAT_ORDER do
        local fs = NewText("CENTER")
        fs:SetPoint("CENTER", row, "LEFT", STAT_X + (i - 1) * STAT_STEP, 0)
        row.stats[i] = fs

        local line = row:CreateTexture(nil, "OVERLAY")
        line:SetHeight(2)
        line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, 1)
        line:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, 1)
        line:Hide()
        row.statLines[i] = line
    end

    -- item level
    row.ilvl = NewText("RIGHT")
    row.ilvl:SetPoint("LEFT", row, "LEFT", ILVL_X, 0)
    row.ilvl:SetWidth(ILVL_W)

    -- item name, fixed width, clipped to a single line
    row.name = NewText("LEFT")
    row.name:SetPoint("LEFT", row, "LEFT", NAME_X, 0)
    row.name:SetWidth(NAME_W)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    if row.name.SetMaxLines then row.name:SetMaxLines(1) end

    row.nameHit = NewHit(OnNameEnter)
    row.nameHit:SetAllPoints(row.name)

    -- enchant tag, fixed column
    row.ench = NewText("LEFT")
    row.ench:SetPoint("LEFT", row, "LEFT", ENCH_X, 0)

    row.enchHit = NewHit(OnEnchantEnter)
    row.enchHit:SetAllPoints(row.ench)

    -- socket icons, fixed column, each with a hover frame
    row.sockets = {}
    row.socketHits = {}
    for i = 1, MAX_SOCKETS do
        local tex = row:CreateTexture(nil, "OVERLAY")
        tex:SetSize(SOCKET_SIZE, SOCKET_SIZE)
        tex:SetPoint("LEFT", row, "LEFT", SOCKET_X + (i - 1) * SOCKET_STEP, 0)
        row.sockets[i] = tex

        local hit = NewHit(OnSocketEnter)
        hit:SetAllPoints(tex)
        row.socketHits[i] = hit
    end

    return row
end

-- Pack the visible rows tightly and center the block vertically;
-- on very short frames fall back to an even spread.
local function LayoutRows()
    if not panel or not rows then return end
    local height = panel:GetHeight()
    if not height or height <= 0 then return end

    local shownRows = {}
    for _, row in ipairs(rows) do
        if row.shown ~= false then shownRows[#shownRows + 1] = row end
    end
    local count = #shownRows
    if count == 0 then return end

    local pad = 8
    local rowHeight = math.min((height - pad * 2) / count, ROW_H)
    local top = (height - rowHeight * count) / 2
    for i, row in ipairs(shownRows) do
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 6,
            -top - (i - 1) * rowHeight)
    end
end

------------------------------------------------------------------
-- Row refresh
------------------------------------------------------------------

local function UpdateRow(row)
    local cfg = ns.Config
    local slotID = row.slotID

    ns.SetOverlayFont(row.slot, FS, "OUTLINE")
    row.slot:SetText((ns.L and ns.L.slots[row.slotKey]) or "")

    for i = 1, #STAT_ORDER do
        row.stats[i]:Hide()
        row.statLines[i]:Hide()
    end
    row.ench:Hide()
    row.enchHit:EnableMouse(false)
    row.nameHit:EnableMouse(false)
    for i = 1, MAX_SOCKETS do
        row.sockets[i]:Hide()
        row.socketHits[i]:EnableMouse(false)
        row.socketHits[i].gemID = nil
    end

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
        ns.SetOverlayFont(row.ilvl, FS, "OUTLINE")
        row.ilvl:SetTextColor(r, g, b, 1)
        row.ilvl:SetText(tostring(ilvl))
    else
        row.ilvl:SetText("")
    end

    -- secondary stat grid with dominant-stat underline. The "big"
    -- stat is the strictly greatest one; ties mean no underline.
    local stats = GetStatsTable(itemLink)
    if stats then
        local maxKey, maxVal, tie = nil, 0, false
        for _, statKey in ipairs(STAT_ORDER) do
            local v = stats[STAT_KEYS[statKey]]
            if type(v) == "number" and v > 0 then
                if v > maxVal then
                    maxVal, maxKey, tie = v, statKey, false
                elseif v == maxVal then
                    tie = true
                end
            end
        end
        if tie then maxKey = nil end

        for i, statKey in ipairs(STAT_ORDER) do
            if stats[STAT_KEYS[statKey]] then
                local fs = row.stats[i]
                local c = cfg.STAT_COLORS[statKey]
                ns.SetOverlayFont(fs, FS, "OUTLINE")
                fs:SetText((ns.L and ns.L.stats[statKey]) or "")
                fs:SetTextColor(c[1], c[2], c[3], c[4])
                fs:Show()
                if statKey == maxKey then
                    local line = row.statLines[i]
                    line:SetColorTexture(c[1], c[2], c[3], 0.9)
                    line:Show()
                end
            end
        end
    end

    -- item name in the client language, quality colored
    local name, _, quality = C_Item.GetItemInfo(itemLink)
    ns.SetOverlayFont(row.name, FS, "OUTLINE")
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
    row.nameHit:EnableMouse(true)

    -- enchant tag in its fixed column
    local enchantID, gems = ParseItemLink(itemLink)
    if IsEnchantableSlot(slotID, itemLink) then
        local enchanted = enchantID and enchantID ~= "" and enchantID ~= "0"
        local c = enchanted and cfg.ENCHANT_OK_COLOR or cfg.ENCHANT_MISSING_COLOR
        ns.SetOverlayFont(row.ench, FS, "OUTLINE")
        row.ench:SetText((ns.L and ns.L.enchant) or "EN")
        row.ench:SetTextColor(c[1], c[2], c[3], c[4])
        row.ench:Show()
        row.enchHit:EnableMouse(enchanted and true or false)
    end

    -- sockets in their fixed column: filled gems first, then the
    -- genuinely empty sockets (EMPTY_SOCKET_* stats report the
    -- item's total socket count, so subtract the filled gems)
    local emptyCount = math.max(0, CountTemplateSockets(stats) - #gems)
    local shown = 0
    for _, gemID in ipairs(gems) do
        if shown >= MAX_SOCKETS then break end
        shown = shown + 1
        local tex = row.sockets[shown]
        local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(gemID)
        tex:SetTexture(icon or EMPTY_SOCKET_TEXTURE)
        tex:Show()
        row.socketHits[shown].gemID = gemID
        row.socketHits[shown]:EnableMouse(true)
    end
    for _ = 1, emptyCount do
        if shown >= MAX_SOCKETS then break end
        shown = shown + 1
        local tex = row.sockets[shown]
        tex:SetTexture(EMPTY_SOCKET_TEXTURE)
        tex:Show()
    end
end

------------------------------------------------------------------
-- Panel lifecycle
------------------------------------------------------------------

function ns.SetupSidePanel()
    if panel or not ns.Config.PANEL_ENABLED then return end
    if not CharacterFrame then return end

    ComputeGeometry()

    panel = CreateFrame("Frame", "DodoInspectSidePanel",
        CharacterFrame, "BackdropTemplate")
    panel:SetWidth(PANEL_W)
    -- match the character frame height exactly
    panel:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 2, 0)
    panel:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMRIGHT", 2, 0)
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
        rows[index] = CreateRow(panel, slotInfo)
    end

    LayoutRows()
    panel:SetScript("OnSizeChanged", LayoutRows)
    panel:SetScript("OnShow", function()
        C_Timer.After(0, function()
            ns.UpdateSidePanel()
        end)
    end)
end

function ns.UpdateSidePanel()
    if not panel or not panel:IsShown() then return end

    for _, row in ipairs(rows) do
        -- hide the off-hand row entirely when nothing is equipped
        local visible = true
        if row.slotID == 17 and not GetInventoryItemLink("player", 17) then
            visible = false
        end
        row.shown = visible
        if visible then
            row:Show()
            UpdateRow(row)
        else
            row:Hide()
        end
    end

    LayoutRows()
end
