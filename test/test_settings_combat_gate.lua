-- 全仓离线测试:战斗中「打开设置」不许碰暴雪设置系统,脱战后补开。
--
-- 跑法(repo 根目录):  lua test/test_settings_combat_gate.lua [插件=目录 ...]
--   A/B:把某个插件换成一份种了违规的拷贝再跑 ——
--        lua test/test_settings_combat_gate.lua DodoGrid=<拷贝的 DodoGrid 目录>
--   加 -v 列出每个插件本次「兜底」了哪些客户端 API。
--
-- 为什么要它:2026-10-13 HOME 团本里 BugSack 抓到
--   [ADDON_ACTION_BLOCKED] 插件 'DodoGuanzhu' 尝试调用保护功能 'OpenSettingsPanel()'
-- Settings.OpenToCategory 底下就是那个受保护函数。被拦的保护调用**不抛 Lua 错**,pcall 接不住
-- ⇒ 只能在调用之前闸 InCombatLockdown()。DodoGuanzhu 自己那份在 DodoGuanzhu/test/test_open_combat.lua;
-- 本文件管其余**所有**直接调 Settings.OpenToCategory 的插件,外加一道**静态盘点**:
-- 仓里新冒出来的调用点没登记进下面的 CASES(或 COVERED_ELSEWHERE)就红 —— 修类,不只修这九例。
--
-- 做法:每个插件在一个**全新的环境表**里加载它**真的**源文件,只 stub 客户端 API,
-- 从玩家真会走的入口(slash 命令 / 小地图右键)打开,数 Settings.OpenToCategory 被调了几次。
--
-- ⚠ 证不了的(只有真机答得了):
--   ① 真客户端里 PLAYER_REGEN_ENABLED 那一帧 InCombatLockdown() 是不是已经 false;
--   ② 脱战后由**事件**(不是按键)触发的那次 OpenToCategory 会不会被别的限制拦。
--   这两条 DodoGuanzhu 0.1.2 的真机验收会先答 —— 它过了,这里的九个才算真过。

local verbose = false
local OVERRIDE = {}
for _, a in ipairs(arg or {}) do
    if a == "-v" then verbose = true
    else
        local name, dir = a:match("^([%w_]+)=(.+)$")
        assert(name, "参数要么是 -v,要么是 插件名=目录,收到: " .. a)
        OVERRIDE[name] = dir
    end
end

local checks, fails = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then fails = fails + 1; print("FAIL: " .. msg) end
    return cond
end

