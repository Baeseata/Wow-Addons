-- DodoInspect - InspectPanel.lua
-- A compact gear panel docked to the right of the inspect window:
--   [slot] [item level] [stat grid (vers / haste / mastery / crit)]
-- The item level is gradient colored. Enchant and gems are NOT here --
-- they are overlaid directly on the inspected gear slots (Inspect.lua).
-- One row per equipment slot.
--
-- The read-only data layer (the slot and stat tables, GetStatsTable)
-- is shared from SidePanel.lua via ns.*; only layout and rendering
-- live here.
--
-- Blizzard_InspectUI is load-on-demand, so the panel is built when
-- that addon loads (or lazily on the first inspect event) and refreshes
-- on INSPECT_READY / GET_ITEM_INFO_RECEIVED. Inspect targets are
-- players you may inspect (readable gear); stat values are
-- issecretvalue-guarded before any comparison anyway.

local _, ns = ...

------------------------------------------------------------------
-- Geometry (slot box + four centered stat columns)
------------------------------------------------------------------

local FS
local SLOT_W, ILVL_X, ILVL_W, STAT_X, STAT_STEP, ROW_H, PANEL_W

local function ComputeGeometry()
    FS        = ns.InspectPanelFontSize()
    SLOT_W    = math.floor(FS * 2.0)
    -- item level column, between the slot box and the stat grid
    ILVL_X    = SLOT_W + math.floor(FS * 0.3)
    ILVL_W    = math.floor(FS * 2.2)
    STAT_X    = ILVL_X + ILVL_W + math.floor(FS * 0.9)
    STAT_STEP = math.floor(FS * 1.6)
    ROW_H     = FS + 8
    -- wrap the slot box, the item level and the four stat columns
    -- (last centered at STAT_X + 3*STAT_STEP), plus a margin
    PANEL_W   = STAT_X + STAT_STEP * 3 + math.floor(FS * 0.9) + 12
end

local panel, rows

------------------------------------------------------------------
-- Row construction
------------------------------------------------------------------

-- Re-apply every font-size-derived measurement (row size, column
-- positions, fixed widths) to an existing row. Run at creation and again
-- whenever the panel font size changes, so rows re-flow in place instead
-- of being torn down. The stat underlines re-anchor to their labels in
-- UpdateRow.
local function ApplyRowGeometry(row)
    row:SetSize(PANEL_W - 12, ROW_H)
    row.slot:SetWidth(SLOT_W)

    row.ilvl:ClearAllPoints()
    row.ilvl:SetPoint("LEFT", row, "LEFT", ILVL_X, 0)
    row.ilvl:SetWidth(ILVL_W)

    for i = 1, #ns.STAT_ORDER do
        local fs = row.stats[i]
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", row, "LEFT", STAT_X + (i - 1) * STAT_STEP, 0)
    end
end

local function CreateRow(parent, slotInfo)
    local row = CreateFrame("Frame", nil, parent)
    row.slotID = slotInfo.id
    row.slotKey = slotInfo.key

    local function NewText(justify)
        local fs = row:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, FS, "OUTLINE")
        fs:SetJustifyH(justify)
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
        return fs
    end

    -- slot abbreviation (left edge of the row; width set by geometry)
    row.slot = NewText("LEFT")
    row.slot:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.slot:SetTextColor(0.25, 0.85, 0.85, 1)

    -- item level (gradient colored), between the slot and the stats
    row.ilvl = NewText("RIGHT")

    -- four-column secondary stat grid with dominant-stat underline
    row.stats = {}
    row.statLines = {}
    for i = 1, #ns.STAT_ORDER do
        local fs = NewText("CENTER")
        row.stats[i] = fs

        local line = row:CreateTexture(nil, "OVERLAY")
        line:SetHeight(2)
        line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, 1)
        line:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, 1)
        line:Hide()
        row.statLines[i] = line
    end

    ApplyRowGeometry(row)
    return row
end

