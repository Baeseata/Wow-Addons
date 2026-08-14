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
    return ns.IsEnabled("showGearPanel")
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

local HEADER_H = 40
local PAD = 8
local MAX_ROWS = 12

-- Geometry follows the side panel's font size, so this window reads at
-- the same scale as the panel that opened it and the options font slider
-- reaches it too. Recomputed on every refresh rather than captured once,
-- because the slider can move while the panel is open.
local FS, ROW_HEIGHT, STAT_STEP, NAME_W, ILVL_W, SOURCE_W, PANEL_WIDTH

local function Layout()
    FS          = ns.SidePanelFontSize()
    ROW_HEIGHT  = math.floor(FS * 1.35)
    STAT_STEP   = math.floor(FS * 1.6)   -- one stat grid column
    NAME_W      = math.floor(FS * 11)
    ILVL_W      = math.floor(FS * 2.4)
    SOURCE_W    = math.floor(FS * 10)
    PANEL_WIDTH = NAME_W + ILVL_W + STAT_STEP * 4 + SOURCE_W + PAD * 2 + 16
end

-- A FontString created without a font template has no font object, and
-- SetText on it throws "Font not set". Every cell gets its font at
-- creation AND again in LayoutRow: this addon already shipped that exact
-- bug once (1.1.1, TargetInfo).
local function NewCell(row, justify)
    local fs = row:CreateFontString(nil, "OVERLAY")
    ns.SetOverlayFont(fs, FS)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function LayoutRow(row, index)
    row:SetSize(PANEL_WIDTH - PAD * 2, ROW_HEIGHT)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", PAD,
                 -(HEADER_H + (index - 1) * ROW_HEIGHT))

    ns.SetOverlayFont(row.name, FS)
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetWidth(NAME_W)

    ns.SetOverlayFont(row.ilvl, FS)
    row.ilvl:ClearAllPoints()
    row.ilvl:SetPoint("LEFT", row, "LEFT", NAME_W, 0)
    row.ilvl:SetWidth(ILVL_W)

    for i = 1, #ns.STAT_ORDER do
        local fs = row.stats[i]
        ns.SetOverlayFont(fs, FS)
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", row, "LEFT",
                    NAME_W + ILVL_W + math.floor((i - 0.5) * STAT_STEP), 0)
    end

    ns.SetOverlayFont(row.source, FS)
    row.source:ClearAllPoints()
    row.source:SetPoint("LEFT", row, "LEFT",
                        NAME_W + ILVL_W + STAT_STEP * 4 + 6, 0)
    row.source:SetWidth(SOURCE_W)
end

-- Pick the first thing in a return list that looks like an item link.
-- Written with select() rather than a table because the journal's return
-- signature has changed across expansions and embedded nils would
-- truncate a table walk, hiding the link that comes after them.
local function FirstItemLink(ok, ...)
    if not ok then return nil end
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "string" and value:find("|Hitem:", 1, true) then
            return value
        elseif type(value) == "table" and type(value.link) == "string" then
            return value.link
        end
    end
    return nil
end

-- SetItemByID renders an item with no bonus ids at all -- its base form.
-- That is why the returning dungeon pieces come up blue at item level
-- 59: nothing is broken, that literally is the item before the season's
-- bonus ids are applied. The Encounter Journal's own link carries those
-- ids, so preferring it makes the tooltip match what actually drops.
--
-- Best effort on purpose: this needs the journal loaded with the right
-- instance selected, and we deliberately do NOT select one, because that
-- would move the player's own Encounter Journal out from under them.
-- When it comes back empty we show the bare item rather than nothing.
-- Difficulty the journal should be asked about. Raid loot is quoted at
-- Mythic, dungeon loot at Mythic keystone level, because that is the
-- version of the item this panel is recommending you go get.
local MYTHIC_RAID, MYTHIC_DUNGEON = 16, 23

-- false is cached as "asked, nothing there" so a miss costs one lookup
-- per item rather than one per mouseover.
local linkCache = {}

