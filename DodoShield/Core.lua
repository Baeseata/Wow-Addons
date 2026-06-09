DodoShield = DodoShield or {}
local DS = DodoShield

local DEFAULT_PRESET_NAME = "默认"

local function MakeDefaultPreset(name)
    return {
        name = name or DEFAULT_PRESET_NAME,
        bossId = nil,
        appearance = {
            fontSize = 72,
            color = { 1, 1, 1, 1 },
            xOffset = 0,
            yOffset = 200,
            locked = true,
            soundEnabled = false,
            soundId = 8959,
        },
        rows = {
            { seconds = 180, duration = 5, text = "放罩子" },
        },
    }
end

function DS.InitDB()
    if type(DodoShieldDB) ~= "table" then DodoShieldDB = {} end
    if type(DodoShieldDB.presets) ~= "table" then DodoShieldDB.presets = {} end
    if not next(DodoShieldDB.presets) then
        DodoShieldDB.presets[DEFAULT_PRESET_NAME] = MakeDefaultPreset(DEFAULT_PRESET_NAME)
    end
    for name, p in pairs(DodoShieldDB.presets) do
        p.name = name
        p.appearance = p.appearance or {}
        local a = p.appearance
        a.fontSize = a.fontSize or 72
        a.color = a.color or { 1, 1, 1, 1 }
        a.xOffset = a.xOffset or 0
        a.yOffset = a.yOffset or 200
        if a.locked == nil then a.locked = true end
        if a.soundEnabled == nil then a.soundEnabled = false end
        a.soundId = a.soundId or 8959
        p.rows = p.rows or {}
    end
    if not DodoShieldDB.activePreset or not DodoShieldDB.presets[DodoShieldDB.activePreset] then
        DodoShieldDB.activePreset = next(DodoShieldDB.presets)
    end
end

function DS.GetActivePreset()
    if not DodoShieldDB or not DodoShieldDB.presets then return nil end
    return DodoShieldDB.presets[DodoShieldDB.activePreset]
end

function DS.SetActivePreset(name)
    if DodoShieldDB.presets[name] then
        DodoShieldDB.activePreset = name
        DS.ApplyAppearance()
        return true
    end
    return false
end

function DS.NewPreset(name)
    if not name or name == "" then return false, "名称不能为空" end
    if DodoShieldDB.presets[name] then return false, "该名称已存在" end
    DodoShieldDB.presets[name] = MakeDefaultPreset(name)
    DodoShieldDB.activePreset = name
    DS.ApplyAppearance()
    return true
end

function DS.RenamePreset(oldName, newName)
    if not newName or newName == "" then return false, "名称不能为空" end
    if oldName == newName then return true end
    if DodoShieldDB.presets[newName] then return false, "该名称已存在" end
    local p = DodoShieldDB.presets[oldName]
    if not p then return false, "方案不存在" end
    p.name = newName
    DodoShieldDB.presets[newName] = p
    DodoShieldDB.presets[oldName] = nil
    if DodoShieldDB.activePreset == oldName then
        DodoShieldDB.activePreset = newName
    end
    return true
end

function DS.DeletePreset(name)
    if not DodoShieldDB.presets[name] then return false end
    DodoShieldDB.presets[name] = nil
    local any
    for n in pairs(DodoShieldDB.presets) do any = n; break end
    if not any then
        DodoShieldDB.presets[DEFAULT_PRESET_NAME] = MakeDefaultPreset(DEFAULT_PRESET_NAME)
        DodoShieldDB.activePreset = DEFAULT_PRESET_NAME
    elseif DodoShieldDB.activePreset == name then
        DodoShieldDB.activePreset = any
    end
    DS.ApplyAppearance()
    return true
end

function DS.ParseTime(str)
    if type(str) == "number" then return str end
    str = tostring(str or ""):gsub("%s", "")
    local m, s = str:match("^(%d+):(%d+)$")
    if m then return tonumber(m) * 60 + tonumber(s) end
    return tonumber(str)
end

function DS.FormatTime(sec)
    sec = tonumber(sec) or 0
    local m = math.floor(sec / 60)
    local s = math.floor(sec - m * 60)
    return string.format("%d:%02d", m, s)
end

