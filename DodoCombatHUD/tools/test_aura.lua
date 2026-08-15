-- 离线测 AuraSets.lua 的纯函数 + 内置表的结构约束。跑法:lua tools/test_aura.lua(插件根目录)
-- 加载真文件,不手抄一份 —— 手抄的那份会跟 bug 共享同一个误解。
local ns = {}
assert(loadfile("AuraSets.lua"))("DodoCombatHUD", ns)

local pass, fail = 0, 0
local function check(label, got, want)
    if got == want then pass = pass + 1
    else fail = fail + 1
        print(("  FAIL %s: got %s want %s"):format(label, tostring(got), tostring(want))) end
end

-- 反空转:文件真被加载了才继续,否则下面全是 nil == nil 的假绿
assert(type(ns.AuraList) == "function" and type(ns.SPEC_DOTS) == "table"
       and type(ns.SPEC_CDS) == "table", "AuraSets.lua 没加载成功,后面的绿全是空转")

print("== 内置表的结构约束 ==")
-- DoT 那排是固定格位、容器按 DOT_SLOTS 预建 ⇒ 超出的格子**画不出来**,而且不报错
local over = 0
for spec, list in pairs(ns.SPEC_DOTS) do
    if #list > ns.DOT_SLOTS then
        over = over + 1
        print(("     spec %d 有 %d 个 DoT,超过 DOT_SLOTS=%d"):format(spec, #list, ns.DOT_SLOTS))
    end
end
check("没有专精的 DoT 数超过 DOT_SLOTS", over, 0)

-- 两张按专精的表必须覆盖同一批专精:漏一个的症状是"换到那个专精整排空",
-- 而它跟"这专精本来就没有"分不开
local missing = 0
for spec in pairs(ns.SPEC_DOTS) do if ns.SPEC_CDS[spec] == nil then missing = missing + 1 end end
for spec in pairs(ns.SPEC_CDS) do if ns.SPEC_DOTS[spec] == nil then missing = missing + 1 end end
check("两张表的专精集一致", missing, 0)

-- specID 写重了 = 后一条静默盖掉前一条
local seen, dup = {}, 0
for _, id in pairs(ns.SPEC) do
    if seen[id] then dup = dup + 1 end
    seen[id] = true
end
check("SPEC 常量没有重复的 specID", dup, 0)

-- ID 打错成字符串 / 0 / 负数会静默筛不到任何东西
local bad = 0
for _, tbl in ipairs({ ns.SPEC_DOTS, ns.SPEC_CDS }) do
    for _, list in pairs(tbl) do
        for _, id in ipairs(list) do
            if type(id) ~= "number" or id <= 0 or id ~= math.floor(id) then bad = bad + 1 end
        end
    end
end
for _, list in ipairs({ ns.LUST, ns.RAID }) do
    for _, id in ipairs(list) do
        if type(id) ~= "number" or id <= 0 or id ~= math.floor(id) then bad = bad + 1 end
    end
end
check("所有 spellID 都是正整数", bad, 0)

print("== AuraList:没配过 → 内置表 ==")
local shadow = 258
local l, custom = ns.AuraList(nil, "dots", shadow)
check("暗牧内置三格", #l, 3)
check("custom=false", custom, false)
check("第一格 = 吸血鬼之触", l[1], 34914)

print("== AuraList 返回的是拷贝,不是内置表本身 ==")
-- 返回引用的话,调用方一 ListAdd 就**把内置表改了**,而且是所有角色共享、下次读还带着
ns.ListAdd(l, 999999)
local l2 = ns.AuraList(nil, "dots", shadow)
check("改返回值不污染内置表", #l2, 3)

print("== AuraList:配过 → 玩家的桶 ==")
local saved = {}
ns.SetAuraList(saved, "dots", shadow, { 111, 222 })
local l3, c3 = ns.AuraList(saved, "dots", shadow)
check("拿到玩家那份", #l3, 2)
check("custom=true", c3, true)
check("别的专精仍走内置", #(ns.AuraList(saved, "dots", 267)), 1)   -- 毁灭术 = Immolate 一个

print("== 玩家把一排删空:必须留空,不许回落内置 ==")
-- 判据是"桶存不存在"不是"桶空不空"。按后者写的话,他删空 → 下次登录又长回来,
-- 而「设置自己会变」是最难查的一类
ns.SetAuraList(saved, "dots", shadow, {})
local l4, c4 = ns.AuraList(saved, "dots", shadow)
check("空列表", #l4, 0)
check("仍算 custom", c4, true)

print("== ResetAuraList:回内置 ==")
ns.ResetAuraList(saved, "dots", shadow)
local l5, c5 = ns.AuraList(saved, "dots", shadow)
check("回到内置三格", #l5, 3)
check("custom=false", c5, false)

print("== 全局那两排(嗜血 / 团队增益)不吃 specID ==")
local lust, lc = ns.AuraList(nil, "lust", nil)
check("嗜血内置七个", #lust, 7)
check("custom=false", lc, false)
ns.SetAuraList(saved, "lust", nil, {})
local lust2, lc2 = ns.AuraList(saved, "lust", nil)
check("删空后留空", #lust2, 0)
check("仍算 custom", lc2, true)
ns.ResetAuraList(saved, "lust", nil)
check("reset 回内置", #(ns.AuraList(saved, "lust", nil)), 7)

print("== specID 为 nil:按专精那两排必须早退,不许拿 nil 当键 ==")
-- `t[nil] = v` 是硬错误。不早退的话它会从 slash 命令里冒出来,玩家看到一串红字堆栈,
-- 而根因(问不出专精)一个字都没提。
local s2 = {}
local okSet = pcall(function() return ns.SetAuraList(s2, "dots", nil, { 1 }) end)
check("SetAuraList 不炸", okSet, true)
check("而且如实返回 false", ns.SetAuraList(s2, "dots", nil, { 1 }), false)
check("没往存档里写", s2.dots, nil)
local okReset = pcall(function() return ns.ResetAuraList(s2, "dots", nil) end)
check("ResetAuraList 不炸", okReset, true)
check("如实返回 false", ns.ResetAuraList(s2, "dots", nil), false)
-- 全局那两排不吃 specID ⇒ nil 完全合法,照写
check("全局排 nil specID 照写", ns.SetAuraList(s2, "raid", nil, { 5 }), true)
check("写进去了", s2.raid[1], 5)

print("== ListAdd / ListRemove ==")
local t = { 1, 2 }
check("加新的", ns.ListAdd(t, 3), true)
check("重复不加", ns.ListAdd(t, 2), false)
check("长度 3", #t, 3)
check("删掉在的", ns.ListRemove(t, 2), true)
check("删不在的", ns.ListRemove(t, 99), false)
check("长度 2", #t, 2)

print("== 迁移:扁平数组 → 按专精分桶 ==")
local old = { dots = { 34914, 589, 335467 } }
check("确实迁了", ns.MigrateDotsToBuckets(old, shadow), true)
check("老形状没了", rawget(old.dots, 1), nil)
check("进了暗牧那桶", #old.dots[shadow], 3)
check("幂等:第二遍不动", ns.MigrateDotsToBuckets(old, shadow), false)

print("== 迁移:拿不到 specID 就丢掉(回落内置零损失)==")
local old2 = { dots = { 1, 2, 3 } }
check("仍算迁过", ns.MigrateDotsToBuckets(old2, nil), true)
check("桶是空的", next(old2.dots), nil)
check("于是读回内置", #(ns.AuraList(old2, "dots", shadow)), 3)

print("== 迁移:已经是分桶形状的不许动 ==")
local newshape = { dots = { [shadow] = { 111 } } }
check("不迁", ns.MigrateDotsToBuckets(newshape, shadow), false)
check("原样", newshape.dots[shadow][1], 111)

print("== 负对照:老数组要是**没**迁,暗牧的 ID 会带到别的专精身上 ==")
-- 这就是不迁的真实后果 —— 不是"丢设置",是骑士那排永远空着且自愈不了
local unmigrated = { dots = { 34914, 589, 335467 } }
local asPal = unmigrated.dots[SPEC_PAL] or unmigrated.dots[70]
check("不迁时骑士桶读出来是 nil(⇒ 得靠迁移兜住)", asPal, nil)

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
