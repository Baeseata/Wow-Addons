-- DodoInspect - GearPanel.lua
-- The docked window that lists this season's candidates for one slot,
-- ranked by how well their secondary stats match the viewed character's
-- stat priority.
--
-- Opened by clicking a slot label in either side panel, docks to the
-- right of whichever panel opened it, and closes with the character
-- frame. One instance is shared: clicking another slot swaps the
-- contents, clicking the same slot again closes it.
--
-- NOT a best-in-slot list, and the header says so. See GearRank.lua.
--
-- SECRET VALUES: this panel is reachable from InspectPanel, whose unit
-- token follows your target and can therefore be an enemy player. Spec
-- lookups go through ns.InspectSpecID, which guards; the equipped-item
-- lookup guards here. Nothing else in this file touches unit data.

local _, ns = ...

local panel
local state = { slotKey = nil, unit = nil, anchor = nil, slotID = nil }

-- Crafted-gear slots. Wrist and back are where the season's embellished
-- crafts land, because they carry the smallest stat budget and so cost
-- the least to hand over. The panel says so rather than confidently
-- ranking drops that are not the real answer for those slots.
local CRAFTED_SLOTS = {
    INVTYPE_WRIST = true,
    INVTYPE_CLOAK = true,
}

local function Colored(text, color)
    if not color then return text end
    return string.format("|cff%02x%02x%02x%s|r",
                         math.floor(color[1] * 255),
                         math.floor(color[2] * 255),
                         math.floor(color[3] * 255), text)
end

-- "71% Haste / 29% Crit" using the same abbreviations and colors the
-- stat grid already uses, so the two panels read as one tool.
local function StatSummary(entry)
    local firstStat, firstValue = entry[5], entry[6]
    if not firstStat then return nil end
    local secondStat, secondValue = entry[7], entry[8]
    local total = (firstValue or 0) + (secondValue or 0)
    if total <= 0 then return nil end

    local labels = ns.L and ns.L.stats or {}
    local colors = ns.Config.STAT_COLORS or {}
    local parts = {
        Colored(string.format("%d%% %s",
                              math.floor((firstValue / total) * 100 + 0.5),
                              labels[firstStat] or firstStat),
                colors[firstStat]),
    }
    if secondStat then
        parts[#parts + 1] = Colored(
            string.format("%d%% %s",
                          math.floor((secondValue / total) * 100 + 0.5),
                          labels[secondStat] or secondStat),
            colors[secondStat])
    end
    return table.concat(parts, " / ")
end

-- Which content order to rank against. Persisted, defaults to Mythic+.
function ns.GearPanelContent()
    local db = DodoInspectDB
    if db and db.gearPanelContent == "raid" then return "raid" end
    return "mythic"
end

function ns.SetGearPanelContent(content)
    DodoInspectDB.gearPanelContent = (content == "raid") and "raid" or "mythic"
    if panel and panel:IsShown() then ns.RefreshGearPanel() end
end

function ns.GearPanelActive()
    if ns.Config.LOOT_FEATURE_ENABLED ~= true then return false end
    local db = DodoInspectDB
    return (db and db.showGearPanel == true) and true or false
end

-- Equipped item id for the viewed unit, or nil. Guarded: on an enemy
-- player every inventory query can come back secret, and comparing one
-- is an error, not a false.
local function EquippedID(unit, slotID)
    if not unit or not slotID then return nil end
    local ok, id = pcall(GetInventoryItemID, unit, slotID)
    if not ok then return nil end
    if issecretvalue(id) then return nil end
    if type(id) ~= "number" then return nil end
    return id
end

local ROW_HEIGHT = 15
local HEADER_H = 40
local PAD = 8
local NAME_W, STAT_W, SOURCE_W = 170, 115, 150
local PANEL_WIDTH = NAME_W + STAT_W + SOURCE_W + PAD * 2 + 16
local MAX_ROWS = 12

local function NewCell(row, width, anchor, offset)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("LEFT", anchor or row, anchor and "RIGHT" or "LEFT", offset or 0, 0)
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(PANEL_WIDTH - PAD * 2, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD,
                 -(HEADER_H + (index - 1) * ROW_HEIGHT))

    row.name = NewCell(row, NAME_W)
    row.stats = NewCell(row, STAT_W, row.name, 6)
    row.source = NewCell(row, SOURCE_W, row.stats, 6)

    -- Hovering a row shows the real item tooltip, which is where the
    -- item level, sockets and any on-item effect actually live. The
    -- ranking deliberately does not fold those in, so the tooltip is
    -- how the player checks what the score does not know.
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function EnsureRows(count)
    panel.rows = panel.rows or {}
    for i = #panel.rows + 1, count do
        panel.rows[i] = CreateRow(panel, i)
    end
    for i = count + 1, #panel.rows do
        panel.rows[i]:Hide()
    end
end

