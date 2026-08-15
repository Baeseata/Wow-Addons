-- 离线测 SavedVariables 迁移。跑法:lua tools/test_migrate.lua(在插件根目录)
-- 从**真文件**里抠 DEFAULTS / CopyDefaults / 迁移块来跑,不手抄第二份 ——
-- 手抄的那份会跟 bug 共享同一个误解,测了等于没测。
local src = assert(io.open("DodoCombatHUD.lua", "rb")):read("a")

local defaults = assert(src:match("(local DEFAULTS = {.-\n})"), "抠不到 DEFAULTS")
local copyfn   = assert(src:match("(local function CopyDefaults.-\nend)"), "抠不到 CopyDefaults")
-- 迁移块 = 从 v0.7 那条起,到 powerColor 那块的 end 为止(目前最后一块)
-- 结束锚用 `local savedPT`(CopyDefaults 前那行),不锚某一块的结尾 ——
-- 那样以后**再加迁移块也不用改这里**,不然每加一块就要回来修锚点一次。
local migrate  = assert(src:match("(%-%- v0%.7.-)%s*local savedPT"),
                        "抠不到迁移块 —— 锚点漂了,先看 PLAYER_LOGIN 那段")
assert(#defaults > 200 and #copyfn > 100 and #migrate > 300, "抠到的片段太短,锚点多半没对上")

-- 0.10 起迁移块里多了两个外部依赖:`ns`(AuraSets.lua)和 `CurrentSpecID()`。
-- 🔑 `ns` 用**真的** AuraSets.lua,不手搓一份 —— 手搓的那份会跟 bug 共享同一个误解。
-- `CurrentSpecID` 只能 stub(它要真客户端),但它就返回一个常量,建模不了什么东西。
local TEST_SPEC = 258
local PREAMBLE = ([[
local ns = {}
assert(loadfile("AuraSets.lua"))("DodoCombatHUD", ns)
local function CurrentSpecID() return %d end
local curSpec
]]):format(TEST_SPEC)

local function build(order, defaultsOverride)
    local d = defaultsOverride or defaults
    local body
    if order == "correct" then
        body = migrate .. "\n local db = CopyDefaults(DEFAULTS, saved or {}) \n return db"
    else -- 负对照:故意把顺序调反(CopyDefaults 先跑)
        body = " local db = CopyDefaults(DEFAULTS, saved or {}) \n saved = db \n"
               .. migrate .. "\n return db"
    end
    return assert(load(PREAMBLE .. d .. "\n" .. copyfn
        .. "\nreturn function(saved)\n" .. body .. "\nend"))()
end

local run, runBad = build("correct"), build("reversed")
local pass, fail = 0, 0
local function check(label, got, want)
    if got == want then pass = pass + 1
    else fail = fail + 1; print(("  FAIL %s: got %s want %s"):format(label, tostring(got), tostring(want))) end
end

print("== 全新用户 ==")
local db = run(nil)
check("dotWidth", db.dotWidth, 36)
check("dotFontSize", db.dotFontSize, 16)
check("powerOn", db.powerOn, true)
check("secondaryOn", db.secondaryOn, true)
check("powerColors 是空表", type(db.powerColors) == "table" and next(db.powerColors) == nil, true)
check("powerColor 已从 DEFAULTS 移除", db.powerColor, nil)

print("== 老用户:dotSize + 手调过的 powerColor ==")
db = run({ dotSize = 45, dotFontScale = 0.45, powerColor = { 0.9, 0.1, 0.8 } })
check("dotWidth", db.dotWidth, 45)
check("dotFontSize", db.dotFontSize, 20)
check("老 powerColor 清掉", db.powerColor, nil)
check("搬进 powerColors.Insanity[1]", db.powerColors.Insanity[1], 0.9)
check("搬进 powerColors.Insanity[3]", db.powerColors.Insanity[3], 0.8)

print("== 幂等:已迁移过的再跑一遍不许变 ==")
db = run({ dotWidth = 50, dotHeight = 20, dotFontSize = 15,
           powerColors = { Insanity = { 0.1, 0.2, 0.3 } } })
check("dotWidth", db.dotWidth, 50)
check("Insanity 不被顶掉", db.powerColors.Insanity[1], 0.1)

print("== 已有 powerColors.Insanity 时,老 powerColor 不许覆盖它 ==")
db = run({ powerColor = { 1, 1, 1 }, powerColors = { Insanity = { 0.5, 0.5, 0.5 } } })
check("保留新的", db.powerColors.Insanity[1], 0.5)
check("老键仍清掉", db.powerColor, nil)

print("== v0.9.1:白色的 Insanity 覆盖要删掉(回落到亮紫)==")
db = run({ powerColors = { Insanity = { 1, 1, 1 } } })
check("白覆盖被删", db.powerColors.Insanity, nil)

print("== 但他自己调过的颜色不许动 ==")
db = run({ powerColors = { Insanity = { 0.3, 0.9, 0.2 } } })
check("自定义色保留", db.powerColors.Insanity[2], 0.9)

print("== 从 0.8 直升:白 powerColor 搬进去后也该被删掉 ==")
db = run({ powerColor = { 1, 1, 1 } })
check("搬进去又删掉", db.powerColors.Insanity, nil)
check("老键仍清掉", db.powerColor, nil)

print("== 0.10:dots 从扁平数组迁进按专精的桶 ==")
db = run({ dots = { 34914, 589, 335467 } })
check("老形状没了", rawget(db.dots, 1), nil)
check("进了当前专精那桶", #db.dots[TEST_SPEC], 3)
check("桶里第一个还是 VT", db.dots[TEST_SPEC][1], 34914)

print("== 0.10:CopyDefaults 不许动玩家已经分好的桶 ==")
-- 这条断言正是"把 savedDots 那行特判删掉"的依据:DEFAULTS.dots 现在是**空表**,
-- CopyDefaults 递归进去一个键都加不了。⚠ 下面紧跟着一条负对照证明这个断言是灵的。
db = run({ dots = { [TEST_SPEC] = { 111 } } })
check("桶原样", db.dots[TEST_SPEC][1], 111)
check("桶长度 1", #db.dots[TEST_SPEC], 1)

print("== 负对照:DEFAULTS.dots 要是**非空**,CopyDefaults 就会污染玩家的桶 ==")
-- 把默认值换成非空的重跑一遍。红不了的话上面那条绿是空转 ——
-- 它就证明不了"删掉 savedDots 特判是安全的"这件事。
local pollutedDefaults = defaults:gsub("dots%s*=%s*{},", "dots = { 7, 8, 9 },", 1)
assert(pollutedDefaults ~= defaults, "负对照的锚点没命中,这条等于没做")
local runPoison = build("correct", pollutedDefaults)
local poisoned = runPoison({ dots = { [TEST_SPEC] = { 111 } } })
if #poisoned.dots[TEST_SPEC] == 1 and poisoned.dots[1] == nil then
    fail = fail + 1
    print("  FAIL 负对照没红 —— 这个测试对 DEFAULTS.dots 空不空不敏感")
else
    pass = pass + 1
    print(("  OK 非空默认值确实会灌进来:dots[1]=%s 桶长度=%d")
        :format(tostring(poisoned.dots[1]), #poisoned.dots[TEST_SPEC]))
end

print("== 负对照:顺序调反应当丢值 ==")
local bad = runBad({ dotSize = 45, dotFontScale = 0.45, powerColor = { 0.9, 0.1, 0.8 } })
if bad.dotWidth == 45 and bad.powerColors and bad.powerColors.Insanity then
    fail = fail + 1
    print("  FAIL 顺序负对照没红 —— 这个测试对顺序不敏感,前面的绿是假的")
else
    pass = pass + 1
    print(("  OK 顺序反了就丢:dotWidth=%s Insanity=%s")
        :format(tostring(bad.dotWidth), tostring(bad.powerColors and bad.powerColors.Insanity)))
end

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
