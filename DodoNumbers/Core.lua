-- DodoNumbers - Core
-- 12.0+ (Midnight pre-patch) friendly: uses *_v2 CVars when available.
local ADDON_NAME = ...
_G.DodoNumbers = _G.DodoNumbers or {}
local DN = _G.DodoNumbers
DN.ADDON_NAME = ADDON_NAME

local DEFAULTS = {
  enabled = true,

  -- User-facing sizing
  basePx = 40,        -- semantic baseline (40 => scale 1.0)
  critMult = 2.0,     -- critPx = ceil(basePx * critMult)

  -- Toggles
  showPetDamage = true,
  showPeriodicDamage = true,
  showMissDodgeParry = true,

  -- Behavior
  floatMode = 1,          -- 1 up, 2 down, 3 arc
  directionalScale = 0.0, -- 0 = no directional scatter
  rampDuration = 1.0,     -- lifetime-ish (higher => lasts longer)
  randomXY = 0.0,         -- spawn horizontal scatter

  -- Internal
  original = nil,           -- captured CVars
  originalCaptured = false, -- flag
  computed = { scale = 1.0, critPx = 80, rampPowCrit = 16 },
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

local function CVarExists(name)
  if C_CVar and C_CVar.GetCVarInfo then
    return C_CVar.GetCVarInfo(name) ~= nil
  end
  local ok, v = pcall(GetCVar, name)
  return ok and v ~= nil and v ~= ""
end

local function SafeGetCVar(name)
  local ok, v = pcall(GetCVar, name)
  if ok then return v end
  return nil
end

local function SafeSetCVar(name, value)
  if not CVarExists(name) then return false end
  local ok = pcall(SetCVar, name, tostring(value))
  return ok
end

local function Clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

local function BoolToInt(b) return b and 1 or 0 end

-- Always set both v2 + legacy where plausible; client will ignore non-existent.
local CVAR_KEYS = {
  -- Scale
  "WorldTextScale_v2",
  "WorldTextScale",

  -- Crit curve
  "WorldTextRampPowCrit",

  -- Lifetime / behavior
  "WorldTextRampDuration_v2",
  "WorldTextRampDuration",
  "WorldTextRandomXY_v2",
  "WorldTextRandomXY",

  "floatingCombatTextFloatMode_v2",
  "floatingCombatTextFloatMode",
  "floatingCombatTextCombatDamageDirectionalScale_v2",
  "floatingCombatTextCombatDamageDirectionalScale",

  -- Toggles
  "floatingCombatTextPetMeleeDamage_v2",
  "floatingCombatTextPetMeleeDamage",
  "floatingCombatTextPetSpellDamage_v2",
  "floatingCombatTextPetSpellDamage",

  "floatingCombatTextCombatLogPeriodicSpells_v2",
  "floatingCombatTextCombatLogPeriodicSpells",

  "floatingCombatTextDodgeParryMiss_v2",
  "floatingCombatTextDodgeParryMiss",
}

function DN:InitDB()
  _G.DodoNumbersDB = _G.DodoNumbersDB or {}
  CopyDefaults(_G.DodoNumbersDB, DEFAULTS)
  self.db = _G.DodoNumbersDB
end

function DN:CaptureOriginal()
  local db = self.db
  db.original = db.original or {}

  -- IMPORTANT: allow upgrades to capture newly-added CVars
  for _, key in ipairs(CVAR_KEYS) do
    if db.original[key] == nil and CVarExists(key) then
      db.original[key] = SafeGetCVar(key)
    end
  end

  db.originalCaptured = true
end

function DN:RestoreOriginal()
  local db = self.db
  if type(db.original) ~= "table" then return end

  -- Stop auto-apply after restore
  db.enabled = false

  for key, value in pairs(db.original) do
    if value ~= nil then
      SafeSetCVar(key, value)
    end
  end
end

local function ComputeScale(basePx)
  return Clamp(basePx / DEFAULTS.basePx, 0.1, 5.0)
end

local function ComputeRampPowCrit(basePx, critMult)
  local critPx = math.ceil(basePx * critMult)
  local ratio = critPx / math.max(1, basePx)

  -- Approximation: scale a typical "8" baseline by desired ratio.
  local ramp = math.floor((8.0 * ratio) + 0.5)
  ramp = Clamp(ramp, 1, 40)

  return critPx, ramp
end

local function SetBoth(v2, legacy, value)
  SafeSetCVar(v2, value)
  SafeSetCVar(legacy, value)
end

function DN:Apply()
  local db = self.db
  if not db.enabled then return end

  self:CaptureOriginal()

  -- Sizing
  local basePx = tonumber(db.basePx) or DEFAULTS.basePx
  basePx = math.floor(basePx + 0.5)
  basePx = Clamp(basePx, 1, 200)
  db.basePx = basePx

  local critMult = tonumber(db.critMult) or DEFAULTS.critMult
  critMult = Clamp(critMult, 1.0, 10.0)
  db.critMult = critMult

  local scale = ComputeScale(basePx)
  local critPx, rampPowCrit = ComputeRampPowCrit(basePx, critMult)

  db.computed = db.computed or {}
  db.computed.scale = scale
  db.computed.critPx = critPx
  db.computed.rampPowCrit = rampPowCrit

  SetBoth("WorldTextScale_v2", "WorldTextScale", scale)
  SafeSetCVar("WorldTextRampPowCrit", rampPowCrit)

  -- Behavior
  local floatMode = tonumber(db.floatMode) or DEFAULTS.floatMode
  floatMode = math.floor(floatMode + 0.5)
  floatMode = Clamp(floatMode, 1, 3)
  db.floatMode = floatMode
  SetBoth("floatingCombatTextFloatMode_v2", "floatingCombatTextFloatMode", floatMode)

  local dirScale = tonumber(db.directionalScale) or DEFAULTS.directionalScale
  dirScale = Clamp(dirScale, 0.0, 2.0)
  db.directionalScale = dirScale
  SetBoth("floatingCombatTextCombatDamageDirectionalScale_v2", "floatingCombatTextCombatDamageDirectionalScale", dirScale)

  local dur = tonumber(db.rampDuration) or DEFAULTS.rampDuration
  dur = Clamp(dur, 0.2, 5.0)
  db.rampDuration = dur
  SetBoth("WorldTextRampDuration_v2", "WorldTextRampDuration", dur)

  local rnd = tonumber(db.randomXY) or DEFAULTS.randomXY
  rnd = Clamp(rnd, 0.0, 80.0)
  db.randomXY = rnd
  SetBoth("WorldTextRandomXY_v2", "WorldTextRandomXY", rnd)

  -- Toggles
  local pet = BoolToInt(db.showPetDamage)
  SetBoth("floatingCombatTextPetMeleeDamage_v2", "floatingCombatTextPetMeleeDamage", pet)
  SetBoth("floatingCombatTextPetSpellDamage_v2", "floatingCombatTextPetSpellDamage", pet)

  local periodic = BoolToInt(db.showPeriodicDamage)
  SetBoth("floatingCombatTextCombatLogPeriodicSpells_v2", "floatingCombatTextCombatLogPeriodicSpells", periodic)

  local miss = BoolToInt(db.showMissDodgeParry)
  SetBoth("floatingCombatTextDodgeParryMiss_v2", "floatingCombatTextDodgeParryMiss", miss)
end

function DN:SetEnabled(on)
  self.db.enabled = not not on
  if self.db.enabled then
    self:Apply()
  end
end

-- Optional debug helper
SLASH_DODONUMBERSDBG1 = "/dncv"
SlashCmdList["DODONUMBERSDBG"] = function()
  if not DN.db then print("DodoNumbers: DB not ready") return end
  print("DodoNumbers CVars snapshot:")
  local keys = {
    "WorldTextScale_v2","WorldTextScale","WorldTextRampPowCrit",
    "WorldTextRampDuration_v2","WorldTextRampDuration",
    "WorldTextRandomXY_v2","WorldTextRandomXY",
    "floatingCombatTextFloatMode_v2","floatingCombatTextFloatMode",
    "floatingCombatTextCombatDamageDirectionalScale_v2","floatingCombatTextCombatDamageDirectionalScale",
    "floatingCombatTextCombatLogPeriodicSpells_v2","floatingCombatTextCombatLogPeriodicSpells",
    "floatingCombatTextPetMeleeDamage_v2","floatingCombatTextPetMeleeDamage",
    "floatingCombatTextPetSpellDamage_v2","floatingCombatTextPetSpellDamage",
    "floatingCombatTextDodgeParryMiss_v2","floatingCombatTextDodgeParryMiss",
  }
  for _, k in ipairs(keys) do
    if CVarExists(k) then
      print("  ", k, "=", SafeGetCVar(k))
    end
  end
end

-- Events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    DN:InitDB()
    DN:CaptureOriginal()
    if DN.InitOptions then DN:InitOptions() end
  elseif event == "PLAYER_LOGIN" then
    DN:Apply()
  end
end)