-- 客户端给 string 加了 trim(`msg:trim()`);它挂在字符串元表上,只能往真 string 表里补。
string.trim = string.trim or function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function readFile(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local s = fh:read("a"); fh:close()
    return s
end

---------------------------------------------------------------------------------------------------
-- 客户端 stub。照 canon:没设过的字段就是 nil;只有大写开头的**方法名**才答函数;
-- Create* 必须返回新对象;尺寸类 Get* 答数。兜底到的名字全记下来(-v 打印),别让它悄悄替 bug 遮丑。
---------------------------------------------------------------------------------------------------
-- 模板会往框体上挂的子对象(cb.Text / slider.Low ……)。这些名字答一个子区域,不答函数。
local CHILD_KEYS = {
    Text = true, Label = true, Low = true, High = true, Title = true, TitleText = true,
    Slider = true, Icon = true, NineSlice = true, Bg = true, Border = true, Middle = true,
    Left = true, Right = true, ScrollBar = true, ScrollChild = true, Inset = true, EditBox = true,
    Back = true, Forward = true, MinText = true, MaxText = true, RightText = true, LeftText = true,
    TopText = true, Value = true, Container = true, CloseButton = true, Header = true,
}
local NUMBER_GETTERS = {
    GetWidth = 100, GetHeight = 20, GetStringWidth = 50, GetStringHeight = 12, GetLeft = 0,
    GetRight = 100, GetTop = 20, GetBottom = 0, GetScale = 1, GetEffectiveScale = 1,
    GetFrameLevel = 1, GetNumPoints = 1, GetValue = 0, GetAlpha = 1, GetID = 0, GetNumLines = 1,
    GetMinMaxValues = 0, GetValueStep = 1, GetCursorPosition = 0, GetNumber = 0, GetLineHeight = 12,
}

-- 一个插件一个 harness:全新的环境表、全新的框体表、全新的 Settings。插件之间零共享状态。
local function NewHarness()
    local h = { combat = false, opened = {}, printed = {}, frames = {}, errors = {},
                fallbacks = {}, nilGlobals = {}, categories = {} }
    local nextID = 1000

    local function note(k) h.fallbacks[k] = (h.fallbacks[k] or 0) + 1 end

    local NewRegion
    local regionMeta = { __index = function(t, k)
        if type(k) ~= "string" then return nil end
        local first = k:sub(1, 1)
        if first ~= first:upper() or first == "_" then return nil end   -- 小写字段 = 没设过 = nil
        local v
        if CHILD_KEYS[k] then
            v = NewRegion(); note("." .. k)
        elseif k:match("^Create") then
            v = function() return NewRegion() end; note(k)
        elseif NUMBER_GETTERS[k] then
            local n = NUMBER_GETTERS[k]; v = function() return n end
        elseif k == "GetCenter" or k == "GetSize" then
            v = function() return 0, 0 end
        elseif k == "GetName" then
            v = function(self) return self._name end       -- 匿名框体真机也答 nil
        elseif k == "GetText" then
            v = function() return "" end
        elseif k:match("^Get") or k:match("^Is") or k:match("^Has") or k:match("^Can") then
            v = function() return nil end; note(k)
        else
            v = function() return nil end; note(k)
        end
        rawset(t, k, v)
        return v
    end }

    NewRegion = function()
        local r = { _events = {}, _scripts = {}, _shown = true }
        function r:RegisterEvent(e) self._events[e] = true end
        function r:RegisterUnitEvent(e) self._events[e] = true end
        function r:UnregisterEvent(e) self._events[e] = nil end
        function r:UnregisterAllEvents() self._events = {} end
        function r:IsEventRegistered(e) return self._events[e] == true end
        function r:SetScript(k, fn) self._scripts[k] = fn end
        function r:GetScript(k) return self._scripts[k] end
        function r:HookScript(k, fn)
            local old = self._scripts[k]
            self._scripts[k] = old and function(...) old(...); return fn(...) end or fn
        end
        function r:Show() self._shown = true end
        function r:Hide() self._shown = false end
        function r:SetShown(v) self._shown = v and true or false end
        function r:IsShown() return self._shown end
        function r:IsVisible() return self._shown end
        h.frames[#h.frames + 1] = r
        return setmetatable(r, regionMeta)
    end

    function h.newCategory(name)
        nextID = nextID + 1
        local cat = NewRegion()
        cat.ID, cat.name = nextID, name
        function cat:GetID() return self.ID end
        function cat:GetName() return self.name end
        h.categories[name] = h.categories[name] or cat
        if not h.topCategory and not tostring(name):match("^sub:") then h.topCategory = cat end
        return cat
    end

    -- settingsCalls 数的是「碰了设置系统几次」(任何 Settings.* 调用都算)。战斗中这个数必须不动 ——
    -- 不只 OpenToCategory:懒建面板的插件第一次打开时会先 Register*,那也是在碰设置系统。
    h.settingsCalls = 0
    local function touch(fn) return function(...) h.settingsCalls = h.settingsCalls + 1; return fn(...) end end
    local Settings = {
        OpenToCategory = touch(function(id) h.opened[#h.opened + 1] = id end),
        RegisterCanvasLayoutCategory = touch(function(_, name) return h.newCategory(name) end),
        RegisterVerticalLayoutCategory = touch(function(name) return h.newCategory(name) end),
        RegisterCanvasLayoutSubcategory = touch(function(_, _, name) return h.newCategory("sub:" .. tostring(name)) end),
        RegisterVerticalLayoutSubcategory = touch(function(_, name) return h.newCategory("sub:" .. tostring(name)) end),
        RegisterAddOnCategory = touch(function() end),
    }
    setmetatable(Settings, { __index = function(_, k)
        note("Settings." .. k)
        return touch(function() return NewRegion() end)
    end })

    local env = {}
    h.env = env
    local base = {
        string = string, table = table, math = math, os = os, coroutine = coroutine, utf8 = utf8,
        pairs = pairs, ipairs = ipairs, next = next, type = type, tostring = tostring,
        tonumber = tonumber, select = select, pcall = pcall, xpcall = xpcall, error = error,
        assert = assert, setmetatable = setmetatable, getmetatable = getmetatable,
        rawget = rawget, rawset = rawset, rawequal = rawequal, unpack = table.unpack,
        format = string.format, strfind = string.find, strsub = string.sub, strlower = string.lower,
        strupper = string.upper, strmatch = string.match, gsub = string.gsub, strlen = string.len,
        strrep = string.rep, strbyte = string.byte, strchar = string.char,
        floor = math.floor, ceil = math.ceil, abs = math.abs, max = math.max, min = math.min,
        tinsert = table.insert, tremove = table.remove, sort = table.sort,
        date = os.date, time = os.time,
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
        strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end,
        strsplit = function(sep, s)
            local out = {}
            for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
            return table.unpack(out)
        end,
        print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
            h.printed[#h.printed + 1] = table.concat(parts, " ")
        end,
        InCombatLockdown = function() return h.combat end,
        CreateFrame = function(_, name, _, template)
            local f = NewRegion()
            if name then
                f._name = name
                env[name] = f
                -- 带名字的模板框体,真机会顺带建 <名字>Text / Low / High 这几个全局子对象
                -- (DodoUnholy 就是 _G[cb:GetName() .. "Text"]:SetText(...) 这么取的)。
                if template then
                    for _, s in ipairs({ "Text", "Low", "High" }) do env[name .. s] = env[name .. s] or NewRegion() end
                end
            end
            return f
        end,
        GetProfessions = function() return nil end,
        UnitClass = function() return "Death Knight", "DEATHKNIGHT", 6 end,
        Settings = Settings,
        SlashCmdList = {},
        hooksecurefunc = function() end,
        GetLocale = function() return "enUS" end,
        GetTime = function() return 0 end,
        GetCursorPosition = function() return 0, 0 end,
        GetCVar = function() return nil end,
        GetCVarBool = function() return false end,
        C_Timer = { After = function() end, NewTicker = function() return NewRegion() end,
                    NewTimer = function() return NewRegion() end },
        StaticPopupDialogs = {}, UISpecialFrames = {},
        STANDARD_TEXT_FONT = "Fonts/FRIZQT__.TTF",   -- 值无所谓,只要是个串
    }
    base.UIParent = NewRegion(); base.Minimap = NewRegion(); base.GameTooltip = NewRegion()
    base._G = env
    setmetatable(env, { __index = function(_, k)
        local v = base[k]
        if v == nil then h.nilGlobals[k] = true end
        return v
    end })

    -- 把一个事件派给所有登记了它的框体。每个 handler 各自 pcall:
    -- 一个跟本测试无关的 handler 炸了也要记成红(stub 不够 = 这条没测到),但不许拖垮别的。
    function h.fire(event, ...)
        local snapshot = {}
        for _, f in ipairs(h.frames) do
            if f._events[event] and f._scripts.OnEvent then snapshot[#snapshot + 1] = f end
        end
        for _, f in ipairs(snapshot) do
            local ok, err = pcall(f._scripts.OnEvent, f, event, ...)
            if not ok then h.errors[#h.errors + 1] = event .. ": " .. tostring(err) end
        end
    end

    -- returnLocal:要这个文件**顶层的某个 local** 就传它的名字(在源码末尾追加一句 return)。
    -- 用来拿 DodoGrid/Core.lua 那张 local defaults —— 设置页的控件按它取初值,手搓一份就会漂。
    function h.load(path, addonName, ns, returnLocal)
        local src = readFile(path)
        if not src then error("读不到 " .. path) end
        if returnLocal then src = src .. "\nreturn " .. returnLocal end
        local chunk = assert(load(src, "@" .. path, "t", env))
        return chunk(addonName, ns)
    end

    -- 只要一个文件的顶层(defaults / slash),不要它的事件:真机上它的 handler 全在 PLAYER_LOGIN
    -- 之后才有东西可操作,而本测试不模拟登录 ⇒ 把这次加载新建的框体的事件全摘掉。
    function h.loadQuiet(path, addonName, ns, returnLocal)
        local n = #h.frames
        local ret = h.load(path, addonName, ns, returnLocal)
        for i = n + 1, #h.frames do h.frames[i]._events = {} end
        return ret
    end

    function h.reset() h.opened = {}; h.printed = {} end
    return h
end

---------------------------------------------------------------------------------------------------
-- 用例。每个插件:setup 用**真的**源文件把它跑到「玩家能点开设置」的状态,open = 玩家真会走的入口,
-- expect = 期望传给 OpenToCategory 的那个值(在 setup 之后读)。callSites = 本插件里所有
-- OpenToCategory 调用点所在的文件(静态盘点对账用)。
---------------------------------------------------------------------------------------------------
local function topID(h) return h.topCategory and h.topCategory.ID end

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = deepCopy(v) end
    return out
end

local CASES = {
    { name = "DodoCursor", callSites = { "Options.lua" },
      setup = function(h, dir)
          h.env.DodoCursor = {}
          h.load(dir .. "/Options.lua", "DodoCursor", {})
          h.env.DodoCursor:InitOptions()
      end,
      open = function(h) h.env.SlashCmdList.DODOCURSOR("") end,
      expect = topID },

    { name = "DodoNumbers", callSites = { "Options.lua" },
      setup = function(h, dir)
          h.env.DodoNumbers = {}
          h.load(dir .. "/Options.lua", "DodoNumbers", {})
          h.env.DodoNumbers:InitOptions()
      end,
      open = function(h) h.env.SlashCmdList.DODONUMBERS("") end,
      expect = topID },

    { name = "DodoGrid", callSites = { "Options.lua" },
      setup = function(h, dir)
          h.ns = {}
          local defaults = h.loadQuiet(dir .. "/Core.lua", "DodoGrid", h.ns, "defaults")
          assert(type(defaults) == "table", "DodoGrid/Core.lua 顶层没有 local defaults 了")
          h.ns.db = deepCopy(defaults)   -- 真机由 Core 的 PLAYER_LOGIN 做;那个 handler 还会建 45 个格子,不跑它
          h.load(dir .. "/Options.lua", "DodoGrid", h.ns)
          h.ns.InitOptions()
      end,
      open = function(h) h.env.SlashCmdList.DODOGRID("config") end,
      expect = topID },

    { name = "DodoNameplate", callSites = { "Options.lua" },
      setup = function(h, dir)
          h.ns = {}
          for _, f in ipairs({ "Guards.lua", "Locale.lua", "Classification.lua", "Core.lua" }) do
              h.loadQuiet(dir .. "/" .. f, "DodoNameplate", h.ns)
          end
          h.ns.db = deepCopy(h.ns.defaults)   -- 真机由 Core 的 PLAYER_LOGIN 做
          h.ns.ApplyLocale()
          h.load(dir .. "/Options.lua", "DodoNameplate", h.ns)
          h.ns.InitOptions()
      end,
      open = function(h) h.env.SlashCmdList.DODONAMEPLATE("") end,
      expect = topID },

    { name = "DodoGatherMate", callSites = { "DodoGatherMate.lua" },
      setup = function(h, dir)
          h.load(dir .. "/DodoGatherMate.lua", "DodoGatherMate", {})
          h.fire("ADDON_LOADED", "DodoGatherMate")
          h.fire("PLAYER_LOGIN")
      end,
      open = function(h) h.env.SlashCmdList.DODOGATHERMATE("") end,
      expect = topID },

    { name = "DodoInspect", callSites = { "Minimap.lua" },
      setup = function(h, dir)
          h.ns = {}
          h.env.DodoInspectDB = {}
          h.load(dir .. "/Config.lua", "DodoInspect", h.ns)
          h.load(dir .. "/Locales.lua", "DodoInspect", h.ns)
          h.ns.L = h.ns.L or (h.ns.Locales and h.ns.Locales.en)
          h.load(dir .. "/Minimap.lua", "DodoInspect", h.ns)
          -- 分类注册住在 Options.lua 一大段 pcall 里,跟这条路无关;Minimap.lua 只认 ns.OptionsCategory。
          h.ns.OptionsCategory = h.newCategory("DodoInspect")
          h.ns.SetupMinimapButton()
      end,
      open = function(h)
          local b = h.env.DodoInspectMinimapButton
          b._scripts.OnClick(b, "RightButton")      -- 右键 = 开设置,DodoGuanzhu 正是在这条路上被拦的
      end,
      expect = function(h) return h.ns.OptionsCategory end },

    { name = "DodoSays", callSites = { "DodoSays.lua" },
      setup = function(h, dir)
          h.ns = {}
          h.load(dir .. "/Util.lua", "DodoSays", h.ns)       -- slash 先拿 ns.QUADRANT_BY_ID 认象限
          h.load(dir .. "/Options.lua", "DodoSays", h.ns)
          h.load(dir .. "/DodoSays.lua", "DodoSays", h.ns)
          h.ns.db = h.ns.db or deepCopy(h.ns.DEFAULTS or {})
          -- 故意不派 ADDON_LOADED:让面板保持「还没建」,第一次打开才建 —— 这样「战斗中连
          -- Register* 都不许碰」那条(场景 6)才够得着 BuildOptions 是不是也在闸后面。
      end,
      open = function(h) h.env.SlashCmdList.DODOSAYS("config") end,
      expect = topID },

    { name = "DodoStatHUD", callSites = { "DodoStatHUD.lua" },
      setup = function(h, dir)
          h.load(dir .. "/DodoStatHUD.lua", "DodoStatHUD", {})
          h.fire("ADDON_LOADED", "DodoStatHUD")
          h.fire("PLAYER_LOGIN")
      end,
      open = function(h) h.env.SlashCmdList.DODOSTATHUD("") end,
      expect = topID },

    { name = "DodoUnholy", callSites = { "DodoUnholy.lua" },
      setup = function(h, dir)
          h.load(dir .. "/DodoUnholy.lua", "DodoUnholy", {})
          h.fire("ADDON_LOADED", "DodoUnholy")
          h.fire("PLAYER_LOGIN")
      end,
      open = function(h) h.env.SlashCmdList.DODOUNHOLY("config") end,
      expect = topID },
}

-- 有自己那份测试、不归本文件管的调用点。
local COVERED_ELSEWHERE = {
    ["DodoGuanzhu/Options.lua"] = "DodoGuanzhu/test/test_open_combat.lua",
}

---------------------------------------------------------------------------------------------------
-- 场景(跟 DodoGuanzhu/test/test_open_combat.lua 同一套,外加第 6 条)
---------------------------------------------------------------------------------------------------
local function saysCombat(s)
    s = tostring(s or "")
    return s:find("combat", 1, true) or s:find("战斗", 1, true) or s:find("combate", 1, true)
end

local function runCase(c)
    local dir = OVERRIDE[c.name] or c.name
    local tag = c.name .. ": "

    local function fresh()
        local h = NewHarness()
        local ok, err = pcall(c.setup, h, dir)
        -- setup 崩 = 这个插件一条都没测到。必须红,而且要红得看得出是 harness 的问题。
        if not check(ok, tag .. "setup 崩了(stub 不够 => 本插件零覆盖): " .. tostring(err)) then return nil end
        return h
    end
    local function open(h)
        local ok, err = pcall(c.open, h)
        check(ok, tag .. "open 崩了: " .. tostring(err))
    end

    local h = fresh()
    if not h then return end

    -- 0. 正向对照:脱战打开 ⇒ 真的去开了。证明这条路通到 OpenToCategory,下面的「没开」才有意义。
    --    expect 在这次打开**之后**才读:懒建面板的插件(DodoSays)第一次打开时才注册分类。
    h.reset(); h.combat = false; open(h)
    local expect = c.expect(h)
    check(expect ~= nil, tag .. "脱战打开过一次,仍拿不到期望的分类 —— 正向对照没有比较对象")
    check(#h.opened == 1 and h.opened[1] == expect,
        tag .. "脱战打开:应调 OpenToCategory(期望的分类) 一次,实际 " .. #h.opened .. " 次")

    -- 1. 战斗中打开 ⇒ 设置系统一下都不许碰(不只 OpenToCategory),并且说一句话。
    h.reset(); h.combat = true
    local before = h.settingsCalls
    open(h)
    check(#h.opened == 0, tag .. "战斗中打开:不许调 OpenToCategory(会被拦成 ADDON_ACTION_BLOCKED),实际 " .. #h.opened .. " 次")
    check(h.settingsCalls == before, tag .. "战斗中打开:任何 Settings.* 都不许碰,实际碰了 " .. (h.settingsCalls - before) .. " 次")
    check(#h.printed == 1 and saysCombat(h.printed[1]),
        tag .. "战斗中打开:应在聊天框说一句跟战斗有关的话(不说 = 玩家只看到「点不开」),实际 " .. #h.printed .. " 条")

    -- 2. 战斗中连点 ⇒ 不刷屏,仍然不开。
    open(h); open(h)
    check(#h.printed == 1, tag .. "战斗中连点三下:提示只该出一次,实际 " .. #h.printed .. " 条")
    check(#h.opened == 0, tag .. "战斗中连点三下:仍然一次都不许开")

    -- 3. 脱战 ⇒ 补开,且只开一次。
    h.combat = false; h.fire("PLAYER_REGEN_ENABLED")
    check(#h.opened == 1 and h.opened[1] == expect, tag .. "脱战事件:应补开一次,实际 " .. #h.opened .. " 次")
    h.fire("PLAYER_REGEN_ENABLED")
    check(#h.opened == 1, tag .. "再脱战一次:待办已清,累计应仍为 1 次,实际 " .. #h.opened .. " 次")

    -- 4. 脱战事件那一帧还锁着 ⇒ 不开、待办留着,下次真脱战再开。
    h.reset(); h.combat = true; open(h)
    h.fire("PLAYER_REGEN_ENABLED")
    check(#h.opened == 0, tag .. "脱战事件但仍锁着:不许开,实际 " .. #h.opened .. " 次")
    check(#h.printed == 1, tag .. "脱战事件但仍锁着:重新记待办不许再提示一次,实际 " .. #h.printed .. " 条")
    h.combat = false; h.fire("PLAYER_REGEN_ENABLED")
    check(#h.opened == 1, tag .. "下一次真脱战:应补开一次,实际 " .. #h.opened .. " 次")

    -- 5. 没在战斗中点过 ⇒ 进出战斗不许平白弹设置窗。
    h.reset(); h.combat = true; h.fire("PLAYER_REGEN_DISABLED")
    h.combat = false; h.fire("PLAYER_REGEN_ENABLED")
    check(#h.opened == 0, tag .. "没点过的一次进出战斗:不该弹设置窗,实际 " .. #h.opened .. " 次")

    check(#h.errors == 0, tag .. "有事件 handler 报错(stub 不够?): " .. tostring(h.errors[1]))

    -- 6. 全新加载、**第一次**打开就在战斗中 ⇒ 连懒建面板的 Register* 也不许碰;脱战照样补开。
    local h2 = fresh()
    if h2 then
        h2.combat = true
        local b2 = h2.settingsCalls
        open(h2)
        check(h2.settingsCalls == b2, tag .. "首次打开就在战斗中:任何 Settings.* 都不许碰(懒建面板也算),实际碰了 " .. (h2.settingsCalls - b2) .. " 次")
        h2.combat = false; h2.fire("PLAYER_REGEN_ENABLED")
        check(#h2.opened == 1, tag .. "首次打开就在战斗中:脱战应补开一次,实际 " .. #h2.opened .. " 次")
    end

    if verbose then
        local names = {}
        for k, n in pairs(h.fallbacks) do names[#names + 1] = k .. "x" .. n end
        table.sort(names)
        print(("  %s 兜底了 %d 个名字: %s"):format(c.name, #names, table.concat(names, " ")))
    end
end

for _, c in ipairs(CASES) do runCase(c) end

---------------------------------------------------------------------------------------------------
-- 静态盘点:仓里每一个(非注释行上的)OpenToCategory / OpenSettingsPanel / SettingsPanel 引用,
-- 所在文件都必须归某个用例或 COVERED_ELSEWHERE 管。
-- 新插件照抄一句 Settings.OpenToCategory 而没配闸 = 这里红,而不是等下一次团本 BugSack。
-- 文件清单按 git 判(git ls-files),git 起不来就红 —— 不退回扫磁盘,免得本机多出来的东西替它作答。
---------------------------------------------------------------------------------------------------
local expected = {}
for _, c in ipairs(CASES) do
    for _, f in ipairs(c.callSites) do expected[c.name .. "/" .. f] = "本文件 CASES" end
end
for f, by in pairs(COVERED_ELSEWHERE) do expected[f] = by end

local p = io.popen('git ls-files -- "*.lua"')
local listing = p and p:read("a") or ""
if p then p:close() end
local scanned, found = 0, {}
for path in listing:gmatch("[^\r\n]+") do
    -- 测试 / 工具目录不进 CF 包,也不在玩家那儿跑;它们引用这个名字是在断言它,不是在调用它。
    if not path:find("/test/", 1, true) and not path:find("/tools/", 1, true) and not path:match("^test/") then
        scanned = scanned + 1
        local src = readFile(path) or ""
        for line in src:gmatch("[^\n]*") do
            local code = line:match("^%s*(.-)%s*$")
            -- 认的是**名字出现**,不是「名字后面紧跟括号」:DodoGuanzhu 写的是
            -- pcall(Settings.OpenToCategory, id),只认 `OpenToCategory(` 会把它漏掉(第一版就漏了)。
            -- frontier 让 InterfaceOptionsFrame_OpenToCategory(经典版遗留,零售版不存在)不算数。
            if code:sub(1, 2) ~= "--" and (code:find("%f[%w_]OpenToCategory%f[^%w_]")
                    or code:find("%f[%w_]OpenSettingsPanel%f[^%w_]")
                    or code:find("%f[%w_]SettingsPanel%f[^%w_]")) then
                found[path] = true
                break
            end
        end
    end
end
check(scanned > 0, "静态盘点:git ls-files 一个 .lua 都没列出来(不在 repo 根目录跑?git 起不来?)—— 盘点没跑等于没盘")
for path in pairs(found) do
    check(expected[path] ~= nil, "静态盘点:" .. path .. " 调了 OpenToCategory,但没有任何战斗闸测试管它 —— "
        .. "照 DodoGuanzhu/Options.lua 加闸,再往本文件 CASES 里加一条")
end
for path, by in pairs(expected) do
    check(found[path], "静态盘点:登记了 " .. path .. "(" .. by .. "),但那里已经没有 OpenToCategory 调用 —— 登记过期了,删掉它")
end

print(("%d checks, %d failures"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
