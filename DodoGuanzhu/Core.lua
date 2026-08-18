-- DodoGuanzhu :: Core.lua
-- 能量灌注(Power Infusion, 10060)顺位:预设一份名单,一个宏按优先级挑人,
-- 都给不出去才给自己。**优先级 fallback 由宏条件自己完成,插件不在战斗中做任何决策** ——
-- 这跟 DodoGrid/Dispel.lua 是同一个思路:让游戏自己判,我们不读数据。
--
-- 数据是唯一真相:名单 + 开关 → 宏正文、面板、预览都是它的渲染。
-- 别让任何一处自己维护第二套判断顺序(那会静默漂,而两边都看着正常)。

local ADDON, ns = ...

ns.PI_SPELL_ID = 10060          -- 技能名一律运行时取,不硬编码"能量灌注"(跨语言客户端都对)

-- 实测常量(12.1.0 build 120100 / US-Illidan,/dp macro 三跑一致):
-- 宏正文按**码位**截断,回读上限 256;UI 输入框那边是 255 ⇒ 取小的那个当预算。
ns.BODY_LIMIT = 255
ns.MAX_MEMBERS = 8              -- 名单人数上限。256 码位放得下,8 个纯属够用

local DEFAULTS = {
    lists = nil,                -- 见 Core.EnsureDB
    editing = 1,                -- 面板当前在编哪一套
    capture = { alsoMouseover = true },
    minimapAngle = 200,        -- 小地图按钮在环上的角度(度)。拖动时实时写回

    preview = { enabled = true, locked = false, x = 0, y = -180 },
}

local function NewList(name)
    return {
        name     = name or "默认",
        members  = {},          -- 有序数组,[1] 优先级最高。存的是**名字字符串**
        useFocus = true,        -- 焦点组排最前(Jerry 的焦点常挂术士/法师 = 灌注目标本身)
        selfLast = true,        -- 末尾兜底 [@player]。点了 Twins of the Sun Priestess 时
                                -- 给出去永远优于给自己 ⇒ 这是止损不是备选
    }
end
ns.NewList = NewList

function ns.EnsureDB()
    DodoGuanzhuDB = DodoGuanzhuDB or {}
    local db = DodoGuanzhuDB
    if Dodo and Dodo.CopyDefaults then Dodo.CopyDefaults(db, DEFAULTS) end
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil and type(v) ~= "table" then db[k] = v end
        if type(v) == "table" and type(db[k]) ~= "table" then db[k] = CopyTable(v) end
    end
    if type(db.lists) ~= "table" or #db.lists == 0 then db.lists = { NewList("默认") } end
    if type(db.editing) ~= "number" or not db.lists[db.editing] then db.editing = 1 end
    ns.db = db
    return db
end

-- 当前在编的那一套。**所有模块都从这儿拿,不各自缓存。**
function ns.Current()
    local db = ns.db or ns.EnsureDB()
    return db.lists[db.editing] or db.lists[1]
end

function ns.ListByName(name)
    for i, L in ipairs((ns.db or ns.EnsureDB()).lists) do
        if L.name == name then return L, i end
    end
end

-- 名单变了 → 谁关心谁自己刷。避免模块之间互相 require。
ns.callbacks = {}
function ns.OnChanged(fn) ns.callbacks[#ns.callbacks + 1] = fn end
-- kind == "view" ⇒ 只刷新,不标脏。
-- 🔴 这个参数是补一次真事故:第一版让 Changed() **无条件** MarkDirty,
--    而 Changed() 原本只表示「去刷新」,我给它加了「数据变脏」这第二个语义,
--    却没把它的 7 个调用点重新审一遍 ⇒ 点一下**方案下拉**(纯换视图、什么都没编辑)
--    面板就打出「名单改过了,还没写进宏」并高亮按钮 —— **面板开始撒谎**。
--    canon:换了模型,要把旧模型的每一条推论都点一遍;危险的正是那些单独看还合理的推论。
-- ⚠ 默认(不传参)= 标脏。说不清是不是一次真编辑就按最严的算 —— 漏标的代价是
--    玩家按着一个过期的宏而屏幕上什么都没说,比多提示一次贵得多。
function ns.Changed(kind)
    if kind ~= "view" then ns.MarkDirty() end
    for _, fn in ipairs(ns.callbacks) do pcall(fn) end
end

function ns.Print(msg)
    print("|cff88ccffDodoGuanzhu|r " .. tostring(msg))
end

-- ── 名字的规范化与校验:**只有这一份** ────────────────────────────────
-- 🔴 首轮三个模块各写了一份(Slash 剥 -服务器、Capture 不剥;非法字符校验两处各一份),
--    那是 canon 说的「同一不变式两份手写实现 = 静默分歧发生器」:两边单独看都对,
--    漂了没人读得出来,而症状是"面板说重复了、宏里却有两个他"。判据 =「这俩不一致谁会发现」。

-- 这些字符进了宏正文会**破坏条件语法**(拆断 [ ] 分组、逗号分隔、多命令分号)。
-- 空白同样致命:@名字 后面一个空格,解析器就把后面的当技能名了。
local BAD = "[%[%]%,%;%|%s]"

-- 去重/比较用。剥掉 -服务器 后缀 + 转小写。
-- ⚠ 剥后缀是**故意**的:同服的人 GetUnitName 不给后缀、跨服给,同一个人在两种情况下
--    会拿到两个字符串。不剥的话他能被录进去两次,而两行看起来一模一样。
function ns.NormalizeName(name)
    if type(name) ~= "string" then return nil end
    local base = name:match("^([^%-]+)") or name
    return strlower(base)
end

function ns.SameName(a, b)
    local na, nb = ns.NormalizeName(a), ns.NormalizeName(b)
    return na ~= nil and na == nb
end

-- → ok, reason。写宏和录入**必须用同一个**,否则会出现"录得进去但写不出宏"的死结。
function ns.ValidateName(name)
    if type(name) ~= "string" or name == "" then return false, "名字是空的" end
    if name:find(BAD) then
        return false, "名字里有 [ ] , ; | 或空格 —— 这些会拆坏宏条件"
    end
    return true
end

-- ── 「名单改了,但还没写进宏」───────────────────────────────────────
-- 🔑 Preview 预测的是**名单**,而你按下去执行的是**已经写进宏栏的那份宏** —— 两者可以不同步。
--    没有这个标记的话,面板会用"下次会给谁"的口气说一件当下不成立的事。
local dirty = false
function ns.MarkDirty()  dirty = true  end
function ns.ClearDirty() dirty = false end
function ns.IsDirty()    return dirty  end

-- 技能名。C_Spell.GetSpellName 拿不到时(未学会 / 早期加载)回落成 nil,
-- 调用方要自己处理 —— 宁可不写宏,也不要写一个技能名是 nil 的宏。
function ns.SpellName()
    local ok, n = pcall(C_Spell.GetSpellName, ns.PI_SPELL_ID)
    return ok and n or nil
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ns.EnsureDB()
        f:UnregisterEvent("ADDON_LOADED")
        if ns.Slash and ns.Slash.Init then ns.Slash.Init() end
    end
end)
ns.frame = f
