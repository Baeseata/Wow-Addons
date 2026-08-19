-- 离线测 DoT filter 的准入判据 DotUnitEligible。跑法:lua tools/test_dotgate.lua(插件根目录)
--
-- 为什么值得单独测:这个判据错一个方向的后果**不对称** ——
--   判太松(该拦没拦)= filter 被暴雪静默丢掉 ⇒ 三格画同样的东西,**零报错**,
--                      而且 slot.spellID 记下之后**永不重试** = 永久故障;
--   判太严(不该拦拦了)= 那排空着,一眼看得见,下次换目标自己就好了。
-- ⇒ 判据必须 fail-closed。这里逐条钉死,尤其是"问不出来"那两条。
--
-- 从**真文件**里抠函数来跑,不手抄第二份 —— 手抄的那份会跟 bug 共享同一个误解。
local src = assert(io.open("DodoCombatHUD.lua", "rb")):read("a")
local body = assert(src:match("(local function DotUnitEligible%(%).-\nend)"),
                    "抠不到 DotUnitEligible —— 函数改名了就来改这一行")

-- 反空转:确认抠到的确实是那个函数体,而不是一段碰巧匹配上的东西
assert(body:find("UnitCanAssist", 1, true), "抠到的片段里没有 UnitCanAssist,不是那个函数")

local pass, fail = 0, 0
local function check(label, got, want)
    if got == want then pass = pass + 1
    else fail = fail + 1
        print(("  FAIL %s: got %s want %s"):format(label, tostring(got), tostring(want))) end
end

-- 用给定的两个 stub 造一份 DotUnitEligible。mutate 非 nil 时先改源码(A/B 用)
local function build(exists, assist, mutate)
    local text = mutate and mutate(body) or body
    local env = { pcall = pcall, UnitExists = exists, UnitCanAssist = assist }
    local chunk = assert(load(text .. "\nreturn DotUnitEligible", "gate", "t", env))
    return chunk()
end

local function boom() error("secret / API 没了 / 随便什么炸法") end

print("== DotUnitEligible ==")
check("没目标           -> 不合格", build(function() return false end,
                                          function() return false end)(), false)
check("友方目标         -> 不合格", build(function() return true end,
                                          function() return true  end)(), false)
check("敌方目标         -> 合格",   build(function() return true end,
                                          function() return false end)(), true)
check("UnitExists 抛错  -> 不合格", build(boom, function() return false end)(), false)
check("UnitCanAssist 抛错-> 不合格", build(function() return true end, boom)(), false)

-- ── A/B:种回两个**真会有人写出来**的缺陷,测试必须变红 ──
-- 这一步不是走过场:一个永远绿的判据测试,跟没有测试是同一回事。
print("== A/B(种回缺陷,下面两条必须都报 caught) ==")
local function ab(label, mutate, exists, assist, wrongAnswer)
    local ok, got = pcall(function() return build(exists, assist, mutate)() end)
    if ok and got == wrongAnswer then print("  caught  " .. label); pass = pass + 1
    else fail = fail + 1
        print(("  FAIL %s: 种回缺陷后结果没变(got %s)—— 这个测试是空转的"):format(
              label, tostring(got))) end
end
-- ① 把 fail-closed 写反:问不出来就放行
ab("okA 失败时 return true", function(t)
        local out = t:gsub("if not okA then return false end", "if not okA then return true end")
        assert(out ~= t, "gsub 没命中 —— 源码改了,A/B 是空转的")
        return out
   end, function() return true end, boom, true)
-- ② 干脆不判敌友(最原始的那版就是这样,而它正是 0.11.0 那个 bug)
ab("不判敌友", function(t)
        local out = t:gsub("return not assist", "return true")
        assert(out ~= t, "gsub 没命中 —— 源码改了,A/B 是空转的")
        return out
   end, function() return true end, function() return true end, true)

print(("== %d passed, %d failed =="):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
