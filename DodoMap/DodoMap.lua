local addonName = ...

local ADDON_TITLE = "DodoMap"
local DEFAULTS = {
    unlockCoordFrame = false,
    fontSize = 14,
    coordFramePos = nil,
    minimapAngle = 225,
}

local db
local eventFrame = CreateFrame("Frame")
local coordFrame
local coordText
local popupFrame
local minimapButton
local unlockCheckBox
local fontSizeEditBox
local coordTicker

local function Print(msg)
    print("|cff33ff99DodoMap:|r " .. tostring(msg))
end

local function CopyDefaults(src, dst)
    if type(src) ~= "table" then
        return {}
    end
    if type(dst) ~= "table" then
        dst = {}
    end

    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end

    return dst
end

local function GetCurrentMapID()
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then
        return mapID
    end

    if WorldMapFrame and WorldMapFrame.GetMapID then
        return WorldMapFrame:GetMapID()
    end

    return nil
end

local function GetPlayerXY()
    local mapID = GetCurrentMapID()
    if not mapID then
        return nil, nil, nil
    end

    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    if not position then
        return nil, nil, mapID
    end

    local x, y = position:GetXY()
    return x, y, mapID
end

local function NormalizeAngle(angle)
    angle = tonumber(angle) or DEFAULTS.minimapAngle
    angle = angle % 360
    if angle < 0 then
        angle = angle + 360
    end
    return angle
end

local function GetAngleFromOffsets(dx, dy)
    if dx == 0 then
        if dy > 0 then
            return 90
        elseif dy < 0 then
            return 270
        else
            return DEFAULTS.minimapAngle
        end
    end

    local angle = math.deg(math.atan(dy / dx))
    if dx < 0 then
        angle = angle + 180
    elseif dy < 0 then
        angle = angle + 360
    end

    return NormalizeAngle(angle)
end

local function UpdateCoordinateText()
    if not coordText then
        return
    end

    local x, y = GetPlayerXY()
    if x and y then
        coordText:SetFormattedText("%.1f, %.1f", x * 100, y * 100)
    else
        coordText:SetText("--.-, --.-")
    end
end

local function SaveCoordFramePosition()
    if not coordFrame then
        return
    end

    local centerX, centerY = coordFrame:GetCenter()
    if not centerX or not centerY then
        return
    end

    local uiCenterX = UIParent:GetWidth() / 2
    local uiCenterY = UIParent:GetHeight() / 2

    db.coordFramePos = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = centerX - uiCenterX,
        y = centerY - uiCenterY,
    }
end

local function ApplyCoordFramePosition()
    if not coordFrame then
        return
    end

    coordFrame:ClearAllPoints()

    if db.coordFramePos then
        coordFrame:SetPoint(
            db.coordFramePos.point or "CENTER",
            UIParent,
            db.coordFramePos.relativePoint or "CENTER",
            db.coordFramePos.x or 0,
            db.coordFramePos.y or 0
        )
    else
        coordFrame:SetPoint("TOPLEFT", Minimap, "BOTTOMLEFT", 0, -2)
    end
end

local function ApplyFontSize()
    if not coordText then
        return
    end

    local size = tonumber(db.fontSize) or DEFAULTS.fontSize
    size = math.floor(size + 0.5)
    size = math.max(8, math.min(32, size))
    db.fontSize = size

    coordText:SetFontObject(NumberFontNormal)
    local fontPath = coordText:GetFont()
    if fontPath then
        coordText:SetFont(fontPath, size, "OUTLINE")
    end

    coordFrame:SetSize(math.max(80, coordText:GetStringWidth() + 10), math.max(size + 8, 20))
    UpdateCoordinateText()
end

local function ApplyUnlockState()
    if not coordFrame then
        return
    end

    local unlocked = db.unlockCoordFrame
    coordFrame:SetMovable(unlocked)
    coordFrame:EnableMouse(unlocked)

    if unlocked then
        coordFrame.bg:Show()
        coordFrame.dragHint:Show()
    else
        coordFrame.bg:Hide()
        coordFrame.dragHint:Hide()
    end

    if unlockCheckBox then
        unlockCheckBox:SetChecked(unlocked)
    end