function DS.SortRows(preset)
    if not preset or not preset.rows then return end
    table.sort(preset.rows, function(a, b)
        return (a.seconds or 0) < (b.seconds or 0)
    end)
end

local display = CreateFrame("Frame", "DodoShieldDisplay", UIParent)
display:SetSize(800, 140)
display:SetFrameStrata("HIGH")
display:SetMovable(true)
display:RegisterForDrag("LeftButton")
display:SetClampedToScreen(true)
display:Hide()

local border = display:CreateTexture(nil, "BACKGROUND")
border:SetAllPoints()
border:SetColorTexture(0.2, 0.8, 0.2, 0.25)
border:Hide()

local text = display:CreateFontString(nil, "OVERLAY")
text:SetPoint("CENTER", display, "CENTER")
text:SetTextColor(1, 1, 1, 1)

DS.display = display
DS.displayText = text

local reminderTimer
local reminderActive = false

display:SetScript("OnDragStart", function(self) self:StartMoving() end)
display:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local preset = DS.GetActivePreset()
    if not preset then return end
    local cx = (self:GetLeft() + self:GetRight()) / 2
    local cy = (self:GetTop() + self:GetBottom()) / 2
    local ux = UIParent:GetLeft() + UIParent:GetWidth() / 2
    local uy = UIParent:GetBottom() + UIParent:GetHeight() / 2
    preset.appearance.xOffset = cx - ux
    preset.appearance.yOffset = cy - uy
    DS.ApplyAppearance()
end)

function DS.ApplyAppearance()
    local preset = DS.GetActivePreset()
    if not preset then return end
    local a = preset.appearance
    local size = a.fontSize or 72
    text:SetFont("Fonts\\ARKai_T.ttf", size, "OUTLINE")
    if not text:GetFont() then
        text:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE")
    end
    local c = a.color or { 1, 1, 1, 1 }
    text:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    display:ClearAllPoints()
    display:SetPoint("CENTER", UIParent, "CENTER", a.xOffset or 0, a.yOffset or 200)
    if a.locked then
        display:EnableMouse(false)
        border:Hide()
        if not reminderActive then
            text:SetText("")
            display:Hide()
        end
    else
        display:EnableMouse(true)
        border:Show()
        display:Show()
        if not reminderActive then
            text:SetText("放罩子")
        end
    end
end

function DS.ShowReminder(str, duration)
    reminderActive = true
    text:SetText(str or "")
    display:Show()
    if reminderTimer then reminderTimer:Cancel() end
    reminderTimer = C_Timer.NewTimer(duration or 5, function()
        reminderActive = false
        local preset = DS.GetActivePreset()
        if preset and preset.appearance.locked then
            text:SetText("")
            display:Hide()
        else
            text:SetText("放罩子")
        end
    end)
end

function DS.TestRow(row)
    DS.ApplyAppearance()
    DS.ShowReminder(row.text or "", row.duration or 5)
    local preset = DS.GetActivePreset()
    if preset and preset.appearance.soundEnabled then
        PlaySound(preset.appearance.soundId or 8959, "Master")
    end
end

local combatId = 0
local combatTimers = {}

local function CancelAllTimers()
    for _, t in ipairs(combatTimers) do
        if t and t.Cancel then t:Cancel() end
    end
    wipe(combatTimers)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        DS.InitDB()
        DS.ApplyAppearance()
    elseif event == "PLAYER_REGEN_DISABLED" then
        combatId = combatId + 1
        local myId = combatId
        local preset = DS.GetActivePreset()
        if not preset or not preset.rows then return end
        CancelAllTimers()
        for _, row in ipairs(preset.rows) do
            local r = row
            local t = C_Timer.NewTimer(r.seconds or 0, function()
                if myId ~= combatId then return end
                DS.ShowReminder(r.text, r.duration)
                if preset.appearance.soundEnabled then
                    PlaySound(preset.appearance.soundId or 8959, "Master")
                end
            end)
            table.insert(combatTimers, t)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        combatId = combatId + 1
        CancelAllTimers()
        reminderActive = false
        if reminderTimer then reminderTimer:Cancel() end
        local preset = DS.GetActivePreset()
        if preset and preset.appearance.locked then
            text:SetText("")
            display:Hide()
        else
            text:SetText("放罩子")
        end
    end
end)
