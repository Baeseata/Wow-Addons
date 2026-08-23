-- Boiling.lua - 血 DK「沸点」监视:**探针 + 显示层**(0.12 起有显示,0.13 起面板能开关它)。
--
-- ⚠ 这段文件头 0.12 之前写的是「第一步只有探针,没有任何显示 / 只读、只打印、
--   不建受保护框体」—— **那是当时的施工阶段,不是现在的事实**,已经改过来了。
--   下面 `沸点那一格` 那节才是显示层的正文。
--
-- 当初先做探针的理由留着(它解释了为什么显示层长这样):显示怎么做完全取决于
-- 一个还没量过的答案 —— 那两个 buff 是不是 per-spell `Aura=Never`。
-- 是 ⇒ 明文读 expirationTime、自己算自己画;不是 ⇒ 只能把 spellID 递给暴雪的
-- AuraContainer,让它去取数据、去画倒计时。猜错的代价不是"改一改",是整层重写。
-- 量出来的答案是**后者**(战斗中光环被扣值),所以绿色那半交给暴雪画、
-- 红色那 3 秒(恒定长度、起点是明文事件)才是我们自己算的。

local ADDON, ns = ...
ns = ns or {}

-- ---------------------------------------------------------------- 待验断言
-- 出处 = SimulationCraft `engine/class_modules/sc_death_knight.cpp:15219`:
--     spell.boiling_point_buff      = 1265968
--     spell.boiling_point_echo_buff = 1265982
-- 以及它 blood_boil 的 execute():proc 在场就 expire proc、trigger echo;
-- echo 的 expire callback 打出那一发额外血沸 ⇒ **echo 消失的瞬间 = 自动血沸落地**。
--
-- 🔴 这四个数现在是**断言,不是事实**。本文件存在的全部理由就是把它们变成事实。
-- 任何一条对不上,先改这张表,别改下面的逻辑。
local ID = {
    proc   = 1265968,   -- 沸点 proc:wowhead 标 15 秒,+50% 血沸伤害,有图标
    echo   = 1265982,   -- 沸点 echo:wowhead 标 3 秒,标着 No Aura Icon(隐藏)
    boil   = 50842,     -- 血液沸腾
    talent = 1265790,   -- 沸点(隐藏被动本体)
}
local SPEC_BLOOD = 250

-- ---------------------------------------------------------------- secret 安全层
-- 12.x 的 secret 值**用 type() 认不出来** —— 它伪装成它顶替的那个数/字符串,
-- 只在你**使用**它的时候才炸。而 `tostring()` 本身就算一次使用。
-- ⇒ 打日志是最容易炸的地方,而它炸在事件处理里 = 整个探针静默死掉、一条读数都拿不到。
local function isSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, s = pcall(issecretvalue, v)
    return ok and s == true
end

local function describe(v)
    if v == nil then return "nil" end
    if isSecret(v) then return "|cffff8800SECRET|r" end
    local ok, s = pcall(tostring, v)
    if not ok then return "<unreadable>" end
    return s
end

local function Print(msg) print("|cffff66cc" .. ADDON .. "|r " .. msg) end

-- 同时进聊天框和 DodoProbe 的落盘日志(装了才写),这样长时间轴不用截屏抄。
local function emit(s)
    Print(s)
    if _G.DodoProbeLog then _G.DodoProbeLog("dch-bp", s) end
end

-- 探测式调用:API 不存在 / 调用被拒 / 返回 secret,三种情况各有各的说法,
-- 别糊成一个 "nil" —— 它们对应完全不同的修法。
local function call(fn, ...)
    if type(fn) ~= "function" then return "|cffff3333没这个API|r" end
    local ok, v = pcall(fn, ...)
    if not ok then return "|cffff3333ERROR|r" end
    return describe(v)
end

-- SecrecyLevel 是个 enum,光打数字看不懂。反查一次名字,拿不到就退回数字。
local SECRECY = {}
do
    local e = Enum and Enum.SecrecyLevel
    if type(e) == "table" then
        for k, v in pairs(e) do SECRECY[v] = k end
    end
end

local function secrecy(fn, id)
    if type(fn) ~= "function" then return "|cffff3333没这个API|r" end
    local ok, v = pcall(fn, id)
    if not ok then return "|cffff3333ERROR|r" end
    if isSecret(v) then return "|cffff8800SECRET|r" end
    local name = SECRECY[v]
    if name then return name .. "(" .. tostring(v) .. ")" end
    return tostring(v)
end

-- 🔑 本探针最要紧的一行。
-- DodoProbe 2026-08-15 复测推翻过它自己上一版的结论:死掉的是**枚举**
-- (GetAuraDataByIndex 战斗中 ERROR),**不是定点查** —— per-spell Aura=Never 的法术,
-- GetPlayerAuraBySpellID 在战斗中照样给值(实测 BySpellID 1/12,命中的正是那个 Never 的)。
-- 所以这里必须逐字段 describe:表拿到了 ≠ 字段读得到。
local function auraState(id)
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if type(get) ~= "function" then return "没这个API" end
    local ok, a = pcall(get, id)
    if not ok then return "|cffff3333ERROR|r" end
    if a == nil then return "无" end
    if isSecret(a) then return "|cffff8800SECRET表|r" end
    if type(a) ~= "table" then return "非表:" .. describe(a) end
    return ("exp=%s dur=%s 层=%s"):format(
        describe(a.expirationTime), describe(a.duration), describe(a.applications))
end

-- ---------------------------------------------------------------- 静态问答
local function Static()
    emit("---- 沸点探针 · 静态问答 ----")

    -- 🔴 先报被测对象是谁。一份读数拿回来之后,「那到底是什么状态下量的」只能靠回忆,
    -- 而回忆和读数打架时谁也说服不了谁。
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    local specID
    if type(getSpec) == "function" and type(getInfo) == "function" then
        local ok, idx = pcall(getSpec)
        if ok and idx then
            local ok2, id = pcall(getInfo, idx)
            if ok2 then specID = id end
        end
    end
    emit(("  专精=%s(血 DK 应为 %d)  战斗中=%s"):format(describe(specID), SPEC_BLOOD, tostring(InCombatLockdown())))
    emit(("  沸点天赋 IsPlayerSpell(%d)=%s   ← 这条 false 的话下面全部无效"):format(
        ID.talent, call(IsPlayerSpell, ID.talent)))

    -- ① 决定显示层长什么样的那一问。Never ⇒ 明文读、自己画;别的 ⇒ 只能交给暴雪容器。
    if C_Secrets then
        emit(("  HasSecretRestrictions=%s   ShouldAurasBeSecret=%s"):format(
            call(C_Secrets.HasSecretRestrictions), call(C_Secrets.ShouldAurasBeSecret)))
        emit(("  |cff33ff99AuraSecrecy|r  proc(%d)=%s   echo(%d)=%s"):format(
            ID.proc, secrecy(C_Secrets.GetSpellAuraSecrecy, ID.proc),
            ID.echo, secrecy(C_Secrets.GetSpellAuraSecrecy, ID.echo)))
        emit(("  CastSecrecy 血沸(%d)=%s"):format(ID.boil, secrecy(C_Secrets.GetSpellCastSecrecy, ID.boil)))
    else
        emit("  |cffff3333C_Secrets 不存在|r")
    end

    -- ② 名字对不对 = 那两个 ID 抄对了没有。抄错的话下面一切都在量一个不相干的法术。
    emit(("  名字  proc=%s   echo=%s   血沸=%s"):format(
        call(C_Spell.GetSpellName, ID.proc), call(C_Spell.GetSpellName, ID.echo),
        call(C_Spell.GetSpellName, ID.boil)))

    -- ③ 图标:GetSpellTexture 给的是 fileID。
    -- 🔑 判据 = **这三个数一不一样**。不一样 ⇒ 原生变色版存在,直接用;
    --    一样 ⇒ 没有变色版,走染色(SetDesaturated + SetVertexColor,纹理对象归我们)。
    emit(("  图标  proc=%s   echo=%s   血沸=%s   ← 三个数不同 = 有原生变色版"):format(
        call(C_Spell.GetSpellTexture, ID.proc), call(C_Spell.GetSpellTexture, ID.echo),
        call(C_Spell.GetSpellTexture, ID.boil)))

    -- ④ 天赋可能把血沸覆盖成另一个 ID,而 glow 事件报的是**当前那个**。
    -- 只硬编 50842 的话,症状是"这功能在某些天赋下就是不亮",而且零报错。
    emit(("  GetOverrideSpell(%d)=%s   ← 跟 50842 不同的话,glow 报的是这个"):format(
        ID.boil, call(C_Spell and C_Spell.GetOverrideSpell, ID.boil)))

    -- ⑤ 可轮询的状态查询。事件会漏(/reload、战斗中登录、插件晚加载),这个不会。
    emit(("  IsSpellOverlayed(%d)=%s   ← 血沸此刻在不在发光"):format(
        ID.boil, call(C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed, ID.boil)))

    emit("  此刻 proc 光环: " .. auraState(ID.proc))
    emit("  此刻 echo 光环: " .. auraState(ID.echo))
    emit("---- 静态完 ----")
