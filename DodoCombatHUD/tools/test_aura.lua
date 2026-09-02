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

-- ── CD_STACK_STYLE(0.13.5「当资源看」的叠层 buff)────────────────────
-- ① 名单里的 ID 必须真的被某个专精用着。填了个没人用的 ID = 样式永远不生效,
--    而「名单里写着」读起来跟「做好了」一模一样 —— 屏幕上看不出差别(那格根本不出现)。
check("CD_STACK_STYLE 是表", type(ns.CD_STACK_STYLE), "table")
local orphan, styled = 0, 0
for id in pairs(ns.CD_STACK_STYLE or {}) do
    styled = styled + 1
    local used = false
    for _, list in pairs(ns.SPEC_CDS) do
        for _, sid in ipairs(list) do if sid == id then used = true break end end
        if used then break end
    end
    if not used then orphan = orphan + 1; print(("     %d 不在任何 SPEC_CDS 列表里"):format(id)) end
end
check("CD_STACK_STYLE 里没有孤儿 ID", orphan, 0)
check("CD_STACK_STYLE 非空(空了就是这功能被人删干净了)", styled > 0, true)

-- ② 漩涡武器必须**排第一** = 固定在左一。0.13 的规矩是「第 N 个 ID 永远在第 N 格」⇒
--    有人往前面插一个 ID,它就静默挪到第二格,而**屏幕上完全看不出这是 bug**
--    (那格照常显示,只是位置不对)。这条断言是唯一会替它开火的东西。
check("漩涡武器(344179)在增强萨的第一位 = 左一", ns.SPEC_CDS[ns.SPEC.SHA_ENH][1], 344179)
check("漩涡武器进了 CD_STACK_STYLE", ns.CD_STACK_STYLE[344179], true)

-- ── 升腾:三个专精**三个不同的 spellID**(元素 114050 / 增强 114051 / 恢复 114052)──
-- 抄错的典型形状 = 复制上一行忘了改号 ⇒ 那格**永远空着**,而它跟「没点这个天赋」
-- 在屏幕上分不开(两者都是空格子)。这条断言是唯一能把两者分开的东西。
local ASCENDANCE = {
    [ns.SPEC.SHA_ELE] = 114050,
    [ns.SPEC.SHA_ENH] = 114051,
    [ns.SPEC.SHA_RES] = 114052,
}
local ascWrong = 0
for spec, want in pairs(ASCENDANCE) do
    local got
    for _, id in ipairs(ns.SPEC_CDS[spec] or {}) do
        if ASCENDANCE[ns.SPEC.SHA_ELE] == id or ASCENDANCE[ns.SPEC.SHA_ENH] == id
           or ASCENDANCE[ns.SPEC.SHA_RES] == id then got = id end
    end
    if got ~= want then
        ascWrong = ascWrong + 1
        print(("     spec %d 的升腾配成了 %s,该是 %d"):format(spec, tostring(got), want))
    end
end
check("三个萨满专精各配各的升腾 ID", ascWrong, 0)

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