end

local function RefreshOptionsWidgets()
    if unlockCheckBox then
        unlockCheckBox:SetChecked(db.unlockCoordFrame)
    end

    if fontSizeEditBox then
        fontSizeEditBox:SetText(tostring(db.fontSize or DEFAULTS.fontSize))
    end
end

local function ClearWaypoint()
    if C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() and C_Map.ClearUserWaypoint then
        C_Map.ClearUserWaypoint()
    elseif C_Map.ClearUserWaypoint then
        C_Map.ClearUserWaypoint()
    end

    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(false)
    end
end

local function SetWaypointFromCoords(xInput, yInput)
    local x = tonumber(xInput)
    local y = tonumber(yInput)

    if not x or not y then
        Print("请输入有效的 X / Y 坐标。")
        return
    end

    if x < 0 or x > 100 or y < 0 or y > 100 then
        Print("坐标范围应在 0 到 100 之间。")
        return
    end

    local mapID = GetCurrentMapID()
    if not mapID then
        Print("当前无法获取地图信息。")
        return
    end

    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then
        Print("当前地图不支持放置暴雪默认标记。")
        return
    end

    local point = UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100)
    if not point then
        Print("无法创建地图标记。")
        return
    end

    ClearWaypoint()
    C_Map.SetUserWaypoint(point)

    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
end

local function TogglePopup()
    if not popupFrame then
        return
    end

    if popupFrame:IsShown() then
        popupFrame:Hide()
    else
        popupFrame:Show()
        popupFrame.xEdit:SetFocus()
        popupFrame.xEdit:HighlightText()
    end
end

local function UpdateMinimapButtonPosition()
    if not minimapButton then
        return
    end

    db.minimapAngle = NormalizeAngle(db.minimapAngle)

    local radius = (Minimap:GetWidth() / 2) + 6
    local angle = math.rad(db.minimapAngle)
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius

    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function UpdateMinimapButtonFromCursor()
    if not minimapButton then
        return
    end

    local minimapCenterX, minimapCenterY = Minimap:GetCenter()
    if not minimapCenterX or not minimapCenterY then
        return
    end

    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    cursorX = cursorX / scale
    cursorY = cursorY / scale

    local dx = cursorX - minimapCenterX
    local dy = cursorY - minimapCenterY
    if dx == 0 and dy == 0 then
        return
    end

    db.minimapAngle = GetAngleFromOffsets(dx, dy)
    UpdateMinimapButtonPosition()
end

local function CreateCoordDisplay()
    coordFrame = CreateFrame("Frame", "DodoMapCoordFrame", UIParent, "BackdropTemplate")
    coordFrame:SetSize(90, 22)
    coordFrame:SetClampedToScreen(true)
    coordFrame:RegisterForDrag("LeftButton")

    coordFrame:SetScript("OnDragStart", function(self)
        if db.unlockCoordFrame then
            self:StartMoving()
        end
    end)

    coordFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveCoordFramePosition()
        ApplyCoordFramePosition()
    end)

    coordFrame.bg = coordFrame:CreateTexture(nil, "BACKGROUND")
    coordFrame.bg:SetAllPoints()
    coordFrame.bg:SetColorTexture(0, 0, 0, 0.35)

    coordText = coordFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    coordText:SetPoint("CENTER")
    coordText:SetJustifyH("CENTER")
    coordText:SetText("--.-, --.-")

    coordFrame.dragHint = coordFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    coordFrame.dragHint:SetPoint("TOP", coordFrame, "BOTTOM", 0, -1)
    coordFrame.dragHint:SetText("拖动")

    ApplyCoordFramePosition()
    ApplyFontSize()
    ApplyUnlockState()
end

