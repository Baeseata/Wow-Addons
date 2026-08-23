local addonName, ns = ...
local addon = CreateFrame("Frame")
_G[addonName] = addon

local DB
local ICON_SIZE = 31
local DUPLICATE_WINDOW = 60

-- Minimap button default angle: every Dodo addon that draws its own minimap button
-- has to pick a DIFFERENT one, otherwise two buttons stack perfectly and the lower
-- one is unclickable on a fresh install. Angles in use across the monorepo (grep
-- 'minimapAngle|minimap = { angle' to re-check -- this list rots):
--   200 DodoGuanzhu / 200 DodoSays / 205 DodoPool / 210 DodoGatherMate
--   220 (this addon) / 225 DodoMap / 235 DodoBricks / 265 DodoRush
-- Was 210 until 2026-08-22, which collided exactly with DodoGatherMate.
-- Only affects fresh installs: the saved value wins (see deepCopy, fill-if-nil).
local DEFAULTS = {
    minimap = { angle = 220 },
    records = {},
}

-- NOTE:
-- These are the four maps requested in the design discussion.
-- If the live game uses different localized names on the client, they can be adjusted here.
local TRACKED_MAPS = {
    ["永歌森林"] = true,
    ["祖阿曼"] = true,
    ["哈籁恩达尔"] = true,
    ["虚影风暴"] = true,
}

local MAP_ORDER = {
    "永歌森林",
    "祖阿曼",
    "哈籁恩达尔",
    "虚影风暴",
}

-- Observed airdrop talking-head samples from live testing:
-- 兹尔丹：抢占先机，夺取你的战利品。
-- 维迪奥斯：时刻关注战利品出现的机会，比如现在！比如现在！
-- 维迪奥斯：看来远方就有一处宝物。不要放过这个机会！
-- 维迪奥斯：你喜欢好东西吧？那就去找到它们。
local TALKING_HEAD_NPCS = {
    ["兹尔丹"] = true,
    ["维迪奥斯"] = true,
}

local function deepCopy(src, dst)
    if type(src) ~= "table" then return dst end
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = deepCopy(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

local function now()
    return GetServerTime and GetServerTime() or time()
end

local function formatAbsolute(ts)
    if not ts then return "-" end
    return date("%H:%M:%S", ts)
end

local function formatRelative(ts)
    if not ts then return "-" end
    local delta = math.max(0, now() - ts)
    if delta < 60 then
        return string.format("%d秒前", delta)
    elseif delta < 3600 then
        return string.format("%d分钟前", math.floor(delta / 60))
    else
        return string.format("%d小时%d分钟前", math.floor(delta / 3600), math.floor((delta % 3600) / 60))
    end
end

local function getCurrentMapName()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return nil, nil end
    local info = C_Map.GetMapInfo(mapID)
    if not info then return mapID, nil end
    return mapID, info.name
end

local function ensureDB()
    DodoAirdropDB = deepCopy(DEFAULTS, DodoAirdropDB)
    DB = DodoAirdropDB
    for _, mapName in ipairs(MAP_ORDER) do
        DB.records[mapName] = DB.records[mapName] or {}
    end
end

local function isTrackedMap(mapName)
    return mapName and TRACKED_MAPS[mapName]
end

local titleFont = "GameFontHighlightLarge"
local normalFont = "GameFontNormal"

local mainFrame = CreateFrame("Frame", addonName .. "MainFrame", UIParent, "BackdropTemplate")
mainFrame:SetSize(420, 210)
mainFrame:SetPoint("CENTER")
mainFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
})
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
mainFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
mainFrame:Hide()

mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY", titleFont)
mainFrame.title:SetPoint("TOP", 0, -16)
mainFrame.title:SetText("DodoAirdrop")

mainFrame.close = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
mainFrame.close:SetPoint("TOPRIGHT", -6, -6)

mainFrame.header = mainFrame:CreateFontString(nil, "OVERLAY", normalFont)
mainFrame.header:SetPoint("TOPLEFT", 20, -42)
mainFrame.header:SetText("地图                上次时间        距今           状态")

mainFrame.rows = {}
for i, mapName in ipairs(MAP_ORDER) do
    local row = CreateFrame("Frame", nil, mainFrame)
    row:SetSize(380, 24)
    row:SetPoint("TOPLEFT", 18, -44 - i * 28)

    row.map = row:CreateFontString(nil, "OVERLAY", normalFont)
    row.map:SetPoint("LEFT", 4, 0)
    row.map:SetWidth(120)
    row.map:SetJustifyH("LEFT")

    row.abs = row:CreateFontString(nil, "OVERLAY", normalFont)
    row.abs:SetPoint("LEFT", 132, 0)
    row.abs:SetWidth(72)
    row.abs:SetJustifyH("LEFT")

    row.rel = row:CreateFontString(nil, "OVERLAY", normalFont)
    row.rel:SetPoint("LEFT", 220, 0)
    row.rel:SetWidth(90)
    row.rel:SetJustifyH("LEFT")

    row.state = row:CreateFontString(nil, "OVERLAY", normalFont)
    row.state:SetPoint("LEFT", 316, 0)
    row.state:SetWidth(70)
    row.state:SetJustifyH("LEFT")

    row.map:SetText(mapName)
    mainFrame.rows[mapName] = row
end

