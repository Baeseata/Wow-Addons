-- 离线守 Options.lua 的**接缝**。跑法:lua tools/test_options.lua(插件根目录)
--
-- 为什么值得单独写:面板整段裹在 pcall 里(Settings API 改形状时 HUD 不许跟着倒),
-- 于是它的失败形态是**静默消失** —— 打错一个 `ns.` 接口名或一个 DB 键名,
-- 面板就那么没了,而 /dch 一切正常 ⇒ 你会以为"这版没做面板"。
--
-- 四个接缝:
--   ① Options.lua 调的 `ns.Xxx`,主文件那边到底导没导出
--   ② 面板绑的 DB 键名,DEFAULTS 里到底有没有(打错 = 写进一个没人读的键,零报错)
--   ③ 页面里**不许再出现硬编码 y 坐标**(0.13.0 就是这么排出满屏重叠的)
--   ④ 「超出面板高度」的运行时检查还在不在
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

-- 六个页面的函数体,抠一次给下面几条 guard 共用
local pageBodies, nPages = {}, 0
for name, body in OPT:gmatch("local function (Build%w+Page)%(%)(.-)\n    return f\nend") do
    pageBodies[name] = body; nPages = nPages + 1
end
assert(nPages == 6, ("只抠到 %d 个页面,应该是 6 个 —— 正则跟源码漂了"):format(nPages))

---------------------------------------------------------------------------------------------------
-- 接缝 ①:Options.lua 调的每个 ns.Xxx,别的文件必须真的导出了
---------------------------------------------------------------------------------------------------
print("== ns.* 接口:面板调的,主文件导出了吗 ==")

-- ⚠ 两种写法都要认:`ns.Foo = function` 和 `function ns.Foo(...)`。
--    只认前一种的话,AuraSets.lua 那批全是后一种 ⇒ guard 会把它们全报成缺失,
--    而那是一份看起来很有说服力的假红。
local function collectProvided(src, into)
    for k in src:gmatch("%f[%w_]ns%.([%w_]+)%s*=") do into[k] = true end
    for k in src:gmatch("function%s+ns%.([%w_]+)") do into[k] = true end
end

local provided = {}
for _, name in ipairs(FILES) do collectProvided(slurp(name), provided) end
collectProvided(OPT, provided)
assert(next(provided) ~= nil, "一个 ns.* 导出都没扫到 —— 这条 guard 是空转的")

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
        local n = 0; for _ in pairs(used) do n = n + 1 end
        assert(n >= 10, ("只扫到 %d 个 ns.* 引用,面板不可能这么少 —— 正则漂了"):format(n))
        print(("     (扫到 %d 个 ns.* 引用)"):format(n))
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
assert(nDef >= 30, ("只从 DEFAULTS 扫到 %d 个键,正则漂了 —— 下面全是假红"):format(nDef))