local function CreatePopup()
    popupFrame = CreateFrame("Frame", "DodoMapPopupFrame", UIParent, "BasicFrameTemplateWithInset")
    popupFrame:SetSize(250, 155)
    popupFrame:SetPoint("CENTER")
    popupFrame:SetMovable(true)
    popupFrame:EnableMouse(true)
    popupFrame:RegisterForDrag("LeftButton")
    popupFrame:SetClampedToScreen(true)
    popupFrame:SetScript("OnDragStart", popupFrame.StartMoving)
    popupFrame:SetScript("OnDragStop", popupFrame.StopMovingOrSizing)
    popupFrame:Hide()

    local title = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -10)
    title:SetText("DodoMap")

    local xLabel = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    xLabel:SetPoint("TOPLEFT", 16, -36)
    xLabel:SetText("X")

    local xEdit = CreateFrame("EditBox", nil, popupFrame, "InputBoxTemplate")
    xEdit:SetSize(60, 24)
    xEdit:SetPoint("LEFT", xLabel, "RIGHT", 8, 0)
    xEdit:SetAutoFocus(false)
    xEdit:SetMaxLetters(8)

    local yLabel = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    yLabel:SetPoint("LEFT", xEdit, "RIGHT", 16, 0)
    yLabel:SetText("Y")

    local yEdit = CreateFrame("EditBox", nil, popupFrame, "InputBoxTemplate")
    yEdit:SetSize(60, 24)
    yEdit:SetPoint("LEFT", yLabel, "RIGHT", 8, 0)
    yEdit:SetAutoFocus(false)
    yEdit:SetMaxLetters(8)

    local setButton = CreateFrame("Button", nil, popupFrame, "UIPanelButtonTemplate")
    setButton:SetSize(80, 22)
    setButton:SetPoint("TOPLEFT", xLabel, "BOTTOMLEFT", 0, -18)
    setButton:SetText("标记")

    local clearButton = CreateFrame("Button", nil, popupFrame, "UIPanelButtonTemplate")
    clearButton:SetSize(80, 22)
    clearButton:SetPoint("LEFT", setButton, "RIGHT", 12, 0)
    clearButton:SetText("清空")

    local tip = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tip:SetPoint("TOPLEFT", setButton, "BOTTOMLEFT", 0, -10)
    tip:SetWidth(210)
    tip:SetJustifyH("LEFT")
    tip:SetJustifyV("TOP")
    tip:SetText("DoodoMap\n为您导航")

    local function ApplyWaypoint()
        SetWaypointFromCoords(xEdit:GetText(), yEdit:GetText())
    end

    xEdit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        ApplyWaypoint()
    end)

    yEdit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        ApplyWaypoint()
    end)

    setButton:SetScript("OnClick", ApplyWaypoint)

    clearButton:SetScript("OnClick", function()
        xEdit:SetText("")
        yEdit:SetText("")
        ClearWaypoint()
    end)

    popupFrame.xEdit = xEdit
    popupFrame.yEdit = yEdit
end

