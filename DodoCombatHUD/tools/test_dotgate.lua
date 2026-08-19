-- 离线测 DoT filter 的准入判据 PlainTrue + DotUnitEligible。
-- 跑法:lua tools/test_dotgate.lua(插件根目录)
--
-- 为什么值得单独测:这个判据错一个方向的后果**不对称** ——
--   判太松(该拦没拦)= filter 被暴雪静默丢掉 ⇒ 三格画同样的东西,**零报错**;
--   判太严(不该拦拦了)= 那排空着,一眼看得见,换个目标自己就好了。
-- ⇒ 判据必须 fail-closed,而且必须是**正向**的(见下面第二条 A/B)。
--
-- 从**真文件**里抠函数来跑,不手抄第二份 —— 手抄的那份会跟 bug 共享同一个误解。
local src = assert(io.open("DodoCombatHUD.lua", "rb")):read("a")
local plain = assert(src:match("(local function PlainTruthy%(v%).-\nend)"), "抠不到 PlainTruthy")
local gate  = assert(src:match("(local function DotUnitEligible%(%).-\nend)"), "抠不到 DotUnitEligible")

-- 反空转:确认抠到的确实是那两个函数体
assert(plain:find("issecretvalue", 1, true), "PlainTruthy 片段里没有 issecretvalue")
assert(gate:find("UnitCanAttack", 1, true),  "DotUnitEligible 片段里没有 UnitCanAttack")

local pass, fail = 0, 0
local function check(label, got, want)
    if got == want then pass = pass + 1
    else fail = fail + 1
        print(("  FAIL %s: got %s want %s"):format(label, tostring(got), tostring(want))) end
end

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local function boom() error("在副本里读不到 / API 没了 / 随便什么炸法") end
local T, F = function() return true end, function() return false end

-- 造一份 DotUnitEligible。st = 各 API 的 stub;mutate 非 nil 时先改源码(A/B 用)
local function build(st, mutate)
    local text = plain .. "\n" .. gate
    if mutate then text = mutate(text) end
    local env = {
        pcall = pcall, type = type,
        UnitExists    = st.exists    or T,
        UnitCanAttack = st.canAttack or F,
        UnitCanAssist = st.canAssist or F,
        issecretvalue = st.issecret  or function() return false end,
    }
    return assert(load(text .. "\nreturn DotUnitEligible", "gate", "t", env))()
end

print("== DotUnitEligible ==")
check("没目标                  -> 不合格", build{ exists = F }(), false)
check("友方(CanAttack=false)  -> 不合格", build{ canAttack = F }(), false)
check("敌方(CanAttack=true)   -> 合格",   build{ canAttack = T }(), true)
check("UnitExists 抛错         -> 不合格", build{ exists = boom }(), false)
check("UnitCanAttack 抛错      -> 不合格", build{ canAttack = boom }(), false)
check("CanAttack 返回 nil      -> 不合格", build{ canAttack = function() return nil end }(), false)
check("CanAttack 是 secret     -> 不合格",
      build{ canAttack = function() return SECRET end,
             issecret  = function(v) return v == SECRET end }(), false)
check("issecretvalue 自己抛错  -> 不合格", build{ canAttack = T, issecret = boom }(), false)
-- 🔴 暴雪 Unit* 系有一批返回 1/nil 的老 API。判据写成 `== true` 的话这条会红,
--    而真机上的表现是「DoT 那排一次都不显示」—— fail-closed、不报错、极难查。
check("CanAttack 返回 1        -> 合格",   build{ canAttack = function() return 1 end }(), true)
check("exists 是 secret        -> 不合格",
      build{ exists   = function() return SECRET end,
             issecret = function(v) return v == SECRET end }(), false)

-- ── A/B:种回三个**真会有人写出来**的缺陷,每条都必须变红 ──
-- 一个永远绿的判据测试,跟没有测试是同一回事。
print("== A/B(种回缺陷,下面四条必须都报 caught) ==")
local function ab(label, mutate, st, wrongAnswer)
    local ok, got = pcall(function() return build(st, mutate)() end)
    if ok and got == wrongAnswer then print("  caught  " .. label); pass = pass + 1
    else fail = fail + 1
        print(("  FAIL %s: 种回缺陷后结果没变(got %s)—— 这条 A/B 是空转的"):format(
              label, tostring(got))) end
end
local function sub(from, to)
    return function(t)
        local out = t:gsub(from, to)
        assert(out ~= t, "gsub 没命中:" .. from .. " —— 源码改了,这条 A/B 是空转的")
        return out
    end
end

-- ① 回到 0.11.1 那个**负向**判据。这条直接把 2026-08-19 那次实测钉成回归测试:
--    团里友方目标上 CanAttack=false **且** CanAssist=false ⇒ 负向式判成"合格"(错),
--    正向式判成"不合格"(对)。两个 stub 都给 false 就是那天真机的读数。
ab("用 not UnitCanAssist(负向判据)",
   function(t)
       t = sub("pcall%(UnitCanAttack, \"player\", \"target\"%)",
               "pcall(UnitCanAssist, \"player\", \"target\")")(t)
       return sub("return PlainTruthy%(canAttack%)", "return not canAttack")(t)
   end, { canAttack = F, canAssist = F }, true)

-- ② 判据写成 `v == true`(第一版就是这样,差点发出去)⇒ 返回 1 的老 API 恒判假
--    ⇒ DoT 那排一次都不显示。
ab("末尾写成 v == true",
   sub("return v ~= nil and v ~= false", "return v == true"),
   { canAttack = function() return 1 end }, false)

-- ③ 把 secret 那道闸拆掉 ⇒ secret 值走 truthy 判断被当成真
ab("拆掉 secret 闸",
   sub("if not okS or isS then return false end", "if false then return false end"),
   { canAttack = function() return SECRET end,
     issecret  = function(v) return v == SECRET end }, true)

-- ④ 「只有确认是 secret 才拦」(最顺手的那个写法)⇒ issecretvalue 问不出来时 fail-open
ab("issecretvalue 问不出来时放行",
   sub("if not okS or isS then return false end", "if okS and isS then return false end"),
   { canAttack = T, issecret = boom }, true)

print(("== %d passed, %d failed =="):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
