local addonName = ...

local DodoUnholy = CreateFrame("Frame")
_G[addonName] = DodoUnholy

local defaults = {
    summonReminder = true,
    fontSize = 36,
    offsetY = 180,
    rotation = {
        enabled = true,
        iconSize = 64,
        posX = 0,
        posY = -150,
        locked = true,
        showOutOfCombat = true,
    },
}

local function copyDefaults(src, dst)
    if type(src) ~= "table" then
        return dst
    end

    if type(dst) ~= "table" then
        dst = {}
    end

    for key, value in pairs(src) do
        if type(value) == "table" then
            dst[key] = copyDefaults(value, dst[key])
        elseif dst[key] == nil then
            dst[key] = value
        end
    end

    return dst
end

local function isPlayerOnGround()
    if IsMounted and IsMounted() then
        return false
    end

    if UnitOnTaxi and UnitOnTaxi("player") then
        return false
    end

    if UnitUsingVehicle and UnitUsingVehicle("player") then
        return false
    end

    if UnitInVehicle and UnitInVehicle("player") then
        return false
    end

    if UnitHasVehicleUI and UnitHasVehicleUI("player") then
        return false
    end

    return true
end

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end

    if value > maxValue then
        return maxValue
    end

    return value
end

function DodoUnholy:IsGhoulPresent()
    return UnitExists("pet") and not UnitIsDeadOrGhost("pet")
end

local UNHOLY_SPEC_ID = 252

-- Spec API: prefer C_SpecializationInfo namespace, fall back to deprecated globals (still present in 12.0.5)
local function GetSpec()
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        return C_SpecializationInfo.GetSpecialization()
    end
    if GetSpecialization then return GetSpecialization() end
    return nil
end

local function GetSpecInfo(specIndex)
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
        return C_SpecializationInfo.GetSpecializationInfo(specIndex)
    end
    if GetSpecializationInfo then return GetSpecializationInfo(specIndex) end
    return nil
end

function DodoUnholy:IsUnholyDeathKnight()
    local _, classTag = UnitClass("player")
    if classTag ~= "DEATHKNIGHT" then
        return false
    end

    local specIndex = GetSpec()
    if not specIndex then
        return false
    end

    local specID = GetSpecInfo(specIndex)
    return specID == UNHOLY_SPEC_ID
end

function DodoUnholy:ShouldShowSummonReminder()
    if not self:IsUnholyDeathKnight() then
        return false
    end

    if not self.db or not self.db.summonReminder then
        return false
    end

    if not isPlayerOnGround() then
        return false
    end

    return not self:IsGhoulPresent()
end

function DodoUnholy:ApplyWarningAppearance()
    if not self.warningFrame or not self.warningText then
        return
    end

    local fontPath = select(1, self.warningText:GetFont()) or STANDARD_TEXT_FONT
    local fontSize = clamp(tonumber(self.db and self.db.fontSize) or defaults.fontSize, 8, 72)
    local offsetY = clamp(tonumber(self.db and self.db.offsetY) or defaults.offsetY, -500, 500)

    self.db.fontSize = fontSize
    self.db.offsetY = offsetY

    if fontPath then
        self.warningText:SetFont(fontPath, fontSize, "OUTLINE")
    end

    self.warningFrame:ClearAllPoints()
    self.warningFrame:SetPoint("CENTER", UIParent, "CENTER", 0, offsetY)
end

function DodoUnholy:RefreshWarnings()
    if not self.warningFrame or not self.warningText then
        return
    end

    if self:ShouldShowSummonReminder() then
        self.warningText:SetText("宝宝没啦~~")
        self.warningText:Show()
        self.warningFrame:Show()
    else
        self.warningText:SetText("")
        self.warningText:Hide()
        self.warningFrame:Hide()
    end
end

function DodoUnholy:CreateWarningFrame()
    local frame = CreateFrame("Frame", addonName .. "WarningFrame", UIParent)
    frame:SetSize(500, 80)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, defaults.offsetY)
    frame:Hide()

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetTextColor(1, 0.1, 0.1, 1)
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 1)

    self.warningFrame = frame
    self.warningText = text

    self:ApplyWarningAppearance()
end

function DodoUnholy:ApplyFontSizeFromEditBox(editBox)
    local value = tonumber(editBox:GetText())
    if not value then
        editBox:SetText(tostring(self.db.fontSize))
        return
    end

    self.db.fontSize = clamp(math.floor(value + 0.5), 8, 72)
    editBox:SetText(tostring(self.db.fontSize))
    self:ApplyWarningAppearance()
    self:RefreshWarnings()
end

function DodoUnholy:ApplyOffsetYFromEditBox(editBox)
    local value = tonumber(editBox:GetText())
    if not value then
        editBox:SetText(tostring(self.db.offsetY))
        return
    end

    self.db.offsetY = clamp(math.floor(value + 0.5), -500, 500)
    editBox:SetText(tostring(self.db.offsetY))
    self:ApplyWarningAppearance()
    self:RefreshWarnings()
end

function DodoUnholy:CreateLabeledEditBox(panel, labelText, x, y, initialValue, onCommit, onEscape)
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(labelText)

    local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    box:SetSize(80, 24)
    box:SetPoint("LEFT", label, "RIGHT", 12, 0)
    box:SetAutoFocus(false)
    box:SetText(tostring(initialValue))
    box:SetCursorPosition(0)

    box:SetScript("OnEnterPressed", function(editBox)
        onCommit(editBox)
        editBox:ClearFocus()
    end)

    box:SetScript("OnEscapePressed", function(editBox)
        if onEscape then
            onEscape(editBox)
        else
            editBox:SetText(tostring(initialValue))
        end
        editBox:ClearFocus()
    end)

    box:SetScript("OnEditFocusLost", function(editBox)
        onCommit(editBox)
    end)

    return box, label
