-- DodoBricks - Core
-- Initialization, minimap button, main game window (portrait), start screen.
-- Same structure as DodoPool/Core.lua: start screen <-> board, ESC closes the window, the window is draggable and remembers its position.

local ADDON = ...
local DBR = _G.DodoBricks or {}
_G.DodoBricks = DBR

local geo = DBR.geo
local Render = DBR.Render

local DEFAULTS = {
    bestLevel    = nil,    -- highest level reached, nil = none yet
    sound        = true,   -- sound on/off
    soundVolume  = 3,      -- volume 1~10 (same-frame stacked plays)
    minimapAngle = 235,    -- minimap button angle (offset from DodoPool's 205)
    windowPoint  = nil,    -- window position (saved after dragging)
}

local db
local mainFrame, startPanel, playArea, minimapButton

local function Print(msg)
    if _G.Dodo and _G.Dodo.Print then _G.Dodo.Print("Bricks", msg) else print("|cff33ff99DodoBricks:|r " .. tostring(msg)) end
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
-- Switch: start screen <-> board
-- ============================================================
local function StartNew()
    startPanel:Hide()
    playArea:Show()
    if DBR.Game then DBR.Game.New() end
end

local function ContinueSave()
    if DBR.Game and DBR.Game.HasSave and DBR.Game.HasSave() then
        startPanel:Hide()
        playArea:Show()
        DBR.Game.Load()
    end
end

local function ShowStartScreen()
    if playArea then playArea:Hide() end
    -- Cover the HUD (HUD controls are built later with a higher level; raise the start panel above them to fully cover them)
    if startPanel and mainFrame then
        startPanel:SetFrameLevel((mainFrame:GetFrameLevel() or 0) + 40)
    end
    if startPanel and startPanel.recordText then
        local best = db and db.bestLevel
        startPanel.recordText:SetText("Best level: " .. (best and ("Level " .. best) or "--"))
    end
    if startPanel and startPanel.continueBtn then
        if DBR.Game and DBR.Game.HasSave and DBR.Game.HasSave() then
            startPanel.continueBtn:Enable()
        else
            startPanel.continueBtn:Disable()
        end
    end
    startPanel:Show()
end
DBR.ShowStartScreen = ShowStartScreen

-- ============================================================
-- Main window (portrait)
-- ============================================================
local function CreateMainFrame()
    local f = CreateFrame("Frame", "DodoBricksFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(436, 624)
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
        if DBR.Game and DBR.Game.OnWindowHidden then DBR.Game.OnWindowHidden() end
    end)

    if f.TitleText then f.TitleText:SetText("DodoBricks  Bricks") end

    -- Board area: portrait, centered in the lower part of the window, leaving the HUD bar at the top
    playArea = CreateFrame("Frame", "DodoBricksPlayArea", f)
    playArea:SetSize(geo.BOARD_W, geo.BOARD_H)
    playArea:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
    playArea:Hide()
    Render.BuildBoard(playArea)
    DBR.playArea = playArea

    mainFrame = f
    DBR.frame = f

    -- ESC closes
    tinsert(UISpecialFrames, "DodoBricksFrame")
end

local function CreateStartPanel()
    local p = CreateFrame("Frame", nil, mainFrame)
    p:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 12, -26)
    p:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -12, 12)
    p:EnableMouse(true)   -- eat clicks, blocking the HUD buttons underneath

    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.10, 1)

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", p, "TOP", 0, -56)
    title:SetText("|cffffd200DodoBricks|r")

    local sub = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -8)
    sub:SetText("Numbered Brick Breaker")

    local startBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    startBtn:SetSize(180, 34)
    startBtn:SetPoint("TOP", sub, "BOTTOM", 0, -44)
    startBtn:SetText("New Game")
    startBtn:SetScript("OnClick", StartNew)

    local continueBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    continueBtn:SetSize(180, 34)
    continueBtn:SetPoint("TOP", startBtn, "BOTTOM", 0, -12)
    continueBtn:SetText("Continue")
    continueBtn:SetScript("OnClick", ContinueSave)
    p.continueBtn = continueBtn

    local recordText = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    recordText:SetPoint("TOP", continueBtn, "BOTTOM", 0, -30)
    recordText:SetText("Best level: --")
    p.recordText = recordText

    local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", p, "BOTTOM", 0, 40)
    hint:SetText("Hold left-click to aim - release to launch - right-click to cancel\nNumber on a brick = HP; bricks drop one row each round, reach the bottom line and you lose\nWhite ring +1 ball - red ring laser clears a row/column - orange ring bomb 3x3 (every ball triggers it all round)\nClear the whole board in one round for a bonus - first ball's landing spot = next launch point - autosaves between rounds")
    hint:SetJustifyH("CENTER")

    -- Sound toggle + volume slider (bottom-left)
    if DBR.Sound and DBR.Sound.CreateToggle then
        local cb = DBR.Sound.CreateToggle(p)
        cb:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 14, 10)
        if DBR.Sound.CreateVolumeSlider then
            local sl = DBR.Sound.CreateVolumeSlider(p)
            sl:SetPoint("LEFT", cb, "RIGHT", 84, 0)   -- leave room for the "Sound" label and the "Volume" caption
        end
    end

    startPanel = p
    DBR.startPanel = p
end

-- ============================================================
-- Minimap button (same as DodoPool: Shift+left-drag to reposition, left-click to toggle the game)
-- ============================================================
local function NormalizeAngle(a)
    a = (tonumber(a) or 235) % 360
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
DBR.ToggleGame = ToggleGame

local function CreateMinimapButton()
    local b = CreateFrame("Button", "DodoBricksMinimapButton", Minimap)
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
        GameTooltip:AddLine("DodoBricks Brick Breaker", 1, 1, 1)
        GameTooltip:AddLine("Left-click: open/close the game", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Shift + left-drag: move the icon", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    minimapButton = b
    UpdateMinimapButtonPosition()
end

-- ============================================================
-- Initialization
-- ============================================================
local function Initialize()
    DodoBricksDB = CopyDefaults(DodoBricksDB, DEFAULTS)
    db = DodoBricksDB
    DBR.db = db

    CreateMainFrame()
    CreateStartPanel()
    CreateMinimapButton()

    if db.windowPoint then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(db.windowPoint.point or "CENTER", UIParent,
            db.windowPoint.relPoint or "CENTER", db.windowPoint.x or 0, db.windowPoint.y or 0)
    end

    if _G.Dodo and _G.Dodo.Register then _G.Dodo.Register("DodoBricks", DBR) end

    SLASH_DODOBRICKS1 = "/dodobricks"
    SLASH_DODOBRICKS2 = "/bricks"
    SlashCmdList["DODOBRICKS"] = ToggleGame

    Print("Ready. Open with the minimap button or /bricks.")
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        Initialize()
    end
end)
