-- DodoNumbers - Options (Compatible: old InterfaceOptions + new Settings)
local DN = _G.DodoNumbers
if not DN then return end

local function CreateLabel(parent, text, font, x, y)
  local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormal")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetText(text)
  return fs
end

local function CreateEditBox(parent, width, height, x, y)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetSize(width, height)
  eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  eb:SetAutoFocus(false)
  eb:SetTextInsets(6, 6, 0, 0)
  return eb
end

local function CreateCheck(parent, label, x, y)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  cb.Text:SetText(label)
  return cb
end

local function CreateButton(parent, label, w, h, x, y)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:SetText(label)
  return b
end

local function CreateDropdown(parent, label, x, y, width)
  CreateLabel(parent, label, "GameFontNormal", x, y)
  local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 140, y + 12)
  dd:SetWidth(width or 140)
  return dd
end

local function OpenOptions(panel, settingsCategory)
  if Settings and Settings.OpenToCategory then
    if settingsCategory and settingsCategory.GetID then
      Settings.OpenToCategory(settingsCategory:GetID())
      return
    end
    Settings.OpenToCategory("DodoNumbers")
    return
  end
  if InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel) -- old UI sometimes needs twice
  end
end

function DN:InitOptions()
  if self.optionsInited then return end
  self.optionsInited = true

  local panel = CreateFrame("Frame", "DodoNumbersOptionsPanel", UIParent)
  panel.name = "DodoNumbers"
  self.optionsPanel = panel

  local settingsCategory = nil
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, "DodoNumbers")
    Settings.RegisterAddOnCategory(settingsCategory)
  end
  self.settingsCategory = settingsCategory

  if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end

  local icon = panel:CreateTexture(nil, "ARTWORK")
  icon:SetSize(32, 32)
  icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
  icon:SetTexture("Interface\\AddOns\\Dodo\\Media\\Dodo.tga")

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
  title:SetText("DodoNumbers")

  local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  desc:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -8)
  desc:SetWidth(680)
  desc:SetJustifyH("LEFT")
  desc:SetText("说明：本插件不重画飘字，而是通过 12.0 的 *_v2 CVars 调整暴雪“世界飘字”的大小、暴击放大与飘字行为，因此颜色/字体/3D 跟随位置完全沿用暴雪。")

  local y0 = -90

  local enableCB = CreateCheck(panel, "启用 DodoNumbers（启用后会在每次登录自动应用设置）", 16, y0)
  y0 = y0 - 34

  -- Size
  CreateLabel(panel, "基础字号（px）", "GameFontNormal", 16, y0)
  local baseEB = CreateEditBox(panel, 90, 24, 140, y0 + 6)
  y0 = y0 - 34

  CreateLabel(panel, "暴击倍率（crit = ceil(base * mult)）", "GameFontNormal", 16, y0)
  local critEB = CreateEditBox(panel, 90, 24, 300, y0 + 6)
  y0 = y0 - 34

  local preview = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  preview:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y0)
  preview:SetText("")
  y0 = y0 - 44

  -- Behavior
  local floatDD = CreateDropdown(panel, "飘字轨迹", 16, y0, 140)
  y0 = y0 - 44

  CreateLabel(panel, "方向性飞散强度（0=最干净）", "GameFontNormal", 16, y0)
  local dirEB = CreateEditBox(panel, 90, 24, 240, y0 + 6)
  y0 = y0 - 34

  CreateLabel(panel, "存在时长（建议 0.6~2.5）", "GameFontNormal", 16, y0)
  local durEB = CreateEditBox(panel, 90, 24, 240, y0 + 6)
  y0 = y0 - 34

  CreateLabel(panel, "横向散开（0=不散）", "GameFontNormal", 16, y0)
  local rndEB = CreateEditBox(panel, 90, 24, 240, y0 + 6)
  y0 = y0 - 44

  -- Filters
  local petCB = CreateCheck(panel, "显示宠物/召唤物伤害", 16, y0)
  y0 = y0 - 28
  local periodicCB = CreateCheck(panel, "显示周期伤害（DOT）", 16, y0)
  y0 = y0 - 28
  local missCB = CreateCheck(panel, "显示 MISS / DODGE / PARRY", 16, y0)
  y0 = y0 - 44

  local applyBtn = CreateButton(panel, "应用", 120, 26, 16, y0)
  local restoreBtn = CreateButton(panel, "恢复原始并停用", 180, 26, 150, y0)

  y0 = y0 - 34
  local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y0)
  hint:SetWidth(680)
  hint:SetJustifyH("LEFT")
  hint:SetText("提示：点击“恢复原始并停用”会把本插件触碰过的 CVar 全部恢复到首次启用时的原始值，并把“启用 DodoNumbers”自动关闭。")

  -- Dropdown options
  local FLOAT_MODES = {
    { value = 1, text = "向上" },
    { value = 2, text = "向下" },
    { value = 3, text = "弧线" },
  }

  floatDD:SetupMenu(function(_, rootDescription)
    for _, it in ipairs(FLOAT_MODES) do
      rootDescription:CreateRadio(it.text,
        function() return (tonumber(DN.db.floatMode) or 1) == it.value end,
        function() DN.db.floatMode = it.value end)
    end
  end)
  floatDD:GenerateMenu()

  local function RefreshPreview()
    local db = DN.db
    local basePx = tonumber(db.basePx) or 40
    local mult = tonumber(db.critMult) or 2.0
    local critPx = math.ceil(basePx * mult)

    local scale = (db.computed and db.computed.scale) or (basePx / 40)
    local ramp = (db.computed and db.computed.rampPowCrit) or 0

    preview:SetText(string.format(
      "当前：base=%dpx，crit=%dpx；映射：WorldTextScale_v2≈%.2f，WorldTextRampPowCrit≈%d",
      basePx, critPx, scale, ramp
    ))
  end

  local function RefreshControls()
    local db = DN.db
    enableCB:SetChecked(db.enabled and true or false)
    baseEB:SetText(tostring(db.basePx or 40))
    critEB:SetText(tostring(db.critMult or 2.0))

    floatDD:GenerateMenu()
    dirEB:SetText(tostring(db.directionalScale or 0))
    durEB:SetText(tostring(db.rampDuration or 1.0))
    rndEB:SetText(tostring(db.randomXY or 0))

    petCB:SetChecked(db.showPetDamage and true or false)
    periodicCB:SetChecked(db.showPeriodicDamage and true or false)
    missCB:SetChecked(db.showMissDodgeParry and true or false)

    RefreshPreview()
  end

  local function ReadAndApplyFromUI()
    local db = DN.db
    db.enabled = enableCB:GetChecked() and true or false

    local base = tonumber(baseEB:GetText())
    if base then db.basePx = base end

    local mult = tonumber(critEB:GetText())
    if mult then db.critMult = mult end

    local dir = tonumber(dirEB:GetText())
    if dir then db.directionalScale = dir end

    local dur = tonumber(durEB:GetText())
    if dur then db.rampDuration = dur end

    local rnd = tonumber(rndEB:GetText())
    if rnd then db.randomXY = rnd end

    db.showPetDamage = petCB:GetChecked() and true or false
    db.showPeriodicDamage = periodicCB:GetChecked() and true or false
    db.showMissDodgeParry = missCB:GetChecked() and true or false

    DN:Apply()
    RefreshControls()
  end

  panel:SetScript("OnShow", function() RefreshControls() end)

  enableCB:SetScript("OnClick", ReadAndApplyFromUI)
  petCB:SetScript("OnClick", ReadAndApplyFromUI)
  periodicCB:SetScript("OnClick", ReadAndApplyFromUI)
  missCB:SetScript("OnClick", ReadAndApplyFromUI)

  baseEB:SetScript("OnEnterPressed", function(selfEB) selfEB:ClearFocus(); ReadAndApplyFromUI() end)
  critEB:SetScript("OnEnterPressed", function(selfEB) selfEB:ClearFocus(); ReadAndApplyFromUI() end)
  dirEB:SetScript("OnEnterPressed", function(selfEB) selfEB:ClearFocus(); ReadAndApplyFromUI() end)
  durEB:SetScript("OnEnterPressed", function(selfEB) selfEB:ClearFocus(); ReadAndApplyFromUI() end)
  rndEB:SetScript("OnEnterPressed", function(selfEB) selfEB:ClearFocus(); ReadAndApplyFromUI() end)

  applyBtn:SetScript("OnClick", ReadAndApplyFromUI)
  restoreBtn:SetScript("OnClick", function()
    DN:RestoreOriginal()
    RefreshControls()
  end)

  SLASH_DODONUMBERS1 = "/dodonumbers"
  SLASH_DODONUMBERS2 = "/dn"
  SlashCmdList["DODONUMBERS"] = function()
    OpenOptions(panel, settingsCategory)
  end
end
