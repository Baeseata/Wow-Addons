-- DodoUnholy / Rotation.lua
-- V0 单体出招助手 (Rider of the Apocalypse 流派: Festering Scythe + Soul Reaper + Commander of the Dead, 无 Blightfall, 无 San'layn)
-- 设计要点:
--   * 只读 + 只显示,绝不发送任何按键 (合规)。
--   * 12.0 Secret Values: 战斗中部分 API (UnitHealth 某些单位 / 战斗属性) 返回 secret,
--     对其比较/运算会抛错。所有读数都过 issecretvalue 守卫,整段求值再包一层 pcall。
--   * 新技能 (Putrefy / Dread Plague / Festering Scythe) 的 spellID 暂为 nil → 对应优先级行自动跳过,
--     待 /duh scan 拿到精确 ID 后填入即可激活。

local ADDON = ...
local DodoUnholy = _G[ADDON]
if not DodoUnholy then return end

-- ----------------------------------------------------------------------------
-- 技能 / 光环 ID 表  (改这里就能调整,无需动逻辑)
-- 标 VERIFY 的是 12.0 新内容,需用 /duh scan 在你客户端确认后填入。
-- ----------------------------------------------------------------------------
local S = {
    -- 施放技能 (长期稳定 ID)
    DeathCoil          = 47541,
    FesteringStrike    = 85948,
    ScourgeStrike      = 55090,
    Outbreak           = 77575,
    DarkTransformation = 1233448,  -- 12.0: 旧 63560 已被新版覆盖 (scan 确认)
    ArmyOfTheDead      = 42650,
    SoulReaper         = 343294,
    RaiseDead          = 46584,
    -- 12.0 新技能 (scan 确认)
    Putrefy            = 1247378,  -- 腐化

    -- 自身 Buff
    Aura_SuddenDoom        = 81340,
    Aura_DarkTransformation= 1233448,
    Aura_CommanderOfDead   = 390260,
    Aura_FesteringScythe   = nil,   -- VERIFY

    -- 目标 Debuff
    Debuff_FesteringWound  = 194310,
    Debuff_VirulentPlague  = 191587,
    Debuff_DreadPlague     = nil,   -- VERIFY (若你的天赋用凋零疫病替代了剧毒疫病)
}
DodoUnholy.Spells = S  -- 暴露给 /duh debug

local GCD_SPELL = 61304  -- "Global Cooldown" 用于查 GCD 剩余

-- ----------------------------------------------------------------------------
-- 工具
-- ----------------------------------------------------------------------------
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- 是否 secret 值 (12.0 战斗保护)。issecretvalue 是 12.0 全局;不存在时退化为 false。
local function isSecret(v)
    if issecretvalue then return issecretvalue(v) end
    return false
end

local function Known(spellID)
    if not spellID then return false end
    if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
    if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(spellID) then return true end
    return false
end

local function GCDRemain()
    local cd = C_Spell.GetSpellCooldown(GCD_SPELL)
    if not cd or not cd.duration or cd.duration == 0 then return 0 end
    local r = (cd.startTime + cd.duration) - GetTime()
    return r > 0 and r or 0
end

-- 现在可用,或仅被 GCD 挡住 (出招助手要的是"下一个该按的",所以 GCD 中也算可用)
local function ReadyOrGCD(spellID)
    if not spellID then return false end
    local ch = C_Spell.GetSpellCharges(spellID)
    if ch and (ch.maxCharges or 0) > 1 then
        return (ch.currentCharges or 0) >= 1
    end
    local cd = C_Spell.GetSpellCooldown(spellID)
    if not cd then return false end
    if not cd.duration or cd.duration == 0 then return true end
    local remain = (cd.startTime + cd.duration) - GetTime()
    return remain <= GCDRemain() + 0.1
end

-- 自身 Buff 剩余秒数 (无则 0;secret 则 0)
local function BuffRemains(spellID)
    if not spellID then return 0 end
    local a = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    if not a then return 0 end
    local exp = a.expirationTime
    if isSecret(exp) or not exp then return 0 end
    if exp == 0 then return 999 end
    local r = exp - GetTime()
    return r > 0 and r or 0
end

-- 目标身上某 debuff: 返回 层数, 是否存在, 是否可读
-- 12.0 战斗中目标光环的 spellId 可能是 secret → 无法比较识别,此时 readable=false
local function TargetDebuff(spellID)
    if not spellID or not UnitExists("target") then return 0, false, true end
    for i = 1, 40 do
        local d = C_UnitAuras.GetAuraDataByIndex("target", i, "HARMFUL|PLAYER")
        if not d then break end
        if isSecret(d.spellId) then
            return 0, false, false   -- 目标光环被保护,读不到 → 未知
        end
        if d.spellId == spellID then
            local app = d.applications
            if isSecret(app) then return 1, true, true end
            return app or 1, true, true
        end
    end
    return 0, false, true
end

local function TargetHealthPct()
    if not UnitExists("target") then return nil end
    local hp, mx = UnitHealth("target"), UnitHealthMax("target")
    if isSecret(hp) or isSecret(mx) or not mx or mx == 0 then return nil end
    return hp / mx * 100
end

local function RunicPower()
    local rp = UnitPower("player", Enum.PowerType.RunicPower)
    if isSecret(rp) then return nil end
    return rp
end

local function RunicPowerMax()
    local m = UnitPowerMax("player", Enum.PowerType.RunicPower)
    if isSecret(m) or not m or m == 0 then return nil end
    return m
end

local function RunesReady()
    local n = 0
    for i = 1, 6 do
        local _, _, ready = GetRuneCooldown(i)
        if ready then n = n + 1 end
    end
    return n
end

-- true=在身, false=确认掉了, nil=读不到(未知)
local function DiseaseUp()
    local _, vp, readable = TargetDebuff(S.Debuff_VirulentPlague)
    if not readable then return nil end
    local _, dp = TargetDebuff(S.Debuff_DreadPlague)
    return vp or dp
end

local function HasEnemyTarget()
    return UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
end

-- ----------------------------------------------------------------------------
-- 优先级求值 (Rider 单体)。返回建议 spellID 或 nil。
-- 由 UpdateRotation 用 pcall 包裹 —— secret 抛错时退回上一次建议。
-- 顺序参考 SimC midnight 分支 single_target + cooldowns,裁剪到你的天赋,并对不可读状态优雅降级。
-- ----------------------------------------------------------------------------
local function Evaluate()
    if not HasEnemyTarget() then return nil end

    local hp = TargetHealthPct()                  -- nil = 不可读 (secret/无目标)
    local wounds, _, woundReadable = TargetDebuff(S.Debuff_FesteringWound)

    -- 1) 上疾病 (只在"确认掉了"时提示;读不到 → 不提示,避免刷屏)
    if Known(S.Outbreak) and ReadyOrGCD(S.Outbreak) and DiseaseUp() == false then
        return S.Outbreak
    end
    -- 2) Sudden Doom 触发 → 立刻 Death Coil
    if BuffRemains(S.Aura_SuddenDoom) > 0 and Known(S.DeathCoil) then
        return S.DeathCoil
    end
    -- 3) Soul Reaper 斩杀 (HP 不可读时不强行触发)
    if Known(S.SoulReaper) and ReadyOrGCD(S.SoulReaper) and hp and hp <= 35 then
        return S.SoulReaper
    end
    -- 4) Army of the Dead (好了就上)
    if Known(S.ArmyOfTheDead) and ReadyOrGCD(S.ArmyOfTheDead) then
        return S.ArmyOfTheDead
    end
    -- 5) Dark Transformation (有宝宝时)
    if Known(S.DarkTransformation) and ReadyOrGCD(S.DarkTransformation) and DodoUnholy:IsGhoulPresent() then
        return S.DarkTransformation
    end
    -- 6) Putrefy (非斩杀阶段;HP 不可读时默认允许) —— 待填 ID 后激活
    if Known(S.Putrefy) and ReadyOrGCD(S.Putrefy) and (not hp or hp > 35) then
        return S.Putrefy
    end
    -- 7) 倒符能:符文<2 或 符能接近溢出 → Death Coil
    local rp, rpMax = RunicPower(), RunicPowerMax()
    local runes = RunesReady()
    local spendingRP = false
    if runes < 2 then spendingRP = true end
    if rp and rpMax and rp >= rpMax - 10 then spendingRP = true end
    if spendingRP and Known(S.DeathCoil) and (not rp or rp >= 30) then
        return S.DeathCoil
    end
    -- 8) 有脓疮伤口 → Scourge Strike 消伤口 (仅在伤口可读时)
    if woundReadable and Known(S.ScourgeStrike) and ReadyOrGCD(S.ScourgeStrike) and wounds >= 1 then
        return S.ScourgeStrike
    end
    -- 9) 攒伤口 (伤口可读且 <4 时)
    if woundReadable and Known(S.FesteringStrike) and ReadyOrGCD(S.FesteringStrike) and wounds < 4 then
        return S.FesteringStrike
    end
    -- 10) 兜底:有符能就 Death Coil,否则 Festering Strike
    if Known(S.DeathCoil) and rp and rp >= 30 then
        return S.DeathCoil
    end
    if Known(S.FesteringStrike) and ReadyOrGCD(S.FesteringStrike) then
        return S.FesteringStrike
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- 显示 (置顶图标;解锁后可拖动)
-- ----------------------------------------------------------------------------
function DodoUnholy:CreateRotationFrame()
    if self.rotationFrame then return end
    local r = self.db.rotation
    local f = CreateFrame("Button", ADDON .. "RotationIcon", UIParent)
    f:SetSize(r.iconSize, r.iconSize)
    f:SetPoint("CENTER", UIParent, "CENTER", r.posX, r.posY)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:EnableMouse(not r.locked)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- 裁掉图标默认边
    f.icon = icon

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -2, 2)
    bg:SetPoint("BOTTOMRIGHT", 2, -2)
    bg:SetColorTexture(0, 0, 0, 0.5)
    f.bg = bg

    f:SetScript("OnDragStart", function(btn)
        if not self.db.rotation.locked then btn:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(btn)
        btn:StopMovingOrSizing()
        local cx, cy = btn:GetCenter()
        local px, py = UIParent:GetCenter()
        if cx and px then
            self.db.rotation.posX = math.floor(cx - px + 0.5)
            self.db.rotation.posY = math.floor(cy - py + 0.5)
        end
    end)

    f:Hide()
    self.rotationFrame = f