end

-- ---------------------------------------------------------------- 事件录制
--
-- 🔴 2026-08-23 重写:从「固定 30 秒 + 全程闷声」改成「录到抓够为止 + 实时播报」。
--
-- 上一版第一次真机就栽了,而栽的**不是运气**:30 秒里没出 proc,屏幕上
-- 「探针活着只是没赶上」和「探针压根没装上」**长得一模一样** —— 于是连
-- **静态那半段**(不需要 proc、已经答了 6 个问题里的 4 个)也一起丢了,
-- 因为看着没反应就没 /reload,而 DodoProbe 只在 /reload 才落盘。
--
-- ⇒ 三条对策,每条都对着上面那句:
--   ① 抓到就吼一声      —— 「活着但没赶上」当场跟「没装上」分得开
--   ② 每 5 秒报心跳      —— 零事件时也证明它在跑
--   ③ 收工时**大声要 /reload** —— 上一版只说「整段发我」,那是要人去抄聊天框

local rec
local lastAura = ""
local frame, ticker
local HARD_CAP = 300      -- 再没抓够也收工,免得忘了关一直挂着

local function bump(t, id)
    if isSecret(id) or type(id) ~= "number" then
        t.secret = (t.secret or 0) + 1
    else
        t[id] = (t[id] or 0) + 1
    end
end

-- 120 条封顶:AoE 里事件密度很高,刷屏会把真正有用的那几行冲掉。
-- 直方图不受这个限制(它只是计数),所以**样本量不会因为封顶而失真**。
local function log(tag, detail, live)
    if rec.n < 120 then
        rec.n = rec.n + 1
        rec.lines[rec.n] = ("  %6.2fs  %-10s %s"):format(GetTime() - rec.t0, tag, detail or "")
    end
    if live then
        Print(("|cff33ff99[%.1fs] %s|r %s"):format(GetTime() - rec.t0, tag, detail or ""))
    end
end

-- 血沸的"当前"ID:天赋可能把它覆盖掉,而 glow 报的是覆盖后那个。
-- 🔴 这份判据**必须只有一处** —— 录制和常驻显示都用它。写两遍就是个静默分歧发生器:
-- 两边单独看都对,漂了没人读得出来。所以 overrideID 抬到模块级,不再挂在 rec 上
-- (常驻显示时压根没有 rec)。
local overrideID
local function resolveOverride()
    local ok, ov = pcall(function()
        return C_Spell and C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(ID.boil)
    end)
    if ok and type(ov) == "number" and not isSecret(ov) then overrideID = ov end
end

local function isBoil(id)
    if isSecret(id) or type(id) ~= "number" then return false end
    return id == ID.boil or (overrideID ~= nil and id == overrideID)
end

-- 🔑 分开两种"读不到",这是 v3 加的唯一真问题。
-- true  ⇒ RequiresNonSecretAura 把值扣了(战斗限制),脱战就能读
-- false 而**仍然读不到** ⇒ 这个光环压根不在光环表里(隐藏光环),换谁来读都没有,
--        连暴雪自己的 AuraContainer 也画不出来 —— 那就得整层换方案。
local function auraGate()
    local f = C_Secrets and C_Secrets.ShouldAurasBeSecret
    if type(f) ~= "function" then return "?" end
    local ok, v = pcall(f)
    if not ok then return "ERROR" end
    if isSecret(v) then return "SECRET" end
    return tostring(v)
end

-- 只数个数,**一个字段都不碰** —— 碰了万一是 secret 当场炸。
-- 战斗中枚举本来就是 ERROR(DodoProbe 实测),所以这也是个三态答案。
local function helpfulCount()
    local g = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if type(g) ~= "function" then return "?" end
    local n = 0
    for i = 1, 40 do
        local ok, aura = pcall(g, "player", i, "HELPFUL")
        if not ok then return "ERROR@" .. i end
        if type(aura) ~= "table" then break end
        n = n + 1
    end
    return tostring(n)
end

local Stop   -- 前向声明:OnEvent 抓够了要就地收工,而 Stop 定义在它下面

-- 🔴 「消耗了」不能只看一个 armed 布尔。
-- GLOW_HIDE 和 CAST 谁先到,**正是本探针要量的东西之一**(判读第 2 条)——
-- 要是 HIDE 先到就把 armed 清了,CAST 来的时候会判成"没消耗",于是完整周期恒为 0,
-- 而那读起来跟"根本没出过 proc"一模一样。**用时间窗,别用布尔。**
-- 吃一个状态表,不写死 rec —— 录制和常驻显示**共用这一份判据**。
-- 写两遍的话两边单独看都对、漂了没人读得出来(canon:同一不变式两份手写实现 = 静默分歧发生器)。
local function consumedBy(st)
    if st.armed then return true end
    local off = st.glowOffAt
    return off ~= nil and (GetTime() - off) < 0.5
end

local function consumedNow() return consumedBy(rec) end