local function keySeam(src, quiet)
    local bound = {}
    for k in src:gmatch(':Check%("[^"]*", "([%w_]+)"')                      do bound[k] = "Check"  end
    for k in src:gmatch(':Slider%("[^"]*", %-?%d+, %-?%d+, "([%w_]+)"')     do bound[k] = "Slider" end
    for k in src:gmatch('colorGet%("([%w_]+)"%)')                           do bound[k] = "color"  end
    for k in src:gmatch('colorSet%("([%w_]+)"')                             do bound[k] = "color"  end
    for k in src:gmatch('ticksIO%("([%w_]+)"%)')                            do bound[k] = "ticks"  end

    local n, bad = 0, {}
    for k, how in pairs(bound) do
        n = n + 1
        if not defaults[k] then bad[#bad + 1] = k .. "(" .. how .. ")" end
    end
    table.sort(bad)
    if not quiet then
        for _, k in ipairs(bad) do print("     |> " .. k .. " 不在 DEFAULTS 里") end
        assert(n >= 20, ("只扫到 %d 个绑定,面板不可能这么少 —— 正则漂了"):format(n))
        print(("     (%d 个键 / DEFAULTS 共 %d 个)"):format(n, nDef))
    end
    return #bad
end
check("面板绑的 DB 键全都在 DEFAULTS 里", keySeam(OPT), 0)

---------------------------------------------------------------------------------------------------
-- 接缝 ③:页面里不许再出现硬编码 y 坐标
--
-- 🔴 0.13.0 每个控件都手写 y,真机一跑满屏文字互相压。根因不是"坐标算错了",
--    是这个方法**结构上**不成立:Note 的高度取决于它换行成几行,而那要等到运行时
--    (中文断行 + 界面缩放 + 字体)才知道 —— 手写 y 等于替一个你算不出来的量猜常数。
--    0.13.1 改成游标式(Col:take),这条 guard 就是防它被人手写回去。
--
-- 判据:页面函数体里**锚到页面自己**的 SetPoint(三参形式 `SetPoint(点, x, y)`)
-- 的第 3 个参数不许是字面数字。锚到**别的控件**的五参形式(`SetPoint(点, 谁, 点, dx, dy)`)
-- 不在此列 —— 那是相对定位,本来就该写数字。
---------------------------------------------------------------------------------------------------
print("== 页面里有没有硬编码 y 坐标 ==")

local function hardCoded(src, quiet)
    local bad, seen = {}, 0
    for name, body in src:gmatch("local function (Build%w+Page)%(%)(.-)\n    return f\nend") do
        for args in body:gmatch('SetPoint%(("[%u]+"[^%)]*)%)') do
            local n = select(2, args:gsub(",", ""))
            if n == 2 then                       -- 三参形式:点, x, y
                seen = seen + 1
                local y = args:match(",%s*([^,]+)%s*$")
                if y and tonumber(y) then
                    bad[#bad + 1] = ("%s: SetPoint(..., %s)"):format(name, y)
                end
            end
        end
    end
    if not quiet then
        for _, s in ipairs(bad) do print("     |> " .. s .. " 是硬编码 y —— 改用 Col:take()") end
        -- 反空转:页面里现在**确实**有几处三参 SetPoint(手接的 bpCheck / chanEdit),
        -- 一处都扫不到就是正则漂了,那条绿是假的。
        assert(seen >= 2, ("只扫到 %d 处锚到页面的 SetPoint,正则漂了"):format(seen))
        print(("     (扫了 %d 处锚到页面的 SetPoint)"):format(seen))
    end
    return #bad
end
check("页面里没有硬编码 y", hardCoded(OPT), 0)

-- 接缝 ④:那条运行时的「超出面板高度」检查还在不在。
-- canvas 页不滚动,超出的控件被裁掉且不报错;真实高度只有运行时知道 ⇒
-- 这条检查是唯一能发现它的东西,**被人顺手删掉的话离线一点感觉都没有**。
print("== 运行时的溢出检查还在吗 ==")
check("RegisterOptions 里查了 deepest < FLOOR",
    OPT:find("cc%.deepest < FLOOR") ~= nil, true)
check("FLOOR 有定义", OPT:find("\nlocal FLOOR") ~= nil, true)

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
-- ⚠ 空串**是合法的**(= 玩家真的把刻度清了)。正因为它合法,一次误提交就会
--    静默清空刻度 —— 所以 Col:Edit 必须"没改过就不提交",见下面那条 guard。
check("空串 = 空数组(合法:清掉刻度)", #S2T(""), 0)

print("== Col:Edit 必须「没改过就不提交」==")
-- 🔴 0.13.0 的真 bug:commit 无条件挂在 OnEditFocusLost 上 ⇒ 面板一开一关的焦点事件
--    就会拿框里的内容提交一次。而刻度的 set 认空串(合法地清掉刻度)⇒ 一次误提交
--    就把玩家的刻度**写没了**,而且自我固化:写没了以后框永远是空,下次误提交还是空。
--    零报错、看起来就像"这个框不显示值"。
local editSrc = assert(OPT:match("function Col:Edit.-\nend\n"), "抠不到 Col:Edit")
check("commit 里有「跟上次渲染的一样就返回」", editSrc:find("if txt == shown then return end") ~= nil, true)
check("shown 在 refresh 里被更新", editSrc:find("shown = get%(%) or \"\"") ~= nil, true)

---------------------------------------------------------------------------------------------------
-- 接缝 ⑤:估一遍每页每列有多高,别超出面板
--
-- ⚠ 这是**估算**,不是真值 —— 真实高度取决于 GetStringHeight(中文断行 / 界面缩放 / 字体),
--   只有运行时知道(那条检查在 RegisterOptions 里,接缝 ④ 盯着它还在不在)。
--   但估算能在**发出去之前**逮到"整整一个编辑器掉出面板"这种量级的错 ——
--   0.13.1 第一版团队增益页就是这么排出 -593 的,而我在本机一个像素都看不见。
--   ⇒ 两道一起要:离线估算防大错,运行时检查报真值。
---------------------------------------------------------------------------------------------------
print("== 估算:每页每列的高度 ==")

-- 每种控件占多高。跟 Options.lua 里 Col:* 的 take() 参数**手工对齐** ——
-- 漂了的话下面那个反空转会先炸(见 nCalls 断言)。
local H = { Header = 26, Check = 26, Slider = 38, Color = 26, Button = 28, Button2 = 0, Edit = 44 }

-- 中文一个字约占两个 ASCII 宽;300px / 约 6px 一个 ASCII 单位 ≈ 50 单位一行。
local function noteHeight(text)
    local t = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%*%*", "")
    local units = 0
    for _, cp in utf8.codes(t) do units = units + (cp > 0x2000 and 2 or 1) end
    return math.max(1, math.ceil(units / 50)) * 13 + 8
end

local nCalls = 0
local function pageHeights(src)
    local out = {}
    for name, body in src:gmatch("local function (Build%w+Page)%(%)(.-)\n    return f\nend") do
        local col = { c = 14, r = 14 }
        for line in body:gmatch("[^\n]+") do
            local which, meth, rest = line:match("([cr]):(%a+)%((.*)$")
            if which and col[which] then
                nCalls = nCalls + 1
                if H[meth] then
                    col[which] = col[which] + H[meth]
                elseif meth == "Note" then
                    col[which] = col[which] + noteHeight(rest:match('^"(.-)"') or "")
                elseif meth == "NoteBox" then
                    col[which] = col[which] + (tonumber(rest:match("^(%d+)")) or 1) * 13 + 8
                elseif meth == "take" or meth == "gap" then
                    col[which] = col[which] + (tonumber(rest:match("^(%d+)")) or 10)
                elseif meth == "AuraEditor" then
                    -- status(21) + note(34) + 滚动区(vis*22+6) + 添加行(30)
                    -- ⚠ 先把右括号剥掉:不剥的话最后一个参数是 "3)",tonumber 返 nil,
                    --   于是悄悄回落到 maxRows(30)—— 估出来是真值的 6 倍,
                    --   而它只会**多报**、不会漏报,所以第一眼看不出是估算器自己坏了。
                    local inner = rest:match("^(.-)%)") or rest
                    local args = {}
                    for a in (inner .. ","):gmatch("%s*([^,]-)%s*,") do args[#args + 1] = a end
                    local vis = tonumber(args[5]) or tonumber(args[2]) or 6
                    col[which] = col[which] + 21 + 34 + vis * 22 + 6 + 30
                end
            end
        end
        out[name] = { c = col.c, r = col.r }
    end
    return out
end

local function overflow(src, quiet)
    local hs = pageHeights(src)
    local over, report = 0, {}
    for name, v in pairs(hs) do
        report[#report + 1] = ("%s L=%d R=%d"):format(name:sub(6, -5), v.c, v.r)
        if v.c > 545 or v.r > 545 then over = over + 1 end
    end
    table.sort(report)
    if not quiet then
        -- 反空转:一个 Col:* 调用都没扫到 = 正则跟源码漂了,"全都放得下"是假绿
        assert(nCalls >= 60, ("只扫到 %d 个 Col:* 调用,正则漂了"):format(nCalls))
        print("     (" .. table.concat(report, "  ") .. ")")
    end
    return over
end
check("六个页面估算都装得下(<=545)", overflow(OPT), 0)

---------------------------------------------------------------------------------------------------
-- A/B:种回缺陷,下面这几条必须都报 caught。
-- 不做这一步的话,上面那些绿只证明"没找到违规",不证明"没有违规"。
---------------------------------------------------------------------------------------------------
print("== A/B(种回缺陷,下面六条必须都报 caught)==")

local function ab(label, mutate, scan)
    local src = mutate(OPT)
    assert(src ~= OPT, "gsub 没命中:" .. label .. " —— 源码改了,这条 A/B 是空转的")
    local n = scan(src, true)
    if n > 0 then print("  caught  " .. label); pass = pass + 1
    else fail = fail + 1
        print(("  FAIL %s: 种回缺陷后 guard 还是 0 —— 这条 A/B 是空转的"):format(label)) end
end

-- ① 调一个根本不存在的导出。真机上的表现:面板整段 pcall 失败 = **静默消失**。
ab("面板调了一个没人导出的 ns.*",
   function(s) return s:gsub("ns%.ApplyLayout%)", "ns.NoSuchExportXX)", 1) end, nsSeam)

-- ② 勾选框键名打错。表现:写进一个没人读的键,屏幕上什么都不变。
ab("Check 绑了一个 DEFAULTS 里没有的键",
   function(s) return s:gsub('"cdsOn"', '"cdsOnXX"', 1) end, keySeam)

-- ③ 滑条键名打错。表现:读回 nil 退到默认值,拖它没有任何效果。
ab("Slider 绑了一个 DEFAULTS 里没有的键",
   function(s) return s:gsub('"cdWidth"', '"cdWidthXX"', 1) end, keySeam)

-- ④ 色块键名打错。表现:色块永远画灰,改完也不生效。
ab("colorGet 绑了一个 DEFAULTS 里没有的键",
   function(s) return s:gsub('colorGet%("castColor"%)', 'colorGet("castColorXX")', 1) end, keySeam)

-- ⑤ 有人把硬编码 y 写回页面里 —— 就是 0.13.0 那个满屏重叠的形状。
ab("页面里写回了硬编码 y",
   function(s)
       return s:gsub('bpCheck:SetPoint%("TOPLEFT", c%.x, bpTop%)',
                     'bpCheck:SetPoint("TOPLEFT", 16, -64)', 1)
   end, hardCoded)

-- ⑥ 某一列排到面板外面 —— 就是 0.13.1 第一版团队增益页那个 -593。
--    真机上的表现:底下那个编辑器**根本不出现**,而且不报错。
ab("某页某列超出面板高度",
   function(s) return s:gsub('c:AuraEditor%("raid", 30, nil, false, 5%)',
                             'c:AuraEditor("raid", 30, nil, false, 20)', 1) end, overflow)

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
