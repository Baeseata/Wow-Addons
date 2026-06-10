local ADDON_NAME = ...
local DodoStatHUD = CreateFrame("Frame", "DodoStatHUDFrame", UIParent)

local CR_VERSATILITY_DAMAGE_DONE_FALLBACK = _G.CR_VERSATILITY_DAMAGE_DONE or 29
local BASE_MOVEMENT_SPEED = 7
local UPDATE_INTERVAL = 0.20
local DEFAULT_ARROW_HOLD_SECONDS = 5.0

local ARROW_UP = "虎虎虎"
local ARROW_DOWN = "↓↓↓"
local ARROW_UP_COLOR = { 0.15, 1.00, 0.15 }
local ARROW_DOWN_COLOR = { 1.00, 0.15, 0.15 }

local DEFAULTS = {
    fontSize = 16,
    locked = false,
    arrowHoldSeconds = DEFAULT_ARROW_HOLD_SECONDS,

    -- 改成存“左上角”的绝对位置，保证宽度变化时左侧不动
    left = nil,
    top = nil,

    enabled = {
        primary = true,
        crit    = true,
        haste   = true,
        mastery = true,
        vers    = true,
        speed   = true,
    },

    colors = {
        primary = {1.00, 0.82, 0.00},
        crit    = {1.00, 0.25, 0.25},
        haste   = {0.25, 0.85, 1.00},
        mastery = {0.80, 0.35, 1.00},
        vers    = {0.30, 1.00, 0.30},
        speed   = {1.00, 0.60, 0.15},
    },

    baselines = {
        strength  = nil,
        agility   = nil,
        intellect = nil,
    },
}

local DB
local optionsPanel
local settingsCategoryID
local elapsedSinceUpdate = 0

local STAT_ORDER = { "primary", "crit", "haste", "mastery", "vers", "speed" }

local OPTION_LABELS = {
    primary = "主属性",
    crit    = "暴击",
    haste   = "急速",
    mastery = "精通",
    vers    = "全能",
    speed   = "移速",
}

local function CopyDefaults(src, dst)
    if type(dst) ~= "table" then
        dst = {}
    end

    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end

    return dst
end

local function Round1(value)
    value = tonumber(value) or 0
    return math.floor(value * 10 + 0.5) / 10
end

local function ClampArrowHoldSeconds(value)
    value = tonumber(value)
    if not value then
        return DEFAULT_ARROW_HOLD_SECONDS
    end

    if value < 0 then
        value = 0
    elseif value > 60 then
        value = 60
    end

    return Round1(value)
end

local function FormatPercentRounded(valueRounded)
    return string.format("%.1f%%", valueRounded or 0)
end

local function FormatSeconds(value)
    return string.format("%.1f", ClampArrowHoldSeconds(value))
end

local function GetStatColor(statKey)
    local c = DB.colors[statKey]
    if not c then
        return 1, 1, 1
    end
    return c[1] or 1, c[2] or 1, c[3] or 1
end

local function GetUnitStatCurrent(statID)
    local stat, effectiveStat = UnitStat("player", statID)
    return effectiveStat or stat or 0
end

local function GetCurrentPrimaryStatInfo()
    local strength  = GetUnitStatCurrent(1)
    local agility   = GetUnitStatCurrent(2)
    local intellect = GetUnitStatCurrent(4)

    if strength >= agility and strength >= intellect then
        return "strength", "力量", strength
    elseif agility >= intellect then
        return "agility", "敏捷", agility
    else
        return "intellect", "智力", intellect
    end
end

local function EnsurePrimaryBaseline()
    -- 12.0 机密值:战斗中主属性读不到(secret),先不设基准(脱战后会再设)
    local ok, key, _, current = pcall(GetCurrentPrimaryStatInfo)
    if not ok or not key then return end
    if not DB.baselines[key] or DB.baselines[key] <= 0 then
        DB.baselines[key] = math.max(current, 1)
    end
end

local function SaveCurrentPrimaryBaseline()
    -- 战斗中主属性是机密值,无法运算 → 提示脱战后再设(避免报错)
    local ok, key, label, current = pcall(GetCurrentPrimaryStatInfo)
    if not ok or not key then
        if optionsPanel and optionsPanel.baselineText then
            optionsPanel.baselineText:SetText("战斗中无法读取主属性,请脱战后再保存基准。")
        end
        return
    end
    DB.baselines[key] = math.max(current, 1)

    if optionsPanel and optionsPanel.baselineText then
        optionsPanel.baselineText:SetText(string.format("当前基准：%s %d", label, DB.baselines[key]))
    end