mainFrame.footer = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
mainFrame.footer:SetPoint("BOTTOMLEFT", 18, 14)
mainFrame.footer:SetText("左键打开/关闭，Shift+左键拖动小地图按钮")

local function refreshWindow()
    local _, currentMapName = getCurrentMapName()
    for _, mapName in ipairs(MAP_ORDER) do
        local row = mainFrame.rows[mapName]
        local record = DB.records[mapName] or {}
        row.map:SetText(mapName)
        row.abs:SetText(formatAbsolute(record.lastSeen))
        row.rel:SetText(formatRelative(record.lastSeen))
        row.state:SetText(currentMapName == mapName and "当前地图" or "")
    end
end

local function announce(mapName)
    RaidNotice_AddMessage(RaidWarningFrame, string.format("DodoAirdrop：%s 空投已刷新！", mapName), ChatTypeInfo["RAID_WARNING"])
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(string.format("DodoAirdrop：%s 空投已刷新！", mapName), 1, 0.1, 0.1, 1.0)
    end
    if SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
    if SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_3 then
        PlaySound(SOUNDKIT.ALARM_CLOCK_WARNING_3, "Master")
    end
    if type(FlashClientIcon) == "function" then
        FlashClientIcon()
    end
    print(string.format("|cff33ff99DodoAirdrop|r: %s 记录于 %s", mapName, formatAbsolute(now())))
end

local function recordCurrentMap(sourceText, speaker)
    local _, currentMapName = getCurrentMapName()
    if not isTrackedMap(currentMapName) then return end

    local t = now()
    local record = DB.records[currentMapName] or {}
    if record.lastSeen and (t - record.lastSeen) < DUPLICATE_WINDOW then
        return
    end

    record.lastSeen = t
    record.lastSource = sourceText or ""
    record.lastSpeaker = speaker or ""
    DB.records[currentMapName] = record
    refreshWindow()
    announce(currentMapName)
end

local function handleTalkingHead(speaker, text)
    if type(speaker) ~= "string" or speaker == "" then return end
    if not TALKING_HEAD_NPCS[speaker] then return end
    recordCurrentMap(text or "", speaker)
end

local function tryReadTalkingHead()
    local frame = _G.TalkingHeadFrame
    if not frame then return end

    local speaker = frame.NameFrame and frame.NameFrame.Name and frame.NameFrame.Name:GetText() or nil
    local text = frame.TextFrame and frame.TextFrame.Text and frame.TextFrame.Text:GetText() or nil
    handleTalkingHead(speaker, text)
end

local minimapButton = CreateFrame("Button", addonName .. "MinimapButton", Minimap)
minimapButton:SetSize(ICON_SIZE, ICON_SIZE)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)
minimapButton:SetMovable(true)
minimapButton:RegisterForClicks("LeftButtonUp")
minimapButton:RegisterForDrag("LeftButton")

minimapButton.icon = minimapButton:CreateTexture(nil, "BACKGROUND")
minimapButton.icon:SetAllPoints()
minimapButton.icon:SetTexture("Interface\\Minimap\\Tracking\\Banker")

minimapButton.border = minimapButton:CreateTexture(nil, "OVERLAY")
minimapButton.border:SetSize(54, 54)
minimapButton.border:SetPoint("TOPLEFT")
minimapButton.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local function updateMinimapButtonPosition()
    local radius = (Minimap:GetWidth() / 2) + 6
    local angle = math.rad(DB.minimap.angle or DEFAULTS.minimap.angle)
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

minimapButton:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() then
        self.dragging = true
    end
end)

minimapButton:SetScript("OnDragStop", function(self)
    self.dragging = false
end)

minimapButton:SetScript("OnUpdate", function(self)
    if not self.dragging then return end
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    local angle = math.deg(math.atan2(py - my, px - mx))
    DB.minimap.angle = angle
    updateMinimapButtonPosition()
end)

minimapButton:SetScript("OnClick", function()
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        refreshWindow()
        mainFrame:Show()
    end
end)

minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("DodoAirdrop")
    GameTooltip:AddLine("左键：打开主窗口", 1, 1, 1)
    GameTooltip:AddLine("Shift+左键拖动：移动按钮", 1, 1, 1)
    GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

SLASH_DODOAIRDROP1 = "/dodoairdrop"
SLASH_DODOAIRDROP2 = "/dodoad"
SlashCmdList["DODOAIRDROP"] = function()
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        refreshWindow()
        mainFrame:Show()
    end
end

addon:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= addonName then return end
        ensureDB()
        updateMinimapButtonPosition()
        refreshWindow()

        if TalkingHeadFrame and TalkingHeadFrame.PlayCurrent then
            hooksecurefunc(TalkingHeadFrame, "PlayCurrent", function()
                C_Timer.After(0.05, tryReadTalkingHead)
            end)
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
        refreshWindow()
    elseif event == "TALKINGHEAD_REQUESTED" or event == "TALKINGHEAD_CLOSE" then
        C_Timer.After(0.05, tryReadTalkingHead)
    end
end)

addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
addon:RegisterEvent("ZONE_CHANGED_NEW_AREA")
addon:RegisterEvent("ZONE_CHANGED")
addon:RegisterEvent("TALKINGHEAD_REQUESTED")
addon:RegisterEvent("TALKINGHEAD_CLOSE")
