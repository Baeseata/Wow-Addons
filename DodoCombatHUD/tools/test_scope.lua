-- 守一条 luac 和纯函数测试都够不着的规矩:
--   **模块级 local 必须声明在「第一次被某个函数体赋值」之前。**
-- 0.9.0 首次真机就崩在这:`local segHost` 写在 BuildHUD **下面** ⇒ BuildHUD 里那句
-- `segHost = CreateFrame(...)` 赋的是**全局**,而 ApplyLayout 读的 upvalue 恒为 nil
-- ⇒ 登录即 `attempt to index upvalue 'segHost' (a nil value)`。
--
-- 🔑 为什么现有的检查全放过它:
--   · `luac -p` —— 写全局是**合法 Lua**,语法层面完全没问题
--   · tools/test_resource.lua —— 只覆盖 Resource.lua 的纯函数,够不着框体装配
--   两套检查各自完备,坏的是接缝(canon rules/engineering.md guard 家族 (i))。
-- 跑法:lua tools/test_scope.lua

local FILE = "DodoCombatHUD.lua"
local NAMES = {
    "root", "power", "health", "cast",
    "segHost", "segPool", "segsDead",
    "mainPower", "mainToken", "secondary", "DB",
    -- 0.10 的三排 aura 容器 + 当前专精。加新的模块级 local 记得同步这张清单 ——
    -- 不加的话这个 guard 对它**完全失明**,而那正是 0.9.0 首次真机崩掉的那条缝。
    "lustBox", "raidBox", "curSpec", "FLOW_DOWN",
    "rightBox",   -- 0.11:右侧两排合并后的真容器(lustBox/raidBox 退化成它的两个视图)
    "cdRow",      -- 0.13:自身增益改固定格位,原来的单容器 cdBox 已删
    "cdRowPad",   -- 沸点那个固定格占掉的左侧留白(Boiling.lua 推进来)
    "cdOverflowSig",
    "configMode", "preConfigLocked",   -- 0.13.2 配置模式
    "HudDragStart", "HudDragStop",     -- 0.13.3 占位框也当拖拽把手
}

local lines = {}
for l in io.lines(FILE) do lines[#lines + 1] = l end
assert(#lines > 500, "没读到源文件,后面全是空转")

-- 模块级 local 声明:行首就是 local(不缩进)
local function declLine(name)
    for i, l in ipairs(lines) do
        if l:match("^local%s+.*%f[%w_]" .. name .. "%f[^%w_]") then return i end
    end
end

-- 函数体内的**整名赋值**:必然带缩进(模块级声明不缩进)。
-- `segPool[i] = b` 这种索引赋值不算 —— 它不重新绑定那个名字。
local function firstAssign(name)
    for i, l in ipairs(lines) do
        if l:match("^%s+" .. name .. "%s*=[^=]") then return i end
    end
end

local pass, fail = 0, 0
for _, name in ipairs(NAMES) do
    local d, a = declLine(name), firstAssign(name)
    if not d then
        fail = fail + 1
        print(("  FAIL %s: 找不到模块级 `local %s` 声明"):format(name, name))
    elseif a and a < d then
        fail = fail + 1
        print(("  FAIL %s: 第 %d 行在函数体里赋值,但 `local` 到第 %d 行才声明 ⇒ 那次赋的是**全局**")
            :format(name, a, d))
    else
        pass = pass + 1
    end
end

-- ── ② 「推送成功才记标记」的结构守卫 ─────────────────────────────
--
-- 本仓栽过**两次**同一个洞(2026-08-16 aura filter、同日 DoT 那排),0.13 又新写了第三份
-- (ApplyCdFilters)⇒ canon「修类不修例」:与其指望每次都记得,不如让机器盯着。
--
-- 洞长这样:`b.sig = sig` / `slot.spellID = sid` 写在 pcall **外面** ⇒ 推送失败照样
-- 标记成"推过了" ⇒ 从此永不重试 ⇒ 容器停在建组时那份空 filter,而**空 candidateFilters
-- 在暴雪那边是「全放行」** ⇒ 那一格显示你身上所有增益,且全程零报错。
-- 最毒的是取证签名:查的时候 `sig` 里躺着完整的真表,读起来完全像"推下去了"。
--
-- 判据:每个这类赋值,往上走到最近的 `pcall(function()` 或 `if ok then` ——
-- **必须先撞到 `if ok then`**。撞到 pcall = 它在成功分支外面。
local MARKS = { "slot%.spellID = sid", "b%.sig = sig" }
local guarded, unguarded = 0, 0
for i, l in ipairs(lines) do
    local hit = false
    -- 行尾允许带注释(本仓那三处里就有一处带)。⚠ 这不是"放宽正则"——
    -- 尾注释不改变语义;真正不许放宽的是「让匹配器去迁就一种**语义不同**的写法」。
    for _, m in ipairs(MARKS) do
        if l:match("^%s+" .. m .. "%s*$") or l:match("^%s+" .. m .. "%s+%-%-") then hit = true end
    end
    if hit then
        local ok = false
        for j = i - 1, math.max(1, i - 12), -1 do
            if lines[j]:match("^%s*if ok then%s*$") then ok = true break end
            if lines[j]:match("pcall%(function%(%)") then break end
        end
        if ok then guarded = guarded + 1
        else
            unguarded = unguarded + 1
            print(("  FAIL 第 %d 行 `%s` 不在 `if ok then` 里 ⇒ 推送失败也会被记成\"推过了\"")
                :format(i, (l:gsub("^%s+", ""))))
        end
    end
end
-- 反空转:一个都没扫到 = 这条 guard 在替一个不存在的东西背书(比没有更坏)。
-- 0.13 有三处:DoT / 自身增益 / ApplyBoxFilter。**改名了就来改这儿**,别把它注释掉。
assert(guarded + unguarded >= 3,
    ("只扫到 %d 处「推送成功才记标记」,应该至少 3 处 —— 锚点跟源码漂了,这条 guard 是空转的")
    :format(guarded + unguarded))
if unguarded > 0 then fail = fail + unguarded else pass = pass + 1 end
print(("  「推送成功才记标记」:%d 处全在成功分支内"):format(guarded))

-- 反空转:名字一个都没查等于这个 guard 没跑,而「没跑」和「全过」在输出里长得一样
assert(pass + fail >= #NAMES, "扫到的名字数对不上,guard 自己坏了")
print(("\n%d passed, %d failed  (%d names + 1 结构检查)"):format(pass, fail, #NAMES))
os.exit(fail == 0 and 0 or 1)