print("== 内置表:自身增益不许超过 CD_SLOTS(0.13 起固定格位)==")
-- 跟 DoT 那条同族:超出的格子**画不出来,而且不报错**
local overCd = 0
for spec, list in pairs(ns.SPEC_CDS) do
    if #list > ns.CD_SLOTS then
        overCd = overCd + 1
        print(("     spec %d 有 %d 个自身增益,超过 CD_SLOTS=%d"):format(spec, #list, ns.CD_SLOTS))
    end
end
check("没有专精的自身增益数超过 CD_SLOTS", overCd, 0)

print("== 隐藏:默认全显示 ==")
local SH = 258        -- 暗牧
local db = {}
check("没配过 -> 不隐藏", ns.IsAuraHidden(db, "cds", SH, 34914), false)
check("空存档也不该建出桶来", db.hidden, nil)

print("== 隐藏:设了才隐藏,清掉要**把键删掉**(不是写 false)==")
check("设成功", ns.SetAuraHidden(db, "cds", SH, 34914, true), true)
check("读回来是隐藏的", ns.IsAuraHidden(db, "cds", SH, 34914), true)
check("别的 ID 不受影响", ns.IsAuraHidden(db, "cds", SH, 589), false)
check("清成功", ns.SetAuraHidden(db, "cds", SH, 34914, false), true)
check("读回来不隐藏", ns.IsAuraHidden(db, "cds", SH, 34914), false)
-- 🔴 这条才是重点:存 false 等于把**默认值写进存档**,而 0.12 那个坑正是这么来的 ——
--    默认值一旦落盘,后来改默认对他一点用没有。所以必须是 nil,不是 false。
check("存档里那个键是 nil(不是 false)", db.hidden.cds[SH][34914], nil)

print("== 隐藏:两种分桶各走一次(判据只在 PER_SPEC 声明一次)==")
local db2 = {}
ns.SetAuraHidden(db2, "cds",  SH, 111, true)     -- per-spec
ns.SetAuraHidden(db2, "lust", nil, 222, true)    -- global
check("per-spec 桶按专精分", ns.IsAuraHidden(db2, "cds", SH, 111), true)
check("per-spec 换个专精就不隐藏", ns.IsAuraHidden(db2, "cds", 250, 111), false)
check("global 桶不吃 specID", ns.IsAuraHidden(db2, "lust", nil, 222), true)
check("global 传个 specID 也一样", ns.IsAuraHidden(db2, "lust", 999, 222), true)
check("不认识的 kind 不建桶", ns.SetAuraHidden(db2, "nosuch", SH, 1, true), false)

print("== 隐藏:问不出专精时不许崩(t[nil]=v 是硬错误)==")
local db3 = {}
local okNil, resNil = pcall(ns.SetAuraHidden, db3, "cds", nil, 1, true)
check("SetAuraHidden(specID=nil) 不抛", okNil, true)
check("而且如实返回 false", resNil, false)
check("IsAuraHidden(specID=nil) fail-open", ns.IsAuraHidden(db3, "cds", nil, 1), false)

print("== VisibleAuraList:HUD 看可见的,面板看全部 ==")
local db4 = {}
ns.SetAuraList(db4, "cds", SH, { 10, 20, 30, 40 })
check("面板拿到全部", #(ns.AuraList(db4, "cds", SH)), 4)
check("HUD 也是全部(还没隐藏)", #(ns.VisibleAuraList(db4, "cds", SH)), 4)
ns.SetAuraHidden(db4, "cds", SH, 20, true)
check("面板仍拿到全部(不然勾不回来)", #(ns.AuraList(db4, "cds", SH)), 4)
local vis = ns.VisibleAuraList(db4, "cds", SH)
check("HUD 少一个", #vis, 3)
check("保序:第 1 个还是 10", vis[1], 10)
check("保序:第 2 个变成 30", vis[2], 30)
check("保序:第 3 个是 40",   vis[3], 40)
check("custom 标记照旧透传", select(2, ns.VisibleAuraList(db4, "cds", SH)), true)

print("== ListMove:上移 / 下移 / 越界 ==")
local l = { 1, 2, 3 }
check("下移第 1 个", ns.ListMove(l, 1, 1), true)
check("  换过去了", l[1], 2)
check("  换回来了", l[2], 1)
check("上移第 1 个 = 越界", ns.ListMove(l, 1, -1), false)
check("  越界后原样", l[1], 2)
check("下移最后一个 = 越界", ns.ListMove(l, 3, 1), false)
check("索引本身越界", ns.ListMove(l, 9, -1), false)

print("== 隐藏的项仍占**配置**里的名次(隐藏->移动->勾回来,顺序要对)==")
local db5 = {}
ns.SetAuraList(db5, "cds", SH, { 10, 20, 30 })
ns.SetAuraHidden(db5, "cds", SH, 20, true)
local cfg = ns.AuraList(db5, "cds", SH)
ns.ListMove(cfg, 1, 1)                 -- 把 10 跟(隐藏着的)20 换位
ns.SetAuraList(db5, "cds", SH, cfg)
check("可见表现在只剩 10 和 30", #(ns.VisibleAuraList(db5, "cds", SH)), 2)
ns.SetAuraHidden(db5, "cds", SH, 20, false)
local back = ns.VisibleAuraList(db5, "cds", SH)
check("勾回来之后 20 在第 1 位", back[1], 20)
check("10 在第 2 位", back[2], 10)

print("== A/B(种回缺陷,下面每条都必须报 caught)==")
-- 从**真文件**重新 load 一份改过的,不手抄 —— 手抄的那份会跟 bug 共享同一个误解。
local rawsrc = assert(io.open("AuraSets.lua", "rb")):read("a")
local function sub(from, to)
    return function(t)
        local out, n = t:gsub(from, to)
        assert(n > 0, "gsub 没命中:" .. from .. " —— 源码改了,这条 A/B 是空转的")
        return out
    end
end
local function mutated(mutate)
    local ns2 = {}
    assert(load(mutate(rawsrc), "AuraSets(mut)"))("DodoCombatHUD", ns2)
    return ns2
end
-- caught = 种回缺陷之后结果**变了**(变成那个错答案)
local function ab(label, mutate, fn, wrongWant)
    local ok, got = pcall(function() return fn(mutated(mutate)) end)
    if ok and got == wrongWant then print("  caught  " .. label); pass = pass + 1
    else fail = fail + 1
        print(("  FAIL %s: 种回缺陷后没变成预期的错答案(ok=%s got=%s)—— 这条 A/B 是空转的")
              :format(label, tostring(ok), tostring(got))) end
end
-- caught = 种回缺陷之后**抛错**了
local function abError(label, mutate, fn)
    local ok = pcall(function() return fn(mutated(mutate)) end)
    if not ok then print("  caught  " .. label); pass = pass + 1
    else fail = fail + 1
        print(("  FAIL %s: 种回缺陷后居然没抛 —— 这条 A/B 是空转的"):format(label)) end
end

-- ① 清隐藏时写 false 而不是删键。⚠ 行为上看不出来(IsAuraHidden 比的是 == true),
--    坏的是**存档里留下了一个默认值** —— 0.12 那个坑就是这么长出来的。
--    所以断言必须去看存档本身,不能只看函数返回值。
ab("清隐藏时写 false 而不是删键",
   sub("if b then b%[id%] = nil end", "if b then b[id] = false end"),
   function(m)
       local d = {}
       m.SetAuraHidden(d, "cds", 258, 7, true)
       m.SetAuraHidden(d, "cds", 258, 7, false)
       return d.hidden.cds[258][7]
   end, false)

-- ② VisibleAuraList 不过滤 ⇒ 隐藏完全失效(而面板上那个勾看起来是勾上的)
ab("VisibleAuraList 不过滤隐藏",
   sub("if b%[full%[i%]%] ~= true then out%[#out %+ 1%] = full%[i%] end",
       "out[#out + 1] = full[i]"),
   function(m)
       local d = {}
       m.SetAuraList(d, "cds", 258, { 1, 2, 3 })
       m.SetAuraHidden(d, "cds", 258, 2, true)
       return #(m.VisibleAuraList(d, "cds", 258))
   end, 3)

-- ③ ListMove 不查越界 ⇒ 第一格上移会跟 list[0] 换位,把 list[1] 换成 nil
--    ⇒ 那一格**静默消失**,而玩家只是点了个画灰的按钮
ab("ListMove 不检查越界",
   sub("if index < 1 or index > #list or j < 1 or j > #list then return false end", ""),
   function(m)
       local d = { 1, 2, 3 }
       m.ListMove(d, 1, -1)
       return d[1]
   end, nil)

-- ④ hiddenBucket 在 specID=nil 时不早退 ⇒ `t[nil] = v` 硬错误,
--    而它从面板的点击回调里冒出来 = 一串红字堆栈,读不出"是因为问不出专精"
abError("specID=nil 时不早退(t[nil]=v)",
   sub("        if specID == nil then return nil end\n", ""),
   function(m) return m.SetAuraHidden({}, "cds", nil, 1, true) end)

-- ⑤ 有人往增强萨列表前面插一个 ID ⇒ 漩涡武器**静默挪到第二格**。
--    这是 0.13 固定格位那条规矩的直接后果,而屏幕上看不出来:那格照常显示、只是位置不对。
ab("漩涡武器被挤出左一",
   sub("%[SPEC%.SHA_ENH%]   = { 344179, 114051, 108271 }",
       "[SPEC.SHA_ENH]   = { 114051, 344179, 108271 }"),
   function(m) return m.SPEC_CDS[m.SPEC.SHA_ENH][1] end, 114051)

-- ⑥ 样式名单里的 ID 跟列表里的对不上(改了一个忘了改另一个)⇒ 那格退回普通大招样式:
--    倒计时回来了、层数缩回右下角。**两张表各自看都完全正常**,漂了没有任何单点读得出来。
ab("CD_STACK_STYLE 跟 SPEC_CDS 漂了",
   sub("%[344179%] = true,   %-%- 漩涡武器", "[3441790] = true,   -- 漩涡武器"),
   function(m) return m.CD_STACK_STYLE[344179] end, nil)

-- ⑦ 升腾的 ID 抄错成隔壁专精那个(复制上一行忘改号)⇒ 那格永远空着。
ab("增强萨的升腾抄成了恢复萨那个号",
   sub("%[SPEC%.SHA_ENH%]   = { 344179, 114051, 108271 }",
       "[SPEC.SHA_ENH]   = { 344179, 114052, 108271 }"),
   function(m) return m.SPEC_CDS[m.SPEC.SHA_ENH][2] end, 114052)

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
