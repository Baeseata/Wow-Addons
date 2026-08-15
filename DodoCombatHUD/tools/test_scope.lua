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

-- 反空转:名字一个都没查等于这个 guard 没跑,而「没跑」和「全过」在输出里长得一样
assert(pass + fail == #NAMES, "扫到的名字数对不上,guard 自己坏了")
print(("\n%d passed, %d failed  (%d names checked)"):format(pass, fail, #NAMES))
os.exit(fail == 0 and 0 or 1)
