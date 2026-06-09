-- DodoCursor - Core
local ADDON_NAME = ...
_G.DodoCursor = _G.DodoCursor or {}
local DC = _G.DodoCursor
DC.ADDON_NAME = ADDON_NAME

local DEFAULTS = {
  enabled = true,
  size = 48,
  alpha = 0.6,
}

local function CopyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      CopyDefaults(dst[k], v)
    else
      if dst[k] == nil then dst[k] = v end
    end
  end
end

local function Clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

function DC:InitDB()
  _G.DodoCursorDB = _G.DodoCursorDB or {}
  CopyDefaults(_G.DodoCursorDB, DEFAULTS)
  self.db = _G.DodoCursorDB
end

-- Cursor overlay frame
local overlay = CreateFrame("Frame", "DodoCursorOverlay", UIParent)
overlay:SetFrameStrata("TOOLTIP")
overlay:SetSize(48, 48)
overlay:Hide()

local tex = overlay:CreateTexture(nil, "ARTWORK")
tex:SetAllPoints()
tex:SetTexture("Interface\\AddOns\\Dodo\\Media\\Dodo.tga")

DC.overlay = overlay
DC.tex = tex

-- Movement tracking state
local lastX, lastY = 0, 0
local moveStart = 0
local isMoving = false
local isEnlarged = false

local function UpdateSize(db, enlarged)
  local s = tonumber(db.size) or 48
  if enlarged then s = s * 2 end
  overlay:SetSize(s, s)
  isEnlarged = enlarged
end

overlay:SetScript("OnUpdate", function(self, elapsed)
  local cx, cy = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  cx = cx / scale
  cy = cy / scale

  -- Center the circle on cursor tip
  self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)

  -- Movement detection
  local db = DC.db
  if not db then return end

  local dx = cx - lastX
  local dy = cy - lastY
  local moved = (dx * dx + dy * dy) > 1 -- threshold: >1px movement

  if moved then
    if not isMoving then
      isMoving = true
      moveStart = GetTime()
    end
    -- Check if moving for > 0.5s
    if not isEnlarged and (GetTime() - moveStart) >= 0.5 then
      UpdateSize(db, true)
    end
  else
    if isMoving then
      isMoving = false
      if isEnlarged then
        UpdateSize(db, false)
      end
    end
  end

  lastX = cx
  lastY = cy
end)

-- Clear anchors before setting new ones each frame
overlay:ClearAllPoints()

function DC:ApplySettings()
  local db = self.db
  if not db then return end

  local s = Clamp(tonumber(db.size) or 48, 16, 128)
  db.size = s

  local a = Clamp(tonumber(db.alpha) or 0.6, 0.1, 1.0)
  db.alpha = a

  overlay:SetSize(s, s)
  overlay:SetAlpha(a)
  isEnlarged = false
end

function DC:ShowOverlay()
  if not self.db or not self.db.enabled then return end
  overlay:ClearAllPoints()
  overlay:Show()
end

function DC:HideOverlay()
  overlay:Hide()
end

-- Events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    DC:InitDB()
    DC:ApplySettings()
    if DC.InitOptions then DC:InitOptions() end

  elseif event == "PLAYER_LOGIN" then
    DC:ApplySettings()
    if InCombatLockdown() then
      DC:ShowOverlay()
    end

  elseif event == "PLAYER_REGEN_DISABLED" then
    DC:ShowOverlay()

  elseif event == "PLAYER_REGEN_ENABLED" then
    DC:HideOverlay()
  end
end)