end

function DodoUnholy:ApplyRotationAppearance()
    local f = self.rotationFrame
    if not f then return end
    local r = self.db.rotation
    f:SetSize(r.iconSize, r.iconSize)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", r.posX, r.posY)
    f:EnableMouse(not r.locked)
end

function DodoUnholy:UpdateRotation()
    local f = self.rotationFrame
    if not f then return end
    local r = self.db.rotation

    if not (r.enabled and self:IsUnholyDeathKnight()) then
        f:Hide()
        return
    end

    -- 12.0.7: 战斗中所需状态全被 secret/forbidden 封死 → 战斗中不评估、不显示,避免触发禁用
    if InCombatLockdown() then
        f:Hide()
        return
    end
    if not HasEnemyTarget() then
        f:Hide()
        return
    end

    local ok, spellID = pcall(Evaluate)
    if not ok then
        spellID = self._lastSpell  -- secret 抛错 → 维持上次
    end

    if spellID then
        f.icon:SetTexture(C_Spell.GetSpellTexture(spellID))
        f:Show()
        self._lastSpell = spellID
    else
        f:Hide()
    end
end

-- ----------------------------------------------------------------------------
-- 设置面板追加项 (由 DodoUnholy.lua 的 CreateOptionsPanel 调用)
-- ----------------------------------------------------------------------------
function DodoUnholy:AddRotationOptions(panel, anchor)
    local r = self.db.rotation

    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -24)
    header:SetText("单体出招助手 (V0)")

    local enableCheck = CreateFrame("CheckButton", ADDON .. "RotationEnableCheck", panel, "UICheckButtonTemplate")
    enableCheck:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    enableCheck:SetChecked(r.enabled)
    _G[enableCheck:GetName() .. "Text"]:SetText("启用出招建议图标")
    enableCheck:SetScript("OnClick", function(b)
        self.db.rotation.enabled = b:GetChecked() and true or false
        self:UpdateRotation()
    end)

    local lockCheck = CreateFrame("CheckButton", ADDON .. "RotationLockCheck", panel, "UICheckButtonTemplate")
    lockCheck:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, -4)
    lockCheck:SetChecked(r.locked)
    _G[lockCheck:GetName() .. "Text"]:SetText("锁定图标位置 (取消勾选后可拖动)")
    lockCheck:SetScript("OnClick", function(b)
        self.db.rotation.locked = b:GetChecked() and true or false
        self:ApplyRotationAppearance()
    end)

    local oocCheck = CreateFrame("CheckButton", ADDON .. "RotationOOCCheck", panel, "UICheckButtonTemplate")
    oocCheck:SetPoint("TOPLEFT", lockCheck, "BOTTOMLEFT", 0, -4)
    oocCheck:SetChecked(r.showOutOfCombat)
    _G[oocCheck:GetName() .. "Text"]:SetText("脱战也显示 (选中敌对目标即显示)")
    oocCheck:SetScript("OnClick", function(b)
        self.db.rotation.showOutOfCombat = b:GetChecked() and true or false
        self:UpdateRotation()
    end)

    local sizeBox, sizeLabel = self:CreateLabeledEditBox(
        panel, "图标大小", 22, 0, r.iconSize,
        function(box)
            local v = tonumber(box:GetText())
            if not v then box:SetText(tostring(self.db.rotation.iconSize)); return end
            self.db.rotation.iconSize = clamp(math.floor(v + 0.5), 16, 256)
            box:SetText(tostring(self.db.rotation.iconSize))
            self:ApplyRotationAppearance()
        end,
        function(box) box:SetText(tostring(self.db.rotation.iconSize)) end
    )
    -- CreateLabeledEditBox 默认把 label 锚到 panel 左上角,这里重锚到本区块下方 (box 跟随 label)
    sizeLabel:ClearAllPoints()
    sizeLabel:SetPoint("TOPLEFT", oocCheck, "BOTTOMLEFT", 4, -14)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", oocCheck, "BOTTOMLEFT", 4, -48)
    hint:SetWidth(700)
    hint:SetJustifyH("LEFT")
    hint:SetText("图标只做提示、不会替你按键。/duh scan 导出技能ID,/duh debug 看实时读数。\n新技能 (Putrefy/凋零疫病/剧毒镰刀) 待确认ID后才会纳入建议。")

    panel:HookScript("OnShow", function()
        enableCheck:SetChecked(self.db.rotation.enabled)
        lockCheck:SetChecked(self.db.rotation.locked)
        oocCheck:SetChecked(self.db.rotation.showOutOfCombat)
        sizeBox:SetText(tostring(self.db.rotation.iconSize))
    end)