local function TooltipLink(itemID)
    if linkCache[itemID] ~= nil then return linkCache[itemID] or nil end
    if type(EJ_GetLootInfoByID) ~= "function"
       or type(EJ_SelectInstance) ~= "function" then
        return nil
    end
    local entry = ns.LootEntry and ns.LootEntry(itemID)
    if not entry then linkCache[itemID] = false return nil end

    if ns.EnsureEncounterJournal then ns.EnsureEncounterJournal() end

    -- The journal is a single shared selection, and the player may have
    -- their own instance open in it. Borrow it, then put it back exactly
    -- as it was -- silently retargeting someone's Encounter Journal is
    -- the kind of side effect an item level tooltip has no business
    -- causing.
    local prevInstance = EJ_GetCurrentInstance and EJ_GetCurrentInstance()
    local prevDifficulty = EJ_GetDifficulty and EJ_GetDifficulty()

    local isRaid = ns.LootMeta and ns.LootMeta.raids
                   and ns.LootMeta.raids[entry[1]]
    pcall(EJ_SelectInstance, entry[1])
    if type(EJ_SetDifficulty) == "function" then
        pcall(EJ_SetDifficulty, isRaid and MYTHIC_RAID or MYTHIC_DUNGEON)
    end

    local link = FirstItemLink(pcall(EJ_GetLootInfoByID, itemID))

    if prevInstance and prevInstance > 0 then
        pcall(EJ_SelectInstance, prevInstance)
    end
    if prevDifficulty and type(EJ_SetDifficulty) == "function" then
        pcall(EJ_SetDifficulty, prevDifficulty)
    end

    linkCache[itemID] = link or false
    return link
end

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)

    row.name = NewCell(row)
    row.ilvl = NewCell(row, "RIGHT")
    row.source = NewCell(row)

    -- Four-column secondary stat grid: same order, colors, abbreviations
    -- and dominant-stat underline as the character side panel. The two
    -- windows sit side by side and get read together, so they have to
    -- speak one visual language rather than two.
    row.stats, row.statLines = {}, {}
    for i = 1, #ns.STAT_ORDER do
        row.stats[i] = NewCell(row, "CENTER")
        local line = row:CreateTexture(nil, "OVERLAY")
        line:SetHeight(1)
        line:Hide()
        row.statLines[i] = line
    end

    LayoutRow(row, index)

    -- Hovering a row shows the real item tooltip, which is where the
    -- item level, sockets and any on-item effect actually live. The
    -- ranking deliberately does not fold those in, so the tooltip is
    -- how the player checks what the score does not know.
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local link = TooltipLink(self.itemID)
        if link then
            GameTooltip:SetHyperlink(link)
        else
            GameTooltip:SetItemByID(self.itemID)
        end
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
    -- Re-layout the rows that already exist: the font slider can move
    -- between two openings of this panel, and the geometry is derived.
    for i = 1, count do
        LayoutRow(panel.rows[i], i)
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

