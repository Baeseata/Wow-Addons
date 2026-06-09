-- DodoCursor - Options
local DC = _G.DodoCursor
if not DC then return end

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

local function OpenOptions(panel, settingsCategory)
  if Settings and Settings.OpenToCategory then
    if settingsCategory and settingsCategory.GetID then
      Settings.OpenToCategory(settingsCategory:GetID())
      return
    end
    Settings.OpenToCategory("DodoCursor")
    return
  end
  if InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
  end
end

function DC:InitOptions()
  if self.optionsInited then return end
  self.optionsInited = true

  local panel = CreateFrame("Frame", "DodoCursorOptionsPanel", UIParent)
  panel.name = "DodoCursor"
  self.optionsPanel = panel

  local settingsCategory = nil
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, "DodoCursor")
    Settings.RegisterAddOnCategory(settingsCategory)
  end
  self.settingsCategory = settingsCategory

  if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end

  -- Header
  local icon = panel:CreateTexture(nil, "ARTWORK")
  icon:SetSize(32, 32)
  icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
  icon:SetTexture("Interface\\AddOns\\Dodo\\Media\\Dodo.tga")

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
  title:SetText("DodoCursor")

  local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  desc:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -8)
  desc:SetWidth(680)
  desc:SetJustifyH("LEFT")
  desc:SetText("说明：在鼠标光标位置叠加一个粉色圆圈装饰，仅战斗中显示。光标持续移动超过0.5秒后圆圈会放大一倍。")

  local y0 = -90

  -- Enable checkbox
  local enableCB = CreateCheck(panel, "启用 DodoCursor（仅战斗中显示光标装饰）", 16, y0)
  y0 = y0 - 40

  -- Size
  CreateLabel(panel, "圆圈大小（px，16~128）", "GameFontNormal", 16, y0)
  local sizeEB = CreateEditBox(panel, 90, 24, 200, y0 + 6)
  y0 = y0 - 40

  -- Alpha
  CreateLabel(panel, "透明度（0.1~1.0）", "GameFontNormal", 16, y0)
  local alphaEB = CreateEditBox(panel, 90, 24, 200, y0 + 6)
  y0 = y0 - 50

  -- Apply button
  local applyBtn = CreateButton(panel, "应用", 120, 26, 16, y0)

  -- Refresh controls from DB
  local function RefreshControls()
    local db = DC.db
    enableCB:SetChecked(db.enabled and true or false)
    sizeEB:SetText(tostring(db.size or 48))
    alphaEB:SetText(tostring(db.alpha or 0.6))
  end

  -- Read UI values and apply
  local function ReadAndApply()
    local db = DC.db
    db.enabled = enableCB:GetChecked() and true or false

    local s = tonumber(sizeEB:GetText())
    if s then db.size = s end

    local a = tonumber(alphaEB:GetText())
    if a then db.alpha = a end

    DC:ApplySettings()

    -- Show/hide based on enabled + combat state
    if db.enabled and InCombatLockdown() then
      DC:ShowOverlay()
    else
      DC:HideOverlay()
    end

    RefreshControls()
  end

  panel:SetScript("OnShow", function() RefreshControls() end)

  enableCB:SetScript("OnClick", ReadAndApply)
  sizeEB:SetScript("OnEnterPressed", function(self) self:ClearFocus(); ReadAndApply() end)
  alphaEB:SetScript("OnEnterPressed", function(self) self:ClearFocus(); ReadAndApply() end)
  applyBtn:SetScript("OnClick", ReadAndApply)

  -- Slash commands
  SLASH_DODOCURSOR1 = "/dodocursor"
  SLASH_DODOCURSOR2 = "/dc"
  SlashCmdList["DODOCURSOR"] = function()
    OpenOptions(panel, settingsCategory)
  end
end
