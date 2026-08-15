-- DodoCombatHUD - Resource.lua
-- 多职业资源条的**纯逻辑**:哪些资源要画、画成几格、每格填多少、什么颜色。
-- 🔑 这个文件**一个框体都不建、一点状态都不存** ⇒ 能离线跑(tools/test_resource.lua)。
--    框体 / 布局 / 驱动全在 DodoCombatHUD.lua。分开是为了让算法那一半能被测试够得着。
--
-- 🔴 分档依据(2026-08-15 /dp 实测,canon rules/wow-addons.md 有全表):
--    `C_Secrets.GetPowerTypeSecrecy` 说 —— **离散资源全是 `Never`(明文,可读可算)**,
--    连续主资源是 `Ctx`(战斗中拿不到明文,只能喂进控件让它自己画)。
--    ⇒ 下面 DISCRETE 那批可以随便算;连续那批一个数都别读。

local ADDON, ns = ...
ns = ns or {}

-- ── 哪些资源画成「N 格」──────────────────────────────────────
-- 判据不是「数值小」,是**游戏把它当颗粒**:玩家心里数的是「几颗」不是「百分之几」。
-- ⚠ 星能(LunarPower)/ 漩涡(Maelstrom)看着像资源点,其实是 0..100 的连续量,不在这。
-- ⚠ 顺序表是**唯一来源**,下面那个集合从它推出来 —— 两份手写清单必然会漂,
--   而漂了以后没有任何单点读得出来(canon rules/engineering.md)。
-- 要有序是因为探测时按它逐个试:虽然目前每个专精最多只有一个离散资源
--   (猫德 = 连击点、惩戒 = 圣能、毁灭 = 碎片、DK = 符文…),但 `pairs` 顺序不确定,
--   哪天真出现两个,行为就成了随机的 —— 那种 bug 每次登录表现还不一样。
ns.DISCRETE_ORDER = {
    "ComboPoints", "HolyPower", "SoulShards", "Chi", "ArcaneCharges", "Runes", "Essence",
}
ns.DISCRETE = {}
for _, n in ipairs(ns.DISCRETE_ORDER) do ns.DISCRETE[n] = true end

-- ⛔ 探测「本专精有哪些资源」时必须排掉这两个:它们的 max 也是 100 且**几乎总在**
--    (2026-08-15 实测,暗牧身上就有),按「max > 0」判会把它们当成真资源画出来。
ns.EXCLUDE = { AlternateQuest = true, AlternateEncounter = true, Alternate = true }

-- ── 配色 ────────────────────────────────────────────────────
-- 🔴 **故意不用 `PowerBarColor`**(官方表)。官方色是给暴雪那种带厚金属边框 + 不透明底的
--    框体调的,搬到一根裸条上会糊 —— 疯狂条就是这么从官方 atlas 退回素图 + 自选亮紫的
--    (理由见 DodoCombatHUD.lua 的 DEFAULTS.powerTexture)。
--    这里是自己调的:统一往「暗场景里跳得出来」的方向偏。
-- 顺序:玩家可覆盖(DB.powerColors[name]) > 本表 > PowerBarColor > 灰。
ns.COLORS = {
    -- 连续主资源
    Mana          = { 0.25, 0.55, 1.00 },
    Rage          = { 1.00, 0.25, 0.25 },
    Focus         = { 1.00, 0.60, 0.30 },
    Energy        = { 1.00, 0.92, 0.35 },
    RunicPower    = { 0.35, 0.75, 1.00 },
    Insanity      = { 0.72, 0.42, 1.00 },   -- 跟原疯狂条默认色一致,别动
    Fury          = { 0.85, 0.35, 0.95 },
    Pain          = { 1.00, 0.55, 0.20 },
    LunarPower    = { 0.55, 0.60, 1.00 },
    Maelstrom     = { 0.30, 0.80, 0.95 },
    -- 离散(分段)
    ComboPoints   = { 1.00, 0.40, 0.30 },
    HolyPower     = { 1.00, 0.88, 0.40 },
    SoulShards    = { 0.70, 0.45, 0.95 },
    Chi           = { 0.45, 0.95, 0.80 },
    ArcaneCharges = { 0.65, 0.55, 1.00 },
    Runes         = { 0.45, 0.80, 1.00 },
    Essence       = { 0.40, 0.85, 0.90 },
}