end

function DodoUnholy:CreateOptionsPanel()
    local panel = CreateFrame("Frame", addonName .. "OptionsPanel", UIParent)
    panel.name = addonName

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("DodoUnholy")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetWidth(700)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("仅保留“宝宝呢？”提醒。可调整开关、字体大小和纵向位置（Y 值）。")

    local summonCheck = CreateFrame("CheckButton", addonName .. "SummonReminderCheck", panel, "UICheckButtonTemplate")
    summonCheck:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -18)
    summonCheck:SetChecked(self.db.summonReminder)
    _G[summonCheck:GetName() .. "Text"]:SetText("召唤宝宝提醒")
    summonCheck:SetScript("OnClick", function(button)
        self.db.summonReminder = button:GetChecked() and true or false
        self:RefreshWarnings()
    end)

    local fontSizeBox = self:CreateLabeledEditBox(
        panel,
        "字体大小",
        22,
        -110,
        self.db.fontSize,
        function(editBox)
            self:ApplyFontSizeFromEditBox(editBox)
        end,
        function(editBox)
            editBox:SetText(tostring(self.db.fontSize))
        end
    )

    local offsetYBox = self:CreateLabeledEditBox(
        panel,
        "位置 Y",
        22,
        -150,
        self.db.offsetY,
        function(editBox)
            self:ApplyOffsetYFromEditBox(editBox)
        end,
        function(editBox)
            editBox:SetText(tostring(self.db.offsetY))
        end
    )

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", offsetYBox, "BOTTOMLEFT", -2, -12)
    hint:SetWidth(700)
    hint:SetJustifyH("LEFT")
    hint:SetText("字体大小范围 8~72；Y 值范围 -500~500。按回车或失去焦点后立即生效。")

    panel:SetScript("OnShow", function()
        summonCheck:SetChecked(self.db.summonReminder)
        fontSizeBox:SetText(tostring(self.db.fontSize))
        offsetYBox:SetText(tostring(self.db.offsetY))
    end)

    -- 出招助手 (Rotation.lua) 在此追加它自己的选项区
    -- (须放在主 OnShow 的 SetScript 之后,其内部 HookScript 才能叠加而不被覆盖)
    if self.AddRotationOptions then
        self:AddRotationOptions(panel, hint)
    end

    self.optionsPanel = panel
    self.fontSizeBox = fontSizeBox
    self.offsetYBox = offsetYBox

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, addonName)
        Settings.RegisterAddOnCategory(category)
        if category and category.GetID then
            self.categoryID = category:GetID()
        end
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function DodoUnholy:OpenOptions()
    if Settings and Settings.OpenToCategory and self.categoryID then
        Settings.OpenToCategory(self.categoryID)
    elseif InterfaceOptionsFrame_OpenToCategory and self.optionsPanel then
        InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
    end
end

function DodoUnholy:Initialize()
    DodoUnholyDB = copyDefaults(defaults, DodoUnholyDB)
    self.db = DodoUnholyDB

    self:CreateWarningFrame()
    self:CreateOptionsPanel()
    if self.InitRotation then
        self:InitRotation()
    end
    self:RefreshWarnings()

    SLASH_DODOUNHOLY1 = "/dodounholy"
    SLASH_DODOUNHOLY2 = "/duh"
    SlashCmdList.DODOUNHOLY = function(msg)
        msg = msg and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
        if msg == "config" or msg == "settings" or msg == "option" or msg == "options" then
            self:OpenOptions()
        elseif msg == "scan" and self.ScanBars then
            self:ScanBars()
        elseif msg == "debug" and self.DebugRotation then
            self:DebugRotation()
        -- ⛔ `cl`(战斗日志探针)已于 2026-08-22 连同 `Rotation.lua` 里的
        --    `ProbeCombatLog` 一起删除 —— 注册 COMBAT_LOG_EVENT_UNFILTERED 会抛
        --    ADDON_ACTION_FORBIDDEN 并污染当时的调用栈。理由和证据出处见 Rotation.lua
        --    里原地那段注释。**别把这个分支加回来。**
        elseif msg == "lock" then
            self.db.rotation.locked = true
            self:ApplyRotationAppearance()
            print("|cff33ff99DodoUnholy|r：出招图标已锁定。")
        elseif msg == "unlock" then
            self.db.rotation.locked = false
            self:ApplyRotationAppearance()
            print("|cff33ff99DodoUnholy|r：出招图标已解锁,拖动它移动位置。")
        else
            print("|cff33ff99DodoUnholy|r：/duh config 设置 | scan 导出技能ID | debug 实时读数 | lock/unlock 锁定/解锁图标。")
        end
    end
end

DodoUnholy:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName == addonName then
            DodoUnholy:Initialize()
        end
        return
    end

    if event == "UNIT_PET" then
        local unit = ...
        if unit == "player" then
            DodoUnholy:RefreshWarnings()
        end
        return
    end

    DodoUnholy:RefreshWarnings()
end)

DodoUnholy:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
DodoUnholy:RegisterEvent("ADDON_LOADED")
DodoUnholy:RegisterEvent("PLAYER_ENTERING_WORLD")
DodoUnholy:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
DodoUnholy:RegisterEvent("PLAYER_CONTROL_GAINED")
DodoUnholy:RegisterEvent("PLAYER_CONTROL_LOST")
DodoUnholy:RegisterEvent("PLAYER_REGEN_DISABLED")
DodoUnholy:RegisterEvent("PLAYER_REGEN_ENABLED")
DodoUnholy:RegisterEvent("UNIT_PET")
DodoUnholy:RegisterEvent("UNIT_ENTERED_VEHICLE")
DodoUnholy:RegisterEvent("UNIT_EXITED_VEHICLE")