end

-- ----------------------------------------------------------------------------
-- 诊断命令
-- ----------------------------------------------------------------------------
function DodoUnholy:ScanBars()
    print("|cff33ff99DodoUnholy 扫描|r 动作条技能 (ID : 名称) —— 复制整段发我:")
    local seen = {}
    for slot = 1, 120 do
        local actionType, id = GetActionInfo(slot)
        if actionType == "spell" and id and not seen[id] then
            seen[id] = true
            local name = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
            print(("%d : %s"):format(id, name or "?"))
        end
    end
    print("|cff33ff99DodoUnholy|r 扫描完毕。")
end

-- 探测某读取的结果: "值" / "secret" / "nil" / "err"
local function probeVal(fn)
    local ok, v = pcall(fn)
    if not ok then return "err" end
    if v == nil then return "nil" end
    if isSecret(v) then return "secret" end
    return tostring(v)
end

function DodoUnholy:DebugRotation()
    print("|cff33ff99DodoUnholy 探测|r 12.0.7 战斗可读性 (打着木桩、处于战斗中再敲):")
    print(" InCombat=", tostring(InCombatLockdown()),
          " | 目标=", UnitExists("target") and (GetUnitName("target") or "?") or "无",
          " | 可攻击=", tostring(HasEnemyTarget()))
    print(" 目标HP=", probeVal(function() return UnitHealth("target") end),
          " / max=", probeVal(function() return UnitHealthMax("target") end))
    print(" 符能=", probeVal(function() return UnitPower("player", Enum.PowerType.RunicPower) end),
          " / max=", probeVal(function() return UnitPowerMax("player", Enum.PowerType.RunicPower) end),
          " | 符文就绪=", tostring(RunesReady()))
    print(" 自身Buff SuddenDoom(81340).expiration=", probeVal(function()
        local a = C_UnitAuras.GetPlayerAuraBySpellID(81340); return a and a.expirationTime or nil
    end))
    for _, filt in ipairs({ "HARMFUL", "HARMFUL|PLAYER" }) do
        print((" 目标光环[%s]:"):format(filt))
        local any = false
        for i = 1, 8 do
            local d = C_UnitAuras.GetAuraDataByIndex("target", i, filt)
            if not d then break end
            any = true
            local sid = isSecret(d.spellId) and "secret" or tostring(d.spellId)
            local app = isSecret(d.applications) and "secret" or tostring(d.applications)
            local nm  = isSecret(d.name) and "secret" or tostring(d.name)
            print(("   #%d id=%s 层=%s 名=%s"):format(i, sid, app, nm))
        end
        if not any then print("   (无)") end
    end
    print("|cff33ff99DodoUnholy|r 探测完毕,整段发我。")