-- Spec and hero talent for whichever unit the opening panel is showing.
-- Both lookups already guard secret values internally; this only decides
-- which of the two entry points to use.
local function ViewedSpec()
    if state.unit == "player" then
        return ns.PlayerSpecID and ns.PlayerSpecID(),
               ns.PlayerHeroSubTree and ns.PlayerHeroSubTree()
    end
    return ns.InspectSpecID and ns.InspectSpecID(state.unit),
           ns.InspectHeroSubTree and ns.InspectHeroSubTree()
end

local function SetRow(row, index, entryRow, equippedID)
    row.itemID = entryRow.id
    local name = C_Item.GetItemInfo(entryRow.id)
    local isEquipped = (equippedID == entryRow.id)

    local label = string.format("%d. %s", index, name or ("item:" .. entryRow.id))
    if isEquipped then
        label = label .. " " .. (ns.L.gearEquipped or "(equipped)")
    end
    if entryRow.effect then
        label = label .. " " .. Colored("*", ns.Config.GEAR_EFFECT_COLOR)
    end
    row.name:SetText(label)
    row.name:SetTextColor(isEquipped and 1 or 0.9, isEquipped and 0.82 or 0.9,
                          isEquipped and 0.2 or 0.9)

    if entryRow.unranked then
        row.stats:SetText(Colored(ns.L.gearNoStats or "no stat data",
                                  ns.Config.GEAR_MUTED_COLOR))
    else
        local summary = StatSummary(entryRow.entry)
        local fit = math.floor((entryRow.score or 0) * 100 + 0.5)
        row.stats:SetText(string.format("%s  %d%%", summary or "", fit))
    end

    row.source:SetText(Colored(ns.LootSourceText(entryRow.id) or "",
                               ns.Config.LOOT_SOURCE_COLOR))
    row:Show()
end

function ns.RefreshGearPanel()
    if not panel or not state.slotKey then return end

    local specID, subTree = ViewedSpec()
    local candidates = specID
        and ns.SlotCandidates(state.slotKey, specID, subTree,
                              ns.GearPanelContent())

    -- INVTYPE_* are global strings the client already localizes ("Head",
    -- "Tete", ...). Falling back to our own two-letter abbreviation keeps
    -- the header from going blank if one is ever missing.
    local slotName = _G[state.slotKey]
    if type(slotName) ~= "string" or slotName == "" then
        slotName = (ns.L.slots and ns.L.slots[state.slotKey]) or ""
    end
    panel.title:SetText(slotName)

    -- Crafted slots get an honest first line instead of a confident
    -- ranking: the real answer there is an embellished craft, which is
    -- not in any loot table and whose stats the player picks anyway.
    local notes = {}
    if CRAFTED_SLOTS[state.slotKey] then
        notes[#notes + 1] = ns.L.gearCrafted or ""
    end
    -- provisional lives on the spec entry, not on the resolved build, and
    -- StatPrioritySpecCurrent only answers "is this spec live at all".
    local specData = specID and ns.StatPriority and ns.StatPriority[specID]
    if specData and specData.provisional == true then
        notes[#notes + 1] = ns.L.gearProvisional or ""
    end
    panel.note:SetText(table.concat(notes, "  "))

    if not candidates or #candidates == 0 then
        EnsureRows(0)
        panel.empty:SetText(specID and (ns.L.gearNoCandidates or "")
                                    or (ns.L.gearNoSpec or ""))
        panel.empty:Show()
        panel:SetHeight(HEADER_H + 24)
        return
    end
    panel.empty:Hide()

    local shown = math.min(#candidates, MAX_ROWS)
    EnsureRows(shown)
    local equippedID = EquippedID(state.unit, state.slotID)
    for i = 1, shown do
        SetRow(panel.rows[i], i, candidates[i], equippedID)
    end
    panel:SetHeight(HEADER_H + shown * ROW_HEIGHT + 8)
end

function ns.SetupGearPanel()
    if panel then return panel end

    panel = CreateFrame("Frame", "DodoInspectGearPanel", UIParent,
                        "BackdropTemplate")
    panel:SetWidth(PANEL_WIDTH)
    panel:SetHeight(HEADER_H + 24)
    panel:SetFrameStrata("HIGH")
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:Hide()

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -8)

    -- The header states what the list is, because "first row" reads as
    -- "best in slot" to anyone who does not read the tooltip, and it is
    -- not that. See GearRank.lua.
    panel.subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.subtitle:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -2)
    panel.subtitle:SetText(ns.L and ns.L.gearSubtitle or "")

    panel.note = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.note:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -26, -8)
    panel.note:SetJustifyH("RIGHT")

    panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.empty:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -HEADER_H)
    panel.empty:Hide()

    panel.close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    panel.close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
    panel.close:SetScript("OnClick", function() ns.CloseGearPanel() end)

    -- Raid / Mythic+ toggle. Only meaningful for the specs whose orders
    -- differ, but always shown so its absence never reads as a bug.
    panel.content = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.content:SetSize(52, 18)
    panel.content:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", -26, 2)
    panel.content:SetScript("OnClick", function()
        ns.SetGearPanelContent(ns.GearPanelContent() == "raid" and "mythic"
                                                                or "raid")
        panel.content:SetText(ns.GearPanelContent() == "raid"
                              and (ns.L.priRaid or "Raid")
                              or (ns.L.priMythic or "M+"))
    end)
    panel.content:SetText(ns.GearPanelContent() == "raid"
                          and (ns.L and ns.L.priRaid or "Raid")
                          or (ns.L and ns.L.priMythic or "M+"))

    return panel
