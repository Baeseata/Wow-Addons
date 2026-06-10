-- DodoPool - Core
-- Initialization, minimap button, main game window, start screen, ball rack display.
-- Phase 1 (0.1.0): only "open the window + render the full 9-ball table + rack the balls". Physics/input/rules come later, separately.

local ADDON = ...
local DP = _G.DodoPool or {}
_G.DodoPool = DP

local geo = DP.geo
local Render = DP.Render

local DEFAULTS = {
    bestStrokes = nil,     -- best (fewest) stroke count, nil = none yet
    aimAssist   = "full",  -- full | line | none (aim assist, used later)
    sound       = true,    -- sound on/off (start-screen / HUD checkbox)
    soundVolume = 3,       -- volume 1~10 (same-frame stacked plays, start-screen slider)
    minimapAngle = 205,    -- minimap button angle
    windowPoint = nil,     -- window position (saved after dragging)
}

local db
local mainFrame, startPanel, playArea, minimapButton

local function Print(msg)
    if _G.Dodo and _G.Dodo.Print then _G.Dodo.Print("Pool", msg) else print("|cff33ff99DodoPool:|r " .. tostring(msg)) end
end

local function CopyDefaults(dst, src)
    if _G.Dodo and _G.Dodo.CopyDefaults then return _G.Dodo.CopyDefaults(dst, src) end
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then dst[k] = CopyDefaults(dst[k], v)
        elseif dst[k] == nil then dst[k] = v end
    end
    return dst
end

-- ============================================================
-- Switch: start screen <-> table (racking/physics handed off to the Game module)
-- ============================================================
local function ShowTable()
    startPanel:Hide()
    playArea:Show()
    if DP.Game then DP.Game.New() end
end

local function ShowStartScreen()
    if playArea then playArea:Hide() end
    -- Cover the HUD (HUD controls are built later with a higher level; raise the start panel above them to fully cover them)
    if startPanel and mainFrame then
        startPanel:SetFrameLevel((mainFrame:GetFrameLevel() or 0) + 20)
    end
    -- Refresh the best-strokes display
    if startPanel and startPanel.recordText then
        local best = db and db.bestStrokes
        startPanel.recordText:SetText("Best strokes: " .. (best and tostring(best) or "--"))
    end
    -- "Continue" is only available when a save exists
    if startPanel and startPanel.continueBtn then
        if DP.Game and DP.Game.HasSave and DP.Game.HasSave() then
            startPanel.continueBtn:Enable()
        else
            startPanel.continueBtn:Disable()
        end
    end
    startPanel:Show()
end
DP.ShowStartScreen = ShowStartScreen

-- ============================================================
-- Main window
-- ============================================================
local function CreateMainFrame()
    local f = CreateFrame("Frame", "DodoPoolFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(1010, 620)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        db.windowPoint = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    f:Hide()
    f:SetScript("OnHide", function()
        if DP.Game and DP.Game.OnWindowHidden then DP.Game.OnWindowHidden() end
    end)

    -- Title
    if f.TitleText then f.TitleText:SetText("DodoPool  9-Ball") end

    -- Top HUD bar placeholder (the physics phase puts power/english/elevation/strokes here)
    local hud = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hud:SetPoint("TOP", f, "TOP", 0, -28)
    hud:SetText("|cff9dd6a0Table preview -- physics and controls coming later|r")
    f.hud = hud

    -- Felt area, centered and slightly low relative to the window, leaving room for the top HUD
    playArea = CreateFrame("Frame", "DodoPoolPlayArea", f)
    playArea:SetSize(geo.FELT_W, geo.FELT_H)
    playArea:SetPoint("BOTTOM", f, "BOTTOM", 0, 34)
    playArea:Hide()
    Render.BuildTable(playArea)
    DP.playArea = playArea

    mainFrame = f
    DP.frame = f

    -- ESC closes
    tinsert(UISpecialFrames, "DodoPoolFrame")
end

local function CreateStartPanel()
    local p = CreateFrame("Frame", nil, mainFrame)
    p:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 12, -26)
    p:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -12, 12)
    p:EnableMouse(true)   -- eat clicks, blocking the HUD buttons underneath (covers the HUD when returning to the menu from the table)

    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.10, 0.07, 1)

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", p, "TOP", 0, -50)
    title:SetText("|cffffd200DodoPool|r")

    local sub = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -8)
    sub:SetText("Single-player 9-Ball")

    local startBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    startBtn:SetSize(180, 34)
    startBtn:SetPoint("TOP", sub, "BOTTOM", 0, -40)
    startBtn:SetText("New Game")
    startBtn:SetScript("OnClick", ShowTable)

    local continueBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    continueBtn:SetSize(180, 34)
    continueBtn:SetPoint("TOP", startBtn, "BOTTOM", 0, -12)
    continueBtn:SetText("Continue")
    continueBtn:SetScript("OnClick", function()
        if DP.Game and DP.Game.HasSave and DP.Game.HasSave() then
            startPanel:Hide()
            playArea:Show()
            DP.Game.Load()
        end
    end)
    p.continueBtn = continueBtn

    local recordText = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    recordText:SetPoint("TOP", continueBtn, "BOTTOM", 0, -28)
    recordText:SetText("Best strokes: --")
    p.recordText = recordText

    local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", p, "BOTTOM", 0, 16)
    hint:SetText("Drag the mouse to aim and charge - WASD strike point - QE elevation - must hit the lowest-numbered ball first")

    -- Sound toggle (bottom-left; state syncs with the HUD checkbox) + volume slider (levels 1~5)
    if DP.Sound and DP.Sound.CreateToggle then
        local cb = DP.Sound.CreateToggle(p)
        cb:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 14, 10)
        if DP.Sound.CreateVolumeSlider then
            local sl = DP.Sound.CreateVolumeSlider(p)
            sl:SetPoint("LEFT", cb, "RIGHT", 84, 0)   -- leave room for the "Sound" label and the "Volume" caption
        end
    end

    startPanel = p
    DP.startPanel = p