local function OnEvent(_, event, a1, _, a3)
    if not (rec and rec.on) then return end

    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        bump(rec.glows, a1)
        local boil = isBoil(a1)
        if boil then
            rec.armed, rec.procs, rec.showAt, rec.consumedThis = true, rec.procs + 1, GetTime(), false
        end
        -- 🔴 这一行是 v3 的重点:血沸**正在发光**,proc buff 就必然在身上。
        -- 此刻还读不到 = 它根本不在光环表里,不是"战斗中被扣了值"。
        log("GLOW_SHOW", ("spellID=%s%s | proc[%s] echo[%s] | 光环闸=%s HELPFUL=%s"):format(
            describe(a1), boil and "   |cff33ff99← 血沸亮了|r" or "",
            auraState(ID.proc), auraState(ID.echo), auraGate(), helpfulCount()), true)

    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        local boil = isBoil(a1)
        local extra = ""
        if boil and rec.showAt then
            local d = GetTime() - rec.showAt
            local consumed = rec.consumedThis or
                (rec.lastHitAt ~= nil and (GetTime() - rec.lastHitAt) < 0.5)
            -- 🔴 第三种灭法(2026-08-23 Jerry 真机发现):
            -- 3 秒 echo 落地时如果身上又有一个新 proc,**那一发自动血沸可能把它也消耗掉**
            -- ⇒ glow 灭掉,而**没有任何人施法**(echo 不发 UNIT_SPELLCAST_SUCCEEDED,已实测)。
            -- 判据:这次 HIDE 正好落在某个待发 echo 的落地时刻上(±0.4s)。
            -- 它要是成立,「自然过期」那一栏就会被污染 —— 所以必须单独一类。
            local byEcho = (not consumed) and rec.echoEndsAt ~= nil
                           and math.abs(GetTime() - rec.echoEndsAt) < 0.4
            rec.durs[#rec.durs + 1] = { d = d, consumed = consumed, byEcho = byEcho }
            if not consumed and not byEcho then rec.expired = rec.expired + 1 end
            if byEcho then rec.echoAte = (rec.echoAte or 0) + 1 end
            extra = ("   |cffffff00亮了 %.2fs → %s|r"):format(d,
                consumed and "被消耗"
                or byEcho and "|cffff3333无人施法却灭了,正好赶上 echo 落地 ← echo 自己吃掉了新 proc|r"
                or "|cffff5555自然过期 = 这就是 proc 窗口真实时长|r")
        end
        log("GLOW_HIDE", ("spellID=%s%s | proc[%s] 光环闸=%s"):format(
            describe(a1), extra, auraState(ID.proc), auraGate()), boil)
        -- 🔴 HIDE 必须清 armed。glow 灭掉有两个原因:被消耗、或者 15 秒自然过期。
        -- 不清的话,过期那次会让 armed 一直挂着 true ⇒ 之后随便一发普通血沸
        -- 都被记成"高亮那一发",完整周期虚高,而时间轴上看不出哪条是假的。
        -- 真·被消耗那次靠 glowOffAt 的时间窗接住(HIDE 和 CAST 几乎同刻)。
        if boil then
            rec.armed, rec.glowOffAt, rec.showAt = false, GetTime(), nil
            if rec.mode == "expire" and rec.expired >= rec.want then Stop("放生够了") end
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- 🔴 顺序是故意的:先证明 unit 是明文的 "player",再碰 spellID。
        -- 反过来写,场上任何一个 boss 施法都会让我们去碰一个 secret;
        -- 一次抛错逃进事件处理 = 整个探针静默死掉,连报错都看不到。
        if isSecret(a1) or a1 ~= "player" then return end
        bump(rec.casts, a3)
        local boil = isBoil(a3)
        local hit  = boil and consumedNow()
        log("CAST", ("spellID=%s%s | proc[%s] echo[%s]"):format(describe(a3),
            hit and "   |cffff5555← 高亮那一发|r" or "",
            auraState(ID.proc), auraState(ID.echo)), boil)
        if hit then
            rec.cycles, rec.armed, rec.glowOffAt = rec.cycles + 1, false, nil
            rec.consumedThis, rec.lastHitAt = true, GetTime()
            -- echo 观察窗:那一发之后 3.5 秒内**任何**光环变动都强制记一行,
            -- 不走去重 —— 我们要找的正是"echo 落地有没有留下任何痕迹"。
            rec.echoUntil  = GetTime() + 3.5
            rec.echoEndsAt = GetTime() + 3.0   -- 那一发自动血沸的落地时刻
            if rec.mode ~= "expire" and rec.cycles >= rec.want then Stop("抓够了") end
        end

    elseif event == "UNIT_AURA" then
        if isSecret(a1) or a1 ~= "player" then return end
        -- arg2 是 secret 表,**碰都不碰** —— 只拿这个事件当"该重查了"的节拍。
        local st = ("proc[%s] echo[%s]"):format(auraState(ID.proc), auraState(ID.echo))
        local inWindow = rec.echoUntil ~= nil and GetTime() < rec.echoUntil
        if st ~= lastAura or inWindow then
            lastAura = st
            log("AURA", st .. (inWindow and "   |cff9999ff← echo 观察窗内|r" or ""))
        end
    end
end

-- ② 心跳:零事件的时候也要证明自己活着。
-- 上一版最大的问题就是没有这个 —— 玩家看不出"在跑但没赶上"和"根本没装上"的区别。
local function Heartbeat()
    if not (rec and rec.on) then return end
    Print(("|cffff66cc沸点探针|r 已跑 %ds · 血沸亮 %d 次 · 完整周期 %d/%d · 事件 %d 条   (/dch bp stop 收工)")
        :format(math.floor(GetTime() - rec.t0), rec.procs, rec.cycles, rec.want, rec.n))
end

-- 直方图:哪个 spellID 出现了几次。**它不受时间轴 120 条封顶的影响** ——
-- 封顶只砍展示,不砍计数,所以样本量不会因为刷屏而失真。
-- 🎁 副产物:心脏打击的次数就是 proc 率的**分母**,而血沸真正的 ID 会自己浮出来
--    (不用赌 GetOverrideSpell 猜得对不对)。
local function hist(t, title)
    local ks = {}
    for k in pairs(t) do ks[#ks + 1] = k end
    if #ks == 0 then emit("  " .. title .. ":(空)") return end
    table.sort(ks, function(a, b) return (t[a] or 0) > (t[b] or 0) end)
    emit("  " .. title .. ":")
    for i = 1, math.min(#ks, 10) do
        local k = ks[i]
        emit(("    %-12s x%-4d %s"):format(tostring(k), t[k],
            type(k) == "number" and call(C_Spell.GetSpellName, k) or ""))
    end
end

function Stop(reason)
    if not (rec and rec.on) then return end
    rec.on = false
    if frame then frame:UnregisterAllEvents() end
    if ticker then pcall(function() ticker:Cancel() end); ticker = nil end

    emit(("---- 收工(%s)· 跑了 %ds · 血沸亮 %d 次 · 完整周期 %d ----"):format(
        reason or "?", math.floor(GetTime() - rec.t0), rec.procs, rec.cycles))
    if (rec.echoAte or 0) > 0 then
        emit(("  |cffff3333坐实 %d 次:echo 那一发把新 proc 也吃掉了|r"):format(rec.echoAte))
        emit("  ⇒ 那时会有**第二个 3 秒**,而它没有任何施法事件可认 —— 只能靠这条 HIDE 认。")
    end
    if #rec.durs > 0 then
        emit("  |cff33ff99血沸高亮持续了多久|r:")
        for i = 1, #rec.durs do
            local r = rec.durs[i]
            emit(("    #%d  %.2fs  %s"):format(i, r.d,
                r.consumed and "被消耗(这只是你的反应时间,不是窗口长度)"
                or r.byEcho and "|cffff3333被 echo 那一发吃掉了(无人施法)|r"
                or "|cffff5555自然过期 ← proc 窗口真实时长就是它|r"))
        end
        if rec.expired == 0 then
            emit("    |cffff8800一次自然过期都没有 ⇒ 窗口时长仍未定案。跑 /dch bp expire 专门放生几个。|r")
        end
    end
    hist(rec.casts, "我自己的施法 spellID x次数  ← 心脏打击那个数 = proc 率的分母")
    hist(rec.glows, "动作条高亮 spellID x次数    ← 血沸真正用的是哪个 ID")
    emit(("---- 时间轴(%d 条)----"):format(rec.n))
    for i = 1, rec.n do emit(rec.lines[i]) end

    if rec.procs == 0 then
        emit("  |cffff8800血沸一次都没亮|r —— 两种可能,靠上面那张高亮直方图分:")
        emit("    直方图**空的**   ⇒ glow 这条路整个不开火(或者天赋没点),得换信道")
        emit("    直方图**有别的** ⇒ 事件是通的,只是没轮到血沸 = 纯运气,再来一轮")
    end
    emit("  |cff33ff99判读三条|r")
    emit("  1) 高亮那一发 CAST 之后约 3.00s 若**又来一条同 ID 的 CAST**,那是 echo 自己那一发")
    emit("  2) GLOW_HIDE 跟那条 CAST 谁先到、差多少 —— 决定拿哪个当'消耗了'的判据")
    emit("  3) proc 那行 exp= 是数字还是 SECRET/无 —— 数字 ⇒ 15 秒能自己算自己画")
    emit("---- 完 ----")
    Print(" ")
    Print("|cffff3333🔴 现在打一次 /reload|r|cffff8800 —— DodoProbe 只在 reload 那一刻落盘。")
    Print("|cffff8800   不 reload 的话上面这些只在聊天框里,关了就没了(上一轮就是这么丢的)。|r")
end

local session = 0

local function Start(want, mode)
    if rec and rec.on then emit("已经在录了。/dch bp stop 收工。") return end
    Static()

    -- 普通 Frame,不是 AuraContainer,也不挂 UIParent ⇒ 跟现有四排零交集。
    if not frame then frame = CreateFrame("Frame") end
    frame:SetScript("OnEvent", OnEvent)
    frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    frame:RegisterUnitEvent("UNIT_AURA", "player")

    rec = { on = true, t0 = GetTime(), n = 0, lines = {}, want = want, mode = mode,
            procs = 0, cycles = 0, expired = 0, durs = {},
            casts = {}, glows = {}, armed = false }
    lastAura = ""
    resolveOverride()

    if C_Timer.NewTicker then ticker = C_Timer.NewTicker(10, Heartbeat) end
    -- 每次开录换一个号:旧的硬上限定时器认号,不会把新一轮掐掉。
    session = session + 1
    local mine = session
    C_Timer.After(HARD_CAP, function()
        if session == mine then Stop(("到 %d 秒硬上限"):format(HARD_CAP)) end
    end)

    if mode == "expire" then
        emit(("---- 开录【放生模式】:抓够 %d 次**自然过期**才停(最多 %d 秒)----"):format(want, HARD_CAP))
        emit("  |cffff3333这一轮:出了 proc 千万别打血沸,让它自己灭。|r")
        emit("  心脏打击 / 灵界打击 / 精髓分裂照打,**就是不许按血沸**。")
        emit("  要量 GLOW_SHOW→GLOW_HIDE 的自然间隔 = proc 窗口真实时长(15 还是 12,由它定案),")
        emit("  顺带看 proc 续期时 GLOW_SHOW 会不会重发 —— 这两件事决定那个数字怎么画。")
    else
        emit(("---- 开录:抓够 %d 个完整周期就自己停(最多 %d 秒)----"):format(want, HARD_CAP))
        emit("  **专点心脏打击**别走完整循环 —— 单体 15%/次,循环里塞得越多越快出。")
        emit("  想快:去打一堆小怪。SimC 的模型里 proc 率按目标数放大,打满 5 个是 66%/次。")
    end
    Print("|cff33ff99每抓到一次会当场吼一声,每 10 秒报一次心跳|r —— 十几秒没动静就是没装上,不是运气。")
end


-- ---------------------------------------------------------------- 沸点那一格
--
-- 0.12(Jerry 2026-08-23 定):**不再另起一排**,钉进「大招存续排」最左边一格。
--
-- 骨盾 / 符文剑(舞动符文武器 49028)/ 血后精华 都是普通自身 buff ——
-- 直接进 `AuraSets.lua` 的大招表就行,**一行配置,零代码**。骨盾已经加进去了。
--
-- 只有沸点需要单独一格,因为它要三件大招排给不了的东西:
--   ① **血沸的图标** —— 容器画的是光环自己那张(沸点自带的 1380870)
--   ② **绿 / 红换色**
--   ③ **有 3 显 3、没 3 显 15** 的优先级 —— 同一格,两个数据源
-- 而且它必须**位置固定**:大招排按剩余时间排序,图标会左右移位,
-- 而这一格是要在 1.2 秒内做反应的东西,不能让它跑来跑去。
--
-- 排布靠 `ns.SetCdRowPad(w + sp)`:大招容器整体右移一格,我们占下最左那格。
-- 没启用时 pad = 0,别的专精一个像素都不受影响。

local boil = { slot = nil, container = nil, glowOn = false, pad = 0 }

local function slotGeom()
    local db = _G.DodoCombatHUDDB
    local n = type(db) == "table" and db or {}
    return tonumber(n.cdWidth) or 32, tonumber(n.cdHeight) or 32, tonumber(n.cdSpacing) or 2
end

-- 🔴 存的是「**被手动关过**」,不是「开着」。0.12.1 从 `on` 反过来改的,原因值得记:
--
-- `on` 那一版的默认值曾经是 false。而 `db.bpSlot = db.bpSlot or { on = true }` 里的 `or`
-- **只在键不存在时才生效** ⇒ 谁在那一版加载过一次,存档里就永久留着 on=false,
-- 后来把默认改成 true **对他一点用都没有**。而自动路径是静默的 ⇒ 零报错、零提示,
-- 表现成"这功能就是不出现",查半天查不到存档层。
--
-- ⇒ 通法:**默认值改动对已经落盘的键无效**。凡是"缺省该是开"的开关,
--   就存它的**反面**(缺省缺席 = 开),这样默认值根本不需要写进存档,也就无从变旧。
local function slotDB()
    local db = _G.DodoCombatHUDDB
    if type(db) ~= "table" then return {} end
    db.bpSlot = db.bpSlot or {}
    db.bpSlot.on = nil        -- 作废旧键,别让它再骗下一个人
    return db.bpSlot
end

local function tintIcon(tex, r, g, b)
    pcall(function() tex:SetDesaturated(true); tex:SetVertexColor(r, g, b) end)
end

local function makeContainer(parent, name, spellID, r, g, b, artID)
    -- 🔴 尺寸**现取**,不吃文件级常量:上一版那个 `SLOT = 44` 是"另起一排"时代的写死值,
    -- 改成钉进自身增益排之后它被删了,而这里还在用 ⇒ SetSize(nil, nil) 当场崩,
    -- 而且崩在 pcall 里 ⇒ 表现成"容器建不出来",完全看不出是个悬空的常量。
    local W, H = slotGeom()
    local ok, c = pcall(function()
        local cc = CreateFrame("AuraContainer", name, parent, "CustomAuraContainerTemplate")
        cc:SetFlowLayoutAnchorPoint("TOPLEFT")
        cc:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
        cc:SetFlowLayoutMaximumLineSize(math.huge)
        cc:SetUnit("player")
        cc:AddAuraGroup("g", "HELPFUL", {
            maxFrameCount   = 6,
            sortMethod      = AuraContainerSortMethod.Expiration,
            sortDirection   = AuraContainerSortDirection.Normal,
            candidateFilters = { includeSpellIDs = { [spellID] = true } },
            initializeFrame = function(button)
                local tex = button:CreateTexture(nil, "ARTWORK")
                tex:SetPoint("TOPLEFT", 1, -1)
                tex:SetPoint("BOTTOMRIGHT", -1, 1)
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                if artID then
                    -- 🔑 换掉暴雪写进来的图:**别跟它抢同一张贴图**(它每次刷新都重写)。
                    -- 递一张 1x1、alpha=0 的"收数据用"贴图给它,真正给人看的那张它碰不到。
                    -- 倒计时仍归它画 ⇒ 续期照样自动跟上。2026-08-23 真机验过。
                    pcall(function() tex:SetTexture(C_Spell.GetSpellTexture(artID)) end)
                    local sink = button:CreateTexture(nil, "BACKGROUND")
                    sink:SetSize(1, 1)
                    sink:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
                    sink:SetAlpha(0)
                    button:SetIcon(sink)
                else
                    button:SetIcon(tex)
                end
                tintIcon(tex, r, g, b)
                local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
                cd:SetAllPoints(tex); cd:SetReverse(true); cd:SetDrawEdge(true)
                button:SetDurationCooldown(cd)
                pcall(function()
                    local fs = cd:GetCountdownFontString()
                    if fs then fs:SetFont(select(1, fs:GetFont()) or STANDARD_TEXT_FONT, 16, "OUTLINE") end
                end)
                button:SetSize(W, H)
                -- ⛔ 不接 SetApplicationCount:那个 sink 会在同一次调用里同步写 FontString,
                --    字体没设好就是 "Font not set",而它会把整个初始化掀掉。
            end,
            layout = { elementSpacing = 0, elementWidth = W, elementHeight = H, layoutIndex = 1 },
        })
        return cc
    end)
    if not ok then
        Print("|cffff3333建格失败|r " .. tostring(name) .. ":" .. tostring(c))
        return nil
    end
    return c
end

-- ---- 红色 3 秒(echo)------------------------------------------------------
-- 🔑 为什么这里可以自己调 `Cooldown:SetCooldown`:它的限制是
--    `SecretArguments = "AllowedWhenUntainted"` —— 挡的是**插件喂 secret**,
--    不是"插件不许调"。我们喂 GetTime() 和 3.0,都是自己算的明文 ⇒ 合法。
local ECHO_LEN = 3.0
local echo = { frame = nil, cd = nil, fs = nil, flashTex = nil,
               endAt = 0, flash = 0, lastFire = 0 }

local function BuildEcho(slot)
    local f = CreateFrame("Frame", "DodoBoilingEcho", slot)
    f:SetAllPoints(slot)
    f:SetFrameLevel(slot:GetFrameLevel() + 20)     -- 盖在绿的上面

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", -1, 1)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pcall(function() tex:SetTexture(C_Spell.GetSpellTexture(ID.boil)) end)
    tintIcon(tex, 1, 0.25, 0.2)

    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints(tex); cd:SetReverse(true); cd:SetDrawEdge(true)
    pcall(function() cd:SetHideCountdownNumbers(true) end)   -- 数字自己画,要一位小数

    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("CENTER", f, "CENTER", 0, 0)

    local fl = f:CreateTexture(nil, "OVERLAY")
    fl:SetAllPoints(tex)
    fl:SetColorTexture(1, 1, 1, 1)
    fl:SetBlendMode("ADD")
    fl:SetAlpha(0)

    f:Hide()
    echo.frame, echo.cd, echo.fs, echo.flashTex = f, cd, fs, fl
end

local function EchoFire()
    if not echo.frame then return end
    local now = GetTime()
    -- 幂等:同一帧同一技能可能报两次 SUCCEEDED(2026-08-23 实测 434144 就报了两次)。
    if now - echo.lastFire < 0.1 then return end
    -- 已经在跑 = 被顶掉重排:待发那一发被逼着提前打出去了,新的重排 3 秒 ⇒ 闪一下。
    if echo.frame:IsShown() then echo.flash = 0.30 end
    echo.lastFire, echo.endAt = now, now + ECHO_LEN
    echo.landsAt = now + ECHO_LEN          -- 那一发自动血沸的落地时刻,给 GLOW_HIDE 判据用
    pcall(function() echo.cd:SetCooldown(now, ECHO_LEN) end)
    echo.frame:Show()
end

-- ---- 常驻状态机 ------------------------------------------------------------
-- 绿色那半靠容器自己活;红色这半没有任何光环可读、echo 落地也不发事件
-- ⇒ 必须有人盯着事件。三个信号全是明文:glow 亮/灭 + 我自己的施法。
local live = { armed = false, glowOffAt = nil, echoEndsAt = nil }
local liveFrame

local function LiveOn()
    if not liveFrame then
        liveFrame = CreateFrame("Frame")
        liveFrame:SetScript("OnEvent", function(_, ev, a1, _, a3)
            if ev == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
                if isBoil(a1) then live.armed = true end
            elseif ev == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
                if isBoil(a1) then
                    local now = GetTime()
                    -- 🔴 glow 灭掉有**三个**原因,不是两个(2026-08-23 Jerry 真机发现,
                    -- 并靠「echo 落地那一刻绿的 15 跟着消失」当场定案):
                    --   ① 你打出了高亮那一发   ② 15 秒自然过期
                    --   ③ **echo 那一发把新 proc 也吃掉了** —— 它自己又排了一个 3 秒,
                    --      而它**不发任何施法事件**(已实测)⇒ 只能靠这条 HIDE 认出来。
                    -- 判据:没人刚施过法 + 这一刻正好是某个待发 echo 的落地时刻。
                    local justCast  = (now - echo.lastFire) < 0.2
                    local atEchoEnd = echo.landsAt ~= nil and math.abs(now - echo.landsAt) < 0.3
                    live.armed, live.glowOffAt = false, now
                    if (not justCast) and atEchoEnd then
                        EchoFire()          -- 链条可以继续:新的 landsAt 由它自己刷
                    end
                end
            elseif ev == "UNIT_SPELLCAST_SUCCEEDED" then
                if isSecret(a1) or a1 ~= "player" then return end   -- 先证明 unit,再碰 spellID
                if not isBoil(a3) then return end
                if consumedBy(live) then
                    live.glowOffAt = nil
                    EchoFire()
                end
            end
        end)
    end
    resolveOverride()
    live.armed, live.glowOffAt = false, nil
    echo.landsAt = nil
    liveFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    liveFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    liveFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    -- 🔑 补一次同步:/reload 或战斗中登录时 proc 可能正亮着,而那条 GLOW_SHOW 早过去了。
    -- 事件会漏,这个查询不会 —— 它返回明文 bool。
    pcall(function()
        if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed(ID.boil) then
            live.armed = true
        end
    end)
end

local function LiveOff()
    if liveFrame then liveFrame:UnregisterAllEvents() end
    if echo.frame then echo.frame:Hide() end
    echo.endAt, echo.landsAt = 0, nil
end

-- ---- 每帧驱动:红盖绿 + 发光 -----------------------------------------------
-- 🔑 「绿现在亮着吗」**不能问容器** —— `AuraButton:IsShown()` 是 secret,
--    结构上问不出来。拿 `IsSpellOverlayed(血沸)` 当代理:明文 bool,
--    而且它跟 proc 严格同生共死(实测 glow 亮/灭就是 proc 起/落)。
local function ProcUp()
    local ok, v = pcall(function()
        return C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed(ID.boil)
    end)
    return (ok and v == true)
end

local function SetGlow(on)
    if boil.glowOn == on or not boil.slot then return end
    boil.glowOn = on
    -- 搬暴雪自己那套 proc 发光(Blizzard_CooldownViewer 就是这么给普通框体加的),
    -- 不自研:它对任意有 GetSize() 的框体成立,`.action` / `.bar` 都是 nil-safe。
    pcall(function()
        if not ActionButtonSpellAlertManager then return end
        if on then ActionButtonSpellAlertManager:ShowAlert(boil.slot)
        else       ActionButtonSpellAlertManager:HideAlert(boil.slot) end
    end)
end

local function RowUpdate(_, dt)
    local now = GetTime()
    local echoOn = echo.frame ~= nil and echo.endAt > now
    if echo.frame then
        if echoOn then
            if not echo.frame:IsShown() then echo.frame:Show() end
            echo.fs:SetText(("%.1f"):format(echo.endAt - now))
            if echo.flash > 0 then
                echo.flash = echo.flash - (dt or 0)
                echo.flashTex:SetAlpha(math.max(0, echo.flash / 0.30))
            end
        elseif echo.frame:IsShown() then
            echo.frame:Hide()
        end
    end
    -- 有红显红、没红有绿显绿;两种情况**都发光**(你定的)。
    local active = echoOn or ProcUp()
    SetGlow(active)
    -- 配置模式下即使没内容也留一点底色(0.35),好让人看得见这格占哪儿。
    if boil.bg then boil.bg:SetAlpha(active and 0.55 or (boil.config and 0.35 or 0)) end
end

-- ---- 建格 / 显隐 -----------------------------------------------------------
--
-- 🔴 位置**不是拖出来的**,是从大招排的锚点算出来的 ⇒ 挪 HUD、开关次要资源条、
-- 改 /dch cdh 图标大小,它都自己跟上。没有可拖 = 没有"存的位置跟当前布局对不上"这种状态。
local function Reposition()
    if not boil.slot then return end
    local anchor, y = nil, nil
    if ns.GetCdRowAnchor then anchor, y = ns.GetCdRowAnchor() end
    if not anchor then return end
    local w, h = slotGeom()
    boil.slot:SetSize(w, h)
    boil.slot:ClearAllPoints()
    boil.slot:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -4)
end

local function BuildSlot()
    if boil.slot then return true end
    if InCombatLockdown() then
        Print("|cffff3333战斗中不建框体|r —— 脱战再敲一次(受保护框体战斗中大概率被拒)。")
        return false
    end
    if not (ns.GetCdRowAnchor and ns.GetCdRowAnchor()) then
        Print("|cffff3333HUD 还没建好|r —— 稍等一下再敲。")
        return false
    end
    local w, h = slotGeom()
    local sf = CreateFrame("Frame", "DodoBoilingSlot", UIParent)
    sf:SetSize(w, h)

    -- 暗底只在这格**有内容**时画。位置照样钉死(反应速度靠的就是它不动),
    -- 但空着的时候整格是透明的 —— 「不占位」和「看不见」是两件事,
    -- 而只有后者是零代价的:让它不占位就得让**大招图标**跟着 proc 左右跳。
    local bg = sf:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(sf)
    bg:SetColorTexture(0, 0, 0, 0.55)
    bg:SetAlpha(0)
    boil.bg = bg

    boil.slot = sf
    boil.container = makeContainer(sf, "DodoBoilingBox", ID.proc, 0.3, 1, 0.3, ID.boil)
    if boil.container then
        boil.container:ClearAllPoints()
        boil.container:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, 0)
    end
    BuildEcho(sf)
    Reposition()

    -- 驱动挂在格子自己身上:它启用时一直显示(空着也占位),所以 OnUpdate 一定在跑。
    local acc = 0
    sf:SetScript("OnUpdate", function(self, dt)
        RowUpdate(self, dt)
        -- 布局可能被别处改(开关条 / 改图标大小 / 挪 HUD),每秒对一次位置。
        -- 事件驱动要赌"我知道所有会改布局的路径",而那个赌注验不了。
        acc = acc + (dt or 0)
        if acc >= 1 then acc = 0; Reposition() end
    end)
    sf:Hide()
    return true
end

-- auto = 这次是自动判定触发的(换专精 / 换天赋 / 开关大招排),不是人敲的命令。
-- 🔴 两件事都挂在它上面,而且**必须一起**:不吭声 + **不写存盘**。
-- 只做前者的话,自动收起会被记成"你手动关的" ⇒ 换回血 DK 也不再出现,
-- 而那个状态一旦写进 SavedVariables,重登也修不好 —— 得手敲命令才救得回来。
local function ShowSlot(auto)
    if not BuildSlot() then return end
    if not auto then slotDB().manualOff = nil end
    Reposition()
    boil.slot:Show()
    -- ⚠ 容器"收不收事件""什么时候重画"**都**挂在 IsVisible() 上 ⇒ 先 Show 再 SetEnabled。
    if boil.container then pcall(function() boil.container:SetEnabled(true) end) end
    -- 把大招排整体右移一格,腾出最左那格给我们。
    local w, _, sp = slotGeom()
    boil.pad = w + sp
    if ns.SetCdRowPad then pcall(ns.SetCdRowPad, boil.pad) end
    LiveOn()
    if not auto then
        emit("沸点格:|cff33ff33开|r —— 钉在大招存续排最左边,有 3 显红、没红有 15 显绿,都发光。")
        Print("  骨盾 / 符文剑 / 血后精华 走大招排本身:`/dch cd` 看现在有哪些。")
    end
end

local function HideSlot(auto)
    if not boil.slot then if not auto then emit("沸点格还没建。") end return end
    if not auto then slotDB().manualOff = true end
    LiveOff()
    SetGlow(false)
    if boil.container then pcall(function() boil.container:SetEnabled(false) end) end
    boil.slot:Hide()
    boil.pad = 0
    if ns.SetCdRowPad then pcall(ns.SetCdRowPad, 0) end
    if not auto then emit("沸点格:关(大招排移回最左)。手动关的话不会再自动出现,`/dch bp row` 开回来。") end
end

-- ---- 自动出现 --------------------------------------------------------------
-- 这一格不该要人敲命令。判据三条,任一不成立就不该占着大招排最左那格:
--   ① 没被手动关掉  ② 血 DK 且**点了沸点天赋**  ③ 大招排本身开着(不然没地方钉)
-- ⚠ 天赋那条不能省:没点沸点的血 DK 那格永远是空的,而"空着占位"在这儿是纯噪音 ——
--   它不是"该在的不在",是"压根不该有"。
local SPEC_BLOOD = 250

local function eligible()
    if slotDB().manualOff then return false end
    local db = _G.DodoCombatHUDDB
    if type(db) == "table" and db.cdsOn == false then return false end

    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    if type(getSpec) ~= "function" or type(getInfo) ~= "function" then return false end
    local ok, idx = pcall(getSpec)
    if not ok or not idx then return false end
    local ok2, id = pcall(getInfo, idx)
    if not ok2 or id ~= SPEC_BLOOD then return false end

    local ok3, known = pcall(IsPlayerSpell, ID.talent)
    return ok3 and known == true
end

local function Evaluate()
    local want = eligible()
    local shown = boil.slot ~= nil and boil.slot:IsShown()
    if want and not shown then ShowSlot(true)
    elseif (not want) and shown then HideSlot(true) end
end

-- 「它没出现」有七八个可能的断点,而从屏幕上看**全都长得一样**。
-- 这个命令把每一环单独打出来,一次问清楚,别再靠猜。
-- ---- 符文刃舞(Dance of Midnight)探针 --------------------------------------
--
-- 要答的是:**同时有几把符文刃舞**,有没有任何可读的载体。
-- 机制(SimC `set_max_pets(10)`):每消耗一个符文 ~12.5% 召一把,持续 8 秒,
-- **最多同时 10 把**。而玩家身上那个招架 buff **不叠** ——
-- SimC 里是 `if remains() < duration then trigger(duration)`,纯刷新。
-- ⇒ 数量不在光环里。12.x 还剩三条可能的通道,这个探针把它们一次全量掉:
--   ① 图腾槽 GetTotemInfo —— WoW 里**唯一**能枚举临时守护者的 API
--   ② 名条 C_NamePlate —— 能不能看见它们、能不能判归属
--   ③ 战斗日志 —— 以前所有"数守护者"插件都靠它。别的插件里实测过**注册被拒**,
--      这儿复核一次(便宜,而且"记得是这样"和"量过"是两回事)
-- 🔴 |cffff3333总结论(2026-08-23 实测四条通道,全死):|r
--    **符文刃舞同时有几把,在 12.x 上没有任何可读载体。**
--      ① 玩家光环   不叠(SimC 纯刷新)+ 战斗中 ContextuallySecret 读不到
--      ② 战斗日志   RegisterEvent 本身是 forbidden action(别再探,见下)
--      ③ 图腾槽     不占槽(画出来一直空)
--      ④ 名条       守护者不在列表里(归我的恒为 0)
--    ⇒ 这不是"我们做不到",是这一整类功能被 12.x 封了。以前的插件全靠 ②。
--    ⚠ 名字容易混:**符文刃舞 = Dancing Rune Weapon(49028)**,
--      **午夜舞步 = Dance of Midnight**(那个"消耗符文有几率召唤"的 apex 天赋)。
local DOM = { r1 = 1264568, r2 = 1264407, summon = 1264353, drw = 49028, parry = 81256 }
local domTimer, clFrame

local function domSample(tag)
    local n = tonumber(_G.MAX_TOTEMS) or 4
    local slots = {}
    for i = 1, n do
        local ok, have, nm, _, du = pcall(GetTotemInfo, i)
        slots[#slots+1] = ok and ("#%d[%s %s %s]"):format(i, describe(have), describe(nm), describe(du))
                             or ("#%d=ERROR"):format(i)
    end
    emit(("  %s 图腾槽(%d): %s"):format(tag, n, table.concat(slots, " ")))

    -- 名条:能看见几个、归属判得出来吗
    local plates, mine, ownerErr = 0, 0, nil
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, list = pcall(C_NamePlate.GetNamePlates)
        if ok and type(list) == "table" then
            plates = #list
            for _, np in ipairs(list) do
                local u = np and np.namePlateUnitToken
                if u then
                    local ok2, isMine = pcall(UnitIsOwnerOrControllerOfUnit, "player", u)
                    if not ok2 then ownerErr = "ERROR"
                    elseif isSecret(isMine) then ownerErr = "SECRET"
                    elseif isMine == true then mine = mine + 1 end
                end
            end
        end
    end
    emit(("  %s 名条: 共%d 归我的=%d 归属判定=%s"):format(tag, plates, mine, ownerErr or "明文"))
    emit(("  %s 光环 招架%d=%s | DoM-r1=%s | DoM-r2=%s"):format(
        tag, DOM.parry, auraState(DOM.parry), auraState(DOM.r1), auraState(DOM.r2)))
end

local function DomProbe()
    emit("---- 符文刃舞探针 ----")
    for _, k in ipairs({ "r1", "r2", "summon", "drw", "parry" }) do
        emit(("  %-6s %-8d 名=%s  AuraSecrecy=%s"):format(k, DOM[k],
            call(C_Spell.GetSpellName, DOM[k]),
            C_Secrets and secrecy(C_Secrets.GetSpellAuraSecrecy, DOM[k]) or "?"))
    end
    -- ③ 战斗日志:|cffff3333已定案,而且**永远别再探**|r。
    -- 2026-08-23 实测:`RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` 不是"注册了收不到",
    -- 是**调用本身被拒** —— 触发 ADDON_ACTION_FORBIDDEN,并把本插件标记进 BugGrabber
    -- 的 badAddons。⇒ 这个问题**不是免费的**:问一次的代价是插件被标记 + 报错刷屏。
    -- 🔴 canon「探针必须无害化」的一个新形态:以前那条讲的是"拆掉关卡去测会真写数据",
    --    这条是"**调用被测 API 本身就是违规动作**"。判据:
    --    要探的那个调用,失败方式是"返回错误"还是"触发保护"?后者不许探。
    emit("  战斗日志 = |cffff3333forbidden(2026-08-23 实测,别再探)|r ——")
    emit("    以前所有'数守护者'的插件都靠它,这条路整个没了。")

    domSample("[脱战]")
    emit("  |cffff3333现在打木桩,正常出手别停|r —— 20 秒内每 2 秒采一次,把符文刃舞刷出来。")
    if domTimer then pcall(function() domTimer:Cancel() end) end
    local n = 0
    if C_Timer.NewTicker then
        domTimer = C_Timer.NewTicker(2, function()
            n = n + 1
            domSample(("[%2ds]"):format(n * 2))
            if n >= 10 then
                pcall(function() domTimer:Cancel() end); domTimer = nil
                emit("---- 完。|cffff3333/reload|r 一次落盘,整段我去读 ----")
            end
        end)
    end
end

-- ---- 图腾槽可视探针 --------------------------------------------------------
-- 🔴 |cffff3333已定案(2026-08-23,12.1.0 build 69404):符文刃舞**不占图腾槽**。|r
--    战斗中 GetTotemInfo 返回 secret(不是 nil/ERROR)⇒ 读不了但也许画得出;
--    画出来 = **一直全空**,武器出着也没有 ⇒ 它们根本不在槽里。
--    (这条依赖一个已证的前提:FontString:SetText 会把 secret 真渲染出来。)
--    **留着这个命令**是因为下个补丁要重量一次 —— 结论会过期,方法不会。
-- 战斗中图腾槽**返回 secret**(不是 nil、不是 ERROR)⇒ 按总钥匙:读不了,但也许画得出。
-- 而「符文刃舞占不占图腾槽」这个问题,secret 恰好把答案挡住了 —— **只能画出来用眼睛看**。
--
-- 🔴 只用 `FontString:SetText`:它是 AllowedWhenTainted 里少数几个真能吃 secret 的。
--   ⛔ `Cooldown:SetCooldown` 不行(AllowedWhenUntainted,插件喂 secret 直接 ERROR)
--   ⛔ 想画倒计时更不行:GetTotemInfo 给的是 start + duration,算剩余要做**算术**,
--      而对 secret 做算术就是崩。⇒ 极限就是"把名字打出来",看得出有几个、看不出还剩多久。
local totemBox
local function TotemProbe()
    if totemBox then
        totemBox:SetShown(not totemBox:IsShown())
        emit("图腾槽可视探针:" .. (totemBox:IsShown() and "开" or "关"))
        return
    end
    if InCombatLockdown() then Print("|cffff3333脱战再敲|r(要建框体)。") return end
    local n = tonumber(_G.MAX_TOTEMS) or 4
    local h = CreateFrame("Frame", "DodoTotemProbe", UIParent, "BackdropTemplate")
    h:SetSize(120, 22 * n + 22)
    h:SetPoint("CENTER", UIParent, "CENTER", -320, 0)
    h:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
    h:SetBackdropColor(0, 0, 0, 0.6)
    h:SetMovable(true); h:EnableMouse(true); h:RegisterForDrag("LeftButton")
    h:SetScript("OnDragStart", function(f) f:StartMoving() end)
    h:SetScript("OnDragStop", function(f) f:StopMovingOrSizing() end)

    local title = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 6, -4)
    title:SetText("|cffffcc00图腾槽(有字=有东西)|r")

    local rows = {}
    for i = 1, n do
        local fs = h:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", 6, -4 - 22 * i)
        fs:SetJustifyH("LEFT")
        fs:SetText(i .. ":")
        rows[i] = fs
    end
    h:SetScript("OnUpdate", function()
        for i = 1, n do
            -- 🔴 name 可能是 secret ⇒ **直接递给 SetText,一个字都不许碰**
            --   (不比较、不拼接、不 tostring —— 任何一样都是崩)。
            local ok, _, nm = pcall(GetTotemInfo, i)
            if ok then pcall(function() rows[i]:SetText(nm) end)
            else pcall(function() rows[i]:SetText("ERR") end) end
        end
    end)
    totemBox = h
    emit("图腾槽可视探针:开。左边那个框,**有字的行 = 那个槽里有东西**。")
    Print("  去打木桩把符文刃舞刷出来 —— 有行冒字 ⇒ 它占图腾槽,这条路能做;")
    Print("  一直全空 ⇒ 不占,那数量在 12.x 就是**彻底没有可读载体**。再敲一次关掉。")
end

local function Why()
    emit("---- 沸点格为什么没出现 ----")
    local db = _G.DodoCombatHUDDB
    emit("  ① 被手动关过? manualOff = " .. tostring(slotDB().manualOff) .. "  (nil/false = 没关过)")
    emit("  ② 自身增益排开着 cdsOn   = " .. tostring(type(db)=="table" and db.cdsOn))
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    emit(("  ③ 专精 API getSpec=%s getInfo=%s"):format(type(getSpec), type(getInfo)))
    local sid
    if type(getSpec)=="function" and type(getInfo)=="function" then
        local ok, idx = pcall(getSpec)
        if ok and idx then local ok2, id = pcall(getInfo, idx); if ok2 then sid = id end end
    end
    emit(("     专精 = %s(血 DK 要 %d)"):format(describe(sid), SPEC_BLOOD))
    emit("  ④ 沸点天赋 IsPlayerSpell(" .. ID.talent .. ") = " .. call(IsPlayerSpell, ID.talent))
    emit("  ⇒ |cffffff00eligible() = " .. tostring(eligible()) .. "|r")
    emit("  ⑤ 战斗中 = " .. tostring(InCombatLockdown()))
    local anchorOK = false
    if ns.GetCdRowAnchor then local a = ns.GetCdRowAnchor(); anchorOK = (a ~= nil) end
    emit(("  ⑥ 自身增益排的锚 GetCdRowAnchor 有=%s 取得到=%s"):format(
        tostring(ns.GetCdRowAnchor ~= nil), tostring(anchorOK)))
    emit(("  ⑦ 格子建了=%s  显示中=%s"):format(
        tostring(boil.slot ~= nil),
        tostring(boil.slot ~= nil and boil.slot:IsShown())))
    emit(("  ⑧ 容器建了=%s   推给排的留白 pad=%s   SetCdRowPad 有=%s"):format(
        tostring(boil.container ~= nil), tostring(boil.pad), tostring(ns.SetCdRowPad ~= nil)))
    if ns.AuraList and type(db) == "table" then
        local ok, list = pcall(ns.AuraList, db, "cds", sid)
        if ok and type(list) == "table" then
            emit("  ⑨ 自身增益排现在这几个:" .. table.concat(list, " "))
        end
    end
    emit("---- 完,整段发我 ----")
end
ns.BoilingWhy = Why

local auto = CreateFrame("Frame")
auto:SetScript("OnEvent", function()
    -- 延后跑:HUD 的条也是 PLAYER_LOGIN 才建的,抢在它前面 GetCdRowAnchor 返回 nil
    -- ⇒ 那格建不出来,而且**不会自己重试** —— 所以每个触发点都延后一拍。
    C_Timer.After(1, Evaluate)
end)
for _, ev in ipairs({
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED",
    "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE",
    "PLAYER_REGEN_ENABLED",   -- 战斗中拒建过的,脱战补上
}) do
    -- 逐个 pcall:某个补丁把事件改名了的话,只该少一个触发点,
    -- 不该让整个文件在加载期抛出去(那会让**整个插件**没加载,而症状是"HUD 全没了")。
    pcall(function() auto:RegisterEvent(ev) end)
end
ns.BoilingEvaluate = Evaluate   -- 给 Options / 自身增益排开关用

-- ── 给 ESC 面板用(0.13)────────────────────────────────────────
-- 🔴 面板**不许自己读写存档里那个键**。存的是 `manualOff`(缺席 = 开)而不是 `on`,
--    理由见上面 slotDB 那段;面板那边要是照直觉写一个 `on`,两份判据当场分叉,
--    而症状是「勾选框和屏幕上那格对不上」—— 谁也看不出来是两个键。
--    ⇒ 只暴露动作,不暴露键名。
-- 配置模式:把那格的暗底点亮,好让人看得见它占的位置。
-- ⚠ **只置标志,不自己画** —— RowUpdate 每帧都在跑,alpha 归它算(它同时知道
--   现在有没有 proc / echo)。在这儿也写一遍就是两份实现,而且第一版真栽了:
--   我照抄了 RowUpdate 里的条件 `not (echoOn or ProcUp())`,而 `echoOn` 是**那个函数
--   里的局部变量** ⇒ 在模块层读到的是个全局 nil,条件恒等于 `not ProcUp()`。
--   `luac -p` 挑不出来(读全局是合法 Lua),而症状只会是 alpha 偶尔不对。
-- ⚠ 也不碰 boil.slot 的显隐:那归 Evaluate 管,多一条判据 = 退出配置模式那格可能就没了。
ns.BoilingSetConfig = function(on)
    boil.config = on and true or false
end
ns.BoilingSlotOn  = function() return not slotDB().manualOff end
ns.BoilingSetSlot = function(v)
    -- 走的是跟 `/dch bp row` 完全同一段代码(手动路径:会吭声、会写盘)。
    if v then ShowSlot(false) else HideSlot(false) end
end
-- 「这个角色现在够不够格显示它」—— 面板拿它决定那个勾选框画不画灰。
-- 🔴 画灰必须**同时说出为什么**:一个点不动又不解释的控件读起来像"坏了"。
ns.BoilingEligible = function()
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    if type(getSpec) ~= "function" or type(getInfo) ~= "function" then return false, "问不出专精" end
    local ok, idx = pcall(getSpec)
    if not ok or not idx then return false, "问不出专精" end
    local ok2, id = pcall(getInfo, idx)
    if not ok2 then return false, "问不出专精" end
    if id ~= SPEC_BLOOD then return false, "只有血 DK 有这一格" end
    local ok3, known = pcall(IsPlayerSpell, ID.talent)
    if not (ok3 and known == true) then return false, "没点「沸点」天赋" end
    return true
end

-- ---------------------------------------------------------------- 入口
-- /dch bp why         沸点格为什么没出现:把每一环单独打出来
-- /dch bp drw         符文刃舞:数量有没有任何可读的载体(图腾槽/名条/战斗日志)
-- /dch bp totem       图腾槽可视探针:secret 读不了,画出来用眼睛看
-- /dch bp row [off]   手动开 / 关那一格(自动判定管不着时用)
-- /dch bp             探针:录到抓够 3 个完整周期
-- /dch bp expire [n]  探针:放生模式,抓自然过期
-- /dch bp now         探针:只跑静态问答
-- /dch bp stop        探针:立刻收工出报告
function ns.BoilingProbe(arg)
    arg = string.lower(tostring(arg or "")):gsub("^%s+", ""):gsub("%s+$", "")

    if arg == "why" then Why() return end
    if arg == "drw" then DomProbe() return end
    if arg == "totem" then TotemProbe() return end
    if arg == "row" or arg == "slot" then ShowSlot() return end
    local r = arg:match("^row%s+(%S+)$")
    if r then
        if r == "off" then HideSlot() return end
        Print("不认识 row 的这个参数:" .. r .. "  (只有 off)")
        return
    end

    if arg == "stop" then
        if rec and rec.on then Stop("你叫停的") else emit("没在录。") end
        return
    end
    if arg == "now" then Static() return end

    local mode
    local n = arg:match("^expire%s*(%d*)$")
    if n then mode, arg = "expire", (n ~= "" and n or "2") end
    local want = tonumber(arg) or 3
    if want < 1 then want = 1 elseif want > 20 then want = 20 end
    Start(want, mode)
end
