-- DodoGuanzhu 离线测试:战斗中点「打开设置」不许碰暴雪设置系统,脱战后补开。
--
-- 跑法(repo 根目录):  lua DodoGuanzhu/test/test_open_combat.lua [插件目录]
-- 插件目录默认 DodoGuanzhu;A/B 时传一份种了违规的拷贝进来。
--
-- 为什么要它:2026-10-13 HOME 团本里 BugSack 抓到
--   [ADDON_ACTION_BLOCKED] 插件 'DodoGuanzhu' 尝试调用保护功能 'OpenSettingsPanel()'
-- 被拦的保护调用**不抛 Lua 错**,外面两层 pcall 都看不见 ⇒ 只能在调用之前闸住。
-- 这份测试钉的就是「闸在不在、补开会不会发生、会不会刷屏」。
--
-- ⚠ 证不了的:真客户端里 PLAYER_REGEN_ENABLED 那一帧 InCombatLockdown() 是不是已经 false、
--    以及补开那一下会不会被别的限制(首领战等)拦。那两条只有真机答得了。
--
-- 做法:加载**真的** Options.lua,只把 EnsurePanel 里那一处 `BuildPanel()` 换成一个 stub 框体
-- (整块面板 UI 跟这条路无关,stub 它要几百行)。替换处数断言 == 1,免得悄悄没换上。

local DIR = (arg and arg[1]) or "DodoGuanzhu"

local checks, fails = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then fails = fails + 1; print("FAIL: " .. msg) end
end

---------------------------------------------------------------------------------------------------
-- stub:只建模这条路真会碰到的东西。没设过的字段就是 nil(别用返回 self 的 catch-all)。
---------------------------------------------------------------------------------------------------
local combat = false
function InCombatLockdown() return combat end

local frames = {}
function CreateFrame()
    local f = { events = {}, scripts = {}, shown = false }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:IsShown() return self.shown end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    frames[#frames + 1] = f
    return f
end

StaticPopupDialogs = {}
C_Timer = { After = function() end, NewTicker = function() end }

local opened = {}       -- 每次真去开设置面板就记一笔 —— 这就是战斗中不许发生的那件事
Settings = {
    RegisterCanvasLayoutCategory = function() return { GetID = function() return 4242 end } end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function(id) opened[#opened + 1] = id end,
}

local printed = {}
local ns = {}
ns.Print = function(s) printed[#printed + 1] = s end
ns.EnsureDB = function() ns.db = ns.db or {}; return ns.db end
ns.OnChanged = function() end

---------------------------------------------------------------------------------------------------
-- 加载
---------------------------------------------------------------------------------------------------
local fh = assert(io.open(DIR .. "/Options.lua", "rb"))
local src = fh:read("a"); fh:close()
local patched, n = src:gsub("\n    BuildPanel%(%)\r?\n", "\n    panel = CreateFrame(\"Frame\")\n")
check(n == 1, "harness: EnsurePanel 里的 BuildPanel() 调用点应恰好替换 1 处,实际 " .. n)
assert(load(patched, "@" .. DIR .. "/Options.lua"))("DodoGuanzhu", ns)

local init
for _, f in ipairs(frames) do
    if f.events.PLAYER_LOGIN and f.events.PLAYER_REGEN_ENABLED then init = f end
end
assert(init, "harness: 找不到注册了 PLAYER_LOGIN + PLAYER_REGEN_ENABLED 的那个 init 框体")
local function fire(event) init.scripts.OnEvent(init, event) end
local function reset() opened = {}; printed = {} end

fire("PLAYER_LOGIN")
local Open = ns.Options and ns.Options.Open
assert(type(Open) == "function", "harness: ns.Options.Open 没导出")

---------------------------------------------------------------------------------------------------
-- 用例
---------------------------------------------------------------------------------------------------
-- 0. 正向对照:脱战点 ⇒ 真的去开了。证明 stub 那条路通到 OpenToCategory,下面的「没开」才有意义。
reset(); combat = false; Open()
check(#opened == 1 and opened[1] == 4242, "脱战点:应调 OpenToCategory(4242) 一次,实际 " .. #opened .. " 次")

-- 1. 战斗中点 ⇒ 一次都不许碰设置系统,并且说一句话(不说 = 玩家只看到「点不开」)。
reset(); combat = true; Open()
check(#opened == 0, "战斗中点:不许调 OpenToCategory(那会被 C 层拦成 ADDON_ACTION_BLOCKED),实际 " .. #opened .. " 次")
check(#printed == 1 and tostring(printed[1]):find("战斗中", 1, true) ~= nil,
    "战斗中点:应在聊天框说一句「战斗中…」,实际 " .. #printed .. " 条")

-- 2. 战斗中连点 ⇒ 不刷屏。
Open(); Open()
check(#printed == 1, "战斗中连点三下:提示只该出一次,实际 " .. #printed .. " 条")
check(#opened == 0, "战斗中连点三下:仍然一次都不许开")

-- 3. 脱战 ⇒ 补开,且只开一次。
combat = false; fire("PLAYER_REGEN_ENABLED")
check(#opened == 1, "脱战事件:应补开一次,实际 " .. #opened .. " 次")
fire("PLAYER_REGEN_ENABLED")
check(#opened == 1, "再脱战一次:待办已清,累计开窗应仍为 1 次,实际 " .. #opened .. " 次")

-- 4. 脱战事件那一帧要是还锁着 ⇒ 不开、待办留着,下次真脱战再开。
reset(); combat = true; Open()
fire("PLAYER_REGEN_ENABLED")            -- combat 仍为 true
check(#opened == 0, "脱战事件但仍锁着:不许开,实际 " .. #opened .. " 次")
combat = false; fire("PLAYER_REGEN_ENABLED")
check(#opened == 1, "下一次真脱战:应补开一次,实际 " .. #opened .. " 次")

-- 5. 没在战斗中点过 ⇒ 脱战不许平白弹设置窗。
reset(); combat = false
fire("PLAYER_REGEN_DISABLED"); fire("PLAYER_REGEN_ENABLED")
check(#opened == 0, "没点过的脱战:不该弹设置窗,实际 " .. #opened .. " 次")

print(("%d checks, %d failures"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