ns.FALLBACK_COLOR = { 0.60, 0.60, 0.65 }

-- ── 纯函数(以下全部可离线测)────────────────────────────────

-- 颜色优先级:玩家覆盖 > 本表 > 官方 PowerBarColor > 灰。
-- ⚠ 两张表的 key 不一样:我们用 Enum 名(SoulShards),官方用 token(SOUL_SHARDS)。
--   token 由 UnitPowerType 给,所以两个都要传进来。
function ns.ColorFor(name, token, overrides)
    local c = overrides and name and overrides[name]
    if type(c) == "table" and type(c[1]) == "number" then return c end
    c = name and ns.COLORS[name]
    if c then return c end
    local pbc = _G.PowerBarColor and token and _G.PowerBarColor[token]
    if type(pbc) == "table" and type(pbc.r) == "number" then
        return { pbc.r, pbc.g, pbc.b }
    end
    return ns.FALLBACK_COLOR
end

-- 精确资源值:离散资源要用 unmodified 的原始值除以 displayMod 才有小数。
-- 毁灭术碎片就是这条 —— raw 0..50 / mod 10 = 0..5.0,「每颗豆带进度」的全部秘密。
-- 其余离散资源 mod = 1,这一步等于原样返回。
function ns.ExactValue(raw, mod)
    if type(raw) ~= "number" then return nil end
    if type(mod) ~= "number" or mod <= 0 then mod = 1 end
    return raw / mod
end

-- 第 i 格该填多少(0..1)。exact = 3.5 ⇒ 1,2,3 格满、第 4 格半、第 5 格空。
-- 🔑 这一个函数同时管住了「整数颗粒」和「毁灭术带进度」两种 —— 不需要为后者写分支。
function ns.SegmentFill(exact, i)
    if type(exact) ~= "number" or type(i) ~= "number" then return 0 end
    local f = exact - (i - 1)
    if f <= 0 then return 0 end
    if f >= 1 then return 1 end
    return f
end

-- N 格平分总宽,**加起来仍然等于原来那根条的总长**(段间缝也算在内)。
function ns.SegmentGeometry(total, n, gap)
    if type(n) ~= "number" or n < 1 then return 0 end
    gap = (type(gap) == "number" and gap >= 0) and gap or 0
    local w = (total - gap * (n - 1)) / n
    if w < 1 then w = 1 end   -- 格子太多时别算出 0 / 负数,那会让整条消失
    return w
end

-- 符文专用:每格有**自己的冷却**,所以不能用 SegmentFill。
-- 就绪的排前面填满,冷却中的按**剩余时间**升序排在后面、按进度部分填充
-- ⇒ 屏幕上永远是「谁先好谁在前」。(形状对照 VinkyDev/VFlow 的 BuildRuneSegmentState。)
-- runes = { {ready=bool, start=num, duration=num}, ... }(全明文,GetRuneCooldown 零 secret 标注)
function ns.RuneFills(runes, now)
    local fills, cd = {}, {}
    for i = 1, #runes do
        local r = runes[i] or {}
        if r.ready then
            fills[#fills + 1] = 1
        else
            local frac, remaining = 0, math.huge
            if type(r.start) == "number" and type(r.duration) == "number" and r.duration > 0 then
                local elapsed = (now or 0) - r.start
                if elapsed < 0 then elapsed = 0 end
                frac = elapsed / r.duration
                if frac > 1 then frac = 1 end
                remaining = r.duration - elapsed
                if remaining < 0 then remaining = 0 end
            end
            cd[#cd + 1] = { frac = frac, remaining = remaining, slot = i }
        end
    end
    -- ⚠ 平手时按槽位兜底,**排序必须稳定** —— 否则两个剩余时间相同的符文会每帧换位置,
    --   屏幕上是一排在抖的格子,而那看起来像渲染 bug 不像排序问题。
    table.sort(cd, function(a, b)
        if a.remaining ~= b.remaining then return a.remaining < b.remaining end
        return a.slot < b.slot
    end)
    for i = 1, #cd do fills[#fills + 1] = cd[i].frac end
    return fills
end