-- Pack the visible rows tightly and center the block vertically.
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

    -- reserve the top strip the stat priority header occupies (0 when
    -- it is disabled or the spec has no data)
    local pad = 8
    local headerH = panel.dodoPriorityHeight or 0
    local rowHeight = math.min((height - headerH - pad * 2) / count, ROW_H)
    -- with a header, keep the rows snug right under it (any slack falls
    -- to the bottom); without one, center the block in the panel
    local top
    if headerH > 0 then
        top = headerH
    else
        top = (height - rowHeight * count) / 2
    end
    for i, row in ipairs(shownRows) do
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 6,
            -top - (i - 1) * rowHeight)
    end
end

------------------------------------------------------------------
-- Row refresh (secondary stat grid from the inspected unit's gear)
------------------------------------------------------------------

local function UpdateRow(row, unit)
    local cfg = ns.Config
    local slotID = row.slotID

    ns.SetOverlayFont(row.slot, FS, "OUTLINE")
    row.slot:SetText((ns.L and ns.L.slots[row.slotKey]) or "")

    for i = 1, #ns.STAT_ORDER do
        row.stats[i]:Hide()
        row.statLines[i]:Hide()
    end
    row.ilvl:SetText("")

    local itemLink = GetInventoryItemLink(unit, slotID)
    if issecretvalue(itemLink) or not itemLink then return end

    -- item level, gradient colored. Read by link (ItemLocation is
    -- player-only); GetLinkItemLevel is shared from Inspect.lua.
    local ilvl = ns.GetLinkItemLevel(itemLink)
    if ilvl then
        local r, g, b = ns.ColorForItemLevel(ilvl)
        ns.SetOverlayFont(row.ilvl, FS, "OUTLINE")
        row.ilvl:SetTextColor(r, g, b, 1)
        row.ilvl:SetText(tostring(ilvl))
    end

    -- underline inset: Latin two-letter abbreviations need a slight
    -- pull-in, a single CJK char fills its box (same as SidePanel)
    local underL, underR = 0, 0
    local sample = (ns.L and ns.L.stats and ns.L.stats.versatility) or ""
    local isCJK = strlenutf8 and #sample > strlenutf8(sample)
    if not isCJK then
        underL = math.floor(FS * 0.06 + 0.5)
        underR = math.floor(FS * 0.17 + 0.5)
    end

    -- secondary stat grid; every value is issecretvalue-guarded before
    -- it is compared for the dominant-stat underline
    local stats = ns.GetStatsTable(itemLink)
    if not stats then return end

    local maxKey, maxVal, tie = nil, 0, false
    for _, statKey in ipairs(ns.STAT_ORDER) do
        local v = stats[ns.STAT_KEYS[statKey]]
        if not issecretvalue(v) and type(v) == "number" and v > 0 then
            if v > maxVal then
                maxVal, maxKey, tie = v, statKey, false
            elseif v == maxVal then
                tie = true
            end
        end
    end
    if tie then maxKey = nil end

    for i, statKey in ipairs(ns.STAT_ORDER) do
        local v = stats[ns.STAT_KEYS[statKey]]
        if not issecretvalue(v) and v then
            local fs = row.stats[i]
            local c = cfg.STAT_COLORS[statKey]
            ns.SetOverlayFont(fs, FS, "OUTLINE")
            fs:SetText((ns.L and ns.L.stats[statKey]) or "")
            fs:SetTextColor(c[1], c[2], c[3], c[4])
            fs:Show()
            if statKey == maxKey then
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

------------------------------------------------------------------
-- Panel lifecycle
------------------------------------------------------------------

-- The panel belongs to the character tab of the inspect window only;
-- the PvP and guild tabs hide it. It is still a child of the inspect
-- frame, so closing the whole window hides it too.
local function ApplyTabVisibility()
    if not panel then return end
    if ns.IsEnabled("showInspectPanel") and InspectPaperDollFrame
        and InspectPaperDollFrame:IsShown() then
        panel:Show()
    else
        panel:Hide()
    end
end

function ns.SetupInspectPanel()
    if panel then return end
    if not ns.IsEnabled("showInspectPanel") then return end
    if not InspectFrame then return end -- load-on-demand; built on first inspect

    ComputeGeometry()

    panel = CreateFrame("Frame", "DodoInspectInspectPanel",
        InspectFrame, "BackdropTemplate")
    panel:SetWidth(PANEL_W)
    panel:SetPoint("TOPLEFT", InspectFrame, "TOPRIGHT", 2, 0)
    panel:SetPoint("BOTTOMLEFT", InspectFrame, "BOTTOMRIGHT", 2, 0)
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    rows = {}
    for index, slotInfo in ipairs(ns.GEAR_SLOTS) do
        rows[index] = CreateRow(panel, slotInfo)
    end

    ns.SetupStatPriorityHeader(panel)

    LayoutRows()
    panel:SetScript("OnSizeChanged", LayoutRows)
    panel:SetScript("OnShow", function()
        C_Timer.After(0, ns.UpdateInspectPanel)
    end)

    -- follow the inspect-frame tab: only the character tab shows it
    if InspectPaperDollFrame and InspectPaperDollFrame.HookScript then
        InspectPaperDollFrame:HookScript("OnShow", ApplyTabVisibility)
        InspectPaperDollFrame:HookScript("OnHide", ApplyTabVisibility)
    end
    ApplyTabVisibility()
end

-- Options checkbox hook.
function ns.ApplyInspectPanelEnabled()
    if ns.IsEnabled("showInspectPanel") then
        ns.SetupInspectPanel()
        if panel then
            ApplyTabVisibility()
            ns.UpdateInspectPanel()
        end
    elseif panel then
        panel:Hide()
    end
end

-- Apply a changed panel font size live: recompute the geometry and
-- re-flow the existing rows in place. Builds the panel first if it does
-- not exist yet (the inspect UI is load-on-demand, so the font may be
-- changed before anyone is ever inspected).
function ns.RebuildInspectPanel()
    if not panel then
        ns.ApplyInspectPanelEnabled()
        return
    end
    ComputeGeometry()
    panel:SetWidth(PANEL_W)
    for _, row in ipairs(rows) do
        ApplyRowGeometry(row)
    end
    LayoutRows()
    ns.UpdateInspectPanel()
end

function ns.UpdateInspectPanel()
    if not panel or not panel:IsShown() then return end
    local unit = InspectFrame and InspectFrame.unit or "target"
    if not UnitExists(unit) then return end

    local heroSub, heroName = ns.InspectHeroSubTree()
    ns.UpdateStatPriorityHeader(panel, ns.InspectSpecID(unit), heroSub, heroName, FS, PANEL_W)

    for _, row in ipairs(rows) do
        -- hide the off-hand row entirely when nothing is equipped there
        local visible = true
        if row.slotID == 17 and not GetInventoryItemLink(unit, 17) then
            visible = false
        end
        row.shown = visible
        if visible then
            row:Show()
            UpdateRow(row, unit)
        else
            row:Hide()
        end
    end

    LayoutRows()
end

------------------------------------------------------------------
-- Events: build on Blizzard_InspectUI load, refresh on inspect data
------------------------------------------------------------------

local function EnsurePanel()
    if not panel and InspectFrame then ns.SetupInspectPanel() end
end

local EVT = CreateFrame("Frame")
EVT:RegisterEvent("ADDON_LOADED")
EVT:RegisterEvent("INSPECT_READY")
EVT:RegisterEvent("GET_ITEM_INFO_RECEIVED")
EVT:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_InspectUI" then EnsurePanel() end
        return
    end
    -- INSPECT_READY / GET_ITEM_INFO_RECEIVED: inspect data or a
    -- previously uncached item just became available. Also covers a
    -- /reload while the inspect UI was already loaded (lazy build).
    EnsurePanel()
    C_Timer.After(0, ns.UpdateInspectPanel)
end)