end

local function GetPrimaryDisplayValue()
    EnsurePrimaryBaseline()

    local key, label, current = GetCurrentPrimaryStatInfo()
    local baseline = DB.baselines[key] or math.max(current, 1)

    if baseline <= 0 then
        baseline = 1
    end

    local percent = (current / baseline) * 100
    return label, percent
end

local function GetCritDisplayValue()
    local holySchool = 2
    local spellCrit = GetSpellCritChance(holySchool) or 0

    for i = holySchool + 1, 7 do
        local value = GetSpellCritChance(i) or spellCrit
        if value < spellCrit then
            spellCrit = value
        end
    end

    local rangedCrit = GetRangedCritChance() or 0
    local meleeCrit = GetCritChance() or 0

    return math.max(spellCrit, rangedCrit, meleeCrit)
end

local function GetHasteDisplayValue()
    return GetHaste() or 0
end

local function GetMasteryDisplayValue()
    return GetMasteryEffect() or 0
end

local function GetVersDisplayValue()
    local ratingBonus = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE_FALLBACK) or 0
    local baseBonus = GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE_FALLBACK) or 0
    return ratingBonus + baseBonus
end

local function GetSpeedDisplayValue()
    local currentSpeed, runSpeed = GetUnitSpeed("player")

    -- 用可达到的跑速（runSpeed），这样开加速技能会立即变化
    local speedValue = runSpeed or currentSpeed or BASE_MOVEMENT_SPEED
    if not speedValue or speedValue <= 0 then
        speedValue = BASE_MOVEMENT_SPEED
    end

    return (speedValue / BASE_MOVEMENT_SPEED) * 100
end

local function GetCurrentEquippedSetName()
    if not C_EquipmentSet
        or not C_EquipmentSet.GetEquipmentSetIDs
        or not C_EquipmentSet.GetEquipmentSetInfo
    then
        return "空"
    end

    local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
    if type(setIDs) ~= "table" then
        return "空"
    end

    for _, setID in ipairs(setIDs) do
        local name, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if isEquipped then
            if name and name ~= "" then
                return name
            end
            return "空"
        end
    end

    return "空"
end

local function GetDisplayDataForStat(statKey)
    if statKey == "primary" then
        local label, value = GetPrimaryDisplayValue()
        local rounded = Round1(value)
        return string.format("%s：%s", label, FormatPercentRounded(rounded)), rounded
    elseif statKey == "crit" then
        local rounded = Round1(GetCritDisplayValue())
        return string.format("暴击：%s", FormatPercentRounded(rounded)), rounded
    elseif statKey == "haste" then
        local rounded = Round1(GetHasteDisplayValue())
        return string.format("急速：%s", FormatPercentRounded(rounded)), rounded
    elseif statKey == "mastery" then
        local rounded = Round1(GetMasteryDisplayValue())
        return string.format("精通：%s", FormatPercentRounded(rounded)), rounded
    elseif statKey == "vers" then
        local rounded = Round1(GetVersDisplayValue())
        return string.format("全能：%s", FormatPercentRounded(rounded)), rounded
    elseif statKey == "speed" then
        local rounded = Round1(GetSpeedDisplayValue())
        return string.format("移速：%s", FormatPercentRounded(rounded)), rounded
    end

    return nil, nil
end

local function ResetStatTrend(statKey)
    if not DodoStatHUD.lastValues then
        DodoStatHUD.lastValues = {}
    end
    if not DodoStatHUD.lastTrends then
        DodoStatHUD.lastTrends = {}
    end
    if not DodoStatHUD.lastChangeTimes then
        DodoStatHUD.lastChangeTimes = {}
    end

    DodoStatHUD.lastValues[statKey] = nil
    DodoStatHUD.lastTrends[statKey] = 0
    DodoStatHUD.lastChangeTimes[statKey] = nil
end

local function SaveDisplayPosition()
    local left = DodoStatHUD:GetLeft()
    local top = DodoStatHUD:GetTop()

    if left and top then
        DB.left = left
        DB.top = top
    end
end

local function ApplyDisplayPosition()
    local left = DB.left
    local top = DB.top

    DodoStatHUD:ClearAllPoints()

    if type(left) == "number" and type(top) == "number" then
        -- 用 UIParent 左下角作参考，把框体左上角固定在绝对坐标
        DodoStatHUD:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    else
        -- 第一次没有保存过位置时，用默认位置先放中间偏右
        DodoStatHUD:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
        SaveDisplayPosition()
    end