-- Two different itemIDs can resolve to the same name: the returning BfA
-- dungeons still list legacy pieces (the ilvl 59 azerite head/shoulder/
-- chest among them) beside their modern namesakes, and one name printed
-- twice reads as a bug no matter which of the two is "right".
--
-- Candidates arrive already ranked, so the first occurrence is the one
-- worth keeping -- and because unranked pieces sort last, a ranked twin
-- always wins over a statless one.
--
-- Items whose name has not come back from the server yet are passed
-- through untouched rather than dropped: GetItemInfo returns nil until
-- the item is cached, and treating nil as a name would collapse every
-- uncached row into one. The panel redraws when the names arrive.
local function DedupeByName(candidates)
    local out, seen = {}, {}
    for _, entryRow in ipairs(candidates) do
        local name = C_Item.GetItemInfo(entryRow.id)
        if name == nil or not seen[name] then
            if name then seen[name] = true end
            out[#out + 1] = entryRow
        end
    end
    return out
end

-- Four-column stat grid mirroring the character side panel: the stat's
-- abbreviation sits in the stat's own column, the dominant one is
-- underlined, ties get no underline. Deliberately no percentages -- the
-- columns already say which stats the item carries, and the list order
-- already carries the fit. Costs a quarter of the width the old
-- "77% Haste / 23% Crit  87%" cell did.
local function SetStatCells(row, entryRow)
    for i = 1, #ns.STAT_ORDER do
        row.stats[i]:Hide()
        row.statLines[i]:Hide()
    end

    -- Items with no secondaries at all (the ilvl 59 BfA azerite pieces)
    -- get an explicit dash: four blank columns read as missing data.
    if entryRow.unranked then
        local fs, c = row.stats[1], ns.Config.GEAR_MUTED_COLOR
        fs:SetText("-")
        fs:SetTextColor(c[1], c[2], c[3], c[4])
        fs:Show()
        return
    end

    local entry = entryRow.entry
    local values = {}
    if entry[5] then values[entry[5]] = entry[6] or 0 end
    if entry[7] then values[entry[7]] = entry[8] or 0 end

    local maxKey, maxVal, tie = nil, 0, false
    for _, key in ipairs(ns.STAT_ORDER) do
        local v = values[key]
        if type(v) == "number" and v > 0 then
            if v > maxVal then maxVal, maxKey, tie = v, key, false
            elseif v == maxVal then tie = true end
        end
    end
    if tie then maxKey = nil end

    -- Latin two-letter abbreviations carry side bearings that make a
    -- full-width underline look wider than the glyphs; a CJK glyph fills
    -- its box. Same correction the side panel applies.
    local underL, underR = 0, 0
    local sample = (ns.L and ns.L.stats and ns.L.stats.versatility) or ""
    if not (strlenutf8 and #sample > strlenutf8(sample)) then
        underL = math.floor(FS * 0.06 + 0.5)
        underR = math.floor(FS * 0.17 + 0.5)
    end

    for i, key in ipairs(ns.STAT_ORDER) do
        if values[key] then
            local fs = row.stats[i]
            local c = ns.Config.STAT_COLORS[key]
            fs:SetText((ns.L and ns.L.stats and ns.L.stats[key]) or key)
            fs:SetTextColor(c[1], c[2], c[3], c[4])
            fs:Show()
            if key == maxKey then
                local line = row.statLines[i]
                line:SetColorTexture(c[1], c[2], c[3], 0.9)
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", underL, 1)
                line:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", -underR, 1)
                line:Show()
            end
        end
    end
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

    -- The item level the piece reaches once fully upgraded, NOT the base
    -- level the static data carries -- that one is 59 for every returning
    -- dungeon piece and is the reason this column exists at all. Blank
    -- for the statless azerite leftovers: they are not on a current
    -- upgrade track, so quoting either ceiling for them would be a lie.
    if entryRow.unranked then
        row.ilvl:SetText("")
    else
        local top = entryRow.topItemLevel
        local cfg = ns.Config
        local c = top and cfg.GEAR_TOP_ILVL_COLOR or cfg.GEAR_ILVL_COLOR
        row.ilvl:SetText(tostring(top and cfg.GEAR_TOP_ITEM_LEVEL
                                      or cfg.GEAR_MYTH_ITEM_LEVEL))
        row.ilvl:SetTextColor(c[1], c[2], c[3], c[4])
    end

    SetStatCells(row, entryRow)

    row.source:SetText(Colored(ns.LootSourceText(entryRow.id) or "",
                               ns.Config.LOOT_SOURCE_COLOR))
    row:Show()
end

function ns.RefreshGearPanel()
    if not panel or not state.slotKey then return end

    -- Geometry is derived from the font size, which the options slider
    -- can have moved since the last draw.
    Layout()
    panel:SetWidth(PANEL_WIDTH)

    local specID, subTree = ViewedSpec()
    local candidates = specID
        and ns.SlotCandidates(state.slotKey, specID, subTree,
                              ns.GearPanelContent())
    if candidates then candidates = DedupeByName(candidates) end

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
        local note = ns.L.gearCrafted or ""
        -- The crafted ceiling, when it is actually known. Config keeps it
        -- nil until a real value is confirmed, and an absent number reads
        -- honestly here -- a wrong one would be quoted back at the player
        -- as if the addon had checked.
        local crafted = ns.Config.GEAR_CRAFTED_ITEM_LEVEL
        if crafted then
            note = note .. " " .. Colored(tostring(crafted),
                                          ns.Config.GEAR_ILVL_COLOR)
        end
        notes[#notes + 1] = note
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

    Layout()
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
