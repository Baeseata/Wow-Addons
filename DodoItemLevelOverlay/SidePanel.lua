-- DodoItemLevelOverlay - SidePanel.lua
-- Gear summary panel docked to the right side of the character
-- frame. One row per equipment slot:
--   [slot] [stat grid] [ilvl] [item name][enchant] ... [sockets]
--
-- - slot:      localized slot abbreviation (same words as the bags)
-- - stat grid: fixed four-column grid (vers / haste / mastery /
--              crit), a column lights up when the item has that
--              secondary stat
-- - ilvl:      gradient colored, same ramp as everywhere else
-- - name:      localized by the game client, quality colored
-- - enchant:   hugs the end of the item name; green when enchanted
--              (Death Knight runeforges count), red when an
--              enchantable slot is empty, hidden on slots that take
--              no enchant this season. Mouse over a green tag to see
--              the actual enchant line from the item tooltip.
-- - sockets:   right-packed, exactly as many icons as the item has
--              sockets: gem icons for filled ones, a bright empty
--              socket for unfilled ones, plus a dim outline on slots
--              that could take a jewelbinder socket but have none
--
-- The panel matches the character frame height; rows spread evenly.

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

-- Row geometry (x offsets from the row left edge).
local NAME_X       = 122 -- where the item name column starts
local SOCKET_STEP  = 15  -- horizontal spacing between socket icons
local ENCH_RESERVE = 30  -- room kept for the enchant tag after the name
local MAX_SOCKETS  = 4   -- display cap; matches the gem fields in a link

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
    local slotID = self.slotID
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local line = GetEnchantTooltipLine(slotID)
    if line then
        GameTooltip:SetText(line, 0.3, 1.0, 0.3, 1, true)
    else
        -- fallback: the full item tooltip still shows the enchant
        GameTooltip:SetInventoryItem("player", slotID)
    end
    GameTooltip:Show()
end

local function OnEnchantLeave()
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
    row:SetSize(cfg.PANEL_WIDTH - 12, 18) -- height assigned by LayoutRows

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

    -- four-column secondary stat grid; center-anchored with natural
    -- width so two-letter labels never get truncated to "..."
    row.stats = {}
    for i = 1, #STAT_ORDER do
        local fs = NewText("CENTER")
        fs:SetPoint("CENTER", row, "LEFT", 32 + (i - 1) * 15, 0)
        row.stats[i] = fs
    end

    -- item level
    row.ilvl = NewText("RIGHT")
    row.ilvl:SetPoint("LEFT", row, "LEFT", 88, 0)
    row.ilvl:SetWidth(28)

    -- item name; width set per refresh so the enchant tag and the
    -- socket icons get exactly the room they need
    row.name = NewText("LEFT")
    row.name:SetPoint("LEFT", row, "LEFT", NAME_X, 0)
    row.name:SetWidth(100)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    if row.name.SetMaxLines then row.name:SetMaxLines(1) end

    -- enchant tag, re-anchored to the end of the name text on every
    -- refresh; the overlay frame provides the mouseover tooltip
    row.ench = NewText("LEFT")
    row.ench:SetPoint("LEFT", row, "LEFT", NAME_X, 0)

    row.enchHit = CreateFrame("Frame", nil, row)
    row.enchHit.slotID = slotInfo.id
    row.enchHit:SetAllPoints(row.ench)
    row.enchHit:SetScript("OnEnter", OnEnchantEnter)
    row.enchHit:SetScript("OnLeave", OnEnchantLeave)
    row.enchHit:EnableMouse(false)

    -- socket icons, right-packed (index 1 is the rightmost)
    row.sockets = {}
    for i = 1, MAX_SOCKETS do
        local tex = row:CreateTexture(nil, "OVERLAY")
        tex:SetSize(13, 13)
        tex:SetPoint("RIGHT", row, "RIGHT", -(i - 1) * SOCKET_STEP, 0)
        row.sockets[i] = tex
    end

    return row
end

-- Spread the rows evenly over the panel's current height.
local function LayoutRows()
    if not panel or not rows then return end
    local height = panel:GetHeight()
    if not height or height <= 0 then return end

    local pad = 10
    local rowHeight = (height - pad * 2) / #rows
    for i, row in ipairs(rows) do
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 6,
            -pad - (i - 1) * rowHeight)
    end
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
    row.enchHit:EnableMouse(false)
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

    -- sockets: only as many icons as the item actually has. The
    -- EMPTY_SOCKET_* stats report the item's total socket count
    -- (filled or not), so subtract the filled gems to get the
    -- genuinely empty ones.
    local enchantID, gems = ParseItemLink(itemLink)
    local totalSockets = CountTemplateSockets(stats)
    local emptyCount = math.max(0, totalSockets - #gems)

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
    for _ = 1, emptyCount do
        if shown >= MAX_SOCKETS then break end
        shown = shown + 1
        local tex = row.sockets[shown]
        tex:SetTexture(EMPTY_SOCKET_TEXTURE)
        tex:SetAlpha(1)
        tex:Show()
    end
    if shown == 0 and cfg.SOCKETABLE_SLOTS[slotID] then
        shown = 1
        local tex = row.sockets[1]
        tex:SetTexture(EMPTY_SOCKET_TEXTURE)
        tex:SetAlpha(0.3)
        tex:Show()
    end

    -- item name in the client language, quality colored; sized so
    -- the enchant tag and the shown sockets get exactly their room
    local enchantable = IsEnchantableSlot(slotID, itemLink)
    local socketsWidth = shown * SOCKET_STEP
    local nameWidth = row:GetWidth() - NAME_X - socketsWidth
        - (enchantable and ENCH_RESERVE or 4)
    if nameWidth < 40 then nameWidth = 40 end
    row.name:SetWidth(nameWidth)

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

    -- enchant tag hugging the end of the visible name text
    if enchantable then
        local enchanted = enchantID and enchantID ~= "" and enchantID ~= "0"
        local c = enchanted and cfg.ENCHANT_OK_COLOR or cfg.ENCHANT_MISSING_COLOR
        local textWidth = row.name:GetStringWidth() or 0
        local offset = math.min(textWidth, nameWidth) + 6

        ns.SetOverlayFont(row.ench, cfg.PANEL_FONT_SIZE, "OUTLINE")
        row.ench:ClearAllPoints()
        row.ench:SetPoint("LEFT", row.name, "LEFT", offset, 0)
        row.ench:SetText((ns.L and ns.L.enchant) or "EN")
        row.ench:SetTextColor(c[1], c[2], c[3], c[4])
        row.ench:Show()

        -- tooltip only when there is an enchant to describe
        row.enchHit:EnableMouse(enchanted and true or false)
    end
end

------------------------------------------------------------------
-- Panel lifecycle
------------------------------------------------------------------

function ns.SetupSidePanel()
    if panel or not ns.Config.PANEL_ENABLED then return end
    if not CharacterFrame then return end

    local cfg = ns.Config

    panel = CreateFrame("Frame", "DodoItemLevelOverlaySidePanel",
        CharacterFrame, "BackdropTemplate")
    panel:SetWidth(cfg.PANEL_WIDTH)
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
            LayoutRows()
            ns.UpdateSidePanel()
        end)
    end)
end

function ns.UpdateSidePanel()
    if not panel or not panel:IsShown() then return end
    for _, row in ipairs(rows) do
        UpdateRow(row)
    end
end
