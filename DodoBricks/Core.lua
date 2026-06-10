-- DodoBricks - Core
-- 初始化、小地图按钮、游戏主窗口(竖版)、开始界面。
-- 结构与 DodoPool/Core.lua 同款:开始界面 <-> 棋盘,ESC 关窗,窗口可拖动并记忆位置。

local ADDON = ...
local DBR = _G.DodoBricks or {}
_G.DodoBricks = DBR

local geo = DBR.geo
local Render = DBR.Render

local DEFAULTS = {
    bestLevel    = nil,    -- 最高到达关数,nil = 暂无
    sound        = true,   -- 音效开关
    soundVolume  = 3,      -- 音量 1~10(同帧叠播次数)
    minimapAngle = 235,    -- 小地图按钮角度(错开 DodoPool 的 205)
    windowPoint  = nil,    -- 窗口位置(拖动后保存)
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
-- 切换:开始界面 <-> 棋盘
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
    -- 盖在 HUD 之上(HUD 控件后建、层级更高,把开始面板抬上去完整遮住)
    if startPanel and mainFrame then
        startPanel:SetFrameLevel((mainFrame:GetFrameLevel() or 0) + 40)
    end
    if startPanel and startPanel.recordText then
        local best = db and db.bestLevel
        startPanel.recordText:SetText("最高关卡: " .. (best and ("第 " .. best .. " 关") or "--"))
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
-- 主窗口(竖版)
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

    if f.TitleText then f.TitleText:SetText("DodoBricks  打砖块") end

    -- 棋盘区:竖版,窗口下部居中,顶上留 HUD 条
    playArea = CreateFrame("Frame", "DodoBricksPlayArea", f)
    playArea:SetSize(geo.BOARD_W, geo.BOARD_H)
    playArea:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
    playArea:Hide()
    Render.BuildBoard(playArea)
    DBR.playArea = playArea

    mainFrame = f
    DBR.frame = f

    -- ESC 关闭
    tinsert(UISpecialFrames, "DodoBricksFrame")
end

local function CreateStartPanel()
    local p = CreateFrame("Frame", nil, mainFrame)
    p:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 12, -26)
    p:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -12, 12)
    p:EnableMouse(true)   -- 吃掉点击,挡住下层 HUD 按钮

    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.10, 1)

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", p, "TOP", 0, -56)
    title:SetText("|cffffd200DodoBricks|r")

    local sub = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -8)
    sub:SetText("数字打砖块")

    local startBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    startBtn:SetSize(180, 34)
    startBtn:SetPoint("TOP", sub, "BOTTOM", 0, -44)
    startBtn:SetText("开始新局")
    startBtn:SetScript("OnClick", StartNew)

    local continueBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    continueBtn:SetSize(180, 34)
    continueBtn:SetPoint("TOP", startBtn, "BOTTOM", 0, -12)
    continueBtn:SetText("继续上次进度")
    continueBtn:SetScript("OnClick", ContinueSave)
    p.continueBtn = continueBtn

    local recordText = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    recordText:SetPoint("TOP", continueBtn, "BOTTOM", 0, -30)
    recordText:SetText("最高关卡: --")
    p.recordText = recordText

    local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", p, "BOTTOM", 0, 40)
    hint:SetText("按住左键瞄准 · 松开发射 · 右键取消\n砖上数字 = 血量,每回合下压一行,压到底线就输了\n吃 \"+1\" 圆环涨球数 · 首球落点 = 下回合发射点 · 回合间自动存档")
    hint:SetJustifyH("CENTER")

    -- 音效开关 + 音量滑条(左下角)
    if DBR.Sound and DBR.Sound.CreateToggle then
        local cb = DBR.Sound.CreateToggle(p)
        cb:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 14, 10)
        if DBR.Sound.CreateVolumeSlider then
            local sl = DBR.Sound.CreateVolumeSlider(p)
            sl:SetPoint("LEFT", cb, "RIGHT", 84, 0)   -- 让出"音效"字与"音量"标
        end
    end

    startPanel = p
    DBR.startPanel = p
end

-- ============================================================
-- 小地图按钮(同 DodoPool:Shift+左键拖动定位,左键开关游戏)
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
        GameTooltip:AddLine("DodoBricks 打砖块", 1, 1, 1)
        GameTooltip:AddLine("左键: 打开/关闭游戏", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Shift+左键拖动: 移动图标", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    minimapButton = b
    UpdateMinimapButtonPosition()
end

-- ============================================================
-- 初始化
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

    Print("已就绪。小地图按钮或 /bricks 打开。")
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        Initialize()
    end
end)