end

function ns.CloseGearPanel()
    state.slotKey, state.unit, state.anchor, state.slotID = nil, nil, nil, nil
    if panel then panel:Hide() end
end

-- Click handler for a slot label. Same slot closes, another slot swaps
-- the contents, and the window docks to whichever panel was clicked.
function ns.ToggleGearPanel(anchorFrame, slotKey, slotID, unit)
    if not ns.GearPanelActive() then return end
    ns.SetupGearPanel()

    if state.slotKey == slotKey and state.anchor == anchorFrame
       and panel:IsShown() then
        ns.CloseGearPanel()
        return
    end

    state.slotKey, state.slotID, state.unit = slotKey, slotID, unit or "player"
    state.anchor = anchorFrame
    -- Reparenting rather than just anchoring: the panel then hides with
    -- whichever side panel opened it, which is what "closes with the
    -- character frame" actually requires -- the side panel is the thing
    -- that hides, and an anchor alone would leave this floating.
    panel:SetParent(anchorFrame)
    panel:SetFrameStrata("HIGH")
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 2, 0)
    panel:Show()
    ns.RefreshGearPanel()
end

function ns.GearPanelSlotKey()
    return state.slotKey
end

-- Redraw on anything that can change what the list should say: item
-- names arriving, a spec or hero talent switch, or the player equipping
-- something (which moves the "equipped" marker). Cheap when closed.
function ns.RefreshGearPanelIfShown()
    if panel and panel:IsShown() then ns.RefreshGearPanel() end
end

--------------------------------------------------------------------
-- Slot label click targets
--------------------------------------------------------------------

local slotButtons = {}
local IDLE = { 0.25, 0.85, 0.85 }
local HOVER = { 0.45, 1.00, 1.00 }

local function ApplyButtonLook(button)
    local open = ns.GearPanelActive()
                 and ns.GearPanelSlotKey() == button.slotKey
                 and button.owner == state.anchor
    local lit = open or button.hovered
    local color = lit and HOVER or IDLE
    button.label:SetTextColor(color[1], color[2], color[3], 1)
    button.underline:SetColorTexture(color[1], color[2], color[3], open and 1 or 0.6)
    button.underline:SetShown(lit and ns.GearPanelActive())
end

function ns.UpdateSlotButtonStates()
    for _, button in ipairs(slotButtons) do
        if button:IsShown() then ApplyButtonLook(button) end
    end
end

-- Make a row's slot label clickable without replacing it. A real Button
-- widget brings its own font metrics and padding, and the side panel's
-- column geometry is an accumulating chain keyed off the label -- so the
-- label stays a FontString and an invisible button sits on top of it.
function ns.AttachSlotButton(row, ownerPanel, unit)
    if not row or not row.slot then return end

    local button = CreateFrame("Button", nil, row)
    button:SetAllPoints(row.slot)
    button:RegisterForClicks("LeftButtonUp")
    button.label = row.slot
    button.slotKey = row.slotKey
    button.slotID = row.slotID
    button.owner = ownerPanel
    button.unit = unit

    -- Same underline treatment the stat columns already use for the
    -- dominant stat, so "this is interactive" speaks the panel's
    -- existing visual language instead of inventing one.
    button.underline = row:CreateTexture(nil, "OVERLAY")
    button.underline:SetHeight(1)
    button.underline:SetPoint("TOPLEFT", row.slot, "BOTTOMLEFT", 0, 1)
    button.underline:SetPoint("TOPRIGHT", row.slot, "BOTTOMRIGHT", 0, 1)
    button.underline:Hide()

    button:SetScript("OnEnter", function(self)
        self.hovered = true
        ApplyButtonLook(self)
    end)
    button:SetScript("OnLeave", function(self)
        self.hovered = false
        ApplyButtonLook(self)
    end)
    button:SetScript("OnClick", function(self)
        local resolved = type(self.unit) == "function" and self.unit()
                         or self.unit
        ns.ToggleGearPanel(self.owner, self.slotKey, self.slotID, resolved)
        ns.UpdateSlotButtonStates()
    end)

    slotButtons[#slotButtons + 1] = button
    return button
end
