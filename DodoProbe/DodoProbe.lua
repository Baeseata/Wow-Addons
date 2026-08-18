-- DodoProbe: measures which combat APIs still hand addons real (non-secret) values in 12.1.
-- Temporary diagnostic. Everything is wrapped in pcall so a blocked call reports instead of erroring.

local P = CreateFrame("Frame")
local out = {}

local function say(s) print("|cff33ff99DodoProbe|r " .. s) end

-- Classify one value without ever operating on it unsafely.
local function tag(ok, v)
    if not ok then return "|cffff3333ERROR|r" end
    if v == nil then return "|cff888888nil|r" end
    if issecretvalue and issecretvalue(v) then return "|cffff8800SECRET|r" end
    if type(v) == "table" then
        if issecrettable and issecrettable(v) then return "|cffff8800SECRET-TABLE|r" end
        return "|cff00ff00table(open)|r"
    end
    return "|cff00ff00" .. tostring(v) .. "|r"
end

local function probe(label, fn)
    local ok, v = pcall(fn)
    out[#out + 1] = string.format("  %-34s %s", label, tag(ok, v))
end

local function sname(id)
    if not id then return nil end
    local ok, n = pcall(C_Spell.GetSpellName, id)
    return ok and n or nil
end

-- Two spell ids this probe needs by name, NOT verified at the time of writing -- the probe
-- prints GetSpellName() next to each so a wrong id is obvious on sight instead of quietly
-- producing an empty result that reads like "the feature doesn't work".
-- Override in-game: /dp dot <id>   /dp exec <id>
P.dotID = 34914   -- 吸血鬼之触? (used by probe B's includeSpellIDs filter)
P.execID = 32379  -- 暗言术:灭?  (used by probe C)

-- Pull one real rotational spell id so cooldown/aura probes hit something that exists.
local function firstRotationSpell()
    if not C_AssistedCombat or not C_AssistedCombat.GetRotationSpells then return nil end
    local ok, t = pcall(C_AssistedCombat.GetRotationSpells)
    if ok and type(t) == "table" and t[1] then return t[1] end
    return nil
end

-- 聊天框读不了这么长的输出(而且滚上去截图很痛苦)。这个窗把最后一次结果原样端出来,
-- Ctrl+A / Ctrl+C 一把带走。颜色码要剥掉,否则复制出去全是 |cffff8800 这种噪音。
local function StripColors(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- ── 📤 落盘通道:探针结果直接进 SavedVariables,不用再靠截屏 / 手抄传给 Claude。
-- 🔴 **SavedVariables 只在 `/reload` 或退出游戏时才写盘** ⇒ 流程必须是「跑 → /reload → 读文件」。
--    漏掉那步 /reload 的症状是「文件里没有这次的结果」,而它跟「探针根本没跑」长得一模一样。
-- 落盘位置:WTF\Account\<账号>\SavedVariables\DodoProbe.lua(游戏自己另留一份 .bak)
-- ⚠ 颜色码在这儿剥掉:它对屏幕有用,进文件就只是噪音,还会干扰 grep。
local LOG_MAX = 3000   -- 上限。不设的话它只增不减,迟早把存档撑大而没人发现

local function LogPush(tag, text)
    DodoProbeDB = DodoProbeDB or {}
    if type(DodoProbeDB.log) ~= "table" then DodoProbeDB.log = {} end
    local log = DodoProbeDB.log
    log[#log + 1] = date("%m-%d %H:%M:%S") .. "  [" .. tostring(tag) .. "]  "
        .. StripColors(tostring(text))
    while #log > LOG_MAX do table.remove(log, 1) end
end

-- 公开给**任何**插件:`if DodoProbeLog then DodoProbeLog("dch", s) end`
-- 探测式调用 ⇒ 被测插件零依赖,没装 DodoProbe 也不会崩。
_G.DodoProbeLog = LogPush

local function ShowCopyBox(text)
    if not P.copyFrame then
        local f = CreateFrame("Frame", "DodoProbeCopyFrame", UIParent, "BackdropTemplate")
        f:SetSize(720, 480)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        f:SetBackdropColor(0, 0, 0, 0.92)
        f:SetBackdropBorderColor(1, 0.6, 0, 1)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -8)
        title:SetText("DodoProbe  —  Ctrl+A 全选, Ctrl+C 复制, Esc 关闭 (可拖动)")

        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 12, -30)
        sf:SetPoint("BOTTOMRIGHT", -32, 12)

        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(660)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.eb = eb
        P.copyFrame = f
    end
    P.copyFrame.eb:SetText(text)
    P.copyFrame:Show()
    P.copyFrame.eb:SetFocus()
    P.copyFrame.eb:HighlightText()
end

-- ===== B. CustomAuraContainer 绑 "target" + includeSpellIDs 精确筛 =====
-- 两个问题一次量:① 这个容器能不能绑 unit token "target"(= 完全不经名条)
-- ② candidateFilters.includeSpellIDs 在**敌方目标的 debuff** 上到底生不生效。
-- 源码说生效(AuraContainerUtil.CanApplyIdentityCandidateFilters 只禁「友方身上的 debuff」和
-- 「敌方身上的 buff」,我们这个组合两条都不沾),但那是契约,不是实测。
local function EnsureAuraProbe()
    if P.auraBuilt ~= nil then return P.auraBuilt end
    P.auraBuilt = false
    if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo
            and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate")) then
        P.auraErr = "没有 CustomAuraContainerTemplate"
        return false
    end

    -- bucket 收集本组创建过的按钮,好在报告里数「现在显示着几个」。
    -- ⚠ 数字只是佐证,**判据是屏幕** —— 池子里的按钮什么时候被回收不归我们管。
    local function makeInit(bucket)
        return function(button)
            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(button)
            button:SetIcon(icon)
            -- 倒计时归暴雪画 —— 插件自己的 SetCooldown 吃不下 secret,这正是走这条路的全部理由。
            local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
            cd:SetAllPoints(icon)
            cd:SetReverse(true)
            button:SetDurationCooldown(cd)
            button:SetSize(32, 32)
            bucket[#bucket + 1] = button
        end
    end

    local function mk(suffix, yOff, label, filterStr, filters)
        local c = CreateFrame("AuraContainer", "DodoProbeAura" .. suffix,
            UIParent, "CustomAuraContainerTemplate")
        c.dpButtons = {}
        c:SetSize(240, 34)
        c:SetPoint("TOPLEFT", UIParent, "TOP", -40, yOff)
        c:SetFlowLayoutAnchorPoint("TOPLEFT")
        c:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
        c:SetFlowLayoutMaximumLineSize(math.huge)
        c:SetUnit("target")
        c:AddAuraGroup("g", filterStr, {
            maxFrameCount = 6,
            sortMethod = AuraContainerSortMethod.Expiration,
            sortDirection = AuraContainerSortDirection.Normal,
            candidateFilters = filters,
            initializeFrame = makeInit(c.dpButtons),
            layout = { elementSpacing = 2, elementWidth = 32, elementHeight = 32, layoutIndex = 1 },
        })
        -- 🔴 这个标签**不能**锚到容器上。实测(12.1.0.69299):
        --   FontString:SetPoint(): Anchoring disallowed as dependent object would inherit
        --   forbidden aspects: UntrustedLayoutScriptExecution
        -- CustomAuraContainer 带着 forbidden aspect ⇒ 插件自己的对象往它身上锚 = 直接被拒,
        -- 而它是在 pcall 里抛的,表现成「整个探针建不起来」,看着像容器这条路不通。
        -- 反方向是允许的:容器 SetParent/SetPoint 到插件的框体上(DodoNameplate 一直这么用)。
        local fs = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPRIGHT", UIParent, "TOP", -46, yOff - 9)
        fs:SetText(label)
        c:SetEnabled(true)
        return c
    end

    -- 三行,不是两行。第三行(最宽的 "HARMFUL")专门为了拆开「上行是 0」这个最容易读反的结果:
    -- 三行全 0 = 绑 target 这条路不通;只有这行有 = 是 |PLAYER 或 |INCLUDE_NAME_PLATE_ONLY 出的问题,
    -- 跟容器本身无关。少了它,一个 0 会被当成「这条路死了」直接写进结论。
    local NP = "|INCLUDE_NAME_PLATE_ONLY"
    local ok, err = pcall(function()
        P.auraAny = mk("Any", -100, "任何 harmful >", "HARMFUL" .. NP, nil)
        P.auraAll = mk("All", -140, "我上的全部 >", "HARMFUL|PLAYER" .. NP, nil)
        P.auraOne = mk("One", -180, "只要这一个 >", "HARMFUL|PLAYER" .. NP,
            { includeSpellIDs = { [P.dotID] = true } })
    end)
    if not ok then P.auraErr = tostring(err); return false end
    P.auraBuilt = true
    P.auraShown = true
    return true
end

-- ===== /dp tint:DoT 染色机制的端到端验证(整套设计一屏看完)=====
-- 三层贴图叠在一根假血条上,每层的 parent 都是一个 **aura button** ⇒ 由 C 层按「那个光环在不在」
-- 开关它。插件全程**不读光环、不做任何比较**;层叠顺序本身就是优先级仲裁。
--   无 DoT → 灰(底色)   只有痛 → 橙   只有触 → 紫   两个都有 → 蓝(最上层,盖住橙和紫)
-- 🔑 「有痛**没**触」这个否定是被层叠**免费**吃掉的 —— 橙层根本不需要知道触在不在。
--
-- 写法全部照抄在产的 PlateTweaks 1.5.0(`Tints.lua`),四条硬约束一条都不能省:
-- 🔴 贴图必须在 `initializeFrame` **那一瞬间**建 —— 暴雪紧接着就
--    `ApplyAccessRestrictions(…, DenyTaintedAccessWhenAurasAreSecret)`;晚一步 = **整个副本里全不生效**。
-- 🔴 谁盖谁只能靠 **draw sublevel**,**绝不能 `SetFrameLevel`** —— aura button 的 strata 是 secret,
--    光环 secret 时那个调用被拒。
-- 🔴 嵌套 = AND:在「痛」的按钮里再建一个筛「触」的容器,祖先隐藏则后代不渲染。
-- 🔴 嵌套容器 `SetAllPoints` 要指向**血条**,绝不指向它的父按钮 ——
--    「我们的对象锚到它们的」被拒,「它们的锚到我们的」可以(本文件 B 组早就实测过这条)。
local TINT_SWP, TINT_VT = 589, 34914
local C_ONLY_SWP  = { 1.00, 0.55, 0.10 }   -- 橙:只有 暗言术:痛
local C_ONLY_VT   = { 0.65, 0.30, 1.00 }   -- 紫:只有 吸血鬼之触
local C_BOTH      = { 0.15, 0.50, 1.00 }   -- 蓝:两个都有

local function TintTex(button, bar, rgb, sub)
    local t = button:CreateTexture(nil, "OVERLAY", nil, sub)
    t:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
    t:SetPoint("TOPLEFT", bar, "TOPLEFT", 2, -2)
    t:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -2, 2)
    return t
end

-- 一条「只筛这一个法术」的规则。slot 池 **1** 个 frame、group 池 **10** 个
-- (暴雪硬编码 FrameCreationBatchSize=10,注释写明是故意的)⇒ 有 slot 就用 slot。
-- 🔴 现场问**这个容器对象**,别提前缓存:Blizzard_AuraContainer 加载晚,早问会得到「不可用」
--    然后整个 session 静默走 10 帧路径,而功能看着是开着的。
local function AddOneSpell(c, key, spellID, initFn)
    local useSlot = type(c.AddAuraSlot) == "function"
        and type(c.SetAuraSlotCandidateFilters) == "function"
    P.tintUsedSlot = useSlot
    local Register = useSlot and c.AddAuraSlot or c.AddAuraGroup
    Register(c, key, "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY", { initializeFrame = initFn })
    local ids = { [spellID] = true }
    if useSlot then
        c:SetAuraSlotCandidateFilters(key, { includeSpellIDs = ids })
    else
        c:SetAuraGroupCandidateFilters(key, { includeSpellIDs = ids })
        c:SetAuraGroupMaxFrameCount(key, 1)
    end
end

-- ⚠ 这里**故意不调** SetIcon / SetDurationCooldown:我们只要按钮的**可见性**,不要它画图标。
--   (PlateTweaks 的 initializeFrame 同样一个图标都不设 —— 只挂贴图。)
local function NewTintContainer(name, parent, bar)
    local c = CreateFrame("AuraContainer", name, parent, "CustomAuraContainerTemplate")
    c:SetEnabled(false)
    pcall(c.SetAllPoints, c, bar)     -- 锚**血条**,绝不锚父按钮
    c:SetFlowLayoutAnchorPoint("TOPLEFT")
    c:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    c:SetFlowLayoutMaximumLineSize(math.huge)
    return c
end

function P.BuildTintRig()
    if P.tintBar then P.tintBar:Show(); return P.tintErrs end
    local bar = CreateFrame("Frame", "DodoProbeTintBar", UIParent)
    bar:SetSize(220, 26)
    bar:SetPoint("CENTER", UIParent, "CENTER", 0, -170)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0.30, 0.30, 0.30, 1)   -- 「无 DoT」= 灰底。什么都不画出来的就是它。
    P.tintBar = bar
    P.tintCs = {}
    local errs = {}

    -- 🔴 容器只按 unit token 注册 `UNIT_AURA`,**`PLAYER_TARGET_CHANGED` 不在它的表里**
    --    ⇒ 绑 "target" 就必须自己接那个事件调 `UpdateAllAuras()`,否则换目标后条上显示的
    --    还是**上一个目标**的状态 —— 症状就是「反应不灵敏 / 慢一拍」,而且它看着完全像
    --    「机制本身有延迟」。⚠ **这是探针专有的毛病**:真接进名条时容器绑永久的
    --    `nameplateN`,不吃这一条 —— 别把它读成机制的性能问题。
    -- 🔴 第二条(canon 采样探针铁律):**必须报出「这次测的是谁」** —— 否则量错对象时,
    --    你拿到的是一份可信、干净、而且无关的数据。时间戳则让「它到底刷没刷」可见。
    local who = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    who:SetPoint("BOTTOM", bar, "TOP", 0, 3)
    who:SetText("|cff888888还没换过目标|r")
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:SetScript("OnEvent", function()
        for _, c in ipairs(P.tintCs) do pcall(c.UpdateAllAuras, c) end
        local okN, n = pcall(UnitName, "target")
        -- 守卫顺序不能反:secret 检查必须在 nil 比较**之前**(GOTCHAS S1)。
        if okN and not (issecretvalue and issecretvalue(n)) and n ~= nil then
            who:SetText(tostring(n) .. "  |cff888888" .. date("%H:%M:%S") .. "|r")
        elseif UnitExists("target") then
            who:SetText("|cffffaa00名字读不出来|r  |cff888888" .. date("%H:%M:%S") .. "|r")
        else
            who:SetText("|cff888888没选目标|r")
        end
    end)
    P.tintEv = ev

    -- 层 1(橙)+ 层 3(蓝):痛的容器。它的按钮同时扛「橙贴图」和「嵌套的触容器」。
    local ok1, err1 = pcall(function()
        local c1 = NewTintContainer("DodoProbeTintSWP", UIParent, bar)
        AddOneSpell(c1, "swp", TINT_SWP, function(button)
            TintTex(button, bar, C_ONLY_SWP, 1)
            local okN, c2 = pcall(NewTintContainer, nil, button, bar)   -- parent = 按钮 ⇒ 祖先隐藏则整棵不渲染
            if not okN or not c2 then errs[#errs + 1] = "嵌套容器建不起来: " .. tostring(c2); return end
            AddOneSpell(c2, "both", TINT_VT, function(inner)
                TintTex(inner, bar, C_BOTH, 3)                          -- 蓝在最上,盖住橙和紫
            end)
            c2:SetUnit("target"); c2:SetEnabled(true)
            P.tintCs[#P.tintCs + 1] = c2
            P.tintNested = true
        end)
        c1:SetUnit("target"); c1:SetEnabled(true)
        P.tintCs[#P.tintCs + 1] = c1
    end)
    if not ok1 then errs[#errs + 1] = "痛层: " .. tostring(err1) end

    -- 层 2(紫):触的容器,单独一条 —— 在橙之上、蓝之下。
    local ok2, err2 = pcall(function()
        local c3 = NewTintContainer("DodoProbeTintVT", UIParent, bar)
        AddOneSpell(c3, "vt", TINT_VT, function(button)
            TintTex(button, bar, C_ONLY_VT, 2)
        end)
        c3:SetUnit("target"); c3:SetEnabled(true)
        P.tintCs[#P.tintCs + 1] = c3
    end)
    if not ok2 then errs[#errs + 1] = "触层: " .. tostring(err2) end

    P.tintErrs = errs
    return errs
end

-- ===== 延迟探针:上了 DoT,名条上的图标慢一拍 =====
-- 🔴 **「图标什么时候出现」这个量测不出来** —— `button:IsShown()` 是 secret(2026-08-15 实测,
-- 一做布尔测试就崩)。所以本探针**不去测它**,改测「UNIT_AURA 事件几点到的」,
-- 再把「事件到了」画成屏幕上闪一下 —— 参照物必须跟图标在**同一个视野**里,
-- 否则「事件的时刻」活在聊天框、「图标的时刻」活在屏幕,两个世界没法比。
--
-- 判据(闪块 vs 你眼睛看到图标出现):
--   闪块和图标几乎同时     ⇒ 事件层没问题,慢的是暴雪容器的渲染/节流
--   闪块先亮、图标晚一拍   ⇒ 同上,而且这一拍被量化了
--   闪块本身就晚           ⇒ 慢在事件层(服务器→客户端),插件这边无能为力
local LAT_WINDOW = 4
-- 只对**真的会上 debuff 的那几个**开始计时。第一版是「arm 后第一个施法就计时」,
-- 结果采到了「触须猛击」——**量的不是他报的那个症状**,而输出看起来完全正常。
-- (canon:我这条验收路径,把那个症状执行到了吗。)
local LAT_SPELLS = { [589] = true, [34914] = true, [335467] = true }  -- 痛 / 吸血鬼之触 / 癫

local function Now()
    return (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()
end

local function LatFlash()
    if not P.latFlash then
        local t = UIParent:CreateTexture(nil, "OVERLAY")
        t:SetSize(56, 56)
        t:SetPoint("CENTER", UIParent, "CENTER", 0, 240)
        t:SetColorTexture(0.2, 1, 0.35, 0.85)
        t:Hide()
        P.latFlash = t
    end
    P.latFlash:Show()
    C_Timer.After(0.3, function() if P.latFlash then P.latFlash:Hide() end end)
end

local function LatReport()
    local L = P.lat
    if not L or not L.t0 then return end
    local rows = { string.format("|cffffff00=== DoT 上身延迟:%s ===|r", tostring(sname(L.spell))) }
    for _, r in ipairs(L.rows) do rows[#rows + 1] = r end

    -- 顺带点一下 DodoNameplate 那三个容器 —— 它们有全局名(Auras.lua 里
    -- "DodoNameplateAura"..suffix..单位号),所以外部探针够得到。
    -- ⚠ 这几个值一律走 tag(),**不许 tostring** —— 万一哪个是 secret,tostring 当场崩。
    if L.plateN then
        for _, kind in ipairs({ "Main", "CC", "Buff" }) do
            local c = _G["DodoNameplateAura" .. kind .. L.plateN]
            if c then
                local okS, shown = pcall(function() return c:IsShown() end)
                local okV, vis   = pcall(function() return c:IsVisible() end)
                local okR, reg   = pcall(function() return c:IsEventRegistered("UNIT_AURA") end)
                rows[#rows + 1] = string.format("  容器 %-5s nameplate%-3s shown=%s visible=%s UNIT_AURA注册=%s",
                    kind, L.plateN, tag(okS, shown), tag(okV, vis), tag(okR, reg))
            end
        end
    else
        rows[#rows + 1] = "  |cffff8800整个窗口里没收到任何 nameplate 的 UNIT_AURA|r"
    end

    rows[#rows + 1] = "  |cff888888对照:闪块 vs 图标,谁先谁后 —— 判据见文件里那段注释|r"
    for _, r in ipairs(rows) do print(r) end
    P.lastOut = StripColors(table.concat(rows, "\n"))
    L.t0, L.spell, L.plateN = nil, nil, nil
    -- 采完一次就**自己收摊**:disarm + 注销 UNIT_AURA。
    -- 这个插件的设计原则是「默认完全静默」,而一个采完样还常驻监听的探针不满足它 ——
    -- 战斗中 UNIT_AURA 每秒几十次,留着纯烧,而且下次谁来读代码会以为它一直在测什么。
    L.armed = false
    P:UnregisterEvent("UNIT_AURA")
    say("延迟样本收完,探针已自动收起(要再采一次就再 /dp lat)。")
end

function P:Run(phase)
    wipe(out)
    local sid = firstRotationSpell()
    local inCombat = InCombatLockdown() and "IN COMBAT" or "out of combat"

    out[#out + 1] = string.format("|cffffff00=== %s (%s) ===|r", phase, inCombat)

    -- 1. Resource / health
    probe("UnitPower(player)",        function() return UnitPower("player") end)
    probe("UnitPowerMax(player)",     function() return UnitPowerMax("player") end)
    probe("UnitHealth(player)",       function() return UnitHealth("player") end)
    probe("UnitHealth(target)",       function() return UnitHealth("target") end)

    -- 2. Cooldowns / charges on a real rotation spell
    if sid then
        out[#out + 1] = "  |cff888888(cooldown probes use spellID " .. sid .. ")|r"
        probe("C_Spell.GetSpellCooldown",  function() return C_Spell.GetSpellCooldown(sid) end)
        probe("C_Spell.GetSpellCharges",   function() return C_Spell.GetSpellCharges(sid) end)
        probe("C_Spell.IsSpellUsable",     function() return C_Spell.IsSpellUsable(sid) end)
        probe("C_UnitAuras.GetPlayerAura", function() return C_UnitAuras.GetPlayerAuraBySpellID(sid) end)
    else
        out[#out + 1] = "  |cffff3333GetRotationSpells returned nothing - cooldown probes skipped|r"
    end

    -- 3. Target auras (DoT tracking)
    probe("GetAuraDataByIndex(target,1)", function()
        return C_UnitAuras.GetAuraDataByIndex("target", 1, "HARMFUL")
    end)

    -- 4. The official rotation channel
    probe("GetNextCastSpell()",       function() return C_AssistedCombat.GetNextCastSpell() end)
    probe("GetNextCastSpell(true)",   function() return C_AssistedCombat.GetNextCastSpell(true) end)
    probe("GetActionSpell()",         function() return C_AssistedCombat.GetActionSpell() end)
    probe("IsAvailable()",            function() return C_AssistedCombat.IsAvailable() end)
    probe("#GetRotationSpells()",     function()
        local t = C_AssistedCombat.GetRotationSpells()
        return t and #t or nil
    end)

    -- 4b. IsAvailable's SECOND return (failureReason) - probe() only keeps the first,
    -- and "false + why" is the whole answer when the rotation channel is dark.
    local okA, avail, why = pcall(C_AssistedCombat.IsAvailable)
    out[#out + 1] = string.format("  %-34s %s  reason=%s",
        "IsAvailable() +reason", tag(okA, avail), tag(okA, why))

    -- 4c. THE build-or-not question: can the suggested spellID drive name + icon?
    -- Contract says GetNextCastSpell returns a plain number and GetSpellName/Texture
    -- carry no secret returns -- verify live before building an addon on it.
    local okN, nxt = pcall(C_AssistedCombat.GetNextCastSpell)
    if okN and type(nxt) == "number" then
        probe("-> GetSpellName(next)",    function() return C_Spell.GetSpellName(nxt) end)
        probe("-> GetSpellTexture(next)", function() return C_Spell.GetSpellTexture(nxt) end)
    else
        out[#out + 1] = "  |cffff3333next cast not a plain number - display chain UNTESTED|r"
    end

    -- 4d. Is the rotation list itself walkable (elements readable, not just #t)?
    local okR, rl = pcall(C_AssistedCombat.GetRotationSpells)
    if okR and type(rl) == "table" then
        local names = {}
        for i = 1, math.min(#rl, 4) do
            local okn, n = pcall(C_Spell.GetSpellName, rl[i])
            names[#names + 1] = (okn and n) and tostring(n) or "?"
        end
        out[#out + 1] = string.format("  %-34s %s", "RotationSpells names[1..4]",
            table.concat(names, ", "))
    end

    -- 6. The four inputs a predictive rotation helper needs: spell CDs / my resource /
    -- my buffs / target DoTs. Each is a separate wall - measure them separately, and do
    -- not settle for the coarse answer the earlier rows give.
    out[#out + 1] = "|cffffff00--- 四件套 ---|r"

    -- Read one field off a possibly-secret table without ever operating on the value.
    local function field(t, k)
        local ok, v = pcall(function() return t[k] end)
        return tag(ok, v)
    end

    -- 6a. CD: rows above say the TABLE is open. That says nothing about its FIELDS -
    -- an open table can hand out secret members.
    if sid then
        local okC, cd = pcall(C_Spell.GetSpellCooldown, sid)
        if okC and type(cd) == "table" then
            out[#out + 1] = string.format("  %-34s start=%s dur=%s on=%s",
                "GetSpellCooldown 里的字段",
                field(cd, "startTime"), field(cd, "duration"), field(cd, "isEnabled"))
        end
    end

    -- 6b. Resource: the predicate reads "secret for power types not explicitly flagged
    -- as never secret" - that wording implies a whitelist exists. Walk the types.
    if Enum and Enum.PowerType then
        local types = { "Mana", "Rage", "Focus", "Energy", "ComboPoints", "Runes",
            "RunicPower", "SoulShards", "HolyPower", "Chi", "Insanity",
            "ArcaneCharges", "Fury", "Pain", "Essence" }
        local open = {}
        for _, n in ipairs(types) do
            local pt = Enum.PowerType[n]
            if pt then
                local ok, v = pcall(UnitPower, "player", pt)
                if ok and v ~= nil and not (issecretvalue and issecretvalue(v)) then
                    open[#open + 1] = n .. "=" .. tostring(v)
                end
            end
        end
        out[#out + 1] = string.format("  %-34s %s", "UnitPower 明文的能量类型",
            #open > 0 and ("|cff00ff00" .. table.concat(open, ", ") .. "|r")
                       or "|cffff8800一个都没有|r")
    end

    -- 6c. Own buffs: RequiresNonSecretAura returns nothing instead of erroring, and the
    -- docs say individual spells can be flagged never-secret. So count hits, don't guess.
    local hit, tried = 0, 0
    local hitNames = {}
    local okR2, rl2 = pcall(C_AssistedCombat.GetRotationSpells)
    if okR2 and type(rl2) == "table" then
        for i = 1, #rl2 do
            tried = tried + 1
            local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, rl2[i])
            if ok and a ~= nil then
                hit = hit + 1
                -- A count answers "how many", and "how many" is useless when 1 of 12 survives
                -- combat -- the whole question is WHICH one. rl2[i] is a plain number (measured),
                -- so it can be named without ever touching the aura table itself.
                local okn, n = pcall(C_Spell.GetSpellName, rl2[i])
                hitNames[#hitNames + 1] = (okn and n) and tostring(n) or ("#" .. tostring(rl2[i]))
            end
        end
    end
    local byIndex = 0
    for i = 1, 8 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if ok and a ~= nil then byIndex = byIndex + 1 end
    end
    out[#out + 1] = string.format("  %-34s BySpellID %d/%d   ByIndex %d/8",
        "自身 buff 拿到几个", hit, tried, byIndex)
    out[#out + 1] = string.format("  %-34s %s", "  -> BySpellID 命中的是",
        #hitNames > 0 and ("|cff00ff00" .. table.concat(hitNames, ", ") .. "|r")
                       or "|cff888888(一个都没有)|r")

    -- 6d. Target DoTs: the index walk already errors. Try the other two shapes before
    -- writing it off - "one call failed" is not "the whole channel is shut".
    if sid then
        probe("目标 GetAuraDataBySpellID", function()
            return C_UnitAuras.GetAuraDataBySpellID("target", sid)
        end)
    end
    probe("目标 ByIndex HARMFUL|PLAYER", function()
        return C_UnitAuras.GetAuraDataByIndex("target", 1, "HARMFUL|PLAYER")
    end)

    -- 7. Stop guessing which things are readable: C_Secrets declares it, per spell and
    -- per power type. NeverSecret is exactly the set a monitoring UI can read real numbers
    -- from. Section 6 measures, this section asks -- when the two disagree, that gap is
    -- itself the finding (GetSpellCooldown already contradicted its own annotation once).
    if C_Secrets then
        local LV = { [0] = "|cff00ff00Never|r", [1] = "|cffff3333Always|r", [2] = "|cffffff00Ctx|r" }
        local function lv(ok, v)
            if not ok then return "|cffff3333ERR|r" end
            return LV[v] or tostring(v)
        end

        out[#out + 1] = "|cffffff00--- C_Secrets 直接问 ---|r"
        local function flag(label, fn)
            local ok, v = pcall(fn)
            out[#out + 1] = string.format("  %-34s %s", label, tag(ok, v))
        end
        flag("HasSecretRestrictions()",   C_Secrets.HasSecretRestrictions)
        flag("ShouldCooldownsBeSecret()", C_Secrets.ShouldCooldownsBeSecret)
        flag("ShouldAurasBeSecret()",     C_Secrets.ShouldAurasBeSecret)

        local okR3, rl3 = pcall(C_AssistedCombat.GetRotationSpells)
        if okR3 and type(rl3) == "table" then
            for i = 1, #rl3 do
                local id = rl3[i]
                local okN2, nm  = pcall(C_Spell.GetSpellName, id)
                local okCd, cdL = pcall(C_Secrets.GetSpellCooldownSecrecy, id)
                local okAu, auL = pcall(C_Secrets.GetSpellAuraSecrecy, id)
                -- U 列:IsSpellUsable 实测是明文布尔(没被封)。它值钱的地方在于——
                -- 如果「暗言术: 灭」这行会随目标血量翻面,那斩杀线就是明文可读的,
                -- 插件能拿它做任何运算。对满血目标和残血目标各跑一次,比这一列。
                local okUs, us = pcall(C_Spell.IsSpellUsable, id)
                out[#out + 1] = string.format("  %-18s CD=%-20s Aura=%-20s U=%s",
                    (okN2 and nm) or ("#" .. tostring(id)),
                    lv(okCd, cdL), lv(okAu, auL), tag(okUs, us))
            end

            -- 施法条整个建在 Cast 上,而上面那张表只打了 CD 和 Aura —— 没打 Cast。
            -- 谓词是按**单位**判的(查 player 不满足条件 ⇒ 明文),但契约末尾留了
            -- 「个别法术可被单独标成永远 secret」的口子。所以不用逐行加一列把表挤爆,
            -- 只列**例外**:理想输出是「一个都没有」。
            local castOdd = {}
            for i = 1, #rl3 do
                local okCa, caL = pcall(C_Secrets.GetSpellCastSecrecy, rl3[i])
                if okCa and caL ~= 0 then
                    local okn, n = pcall(C_Spell.GetSpellName, rl3[i])
                    castOdd[#castOdd + 1] = ((okn and n) or ("#" .. tostring(rl3[i])))
                        .. "=" .. (LV[caL] or tostring(caL))
                elseif not okCa then
                    castOdd[#castOdd + 1] = "#" .. tostring(rl3[i]) .. "=ERR"
                end
            end
            out[#out + 1] = string.format("  %-34s %s", "施法 secrecy 非 Never 的",
                #castOdd > 0 and ("|cffff8800" .. table.concat(castOdd, " ") .. "|r")
                              or "|cff00ff00一个都没有(全 Never)|r")
        end

        if Enum and Enum.PowerType then
            local types = { "Mana", "Rage", "Focus", "Energy", "ComboPoints", "Runes",
                "RunicPower", "SoulShards", "HolyPower", "Chi", "Insanity",
                "ArcaneCharges", "Fury", "Pain", "Essence" }
            local parts = {}
            for _, n in ipairs(types) do
                local pt = Enum.PowerType[n]
                if pt then
                    local ok, l = pcall(C_Secrets.GetPowerTypeSecrecy, pt)
                    if ok and l ~= 1 then parts[#parts + 1] = n .. "=" .. (LV[l] or tostring(l)) end
                end
            end
            out[#out + 1] = string.format("  %-34s %s", "能量类型(非 Always 的)",
                #parts > 0 and table.concat(parts, " ") or "|cffff8800全是 Always|r")
        end
    else
        out[#out + 1] = "  |cffff3333C_Secrets 不存在|r"
    end

    -- 5. Can a secret be turned into a visible colour? (the display escape hatch)
    probe("ColorCurve create",        function() return C_CurveUtil.CreateColorCurve() ~= nil end)
    -- NOTE: this row feeds a PLAINTEXT bool - `hp ~= nil` is a nil check, not a comparison
    -- of the secret, so it never exercised the secret path. Kept as the plaintext control;
    -- the real test lives in section 8 below. (Measuring something immune to the question
    -- you are asking looks exactly like a pass.)
    probe("EvalColorFromBoolean(明文对照)", function()
        local hp = UnitHealth("player")
        local c = C_CurveUtil.EvaluateColorFromBoolean(hp ~= nil,
            CreateColor(1, 0, 0, 1), CreateColor(0, 1, 0, 1))
        return c ~= nil
    end)

    -- 5b. THE key question: can a secret be rendered as visible TEXT / bar width?
    -- If SetText accepts a secret, an external reader can just read the number off the screen
    -- and no colour-encoding scheme is needed at all.
    if not P.fs then
        P.holder = CreateFrame("Frame", nil, UIParent)
        P.holder:SetSize(220, 20)
        P.holder:SetPoint("TOP", UIParent, "TOP", 0, -140)
        P.fs = P.holder:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        P.fs:SetAllPoints()
        P.bar = CreateFrame("StatusBar", nil, P.holder)
        P.bar:SetSize(220, 6)
        P.bar:SetPoint("TOP", P.holder, "BOTTOM", 0, -2)
        P.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        P.bar:SetStatusBarColor(1, 0.5, 0)
        P.bar:SetMinMaxValues(0, 100)

        -- The cooldown swipe is the single most valuable channel for CD monitoring: if it
        -- accepts a secret start/duration, the player gets a real countdown that the addon
        -- itself still cannot read. That is enough for a human-driven rotation.
        P.iconHolder = CreateFrame("Frame", nil, P.holder)
        P.iconHolder:SetSize(48, 48)
        P.iconHolder:SetPoint("TOP", P.bar, "BOTTOM", 0, -8)
        P.iconTex = P.iconHolder:CreateTexture(nil, "ARTWORK")
        P.iconTex:SetAllPoints()
        P.cd = CreateFrame("Cooldown", nil, P.iconHolder, "CooldownFrameTemplate")
        P.cd:SetAllPoints()

        -- 专给「量程能不能是 secret」用的一次性条。不能借用上面那根 P.bar:
        -- 它的量程是创建时写死的明文 0..100,改掉就把资源条那几行的读数弄脏了。
        P.probeBar = CreateFrame("StatusBar", nil, P.holder)
        P.probeBar:SetSize(1, 1)
        P.probeBar:SetPoint("TOPLEFT", P.holder, "TOPLEFT")
        P.probeBar:Hide()

        -- 分段资源条(圣能 / 连击点 / 灵魂碎片)的可行性。
        -- 形状:每段一个 StatusBar,量程各自是 [(i-1)*step, i*step],**五段全喂同一个值**。
        -- 钳制和填充比例都在 C 层算 ⇒ 插件一次比较都不做。这是「逐颗点亮」
        -- (暴雪 ClassPowerBar:TurnOn/TurnOff,需要 `i <= 当前值`)在 secret 下唯一可能的替代。
        -- 🔴 **必须两排**:只画 secret 那排的话没有判据 —— 「全空 / 全满 / 正确」三种结果
        --    在屏幕上长得都像「它本来就这样」。上排喂**明文 65** 当对照,判据就变成
        --    「两排形状一不一样」,一眼读得出。顺带它还验证了我对钳制行为的理解本身对不对。
        local function MakeSegRow(yOff, tint)
            local row = {}
            for i = 1, 5 do
                local b = CreateFrame("StatusBar", nil, P.holder)
                b:SetSize(40, 10)
                b:SetPoint("TOPLEFT", P.holder, "BOTTOMLEFT", (i - 1) * 44, yOff)
                b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                b:SetStatusBarColor(unpack(tint))
                local bg = b:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(0, 0, 0, 0.6)
                -- 量程是**明文**,每段各占全程五分之一(疯狂 0..100 ⇒ 每段 20)
                b:SetMinMaxValues((i - 1) * 20, i * 20)
                row[i] = b
            end
            return row
        end
        P.segPlain  = MakeSegRow(-80, { 0.4, 0.8, 1 })   -- 明文对照(蓝)
        P.segSecret = MakeSegRow(-94, { 1, 0.5, 0 })     -- 待验(橙)
    end
    probe("FontString:SetText(secret HP)", function()
        P.fs:SetText(UnitHealth("player"))
        return "set-ok (look at the text on screen)"
    end)
    probe("FontString:GetText() readback", function() return P.fs:GetText() end)
    probe("StatusBar:SetValue(secret pwr)", function()
        P.bar:SetValue(UnitPower("player"))
        return "set-ok (look at the bar on screen)"
    end)
    probe("StatusBar:GetValue() readback", function() return P.bar:GetValue() end)
    if sid then
        P.iconTex:SetTexture(C_Spell.GetSpellTexture(sid))
        probe("Cooldown:SetCooldown(secret)", function()
            local cd = C_Spell.GetSpellCooldown(sid)
            P.cd:SetCooldown(cd.startTime, cd.duration)
            return "set-ok (看屏幕那个图标转不转圈)"
        end)
    end

    -- 分段资源条。⚠ 结论只能从**屏幕**读:GetValue 回读的是 secret,打印出来永远是 SECRET,
    -- 那一行只证明 SetValue 没报错,不证明它画对了(跟主条那两行同一个道理)。
    probe("段条 上排:明文 65(对照)", function()
        for i = 1, 5 do P.segPlain[i]:SetValue(65) end
        return "set-ok(该看到:前 3 段满 / 第 4 段 1/4 / 第 5 段空)"
    end)
    probe("段条 下排:secret 当前资源", function()
        local v = UnitPower("player")
        for i = 1, 5 do P.segSecret[i]:SetValue(v) end
        return "set-ok(看屏幕:形状该跟上排是同一个套路)"
    end)

    -- 🔴 下排必须**持续刷新**,否则这组探针根本得不出结论:/dp 是一次快照,而
    -- 「下排全空」既可能是「资源真的是 0」(暗牧脱战就是 0)也可能是「钳制坏了」——
    -- **静态一帧里这两个长得一模一样**。唯一能把它们分开的判据是那条老规矩:
    -- 别验「画出来了」,验「它跟着资源涨落而变」。
    -- 60 秒后自停:探针不该留常驻开销(而且到时候该看的已经看完了)。
    P.segUntil = GetTime() + 60
    P.segTicker = P.segTicker or CreateFrame("Frame")
    P.segTicker:SetScript("OnUpdate", function(self)
        if GetTime() > (P.segUntil or 0) then
            self:SetScript("OnUpdate", nil)
            return
        end
        local v = UnitPower("player")
        for i = 1, 5 do P.segSecret[i]:SetValue(v) end
    end)
    out[#out + 1] = "|cff88ff88段条下排会跟着资源实时变 60 秒 —— 打两下看它涨落|r"

    out[#out + 1] = "|cffffff00--- 多职业资源条(主资源 / 次要资源 / 分段) ---|r"

    -- 契约上 UnitPowerType **零 secret 标注** ⇒ 连官方配色都该是明文。
    -- 真是的话:「换专精自动跟上」不用查专精 ID 表,配色也不用自己配二十来种。
    probe("UnitPowerType(player) 主资源", function()
        local pt, token = UnitPowerType("player")
        return string.format("%s (%s)", tostring(pt), tostring(token))
    end)
    probe("-> 官方配色 rgb", function()
        local _, _, r, g, b = UnitPowerType("player")
        return string.format("%s / %s / %s", tostring(r), tostring(g), tostring(b))
    end)
    probe("UnitPower(player,nil,true) 未缩放", function()
        return UnitPower("player", nil, true)
    end)

    -- ⚠ UnitPowerDisplayMod **不吃 unit**(契约里只有一个 powerType 参数)⇒ 在暗牧身上
    -- 也问得出毁灭术碎片的除数。毁灭术「每颗豆带进度」的本质就是:碎片值是 0..50 而不是 0..5,
    -- 这个数就是那个除数。它若明文,分段的量程边界就是**纯明文算术**,一次都不碰 secret。
    for _, n in ipairs({ "SoulShards", "HolyPower", "ComboPoints", "Chi", "ArcaneCharges", "Runes" }) do
        local pt = Enum.PowerType and Enum.PowerType[n]
        if pt then
            probe("DisplayMod(" .. n .. ")", function() return UnitPowerDisplayMod(pt) end)
        end
    end

    -- 遍历 PowerType 全集,**只报这个角色真有的**:Max 对「该单位没有的资源」返明文 0
    -- ⇒ 这一遍同时答出「本专精到底有哪些资源」,不用维护一张专精 ID 表。
    -- 全报的话是三十多行噪音,会把真东西冲掉。
    -- ⚠ mx 自己可能就是 secret ⇒ 比大小**之前**必须先问 issecretvalue,否则探针自己崩;
    --   而且那种情况要如实报一行(「判不了」跟「没有这资源」是两回事)。
    local kinds = {}
    for n, v in pairs(Enum.PowerType or {}) do
        if type(v) == "number" and v >= 0 then kinds[#kinds + 1] = { n, v } end
    end
    table.sort(kinds, function(a, b) return a[2] < b[2] end)
    for _, e in ipairs(kinds) do
        local n, pt = e[1], e[2]
        local okM, mx = pcall(UnitPowerMax, "player", pt)
        if okM and type(mx) == "number" then
            if issecretvalue and issecretvalue(mx) then
                probe("? " .. n .. " max=SECRET(有没有这资源判不了)", function() return mx end)
            elseif mx > 0 then
                probe("有 " .. n .. "  max", function() return mx end)
                probe("   " .. n .. "  cur", function() return UnitPower("player", pt) end)
                probe("   " .. n .. "  cur(未缩放)", function() return UnitPower("player", pt, true) end)
            end
        end
    end

    -- 资源配色。`UnitPowerType` 的 rgb 实测是 nil,所以颜色只能另找路 ——
    -- `PowerBarColor` 是全局表,key 就是 UnitPowerType 给的那个 token。
    -- ⚠ 这一组是**摸清有没有**,不是打算直接拿来用:官方色是给暴雪那种带厚金属边框 +
    -- 不透明底的框体调的,搬到一根裸条上会糊(疯狂条就是这么从官方 atlas 退回
    -- 素图 + 自选亮紫的,理由见 DodoCombatHUD 的 DEFAULTS.powerTexture)。
    if type(PowerBarColor) == "table" then
        local seen = 0
        for _, tk in ipairs({ "MANA", "RAGE", "FOCUS", "ENERGY", "COMBO_POINTS", "RUNES",
                              "RUNIC_POWER", "SOUL_SHARDS", "LUNAR_POWER", "HOLY_POWER",
                              "MAELSTROM", "CHI", "INSANITY", "ARCANE_CHARGES",
                              "FURY", "PAIN", "ESSENCE" }) do
            local c = PowerBarColor[tk]
            seen = seen + 1
            probe("PowerBarColor." .. tk, function()
                if type(c) ~= "table" then return "nil" end
                return string.format("r=%.2f g=%.2f b=%.2f%s",
                    c.r or -1, c.g or -1, c.b or -1,
                    c.atlas and (" atlas=" .. tostring(c.atlas)) or "")
            end)
        end
        -- 反空转:一个都没查等于这组探针没跑,而「没跑」跟「全是 nil」在输出里长得一样
        if seen == 0 then out[#out + 1] = "  |cffff5555(PowerBarColor 一个 token 都没查 = 探针空转)|r" end
    else
        out[#out + 1] = "  |cffff5555PowerBarColor 这张表不存在|r"
    end

    -- 8. Threshold cues for a self-drawn resource bar. Bar LENGTH needs no math
    -- (SetMinMaxValues + SetValue both take secrets), but "go red near overcap" needs a
    -- path from a secret NUMBER to a visual. The generated contract says both curve
    -- Evaluate methods are AllowedWhenUntainted = addons cannot feed them. Contract has
    -- been wrong once already (GetSpellCooldown), so measure it instead of quoting it.
    out[#out + 1] = "|cffffff00--- HUD 阈值提示可行性 ---|r"

    local okCC, curve = pcall(C_CurveUtil.CreateColorCurve)
    if okCC and curve then
        pcall(function()
            curve:AddPoint(0, CreateColor(0.2, 0.6, 1.0, 1))
            curve:AddPoint(100, CreateColor(1.0, 0.2, 0.1, 1))
        end)
        -- Plaintext x first. Without it, a failure on the secret row could just mean
        -- "my curve was built wrong" - which reads identical to "secrets are blocked".
        probe("Curve:Evaluate(明文 50) 负对照", function()
            return curve:Evaluate(50) ~= nil and "ok" or "nil"
        end)
        probe("Curve:Evaluate(secret 资源)", function()
            return curve:Evaluate(UnitPower("player")) ~= nil and "ok" or "nil"
        end)
        probe("curve:HasSecretValues()", function() return curve:HasSecretValues() end)
    end

    -- EvaluateColorFromBoolean IS AllowedWhenTainted - but an addon has to obtain a secret
    -- BOOLEAN first, and comparing a secret number is a hard error. So: which API hands
    -- one out? IsSpellUsable is the candidate that matters (execute-range cue).
    if sid then
        local okU, usable = pcall(C_Spell.IsSpellUsable, sid)
        out[#out + 1] = string.format("  %-34s %s", "IsSpellUsable 给的是不是 secret bool",
            tag(okU, usable))
        probe("EvalColorFromBoolean(那个返回值)", function()
            local u = C_Spell.IsSpellUsable(sid)
            return C_CurveUtil.EvaluateColorFromBoolean(u,
                CreateColor(1, 0, 0, 1), CreateColor(0, 1, 0, 1)) ~= nil and "ok" or "nil"
        end)
    end

    -- 血条的唯一闸门。资源条走通了**不替血条背书**:那次的量程是明文(UnitPowerMax=100),
    -- 而 UnitHealthMax 很可能是 secret ⇒ 血条走的是 SetMinMaxValues(0, secret),没测过。
    -- ⚠ 这几行要**选中一个目标**才有意义;没目标时 UnitHealthMax 返 nil,读起来像被封了。
    probe("UnitHealthMax(target)", function() return UnitHealthMax("target") end)
    probe("UnitHealthMax(player)", function() return UnitHealthMax("player") end)
    if UnitExists("target") then
        probe("SetMinMaxValues(0, secret 血上限)", function()
            P.probeBar:SetMinMaxValues(0, UnitHealthMax("target"))
            return "set-ok"
        end)
        -- 回读:set-ok 只说明「调用没被拒」。最阴的失败是**默默不接受**(当成 0)——
        -- 那样条会恒满或恒空,零报错。回读拿到 SECRET 才说明它真收下了那个值。
        probe("-> GetMinMaxValues() 回读上限", function()
            local _, hi = P.probeBar:GetMinMaxValues()
            return hi
        end)
    else
        out[#out + 1] = "  |cffff8800(没选目标 —— 血条那几行跳过了,选个怪再跑一次)|r"
    end

    -- Two more secret-eating setters off the whitelist. Both clamp to 0..1 and we feed a
    -- 0..100 resource, so the SCREEN tells you nothing here - the only question this row
    -- answers is "does the call go through with a secret at all".
    probe("StatusBar:SetStatusBarDesaturation", function()
        P.bar:SetStatusBarDesaturation(UnitPower("player"))
        return "set-ok"
    end)
    probe("Texture:SetRadialProgressBarPercent", function()
        P.iconTex:SetRadialProgressBarPercent(UnitPower("player"))
        return "set-ok"
    end)

    -- ===== B. 报告(容器本体见文件上方 EnsureAuraProbe)=====
    out[#out + 1] = "|cffffff00--- B. AuraContainer + SetUnit(\"target\") ---|r"
    out[#out + 1] = string.format("  被筛的 DoT id=%d 名字=%s |cff888888(名字不对就 /dp dot <id>)|r",
        P.dotID, tostring(sname(P.dotID)))
    if not EnsureAuraProbe() then
        out[#out + 1] = "  |cffff3333建不起来: " .. tostring(P.auraErr) .. "|r"
    else
        -- 🔴 「数出显示着几个」办不到:`button:IsShown()` 返回 **secret boolean**,一做布尔测试
        -- 就是 "attempt to perform boolean test on a secret boolean value"(2026-08-15 实测,
        -- 第一版就是这么炸的,还把它后面的 A / C 两组一起带没了)。
        -- 合理 —— 可见性本身就泄露「这个光环在不在」。⇒ 本组的判据**只能是眼睛看屏幕**,
        -- 跟「挡的是读了去算,不挡画给人看」是同一件事的两面。
        -- 池大小是明文,但它只说「暴雪替这一组备过几个按钮」,不说现在显示几个。
        pcall(function()
            P.auraAny:UpdateAllAuras(); P.auraAll:UpdateAllAuras(); P.auraOne:UpdateAllAuras()
        end)
        out[#out + 1] = string.format("  1 任何 harmful       按钮池 %d", #P.auraAny.dpButtons)
        out[#out + 1] = string.format("  2 我上的全部         按钮池 %d", #P.auraAll.dpButtons)
        out[#out + 1] = string.format("  3 只要这一个         按钮池 %d", #P.auraOne.dpButtons)
        probe("button:IsShown() 的类型", function()
            local b = P.auraAny.dpButtons[1]
            return b and b:IsShown()
        end)
        out[#out + 1] = "  |cffffff00判据在屏幕上(中上三行图标),不在这几个数字里:|r"
        out[#out + 1] = "  |cffffff00  2 有 3 个、3 只有 1 个(吸血鬼之触) = includeSpellIDs 生效|r"
        out[#out + 1] = "  |cffffff00  三行都空 = 容器绑 \"target\" 不通 / 1 有而 2 空 = 过滤串的问题|r"
        out[#out + 1] = "  |cff888888顺带看图标上转不转圈 —— 那是我们自己画不出来的那样东西|r"
    end

    -- ===== B2. DoT 染色(名条按我的 DoT 变色)=====
    -- 机制不是「读出来再上色」,是**让暴雪的容器替你开关一张你自己的贴图**:
    -- 贴图 parent = aura button ⇒ 跟着按钮那个 secret Shown 显隐;SetPoint 指向外部血条。
    -- 在产先例 = PlateTweaks 1.5.0(`Tints.lua:983` `host:CreateTexture` + `AnchorToFill(tex, healthBar)`)。
    -- ⚠ 本组只量 API 存在性;**颜色对不对只能看屏幕 ⇒ 跑 `/dp tint`**。
    out[#out + 1] = "|cffffff00--- B2. DoT 染色可行性 ---|r"
    -- ① 最便宜的一问,而且可能让整套体操作废:这三个 DoT 的光环 secrecy 档位。
    for _, id in ipairs({ 589, 34914, 335467 }) do
        probe(string.format("AuraSecrecy %d %s", id, tostring(sname(id))), function()
            return C_Secrets.GetSpellAuraSecrecy(id)
        end)
    end
    out[#out + 1] = "  |cff888888NeverSecret ⇒ 明文可读、随便算(容器整套不需要);ContextuallySecret ⇒ 必须走容器|r"
    -- ② AddAuraSlot 池 **1** 个 frame,AddAuraGroup 池 **10** 个(暴雪硬编码
    --    `CustomAuraContainerConstants.FrameCreationBatchSize = 10`,注释写明是**故意**设这么高
    --    来掩盖光环数量)。⇒ 单法术判定走 slot 便宜一个数量级。
    -- 🔴 必须问**真的容器对象、在真的用它那一刻**:`Blizzard_AuraContainer` 加载得晚,
    --    在 ADDON_LOADED 时探测会失败并缓存成「不可用」⇒ 整个 session 静默走 10 帧路径
    --    而功能看着是开着的(PlateTweaks 作者栽过,写在它 SlotsAvailable 的注释里)。
    probe("AddAuraSlot 存在?", function()
        return P.auraOne and type(P.auraOne.AddAuraSlot) == "function"
    end)
    probe("SetAuraSlotCandidateFilters 存在?", function()
        return P.auraOne and type(P.auraOne.SetAuraSlotCandidateFilters) == "function"
    end)
    -- ③ 「野外无拾取怪 = 灰」那条走普通 Lua 分支 ⇒ 它必须是明文才行。
    probe("UnitIsTapDenied(target)", function() return UnitIsTapDenied("target") end)

    -- ===== A. C_CooldownViewer 数据集:暴雪自己会不会追「我打在目标身上的光环」 =====
    -- 实现侧证据说会(CooldownViewerItemData.lua:1 `scanUnits = {"player","target"}`;:17
    -- 要求 `auraData.sourceUnit == "player"`;:1094 `return self:GetAuraDataUnit() == "target"`)。
    -- 这里量的是**那两个 DoT 在不在它的数据表里** —— 不在的话上面那条实现证据对我们没用。
    -- ⚠ 每行末尾的「N 项」是口径验证:全 0 = 我枚举方式错了,不是「暴雪没数据」。
    out[#out + 1] = "|cffffff00--- A. C_CooldownViewer 数据集 ---|r"
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet) then
        out[#out + 1] = "  |cffff3333C_CooldownViewer 不存在|r"
    else
        local nonSelf = {}
        for cname, cval in pairs(Enum.CooldownViewerCategory or {}) do
            local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cval, true)
            if not ok or type(ids) ~= "table" then
                out[#out + 1] = string.format("  %-24s |cffff3333查不到|r", cname)
            else
                for _, id in ipairs(ids) do
                    local ok2, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
                    if ok2 and info and info.hasAura and not info.selfAura then
                        -- 分类是这里唯一还缺的那个字段:它决定这几个 DoT 能不能被单独摆位置
                        -- (布局 blob 里没有 x/y,分开摆只能走分类)。
                        nonSelf[#nonSelf + 1] = string.format("    %s  spellID=%s  分类=%s  cdID=%d",
                            tostring(sname(info.spellID) or "?"), tostring(info.spellID), cname, id)
                    end
                end
                -- 只报计数,不再把整个分类的法术名串出来 —— 那一串会把后面的结论挤出聊天框。
                -- 计数仍然是口径验证:全 0 = 我枚举方式错了,不是「暴雪没数据」。
                out[#out + 1] = string.format("  %-26s %d 项", cname, #ids)
            end
        end
        out[#out + 1] = "  |cffffff00hasAura 且 NOT selfAura(= 追的是别人身上的光环):|r"
        if #nonSelf == 0 then
            out[#out + 1] = "    |cff888888一个都没有|r"
        else
            for _, l in ipairs(nonSelf) do out[#out + 1] = l end
        end
    end

    -- ===== C. 斩杀技的 usable 会不会随目标血量翻面 =====
    -- 验法:对**满血**目标跑一次、对**残血**目标再跑一次,只比这一行。翻面 = 斩杀线明文可读,
    -- HUD 那条 20% 线就能从「一根静态刻度」升级成「真的会闪」。
    out[#out + 1] = "|cffffff00--- C. 斩杀技 usable 翻面 ---|r"
    out[#out + 1] = string.format("  斩杀技 id=%d 名字=%s |cff888888(名字不对就 /dp exec <id>)|r",
        P.execID, tostring(sname(P.execID)))
    probe("IsSpellUsable(斩杀技)", function() return C_Spell.IsSpellUsable(P.execID) end)
    probe("目标存在", function() return UnitExists("target") end)

    for _, line in ipairs(out) do print(line) end
    P.lastOut = StripColors(table.concat(out, "\n"))
    -- 自动落盘:整跑一次的结果进日志,不用记额外命令(真正写盘仍要 /reload,见 LogPush 上面那段)
    LogPush("dp", "---- /dp run (phase=" .. tostring(phase) .. ") ----")
    for _, line in ipairs(out) do LogPush("dp", line) end
    say("done.  |cffffff00/dp copy|r 弹出可复制的窗口;结果也已进落盘日志(|cffffff00/reload|r 后写入文件)")
end

-- Silent by default: this addon ships in the monorepo and syncs to every machine,
-- so it must never print anything unless explicitly asked. /dp arm = one-shot combat run.
-- 位置记录仪的三个入口在本文件下面才定义(它们要用 P 上的状态)。这里先声明成
-- local,否则下面那个 OnEvent 闭包**按词法作用域根本看不见它们** —— 它会去找同名
-- 全局,拿到 nil,然后在"reload 续命"那条路上崩,而那条路平时不走、不容易发现。
local PosStart, PosStop, PosSample

P:RegisterEvent("PLAYER_ENTERING_WORLD")
P:RegisterEvent("PLAYER_REGEN_DISABLED")
P:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
-- The container registers UNIT_AURA for its own unit token but NOT PLAYER_TARGET_CHANGED,
-- so on a target swap it keeps showing the previous target's auras until the new target's
-- next aura event. Blizzard exposes UpdateAllAuras for exactly this ("e.g. target changes"
-- -- AuraContainerSharedMixin). Doing it here also puts that fix under test.
P:RegisterEvent("PLAYER_TARGET_CHANGED")

P:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        say("ready (silent).  /dp = run now   |   /dp arm = run once in next combat")

        -- 自证:每次加载都往落盘日志里写一行。这样"文件里没有这次的东西"就只可能是
        -- **没 /reload**,不会跟"插件压根没加载"混在一起 —— 而那两种从外面看一模一样。
        -- (实测 2026-08-16:SavedVariables 目录里当时根本没有 DodoProbe.lua,
        --  落盘通道写在代码里、却从没真产出过一次文件。)
        if not P.bootLogged then
            P.bootLogged = true
            local _, build = "", "?"
            do local ok, _, b = pcall(GetBuildInfo); if ok and b then build = b end end
            LogPush("boot", "DodoProbe loaded, build " .. tostring(build))
        end

        -- 位置记录跨 /reload 续命:不然"跑完必须 reload 才落盘"和"reload 就把记录停了"
        -- 直接打架,他每 reload 一次就得记着重开一次。
        if DodoProbeDB and DodoProbeDB.posOn then
            C_Timer.After(2, function()
                if DodoProbeDB and DodoProbeDB.posOn and not P.posTicker then
                    PosStart()
                    say("|cffffff00位置记录仍在进行|r(reload 续命)。/dp pos 关。")
                end
            end)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Stay armed until a sample actually lands IN combat. A flat 3s timer can fire
        -- after a short fight already ended, which stamps a "COMBAT" header on an
        -- out-of-combat sample: a run that reports success while the condition under
        -- test was never present. Verify at fire time, re-arm otherwise.
        if P.armed then
            C_Timer.After(3, function()
                if not P.armed then return end
                if InCombatLockdown() then
                    P.armed = false
                    P:Run("COMBAT")
                else
                    say("that fight ended before the 3s mark - still armed, pull something tankier.")
                end
            end)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if P.auraBuilt then
            pcall(function()
                P.auraAny:UpdateAllAuras(); P.auraAll:UpdateAllAuras(); P.auraOne:UpdateAllAuras()
            end)
        end
    elseif event == "UNIT_AURA" then
        -- ⚠ 只取 unit,**绝不碰第二个参数**(受限时那个 updateInfo 是 secret)。
        local unit = ...
        local L = P.lat
        if L and L.armed and L.t0 and type(unit) == "string" then
            if unit == "target" or unit:find("^nameplate") then
                local dt = Now() - L.t0
                if dt <= LAT_WINDOW then
                    L.rows[#L.rows + 1] = string.format("  t=%.3f  UNIT_AURA  %s", dt, unit)
                    LatFlash()
                end
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        local L = P.lat
        if unit == "player" and L and L.armed and not L.t0 and LAT_SPELLS[spellID] then
            L.t0, L.spell = Now(), spellID
            -- 目标那个 nameplate 的 token **在这一刻**就取下来。上一版是「记最后一个收到
            -- UNIT_AURA 的 nameplate」,而周围的怪一直在刷事件 ⇒ 最后留下的是隔壁那只,
            -- 于是容器状态那三行查了个不相干的单位,还看着挺像回事。
            local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
                and C_NamePlate.GetNamePlateForUnit("target")
            L.plateN = plate and plate.namePlateUnitToken
                and plate.namePlateUnitToken:match("^nameplate(%d+)") or nil
            L.rows = { string.format("  t=0.000  施法成功  %s (%s)%s",
                tostring(sname(spellID)), tostring(spellID),
                L.plateN and ("   目标 = nameplate" .. L.plateN) or "   |cffff8800目标没有名条|r") }
            C_Timer.After(LAT_WINDOW, LatReport)
        end
        if unit == "player" and P.watchCast then
            P.watchCast = false
            say("own cast spellID -> " .. tag(true, spellID) .. "   (is my own cast readable?)")
        end
    end
end)

-- ===========================================================================
-- 📍 位置记录仪 (0.14)  —— 玩家坐标到底给不给值,以及给的话长什么样
--
-- 契约层已经查清(build 69214 / 12.1.0):UnitPosition / GetPlayerFacing /
-- C_Map.GetPlayerMapPosition / GetBestMapForUnit **一个 secret 标注都没有**。
-- 但契约用 nilability 表达"副本里不给",而 UnitPosition 那条**压根没建模副本门**
-- ⇒ 契约在"给不给值"上是沉默的,不是在说"能"。只有实测能定。
--
-- 每条样本照实记三态:真值 / nil / SECRET / ERR —— 绝不对 secret 做任何运算。
-- 每条都自带 map + 战斗标志:一条样本必须自己说得清它是在哪儿、什么状态下采的,
-- 否则"副本里 nil"跟"这台机器上它本来就 nil"长得一模一样。
--
-- 🔴 负对照是**免费**的:先在副本外面走两步,那几行就是基线。没有基线,
--    副本里的 nil 什么都证明不了。
-- ===========================================================================

local POS_MAX  = 4000
local POS_TICK = 0.4     -- 秒
local POS_MOVE = 0.25    -- 码;没动就不记,免得站着发呆刷满 4000 条

-- 一个值转成一格。永远不碰 secret,永远不 tostring 它。
local function cell(ok, v)
    if not ok then return "ERR" end
    if v == nil then return "nil" end
    if issecretvalue and issecretvalue(v) then return "SECRET" end
    -- 字符串照实打出来(到这一行它已经确定不是 secret)。原来这儿一律返回 "T:string",
    -- 于是 class 探针的 name / token 两格全是 "T:string" —— 一个探针把「被测对象是谁」
    -- 打成类型名,正是那条「采样探针必须报出这次测的是谁」要挡的坑。截断防止刷屏。
    if type(v) == "string" then
        return (#v > 24) and (v:sub(1, 24) .. "…") or v
    end
    -- 布尔也照实打。上一版只修了字符串,于是 player= / atk= 两格全是 "T:boolean" ——
    -- 「这是敌人还是队友」这个最基本的身份只能靠 GUID 是不是 secret 去**推**,而推来的身份
    -- 正是那条铁律禁止的东西。同一个坑修了两次,第二次才修全。
    if type(v) == "boolean" then return v and "true" or "false" end
    if type(v) ~= "number" then return "T:" .. type(v) end
    return string.format("%.4f", v)
end

-- 能拿来算的那个数,拿不到就 nil。给"动没动"用,别的地方一概用 cell()。
local function num(ok, v)
    if not ok or v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    if type(v) ~= "number" then return nil end
    return v
end

local function PosPush(line)
    DodoProbeDB = DodoProbeDB or {}
    if type(DodoProbeDB.pos) ~= "table" then DodoProbeDB.pos = {} end
    local t = DodoProbeDB.pos
    t[#t + 1] = line
    while #t > POS_MAX do table.remove(t, 1) end
end

-- 一次采样。kind = "W"(走动) / "M:<label>"(手动打点) / "S"(开始)
function PosSample(kind)
    local okP, x, y, z, wmap = pcall(UnitPosition, "player")
    local okF, face = pcall(GetPlayerFacing)

    local uiMap
    do
        local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
        uiMap = ok and m or nil
    end

    -- 归一化坐标要过 Vector2DMixin,而且 uiMap 拿不到时压根不能调。
    local nx, ny = "n/a", "n/a"
    if uiMap and not (issecretvalue and issecretvalue(uiMap)) then
        local ok, v = pcall(C_Map.GetPlayerMapPosition, uiMap, "player")
        if ok and v then
            local ok2, a, b = pcall(v.GetXY, v)
            nx, ny = cell(ok2, a), cell(ok2, b)
        else
            nx, ny = cell(ok, v == nil and nil or v), "-"
        end
    end

    -- boss 的坐标要是也给,房间的锚点就白捡了 —— 那比硬编码四个角强得多,
    -- 因为它换个副本还成立。target 一并量,boss1 不存在时它常常就是那只。
    local okB, bx, by = pcall(UnitPosition, "boss1")
    local okT, tx, ty = pcall(UnitPosition, "target")

    local zone, itype, iid = "?", "?", "?"
    do
        local ok, n, t2, _, _, _, _, _, id = pcall(GetInstanceInfo)
        if ok then zone, itype, iid = tostring(n), tostring(t2), tostring(id) end
    end

    local okC, inC = pcall(InCombatLockdown)

    PosPush(string.format(
        "%s t=%.2f | x=%s y=%s z=%s wmap=%s face=%s | ui=%s nx=%s ny=%s | boss=%s,%s tgt=%s,%s | c=%s | %s/%s/%s",
        kind, (pcall(GetTime) and GetTime() or 0) - (P.posT0 or 0),
        cell(okP, x), cell(okP, y), cell(okP, z), cell(okP, wmap), cell(okF, face),
        cell(true, uiMap), nx, ny,
        cell(okB, bx), cell(okB, by), cell(okT, tx), cell(okT, ty),
        (okC and (inC and "1" or "0")) or "ERR",
        zone, itype, iid))

    return num(okP, x), num(okP, y)
end

function PosStop()
    if P.posTicker then P.posTicker:Cancel(); P.posTicker = nil end
    DodoProbeDB = DodoProbeDB or {}
    DodoProbeDB.posOn = false
end

-- 🔴 采样必须 pcall,而且**失败要落盘**。
-- 一个在 ticker 里抛出来的异常会让记录仪当场无声停摆 —— 而"文件里只有前 20 条"
-- 跟"他走了 20 步就不走了"从外面看一模一样。宁可留一行 ERR! 说明死在哪。
-- 触发这条的最可能原因:某个值今天不是 secret、下个补丁变成 secret,
-- 而 cell() 之外还有哪儿动了它。
local function PosSafe(kind)
    local ok, err = pcall(PosSample, kind)
    if ok then return true end
    PosPush("ERR! 采样抛异常,记录停止 —— " .. tostring(err))
    PosStop()
    say("|cffff3333位置记录崩了并已停止|r,原因已写进落盘记录。/reload 后把文件给我。")
    return false
end

function PosStart()
    PosStop()
    DodoProbeDB = DodoProbeDB or {}
    DodoProbeDB.posOn = true
    P.posT0 = (pcall(GetTime) and GetTime()) or 0
    P.posLastX, P.posLastY = nil, nil

    PosSafe("S")
    P.posTicker = C_Timer.NewTicker(POS_TICK, function()
        local x, y = nil, nil
        do
            local ok, a, b = pcall(UnitPosition, "player")
            x, y = num(ok, a), num(ok, b)
        end
        -- 读不到就照记 —— "读不到"正是我们来量的那件事,别把它过滤掉。
        if x and y and P.posLastX then
            local dx, dy = x - P.posLastX, y - P.posLastY
            if (dx * dx + dy * dy) < (POS_MOVE * POS_MOVE) then return end
        end
        P.posLastX, P.posLastY = x, y
        if not PosSafe("W") then return end
    end)
end

-- ===== /dp class:战场里到底能不能拿到敌对玩家的职业色 =====
-- 起因(2026-08-17):DodoNameplate 在战场里所有敌对玩家血条都是红的。实测 `/dnp test` 回
-- `class: SECRET`,契约对上了 —— `UnitClassBase` 标着 `SecretWhenUnitIdentityRestricted`,
-- 战场里返回 secret ⇒ ClassColor() 拿不到值,回落成敌对红。
--
-- 被测的线索是 **`UnitClassFromGUID`**。契约上它 `SecretArguments = "AllowedWhenTainted"`
-- (⇒ 允许插件把一个 secret 的 GUID 递进去,而 UnitGUID 在受限内容里正是 secret),
-- 而三个返回值里**只有本地化 `className` 带 `ConditionalSecret`**,`classFilename`(token)
-- 和 `classID` 都没标。⚠ 第一次提取标注时我把 `ConditionalSecret` 整个漏了,读起来就是
-- 「这函数完全没限制」—— 逐字重读才抓出来。
--
-- 🔴 但契约只对「是不是 secret」权威,对「给不给值」不权威 —— 这条目自己就写着
--    `MayReturnNothing = true`。前科在案:位置那四个 API 契约上零 secret 标注(读起来完全可用),
--    真机在副本里 x/y/z 全 `nil`。所以这里**逐返回值记三态**(明文 / SECRET / nil / ERR);
--    记成一个「能用 / 不能用」等于没测。
--
-- 🔑 交付物不是「token 是不是明文」,是「**能不能拿到 r,g,b**」。token 明文但查不出颜色完全可能,
--    所以最后一格直接去查 RAID_CLASS_COLORS / C_ClassColor —— 查出数字才算这条路通。
local CLASS_PLATES = 10   -- target 之外再扫 nameplate1..N;战场里站着不动就能一次收一批

-- 借用路那一格(2026-08-17 加):**暴雪自己那根条的颜色**。
-- 他们的 CompactUnitFrame_UpdateHealthColor 是 untainted 代码,`UnitClass` + `RAID_CLASS_COLORS`
-- 直接查明文,而 NamePlateEnemyFrameOptions 的 useClassColors = true ⇒ 战场里实测是彩的
-- ⇒ **职业色已经画在屏幕上了**,只剩一个问题:这个 getter 会不会把那三个数交给插件。
--
-- 🔴 必须连 uf 的 alpha 一起记。生产状态下 DodoNameplate 对它 `SetAlpha(0)` ——
--    「暴雪条可见时读得到」跟「被我们盖掉之后还读得到」是**两个不同的问题**,
--    只测前者会得出一个在生产里根本不成立的结论。⇒ group 6 关着跑一次、开着再跑一次。
-- 🔴 字段名也要报出来:猜错字段名拿到的 nil,跟「颜色读不出来」长得一模一样。
local function BlizzBarCell(unit)
    local okP, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not okP or not plate then return "无板", "-", "-" end
    local okF, forbidden = pcall(plate.IsForbidden, plate)
    if okF and forbidden == true then return "forbidden", "-", "-" end
    local uf = plate.UnitFrame
    if not uf then return "无UnitFrame", "-", "-" end

    local alpha = "ERR"
    do
        local ok, a = pcall(uf.GetAlpha, uf)
        if ok and type(a) == "number" then alpha = string.format("%.2f", a) end
    end

    local field, bar
    for _, k in ipairs({ "healthBar", "HealthBar", "health" }) do
        local ok, v = pcall(function() return uf[k] end)
        if ok and type(v) == "table" and v.GetStatusBarColor then field, bar = k, v; break end
    end
    if not bar then return "没找到healthBar", alpha, "-" end

    local ok, r, g, b = pcall(bar.GetStatusBarColor, bar)
    if not ok then return field, alpha, "ERR" end
    -- 守卫顺序:secret 检查在 nil 比较之前。
    if issecretvalue and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b)) then
        return field, alpha, "SECRET"
    end
    if r == nil then return field, alpha, "nil" end
    return field, alpha, string.format("%.2f/%.2f/%.2f", r, g, b)
end

-- 一个单位一行。永不对 secret 做比较 / 索引 / tostring。
local function ClassLine(unit)
    local okX, exists = pcall(UnitExists, unit)
    if not okX or exists ~= true then return nil end

    -- 身份在采样这一刻钉死。量错对象时拿到的是一份可信、干净、而且无关的数据 —— 那种最难发现。
    local okN, uname = pcall(UnitName, unit)
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    local okA, canAtk = pcall(UnitCanAttack, "player", unit)

    -- 现有的那条路(已知被墙),留着当同一行里的对照:它 SECRET 而新路明文,才叫有进展。
    local okB, base = pcall(UnitClassBase, unit)

    -- 被测的那一跳。GUID 本身可能是 secret,契约说可以递进去 —— 那正是要验的事。
    local okG, guid = pcall(UnitGUID, unit)
    local okC, cName, cFile, cID = false, nil, nil, nil
    if okG then
        okC, cName, cFile, cID = pcall(UnitClassFromGUID, guid)
    end

    -- 交付物那一格。⚠ 守卫顺序不能反:secret 检查必须在 nil 比较**之前**,
    -- 拿 secret 当表键是直接抛的。
    local col = "-"
    if okC and not (issecretvalue and issecretvalue(cFile)) and cFile ~= nil then
        local okR, c = pcall(function() return RAID_CLASS_COLORS and RAID_CLASS_COLORS[cFile] end)
        if not (okR and type(c) == "table" and c.r) then
            okR, c = pcall(function()
                return C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(cFile)
            end)
        end
        if okR and type(c) == "table" and type(c.r) == "number" then
            col = string.format("%.2f/%.2f/%.2f", c.r, c.g, c.b)
        else
            col = "查不到颜色"   -- token 有了却查不出色 = 这条路仍然不通,别读成通了
        end
    elseif okC then
        col = "n/a(token 不可用)"
    end

    local bField, bAlpha, bRGB = BlizzBarCell(unit)

    return string.format(
        "%-11s name=%-14s player=%-6s atk=%-6s | GUID=%-6s | ClassBase=%-8s || FromGUID: cFile=%-8s cID=%-6s => rgb=%s || BLIZZ[%s a=%s] rgb=%s",
        unit, cell(okN, uname), cell(okP, isPlayer), cell(okA, canAtk),
        cell(okG, guid), cell(okB, base),
        cell(okC, cFile), cell(okC, cID), col,
        bField, bAlpha, bRGB)
end

-- 跑一次:target + nameplate1..N,连同区域上下文一起落盘。
local function ClassRun()
    local zone, itype = "?", "?"
    do
        local ok, n, t = pcall(GetInstanceInfo)
        if ok then zone, itype = tostring(n), tostring(t) end
    end

    -- 🔴 负对照做成**可见的**,别靠谁记得:「战场里是 nil」跟「它本来就 nil」长得一模一样。
    --    记下每种区域类型采过几次,跑完当场报还缺哪一半。
    DodoProbeDB = DodoProbeDB or {}
    DodoProbeDB.classZones = DodoProbeDB.classZones or {}
    DodoProbeDB.classZones[itype] = (DodoProbeDB.classZones[itype] or 0) + 1

    local lines = { ("== class 探针 == 区域=%s 类型=%s"):format(zone, itype) }
    local units, n = { "target" }, 0
    for i = 1, CLASS_PLATES do units[#units + 1] = "nameplate" .. i end
    for _, unit in ipairs(units) do
        local line = ClassLine(unit)
        if line then lines[#lines + 1] = line; n = n + 1 end
    end
    if n == 0 then
        lines[#lines + 1] = "  一个单位都不在场 —— 选个目标、或者站到有名条的地方再跑"
    end

    for _, l in ipairs(lines) do LogPush("class", l) end
    P.lastOut = table.concat(lines, "\n")

    say(("class 探针:采到 %d 个单位,区域 %s(%s)"):format(n, zone, itype))
    local zs = {}
    for k, v in pairs(DodoProbeDB.classZones) do zs[#zs + 1] = ("%s×%d"):format(k, v) end
    table.sort(zs)
    say("  已采区域:" .. table.concat(zs, " "))
    local haveWorld = (DodoProbeDB.classZones["none"] or 0) > 0
    local havePvP = (DodoProbeDB.classZones["pvp"] or 0) > 0
        or (DodoProbeDB.classZones["arena"] or 0) > 0
    if haveWorld and havePvP then
        say("  |cff44ff44野外 + 战场两边都采到了|r —— /reload 后把文件给我")
    elseif havePvP then
        say("  |cffffaa00还缺野外对照|r:出去选个敌对玩家再跑一次,否则 nil 分不出是被墙还是本来就没有")
    else
        say("  |cffffaa00还缺战场里那一半|r:进战场选个敌对玩家再跑一次")
    end
    say("  |cffffff00结果只在 /reload 之后才写进文件|r,/dp copy 可当场复制")
end

-- ===== /dp macro:DodoGuanzhu(灌注顺位)开工前要量的六件事 =====
-- 🔴 **这个子命令有副作用**(建一个临时宏再删掉)⇒ 故意不进默认 /dp,只能手敲。
-- 无害化(canon「探针必须无害化」):① 只碰一个绝对不撞名的宏 ② 动手前先确认它不存在,
-- 撞了就中止(EditMacro 撞名会**重写玩家自己的宏**)③ 战斗中不跑(客户端 block 宏 API)
-- ④ 跑完必删,并且**换一种查询形状**核实删干净了 —— 别用删它那条 selector 去验它没了。
local MACRO_TMP = "DPzzTmpMacro"

-- 数 UTF-8 码位。不用 strlenutf8(不保证在),这个只依赖 string.byte。
local function utf8len(s)
    local n = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
end

-- 把条件串喂给**宏自己的求值器**。零副作用:它只求值,不施法。
-- 这是验「一行多组条件的 fallback」最直接的办法 —— 不用真按宏、不消耗 CD。
local function parse(cond)
    if type(SecureCmdOptionParse) ~= "function" then return "|cffff3333函数不存在|r" end
    local ok, action, target = pcall(SecureCmdOptionParse, cond)
    if not ok then return "|cffff3333ERROR|r " .. tostring(action) end
    if action == nil then return "|cff888888不成立(nil)|r" end
    return "|cff00ff00" .. tostring(action) .. "|r → @|cffffd100"
        .. tostring(target or "(宏默认目标)") .. "|r"
end

-- 残留清理。开头和结尾各调一次:开头防上一次跑到一半崩了留下的,结尾是正常收尾。
local function MacroTmpWipe()
    local idx = GetMacroIndexByName and GetMacroIndexByName(MACRO_TMP)
    if idx and idx > 0 then pcall(DeleteMacro, idx) end
end

local function MacroRun()
    local L = {}
    local function add(s) L[#L + 1] = s end
    local function row(k, v) add(string.format("  %-28s %s", k, v)) end

    add("|cff33ff99=== /dp macro · 灌注顺位插件 开工前置 ===|r")
    add(("  build %s   脱战/战斗 = %s"):format(
        (GetBuildInfo and select(4, GetBuildInfo())) or "?",
        InCombatLockdown() and "|cffff8800IN COMBAT|r" or "out of combat"))
    -- 🔴 结果必须自带环境标签。主城是**最宽松**的环境(不是 addon-restricted map),
    --    在这儿测出来的明文,在副本/团本里完全可能变 SECRET ⇒ 两个环境都要跑一次,
    --    没有标签的话两份结果混在一起就分不出谁是谁了。
    local okI, inInst, instType = pcall(IsInInstance)
    add(("  地图 = %s / %s   组队 = %s"):format(
        tostring(okI and instType or "?"),
        tostring((GetZoneText and GetZoneText()) or "?"),
        (IsInRaid and IsInRaid()) and "团队" or ((IsInGroup and IsInGroup()) and "小队" or "|cffffaa00单人|r")))

    -- ── ① 名字形态:写进宏的 @名字 到底长什么样 ────────────────────
    add("|cffffd100── ① 名字形态(决定宏里写什么)──|r")
    -- ⚠ 名字有可能是 secret ⇒ 一律走 tag() 分类,**绝不 tostring 它**(那会当场炸,
    --   而这插件全部的意义就是"全程 pcall 不炸")。
    local function nameCell(u)
        if not UnitExists(u) then return "|cff888888(没有这个单位)|r" end
        return ("Name=%s Full=%s Get(,true)=%s"):format(
            tag(pcall(UnitName, u)), tag(pcall(UnitFullName, u)), tag(pcall(GetUnitName, u, true)))
    end
    row("player", nameCell("player"))
    row("target", nameCell("target"))
    row("focus", nameCell("focus"))
    row("本服名(Normalized)", tostring(GetNormalizedRealmName and GetNormalizedRealmName()))

    -- ── ② 宏条件求值:全程零副作用,直接问宏自己的解析器 ──────────
    add("|cffffd100── ② 宏条件语义(SecureCmdOptionParse,不施法)──|r")
    local me   = UnitName("player")
    local full = (GetUnitName and GetUnitName("player", true)) or me
    local SPL  = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(10060)) or "能量灌注"

    -- 🔑 最值钱的一条:第一组是个**必然不存在**的名字,第二组是 player。
    -- 落到 player = 「一行多组条件会 fallback」这个整个设计的地基被坐实。
    row("fallback(假名→player)",
        parse("[@ZzNoSuchPlayerZz,help,nodead][@player] " .. SPL))
    row("自己短名可解析吗",  parse("[@" .. me .. ",help,nodead] " .. SPL))
    row("自己全名(带服)",    parse("[@" .. full .. ",help,nodead] " .. SPL))
    row("焦点组(要先设焦点)", parse("[@focus,help,nodead][@player] " .. SPL))

    -- 🔑 拿**当前目标**的名字当 @名字 —— 这条专门验「团队外的陌生人能不能进名单」。
    -- ⚠ 名字可能是 secret,而 secret 的 type 仍然是 string ⇒ 只判 type 会在拼接那一步炸,
    --   必须先问 issecretvalue。这也正是这一行要量的那件事本身。
    if UnitExists("target") and UnitIsPlayer("target") then
        local okT, tn = pcall(GetUnitName, "target", true)
        local isSec = okT and issecretvalue and issecretvalue(tn)
        if isSec then
            row("[@目标名字,help]", "|cffff8800目标名字是 SECRET ⇒ 写不进宏|r")
        elseif okT and type(tn) == "string" then
            row("[@目标名字,help]", parse("[@" .. tn .. ",help,nodead] " .. SPL))
            -- 裸的 + exists:区分「名字压根解析不成 unit」和「解析成了但 help 判假」。
            -- 裸的都不成立 ⇒ 是解析失败 ⇒ @名字 只在队伍/团队范围内有效。
            row("[@目标名字] 裸",     parse("[@" .. tn .. "] " .. SPL))
            row("[@目标名字,exists]", parse("[@" .. tn .. ",exists] " .. SPL))
            row("  (那个名字)", "|cff00ff00" .. tn .. "|r")
        else
            row("[@目标名字,help]", "|cff888888拿不到目标名字|r")
        end
    else
        row("[@目标名字,help]", "|cff888888SKIP:没选中玩家目标|r")
    end
    -- 无效条件怎么表现:侧证「宏条件里没有射程这一档」。ERROR 或不成立都说明它不认;
    -- ⚠ 若这行**成立**,说明我把射程判死是错的 —— 那这一条比其他五条都重要。
    row("[@player,inrange] ?", parse("[@player,inrange] " .. SPL))
    -- 🔴 上面那行**自己分不出**两种情况:(a) inrange 是真条件 (b) 未知条件被直接忽略。
    --    两种情况下它都成立 ⇒ 零分辨力。下面两行是负对照,noinrange 是决定性的那条:
    --    一个真条件不可能和它的反面同时为真 ⇒ 两个都成立 = 解析器在忽略未知条件。
    row("[@player,noinrange]",  parse("[@player,noinrange] " .. SPL))
    row("[@player,zzzgarbage]", parse("[@player,zzzgarbage] " .. SPL))
    add("      |cffffff00判读:后两行也成立 ⇒ 未知条件被忽略,inrange 不是真条件(射程结论不变)|r")
    row("[@player,nodead] 自己", parse("[@player,nodead] " .. SPL))

    -- 死人的 help 是真是假 —— 决定 nodead 能不能省(每人省 7 字节)。
    -- 找不到死人就如实报 skip:「没量到」和「量到了是假」必须分得开。
    local deadUnit
    for i = 1, 40 do
        local u = "raid" .. i
        if UnitExists(u) and UnitIsPlayer(u) and UnitIsDeadOrGhost(u) then deadUnit = u break end
    end
    if not deadUnit then
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) and UnitIsPlayer(u) and UnitIsDeadOrGhost(u) then deadUnit = u break end
        end
    end
    if deadUnit then
        local dn = GetUnitName(deadUnit, true)
        row("死人 [@x,help]",   parse("[@" .. dn .. ",help] " .. SPL))
        row("死人 [@x,help,nodead]", parse("[@" .. dn .. ",help,nodead] " .. SPL))
    else
        row("死人 help", "|cff888888SKIP:队里现在没有死人|r")
    end

    -- ── ③ 过滤判据是不是明文(录名单时要用)────────────────────
    add("|cffffd100── ③ 收录过滤用的判据(要明文才能算)──|r")
    local function tp(label, fn) row(label, tag(pcall(fn))) end
    tp("UnitIsPlayer(target)",   function() return UnitIsPlayer("target") end)
    tp("UnitCanAssist(p,target)",function() return UnitCanAssist("player", "target") end)
    tp("UnitIsDeadOrGhost(tgt)", function() return UnitIsDeadOrGhost("target") end)
    tp("UnitIsConnected(target)",function() return UnitIsConnected("target") end)
    tp("UnitName(target)",       function() return UnitName("target") end)
    tp("UnitClass 第2返(职业色)",function() return (select(2, UnitClass("target"))) end)
    tp("UnitInRange(target)",    function() return UnitInRange("target") end)  -- 预期 SECRET
    tp("PI 技能名(10060)",       function() return SPL end)

    -- ── ⑤ 射程专项:noinrange 判假 ⇒ inrange 疑似**真条件**,这组来定案 ────
    add("|cffffd100── ⑤ 射程(inrange 疑似真条件)──|r")
    -- 🔴 排掉最后一个替代解释:noinrange 判假也可能是「no+未知」走了另一条路,
    --    而不是 inrange 被识别。nozzzgarbage 成立 ⇒ no+未知一样被忽略 ⇒ 定案。
    row("[@player,nozzzgarbage]", parse("[@player,nozzzgarbage] " .. SPL))
    -- @target 是 **unit token 不是名字** ⇒ 对陌生人照样解析得到,
    -- 可以拿主城里的路人当尺子量 inrange 到底是多远。
    row("[@target,help]",      parse("[@target,help] " .. SPL))
    row("[@target,exists]",    parse("[@target,exists] " .. SPL))
    row("[@target,inrange]",   parse("[@target,inrange] " .. SPL))
    row("[@target,noinrange]", parse("[@target,noinrange] " .. SPL))
    -- 标尺:拿几个已知距离的判据交叉定位 inrange 到底对应多少码。
    tp("CheckInteractDist 1(28y)", function() return CheckInteractDistance("target", 1) end)
    tp("CheckInteractDist 2(11y)", function() return CheckInteractDistance("target", 2) end)
    tp("CheckInteractDist 3(10y)", function() return CheckInteractDistance("target", 3) end)
    tp("C_Spell.IsSpellInRange",   function() return C_Spell.IsSpellInRange(10060, "target") end)
    tp("IsSpellInRange(旧全局)",   function() return IsSpellInRange(SPL, "target") end)

    -- ── ④ 长度上限:字节还是字符(唯一有副作用的一段)──────────────
    add("|cffffd100── ④ 长度上限(决定名单能放几个人)──|r")
    if InCombatLockdown() then
        row("长度探针", "|cffff8800SKIP:战斗中,客户端 block 宏 API|r")
    elseif type(CreateMacro) ~= "function" then
        row("长度探针", "|cffff3333SKIP:没有 CreateMacro|r")
    else
        MacroTmpWipe()                       -- 防上一次跑到一半崩了留下的
        local before = GetNumMacros()
        local exist  = GetMacroIndexByName(MACRO_TMP)
        if exist and exist > 0 then
            row("长度探针", "|cffff3333中止:" .. MACRO_TMP .. " 竟然已存在,不覆盖|r")
        else
            local idx
            local okC = pcall(function() idx = CreateMacro(MACRO_TMP, 134400, "x", nil) end)
            if not okC or not idx or idx == 0 then
                row("长度探针", "|cffff3333建不出来(槽位满?)|r")
            else
                -- 300 个汉字 = 300 码位 / 900 字节 ⇒ 两种上限都会被它撞到。
                local okE, errE = pcall(EditMacro, idx, nil, nil, string.rep("中", 300))
                -- ⚠ 别用 GetMacroBody:暴雪自己的 Blizzard_MacroUI 全程用 GetMacroInfo 的
                --   第 3 个返回值,而 GetMacroBody 在 12.1 源码里一次都没出现 ⇒ 它可能是 nil,
                --   裸调会当场崩。type 检查兜住 secret / nil 两种,#got 才不会炸。
                local okB, _, _, body3 = pcall(GetMacroInfo, idx)
                local got = (okB and type(body3) == "string") and body3 or ""
                row("正文 300汉字→回读", ("%d 字节 / %d 码位 %s"):format(#got, utf8len(got),
                    okE and "" or ("|cffff3333EditMacro:" .. tostring(errE) .. "|r")))
                -- 实测基准(12.1.0 build 120100,美服 Illidan):写 300 汉字 → 回读
                -- 768 字节 / 256 码位 ⇒ **按码位截,不按字节** ⇒ 中文名不吃亏。
                -- ⚠ UI 输入框那边是 letters="255",跟 API 层的 256 差 1 ⇒ 生成时按 255 保守算。
                add("      |cffffff00基准:768字节/256码位 = 按码位截。对不上就是暴雪改了|r")
                -- 宏名 2 ASCII + 10 汉字 = 12 码位 / 32 字节,16 上限两种读法都会截。
                local okN = pcall(EditMacro, idx, "DP" .. string.rep("中", 10), nil, nil)
                local okG2, n2 = pcall((C_Macro and C_Macro.GetMacroName) or GetMacroInfo, idx)
                local gotN = (okG2 and type(n2) == "string") and n2 or ""
                row("宏名 2A+10汉→回读", ("%d 字节 / %d 码位 [%s]%s"):format(#gotN, utf8len(gotN),
                    tostring(gotN), okN and "" or " |cffff3333改名被拒|r"))
                -- 清理。⚠ 上一步改过名了 ⇒ 只能靠 idx 删,MacroTmpWipe 已经找不到它。
                pcall(DeleteMacro, idx)
                local after = GetNumMacros()
                row("清理", (before == after) and "|cff00ff00已删净(宏总数前后一致)|r"
                    or ("|cffff3333没删净! 前=" .. tostring(before) .. " 后=" .. tostring(after)
                        .. " —— 去宏界面手删那个 DP 开头的|r"))
            end
        end
        MacroTmpWipe()
    end
    local okS, used = pcall(GetNumMacros)      -- 这行在 if 外面 ⇒ 不能靠上面那个 type 检查兜
    row("宏槽位", okS and ("账号已用 " .. tostring(used) .. " / 120") or "|cff888888读不到|r")

    P.lastOut = StripColors(table.concat(L, "\n"))
    for _, s in ipairs(L) do print(s) end
    LogPush("macro", P.lastOut)
    ShowCopyBox(P.lastOut)
    say("已弹复制窗(Ctrl+A / Ctrl+C)。|cffffd100/reload|r 落盘,|cffffd100/dp copy|r 再开一次。")
end

SLASH_DODOPROBE1 = "/dp"
SLASH_DODOPROBE2 = "/dodoprobe"
SlashCmdList.DODOPROBE = function(msg)
    local cmd, arg = string.lower(msg or ""):match("^%s*(%a*)%s*(%d*)")
    arg = tonumber(arg)
    if cmd == "lat" then
        P.lat = P.lat or { rows = {} }
        P.lat.armed = not P.lat.armed
        P.lat.t0, P.lat.spell, P.lat.plateN = nil, nil, nil
        if P.lat.armed then
            -- 只在武装时注册:UNIT_AURA 在战斗中极频繁,常驻监听纯属白烧。
            P:RegisterEvent("UNIT_AURA")
            say("延迟探针已武装 —— |cffffff00选中目标,放「痛」/「吸血鬼之触」/「癫」其中一个|r。"
                .. "别的技能不会触发计时(上一版就是这么采到了触须猛击)。")
            say("屏幕上方会在每次 UNIT_AURA 到达时闪一个绿块 —— |cffffff00盯着它和名条图标谁先谁后|r。")
        else
            P:UnregisterEvent("UNIT_AURA")
            say("延迟探针关了。")
        end
    elseif cmd == "tint" then
        -- 判据**只能是眼睛**:按钮的 Shown 是 secret,数不出来也断言不了(见 B 组注释)。
        local errs = P.BuildTintRig()
        say("|cffffd100DoT 染色钻机|r —— 屏幕中央偏下那根条,选个怪往上招呼:")
        say("  无 DoT=|cff888888灰|r  只有痛=|cffff8c1a橙|r  只有触=|cffaa4dff紫|r  两个都有=|cff2680ff蓝|r")
        say(string.format("  规则走 %s / 嵌套容器 %s",
            P.tintUsedSlot and "|cff44ff44AddAuraSlot(池1)|r" or "|cffffaa00AddAuraGroup(池10)|r",
            P.tintNested and "|cff44ff44建起来了|r" or "|cffff3333没建起来|r"))
        if errs and #errs > 0 then
            for _, e in ipairs(errs) do say("  |cffff3333" .. e .. "|r") end
        end
        -- 三种读法必须分开,否则「条不变色」会被当成「这条路死了」直接写进结论:
        say("  |cff888888条一直灰 = 机制不通 / 只变一种色 = 层叠或嵌套出问题 / 四种全对 = 整套成立|r")
        say("  |cff888888先脱战在木桩上过一遍,再进副本复一遍 —— 副本才是它真正会死的地方|r")
        if DodoProbeLog then
            DodoProbeLog("tint", string.format("slot=%s nested=%s errs=%d",
                tostring(P.tintUsedSlot), tostring(P.tintNested), errs and #errs or -1))
            for _, e in ipairs(errs or {}) do DodoProbeLog("tint", e) end
        end

    elseif cmd == "pos" then
        if P.posTicker then
            PosStop()
            local n = (DodoProbeDB and type(DodoProbeDB.pos) == "table") and #DodoProbeDB.pos or 0
            say(("位置记录停。共 %d 条 —— |cffffff00还要 /reload 一次才真的写进文件|r"):format(n))
        else
            PosStart()
            say("位置记录 |cff44ff44ON|r,每 " .. POS_TICK .. "s 采一次(没动就不记)。")
            say("  |cffffff00先在副本外面走两步|r —— 那是负对照。没有它,副本里的 nil 什么都证明不了。")
            say("  站到一个标记上时敲 |cffffd100/dp mark cross|r(square / triangle / circle)打个点。")
            say("  完事 |cffffd100/dp pos|r 关,再 |cffffd100/reload|r 落盘。")
        end

    elseif cmd == "mark" then
        local label = (msg or ""):match("^%s*%a+%s+(%S+)")
        if not label then
            say("要带个名字:|cffffd100/dp mark cross|r")
        else
            -- 身份在**打点这一刻**钉死,不从采样流里事后推 —— 推出来的那个会被
            -- 周围的噪声覆盖成不相干的东西,而那几行读起来照样像回事。
            if not P.posTicker then PosStart() end
            PosSafe("M:" .. string.lower(label))
            say("打点 |cff44ff44" .. label .. "|r")
        end

    elseif cmd == "posclear" then
        DodoProbeDB = DodoProbeDB or {}
        DodoProbeDB.pos = {}
        say("位置记录已清空 —— |cffffff00还要 /reload 一次|r 才会从文件里消失。")

    elseif cmd == "class" then
        ClassRun()

    elseif cmd == "macro" then
        -- 有副作用(建一个临时宏再删),所以只走手敲,不进默认 /dp。
        MacroRun()

    elseif cmd == "log" then
        local n = (DodoProbeDB and type(DodoProbeDB.log) == "table") and #DodoProbeDB.log or 0
        say(("落盘日志 %d 条。|cffffff00得再 /reload 一次才会真的写进文件|r"):format(n))
        say("  文件:WTF\\Account\\<账号>\\SavedVariables\\DodoProbe.lua")
    elseif cmd == "clear" then
        DodoProbeDB = DodoProbeDB or {}
        DodoProbeDB.log = {}
        say("日志已清空 —— |cffffff00还要 /reload 一次|r 才会从文件里消失。")
    elseif cmd == "copy" then
        if P.lastOut then
            ShowCopyBox(P.lastOut)
        else
            say("nothing captured yet -- run /dp first.")
        end
    elseif cmd == "arm" then
        P.armed, P.watchCast = true, true
        say("armed. Pull a mob -- runs once 3s into combat, then disarms itself.")
    elseif cmd == "dot" and arg then
        P.dotID = arg
        if P.auraBuilt then
            pcall(function()
                P.auraOne:SetAuraGroupCandidateFilters("g", { includeSpellIDs = { [P.dotID] = true } })
            end)
        end
        say("dot id -> " .. P.dotID .. "  (" .. tostring(sname(P.dotID)) .. ")")
    elseif cmd == "exec" and arg then
        P.execID = arg
        say("exec id -> " .. P.execID .. "  (" .. tostring(sname(P.execID)) .. ")")
    elseif cmd == "aura" then
        if P.auraBuilt then
            P.auraShown = not P.auraShown
            pcall(function()
                P.auraAny:SetEnabled(P.auraShown)
                P.auraAll:SetEnabled(P.auraShown)
                P.auraOne:SetEnabled(P.auraShown)
            end)
            say("aura probe rows -> " .. (P.auraShown and "on" or "off"))
        else
            say("aura probe not built yet -- run /dp once out of combat first.")
        end
    else
        P.watchCast = true
        P:Run("MANUAL")
    end
end