end

local function ApplyLockState()
    if DB.locked then
        DodoStatHUD:EnableMouse(false)
        if DodoStatHUD.bg then
            DodoStatHUD.bg:Hide()
        end
    else
        DodoStatHUD:EnableMouse(true)
        if DodoStatHUD.bg then
            DodoStatHUD.bg:Show()
        end
    end
end

local function ApplyLineFont(fs)
    fs:SetFont(STANDARD_TEXT_FONT, DB.fontSize, "OUTLINE")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetJustifyH("LEFT")
end

local function ApplyArrowFont(fs)
    fs:SetFont(STANDARD_TEXT_FONT, DB.fontSize, "OUTLINE")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetJustifyH("LEFT")
end

local function UpdateTrendForStat(statKey, currentRounded)
    if not DodoStatHUD.lastValues then
        DodoStatHUD.lastValues = {}
    end
    if not DodoStatHUD.lastTrends then
        DodoStatHUD.lastTrends = {}
    end
    if not DodoStatHUD.lastChangeTimes then
        DodoStatHUD.lastChangeTimes = {}
    end

    local now = GetTime()
    local oldValue = DodoStatHUD.lastValues[statKey]
    local trend = DodoStatHUD.lastTrends[statKey] or 0
    local lastChangeTime = DodoStatHUD.lastChangeTimes[statKey]

    if oldValue ~= nil then
        if currentRounded > oldValue then
            trend = 1
            lastChangeTime = now
        elseif currentRounded < oldValue then
            trend = -1
            lastChangeTime = now
        end
    else
        trend = 0
        lastChangeTime = nil
    end

    local holdSeconds = ClampArrowHoldSeconds(DB.arrowHoldSeconds)
    if trend ~= 0 and lastChangeTime and (now - lastChangeTime) > holdSeconds then
        trend = 0
        lastChangeTime = nil
    end

    DodoStatHUD.lastValues[statKey] = currentRounded
    DodoStatHUD.lastTrends[statKey] = trend
    DodoStatHUD.lastChangeTimes[statKey] = lastChangeTime

    return trend
end

local function UpdateHUD()
    if not DB then
        return
    end

    local shown = 0
    local prevText
    local maxWidth = 0
    local lineSpacing = DB.fontSize + 4

    -- 顶部新增：当前装备方案
    local headerFS = DodoStatHUD.headerText
    ApplyLineFont(headerFS)
    headerFS:SetText(string.format("当前方案：%s", GetCurrentEquippedSetName()))
    headerFS:SetTextColor(1, 1, 1, 1)
    headerFS:ClearAllPoints()
    headerFS:SetPoint("TOPLEFT", DodoStatHUD, "TOPLEFT", 0, 0)
    headerFS:Show()

    prevText = headerFS
    maxWidth = math.max(maxWidth, headerFS:GetStringWidth() or 0)

    for _, statKey in ipairs(STAT_ORDER) do
        if DB.enabled[statKey] then
            shown = shown + 1

            local row = DodoStatHUD.lines[shown]
            local textFS = row.text
            local arrowFS = row.arrow

            -- 12.0 机密值:战斗中属性 API 返回 secret,无法比较/运算。
            -- pcall 包住计算,战斗中算不出来就沿用上次的值(脱战自动恢复实时),避免每帧报错。
            DodoStatHUD.lastDisplay = DodoStatHUD.lastDisplay or {}
            local ok, text, roundedValue = pcall(GetDisplayDataForStat, statKey)
            if ok then
                DodoStatHUD.lastDisplay[statKey] = { text = text, value = roundedValue }
            else
                local cached = DodoStatHUD.lastDisplay[statKey]
                text = (cached and cached.text) or "--"
                roundedValue = cached and cached.value
            end
            local r, g, b = GetStatColor(statKey)
            local trend = UpdateTrendForStat(statKey, roundedValue or 0)

            ApplyLineFont(textFS)
            textFS:SetText(text or "")
            textFS:SetTextColor(r, g, b, 1)
            textFS:ClearAllPoints()

            if prevText then
                textFS:SetPoint("TOPLEFT", prevText, "BOTTOMLEFT", 0, -2)
            else
                textFS:SetPoint("TOPLEFT", DodoStatHUD, "TOPLEFT", 0, 0)
            end

            textFS:Show()
            prevText = textFS

            ApplyArrowFont(arrowFS)
            arrowFS:ClearAllPoints()
            arrowFS:SetPoint("LEFT", textFS, "RIGHT", 4, 0)

            if trend > 0 then
                arrowFS:SetText(ARROW_UP)
                arrowFS:SetTextColor(ARROW_UP_COLOR[1], ARROW_UP_COLOR[2], ARROW_UP_COLOR[3], 1)
                arrowFS:Show()
            elseif trend < 0 then
                arrowFS:SetText(ARROW_DOWN)
                arrowFS:SetTextColor(ARROW_DOWN_COLOR[1], ARROW_DOWN_COLOR[2], ARROW_DOWN_COLOR[3], 1)
                arrowFS:Show()
            else
                arrowFS:SetText("")
                arrowFS:Hide()
            end

            local rowWidth = (textFS:GetStringWidth() or 0)
            if arrowFS:IsShown() then
                rowWidth = rowWidth + 4 + (arrowFS:GetStringWidth() or 0)
            end

            if rowWidth > maxWidth then
                maxWidth = rowWidth
            end
        end
    end

    for i = shown + 1, #DodoStatHUD.lines do
        local row = DodoStatHUD.lines[i]
        row.text:Hide()
        row.text:SetText("")
        row.arrow:Hide()
        row.arrow:SetText("")
    end

    -- 不管下面统计项开没开，至少显示“当前方案”这一行
    local totalRows = shown + 1
    local width = math.max(30, maxWidth + 8)
    local height = math.max(20, (totalRows * lineSpacing) - 2)

    DodoStatHUD:SetSize(width, height)
    if DodoStatHUD.bg then
        DodoStatHUD.bg:SetSize(width, height)
    end