end

-- ============================================================
-- Minimap button (copied from DodoMap: Shift+left-drag to reposition, left-click to toggle the game)
-- ============================================================
local function NormalizeAngle(a)
    a = (tonumber(a) or 205) % 360
    if a < 0 then a = a + 360 end
    return a
end

local function UpdateMinimapButtonPosition()
    if not minimapButton then return end
    db.minimapAngle = NormalizeAngle(db.minimapAngle)
    local radius = (Minimap:GetWidth() / 2) + 6
    local rad = math.rad(db.minimapAngle)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

local function UpdateMinimapButtonFromCursor()
    local cx, cy = Minimap:GetCenter()
    if not cx then return end
    local mx, my = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    mx, my = mx / scale, my / scale
    local dx, dy = mx - cx, my - cy
    db.minimapAngle = math.deg(math.atan2(dy, dx))
    UpdateMinimapButtonPosition()
end

local function ToggleGame()
    if not mainFrame then return end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        ShowStartScreen()
        mainFrame:Show()
    end
end
DP.ToggleGame = ToggleGame

local function CreateMinimapButton()
    local b = CreateFrame("Button", "DodoPoolMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture((_G.Dodo and _G.Dodo.icon) or "Interface\\Icons\\INV_Misc_Toy_10")
    b.icon = icon

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetSize(23, 23)
    hl:SetPoint("CENTER", 0, 1)
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    hl:SetBlendMode("ADD")

    b:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or not IsShiftKeyDown() then return end
        self.dragging = true
        self:SetScript("OnUpdate", UpdateMinimapButtonFromCursor)
    end)
    b:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not self.dragging then return end
        self.dragging = false
        self:SetScript("OnUpdate", nil)
        self.suppressClick = true
    end)
    b:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if self.suppressClick then self.suppressClick = nil; return end
            ToggleGame()
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("DodoPool 9-Ball", 1, 1, 1)
        GameTooltip:AddLine("Left-click: open/close the game", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Shift + left-drag: move the icon", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    minimapButton = b
    UpdateMinimapButtonPosition()
end

-- Combat handling moved to the Game module (pause + release the keyboard), see OnCombat in Game.lua.

-- ============================================================
-- Initialization
-- ============================================================
local function Initialize()
    DodoPoolDB = CopyDefaults(DodoPoolDB, DEFAULTS)
    db = DodoPoolDB
    DP.db = db

    CreateMainFrame()
    CreateStartPanel()
    CreateMinimapButton()

    -- Restore window position
    if db.windowPoint then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(db.windowPoint.point or "CENTER", UIParent,
            db.windowPoint.relPoint or "CENTER", db.windowPoint.x or 0, db.windowPoint.y or 0)
    end

    if _G.Dodo and _G.Dodo.Register then _G.Dodo.Register("DodoPool", DP) end

    -- Slash commands
    SLASH_DODOPOOL1 = "/dodopool"
    SLASH_DODOPOOL2 = "/pool"
    SlashCmdList["DODOPOOL"] = ToggleGame

    Print("Ready. Open with the minimap button or /pool.")
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        Initialize()
    end
end)
