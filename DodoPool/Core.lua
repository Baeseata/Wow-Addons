-- DodoPool - Core
-- 初始化、小地图按钮、游戏主窗口、开始界面、摆球展示。
-- 第一阶段(0.1.0):只到"开窗 + 渲染整张九球桌 + 摆好球"。物理/输入/规则随后单独做。

local ADDON = ...
local DP = _G.DodoPool or {}
_G.DodoPool = DP

local geo = DP.geo
local Render = DP.Render

local DEFAULTS = {
    bestStrokes = nil,     -- 最佳(最少)杆数，nil = 暂无
    aimAssist   = "full",  -- full | line | none(瞄准辅助，后续用)
    sound       = true,    -- 音效开关(开始界面 / HUD 勾选框)
    soundVolume = 3,       -- 音量 1~10(同帧叠播次数,开始界面滑条)
    minimapAngle = 205,    -- 小地图按钮角度
    windowPoint = nil,     -- 窗口位置(拖动后保存)
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
-- 切换:开始界面 <-> 牌桌(摆球/物理交给 Game 模块)
-- ============================================================
local function ShowTable()
    startPanel:Hide()
    playArea:Show()
    if DP.Game then DP.Game.New() end
end

local function ShowStartScreen()
    if playArea then playArea:Hide() end
    -- 盖在 HUD 之上(HUD 控件后建、层级更高,这里把开始面板抬到它们之上完整遮住)
    if startPanel and mainFrame then
        startPanel:SetFrameLevel((mainFrame:GetFrameLevel() or 0) + 20)
    end
    -- 刷新最佳杆数显示
    if startPanel and startPanel.recordText then
        local best = db and db.bestStrokes
        startPanel.recordText:SetText("最佳杆数: " .. (best and tostring(best) or "--"))
    end
    -- 有存档才能"继续"
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
-- 主窗口
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

    -- 标题
    if f.TitleText then f.TitleText:SetText("DodoPool  九球") end

    -- 顶部 HUD 条占位(物理阶段放力度/塞/抬杆/杆数)
    local hud = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hud:SetPoint("TOP", f, "TOP", 0, -28)
    hud:SetText("|cff9dd6a0台面预览 -- 物理与操控随后实现|r")
    f.hud = hud

    -- 牌桌区(felt)，相对窗口居中偏下，给顶部 HUD 留空
    playArea = CreateFrame("Frame", "DodoPoolPlayArea", f)
    playArea:SetSize(geo.FELT_W, geo.FELT_H)
    playArea:SetPoint("BOTTOM", f, "BOTTOM", 0, 34)
    playArea:Hide()
    Render.BuildTable(playArea)
    DP.playArea = playArea

    mainFrame = f
    DP.frame = f

    -- ESC 关闭
    tinsert(UISpecialFrames, "DodoPoolFrame")
end

local function CreateStartPanel()
    local p = CreateFrame("Frame", nil, mainFrame)
    p:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 12, -26)
    p:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -12, 12)
    p:EnableMouse(true)   -- 吃掉点击,挡住下层 HUD 按钮(从牌桌返回菜单时盖在 HUD 之上)

    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.10, 0.07, 1)

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", p, "TOP", 0, -50)
    title:SetText("|cffffd200DodoPool|r")

    local sub = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -8)
    sub:SetText("单人九球")

    local startBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    startBtn:SetSize(180, 34)
    startBtn:SetPoint("TOP", sub, "BOTTOM", 0, -40)
    startBtn:SetText("开始新局")
    startBtn:SetScript("OnClick", ShowTable)

    local continueBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    continueBtn:SetSize(180, 34)
    continueBtn:SetPoint("TOP", startBtn, "BOTTOM", 0, -12)
    continueBtn:SetText("继续上次进度")
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
    recordText:SetText("最佳杆数: --")
    p.recordText = recordText

    local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", p, "BOTTOM", 0, 16)
    hint:SetText("鼠标拖动瞄准蓄力 · WASD 击球点 · QE 抬杆 · 必须先碰最小号球")

    -- 音效开关(左下角;与 HUD 勾选框状态同步)+ 音量滑条(1~5 档)
    if DP.Sound and DP.Sound.CreateToggle then
        local cb = DP.Sound.CreateToggle(p)
        cb:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 14, 10)
        if DP.Sound.CreateVolumeSlider then
            local sl = DP.Sound.CreateVolumeSlider(p)
            sl:SetPoint("LEFT", cb, "RIGHT", 84, 0)   -- 让出"音效"字与"音量"标
        end
    end

    startPanel = p
    DP.startPanel = p
end

-- ============================================================
-- 小地图按钮(抄 DodoMap:Shift+左键拖动定位，左键开关游戏)
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
        GameTooltip:AddLine("DodoPool 九球", 1, 1, 1)
        GameTooltip:AddLine("左键: 打开/关闭游戏", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Shift+左键拖动: 移动图标", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    minimapButton = b
    UpdateMinimapButtonPosition()
end

-- 进战处理已移交 Game 模块(暂停 + 放开键盘),见 Game.lua 的 OnCombat。

-- ============================================================
-- 初始化
-- ============================================================
local function Initialize()
    DodoPoolDB = CopyDefaults(DodoPoolDB, DEFAULTS)
    db = DodoPoolDB
    DP.db = db

    CreateMainFrame()
    CreateStartPanel()
    CreateMinimapButton()

    -- 恢复窗口位置
    if db.windowPoint then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(db.windowPoint.point or "CENTER", UIParent,
            db.windowPoint.relPoint or "CENTER", db.windowPoint.x or 0, db.windowPoint.y or 0)
    end

    if _G.Dodo and _G.Dodo.Register then _G.Dodo.Register("DodoPool", DP) end

    -- 斜杠命令
    SLASH_DODOPOOL1 = "/dodopool"
    SLASH_DODOPOOL2 = "/pool"
    SlashCmdList["DODOPOOL"] = ToggleGame

    Print("已就绪。小地图按钮或 /pool 打开。")
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        Initialize()
    end
end)