end

local function RefreshOptionsPanel()
    if not optionsPanel then
        return
    end

    if optionsPanel.fontSizeValue then
        optionsPanel.fontSizeValue:SetText(tostring(DB.fontSize))
    end

    if optionsPanel.arrowHoldEdit then
        optionsPanel.arrowHoldEdit:SetText(FormatSeconds(DB.arrowHoldSeconds))
    end

    if optionsPanel.lockedCheck then
        optionsPanel.lockedCheck:SetChecked(DB.locked)
    end

    if optionsPanel.baselineText then
        local ok, key, label = pcall(GetCurrentPrimaryStatInfo)
        if ok and key then
            local base = DB.baselines[key]
            if base and base > 0 then
                optionsPanel.baselineText:SetText(string.format("当前基准：%s %d", label, base))
            else
                optionsPanel.baselineText:SetText(string.format("当前基准：%s 未设置", label))
            end
        end
    end

    if optionsPanel.statControls then
        for statKey, row in pairs(optionsPanel.statControls) do
            if row.check then
                row.check:SetChecked(DB.enabled[statKey])
            end
            if row.swatch then
                local c = DB.colors[statKey]
                row.swatch:SetColorTexture(c[1], c[2], c[3], 1)
            end
        end
    end
end

local function OpenColorPickerForStat(statKey)
    local c = DB.colors[statKey]
    if not c then
        return
    end

    local function ApplySelectedColor()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        DB.colors[statKey][1] = r
        DB.colors[statKey][2] = g
        DB.colors[statKey][3] = b
        UpdateHUD()
        RefreshOptionsPanel()
    end

    local info = {
        r = c[1],
        g = c[2],
        b = c[3],
        hasOpacity = false,
        swatchFunc = ApplySelectedColor,
        cancelFunc = function()
            local prev = ColorPickerFrame.previousValues
            if prev then
                DB.colors[statKey][1] = prev.r
                DB.colors[statKey][2] = prev.g
                DB.colors[statKey][3] = prev.b
                UpdateHUD()
                RefreshOptionsPanel()
            end
        end,
    }

    ColorPickerFrame:SetupColorPickerAndShow(info)
end

local function ApplyArrowHoldEditBoxValue(editBox)
    local value = tonumber(editBox:GetText())
    if value ~= nil then
        DB.arrowHoldSeconds = ClampArrowHoldSeconds(value)
    else
        DB.arrowHoldSeconds = ClampArrowHoldSeconds(DB.arrowHoldSeconds)
    end

    editBox:SetText(FormatSeconds(DB.arrowHoldSeconds))
    UpdateHUD()
    RefreshOptionsPanel()
end

local function CreateCheckbox(parent, labelText, x, y, onClick)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    label:SetText(labelText)

    check:SetScript("OnClick", function(self)
        onClick(self:GetChecked())
    end)

    check.label = label
    return check
