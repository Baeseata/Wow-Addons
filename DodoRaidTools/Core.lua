-- DodoRaidTools - Core
-- v0.5.0  仅史诗奥蕾莉亚 (Crown of the Cosmos Mythic) 自动启用
local ADDON_NAME = ...
_G.DodoRaidTools = _G.DodoRaidTools or {}
local DRT = _G.DodoRaidTools
DRT.ADDON_NAME = ADDON_NAME

local PREFIX = "|cFFFFD200[DodoRaidTools]|r "

local state = {
  active = false,
  phase = 1,
  phaseStart = 0,
  debug = false,
}

local function GetUIFont()
  return STANDARD_TEXT_FONT or (GameFontNormal and GameFontNormal:GetFont()) or "Fonts\\ARIALN.TTF"
end

local function FormatElapsed(elapsed)
  if elapsed < 0 then elapsed = 0 end
  if elapsed < 60 then
    return string.format("%ds", math.floor(elapsed))
  end
  local minutes = math.floor(elapsed / 60)
  local seconds = math.floor(elapsed - minutes * 60)
  return string.format("%dm %ds", minutes, seconds)
end

-- 内部阶段编号 → 显示标签
-- 1 = 阶段 1, 2 = 阶段 1.5 (中场1), 3 = 阶段 2, 4 = 阶段 2.5 (中场2), 5 = 阶段 3
local PHASE_LABELS = {
  [1] = "1",
  [2] = "1.5",
  [3] = "2",
  [4] = "2.5",
  [5] = "3",
}

local function PhaseLabel(p)
  return PHASE_LABELS[p] or tostring(p)
end

local timerFrame = CreateFrame("Frame", "DodoRaidToolsTimerFrame", UIParent)
timerFrame:SetSize(420, 140)
timerFrame:SetPoint("TOP", UIParent, "TOP", 0, -120)
timerFrame:SetFrameStrata("HIGH")
timerFrame:Hide()

local font = GetUIFont()

local phaseText = timerFrame:CreateFontString(nil, "OVERLAY")
phaseText:SetFont(font, 36, "OUTLINE")
phaseText:SetPoint("TOP", timerFrame, "TOP", 0, 0)
phaseText:SetTextColor(1.0, 0.82, 0.0)
phaseText:SetText("阶段 1")

local timerText = timerFrame:CreateFontString(nil, "OVERLAY")
timerText:SetFont(font, 72, "OUTLINE")
timerText:SetPoint("TOP", phaseText, "BOTTOM", 0, -6)
timerText:SetTextColor(1.0, 1.0, 1.0)
timerText:SetText("0s")

local nextAbilityText = timerFrame:CreateFontString(nil, "OVERLAY")
nextAbilityText:SetFont(font, 40, "OUTLINE")
nextAbilityText:SetPoint("TOP", timerText, "BOTTOM", 0, -4)
nextAbilityText:SetTextColor(1.0, 0.4, 0.3)
nextAbilityText:SetText("")

-- Crown 自动追踪状态(declared early so OnUpdate / GetUpcomingCrownAbility 能引用)
local CROWN_ENCOUNTER_ID = 3181
local DIFFICULTY_MYTHIC = 16

local crown = {
  active = false,
  isMythic = false,
  silverstrikeBarrageCount = 0,
  prevEventTime = 0,
  stage2Scheduled = false,
  stage3Scheduled = false,
}

-- Crown of the Cosmos: 阶段相对秒数 (data: NorthernSkyRaidTools/BossTimelines/CrownOfTheCosmos.lua)
local CROWN_TIMELINE = {
  ["银锋箭"] = {
    heroic = { [1] = {24, 45, 68, 91, 112} },
    mythic = { [1] = {20, 38, 57, 76, 93, 120} },
  },
  ["方尖碑"] = {
    heroic = {
      [1] = {7, 35, 67, 99, 127},
      [5] = {10, 17, 37, 54, 70, 77, 97, 114, 130, 137, 157, 174, 190, 199},
    },
    mythic = {
      [1] = {5, 28, 55, 81},
      [3] = {14, 39, 66, 91, 118},
      [5] = {10, 20, 55, 71, 80, 115, 131, 140, 175, 191, 200},
    },
  },
}

local function FindNextRemain(times, elapsed)
  if not times then return nil end
  for _, t in ipairs(times) do
    if t > elapsed then return t - elapsed end
  end
  return nil
end

local function GetUpcomingCrownAbility()
  if not crown or not crown.active then return nil, nil end
  local phase = state.phase
  local diff = crown.isMythic and "mythic" or "heroic"
  local elapsed = GetTime() - state.phaseStart

  local bestRemain, bestName = nil, nil
  for name, byDiff in pairs(CROWN_TIMELINE) do
    local times = byDiff[diff] and byDiff[diff][phase]
    local r = FindNextRemain(times, elapsed)
    if r and (not bestRemain or r < bestRemain) then
      bestRemain = r
      bestName = name
    end
  end
  return bestName, bestRemain
