local DS = DodoShield
local panel, presetDropdown, rowScrollContent, appearanceWidgets
local addRowBtn
local rowPool = {}

local RefreshAll, RefreshRows, RefreshPresetDropdown, RefreshAppearance

StaticPopupDialogs["DODOSHIELD_NEW_PRESET"] = {
    text = "输入新方案名称:",
    button1 = "确定",
    button2 = "取消",
    hasEditBox = true,
    OnShow = function(self)
        self.editBox:SetText("")
        self.editBox:SetFocus()
    end,
    OnAccept = function(self)
        local ok, err = DS.NewPreset(self.editBox:GetText())
        if not ok and err then print("|cffff4040[DodoShield]|r " .. err) end
        RefreshAll()
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local ok, err = DS.NewPreset(self:GetText())
        if not ok and err then print("|cffff4040[DodoShield]|r " .. err) end
        parent:Hide()
        RefreshAll()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["DODOSHIELD_RENAME_PRESET"] = {
    text = "输入新名称:",
    button1 = "确定",
    button2 = "取消",
    hasEditBox = true,
    OnShow = function(self)
        self.editBox:SetText(DodoShieldDB.activePreset or "")
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    OnAccept = function(self)
        local ok, err = DS.RenamePreset(DodoShieldDB.activePreset, self.editBox:GetText())
        if not ok and err then print("|cffff4040[DodoShield]|r " .. err) end
        RefreshAll()
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local ok, err = DS.RenamePreset(DodoShieldDB.activePreset, self:GetText())
        if not ok and err then print("|cffff4040[DodoShield]|r " .. err) end
        parent:Hide()
        RefreshAll()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["DODOSHIELD_DELETE_PRESET"] = {
    text = "确定删除当前方案?",
    button1 = "确定",
    button2 = "取消",
    OnAccept = function()
        DS.DeletePreset(DodoShieldDB.activePreset)
        RefreshAll()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function CreateRowFrame()
    local row = CreateFrame("Frame", nil, rowScrollContent)
    row:SetSize(500, 26)

    local secEdit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    secEdit:SetSize(70, 20)
    secEdit:SetPoint("LEFT", row, "LEFT", 10, 0)
    secEdit:SetAutoFocus(false)

    local durEdit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    durEdit:SetSize(50, 20)
    durEdit:SetPoint("LEFT", secEdit, "RIGHT", 18, 0)
    durEdit:SetAutoFocus(false)

    local txtEdit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    txtEdit:SetSize(160, 20)
    txtEdit:SetPoint("LEFT", durEdit, "RIGHT", 18, 0)
    txtEdit:SetAutoFocus(false)

    local testBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    testBtn:SetSize(50, 20)
    testBtn:SetPoint("LEFT", txtEdit, "RIGHT", 12, 0)
    testBtn:SetText("测试")

    local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    delBtn:SetSize(50, 20)
    delBtn:SetPoint("LEFT", testBtn, "RIGHT", 4, 0)
    delBtn:SetText("删除")

    row.secEdit, row.durEdit, row.txtEdit = secEdit, durEdit, txtEdit
    row.testBtn, row.delBtn = testBtn, delBtn
    return row
end

local function GetRowFrame(i)
    if not rowPool[i] then rowPool[i] = CreateRowFrame() end
    return rowPool[i]
end

RefreshRows = function()
    local preset = DS.GetActivePreset()
    if not preset or not rowScrollContent then return end
    DS.SortRows(preset)

    for _, f in pairs(rowPool) do f:Hide() end

    for i, rowData in ipairs(preset.rows) do
        local f = GetRowFrame(i)
        f:Show()
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", rowScrollContent, "TOPLEFT", 0, -(i - 1) * 28)

        f.secEdit:SetText(DS.FormatTime(rowData.seconds or 0))
        f.durEdit:SetText(tostring(rowData.duration or 5))
        f.txtEdit:SetText(rowData.text or "")

        f.secEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        f.secEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        f.secEdit:SetScript("OnEditFocusLost", function(self)
            local s = DS.ParseTime(self:GetText())
            if s then rowData.seconds = s end
            RefreshRows()
        end)

        f.durEdit:SetScript("OnTextChanged", function(self)
            local n = tonumber(self:GetText())
            if n and n > 0 then rowData.duration = n end
        end)
        f.durEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        f.durEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        f.txtEdit:SetScript("OnTextChanged", function(self)
            rowData.text = self:GetText()
        end)
        f.txtEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        f.txtEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        f.testBtn:SetScript("OnClick", function() DS.TestRow(rowData) end)

        local idx = i
        f.delBtn:SetScript("OnClick", function()
            table.remove(preset.rows, idx)
            RefreshRows()
        end)
    end

    rowScrollContent:SetHeight(math.max(1, #preset.rows * 28))
end

RefreshPresetDropdown = function()
    if not presetDropdown then return end
    presetDropdown:SetupMenu(function(_, rootDescription)
        local names = {}
        for n in pairs(DodoShieldDB.presets) do table.insert(names, n) end
        table.sort(names)
        for _, name in ipairs(names) do
            rootDescription:CreateRadio(name,
                function() return DodoShieldDB.activePreset == name end,
                function()
                    DS.SetActivePreset(name)
                    RefreshAll()
                end)
        end
    end)
    presetDropdown:SetDefaultText(DodoShieldDB.activePreset or "选择方案")
    presetDropdown:GenerateMenu()
end

RefreshAppearance = function()
    local preset = DS.GetActivePreset()
    if not preset or not appearanceWidgets then return end
    local a = preset.appearance
    local w = appearanceWidgets
    w.slider:SetValue(a.fontSize or 72)
    _G[w.slider:GetName() .. "Text"]:SetText("字体大小: " .. (a.fontSize or 72))
    local c = a.color
    w.colorSwatch:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1)
    w.lockCB:SetChecked(not a.locked)
    w.soundCB:SetChecked(a.soundEnabled and true or false)
end

RefreshAll = function()
    if not DodoShieldDB then return end
    RefreshPresetDropdown()
    RefreshRows()
    RefreshAppearance()
end

local function BuildPanel()
    panel = CreateFrame("Frame", "DodoShieldOptionsPanel")
    panel.name = "DodoShield"
    panel:Hide()

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("DodoShield")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText("进战斗按时间提醒")

    local presetLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    presetLabel:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -20)
    presetLabel:SetText("方案:")

    presetDropdown = CreateFrame("DropdownButton", "DodoShieldPresetDropdown", panel, "WowStyle1DropdownTemplate")
    presetDropdown:SetPoint("LEFT", presetLabel, "RIGHT", 6, 0)
    presetDropdown:SetWidth(160)

    local newBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    newBtn:SetSize(60, 22)
    newBtn:SetPoint("LEFT", presetDropdown, "RIGHT", 6, 0)
    newBtn:SetText("新建")
    newBtn:SetScript("OnClick", function() StaticPopup_Show("DODOSHIELD_NEW_PRESET") end)

    local renameBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    renameBtn:SetSize(70, 22)
    renameBtn:SetPoint("LEFT", newBtn, "RIGHT", 4, 0)
    renameBtn:SetText("重命名")
    renameBtn:SetScript("OnClick", function() StaticPopup_Show("DODOSHIELD_RENAME_PRESET") end)

    local delPresetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    delPresetBtn:SetSize(80, 22)
    delPresetBtn:SetPoint("LEFT", renameBtn, "RIGHT", 4, 0)
    delPresetBtn:SetText("删除方案")
    delPresetBtn:SetScript("OnClick", function() StaticPopup_Show("DODOSHIELD_DELETE_PRESET") end)

    local colHeaderY = -100
    local h
    h = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h:SetPoint("TOPLEFT", panel, "TOPLEFT", 26, colHeaderY)
    h:SetText("时间(分:秒)")
    h = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h:SetPoint("TOPLEFT", panel, "TOPLEFT", 116, colHeaderY)
    h:SetText("持续(秒)")
    h = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h:SetPoint("TOPLEFT", panel, "TOPLEFT", 200, colHeaderY)
    h:SetText("提醒内容")

    local scrollFrame = CreateFrame("ScrollFrame", "DodoShieldRowScroll", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, colHeaderY - 20)
    scrollFrame:SetSize(520, 170)

    rowScrollContent = CreateFrame("Frame", nil, scrollFrame)
    rowScrollContent:SetSize(500, 1)
    scrollFrame:SetScrollChild(rowScrollContent)

    addRowBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addRowBtn:SetSize(100, 22)
    addRowBtn:SetPoint("TOPLEFT", scrollFrame, "BOTTOMLEFT", 0, -6)
    addRowBtn:SetText("+ 新增行")
    addRowBtn:SetScript("OnClick", function()
        local preset = DS.GetActivePreset()
        if not preset then return end
        table.insert(preset.rows, { seconds = 0, duration = 5, text = "" })
        RefreshRows()
    end)

    local appY = colHeaderY - 240
    local sectionLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    sectionLabel:SetPoint("TOPLEFT", 16, appY)
    sectionLabel:SetText("外观 (每方案独立)")

    local slider = CreateFrame("Slider", "DodoShieldFontSlider", panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 32, appY - 34)
    slider:SetMinMaxValues(12, 144)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(200)
    _G[slider:GetName() .. "Low"]:SetText("12")
    _G[slider:GetName() .. "High"]:SetText("144")
    slider:SetScript("OnValueChanged", function(self, v)
        local preset = DS.GetActivePreset()
        if not preset then return end
        local iv = math.floor(v + 0.5)
        preset.appearance.fontSize = iv
        _G[self:GetName() .. "Text"]:SetText("字体大小: " .. iv)
        DS.ApplyAppearance()
    end)

    local colorBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    colorBtn:SetSize(90, 22)
    colorBtn:SetPoint("LEFT", slider, "RIGHT", 30, 0)
    colorBtn:SetText("字体颜色")
    local colorSwatch = colorBtn:CreateTexture(nil, "OVERLAY")
    colorSwatch:SetSize(18, 18)
    colorSwatch:SetPoint("LEFT", colorBtn, "RIGHT", 6, 0)
    colorSwatch:SetColorTexture(1, 1, 1, 1)
    colorBtn:SetScript("OnClick", function()
        local preset = DS.GetActivePreset()
        if not preset then return end
        local c = preset.appearance.color
        local function apply()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            local na = 1
            if ColorPickerFrame.GetColorAlpha then na = ColorPickerFrame:GetColorAlpha() end
            preset.appearance.color = { nr, ng, nb, na }
            colorSwatch:SetColorTexture(nr, ng, nb, 1)
            DS.ApplyAppearance()
        end
        local info = {
            r = c[1], g = c[2], b = c[3], opacity = c[4] or 1, hasOpacity = true,
            swatchFunc = apply,
            opacityFunc = apply,
            cancelFunc = function(prev)
                preset.appearance.color = { prev.r, prev.g, prev.b, prev.opacity or 1 }
                colorSwatch:SetColorTexture(prev.r, prev.g, prev.b, 1)
                DS.ApplyAppearance()
            end,
        }
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow(info)
        else
            ColorPickerFrame:Hide()
            ColorPickerFrame.func = info.swatchFunc
            ColorPickerFrame.opacityFunc = info.opacityFunc
            ColorPickerFrame.cancelFunc = info.cancelFunc
            ColorPickerFrame.hasOpacity = true
            ColorPickerFrame.opacity = info.opacity
            ColorPickerFrame.previousValues = { r = c[1], g = c[2], b = c[3], opacity = c[4] or 1 }
            ColorPickerFrame:SetColorRGB(c[1], c[2], c[3])
            ColorPickerFrame:Show()
        end
    end)

    local lockCB = CreateFrame("CheckButton", "DodoShieldLockCB", panel, "UICheckButtonTemplate")
    lockCB:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, -26)
    lockCB:SetSize(24, 24)
    local lockLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lockLbl:SetPoint("LEFT", lockCB, "RIGHT", 4, 0)
    lockLbl:SetText("解锁位置 (可拖动)")
    lockCB:SetScript("OnClick", function(self)
        local preset = DS.GetActivePreset()
        if not preset then return end
        preset.appearance.locked = not self:GetChecked()
        DS.ApplyAppearance()
    end)

    local soundCB = CreateFrame("CheckButton", "DodoShieldSoundCB", panel, "UICheckButtonTemplate")
    soundCB:SetPoint("LEFT", lockLbl, "RIGHT", 40, 0)
    soundCB:SetSize(24, 24)
    local soundLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    soundLbl:SetPoint("LEFT", soundCB, "RIGHT", 4, 0)
    soundLbl:SetText("启用声音提示")
    soundCB:SetScript("OnClick", function(self)
        local preset = DS.GetActivePreset()
        if not preset then return end
        preset.appearance.soundEnabled = self:GetChecked() and true or false
    end)

    appearanceWidgets = {
        slider = slider,
        colorBtn = colorBtn,
        colorSwatch = colorSwatch,
        lockCB = lockCB,
        soundCB = soundCB,
    }

    panel:SetScript("OnShow", RefreshAll)
end

local function RegisterPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "DodoShield")
        category.ID = "DodoShield"
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

local init = CreateFrame("Frame")
init:RegisterEvent("ADDON_LOADED")
init:SetScript("OnEvent", function(self, _, name)
    if name == "DodoShield" then
        DS.InitDB()
        BuildPanel()
        RegisterPanel()
        self:UnregisterAllEvents()
    end
end)
