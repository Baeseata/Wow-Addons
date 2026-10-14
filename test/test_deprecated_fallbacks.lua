-- 全仓静态守卫:只由暴雪「弃用兼容包」提供的全局,不许裸用而没有正式写法兜着。
--
-- 跑法(repo 根目录):  lua test/test_deprecated_fallbacks.lua [插件名=目录 ...]
--   A/B:把某个插件换成一份种了违规的拷贝 —— DodoAirdrop=<拷贝的 DodoAirdrop 目录>
--
-- 为什么要它:Blizzard_Deprecated* 这批兼容包每个文件开头都是
--   if not GetCVarBool("loadDeprecationFallbacks") then return end
-- ⇒ 玩家关掉这个 CVar,下表左边的全局**今天**就是 nil;而 12.1.5 一口气整包删了 10 个
-- (物品那包就在里面,d2aa743 修过)。剩下的随时轮到。裸用它们的代码坏掉的样子有两种:
-- 裸调用直接 Lua 报错(DodoAirdrop 的团队警报),或者藏在 pcall / 存在性判断后面**静默失效**
-- (DodoCombatHUD / DodoXuefei 的沸点格判「没点天赋」、DodoUnholy 判「技能都没学」)——
-- 后一种比前一种更难查。2026-10-14 全仓扫过,修完之后这张表上每个名字都有正式写法兜着。
--
-- 规则:非注释、非字符串的代码里,只要以**裸标识符**引用了下表左边的名字,
-- 前后 WINDOW 行之内就必须出现右边任一正式写法(典型形状:`(C_X and C_X.F) or F`、
-- 或者 `if C_X.F then ... elseif F then ...`)。
-- ⚠ 覆盖面 != 规则适用面:它只认表里这些名字。暴雪下次新弃用一批,要人往表里加
--   (来源 = Gethe/wow-ui-source 的 Interface/AddOns/Blizzard_Deprecated*/ 下各文件)。
-- ⚠ 「附近出现」是启发式,不是作用域分析:同一个文件两个函数挨得很近时可能互相作保。
--   它挡的是「整段只认裸全局」这个真实发生过的形状,不是所有可能的写法。

local WINDOW = 12

-- 名字 = { 正式写法(出现任一即可), 出处 }
local DEPRECATED = {
    IsPlayerSpell                 = { { "C_SpellBook.IsSpellKnown" }, "Blizzard_DeprecatedSpellBook" },
    IsSpellKnown                  = { { "C_SpellBook.IsSpellKnown", "C_SpellBook.IsSpellInSpellBook" }, "Blizzard_DeprecatedSpellBook" },
    IsSpellKnownOrOverridesKnown  = { { "C_SpellBook.IsSpellInSpellBook" }, "Blizzard_DeprecatedSpellBook" },
    GetSpecialization             = { { "C_SpecializationInfo.GetSpecialization" }, "Blizzard_DeprecatedSpecialization" },
    GetSpecializationInfo         = { { "C_SpecializationInfo.GetSpecializationInfo" }, "Blizzard_DeprecatedSpecialization" },
    GetInspectSpecialization      = { { "C_SpecializationInfo.GetInspectSpecialization" }, "Blizzard_Deprecated/Shared/Deprecated_12_1_0" },
    RaidNotice_AddMessage         = { { "RaidWarningUtil.AddMessage" }, "Blizzard_DeprecatedRaidWarning" },
    CombatLogGetCurrentEventInfo  = { { "C_CombatLog.GetCurrentEventInfo" }, "Blizzard_DeprecatedCombatLog" },
    -- 12.1.5 已经整包删掉的(Blizzard_DeprecatedItemScript):回归守卫,别让它们再长回来。
    GetItemInfo                   = { { "C_Item.GetItemInfo" }, "Blizzard_DeprecatedItemScript(12.1.5 已删)" },
    GetItemInfoInstant            = { { "C_Item.GetItemInfoInstant" }, "Blizzard_DeprecatedItemScript(12.1.5 已删)" },
    IsEquippableItem              = { { "C_Item.IsEquippableItem" }, "Blizzard_DeprecatedItemScript(12.1.5 已删)" },
    GetDetailedItemLevelInfo      = { { "C_Item.GetDetailedItemLevelInfo" }, "Blizzard_DeprecatedItemScript(12.1.5 已删)" },
}

-- 豁免:键 = "文件|名字"(不写行号 —— 行号写下那一刻就开始漂)。理由必须是可以去核实的事实。
local EXEMPT = {
    ["DodoSays/Trace.lua|CombatLogGetCurrentEventInfo"] =
        "死分支:COMBAT_LOG_EVENT_UNFILTERED 从不注册(12.x 注册即 ADDON_ACTION_FORBIDDEN,见同文件 \"deliberately NOT registered\" 那段)",
}

local OVERRIDE = {}
for _, a in ipairs(arg or {}) do
    local name, dir = a:match("^([%w_]+)=(.+)$")
    assert(name, "参数要写成 插件名=目录,收到: " .. a)
    OVERRIDE[name] = dir