end

timerFrame:SetScript("OnUpdate", function(self)
  if not state.active then return end
  local elapsed = GetTime() - state.phaseStart
  phaseText:SetText("阶段 " .. PhaseLabel(state.phase))
  timerText:SetText(FormatElapsed(elapsed))

  local name, remain = GetUpcomingCrownAbility()
  if name and remain and remain > 0 and remain <= 5 then
    nextAbilityText:SetText(string.format("%s %ds", name, math.ceil(remain)))
  else
    nextAbilityText:SetText("")
  end
end)

function DRT:Start()
  state.active = true
  state.phase = 1
  state.phaseStart = GetTime()
  timerFrame:Show()
end

function DRT:NextPhase()
  if not state.active then
    state.active = true
    state.phase = 1
  else
    state.phase = state.phase + 1
  end
  state.phaseStart = GetTime()
  timerFrame:Show()
end

function DRT:SetPhase(p)
  state.active = true
  state.phase = p
  state.phaseStart = GetTime()
  timerFrame:Show()
end

function DRT:Reset()
  state.active = false
  state.phase = 1
  state.phaseStart = 0
  phaseText:SetText("阶段 1")
  timerText:SetText("0s")
  nextAbilityText:SetText("")
  timerFrame:Hide()
end

function DRT:Show()
  timerFrame:Show()
end

function DRT:Hide()
  timerFrame:Hide()
end

--------------------------------------------------------------------------------
-- 自动阶段检测: Crown of the Cosmos (虚影尖塔尾王 / 宇宙之冕)
-- encounterID 3181, 规则参考 BigWigs/TheVoidspire/Crown.lua
-- (CROWN_ENCOUNTER_ID / DIFFICULTY_MYTHIC / crown 已在文件上方提前声明)
--------------------------------------------------------------------------------

local function StartCrownTracking(difficultyID)
  crown.active = true
  crown.isMythic = (difficultyID == DIFFICULTY_MYTHIC)
  crown.silverstrikeBarrageCount = 0
  crown.prevEventTime = GetTime()
  crown.stage2Scheduled = false
  crown.stage3Scheduled = false
end

local function StopCrownTracking()
  crown.active = false
end

-- duration 四舍五入到 N 位小数
local function RoundTo(value, decimals)
  local m = 10 ^ decimals
  return math.floor(value * m + 0.5) / m
end

local function HandleCrownTimelineEvent(eventInfo)
  if not crown.active then return end
  if eventInfo.source ~= 0 then return end -- 0 = Encounter source only

  local duration = eventInfo.duration or 0
  local d1 = RoundTo(duration, 1)
  local d0 = RoundTo(duration, 0)

  local now = GetTime()
  local gap = now - crown.prevEventTime
  crown.prevEventTime = now

  local stage = state.phase

  if stage == 1 then
    -- 阶段 1 → 1.5 (中场1): duration ≈ 25 立即进入中场
    -- 阶段 1.5 → 2: 25 秒后中场结束
    if d1 == 25 and not crown.stage2Scheduled then
      crown.stage2Scheduled = true
      DRT:SetPhase(2)
      print(PREFIX .. "自动切到 阶段 1.5 (中场)")
      C_Timer.After(duration, function()
        if crown.active and state.phase == 2 then
          DRT:SetPhase(3)
          print(PREFIX .. "自动切到 阶段 2")
        end
      end)
    end

  elseif stage == 3 then
    -- 史诗: 阶段 2 → 3, 距上次 timeline 事件 > 15 秒直接进入阶段 3 (无明显中场信号)
    if crown.isMythic and gap > 15 then
      DRT:SetPhase(5)
      print(PREFIX .. "自动切到 阶段 3 (史诗: 检测到 timeline 间隙)")
      return
    end

    -- 非史诗: 跟踪 Silverstrike Barrage 次数
    if d1 == 1.5 then
      crown.silverstrikeBarrageCount = crown.silverstrikeBarrageCount + 1
    end

    -- 非史诗 阶段 2 → 2.5 (中场2): silverstrikeBarrageCount > 1 AND duration ≈ 20
    -- 阶段 2.5 → 3: 20 秒后中场结束
    if (not crown.isMythic) and crown.silverstrikeBarrageCount > 1 and d0 == 20 and not crown.stage3Scheduled then
      crown.stage3Scheduled = true
      DRT:SetPhase(4)
      print(PREFIX .. "自动切到 阶段 2.5 (中场)")
      C_Timer.After(duration, function()
        if crown.active and state.phase == 4 then
          DRT:SetPhase(5)
          print(PREFIX .. "自动切到 阶段 3")
        end
      end)
    end
  end
