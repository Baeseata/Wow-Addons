-- 离线守 Options.lua 的**接缝**。跑法:lua tools/test_options.lua(插件根目录)
--
-- 为什么值得单独写:面板整段裹在 pcall 里(Settings API 改形状时 HUD 不许跟着倒),
-- 于是它的失败形态是**静默消失** —— 打错一个 `ns.` 接口名或一个 DB 键名,
-- 面板就那么没了,而 /dch 一切正常 ⇒ 你会以为"这版没做面板"。
--
-- 两个接缝(canon guard 家族 (i):两套各自完备、中间那段谁都没覆盖):
--   ① Options.lua 调的 `ns.Xxx`,主文件那边到底导没导出
--   ② 面板绑的 DB 键名,DEFAULTS 里到底有没有(打错 = 写进一个没人读的键,零报错)
--
-- 纯文本扫描,不需要 WoW API,也不需要把 125KB 的主文件跑起来。

local function slurp(p)
    local f = assert(io.open(p, "rb"), "读不到 " .. p)
    local s = f:read("a"); f:close(); return s
end

local OPT   = slurp("Options.lua")
local FILES = { "DodoCombatHUD.lua", "AuraSets.lua", "Resource.lua", "Boiling.lua" }

local pass, fail = 0, 0
local function check(label, got, want)
    if got == want then pass = pass + 1
    else fail = fail + 1
        print(("  FAIL %s: got %s want %s"):format(label, tostring(got), tostring(want))) end
end

