-- DodoTarget.lua (Retail 12.0+)
-- Show target player's: ilvl (rounded) + race + class + spec + hero talents (localized/Chinese on CN client)
-- IMPORTANT: Do NOT show partial frame (no "0 ilvl" flicker). Show only when ilvl+spec are ready.

local ADDON_NAME = ...

DodoTargetDB = DodoTargetDB or {
  enabled = true,
  fontSize = 20,
  offsetX = 0,
  offsetY = -16,
  twoLines = false,
}

local function Round(x)
  if type(x) ~= "number" then return nil end
  return math.floor(x + 0.5)
end

local function IsPlayerTarget()
  return UnitExists("target") and UnitIsPlayer("target")
end

-- =========================
-- Display Frame
-- =========================
local UI = CreateFrame("Frame", "DodoTargetDisplay", UIParent)
UI:SetFrameStrata("HIGH")
UI:SetFrameLevel(9999)
UI:SetSize(620, 44)
UI:Hide()

UI.t1 = UI:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
UI.t1:SetPoint("TOP", UI, "TOP", 0, 0)
UI.t1:SetJustifyH("CENTER")

UI.t2 = UI:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
UI.t2:SetPoint("TOP", UI.t1, "BOTTOM", 0, -2)
UI.t2:SetJustifyH("CENTER")

local function ApplyFont()
  local fs = tonumber(DodoTargetDB.fontSize) or 16
  UI.t1:SetFont(STANDARD_TEXT_FONT, fs, "OUTLINE")
  UI.t2:SetFont(STANDARD_TEXT_FONT, math.max(11, fs - 3), "OUTLINE")
end

local function Anchor()
  UI:ClearAllPoints()
  if TargetFrame then
    UI:SetPoint("BOTTOM", TargetFrame, "TOP", DodoTargetDB.offsetX or 0, DodoTargetDB.offsetY or 16)
  else
    UI:SetPoint("TOP", UIParent, "TOP", 0, -140)
  end
end

local function HideUI()
  UI.t1:SetText("")
  UI.t2:SetText("")
  UI:Hide()
end

-- =========================
-- Spec API helpers (prefer C_SpecializationInfo, fall back to deprecated globals — still present in 12.0.5)
-- =========================
local function GetInspectSpec(unit)
  if C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization then
    return C_SpecializationInfo.GetInspectSpecialization(unit)
  end
  if GetInspectSpecialization then return GetInspectSpecialization(unit) end
  return nil
end

local function GetSpecInfoByID(specID)
  if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoByID then
    return C_SpecializationInfo.GetSpecializationInfoByID(specID)
  end
  if GetSpecializationInfoByID then return GetSpecializationInfoByID(specID) end
  return nil
end

-- =========================
-- Data getters
-- =========================
local function GetLocalizedRaceClass()
  local race = select(1, UnitRace("target")) or "未知种族"
  local class = select(1, UnitClass("target")) or "未知职业"
  return race, class
end

local function GetInspectSpecName()
  local specID = GetInspectSpec("target")
  if not specID or specID <= 0 then return nil end
  local _, name = GetSpecInfoByID(specID) -- localized
  return name
end

local function GetInspectIlvl()
  if not C_PaperDollInfo or not C_PaperDollInfo.GetInspectItemLevel then return nil end
  local v = C_PaperDollInfo.GetInspectItemLevel("target")
  v = Round(v)
  if not v or v <= 0 then return nil end -- key: treat 0 as "not ready"
  return v
end

-- =========================
-- Hero Talent (Inspect Traits)
-- =========================
local function GetInspectHeroTalentName()
  if not C_Traits or not C_ClassTalents then return nil end
  if not C_Traits.HasValidInspectData or not C_Traits.HasValidInspectData() then
    return nil
  end

  local specID = GetInspectSpec("target")
  if not specID or specID <= 0 then return nil end

  local treeID = C_ClassTalents.GetTraitTreeForSpec and C_ClassTalents.GetTraitTreeForSpec(specID)
  if not treeID then return nil end

  local nodeIDs = C_Traits.GetTreeNodes and C_Traits.GetTreeNodes(treeID)
  if type(nodeIDs) ~= "table" then return nil end

  local configID = -1 -- inspect config

  for _, nodeID in ipairs(nodeIDs) do
    local nodeInfo = C_Traits.GetNodeInfo and C_Traits.GetNodeInfo(configID, nodeID)
    if nodeInfo and type(nodeInfo.entryIDs) == "table" then
      local activeEntryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID
      for _, entryID in ipairs(nodeInfo.entryIDs) do
        local entryInfo = C_Traits.GetEntryInfo and C_Traits.GetEntryInfo(configID, entryID)
        if entryInfo and entryInfo.subTreeID and activeEntryID == entryID then
          local subTreeInfo = C_Traits.GetSubTreeInfo and C_Traits.GetSubTreeInfo(configID, entryInfo.subTreeID)
          if subTreeInfo and subTreeInfo.name then
            return subTreeInfo.name
          end
        end
      end
    end
  end

  return nil
