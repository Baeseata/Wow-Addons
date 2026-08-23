-- 离线跑 Boiling.lua 的探针,不进游戏。
--   lua tools/test_boiling.lua
--
-- 为什么值得写:这个探针的产物全是 string.format 拼出来的,而 %d 喂了个 string
-- 在 Lua 里是**运行时**才炸的。真机上它炸在事件处理里 = 整个探针静默死掉,
-- 而"没输出"和"没触发"从外面长得一模一样 —— 那就是白打一趟木桩。
--
-- 两个场景是一对 A/B:
--   A 全明文  = per-spell Aura=Never 的最好情况,验的是"读数拼得对不对"
--   B 全 secret/nil = 真机最坏情况,验的是"secret 安全层拦不拦得住"
-- ⚠ 只跑 A 的话,describe/isSecret 那一层一行都没被执行到 —— 那是零信息量的绿。

local SECRETS = setmetatable({}, { __mode = "k" })
local function mkSecret(v) SECRETS[v] = true; return v end

local out = {}
local realprint = print
_G.print = function(s) out[#out + 1] = tostring(s) end

_G.issecretvalue    = function(v) return SECRETS[v] == true end
local inCombat = true
local overlayed = false
_G.InCombatLockdown = function() return inCombat end
local specID, hasTalent = 250, true
_G.IsPlayerSpell           = function() return hasTalent end
_G.GetSpecialization       = function() return 1 end
_G.GetSpecializationInfo   = function() return specID end

local NOW = 1000.0
_G.GetTime = function() return NOW end
local timers = {}
local tickers = {}
_G.C_Timer = {
    After     = function(d, fn) timers[#timers + 1] = { d = d, fn = fn } end,
    NewTicker = function(d, fn)
        local t = { d = d, fn = fn, cancelled = false }
        function t:Cancel() self.cancelled = true end
        tickers[#tickers + 1] = t
        return t
    end,
}

-- 通用框体桩。
-- ⚠ 未知方法自动兜底成空函数是**宽容的默认值** —— 打错一个方法名会被静默吞掉。
-- 所以每兜底一次就记一笔,跑完全部列出来:名字里出现没见过的东西 = 有 typo。
local fired
local frames, autoStub = {}, {}
local levelSeq = 0
local initErrors = {}        -- initializeFrame 里抛出来的,收着,跑完统一断言

-- 🔴 几个方法**按真机签名严格校验**,不走宽容兜底。
-- 2026-08-23 实撞:`button:SetSize(SLOT, SLOT)` 里的 SLOT 是个被删掉的老常量 ⇒ 真机
-- `bad argument #1 to SetSize`,而桩把 SetSize 兜底成空函数 ⇒ 离线**全绿**。
-- 宽容的默认值会替 bug 遮丑 —— 这几个是最容易被喂 nil 的,所以专门收紧。
local function strictNum(name, ...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) ~= "number" then
            error(name .. " 第 " .. i .. " 个参数不是数字:" .. tostring(v), 3)
        end
    end
end
local function mkFrame(kind, name)
    local f = { __kind = kind, __name = name, __shown = false, events = {}, __fs = {}, __tex = {} }
    function f:Show() self.__shown = true end
    function f:Hide() self.__shown = false end
    function f:IsShown() return self.__shown end
    function f:SetScript(k, fn)
        if k == "OnEvent" then fired = fn; self.__onevent = fn end
        if k == "OnUpdate" then self.__onupdate = fn end
    end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:RegisterUnitEvent(e) self.events[e] = true end
    function f:UnregisterAllEvents() self.events = {} end
    function f:SetSize(w, h) strictNum("SetSize", w, h); self.__w, self.__h = w, h end
    function f:SetAlpha(a) strictNum("SetAlpha", a); self.__alpha = a end
    function f:SetCooldown(st, du) strictNum("SetCooldown", st, du); self.__cd = { st, du } end
    function f:SetVertexColor(r, g, b) strictNum("SetVertexColor", r, g, b) end
    function f:SetPoint(pt) if type(pt) ~= "string" then error("SetPoint 第 1 个参数不是字符串", 3) end end
    -- 真机上容器会**批量预建**按钮并对每个跑 initializeFrame。桩里也建一个 ——
    -- 否则那一整段(图标 / sink 贴图 / Cooldown / 字体 / SetSize)离线一行都不执行。
    function f:AddAuraGroup(gname, filter, opts)
        self.__groups = self.__groups or {}
        self.__groups[gname] = opts
        if type(opts) == "table" and type(opts.initializeFrame) == "function" then
            local btn = mkFrame("Button", tostring(gname) .. "_btn")
            btn.SetIcon = function(b, tex) b.__icon = tex end
            btn.SetDurationCooldown = function(b, cd) b.__durCd = cd end
            local ok, err = pcall(opts.initializeFrame, btn)
            if not ok then initErrors[#initErrors + 1] = tostring(err) end
            self.__button = btn
        end
    end
    -- 真机上 GetFrameLevel 永远返回数字;兜底成 nil 会让 `lvl + 20` 抛错,
    -- 而那个错发生在建排途中 ⇒ 后面的断言测的是"半个排"。
    levelSeq = levelSeq + 1
    f.__level = levelSeq
    function f:GetFrameLevel() return self.__level end
    function f:SetFrameLevel(v) self.__level = v end
    function f:CreateTexture()
        local t = mkFrame("texture")
        self.__tex[#self.__tex + 1] = t
        return t
    end
    function f:CreateFontString()
        local t = mkFrame("fs")
        function t:SetText(v) self.__text = v end
        self.__fs[#self.__fs + 1] = t
        return t
    end
    setmetatable(f, { __index = function(t, k)
        -- 🔴 `__` 开头的是**测试自己的内省字段**,绝不能兜底:
        -- 兜底会让 `if f.__onupdate then` 对每个框体都成立 ⇒ 查找函数返回错的那个,
        -- 而断言照样跑、照样给答案 —— 这正是"宽容的默认值会替 bug 遮丑"。
        if type(k) == "string" and k:sub(1, 2) == "__" then return nil end
        autoStub[k] = (autoStub[k] or 0) + 1
        local fn = function() end
        rawset(t, k, fn)
        return fn
    end })
    frames[#frames + 1] = f
    return f
end
_G.CreateFrame = function(kind, name) return mkFrame(kind, name) end

-- 暴雪那套 proc 发光的桩:记下现在给谁开着,好断言"显示时周围发光"
_G.ActionButtonSpellAlertManager = {
    shown = {},
    ShowAlert = function(self, f) self.shown[f] = true end,
    HideAlert = function(self, f) self.shown[f] = nil end,
}

-- 找那个注册了 glow 事件的框体(测试期只会有一个)
local function eventFrame()
    for i = #frames, 1, -1 do
        if frames[i].events["SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"] then return frames[i] end
    end
end
-- 按名字找 —— 别再用"有 OnUpdate 的那个"当判据:驱动挪到排上之后,
-- 那个判据会摸到排的宿主框体,而断言照样跑、照样给答案(假绿)。
local function frameByName(n)
    for i = #frames, 1, -1 do if frames[i].__name == n then return frames[i] end end
end

_G.UIParent = mkFrame("Frame")
_G.STANDARD_TEXT_FONT = "font.ttf"
_G.AnchorUtil = { FlowDirection = { Right = 1, Down = 2, Up = 3, Left = 4 } }
_G.AuraContainerSortMethod = { Expiration = 1 }
_G.AuraContainerSortDirection = { Normal = 1 }
_G.DodoCombatHUDDB = {}

_G.Enum = { SecrecyLevel = { Never = 0, Restricted = 1, Always = 2 } }

-- 场景装配。plain=true 走 A,false 走 B。
local scene = {}
local function setup(plain)
    scene.plain = plain
    frames = {}
    -- 🔴 每个场景开头清空。SECRETS 是按**值**登记的,而 Lua 的数字是值不是对象 ——
    -- B 场景 mkSecret(1015.0) 标的是「数字 1015.0」本身,不清的话 C 场景那个
    -- 明文 1015.0 也会被判成 secret。实撞:C 段光环读数整段报的是污染、不是代码。
    for k in pairs(SECRETS) do SECRETS[k] = nil end
    _G.C_Secrets = {
        HasSecretRestrictions   = function() return true end,
        ShouldAurasBeSecret     = function() return not plain end,
        GetSpellAuraSecrecy     = function() return plain and 0 or 2 end,
        GetSpellCastSecrecy     = function() return 0 end,
    }
    _G.C_Spell = {
        GetSpellName    = function(id) return "沸点#" .. id end,
        GetSpellTexture = function(id) return plain and (id % 1000) or nil end,
        GetOverrideSpell = plain and function(id) return id end or nil,   -- B 场景模拟 API 不存在
    }
    _G.C_SpellActivationOverlay = { IsSpellOverlayed = function() return overlayed end }
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function(id)
            if not plain then
                if id == 1265982 then return nil end                       -- 隐藏光环:读不到
                return { expirationTime = mkSecret(1015.0), duration = mkSecret(15.0),
                         applications = mkSecret(1) }
            end
            if id == 1265968 then return { expirationTime = 1015.0, duration = 15.0, applications = 1 } end
            return nil
        end,
    }
end

local function loadBoiling()
    local chunk = loadfile("Boiling.lua") or loadfile("../Boiling.lua")
    assert(chunk, "找不到 Boiling.lua —— 在插件根目录或 tools/ 下面跑")
    local ns = {}
    -- DodoCombatHUD.lua 会导出这两个;不桩的话 BuildSlot 直接拒建,
    -- 而后面每条断言都会红成一片、看不出根因在这儿。
    local anchorFrame = mkFrame("Frame", "FakeCdAnchor")
    ns.cdPad = 0
    ns.GetCdRowAnchor = function() return anchorFrame, -4 end
    ns.SetCdRowPad    = function(px) ns.cdPad = tonumber(px) or 0 end
    chunk("DodoCombatHUD", ns)
    return ns
end

local fails = 0
local function check(name, cond, dump)
    if cond then
        realprint("  ok    " .. name)
    else
        fails = fails + 1
        realprint("  FAIL  " .. name)
        if dump then for _, l in ipairs(out) do realprint("        | " .. l) end end
    end
end

local function joined() return table.concat(out, "\n") end
local function has(s) return joined():find(s, 1, true) ~= nil end

-- ── A:全明文 ─────────────────────────────────────────────────────────────
realprint("[A] per-spell Aura=Never,一切明文")
setup(true); out = {}; timers = {}
local nsA = loadBoiling()
local okA, errA = pcall(nsA.BoilingProbe, "now")
check("静态问答不抛错", okA, false); if not okA then realprint("        " .. tostring(errA)) end
check("secrecy 反查出枚举名 Never(0)", has("Never(0)"))
check("明文 expirationTime 拼进去了", has("exp=1015"))
check("echo 没光环时说'无'", has("此刻 echo 光环: 无"))
check("没有一处 ERROR", not has("ERROR"), true)

-- ── B:全 secret / API 缺失 ───────────────────────────────────────────────
realprint("[B] 真机最坏情况:字段 secret、GetOverrideSpell 不存在")
setup(false); out = {}; timers = {}
local nsB = loadBoiling()
local okB, errB = pcall(nsB.BoilingProbe, "now")
check("静态问答不抛错", okB, false); if not okB then realprint("        " .. tostring(errB)) end
check("secret 字段被拦成 SECRET 没去 tostring", has("SECRET"))
check("API 不存在报的是'没这个API'不是 nil", has("没这个API"))
check("ShouldAurasBeSecret=true 如实报出", has("ShouldAurasBeSecret=true"))

-- ── C:录制路径(v2) ──────────────────────────────────────────────────────
-- 🔴 这一段才是真机上会执行的那条路。A/B 只跑了静态问答,事件处理里的 format
-- 一行都没执行到 —— 只跑 A/B 就宣布"通过"是假绿。
--
-- v2 新增的重点是 consumedNow():GLOW_HIDE 和 CAST 谁先到**是探针要量的东西之一**,
-- 所以判"消耗了"绝不能依赖一个会被 HIDE 清掉的布尔。两种顺序都必须算对。
realprint("[C] 事件录制 v2:两种事件顺序 + 负对照")
setup(true); out = {}; timers = {}; tickers = {}; fired = nil
local nsC = loadBoiling()
check("Stop 没污染全局", _G.Stop == nil)
local okC = pcall(nsC.BoilingProbe, "2")     -- 抓够 2 个完整周期就自停
check("开录不抛错", okC)
check("装上了事件 handler", type(fired) == "function")
check("挂了心跳 ticker(10s)", #tickers == 1 and tickers[1].d == 10)
check("硬上限 300s", #timers == 1 and timers[1].d == 300)

if type(fired) == "function" then
    local function fire(...)
        local ok, e = pcall(fired, nil, ...)
        if not ok then realprint("        抛错: " .. tostring(e)) end
        return ok
    end
    out = {}
    -- 周期 1:CAST 在 GLOW_HIDE **之前**(armed 还是 true)
    NOW = 1000.5; check("周期1 GLOW_SHOW", fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842))
    NOW = 1002.0; check("周期1 CAST",      fire("UNIT_SPELLCAST_SUCCEEDED", "player", "gA", 50842))
    NOW = 1002.0; check("周期1 GLOW_HIDE", fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 50842))
    -- 负对照:boss 施法(unit 明文但不是 player)+ unit 本身是 secret
    NOW = 1002.5; check("boss 施法不抛错",   fire("UNIT_SPELLCAST_SUCCEEDED", "boss1", "gB", 999999))
    NOW = 1003.0; check("secret unit 不抛错", fire("UNIT_SPELLCAST_SUCCEEDED", mkSecret("boss1"), "gC", mkSecret(888)))
    NOW = 1003.5; check("UNIT_AURA 不抛错",  fire("UNIT_AURA", "player"))
    -- 周期 2:GLOW_HIDE 在 CAST **之前**(armed 已被清)—— v2 就是为这个写的
    NOW = 1010.0; check("周期2 GLOW_SHOW", fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842))
    NOW = 1011.9; check("周期2 GLOW_HIDE", fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 50842))
    NOW = 1012.0; check("周期2 CAST",      fire("UNIT_SPELLCAST_SUCCEEDED", "player", "gD", 50842))

    local j = joined()
    check("抓够 2 个就自己停了",      j:find("收工(抓够了)", 1, true) ~= nil, true)
    check("|cff33ff99反序也算成周期|r:完整周期 2", j:find("完整周期 2", 1, true) ~= nil, true)
    check("血沸亮了 2 次",            j:find("血沸亮 2 次", 1, true) ~= nil, true)
    check("心跳 ticker 被取消",       tickers[1].cancelled == true)
    check("直方图印出了施法 ID",      j:find("50842", 1, true) ~= nil)
    check("|cff33ff99负对照|r:999999 一个字都没进去", j:find("999999", 1, true) == nil, true)
    check("|cff33ff99负对照|r:888 一个字都没进去",    j:find("888", 1, true) == nil, true)
    -- ⚠ 认 describe() 真吐出来的带色标记,不扫裸词 —— 报告说明文字里本来就含 "SECRET"
    check("C 里读数不该有 secret",    j:find("|cffff8800SECRET|r", 1, true) == nil, true)
    check("大声要了 /reload",         j:find("/reload", 1, true) ~= nil, true)
    check("相对时刻算对(0.50s/2.00s)",
          j:find("0.50s", 1, true) ~= nil and j:find("2.00s", 1, true) ~= nil, true)
end

-- ── D:proc 自然过期,不算周期 ────────────────────────────────────────────
-- 这条直接守 GLOW_HIDE 清 armed 那个修复。没有它的话:过期那次 armed 一直挂着,
-- 之后随便一发普通血沸都被记成"高亮那一发" ⇒ 完整周期虚高,而时间轴上看不出哪条是假的。
realprint("[D] proc 过期后打的普通血沸,不许算成周期")
setup(true); out = {}; timers = {}; tickers = {}; fired = nil
local nsD = loadBoiling()
pcall(nsD.BoilingProbe, "5")            -- want=5,不会中途自停
out = {}
NOW = 2000.0; pcall(fired, nil, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)
NOW = 2015.0; pcall(fired, nil, "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 50842)  -- 15 秒后 = 自然过期
NOW = 2020.0; pcall(fired, nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "gE", 50842)
pcall(nsD.BoilingProbe, "stop")
local jd = joined()
check("血沸确实亮过 1 次",       jd:find("血沸亮 1 次", 1, true) ~= nil, true)
check("过期后那发不算周期(0)", jd:find("完整周期 0", 1, true) ~= nil, true)
check("提示了'一次都没消耗'的分诊", jd:find("完整周期 0", 1, true) ~= nil)

-- ── E:放生模式 ──────────────────────────────────────────────────────────
-- 守的是 v3 唯一的新问题:proc 窗口到底多长。只有**自然过期**那次的间隔算数,
-- 被消耗那次量到的是玩家的反应时间(实测 1.20~1.29s)—— 两者混在一起 = 读数没用。
realprint("[E] 放生模式:只认自然过期,抓够 2 次自停")
setup(true); out = {}; timers = {}; tickers = {}; fired = nil
local nsE = loadBoiling()
pcall(nsE.BoilingProbe, "expire")
out = {}
NOW = 3000.0; pcall(fired, nil, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)
NOW = 3015.0; pcall(fired, nil, "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 50842)   -- 过期 #1
NOW = 3020.0; pcall(fired, nil, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)
NOW = 3032.0; pcall(fired, nil, "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 50842)   -- 过期 #2 → 自停
local je = joined()
check("抓够 2 次自然过期就停",  je:find("收工(放生够了)", 1, true) ~= nil, true)
check("两次都判成自然过期",      select(2, je:gsub("自然过期 ← proc", "")) == 2, true)
check("量到 15.00s",             je:find("15.00s", 1, true) ~= nil, true)
check("量到 12.00s",             je:find("12.00s", 1, true) ~= nil, true)

-- 负对照:放生模式里**打了**血沸的那次不算过期,也不许提前收工
realprint("[E2] 放生模式里消耗掉的那次不算过期")
setup(true); out = {}; timers = {}; tickers = {}; fired = nil
local nsE2 = loadBoiling()
pcall(nsE2.BoilingProbe, "expire")
out = {}
NOW = 4000.0; pcall(fired, nil, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)
NOW = 4001.2; pcall(fired, nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "gF", 50842)
NOW = 4001.2; pcall(fired, nil, "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 50842)
NOW = 4010.0; pcall(fired, nil, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)
NOW = 4022.0; pcall(fired, nil, "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 50842)   -- 这才是第 1 次过期
local j2 = joined()
check("消耗那次没被算成过期(还没停)", j2:find("收工", 1, true) == nil, true)
pcall(nsE2.BoilingProbe, "stop")
local j3 = joined()
check("报告里消耗/过期分得开",
      j3:find("被消耗(这只是你的反应时间", 1, true) ~= nil
      and j3:find("自然过期 ← proc", 1, true) ~= nil, true)

-- ── F:row 子命令的分发与战斗闸 ───────────────────────────────────────────
local function run(fn, ...)
    local ok, e = pcall(fn, ...)
    if not ok then realprint("        |cff抛错|r " .. tostring(e)) end
    return ok
end
realprint("[F] row 子命令")
setup(true); out = {}; timers = {}; tickers = {}; fired = nil
local nsF = loadBoiling()
inCombat = true
run(nsF.BoilingProbe, "row")
check("战斗中拒建并说明原因", has("战斗中不建框体"), true)
out = {}
run(nsF.BoilingProbe, "row off")
check("没建就 off 不炸、且如实说", has("沸点格还没建"), true)
out = {}
run(nsF.BoilingProbe, "row zzz")
check("不认识的 row 参数会点名", has("不认识 row 的这个参数"), true)
out = {}
run(nsF.BoilingProbe, "rows")
check("|cff33ff99负对照|r:rows 不该被当成 row", not has("战斗中不建框体"), true)
run(nsF.BoilingProbe, "stop")
inCombat = false

-- ── G:自身 buff 排:红盖绿 + 发光 ────────────────────────────────────────
-- 🔴 绿色那半(暴雪容器)跑通了**完全不替这半背书**:这半是"没有光环可读、
-- echo 落地也不发事件" ⇒ 全靠 glow + 我自己的施法自己计时。
realprint("[G] 自身 buff 排:红盖绿 + 发光")
setup(true); out = {}; timers = {}; tickers = {}; fired = nil
inCombat, overlayed = false, false
local nsG = loadBoiling()
run(nsG.BoilingProbe, "row")
local host  = frameByName("DodoBoilingSlot")     -- 驱动挂在格子自己身上
local ec    = frameByName("DodoBoilingEcho")
local slot4 = host
local ef    = eventFrame()
local glow  = _G.ActionButtonSpellAlertManager.shown
check("沸点格建出来了", host ~= nil)
check("echo 覆盖层建出来了", ec ~= nil)
check("大招排右移了一格给它腾位", (nsG.cdPad or 0) > 0)
check("状态机挂上 3 个事件", ef ~= nil and ef.events["SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"]
      and ef.events["SPELL_ACTIVATION_OVERLAY_GLOW_HIDE"] and ef.events["UNIT_SPELLCAST_SUCCEEDED"])

if host and ec and ef and slot4 then
    local function ev(...)
        local ok, e = pcall(ef.__onevent, nil, ...)
        if not ok then realprint("        |cff抛错|r " .. tostring(e)) end
    end
    local function tick(dt) pcall(host.__onupdate, host, dt or 0) end
    local function txt() return ec.__fs[1] and ec.__fs[1].__text end

    NOW = 5000.0; ev("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 50842); tick()
    check("|cff33ff99负对照|r:没 proc 时打血沸,不出红", ec.__shown == false, true)
    check("|cff33ff99负对照|r:什么都没有时不发光", glow[slot4] == nil, true)
    -- bg 是这格上建的第一张贴图(容器/echo 的贴图都建在各自的子框体上)
    check("|cff33ff99负对照|r:空着时整格透明", (host.__tex[1].__alpha or 1) == 0, true)

    overlayed = true
    NOW = 5001.0; ev("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842); tick()
    check("只有绿(15秒)时也发光", glow[slot4] == true, true)
    check("只有绿时红不显示", ec.__shown == false, true)

    NOW = 5001.5; ev("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 99999); tick()
    check("|cff33ff99负对照|r:亮着但打的是别的技能,不出红", ec.__shown == false, true)
    NOW = 5002.0; ev("UNIT_SPELLCAST_SUCCEEDED", "boss1", "g", 50842); tick()
    check("|cff33ff99负对照|r:boss 打血沸不算我打的", ec.__shown == false, true)

    NOW = 5010.0; ev("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)
    NOW = 5011.2; ev("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 50842)
    overlayed = false                       -- proc 被消耗 ⇒ 绿灭
    NOW = 5011.2; tick()
    check("高亮那一发 → 红出现", ec.__shown == true, true)
    check("倒数从 3.0 起", txt() == "3.0", true)
    check("红在跑时也发光", glow[slot4] == true, true)
    check("有内容时暗底出来", (host.__tex[1].__alpha or 0) > 0, true)

    ev("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 50842)
    NOW = 5012.2; tick(1.0)
    check("同帧重复上报不重排(1 秒后 = 2.0)", txt() == "2.0", true)

    NOW = 5012.5; ev("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)
    NOW = 5013.0; ev("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 50842)
    NOW = 5013.0; tick()
    check("被顶掉重排 → 回到 3.0", txt() == "3.0", true)
    check("重排时闪了一下", ec.__tex and ec.__tex[2] and (ec.__tex[2].__alpha or 0) > 0.5, true)

    NOW = 5016.1; tick()
    check("3 秒到自己收起来", ec.__shown == false, true)
    check("红没了绿也没 ⇒ 灭光", glow[slot4] == nil, true)

    NOW = 5020.0; ev("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)
    NOW = 5021.0; ev("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 50842)
    NOW = 5021.0; ev("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 50842)
    NOW = 5021.0; tick()
    check("HIDE 先到也认得出是消耗", ec.__shown == true, true)
    NOW = 5030.0; tick()

    NOW = 5040.0; ev("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)
    NOW = 5055.0; ev("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 50842)
    NOW = 5060.0; ev("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 50842)
    NOW = 5060.0; tick()
    check("|cff33ff99负对照|r:proc 过期后打血沸,不出红", ec.__shown == false, true)

    out = {}
    run(nsG.BoilingProbe, "row off")
    check("关掉会注销事件", next(ef.events) == nil, true)
    check("关掉会灭光", glow[slot4] == nil, true)
    check("关掉会把大招排移回去", (nsG.cdPad or -1) == 0, true)
end

realprint("[G2] 开排时 proc 已经亮着(补同步)")
setup(true); out = {}; fired = nil
inCombat, overlayed = false, true
local nsG2 = loadBoiling()
run(nsG2.BoilingProbe, "row")
local ef2 = eventFrame()
local ec2 = frameByName("DodoBoilingEcho")
local h2  = frameByName("DodoBoilingSlot")
if ef2 and ec2 and h2 then
    NOW = 6000.0; pcall(ef2.__onevent, nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "g", 50842)
    pcall(h2.__onupdate, h2, 0)
    check("没收到 GLOW_SHOW 也认得出(靠 IsSpellOverlayed 补的)", ec2.__shown == true, true)
end
overlayed = false

-- ── H:第三种灭法 —— echo 那一发把新 proc 也吃掉 ──────────────────────────
-- 2026-08-23 Jerry 真机发现的那个场景。判据必须跟「自然过期」分得开,
-- 否则那一栏会被污染:一个 3 秒后灭掉的 glow 会被记成「proc 窗口只有 3 秒」。
realprint("[H] echo 吃掉新 proc(无人施法的 HIDE)")
setup(true); out = {}; timers = {}; tickers = {}; fired = nil
local nsH = loadBoiling()
run(nsH.BoilingProbe, "3")
out = {}
NOW = 7000.0; pcall(fired, nil, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)
NOW = 7001.0; pcall(fired, nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "g", 50842)  -- 消耗,echo 落地在 7004
NOW = 7001.0; pcall(fired, nil, "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 50842)
NOW = 7002.0; pcall(fired, nil, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)       -- 3 秒内又出新 proc
NOW = 7004.0; pcall(fired, nil, "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 50842)       -- 无人施法,正好 echo 落地
run(nsH.BoilingProbe, "stop")
local jh = joined()
check("认出是被 echo 吃掉的", jh:find("echo 自己吃掉了新 proc", 1, true) ~= nil, true)
check("报告里单列一类", jh:find("被 echo 那一发吃掉了", 1, true) ~= nil, true)
check("坐实计数报出来", jh:find("坐实 1 次", 1, true) ~= nil, true)
check("|cff33ff99负对照|r:没被算成自然过期", jh:find("自然过期 ← proc", 1, true) == nil, true)

realprint("[H2] 真的自然过期,别误判成 echo 吃的")
setup(true); out = {}; timers = {}; tickers = {}; fired = nil
local nsH2 = loadBoiling()
run(nsH2.BoilingProbe, "3")
out = {}
NOW = 8000.0; pcall(fired, nil, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)
NOW = 8001.0; pcall(fired, nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "g", 50842)
NOW = 8001.0; pcall(fired, nil, "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 50842)
NOW = 8002.0; pcall(fired, nil, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)
NOW = 8017.0; pcall(fired, nil, "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 50842)       -- 15 秒后,离 echo 落地远得很
run(nsH2.BoilingProbe, "stop")
local jh2 = joined()
check("15 秒后灭的仍判自然过期", jh2:find("自然过期 ← proc", 1, true) ~= nil, true)
check("|cff33ff99负对照|r:没误判成 echo 吃的", jh2:find("坐实", 1, true) == nil, true)

-- ── I:echo 链 —— echo 那一发吃掉新 proc,红要接着再跑 3 秒 ────────────────
-- 2026-08-23 Jerry 真机定案:echo 落地那一刻绿的 15 跟着消失 ⇒ 确实被吃掉了。
-- 而那一发**不发任何施法事件**(已实测)⇒ 只能靠「无人施法的 GLOW_HIDE 正好赶上落地」认。
realprint("[I] echo 链:无人施法的 HIDE 要接着排 3 秒")
setup(true); out = {}; timers = {}; tickers = {}; fired = nil
inCombat, overlayed = false, false
local nsI = loadBoiling()
run(nsI.BoilingProbe, "row")
local hI  = frameByName("DodoBoilingSlot")
local ecI = frameByName("DodoBoilingEcho")
local efI = eventFrame()
if hI and ecI and efI then
    local function ev(...) pcall(efI.__onevent, nil, ...) end
    local function tick(dt) pcall(hI.__onupdate, hI, dt or 0) end
    local function txt() return ecI.__fs[1] and ecI.__fs[1].__text end

    NOW = 9000.0; ev("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)
    NOW = 9001.0; ev("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 50842)   -- echo 落地在 9004
    NOW = 9001.0; ev("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 50842)        -- 同帧,是"你打的"
    NOW = 9001.0; tick()
    check("第一发:红起来了", ecI.__shown == true and txt() == "3.0", true)

    NOW = 9002.0; ev("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)        -- 3 秒内又出新 proc
    NOW = 9003.0; tick()
    check("链条前:剩 1.0", txt() == "1.0", true)

    NOW = 9004.0; ev("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 50842)        -- 无人施法,正好落地
    NOW = 9004.0; tick()
    check("|cff33ff99链条接上|r:红重新回到 3.0", txt() == "3.0", true)
    check("链条接上时红仍然显示", ecI.__shown == true, true)

    -- 链条可以继续:第二个 echo 落地在 9007
    NOW = 9005.0; ev("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)
    NOW = 9007.0; ev("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 50842)
    NOW = 9007.0; tick()
    check("链条能连着接第二次", txt() == "3.0", true)

    NOW = 9010.1; tick()
    check("链条断了就正常收起来", ecI.__shown == false, true)

    -- 负对照 ①:无人施法的 HIDE,但**不在**落地时刻(= 15 秒自然过期)
    NOW = 9020.0; ev("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)
    NOW = 9035.0; ev("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 50842)
    NOW = 9035.0; tick()
    check("|cff33ff99负对照|r:自然过期不许起红", ecI.__shown == false, true)

    -- 负对照 ②:你自己打的那一发,HIDE 同帧,不许被当成"echo 吃的"再排一次
    NOW = 9040.0; ev("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)
    NOW = 9041.0; ev("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 50842)
    NOW = 9041.0; ev("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 50842)
    NOW = 9042.0; tick(1.0)
    check("|cff33ff99负对照|r:自己打的那发只排一次(1 秒后 = 2.0)", txt() == "2.0", true)
end

-- ── J:自动出现的三条判据 ────────────────────────────────────────────────
-- 它不该要人敲命令,所以判据本身就是功能的一部分:任一条不成立都不该占着大招排最左格。
realprint("[J] 自动出现:专精 / 天赋 / 大招排开关")
setup(true); out = {}; timers = {}; tickers = {}; fired = nil
inCombat, overlayed = false, false
specID, hasTalent = 250, true
local nsJ = loadBoiling()
_G.DodoCombatHUDDB = { cdsOn = true }
local function slot() return frameByName("DodoBoilingSlot") end
local function shown() local f = slot(); return f ~= nil and f.__shown == true end

run(nsJ.BoilingEvaluate)
check("血 DK + 点了天赋 ⇒ 自己出现", shown(), true)

specID = 251                                   -- 冰霜 DK
run(nsJ.BoilingEvaluate)
check("|cff33ff99负对照|r:换成别的专精 ⇒ 收起来", not shown(), true)
check("收起来时大招排移回去", (nsJ.cdPad or -1) == 0, true)

specID = 250
run(nsJ.BoilingEvaluate)
check("换回血 DK ⇒ 又出来", shown(), true)

-- 正对照:有这格的时候,大招排**确实**被推开了一格。
-- 🔴 少了这条,下面那个"pad 归零"就是空转 —— pad 一直是 0 也能全绿。
check("有这格时大招排被推开(pad > 0)", (nsJ.cdPad or 0) > 0, true)

hasTalent = false                              -- 血 DK 但没点沸点
run(nsJ.BoilingEvaluate)
check("|cff33ff99负对照|r:没点沸点天赋 ⇒ 不该有这格", not shown(), true)
-- 🔑 Jerry 要的「没点天赋就把它隐藏掉、其他的顺延到前面」——
--    实现方式就是这个 pad 回 0(大招排整体左移一格)。这条断言就是那句需求。
check("没点天赋 ⇒ 大招排顺延回最左(pad = 0)", (nsJ.cdPad or -1) == 0, true)
-- 面板那条路:它拿 ns.BoilingEligible 决定那一行画不画,并且要**说出为什么**。
do
    local ok, why = nsJ.BoilingEligible()
    check("面板:没点天赋 ⇒ 不合格", ok == false, true)
    check("面板:而且给得出原因", type(why) == "string" and #why > 0, true)
end

hasTalent = true
_G.DodoCombatHUDDB.cdsOn = false               -- 大招排整排关掉了
run(nsJ.BoilingEvaluate)
check("|cff33ff99负对照|r:大招排关了 ⇒ 没地方钉,收起来", not shown(), true)

_G.DodoCombatHUDDB.cdsOn = true
run(nsJ.BoilingEvaluate)
check("大招排开回来 ⇒ 又出来", shown(), true)

-- 手动关掉之后不许自动开回来 —— 否则那个开关等于没有
out = {}
run(nsJ.BoilingProbe, "row off")
check("手动关掉了", not shown(), true)
run(nsJ.BoilingEvaluate)
check("|cff33ff99负对照|r:手动关过就不再自动出现", not shown(), true)
run(nsJ.BoilingProbe, "row")
check("手动开回来", shown(), true)

-- 🔴 回归:0.12.0 那版的存档里带着 bpSlot = { on = false }(那时默认就是 false),
-- 而"改默认值"对**已经落盘的键**无效 ⇒ 它会永久压着这个功能,且自动路径是静默的。
-- 现在存的是 manualOff(缺席 = 开),老键必须被当垃圾扔掉。
realprint("[J2] 老存档里的 on=false 不许再压着它")
setup(true); out = {}; frames = {}; fired = nil
inCombat, overlayed = false, false
specID, hasTalent = 250, true
local nsJ2 = loadBoiling()
_G.DodoCombatHUDDB = { cdsOn = true, bpSlot = { on = false } }   -- 0.12.0 留下的存档
run(nsJ2.BoilingEvaluate)
local f2 = frameByName("DodoBoilingSlot")
check("老键 on=false 被无视,照样出现", f2 ~= nil and f2.__shown == true, true)
check("|cff33ff99顺手|r:老键被清掉,不留着骗人", _G.DodoCombatHUDDB.bpSlot.on == nil, true)

realprint("[K] 容器的 initializeFrame")
check("initializeFrame 一次都没抛", #initErrors == 0)
for _, e in ipairs(initErrors) do realprint("        |cff抛错|r " .. e) end

realprint("")
realprint("桩自动兜底的方法:")
do
    local ks = {}
    for k in pairs(autoStub) do ks[#ks + 1] = k end
    table.sort(ks)
    realprint("  (" .. #ks .. " 个) " .. table.concat(ks, " "))
    realprint("  ⚠ 里面出现没见过的名字 = 代码里有 typo 被静默吞了")
end

realprint("")
if fails == 0 then realprint("全部通过") else realprint(fails .. " 条 FAIL") end
os.exit(fails == 0 and 0 or 1)