local function CreateMinimapButton()
    minimapButton = CreateFrame("Button", "DodoMapMinimapButton", Minimap)
    minimapButton:SetSize(31, 31)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local icon = minimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    minimapButton.icon = icon

    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local highlight = minimapButton:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(23, 23)
    highlight:SetPoint("CENTER", 0, 1)
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")

    minimapButton:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or not IsShiftKeyDown() then
            return
        end

        self.isDragging = true
        self:SetScript("OnUpdate", function()
            UpdateMinimapButtonFromCursor()
        end)
        UpdateMinimapButtonFromCursor()
    end)

    minimapButton:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not self.isDragging then
            return
        end

        self.isDragging = false
        self:SetScript("OnUpdate", nil)
        self.suppressNextLeftClick = true
    end)

    minimapButton:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if self.suppressNextLeftClick then
                self.suppressNextLeftClick = nil
                return
            end
            TogglePopup()
        else
            ClearWaypoint()
        end
    end)

    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("DodoMap", 1, 1, 1)
        GameTooltip:AddLine("左键：打开坐标输入", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Shift+左键拖动：移动小地图图标", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("右键：清除当前标记", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    minimapButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    UpdateMinimapButtonPosition()
end

local function CreateOptionsPanel()
    local options = CreateFrame("Frame")
    options.name = ADDON_TITLE
    options:Hide()
    options:SetScript("OnShow", RefreshOptionsWidgets)

    options.OnCommit = function() end
    options.OnDefault = function()
        db.unlockCoordFrame = DEFAULTS.unlockCoordFrame
        db.fontSize = DEFAULTS.fontSize
        db.coordFramePos = nil
        db.minimapAngle = DEFAULTS.minimapAngle

        ApplyCoordFramePosition()
        ApplyFontSize()
        ApplyUnlockState()
        UpdateMinimapButtonPosition()
        RefreshOptionsWidgets()
    end
    options.OnRefresh = RefreshOptionsWidgets

    local header = options:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 16, -16)
    header:SetText("DodoMap")

    local subText = options:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subText:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    subText:SetWidth(520)
    subText:SetJustifyH("LEFT")
    subText:SetText("坐标显示与输入坐标标记设置。")

    unlockCheckBox = CreateFrame("CheckButton", nil, options, "UICheckButtonTemplate")
    unlockCheckBox:SetPoint("TOPLEFT", subText, "BOTTOMLEFT", 0, -18)

    local unlockLabel = options:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    unlockLabel:SetPoint("LEFT", unlockCheckBox, "RIGHT", 4, 0)
    unlockLabel:SetText("解锁坐标显示框（可拖动）")

    unlockCheckBox:SetScript("OnClick", function(self)
        db.unlockCoordFrame = self:GetChecked() and true or false
        ApplyUnlockState()
    end)

    local fontLabel = options:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", unlockCheckBox, "BOTTOMLEFT", 0, -18)
    fontLabel:SetText("坐标字体大小")

    fontSizeEditBox = CreateFrame("EditBox", nil, options, "InputBoxTemplate")
    fontSizeEditBox:SetSize(60, 24)
    fontSizeEditBox:SetPoint("LEFT", fontLabel, "RIGHT", 12, 0)
    fontSizeEditBox:SetAutoFocus(false)
    fontSizeEditBox:SetMaxLetters(2)

    local fontHelp = options:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fontHelp:SetPoint("LEFT", fontSizeEditBox, "RIGHT", 8, 0)
    fontHelp:SetText("范围：8 - 32")

    local function CommitFontSize()
        local value = tonumber(fontSizeEditBox:GetText())
        if not value then
            fontSizeEditBox:SetText(tostring(db.fontSize or DEFAULTS.fontSize))
            return
        end

        db.fontSize = value
        ApplyFontSize()
        fontSizeEditBox:SetText(tostring(db.fontSize))
    end

    fontSizeEditBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        CommitFontSize()
    end)

    fontSizeEditBox:SetScript("OnEditFocusLost", CommitFontSize)

    local category, layout = Settings.RegisterCanvasLayoutCategory(options, ADDON_TITLE, ADDON_TITLE)
    category.ID = ADDON_TITLE

    if layout and layout.AddAnchorPoint then
        layout:AddAnchorPoint("TOPLEFT", 0, 0)
        layout:AddAnchorPoint("BOTTOMRIGHT", 0, 0)
    end

    Settings.RegisterAddOnCategory(category)
end

local function Initialize()
    DodoMapDB = CopyDefaults(DEFAULTS, DodoMapDB)
    db = DodoMapDB

    CreateCoordDisplay()
    CreatePopup()
    CreateMinimapButton()
    CreateOptionsPanel()

    UpdateCoordinateText()

    if coordTicker then
        coordTicker:Cancel()
    end
    coordTicker = C_Timer.NewTicker(0.10, UpdateCoordinateText)
end

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        Initialize()
    end
end)