end

local checks, fails = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then fails = fails + 1; print("FAIL: " .. msg) end
    return cond
end

-- 把一行变成「只剩代码」:字符串内容清空、行尾注释去掉;块注释由调用方按状态跳过。
local function codeOf(line)
    local s = line:gsub('"[^"]*"', '""'):gsub("'[^']*'", "''")
    return (s:gsub("%-%-.*$", ""))
end

-- 「裸标识符引用」:前面不是字母数字下划线、不是 . 或 :(那是别人的成员),后面不接字母数字下划线。
local function refsBare(code, name)
    local start = 1
    while true do
        local i, j = code:find(name, start, true)
        if not i then return false end
        local before = i > 1 and code:sub(i - 1, i - 1) or ""
        local after = code:sub(j + 1, j + 1)
        if not before:match("[%w_.:]") and not after:match("[%w_]") then return true end
        start = j + 1
    end
end

-- 匹配器自测,两个方向都要灵(子串匹配止于词中间 ⇒ 一定匹错,所以先证明它不会)。
do
    local cases = {
        { "if IsPlayerSpell(id) then", "IsPlayerSpell", true },
        { "local ok = pcall(IsPlayerSpell, x)", "IsPlayerSpell", true },
        { "x = C_Item.GetItemInfo(link)", "GetItemInfo", false },
        { "x = ns.GetSpecialization()", "GetSpecialization", false },
        { "x = self:GetSpecialization()", "GetSpecialization", false },
        { "x = GetSpecializationInfo(i)", "GetSpecialization", false },
        { "x = MyIsPlayerSpell(id)", "IsPlayerSpell", false },
        { 'print("call IsPlayerSpell(1)")', "IsPlayerSpell", false },
        { "x = 1 -- see IsPlayerSpell()", "IsPlayerSpell", false },
    }
    for _, c in ipairs(cases) do
        local got = refsBare(codeOf(c[1]), c[2])
        check(got == c[3], ("匹配器自测:%q 里找 %s 应为 %s,实际 %s"):format(c[1], c[2], tostring(c[3]), tostring(got)))
    end
end

local function readFile(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local s = fh:read("a"); fh:close()
    return s
end

local p = io.popen('git ls-files -- "*.lua"')
local listing = p and p:read("a") or ""
if p then p:close() end

local scanned, guarded, exempted, usedExempt = 0, 0, 0, {}
for path in listing:gmatch("[^\r\n]+") do
    local addon, rest = path:match("^(Dodo[%w_]*)/(.+)$")
    -- 测试 / 工具不进 CF 包、不在玩家那儿跑;DodoProbe 是诊断插件,它直接问裸全局就是它的本职。
    if addon and addon ~= "DodoProbe" and not rest:find("^test/") and not rest:find("^tools/")
            and not rest:find("/test/") and not rest:find("/tools/") then
        local src = readFile((OVERRIDE[addon] or addon) .. "/" .. rest)
        if src then
            scanned = scanned + 1
            local lines, inBlock = {}, false
            for raw in (src .. "\n"):gmatch("([^\n]*)\n") do
                local line = raw:gsub("\r$", "")
                local code
                if inBlock then
                    code = ""
                    if line:find("]]", 1, true) then inBlock = false end
                elseif line:match("^%s*%-%-%[%[") then
                    code = ""
                    if not line:find("]]", 1, true) then inBlock = true end
                else
                    code = codeOf(line)
                end
                lines[#lines + 1] = code
            end
            for i, code in ipairs(lines) do
                for name, spec in pairs(DEPRECATED) do
                    if refsBare(code, name) then
                        local key = addon .. "/" .. rest .. "|" .. name
                        if EXEMPT[key] then
                            exempted = exempted + 1; usedExempt[key] = true
                        else
                            local found = false
                            for k = math.max(1, i - WINDOW), math.min(#lines, i + WINDOW) do
                                for _, repl in ipairs(spec[1]) do
                                    if lines[k]:find(repl, 1, true) then found = true; break end
                                end
                                if found then break end
                            end
                            if check(found, ("%s/%s 第 %d 行裸用了 %s(%s 提供,关掉 loadDeprecationFallbacks 就是 nil),"
                                    .. "前后 %d 行内没有正式写法 %s"):format(addon, rest, i, name, spec[2], WINDOW,
                                    table.concat(spec[1], " / "))) then
                                guarded = guarded + 1
                            end
                        end
                    end
                end
            end
        end
    end
end

check(scanned > 0, "git ls-files 一个 .lua 都没列出来(不在 repo 根目录跑?git 起不来?)—— 没扫等于没守")
for key, why in pairs(EXEMPT) do
    check(usedExempt[key], "豁免 " .. key .. " 已经用不上了(那处引用没了)—— 删掉这条豁免:" .. why)
end

print(("扫了 %d 个文件:%d 处裸引用都有正式写法兜着,%d 处走豁免。"):format(scanned, guarded, exempted))
print(("%d checks, %d failures"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