-- 反空转:文件真读到了才往下走
assert(#OPT > 5000, "Options.lua 太短,读错文件了 —— 后面全是空转")

---------------------------------------------------------------------------------------------------
-- 接缝 ①:Options.lua 调的每个 ns.Xxx,别的文件必须真的导出了
---------------------------------------------------------------------------------------------------
print("== ns.* 接口:面板调的,主文件导出了吗 ==")

-- ⚠ 两种写法都要认:`ns.Foo = function` 和 `function ns.Foo(...)`。
--    只认前一种的话,AuraSets.lua 那批全是后一种 ⇒ guard 会把它们**全报成缺失**,
--    而那是一份看起来很有说服力的假红。
local function collectProvided(src, into)
    for k in src:gmatch("%f[%w_]ns%.([%w_]+)%s*=") do into[k] = true end
    for k in src:gmatch("function%s+ns%.([%w_]+)") do into[k] = true end
end

local provided = {}
for _, name in ipairs(FILES) do collectProvided(slurp(name), provided) end
-- Options.lua 自己挂上去的那几个(RegisterOptions / OptionsRegistered …)也算数
collectProvided(OPT, provided)
-- 反空转:一个都没扫到 = 正则跟源码漂了,下面那句"全都有"就是假绿
assert(next(provided) ~= nil, "一个 ns.* 导出都没扫到 —— 这条 guard 是空转的")

-- 抽成函数,好让下面的 A/B 拿**同一段扫描逻辑**去跑种了缺陷的源码。
-- 两份手写的扫描必然会漂,而漂了以后 A/B 验的就不是真正在跑的那个 guard 了。
local function nsSeam(src, quiet)
    local used, missing = {}, {}
    -- 🔴 `%f[%w_]` 那个词边界不能省:没有它,注释里的 "Optio|ns.lua" 会被当成 `ns.lua` ——
    --    一个凭空捏出来的"缺失接口"。canon:报出来的歧义先怀疑是自己预处理造的。
    for k in src:gmatch("%f[%w_]ns%.([%w_]+)") do used[k] = true end
    for k in pairs(used) do
        if not provided[k] then missing[#missing + 1] = k end
    end
    table.sort(missing)
    if not quiet then
        for _, k in ipairs(missing) do
            print(("     |> ns.%s 在 Options.lua 里被调,但没有任何文件导出它"):format(k))
        end
        local nUsed = 0; for _ in pairs(used) do nUsed = nUsed + 1 end
        assert(nUsed >= 10, ("只扫到 %d 个 ns.* 引用,面板不可能这么少 —— 正则漂了"):format(nUsed))
        print(("     (扫到 %d 个 ns.* 引用)"):format(nUsed))
    end
    return #missing
end
check("面板调的 ns.* 全都有人导出", nsSeam(OPT), 0)

---------------------------------------------------------------------------------------------------
-- 接缝 ②:面板绑的每个 DB 键名,DEFAULTS 里必须真的有
--
-- 打错一个键名的后果**完全静默**:勾选框写进一个没人读的键,滑条读回 nil 退到默认值 ——
-- 屏幕上什么都不会变,而它看起来完全像"这个开关没接上"。
---------------------------------------------------------------------------------------------------
print("== DB 键名:面板绑的,DEFAULTS 里有吗 ==")

local HUD = slurp("DodoCombatHUD.lua")
local block = assert(HUD:match("\nlocal DEFAULTS = {(.-)\n}\n"), "抠不到 DEFAULTS 块")
local defaults = {}
for k in block:gmatch("\n    ([%w_]+)%s*=") do defaults[k] = true end
local nDef = 0; for _ in pairs(defaults) do nDef = nDef + 1 end
-- 反空转:DEFAULTS 有几十个键,扫到个位数就是正则漂了
assert(nDef >= 30, ("只从 DEFAULTS 扫到 %d 个键,正则漂了 —— 下面全是假红"):format(nDef))

-- 标签和键名之间只可能是数字 / 标识符 / 运算符,不会再有别的引号字符串 ⇒
-- 「跳过非引号的一段,再抓下一个引号串」就能精确拿到键名。
local function keySeam(src, quiet)
    local bound = {}
    for k in src:gmatch('MakeCheck%(f, "[^"]*",[^"]*"([%w_]+)"') do bound[k] = "MakeCheck" end
    for k in src:gmatch('MakeSlider%(f, "[^"]*",[^"]*"([%w_]+)"') do bound[k] = "MakeSlider" end
    for k in src:gmatch('colorGet%("([%w_]+)"%)')                 do bound[k] = "colorGet"  end
    for k in src:gmatch('colorSet%("([%w_]+)"')                   do bound[k] = "colorSet"  end

    local nBound, badKeys = 0, {}
    for k, how in pairs(bound) do
        nBound = nBound + 1
        if not defaults[k] then badKeys[#badKeys + 1] = k .. "(" .. how .. ")" end
    end
    table.sort(badKeys)
    if not quiet then
        for _, k in ipairs(badKeys) do print("     |> " .. k .. " 不在 DEFAULTS 里") end
        assert(nBound >= 20, ("只扫到 %d 个绑定,面板不可能这么少 —— 正则漂了"):format(nBound))
        print(("     (%d 个键 / DEFAULTS 共 %d 个)"):format(nBound, nDef))
    end
    return #badKeys
end
check("面板绑的 DB 键全都在 DEFAULTS 里", keySeam(OPT), 0)

---------------------------------------------------------------------------------------------------
-- 刻度输入:「20,40,60」<-> 数组。从**真文件**抠出来跑,不手抄第二份。
---------------------------------------------------------------------------------------------------
print("== 刻度输入的解析 ==")
local ticksSrc = assert(OPT:match("(local function TicksToText.-\nend)"), "抠不到 TicksToText")
    .. "\n" .. assert(OPT:match("(local function TextToTicks.-\nend)"), "抠不到 TextToTicks")
local T2S, S2T = load(ticksSrc .. "\nreturn TicksToText, TextToTicks")()

check("数组 -> 文本", T2S({ 20, 40, 60 }), "20,40,60")
check("空数组 -> 空串", T2S({}), "")
check("nil 也不炸", T2S(nil), "")
check("文本 -> 数组 长度", #S2T("20,40,60"), 3)
check("  第 2 个", S2T("20,40,60")[2], 40)
check("带空格也认", #S2T(" 20 , 40 "), 2)
check("小数四舍五入", S2T("20.6")[1], 21)
-- 🔴 非法输入**整条拒收**(返回 nil),不做"能解析几个算几个" ——
--    半生效的刻度会教你一个错的节奏,而它看起来完全像个正经功能。
check("超过 100 整条拒收", S2T("20,140"), nil)
check("负数整条拒收", S2T("-5"), nil)
check("非数字整条拒收", S2T("20,abc"), nil)
check("空串 = 空数组(合法:清掉刻度)", #S2T(""), 0)

---------------------------------------------------------------------------------------------------
-- 接缝 ③:每页的内容不许掉出面板底边
--
-- 🔴 canvas 页**不滚动**:超出面板高度的控件就是被裁掉,**而且不报错** ——
--    症状是"面板下半截空的 / 那个滑条不见了",完全看不出是坐标算错了。
--    这一条是本机唯一验得了的几何问题(像素级对齐仍然只能真机看)。
---------------------------------------------------------------------------------------------------
print("== 每页内容有没有掉出面板底边 ==")

local FLOOR = -545     -- 实测面板可用高度约 560,留一点余量
local ROW_H = 22       -- 跟 Options.lua 里那个常量对齐

-- 行数参数可能写成裸数字,也可能写成 `ns.CD_SLOTS or 8` ⇒ 两种都要认。
-- 🔴 第一版只认裸数字,于是自身增益页和目标页的编辑器**一个都没被量到**,
--    而那两页照样报了个漂亮的"放得下" —— canon guard 家族 (a):覆盖率静默塌陷。
--    下面那条 measured 计数就是为了让这种事再也藏不住。
local AS = {}; assert(loadfile("AuraSets.lua"))("DodoCombatHUD", AS)
local function resolveCount(expr)
    local n = tonumber(expr)
    if n then return n end
    local name, fallback = expr:match("^ns%.([%w_]+)%s+or%s+(%d+)$")
    if name then return tonumber(AS[name]) or tonumber(fallback) end
    return nil
end

local measuredEditors = 0
local function pageDepth(body)
    local deepest = 0
    -- Header / Note / MakeCheck / MakeSlider / MakeColor / MakeEdit 的第 4 个参数都是 y
    for y in body:gmatch('[%w_]+%(f, "[^"]*", [%w_ %+%-]+, (%-?%d+)') do
        deepest = math.min(deepest, tonumber(y))
    end
    -- 编辑器另算:它自己往下长 (visibleRows 行 + 一行添加按钮)
    for y, args in body:gmatch('MakeAuraEditor%(f, [%w_ %+%-]+, (%-?%d+), "[%w_]+", ([^%)]*)%)') do
        local parts = {}
        for p in (args .. ","):gmatch("%s*([^,]-)%s*,") do parts[#parts + 1] = p end
        local maxRows = resolveCount(parts[1] or "")
        local vis = resolveCount(parts[4] or "") or maxRows
        assert(maxRows, "量不出编辑器行数:" .. tostring(parts[1]))
        measuredEditors = measuredEditors + 1
        deepest = math.min(deepest, tonumber(y) - 40 - vis * ROW_H - 30)
    end
    return deepest
end

local pages, nPages = {}, 0
for name, body in OPT:gmatch("local function (Build%w+Page)%(%)(.-)\n    return f\nend") do
    pages[name] = pageDepth(body); nPages = nPages + 1
end
-- 反空转:六个页面一个都没抠到 = 正则漂了,下面那句"全都放得下"是假绿
assert(nPages == 6, ("只抠到 %d 个页面,应该是 6 个 —— 正则跟源码漂了"):format(nPages))
-- 🔴 反向断言:**每个** MakeAuraEditor 调用都要被量到。
--    少量一个,那一页就会报出一个偏浅、而且看起来完全正常的"最低点"。
do
    local total = 0
    for _ in OPT:gmatch("MakeAuraEditor%(f,") do total = total + 1 end
    assert(measuredEditors == total,
        ("有 %d 个 aura 编辑器,只量到 %d 个 —— 剩下那些的高度没算进去,这条 guard 是半瞎的")
        :format(total, measuredEditors))
end

local tooDeep = {}
for name, d in pairs(pages) do
    if d < FLOOR then tooDeep[#tooDeep + 1] = ("%s(最低 %d)"):format(name, d) end
end
table.sort(tooDeep)
for _, s in ipairs(tooDeep) do print("     |> " .. s .. " 会被裁掉") end
check("六个页面的内容都在面板里", #tooDeep, 0)
do
    local names = {}
    for n, d in pairs(pages) do names[#names + 1] = ("%s=%d"):format(n:sub(6, -5), d) end
    table.sort(names)
    print("     (各页最低点:" .. table.concat(names, "  ") .. ")")
end

---------------------------------------------------------------------------------------------------
-- A/B:种回缺陷,下面这几条必须都报 caught。
-- 不做这一步的话,上面那些绿只证明"没找到违规",不证明"没有违规"。
---------------------------------------------------------------------------------------------------
print("== A/B(种回缺陷,下面四条必须都报 caught)==")

local function ab(label, mutate, scan)
    local src = mutate(OPT)
    assert(src ~= OPT, "gsub 没命中:" .. label .. " —— 源码改了,这条 A/B 是空转的")
    local n = scan(src, true)
    if n > 0 then print("  caught  " .. label); pass = pass + 1
    else fail = fail + 1
        print(("  FAIL %s: 种回缺陷后 guard 还是 0 —— 这条 A/B 是空转的"):format(label)) end
end

-- ① 调一个根本不存在的导出。真机上的表现:面板整段 pcall 失败 = **静默消失**,
--    而 /dch 一切正常 ⇒ 你会以为"这版没做面板"。
ab("面板调了一个没人导出的 ns.*",
   function(s) return s:gsub("ns%.ApplyLayout%)", "ns.NoSuchExportXX)", 1) end, nsSeam)

-- ② 键名打错一个字母。表现:勾选框写进一个没人读的键,屏幕上什么都不变。
ab("MakeCheck 绑了一个 DEFAULTS 里没有的键",
   function(s) return s:gsub('"cdsOn"', '"cdsOnXX"', 1) end, keySeam)

-- ③ 滑条键名打错。表现:读回 nil 退到默认值,拖它没有任何效果。
ab("MakeSlider 绑了一个 DEFAULTS 里没有的键",
   function(s) return s:gsub('"cdWidth"', '"cdWidthXX"', 1) end, keySeam)

-- ④ 色块键名打错。表现:色块永远显示白色,改完也不生效。
ab("colorGet 绑了一个 DEFAULTS 里没有的键",
   function(s) return s:gsub('colorGet%("castColor"%)', 'colorGet("castColorXX")', 1) end, keySeam)

-- ⑤ 内容掉出面板底边。真机上的表现:那几个控件**根本不出现**,而且不报错。
do
    local body = assert(OPT:match("local function BuildCastPage%(%)(.-)\n    return f\nend"))
    local hurt = body:gsub('Header%(f, "引导跳数", RIGHT, %-12%)',
                           'Header(f, "引导跳数", RIGHT, -900)', 1)
    assert(hurt ~= body, "gsub 没命中 —— 这条 A/B 是空转的")
    if pageDepth(hurt) < FLOOR then print("  caught  某页内容掉出面板底边"); pass = pass + 1
    else fail = fail + 1; print("  FAIL 掉出底边没被抓到 —— 这条 A/B 是空转的") end
end

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