end

local function CreateSmallButton(parent, width, height, text, x, y, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width, height)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    btn:SetText(text)
    btn:SetScript("OnClick", onClick)
    return btn
end

local function BuildOptionsPanel()
    optionsPanel = CreateFrame("Frame", "DodoStatHUDOptionsPanel", UIParent)
    optionsPanel.name = ADDON_NAME
    optionsPanel.statControls = {}

    local title = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("DodoStatHUD")

    local desc = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetWidth(700)
    desc:SetJustifyH("LEFT")
    desc:SetText("在屏幕上显示当前装备方案，以及主属性 / 暴击 / 急速 / 精通 / 全能 / 移动速度。主属性百分比基于你保存的“无 Buff 基准值”。箭头会在设定秒数后自动隐藏。")

    local fontLabel = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)
    fontLabel:SetText("统一字号")

    local minusBtn = CreateSmallButton(optionsPanel, 24, 22, "-", 16, -86, function()
        DB.fontSize = math.max(8, DB.fontSize - 1)
        UpdateHUD()
        RefreshOptionsPanel()
    end)

    local valueText = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    valueText:SetPoint("LEFT", minusBtn, "RIGHT", 12, 0)
    valueText:SetText(tostring(DB.fontSize))
    optionsPanel.fontSizeValue = valueText

    local plusBtn = CreateSmallButton(optionsPanel, 24, 22, "+", 92, -86, function()
        DB.fontSize = math.min(40, DB.fontSize + 1)
        UpdateHUD()
        RefreshOptionsPanel()
    end)

    local arrowHoldLabel = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    arrowHoldLabel:SetPoint("TOPLEFT", optionsPanel, "TOPLEFT", 16, -118)
    arrowHoldLabel:SetText("箭头保留秒数")

    local arrowHoldEdit = CreateFrame("EditBox", nil, optionsPanel, "InputBoxTemplate")
    arrowHoldEdit:SetSize(64, 24)
    arrowHoldEdit:SetPoint("LEFT", arrowHoldLabel, "RIGHT", 12, 0)
    arrowHoldEdit:SetAutoFocus(false)
    arrowHoldEdit:SetJustifyH("CENTER")
    arrowHoldEdit:SetMaxLetters(5)
    arrowHoldEdit:SetScript("OnEnterPressed", function(self)
        ApplyArrowHoldEditBoxValue(self)
        self:ClearFocus()
    end)
    arrowHoldEdit:SetScript("OnEscapePressed", function(self)
        self:SetText(FormatSeconds(DB.arrowHoldSeconds))
        self:ClearFocus()
    end)
    arrowHoldEdit:SetScript("OnEditFocusLost", function(self)
        ApplyArrowHoldEditBoxValue(self)
    end)
    optionsPanel.arrowHoldEdit = arrowHoldEdit

    local arrowHoldHint = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    arrowHoldHint:SetPoint("LEFT", arrowHoldEdit, "RIGHT", 8, 0)
    arrowHoldHint:SetText("(0.0 - 60.0)")

    local lockedCheck = CreateCheckbox(optionsPanel, "锁定 HUD（取消勾选后可直接拖动 HUD）", 16, -160, function(checked)
        DB.locked = checked and true or false
        ApplyLockState()
        RefreshOptionsPanel()
    end)
    optionsPanel.lockedCheck = lockedCheck

    local resetBtn = CreateSmallButton(optionsPanel, 120, 22, "重置 HUD 位置", 16, -186, function()
        DodoStatHUD:ClearAllPoints()
        DodoStatHUD:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
        SaveDisplayPosition()
        ApplyDisplayPosition()
    end)

    local baselineBtn = CreateSmallButton(optionsPanel, 180, 22, "保存当前主属性为基准", 150, -186, function()
        SaveCurrentPrimaryBaseline()
        ResetStatTrend("primary")
        UpdateHUD()
        RefreshOptionsPanel()
    end)

    local baselineText = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    baselineText:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 0, -10)
    baselineText:SetWidth(500)
    baselineText:SetJustifyH("LEFT")
    optionsPanel.baselineText = baselineText

    local listTitle = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    listTitle:SetPoint("TOPLEFT", baselineText, "BOTTOMLEFT", 0, -18)
    listTitle:SetText("监控项目（勾选显示 / 点右侧按钮改颜色）")

    local startY = -272
    local rowHeight = 28

    for index, statKey in ipairs(STAT_ORDER) do
        local rowY = startY - ((index - 1) * rowHeight)

        local check = CreateCheckbox(optionsPanel, OPTION_LABELS[statKey], 16, rowY, function(checked)
            DB.enabled[statKey] = checked and true or false
            if checked then
                ResetStatTrend(statKey)
            end
            UpdateHUD()
            RefreshOptionsPanel()
        end)

        local colorBtn = CreateSmallButton(optionsPanel, 64, 20, "颜色", 190, rowY + 4, function()
            OpenColorPickerForStat(statKey)
        end)

        local swatch = optionsPanel:CreateTexture(nil, "ARTWORK")
        swatch:SetSize(18, 12)
        swatch:SetPoint("LEFT", colorBtn, "RIGHT", 8, 0)

        optionsPanel.statControls[statKey] = {
            check = check,
            colorBtn = colorBtn,
            swatch = swatch,
        }
    end

    local slashDesc = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    slashDesc:SetPoint("TOPLEFT", optionsPanel, "TOPLEFT", 16, startY - (#STAT_ORDER * rowHeight) - 18)
    slashDesc:SetText("斜杠命令：/dshud")

    local category = Settings.RegisterCanvasLayoutCategory(optionsPanel, ADDON_NAME)
    Settings.RegisterAddOnCategory(category)
    settingsCategoryID = category:GetID()

    optionsPanel:SetScript("OnShow", function()
        RefreshOptionsPanel()
    end)
end

local function InitializeHUD()
    DodoStatHUD:SetClampedToScreen(true)
    DodoStatHUD:SetMovable(true)
    DodoStatHUD:RegisterForDrag("LeftButton")
    DodoStatHUD:SetFrameStrata("MEDIUM")

    DodoStatHUD.bg = DodoStatHUD:CreateTexture(nil, "BACKGROUND")
    DodoStatHUD.bg:SetAllPoints()
    DodoStatHUD.bg:SetColorTexture(0, 0, 0, 0.18)

    DodoStatHUD.lines = {}
    DodoStatHUD.lastValues = {}
    DodoStatHUD.lastTrends = {}
    DodoStatHUD.lastChangeTimes = {}

    DodoStatHUD.headerText = DodoStatHUD:CreateFontString(nil, "OVERLAY")

    for i = 1, #STAT_ORDER do
        local row = {}
        row.text = DodoStatHUD:CreateFontString(nil, "OVERLAY")
        row.arrow = DodoStatHUD:CreateFontString(nil, "OVERLAY")
        DodoStatHUD.lines[i] = row
    end

    DodoStatHUD:SetScript("OnDragStart", function(self)
        if not DB.locked then
            self:StartMoving()
        end
    end)

    DodoStatHUD:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveDisplayPosition()
    end)

    DodoStatHUD:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceUpdate = elapsedSinceUpdate + elapsed
        if elapsedSinceUpdate >= UPDATE_INTERVAL then
            elapsedSinceUpdate = 0
            UpdateHUD()
        end
    end)