end

-- =========================
-- Compose & Show (NO partial)
-- =========================
local function ComposeAndShow()
  if not DodoTargetDB.enabled then
    HideUI()
    return
  end
  if not IsPlayerTarget() then
    HideUI()
    return
  end

  Anchor()
  ApplyFont()

  local ilvl = GetInspectIlvl()
  local spec = GetInspectSpecName()

  -- Key gate: do NOT show until ilvl + spec are ready
  if not ilvl or not spec then
    HideUI()
    return
  end

  local race, class = GetLocalizedRaceClass()
  local hero = GetInspectHeroTalentName() -- optional; don't block display

  local parts = { tostring(ilvl), race, class, spec }
  if hero then table.insert(parts, hero) end

  if DodoTargetDB.twoLines then
    UI.t1:SetText(table.concat({ tostring(ilvl), race, class }, "  "))
    local p2 = { spec }
    if hero then table.insert(p2, hero) end
    UI.t2:SetText(table.concat(p2, "  "))
  else
    UI.t1:SetText(table.concat(parts, "  "))
    UI.t2:SetText("")
  end

  UI:Show()
end

-- =========================
-- Inspect request flow (avoid flicker)
-- =========================
local inspectPendingGUID
local lastInspectRequestAt = 0

local function RequestInspect()
  if not IsPlayerTarget() then return end
  if not CanInspect or not CanInspect("target") then return end

  local now = GetTime()
  if now - lastInspectRequestAt < 0.6 then return end
  lastInspectRequestAt = now

  inspectPendingGUID = UnitGUID("target")
  NotifyInspect("target")
end

-- =========================
-- Events
-- =========================
local EVT = CreateFrame("Frame")
EVT:RegisterEvent("PLAYER_ENTERING_WORLD")
EVT:RegisterEvent("PLAYER_TARGET_CHANGED")
EVT:RegisterEvent("INSPECT_READY")

EVT:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_ENTERING_WORLD" then
    ComposeAndShow()
    return
  end

  if event == "PLAYER_TARGET_CHANGED" then
    inspectPendingGUID = nil

    if IsPlayerTarget() then
      -- Key: hide first, then request inspect; show only when ready
      HideUI()
      RequestInspect()
      -- Sometimes inspect/traits land a bit later; try a couple delayed rebuilds (still gated, so no partial)
      C_Timer.After(0.25, ComposeAndShow)
      C_Timer.After(0.65, ComposeAndShow)
    else
      HideUI()
    end
    return
  end

  if event == "INSPECT_READY" then
    local guid = ...
    if not IsPlayerTarget() then return end
    if inspectPendingGUID and guid and guid ~= inspectPendingGUID then return end

    -- Data ready -> now show (gated)
    ComposeAndShow()
    -- Traits may lag by a frame; rebuild once more (still gated)
    C_Timer.After(0, ComposeAndShow)
    return
  end
end)

-- =========================
-- Slash commands
-- =========================
SLASH_DODOTARGET1 = "/dodot"
SLASH_DODOTARGET2 = "/dodotarget"

SlashCmdList["DODOTARGET"] = function(msg)
  msg = (msg or ""):lower()

  if msg == "on" then
    DodoTargetDB.enabled = true
    ComposeAndShow()
    print("|cffffd200DodoTarget|r 已启用")
    return
  end

  if msg == "off" then
    DodoTargetDB.enabled = false
    HideUI()
    print("|cffffd200DodoTarget|r 已关闭")
    return
  end

  if msg:match("^size") then
    local n = tonumber(msg:match("size%s+(%d+)"))
    if n and n >= 10 and n <= 64 then
      DodoTargetDB.fontSize = n
      ApplyFont()
      ComposeAndShow()
      print("|cffffd200DodoTarget|r 字体大小 = " .. n)
    else
      print("|cffffd200DodoTarget|r 用法：/dodoi size 16（10~64）")
    end
    return
  end

  if msg == "twolines on" then
    DodoTargetDB.twoLines = true
    ComposeAndShow()
    print("|cffffd200DodoTarget|r 两行显示：开")
    return
  end

  if msg == "twolines off" then
    DodoTargetDB.twoLines = false
    ComposeAndShow()
    print("|cffffd200DodoTarget|r 两行显示：关")
    return
  end

  if msg:match("^offset") then
    local x, y = msg:match("offset%s+([%-%.%d]+)%s+([%-%.%d]+)")
    x, y = tonumber(x), tonumber(y)
    if x and y then
      DodoTargetDB.offsetX = x
      DodoTargetDB.offsetY = y
      Anchor()
      ComposeAndShow()
      print("|cffffd200DodoTarget|r 偏移 = " .. x .. ", " .. y)
    else
      print("|cffffd200DodoTarget|r 用法：/dodoi offset 0 16")
    end
    return
  end

  print("|cffffd200DodoTarget|r 指令：")
  print("  /dodoi on|off")
  print("  /dodoi size 16")
  print("  /dodoi twolines on|off")
  print("  /dodoi offset 0 16")
end