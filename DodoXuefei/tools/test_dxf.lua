-- 离线测 DodoXuefei。跑法:lua tools/test_dxf.lua(在插件根目录跑)
--
-- 🔴 **面板和框体这一层本机一行都验不了** —— canvas 页要真 UI 树,aura 容器在 C 层。
--    离线只守得住四类东西,别把它当"全都验过了":
--      ① 纯逻辑(clamp / 消耗判据 / isBoil)—— 真能算
--      ② 接缝(ns.* 有没有人导出、面板碰不碰存档)
--      ③ 结构规矩(模块级 local 的声明顺序、尺寸的三个消费方、删键不写 false)
--      ④ 每条都配 A/B:种回一个**真会有人写出来**的缺陷,它必须变红。
--    canon:一个永远绿的测试,跟没有测试是同一回事。

-- ⚠ 行尾先归一：这些文件在 Windows 上是 CRLF，而下面一堆锚点写的是 \n。
-- 不归一的话锚点静默对不上，而"找不到锚点"跟"这条规矩不成立"从外面看一模一样。
local function slurp(p)
    local raw = assert(io.open(p, "rb"), "读不到 " .. p):read("a")
    return (raw:gsub("\r\n", "\n"))
end
local CORE = slurp("Core.lua")
local OPT  = slurp("Options.lua")
-- 反空转:确认真读到了源文件,别让后面几十条断言全在空气上跑
assert(#CORE > 15000, "Core.lua 太短,多半没读对文件")
assert(#OPT  > 5000,  "Options.lua 太短,多半没读对文件")

local pass, fail = 0, 0
local function check(label, got, want)
    if got == want then pass = pass + 1
    else fail = fail + 1
        print(("  FAIL %s: got %s want %s"):format(label, tostring(got), tostring(want))) end
end
local function ok_(label, cond, msg)
    if cond then pass = pass + 1
    else fail = fail + 1; print("  FAIL " .. label .. ": " .. tostring(msg)) end
end

---------------------------------------------------------------------------------------------------
print("== ① ClampDim:尺寸的上下限只在一处声明,滑条/输入框/命令全走它 ==")
---------------------------------------------------------------------------------------------------
-- 从**真文件**里抠,不手抄第二份 —— 手抄的那份会跟 bug 共享同一个误解。
local BOUNDS = assert(CORE:match("(local MIN_DIM, MAX_DIM = [^\n]+)"), "抠不到 MIN_DIM/MAX_DIM")
local CLAMP  = assert(CORE:match("(local function ClampDim%(v%).-\nend)"), "抠不到 ClampDim")
assert(CLAMP:find("MIN_DIM", 1, true), "ClampDim 片段里没有 MIN_DIM —— 抠错了")

local function buildClamp(mutate)
    local text = BOUNDS .. "\n" .. CLAMP
    if mutate then text = mutate(text) end
    return assert(load(text .. "\nreturn ClampDim, MIN_DIM, MAX_DIM", "clamp", "t",
        { tonumber = tonumber, math = math }))()
end
local Clamp, LO, HI = buildClamp()
check("下限是 16", LO, 16)
check("上限是 128", HI, 128)
check("正常值原样",        Clamp(48), 48)
check("小于下限 -> 钳到下限", Clamp(1), LO)
check("大于上限 -> 钳到上限", Clamp(9999), HI)
check("负数 -> 钳到下限",     Clamp(-40), LO)
check("0 -> 钳到下限(不是 0!)", Clamp(0), LO)
check("小数四舍五入",       Clamp(47.6), 48)
check("数字串也收",         Clamp("64"), 64)
-- 🔴 空串必须**整条拒收**,不能当 0 收下:输入框一擦就提交的话,当 0 收 = 那一格直接消失,
--    而面板里再也没有把它调回来的入口(canon:宽容的默认值会替 bug 遮丑)。
check("空串 -> 拒收(nil)",   Clamp(""), nil)
check("乱字 -> 拒收(nil)",   Clamp("abc"), nil)
check("nil  -> 拒收(nil)",   Clamp(nil), nil)

print("== ①b A/B:种回三个真会有人写出来的 clamp 缺陷,每条都必须变红 ==")
local function abClamp(label, mutate, arg, wrongAnswer)
    local okc, got = pcall(function() return (buildClamp(mutate))(arg) end)
    if okc and got == wrongAnswer then print("  caught  " .. label); pass = pass + 1
    else fail = fail + 1
        print(("  FAIL %s: 种回缺陷后结果没变(got %s)—— 这条 A/B 是空转的")
              :format(label, tostring(got))) end
end
abClamp("忘了钳下限        -> 0 会被收下",
        function(t) return t:gsub("if v < MIN_DIM then v = MIN_DIM end", "") end, 0, 0)
abClamp("忘了钳上限        -> 9999 会被收下",
        function(t) return t:gsub("if v > MAX_DIM then v = MAX_DIM end", "") end, 9999, 9999)
-- 🔴 这条是那三条里最值钱的:`tonumber("") == nil`,而 `(nil) or 0` 是很自然的写法。
--    收下 0 的后果不是"值不对",是那一格从屏幕上消失且再也调不回来。
abClamp("空串当 0 收下     -> 拒收变成了 16",
        function(t) return t:gsub("if not v then return nil end", "v = v or 0") end, "", 16)

---------------------------------------------------------------------------------------------------
print("== ② consumedBy:「消耗了」必须用时间窗,不能用布尔 ==")
---------------------------------------------------------------------------------------------------
-- GLOW_HIDE 和 CAST 谁先到是**不保证**的。HIDE 先到就把 armed 清了的话,CAST 来的时候
-- 会判成"没消耗" ⇒ 红色那 3 秒永远不出现,而那读起来跟"根本没出过 proc"一模一样。
local CONS = assert(CORE:match("(local function consumedBy%(st%).-\nend)"), "抠不到 consumedBy")
assert(CONS:find("glowOffAt", 1, true), "consumedBy 片段里没有 glowOffAt —— 抠错了")

local NOW = 1000
local function buildCons(mutate)
    local text = mutate and mutate(CONS) or CONS
    return assert(load(text .. "\nreturn consumedBy", "cons", "t",
        { GetTime = function() return NOW end }))()
end
local Cons = buildCons()
check("armed 还亮着                 -> 消耗了", Cons{ armed = true }, true)
check("刚灭 0.1 秒(在窗口内)      -> 消耗了", Cons{ armed = false, glowOffAt = NOW - 0.1 }, true)
check("灭了 0.49 秒(边界内)       -> 消耗了", Cons{ armed = false, glowOffAt = NOW - 0.49 }, true)
check("灭了 2 秒(早过窗口)        -> 没消耗", Cons{ armed = false, glowOffAt = NOW - 2 }, false)
check("从没亮过                     -> 没消耗", Cons{ armed = false }, false)

print("== ②b A/B:退回布尔版,「HIDE 先到」那一条必须变红 ==")
do
    -- 这就是真会有人写出来的那一版:只看 armed。
    local Bool = buildCons(function(t)
        return t:gsub("if st%.armed then return true end.-\nend",
                      "if st.armed then return true end\n    return false\nend")
    end)
    local got = Bool{ armed = false, glowOffAt = NOW - 0.1 }
    if got == false then print("  caught  布尔版:glow 先灭 -> 判成没消耗(红色那半从此不出现)")
        pass = pass + 1
    else fail = fail + 1
        print("  FAIL 布尔版 A/B 空转:got " .. tostring(got)) end
end

---------------------------------------------------------------------------------------------------
print("== ③ isBoil:secret 进来必须判 false,而不是拿去比较 ==")
---------------------------------------------------------------------------------------------------
-- 12.x 的 secret 值伪装成它顶替的那个数,**只在你使用它的时候才炸**,而 `==` 就算一次使用。
-- 这个判据排在所有比较前面,所以它必须先挡住 secret。
local SECR = assert(CORE:match("(local function isSecret%(v%).-\nend)"), "抠不到 isSecret")
local BOIL = assert(CORE:match("(local function isBoil%(id%).-\nend)"), "抠不到 isBoil")
assert(BOIL:find("overrideID", 1, true), "isBoil 片段里没有 overrideID —— 抠错了")

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local function buildBoil(override, mutate)
    local text = SECR .. "\n" .. BOIL
    if mutate then text = mutate(text) end
    local env = {
        type = type, pcall = pcall,
        issecretvalue = function(v) return v == SECRET end,
        ID = { boil = 50842 },
        overrideID = override,
    }
    return assert(load(text .. "\nreturn isBoil", "boil", "t", env))()
end
check("血液沸腾本体            -> true",  buildBoil(nil)(50842), true)
check("别的法术                -> false", buildBoil(nil)(12345), false)
check("被天赋替换后的新 ID     -> true",  buildBoil(99991)(99991), true)
check("没有 override 时那个 ID -> false", buildBoil(nil)(99991), false)
check("secret 进来             -> false", buildBoil(nil)(SECRET), false)
check("字符串进来              -> false", buildBoil(nil)("50842"), false)
check("nil 进来                -> false", buildBoil(nil)(nil), false)

print("== ③b 为什么这条没有动态 A/B ==")
-- 🔴 试过了,**空转** —— 记在这儿,免得下一个人再写一遍。
--    真 secret 值**伪装成它顶替的那个数**(`type()` 返回 "number"),只在被**使用**时才炸。
--    而纯 Lua 里造不出这种东西:拿 table 当替身的话,拆掉闸之后 `table == number`
--    只是返回 false、**不报错** ⇒ 有闸没闸结果一模一样,那条 A/B 对这个缺陷完全免疫。
--    (canon guard 家族 (f):度量的那个量对 bug 免疫;以及「替身必须替身于一个真会被查到的值」。)
-- ⇒ 这条不变式改用**结构守卫**盯(见 ④「isSecret 必须排在任何比较前面」),那个 A/B 是真的会红。
print("  (略过:动态上模拟不出来,已改成 ④ 里的结构守卫)")

---------------------------------------------------------------------------------------------------
print("== ④ 结构守卫(每条下面都有 A/B) ==")
---------------------------------------------------------------------------------------------------
-- 🔴 扫源码的守卫最常见的坏法是**锚点抓到注释** —— 于是它扫的是一段自己写的说明,
--    永远绿。所以先把注释剥干净,而且下面配了**反向断言**证明剥的是注释、不是代码。
local function stripComments(src)
    local out = {}
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        local q, i, n, cut = nil, 1, #line, nil
        while i <= n do
            local ch = line:sub(i, i)
            if q then
                if ch == q then q = nil end
            elseif ch == '"' or ch == "'" then
                q = ch
            elseif ch == "-" and line:sub(i + 1, i + 1) == "-" then
                cut = i - 1; break
            end
            i = i + 1
        end
        out[#out + 1] = cut and line:sub(1, cut) or line
    end
    return table.concat(out, "\n")
end

local function replace(s, old, new)
    local i, j = s:find(old, 1, true)
    if not i then return nil, "找不到要替换的片段:" .. old:sub(1, 40) end
    return s:sub(1, i - 1) .. new .. s:sub(j + 1)
end
local function must(s, err) return assert(s, err) end

local guards = {}
local function G(name, fn, abName, ab) guards[#guards + 1] =
    { name = name, fn = fn, abName = abName, ab = ab } end

-- ── ④.1 模块级 local 必须声明在「第一次被赋值」之前 ──────────────────
-- DodoCombatHUD 0.9.0 首次真机就崩在这:声明写晚了 ⇒ 那句赋值赋的是**全局**,
-- 读的人拿到恒 nil。`luac -p` 挑不出来(写全局是合法 Lua),纯函数测试也够不着。
-- 🔑 **新增任何模块级 local 都要加进这张清单** —— 不加的话守卫对它完全失明。
local NAMES = {
    "slot", "container", "bg", "label", "buttons", "needsResize",
    "glowOn", "lookKey", "overrideID", "liveFrame", "autoFrame", "DB",
    "echo", "live",
    "Reposition", "ApplyGeom", "BuildSlot", "ShowSlot", "HideSlot", "Evaluate", "Why",
}
-- 🔴 两个真会咬人的锚点坑,下面各配了一条反向断言证明没踩:
--    ① 注释里出现同名 ⇒ 先剥注释(不剥的话它扫的是一段说明文字)
--    ② **表构造器里的字段**长得跟赋值一模一样(`echo   = 1265982,` 就在 ID 表里)
--       ⇒ 按花括号深度 + 行尾逗号排掉。第一版正是在这儿假阳性的。
local function scopeCheck(src, names)
    local lines = {}
    for l in (stripComments(src) .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
    local depth, before = 0, {}
    for i, l in ipairs(lines) do
        before[i] = depth
        local _, o = l:gsub("{", "")
        local _, c = l:gsub("}", "")
        depth = depth + o - c
    end
    for _, name in ipairs(names) do
        local decl, assign
        for i, l in ipairs(lines) do
            if not decl and l:match("^local%s+.*%f[%w_]" .. name .. "%f[^%w_]") then decl = i end
            if not assign then
                local isAssign = l:match("^%s+" .. name .. "%s*=[^=]")
                              or l:match("^" .. name .. "%s*=[^=]")
                local tableField = before[i] > 0 and l:match(",%s*$")
                if isAssign and not tableField then assign = i end
            end
        end
        if not decl then return false, ("找不到模块级 `local %s`"):format(name) end
        if assign and assign < decl then
            return false, ("%s:第 %d 行赋值,但 local 到第 %d 行才声明 ⇒ 赋的是全局")
                :format(name, assign, decl)
        end
    end
    return true
end

-- 反向断言:证明上面那两条排除规则**没有把真赋值也排掉**。
-- canon:锚点抓错 ⇒ 全判成豁免 = 真空绿,所以加锚必须配一条"没过度捕获"的断言。
do
    local onlyField = "local ID = {\n    foo = 1,\n}\nlocal foo\n"
    ok_("表字段不算赋值(不过度捕获)", (scopeCheck(onlyField, { "foo" })),
        "把 ID 表里的字段当成了赋值")
    -- 表里嵌一个函数、函数里**真的**赋值 —— 深度 > 0 但行尾没有逗号 ⇒ 必须照样抓到。
    local realBad = "local t = {\n    f = function()\n        foo = 1\n    end,\n}\nlocal foo\n"
    ok_("表里嵌函数中的真赋值照样抓得到", not (scopeCheck(realBad, { "foo" })),
        "花括号那条规则开了个洞:嵌在表里的函数体不查了")
    ok_("注释里的同名不算赋值", (scopeCheck("-- foo = 1\nlocal foo\n", { "foo" })),
        "注释没剥干净")
end

G("模块级 local 声明在赋值之前", function(core)
    return scopeCheck(core, NAMES)
end, "把 `local slot, container...` 挪到文件末尾 -> 那几句赋值变成写全局", function(core, opt)
    local decl = must(core:match("(local slot, container, bg, label[^\n]*)"), "抠不到声明行")
    return must(replace(core, decl, "")) .. "\n" .. decl, opt
end)

-- ── ④.2 isBoil:isSecret 那道闸必须排在任何比较**之前** ────────────────
-- (③b 解释了为什么这条只能靠结构守,动态 A/B 对它免疫。)
G("isBoil 先问 isSecret 再比较", function(core)
    local body = core:match("local function isBoil%(id%).-\nend")
    if not body then return false, "抠不到 isBoil" end
    local a = body:find("isSecret(id)", 1, true)
    local b = body:find("id ==", 1, true)
    if not a then return false, "isBoil 里没有 isSecret(id) —— secret 会被直接拿去比较" end
    if not b then return false, "isBoil 里没有 `id ==` —— 抠错了还是改写法了?" end
    if a > b then return false, "isSecret 排在比较后面 ⇒ 真机上先炸再判" end
    return true
end, "拿掉 isSecret(id) 那道闸", function(core, opt)
    return must(replace(core, "if isSecret(id) or type(id)", "if (type(id)")), opt
end)

-- ── ④.3 面板不许自己碰存档 ────────────────────────────────────────
-- 「显示」存的是 `manualOff`(缺席 = 显示),尺寸有 clamp。面板照直觉自己写一个 `on`、
-- 或者自己钳一遍范围,两份判据当场分叉,而症状是「勾选框和屏幕上那格对不上」。
G("Options.lua 一处都不碰 DodoXuefeiDB", function(_, opt)
    local code = stripComments(opt)
    if code:find("DodoXuefeiDB", 1, true) then
        return false, "面板里直接碰了存档 —— 只准走 Core 导出的动作"
    end
    return true
end, "往面板代码里塞一句直接读存档", function(core, opt)
    return core, must(replace(opt, "local function GetVersion()",
        "local function Peek() return DodoXuefeiDB.width end\nlocal function GetVersion()"))
end)

-- ── ④.4 页面里一个 y 坐标都不许写 ─────────────────────────────────
-- 0.13.0 手写 y 真机满屏文字互相压:说明文字换行成几行只有运行时才知道,
-- 手写 y 等于替一个你算不出来的量猜常数。⇒ 摆控件只准走游标(Col:take)。
G("BuildPage 里没有 SetPoint", function(_, opt)
    local body = opt:match("local function BuildPage%(%).-\nend")
    if not body then return false, "抠不到 BuildPage" end
    if not body:find("c:Dim(", 1, true) then return false, "抠到的不是 BuildPage(里面没有 c:Dim)" end
    if stripComments(body):find("SetPoint", 1, true) then
        return false, "页面里出现了 SetPoint ⇒ 有人在手写坐标"
    end
    return true
end, "在页面里手写一个 SetPoint", function(core, opt)
    return core, must(replace(opt, '    c:Dim("宽", "width")',
        '    local x = f:CreateFontString(nil, "OVERLAY")\n    x:SetPoint("TOPLEFT", 16, -300)\n    c:Dim("宽", "width")'))
end)

-- ── ④.5 改尺寸的三个消费方,一个都不许漏 ───────────────────────────
-- 少碰一个就是「半生效」—— 外框变了、图标没变,比完全不生效更难看出是 bug。
G("ApplyGeom 同时碰外框 / 布局 / 已建按钮", function(core)
    local body = core:match("ApplyGeom = function%(%).-\nend")
    if not body then return false, "抠不到 ApplyGeom" end
    for _, needle in ipairs({ "slot:SetSize", "SetAuraGroupLayout", "RestyleButtons" }) do
        if not body:find(needle, 1, true) then
            return false, "ApplyGeom 里少了 " .. needle .. " ⇒ 改尺寸只会半生效"
        end
    end
    return true
end, "把 ApplyGeom 里的 RestyleButtons() 删掉", function(core, opt)
    return must(replace(core, "    RestyleButtons()\n    if echo.fs then", "    if echo.fs then")), opt
end)

-- ── ④.6 碰 aura button 必须过闸,而且碰不得时要记账 ─────────────────
-- 战斗中 / 光环被扣值时碰按钮不是报错,是**整个初始化被掀掉**。而不记账的话,
-- 「战斗中拖了滑条」那次改动永远丢了 —— 外框已经变了、图标没变,零报错。
G("RestyleButtons 有闸 + 碰不得时记账", function(core)
    local body = core:match("local function RestyleButtons%(%).-\nend")
    if not body then return false, "抠不到 RestyleButtons" end
    if not body:find("CanTouchButtons()", 1, true) then return false, "没过 CanTouchButtons 闸" end
    if not body:find("needsResize = true", 1, true) then return false, "碰不得时没记账,那次改动会永远丢" end
    return true
end, "拿掉 CanTouchButtons 闸", function(core, opt)
    return must(replace(core,
        "    if not CanTouchButtons() then needsResize = true; return end",
        "    do end")), opt
end)

-- ── ④.7 清开关一律**删键**,不许写 false ──────────────────────────
-- 写 false 就是把默认值落了盘 ⇒ 以后再改默认值对这个人一点用都没有,而且自动路径静默。
G("manualOff / unlocked 只删键不写 false", function(core)
    local code = stripComments(core)
    for _, k in ipairs({ "manualOff", "unlocked" }) do
        if code:find(k .. "%s*=%s*false") then
            return false, k .. " 被写成了 false —— 该写 nil(删键)"
        end
    end
    return true
end, "把开关简化成 DB.manualOff = false", function(core, opt)
    return must(replace(core, "if v then DB.manualOff = nil else DB.manualOff = true end",
                              "DB.manualOff = false")), opt
end)

-- ── ④.7b `a and nil or b` 恒等于 b ────────────────────────────────
-- 这不是风格问题,是**永远错**:`and nil` 必然假 ⇒ 永远落到 or 那一支,
-- 两个方向的答案一模一样。写这个插件时我自己就踩了一次
-- (`DB.manualOff = v and nil or true` ⇒ 勾「显示」反而把它关掉)。
-- 项目 CLAUDE.md 里早写过这条 and/or 陷阱 —— 光写在文档里挡不住,得有东西盯着。
G("代码里没有 `and nil or`", function(core, opt)
    for name, src in pairs({ ["Core.lua"] = core, ["Options.lua"] = opt }) do
        if stripComments(src):find("and nil or", 1, true) then
            return false, name .. " 里有 `and nil or` —— 它恒等于 or 那一支,展开写成 if/else"
        end
    end
    return true
end, "把开关写回 `v and nil or true`", function(core, opt)
    return must(replace(core, "if v then DB.manualOff = nil else DB.manualOff = true end",
                              "DB.manualOff = v and nil or true")), opt
end)

-- ── ④.8 ns.* 接口两边对得上 ──────────────────────────────────────
-- 两个文件靠 `ns` 这一张桌子交接。少导出一个的症状是 `attempt to call a nil value`,
-- 而它发生在**点开面板那一刻**,不是加载时 —— 平时跑一天都撞不到。
local function assigned(src)
    local set = {}
    for k in src:gmatch("%f[%w_]ns%.([%w_]+)%s*=") do set[k] = true end
    for k in src:gmatch("function%s+ns%.([%w_]+)") do set[k] = true end
    return set
end
G("Options 用到的 ns.* 都有人导出(反之亦然)", function(core, opt)
    local aCore, aOpt = assigned(core), assigned(opt)
    for k in stripComments(opt):gmatch("%f[%w_]ns%.([%w_]+)") do
        if not (aCore[k] or aOpt[k]) then
            return false, "Options 用了 ns." .. k .. ",但两边都没人给它赋值"
        end
    end
    for k in stripComments(core):gmatch("%f[%w_]ns%.([%w_]+)") do
        if not (aCore[k] or aOpt[k]) then
            return false, "Core 用了 ns." .. k .. ",但两边都没人给它赋值"
        end
    end
    return true
end, "把 Core 里的 ns.DimBounds 改个名 -> 面板那边就够不着了", function(core, opt)
    return must(replace(core, "ns.DimBounds  = function()", "ns.DimBoundsX = function()")), opt
end)

-- ── ④.9 ⛔ 两条硬禁 ───────────────────────────────────────────────
-- SetApplicationCount:那个 sink 会在同一次调用里**同步**写 FontString,字体没设好就是
--   "Font not set",而它会把整个初始化掀掉(DodoCombatHUD 真栽过)。
-- COMBAT_LOG_EVENT_UNFILTERED:12.x 里 **RegisterEvent 这个调用本身**就是 forbidden action,
--   会触发 ADDON_ACTION_FORBIDDEN 并把插件标记进 BugGrabber 的 badAddons ——
--   给别人用的插件更不能带这个。canon rules/wow-addons.md 有全量取证。
for _, ban in ipairs({ "SetApplicationCount", "COMBAT_LOG_EVENT_UNFILTERED" }) do
    G("不许出现 " .. ban, function(core)
        if stripComments(core):find(ban, 1, true) then
            return false, ban .. " 出现在代码里(注释里说明它为什么不能用是可以的)"
        end
        return true
    end, "往代码里塞一句 " .. ban, function(core, opt)
        return must(replace(core, "local function LiveOff()",
            "local function Banned() local x = '" .. ban .. "' return x end\nlocal function LiveOff()")), opt
    end)
end

---------------------------------------------------------------------------------------------------
-- 跑守卫 + 每条的 A/B
---------------------------------------------------------------------------------------------------
-- 🔴 先证明 stripComments 剥的是**注释**而不是代码 —— 一个把代码也剥掉的剥离器
--    会让上面每一条守卫都变成"真空绿":它扫的是一片空气,永远不报。
do
    local sample = 'local a = 1 -- DodoXuefeiDB 在注释里\nlocal s = "a--b"\n-- 整行注释 SetApplicationCount\nlocal c = 2\n'
    local got = stripComments(sample)
    ok_("stripComments 剥掉注释里的关键词", not got:find("DodoXuefeiDB", 1, true), "注释没被剥掉")
    ok_("stripComments 剥掉整行注释",       not got:find("SetApplicationCount", 1, true), "整行注释没被剥掉")
    ok_("stripComments 不动代码",           got:find("local c = 2", 1, true) ~= nil, "把代码也剥掉了 = 所有守卫真空绿")
    ok_("stripComments 不动字符串里的 --",  got:find('"a--b"', 1, true) ~= nil, "字符串里的 -- 被当注释切了")
end

for _, g in ipairs(guards) do
    local good, msg = g.fn(CORE, OPT)
    ok_(g.name, good, msg)
end

print("== ④b A/B:种回缺陷,每条都必须变红 ==")
for _, g in ipairs(guards) do
    if g.ab then
        local c2, o2 = g.ab(CORE, OPT)
        local good = g.fn(c2, o2)
        if not good then print("  caught  " .. g.abName); pass = pass + 1
        else fail = fail + 1
            print("  FAIL A/B 空转(种回缺陷后守卫还是绿的):" .. g.abName) end
    end
end


---------------------------------------------------------------------------------------------------
print("== ⑤ 加载冒烟:把格子真建出来跑一遍,并点名它碰了哪些全局 ==")
---------------------------------------------------------------------------------------------------
-- 为什么值得做:这插件要交到别人手上,而「一加载就炸」= 整个插件不存在,
-- 对方只会看到"装了没反应"。`luac -p` 只查语法,查不出「那句 CreateFrame 写错了名字」。
--
-- 🔴 第一版**是空转的**,记在这儿:它只跑到文件级 + 几个导出函数,而 BuildSlot 从没被调用
--    ⇒ 往 BuildSlot 里种一个打错名的全局(`InCombatLockdow`),测试**照样全绿**。
--    canon guard 家族 (e):刺激根本没送达被测代码。⇒ 现在桩会把格子真建出来
--    (连暴雪那个 AddAuraGroup 的 initializeFrame 都真跑一遍 —— 那正是 DodoCombatHUD
--     栽过 "Font not set" 的地方),并且跑完对账"读到了哪些全局"。
local KNOWN = {   -- 真·WoW 全局,桩里没实现也正常(代码全部 nil-safe 地用它们)
    C_Secrets = true, C_Spell = true, C_SpellActivationOverlay = true, C_Timer = true,
    C_UnitAuras = true, C_AddOns = true, C_SpecializationInfo = true, C_XMLUtil = true,
    AnchorUtil = true, AuraContainerSortMethod = true, AuraContainerSortDirection = true,
    ActionButtonSpellAlertManager = true, GameTooltip = true, Settings = true,
    UIParent = true, STANDARD_TEXT_FONT = true, GetSpecialization = true,
    GetSpecializationInfo = true, GetAddOnMetadata = true, IsPlayerSpell = true,
    InCombatLockdown = true, GetTime = true, issecretvalue = true, CreateFrame = true,
    SlashCmdList = true, DodoProbeLog = true, DodoXuefeiDB = true,
    SLASH_DODOXUEFEI1 = true, SLASH_DODOXUEFEI2 = true,
}
do
    local seen, scripts, inits = {}, {}, 0
    local G
    local function newFrame()
        local f, st = {}, { shown = false }
        scripts[f] = {}
        local fixed = {
            Show = function() st.shown = true end,
            Hide = function() st.shown = false end,
            SetShown = function(_, v) st.shown = v and true or false end,
            IsShown = function() return st.shown end,
            IsVisible = function() return st.shown end,
            IsMouseEnabled = function() return false end,
            GetFrameLevel = function() return 1 end,
            GetText = function() return "" end,
            GetFont = function() return "Fonts", 12, "" end,
            GetStringHeight = function() return 12 end,
            GetCenter = function() return 0, 0 end,
            GetEffectiveScale = function() return 1 end,
            GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
            SetScript = function(_, k, fn) scripts[f][k] = fn end,
            CreateTexture = function() return newFrame() end,
            CreateFontString = function() return newFrame() end,
            -- 🔑 真去跑 initializeFrame:那是暴雪会替我们调的那一半,
            --    也正是"字体没设好就把整个初始化掀掉"那类坑住的地方。
            AddAuraGroup = function(_, _, _, cfg)
                if type(cfg) == "table" and type(cfg.initializeFrame) == "function" then
                    inits = inits + 1
                    cfg.initializeFrame(newFrame())
                end
            end,
        }
        return setmetatable(f, { __index = function(_, k)
            if fixed[k] then return fixed[k] end
            -- ⚠ 内省字段**不兜底**:兜成函数的话 `if b.__x then` 对每个对象都成立,
            --   查找类代码会摸到错的对象,而断言照跑照给答案(DodoCombatHUD 栽过三次)。
            if type(k) == "string" and k:sub(1, 2) == "__" then return nil end
            return function() return f end
        end })
    end
    G = setmetatable({
        CreateFrame = function(_, name) local f = newFrame(); if name then rawset(G, name, f) end; return f end,
        SlashCmdList = {}, GetTime = function() return 1000 end,
        InCombatLockdown = function() return false end,
        IsPlayerSpell = function() return true end,          -- 假装点了沸点天赋
        issecretvalue = function() return false end,
        print = function() end,
        C_Timer = { After = function() end },
        C_Spell = { GetSpellTexture = function() return "tex" end, GetOverrideSpell = function() return nil end },
        C_SpellActivationOverlay = { IsSpellOverlayed = function() return false end },
        C_Secrets = { ShouldAurasBeSecret = function() return false end },
        C_SpecializationInfo = { GetSpecialization = function() return 1 end,
                                 GetSpecializationInfo = function() return 250 end },  -- 血 DK
        AnchorUtil = { FlowDirection = { Right = 1, Down = 2 } },
        -- 面板那一层平时**本机一行都验不了**(canvas 要真 UI 树)。桩到这个程度,
        -- 至少"它构造得出来吗"能验 —— 少一个 ns.* 导出、Col 里写错一个方法名,都在这儿现形。
        Settings = {
            RegisterCanvasLayoutCategory = function(_, name) return { name = name } end,
            RegisterAddOnCategory = function() end,
        },
        AuraContainerSortMethod = { Expiration = 1 },
        AuraContainerSortDirection = { Normal = 1 },
        STANDARD_TEXT_FONT = "Fonts",
        type = type, pcall = pcall, ipairs = ipairs, pairs = pairs, tostring = tostring,
        tonumber = tonumber, select = select, math = math, string = string, table = table,
        setmetatable = setmetatable, rawset = rawset, error = error,
    }, { __index = function(_, k) seen[k] = true; return nil end,
         __newindex = function(t, k, v) seen[k] = nil; rawset(t, k, v) end })
    G.UIParent = newFrame()
    G._G = G

    local nsX = {}
    local function run(f)
        local chunk = assert(loadfile(f, "t", G), "loadfile 失败 " .. f)
        return pcall(chunk, "DodoXuefei", nsX)
    end
    local okc, errc = run("Core.lua");    ok_("Core.lua 加载不报错", okc, errc)
    local oko, erro = run("Options.lua"); ok_("Options.lua 加载不报错", oko, erro)

    if okc and oko then
        -- 🔑 先把 ADDON_LOADED 喂进去 —— DB 是在那一刻才接上的。
        --    不喂的话每个导出函数都在开头 `if not DB then return end` 里空转,
        --    而测试会全绿(第一版就是这么绿的)。顺带把面板也构造一遍。
        local ev = rawget(G, "DodoXuefeiEvents")
        ok_("事件框体拿得到", ev ~= nil, "Core 里那个 CreateFrame 没起名字?")
        ok_("ADDON_LOADED 处理不炸(含注册面板)",
            pcall(function() scripts[ev].OnEvent(ev, "ADDON_LOADED", "DodoXuefei") end), "加载处理炸了")
        ok_("面板真注册上了", nsX.OptionsRegistered == true, "RegisterOptions 走了失败分支")
        ok_("面板刷新不炸", pcall(function() nsX.RefreshOptions() end), "Refreshers 里有函数炸了")
        ok_("ns.* 该有的都在", nsX.SetDim and nsX.GetDim and nsX.SetSlotShown and nsX.SetUnlocked
            and nsX.WhyNotShown and nsX.RegisterOptions and true or false, "少了导出")
        ok_("DB 未就位/框体没建时调导出的动作不炸", pcall(function()
            nsX.GetDim("height"); nsX.WhyNotShown(); nsX.IsSlotShown()
            nsX.IsUnlocked(); nsX.DimBounds()
        end), "有导出函数没做 nil 防护")
        -- 🔑 真把格子建出来 —— 这一步才让 BuildSlot / MakeContainer / BuildEcho / ApplyGeom 被执行到
        ok_("SetSlotShown(true) 能把格子建出来且不炸", pcall(function() nsX.SetSlotShown(true) end), "建格路径炸了")
        local sl = rawget(G, "DodoXuefeiSlot")
        ok_("格子建出来了", sl ~= nil, "CreateFrame 没拿到 DodoXuefeiSlot 这个名字")
        ok_("暴雪那半的 initializeFrame 真跑过", inits > 0, "AddAuraGroup 没被调到 ⇒ 按钮初始化这段零覆盖")
        if sl then
            ok_("每帧驱动 RowUpdate 不炸", pcall(function() scripts[sl].OnUpdate(sl, 0.016) end), "OnUpdate 炸了")
            ok_("拖拽 OnDragStop 不炸", pcall(function()
                nsX.SetUnlocked(true); scripts[sl].OnDragStart(sl); scripts[sl].OnDragStop(sl)
            end), "存位置那段炸了")
        end
        -- 🔑 红色那 3 秒是**唯一有真逻辑**的一半(绿的归暴雪画)。这儿真把三个事件喂进去,
        --    断言的是**行为**不是"没炸"。负对照排在前面:没亮过 proc 就施法,不许出现红的。
        local lf, ec = rawget(G, "DodoXuefeiLive"), rawget(G, "DodoXuefeiEcho")
        ok_("事件框体和 echo 框体都拿得到", lf ~= nil and ec ~= nil, "那两个 CreateFrame 没起名字?")
        if lf and ec then
            local fire = function(...) scripts[lf].OnEvent(lf, ...) end
            -- 负对照:proc 没亮过 ⇒ 这一发血沸不是被强化的那发 ⇒ 不该排 echo
            fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 50842)
            check("负对照:没亮过 proc 就施法 -> 不出红", ec:IsShown(), false)
            -- 正对照:proc 亮着时打出那一发 ⇒ 3 秒后自动血沸落地 ⇒ 出红
            fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 50842)
            fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 50842)
            check("正对照:proc 亮着打出去 -> 出红", ec:IsShown(), true)
            ok_("别人/别的单位的施法进来不炸", pcall(function()
                fire("UNIT_SPELLCAST_SUCCEEDED", "target", nil, 50842) end), "unit 判断那段炸了")
        end
        ok_("改尺寸不炸(含 SetAuraGroupLayout + 重刷按钮)", pcall(function() nsX.SetDim("width", 200) end), "改尺寸炸了")
        ok_("改尺寸被钳到上限", nsX.GetDim("width"), 128)
        ok_("/dxf 无参不炸", pcall(function() G.SlashCmdList["DODOXUEFEI"]("") end), "斜杠命令炸了")
        ok_("/dxf why 不炸", pcall(function() G.SlashCmdList["DODOXUEFEI"]("why") end),
            "诊断命令自己炸了 —— 它恰恰是别人出事时唯一的抓手")
        ok_("/dxf w 64 不炸", pcall(function() G.SlashCmdList["DODOXUEFEI"]("w 64") end), "斜杠改尺寸炸了")
        ok_("SetSlotShown(false) 不炸", pcall(function() nsX.SetSlotShown(false) end), "收起路径炸了")
    end

    -- 未知全局对账。**这是"桩不许兜底"的落地** —— 名字打错了会在这儿冒出来。
    local strays = {}
    for k in pairs(seen) do if not KNOWN[k] then strays[#strays + 1] = k end end
    table.sort(strays)
    ok_("没有读到白名单外的全局", #strays == 0,
        "冒出了没见过的全局(多半是打错名字):" .. table.concat(strays, ", "))
end

print(("== %d passed, %d failed =="):format(pass, fail))
if fail > 0 then os.exit(1) end