end

local function OpenSettings()
    if settingsCategoryID then
        Settings.OpenToCategory(settingsCategoryID)
    end
end

SLASH_DODOSTATHUD1 = "/dshud"
SLASH_DODOSTATHUD2 = "/dodostathud"
SlashCmdList.DODOSTATHUD = OpenSettings

DodoStatHUD:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        DodoStatHUDDB = CopyDefaults(DEFAULTS, DodoStatHUDDB or {})
        DB = DodoStatHUDDB
        DB.arrowHoldSeconds = ClampArrowHoldSeconds(DB.arrowHoldSeconds)

        InitializeHUD()
        BuildOptionsPanel()
        EnsurePrimaryBaseline()

        for _, statKey in ipairs(STAT_ORDER) do
            ResetStatTrend(statKey)
        end

        -- 先算出内容尺寸，再应用位置，这样第一次保存 left/top 更稳
        UpdateHUD()
        ApplyDisplayPosition()
        ApplyLockState()
        RefreshOptionsPanel()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        for _, statKey in ipairs(STAT_ORDER) do
            ResetStatTrend(statKey)
        end
        UpdateHUD()
        RefreshOptionsPanel()
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        ResetStatTrend("primary")
        UpdateHUD()
        RefreshOptionsPanel()
        return
    end
end)

DodoStatHUD:RegisterEvent("PLAYER_LOGIN")
DodoStatHUD:RegisterEvent("PLAYER_ENTERING_WORLD")
DodoStatHUD:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")