end

--------------------------------------------------------------------------------
-- 命令
--------------------------------------------------------------------------------

local function PrintHelp()
  print(PREFIX .. "命令:")
  print("  /drt start         - 启动计时器(阶段 1)")
  print("  /drt next          - 进入下一阶段并重新计时")
  print("  /drt phase <n>     - 跳到指定阶段")
  print("  /drt reset         - 停止并隐藏")
  print("  /drt show / hide   - 仅显示/隐藏窗口")
  print("  /drt test          - debug 自测(启动 + 显示)")
  print("  /drt debug         - 切换 timeline 事件日志(默认 关)")
end

SLASH_DODORAIDTOOLS1 = "/drt"
SLASH_DODORAIDTOOLS2 = "/dodoraidtools"
SlashCmdList["DODORAIDTOOLS"] = function(msg)
  msg = (msg or ""):lower()
  msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = cmd or ""
  rest = rest or ""

  if cmd == "start" then
    DRT:Start()
    print(PREFIX .. "计时器已启动 (阶段 1)")
  elseif cmd == "next" then
    DRT:NextPhase()
    print(PREFIX .. "进入阶段 " .. PhaseLabel(state.phase))
  elseif cmd == "phase" then
    -- 接受用户标签 (1, 1.5, 2, 2.5, 3) 或内部编号 1-5
    local LABEL_TO_PHASE = { ["1"] = 1, ["1.5"] = 2, ["2"] = 3, ["2.5"] = 4, ["3"] = 5 }
    local p = LABEL_TO_PHASE[rest] or tonumber(rest)
    if p and p >= 1 then
      p = math.floor(p)
      DRT:SetPhase(p)
      print(PREFIX .. "已切换到阶段 " .. PhaseLabel(p))
    else
      print(PREFIX .. "用法: /drt phase <标签>  例: /drt phase 1.5")
    end
  elseif cmd == "reset" or cmd == "stop" then
    DRT:Reset()
    StopCrownTracking()
    print(PREFIX .. "已重置")
  elseif cmd == "show" then
    DRT:Show()
  elseif cmd == "hide" then
    DRT:Hide()
  elseif cmd == "test" then
    DRT:Start()
    print(PREFIX .. "debug 测试: 已启动. 用 /drt next 切换阶段, /drt reset 停止.")
  elseif cmd == "debug" then
    state.debug = not state.debug
    print(PREFIX .. "timeline 日志: " .. (state.debug and "开" or "关"))
  else
    PrintHelp()
  end
end

--------------------------------------------------------------------------------
-- 事件
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ENCOUNTER_START")
events:RegisterEvent("ENCOUNTER_END")
events:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_ADDED")

local inEncounter = false

events:SetScript("OnEvent", function(self, event, ...)
  if event == "PLAYER_LOGIN" then
    print(PREFIX .. "v0.5.0 已加载. 仅史诗奥蕾莉亚自动启动. 输入 /drt 查看命令.")

  elseif event == "ENCOUNTER_START" then
    local encounterID, encounterName, difficultyID, groupSize = ...
    -- 仅史诗 Crown of the Cosmos (奥蕾莉亚委员会) 启用
    if encounterID ~= CROWN_ENCOUNTER_ID or difficultyID ~= DIFFICULTY_MYTHIC then
      return
    end
    inEncounter = true
    DRT:Start()
    StartCrownTracking(difficultyID)
    print(PREFIX .. "Encounter 开始: " .. tostring(encounterName or encounterID) .. " (史诗)")
    print(PREFIX .. "已启用宇宙之冕自动阶段检测")

  elseif event == "ENCOUNTER_END" then
    -- 只处理我们正在追踪的 encounter
    if not crown.active then return end
    local encounterID, encounterName, _, _, success = ...
    inEncounter = false
    StopCrownTracking()
    DRT:Reset()
    print(PREFIX .. "Encounter 结束: " .. tostring(encounterName or encounterID) ..
      (success == 1 and " (击杀)" or " (失败)"))

  -- PLAYER_REGEN_DISABLED / PLAYER_REGEN_ENABLED 不再自动启停, 仅 ENCOUNTER_START/END 触发

  elseif event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
    local eventInfo = ...
    if not eventInfo then return end

    if state.debug then
      print(string.format("%s[TL] id=%s src=%s dur=%.2f spell=%s(%s)",
        PREFIX,
        tostring(eventInfo.id),
        tostring(eventInfo.source),
        tonumber(eventInfo.duration) or 0,
        tostring(eventInfo.spellName or ""),
        tostring(eventInfo.spellID or "")))
    end

    HandleCrownTimelineEvent(eventInfo)
  end
end)