end

-- 战斗日志探针: 测 COMBAT_LOG 在 12.0.7 战斗中是否还能读到 spellId (决定能否自己数伤口)
function DodoUnholy:ProbeCombatLog()
    local f = self._clProbeFrame
    if not f then
        f = CreateFrame("Frame")
        self._clProbeFrame = f
    end
    local n = 0
    print("|cff33ff99DodoUnholy CL探针|r 接下来 ~8 秒持续打木桩,抓战斗日志事件...")
    f:SetScript("OnEvent", function()
        if n >= 12 then return end
        local ok = pcall(function()
            local info = { CombatLogGetCurrentEventInfo() }
            local sub = info[2]
            if type(sub) ~= "string" or not sub:find("SPELL") then return end
            n = n + 1
            local sid    = isSecret(info[12]) and "secret" or tostring(info[12])
            local nm     = isSecret(info[13]) and "secret" or tostring(info[13])
            local srcSec = isSecret(info[4]) and "secret" or "ok"
            local dstSec = isSecret(info[8]) and "secret" or "ok"
            print(("CL#%d %s id=%s 名=%s src=%s dst=%s"):format(n, tostring(sub), sid, nm, srcSec, dstSec))
        end)
        if not ok then print("CL 事件读取抛错(疑似 secret)") end
    end)
    f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    C_Timer.After(8, function()
        f:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        f:SetScript("OnEvent", nil)
        print("|cff33ff99DodoUnholy|r CL探针结束,整段发我。")
    end)
end

-- ----------------------------------------------------------------------------
-- 初始化 (由 DodoUnholy:Initialize 调用)
-- ----------------------------------------------------------------------------
function DodoUnholy:InitRotation()
    self:CreateRotationFrame()

    -- 诊断: 捕获本插件触发的"禁用/受保护操作",打印到底是哪个函数被封
    local guard = CreateFrame("Frame")
    guard:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    guard:RegisterEvent("ADDON_ACTION_BLOCKED")
    guard:SetScript("OnEvent", function(_, ev, addon, func)
        print(("|cffff3333DodoUnholy拦截|r %s addon=%s func=%s"):format(ev, tostring(addon), tostring(func)))
    end)
    self.rotationGuard = guard

    -- 始终显示的驱动帧,固定节流刷新 (隐藏帧不触发 OnUpdate,故另起一个常显驱动)
    local driver = CreateFrame("Frame", nil, UIParent)
    local acc = 0
    driver:SetScript("OnUpdate", function(_, e)
        acc = acc + e
        if acc < 0.1 then return end
        acc = 0
        self:UpdateRotation()
    end)
    self.rotationDriver = driver

    self:UpdateRotation()
end
