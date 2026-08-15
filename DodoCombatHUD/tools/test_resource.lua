-- 离线测 Resource.lua 的纯函数。跑法:lua tools/test_resource.lua(在插件根目录)
-- 加载真文件,不手抄一份 —— 手抄的那份会跟 bug 共享同一个误解。
local ns = {}
assert(loadfile("Resource.lua"))("DodoCombatHUD", ns)

local pass, fail = 0, 0
local function check(label, got, want, eps)
    local ok
    if eps and type(got) == "number" and type(want) == "number" then
        ok = math.abs(got - want) <= eps
    else
        ok = (got == want)
    end
    if ok then pass = pass + 1
    else fail = fail + 1; print(("  FAIL %s: got %s want %s"):format(label, tostring(got), tostring(want))) end
end

-- 反空转:文件真被加载了才继续,否则下面全是 nil == nil 的假绿
assert(type(ns.SegmentFill) == "function" and type(ns.COLORS) == "table",
       "Resource.lua 没加载成功,后面的绿全是空转")

print("== SegmentFill:整数颗粒(圣能 3/5)==")
for i, want in ipairs({ 1, 1, 1, 0, 0 }) do check("seg" .. i, ns.SegmentFill(3, i), want) end

print("== SegmentFill:毁灭术 3.5 颗碎片 ==")
for i, want in ipairs({ 1, 1, 1, 0.5, 0 }) do check("seg" .. i, ns.SegmentFill(3.5, i), want, 1e-9) end

print("== SegmentFill:边界 ==")
check("空", ns.SegmentFill(0, 1), 0)
check("满", ns.SegmentFill(5, 5), 1)
check("超出不溢出", ns.SegmentFill(99, 1), 1)
check("负值当空", ns.SegmentFill(-3, 1), 0)
check("nil 不炸", ns.SegmentFill(nil, 1), 0)

print("== ExactValue:碎片 raw/mod ==")
check("35/10", ns.ExactValue(35, 10), 3.5, 1e-9)
check("mod=1 原样", ns.ExactValue(3, 1), 3)
check("mod=0 当 1(别除零)", ns.ExactValue(3, 0), 3)
check("nil 进 nil 出", ns.ExactValue(nil, 10), nil)

print("== SegmentGeometry:总宽守恒(用户要求:N 段加起来还是那个总长)==")
for _, case in ipairs({ { 260, 5, 2 }, { 260, 6, 3 }, { 100, 3, 0 }, { 260, 1, 4 } }) do
    local total, n, gap = case[1], case[2], case[3]
    local w = ns.SegmentGeometry(total, n, gap)
    check(("总宽 total=%d n=%d gap=%d"):format(total, n, gap), n * w + (n - 1) * gap, total, 1e-9)
end
check("段数为 0 不炸", ns.SegmentGeometry(260, 0, 2), 0)
check("格子太多时不给负宽", ns.SegmentGeometry(10, 50, 5) >= 1, true)

print("== RuneFills:就绪的排前面,冷却的按剩余时间 ==")
local now = 1000
local runes = {
    { ready = false, start = now - 2, duration = 10 },  -- 剩 8, frac .2
    { ready = true },
    { ready = false, start = now - 9, duration = 10 },  -- 剩 1, frac .9
    { ready = true },
    { ready = false, start = now - 5, duration = 10 },  -- 剩 5, frac .5
    { ready = true },
}
local f = ns.RuneFills(runes, now)
check("格数", #f, 6)
check("前 3 格是就绪的", f[1] == 1 and f[2] == 1 and f[3] == 1, true)
check("第 4 格 = 快好的那个(.9)", f[4], 0.9, 1e-9)
check("第 5 格 (.5)", f[5], 0.5, 1e-9)
check("第 6 格 = 最久的(.2)", f[6], 0.2, 1e-9)

print("== RuneFills:平手必须稳定(否则屏幕上一排格子在抖)==")
-- 🔴 这组数据是**换过一次**的。第一版三个符文 duration 全一样 ⇒ 平手时 frac 也一样
--    ⇒ 顺序怎么变 fills 都是 {.3,.3,.3},**这个量对乱序完全免疫**(A/B 实测:把
--    tiebreak 拆掉,测试照样全绿)。改成「remaining 相同但 frac 不同」,顺序才读得出来。
local tie = {
    { ready = false, start = now - 3,  duration = 10 },  -- 剩 7,frac .30
    { ready = false, start = now - 13, duration = 20 },  -- 剩 7,frac .65
    { ready = false, start = now - 21, duration = 28 },  -- 剩 7,frac .75
}
local t = ns.RuneFills(tie, now)
check("平手按槽位排:第1格", t[1], 0.30, 1e-9)
check("平手按槽位排:第2格", t[2], 0.65, 1e-9)
check("平手按槽位排:第3格", t[3], 0.75, 1e-9)
local a, b = ns.RuneFills(tie, now), ns.RuneFills(tie, now)
check("两次调用结果一致", a[1] == b[1] and a[2] == b[2] and a[3] == b[3], true)

print("== ColorFor 优先级 ==")
check("玩家覆盖赢", ns.ColorFor("Mana", "MANA", { Mana = { 1, 0, 0 } })[1], 1)
check("本表次之", ns.ColorFor("Insanity", "INSANITY", nil)[1], 0.72, 1e-9)
check("没见过的回落成灰", ns.ColorFor("NoSuchPower", "NO_SUCH", nil)[1], ns.FALLBACK_COLOR[1])
check("疯狂色跟原默认一致", ns.COLORS.Insanity[3], 1.00)

print("== 分档表 ==")
check("碎片是离散", ns.DISCRETE.SoulShards, true)
check("圣能是离散", ns.DISCRETE.HolyPower, true)
check("法力不是离散", ns.DISCRETE.Mana, nil)
check("星能不是离散(它是 0..100 连续量)", ns.DISCRETE.LunarPower, nil)
check("AlternateQuest 被排除", ns.EXCLUDE.AlternateQuest, true)

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
