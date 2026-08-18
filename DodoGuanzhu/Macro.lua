-- DodoGuanzhu :: Macro.lua
-- 名单 → 宏正文 → 写进宏栏。**这是整个插件唯一真正"动"游戏的地方**,其余模块只是在编数据。
--
-- 三条硬约束(实测 12.1.0 build 120100 / 美服 Illidan):
--   ① 战斗中客户端**直接 block** 建/改/删宏 ⇒ 一切写操作前置 InCombatLockdown(),
--      战斗里来的请求排队、PLAYER_REGEN_ENABLED 补做(跟 DodoGrid/Dispel.lua 同一套)。
--   ② 正文按**码位**截断,不按字节(写 300 汉字 → 回读 768 字节 / 256 码位)⇒ 中文名不吃亏,
--      但预算一律用 utf8len 算,`#s` 是字节数,在这个文件里永远不是答案。
--   ③ EditMacro 撞名会**直接重写玩家自己的宏** ⇒ 宏名必须带 Dodo 前缀,
--      而且只在 GetMacroIndexByName 找到我们自己那个名字时才 Edit。
--
-- 🔑 插件在战斗中不做任何决策:这里生成一整条 fallback 链,交给宏自己的求值器
--    (SecureCmdOptionParse 从左往右取**第一组全部成立**的)。连"谁在射程内"都不算 ——
--    宏条件里根本没有射程判断:实测 `inrange` 是个**未识别条件、被直接忽略**
--    (`[@player,zzzgarbage]` 照样成立;走近走远跑 `[@target,inrange]` 纹丝不动)。
--    射程归 Preview 用 C_Spell.IsSpellInRange 显示,那只给人看,不参与出手。

local ADDON, ns = ...

local Macro = {}
ns.Macro = Macro

-- 宏名前缀。**这是安全要求不是风格**,见上面 ③。
local NAME_PREFIX = "Dodo "

-- 宏名预算(码位)。UI 那个输入框是 16;API 层只证到"12 码位 / 32 字节能原样存回来",
-- 再往上没人量过 ⇒ 16 是个**赌**。所以 Write 写完必须回读确认名字没被客户端改短,
-- 赌输了要当场看得见(见 Write 尾部),而不是安静地每次多建一个宏。
local NAME_LIMIT = 16

-- 每位成员的条件后缀。help = 能对他施善意法术(排掉敌对/无法协助的),
-- nodead = 别把 2 分钟 CD 喂给一具尸体。**12 个码位一位,8 位就是 96** ——
-- 正文预算的大头在这儿,是故意花的:少一个条件就多一次白给。
local MEMBER_COND = ",help,nodead"

-- 图标。宏面板上一眼认得出是灌注;拿不到就退问号(134400)。
local function iconFor()
    local ok, tex = pcall(C_Spell.GetSpellTexture, ns.PI_SPELL_ID)
    return (ok and tex) or 134400
end

-- 数码位。**不用 strlenutf8**(不保证在),这个只依赖 string.byte:
-- UTF-8 的续接字节都落在 0x80..0xBF,把它们跳掉剩下的就是码位数。
local function utf8len(s)
    local n = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
end

-- 截到 n 个码位。**按字节切会切出半个汉字**,客户端拿到非法 UTF-8 就是一串方块 ——
-- 所以要找的是"第 n+1 个码位从第几个字节开始",在那儿断。
local function utf8trunc(s, n)
    local seen = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then
            seen = seen + 1
            if seen > n then return s:sub(1, i - 1) end
        end
    end
    return s
end

-- 一个人在宏条件里写成什么。**现在直接返回名字本身。**
--
-- 🔴 这个函数是整份代码里唯一一个**没验过的假设**的落脚点,故意收在这一处。
--    假设 = 「队伍/团队里的成员,名字能被 `[@名字,help,nodead]` 解析成一个 unit」。
--    已实测的那半(12.1.0 / 美服 Illidan):主城里对**陌生人**,`[@名字,exists]` 和
--    `[@名字,help]` **都判假**;而裸的 `[@名字]` 会成立 —— 名字被原样当目标传下去了,
--    只是条件判不了它。当时玩家单人,所以"队友到底行不行"**没量到**。
--    ⇒ 怎么证伪:进队,把队友名字填进名单,跑
--      `SecureCmdOptionParse("[@<队友名>,help,nodead] X")`。回 nil = 假设不成立。
--    ⇒ 证伪之后**只改这一个函数**:把名字映射成 unit token(遍历 party1..4 / raid1..40
--      拿 UnitName 比对 —— 那些 API 全是明文,脱战随便算)。代价是 token 会随队伍变动漂,
--      所以那天还要在 GROUP_ROSTER_UPDATE 上补一次 Write。**别提前把那份复杂度铺到别处**,
--      现在铺了就等于替一个可能不成立的未来付钱,而且铺散了以后改不回来。
--
-- ⚠ 跨服名字带 "-服务器" 后缀(GetUnitName(unit, true) 的行为),**原样保留**:
--    宏条件认得它,而剥掉后缀在跨服同名的情况下会指错人。代价是它吃码位(见 BuildBody)。
function Macro.TokenFor(name)
    return name
end

-- 名字里有非法字符 = 这条条件会把**整串**宏条件语法搞坏,而坏掉的不是这一位,
-- 是**它后面整条 fallback 链**(宏是从左往右取第一组成立的,链断在哪儿哪儿以后全没了)。
-- ⇒ 宁可整个拒绝写,也不能写一个"看着有 8 个人、实际到第 3 位就断"的宏 —— 后者
--   在真需要它的那一刻才现形,而那时没人会想到是名字里有个逗号。
--
-- 🔴 这里**不再自己判**哪些字符非法,一律问 `ns.ValidateName`。首轮的教训:
--    Slash / Capture / 本文件各写了一份规则,而且互相不一致(Slash 剥 -服务器后缀、Capture 不剥)
--    ⇒ 出现过"录得进去、却写不出宏"这种谁都说不清是哪一边错的死结。
--    canon:同一不变式两份手写实现 = 静默分歧发生器,两边单独看都对,漂了没人读得出来。

-- 名字有可能是 **secret**(GetUnitName 对队伍/团队外的单位就会给 secret)。
-- 🔴 对 secret 做 tostring / 拼接 / 比较是**当场崩**,而这个函数的调用点恰恰是
--    "出错了正在拼一句给人看的提示" —— 在那儿崩等于把一条可读的错误换成一次卡死。
--    所以拼进任何字符串之前先问一句;`issecretvalue` 在老客户端上可能不存在,故先探。
local function isSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, yes = pcall(issecretvalue, v)
    return ok and yes and true or false
end

-- 能安全拼进提示的写法。**永远不 tostring 一个可能是 secret 的值。**
local function safeLabel(v)
    if isSecret(v) then return "(读不出来的名字)" end
    if type(v) ~= "string" then return "(不是名字)" end
    return v
end

-- 名单 → 有序的条件组。**顺序就是优先级**,不在这儿之外的任何地方再排一次序。
-- 返回 nil, 索引, 名字, 原因 = 有一位用不了(调用方负责报是哪一位、为什么)。
local function clauses(list)
    local out = {}
    -- 焦点排最前:焦点是玩家**当次主动指定**的人,比名单里任何一位都新鲜。
    if list.useFocus then out[#out + 1] = "[@focus" .. MEMBER_COND .. "]" end
    -- ⚠ 不写 `ipairs(list.members or {})`:`or {}` 只兜得住 nil,兜不住"members 是个字符串/数字"
    --   (SavedVariables 被外部改过就会这样)。而这两个 Lua 版本的表现**正好相反**:
    --   客户端的 5.1 上 `ipairs(非表)` **直接抛错**;本机 5.4 上反而**静默零次迭代** ——
    --   后者更糟,它会安安静静写出一个只剩 `[@player]` 的宏,而面板上那 8 个人还在。
    local mem = type(list.members) == "table" and list.members or {}
    for i = 1, #mem do
        local name = mem[i]
        local token = Macro.TokenFor(name)
        -- 顺序要紧:secret 检查必须排在 ValidateName(它会 `name:find`)和下面的拼接之前。
        if isSecret(token) then return nil, i, name, "读不出来(是个 secret 值)" end
        local ok, why = ns.ValidateName(token)
        if not ok then return nil, i, name, why end
        out[#out + 1] = "[@" .. token .. MEMBER_COND .. "]"
    end
    -- 末尾兜底**故意不带 help/nodead**:它必须无条件成立,否则前面全落空时整个宏哑火。
    -- (自己死了这一位也成立 —— 施法本身会失败,但那是游戏的事,不该由宏条件替它决定。)
    if list.selfLast then out[#out + 1] = "[@player]" end
    return out
end

-- 完整宏正文,或 nil。**返回 nil 的两种情况都是"宁可不写,也不写个坏宏"**:
-- 读不到技能名(Core.SpellName 的原话)、或名单里有用不了的名字。
-- 想知道是哪一种,走 Write —— 它会给出可读的原因;这儿只负责能不能出正文。
--
-- 📐 预算实账(zhCN 客户端,"能量灌注" 4 码位)。**这几个数是离线跑出来的,不是手数的** ——
--    手数那版把 "#showtooltip" 数成 13 个字母、又漏了每位成员收尾的 "]",一处一个连错两处:
--    固定开销 = "#showtooltip\n" 13 + "/cast " 6 + 焦点组 20 + "[@player]" 9 + " 技能名" 5 = **53**;
--    留给成员的是 255-53 = **202 码位**,每位 = 名字码位 + **15**("[@" + ",help,nodead" + "]")。
--    ⇒ 8 位同服满长名(12 码位)= 8×27 = 216,**超 14** —— 也就是说
--      MAX_MEMBERS=8 **并不保证装得下**,长度检查是真会开火的闸,不是摆设。
--    ⇒ enUS 上 "Power Infusion" 是 14 码位,固定开销变 63、预算只剩 192,更紧。
function Macro.BuildBody(list)
    if type(list) ~= "table" then return nil end
    local spell = ns.SpellName()
    if not spell then return nil end
    local parts = clauses(list)
    if not parts then return nil end
    -- 首行 `#showtooltip` 后面**故意不跟技能名**:留空它自己取第一个 /cast 的技能 ——
    -- 图标提示一样对,还省下一整个技能名的码位(enUS 上连前面那个空格是 15 个码位)。
    if #parts == 0 then
        -- 名单空 + 两个开关都关。这不是错误,是一个合法的退化状态(等于普通的对当前目标施法),
        -- 单独写一支只为了别拼出 "/cast  技能" 里那个多余的空格。
        return "#showtooltip\n/cast " .. spell
    end
    return "#showtooltip\n/cast " .. table.concat(parts) .. " " .. spell
end

-- 正文的**码位**数(不是字节),**或 nil**。给面板当预算读数用。
-- 🔴 出不了正文时返回 **nil,不是 0** —— 这条是"修类不修例":0 是个完全合法的长度值,
--    于是 Slash 和 Options **各自独立**把它渲染成了绿色的 `0 / 255`,
--    **一个看着最健康的数,恰恰出现在最坏的时候**(技能名还没加载好 / 名单里有非法字符,
--    而这两种情况下 Write 都会当场拒写)。返回 nil 就没法被当成数字显示 ——
--    面板被迫自己表一次态,而不是替一个不存在的正文报出"还很宽裕"。
function Macro.Length(list)
    local body = Macro.BuildBody(list)
    return body and utf8len(body) or nil
end

-- 宏名。前缀 + 方案名,截到 NAME_LIMIT 码位。
--
-- ⚠ 截断的碰撞面比 Core.ListByName 的重名**宽得多**,别把两者当成同一条约束:
--   ListByName 要**完全同名**才认成同一套 —— "团本速刷" 和 "团本保底" 各是各的方案;
--   而宏名只剩 NAME_LIMIT - #NAME_PREFIX = **11 个码位**,那两套的前 11 个码位一样
--   ⇒ **共用同一个宏,后写的赢**,而面板上它们看起来毫无关系(改 A 却把 B 的宏冲了)。
--   ⇒ 这不是"把既有约束往前挪几个字",是一条**新的、更松的**约束。
-- 🔴 不截断更糟,而且糟得很隐蔽:客户端自己截了之后,GetMacroIndexByName(全名)
--   **永远找不到我们建的那个** ⇒ 每次 Write 都 CreateMacro 一个新的,一路把 120 个槽位吃光,
--   而每一次调用都"成功"。⇒ 截断是止血,Write 尾部的回读才是真正的闸。
function Macro.MacroNameFor(list)
    local n = (type(list) == "table" and type(list.name) == "string" and list.name ~= "")
        and list.name or "默认"
    return utf8trunc(NAME_PREFIX .. n, NAME_LIMIT)
end

-- 账号宏还剩几格。GetNumMacros 的**第一个**返回值是账号宏、第二个是角色宏 ——
-- 我们只建账号宏(CreateMacro 第 4 参传 nil),所以只数第一个。
local function slotsLeft()
    if type(GetNumMacros) ~= "function" then return 0 end
    local used = GetNumMacros() or 0
    return (MAX_ACCOUNT_MACROS or 120) - used
end

-- 战斗中攒下的写入请求。键是 list **表本身**,不是名字 —— 名字战斗中可能被改。
local pending = {}

-- 写进宏栏。返回 ok, err(err 是可读中文,调用方直接 ns.Print 就行)。
-- 幂等:同名的宏就地 Edit,不重复建。
function Macro.Write(list)
    if type(list) ~= "table" then return false, "没有可写的方案。" end
    -- 这四个是**全局老式 API**,不在 C_Macro 里(C_Macro 只有另外 4 个函数)。
    -- 逐个 type 检查而不是信"它一定在":这插件的全部价值就是不崩。
    if type(CreateMacro) ~= "function" or type(EditMacro) ~= "function"
        or type(GetMacroIndexByName) ~= "function" then
        return false, "这个客户端上没有宏 API(CreateMacro / EditMacro / GetMacroIndexByName)。"
    end
    -- 战斗中客户端直接拒,别去试。判据永远是 InCombatLockdown(),不是"我记得刚才在打" ——
    -- 那是判战斗的唯一凭据。
    -- ⚠ 这条**是真会走到的**:首轮 Slash 自己也拦了一道战斗,把这里的排队整条短路了;
    --   那道拦已经撤掉 ⇒ 战斗中点写宏就落到这儿。
    -- 🔑 所以措辞的第一件事是让人看出**这不是失败,是排队**。调用方会把这句当 err 打出来
    --   (返回 false 是给调用方判"现在还没写成"用的),而玩家读到的只有这一句 ——
    --   写成"改不了宏"他会在战斗结束后再点一次,然后困惑于宏为什么被写了两遍。
    if InCombatLockdown() then
        pending[list] = true
        return false, "战斗中客户端不让动宏 —— 已排队,脱战会自动补写(不用再点一次)。"
    end

    local spell = ns.SpellName()
    if not spell then
        return false, "读不到「能量灌注」的技能名(没学会,或者还没加载完)。先不写 —— "
            .. "一个技能名是 nil 的宏比没有宏更糟:它按下去毫无反应,而人会以为是自己手滑。"
    end

    -- 原因直接用 ns.ValidateName 的原话 —— 面板/录入侧问的是同一个函数,
    -- 玩家在两个地方看到的说法一致(首轮两处各写一份措辞,同一个名字两种说法)。
    local parts, badIndex, badName, badWhy = clauses(list)
    if not parts then
        return false, ("名单第 %d 位「%s」%s,整条 fallback 链会从这儿断掉。删了重录一次。")
            :format(badIndex or 0, safeLabel(badName), badWhy or "用不了")
    end

    local body = Macro.BuildBody(list)
    if not body then return false, "生成不出宏正文。" end
    local len = utf8len(body)
    -- **别让它静默截断** —— 被截掉的正好是排在最后的那几位,也就是兜底的 [@player]。
    -- 那种宏平时看不出毛病,只在前面全落空的那一次哑火,而那正是它存在的理由。
    if len > ns.BODY_LIMIT then
        return false, ("宏正文 %d 码位,超过 %d 的上限,没写。删掉一两位再试 —— 跨服名字带 \"-服务器\" 后缀,最占地方。")
            :format(len, ns.BODY_LIMIT)
    end

    local name = Macro.MacroNameFor(list)
    local index = GetMacroIndexByName(name)
    local ok, err, created, oldBody
    if index and index > 0 then
        -- 🔑 改之前先抄一份旧正文,给下面的"写进去被截短了"当**回滚锚点**。
        --    走 Edit 这条路时被截断是最坏的一种:它不是"没写成",而是**把一份原来好好的宏
        --    就地改成了截断版**,而截掉的正好是排在最后的 [@player] 兜底 ——
        --    那种宏平时一点毛病都看不出来,只在前面全落空的那一次哑火。
        local okOld, _, _, prev = pcall(GetMacroInfo, index)
        if okOld and type(prev) == "string" then oldBody = prev end
        -- icon 传 nil = 那一项不改 ⇒ 玩家自己给这个宏挑过的图标不会被我们覆盖回去。
        ok, err = pcall(EditMacro, index, name, nil, body)
    elseif slotsLeft() <= 0 then
        return false, ("账号宏槽位满了(上限 %d)。到宏面板腾一个再来。"):format(MAX_ACCOUNT_MACROS or 120)
    else
        ok, err = pcall(function() created = CreateMacro(name, iconFor(), body, nil) end)
        if ok and (not created or created == 0) then
            return false, "建宏失败(槽位可能刚被别的东西占掉)。"
        end
    end
    if not ok then return false, "写宏时客户端抛错:" .. tostring(err) end

    -- 🔑 回读:验的是**当初那个症状**(宏栏里有一个叫 name、内容是这条链的宏),
    --    不是"我调用没报错"。这两件事在这儿真的会分家,而且分家的方式都很安静:
    local found = GetMacroIndexByName(name)
    if not found or found <= 0 then
        -- 名字被客户端改短了 ⇒ 下次再 Write,GetMacroIndexByName(全名) 照样找不到,
        -- 于是又建一个……一路吃到 120 格满,每一次都"成功"。
        -- 刚建出来的那个索引握在手里 ⇒ 精确删掉它,别留下一个每次都会再生一遍的孤儿。
        local undone = false
        if created and created > 0 then undone = pcall(DeleteMacro, created) end
        -- ⚠ 措辞分两支:走 Edit 那条路时**什么都没新建**,说"已撤掉"就是在描述一件没发生的事,
        --   而人会照着这句话去宏面板找那个不存在的残留。给错理由比不给更坏。
        return false, ("客户端把宏名「%s」改短了,我们再也认不出它。把方案名起短一点。%s")
            :format(name, undone and "(刚建的那个已经撤掉了。)" or "")
    end
    -- ⚠ 别用 GetMacroBody:12.1 源码里一次都没出现,可能压根不存在,裸调会当场崩。
    --   暴雪自己的宏界面全程用 GetMacroInfo 的**第 3 个返回值**。
    local okInfo, _, _, back = pcall(GetMacroInfo, found)
    if okInfo and type(back) == "string" and utf8len(back) < len then
        -- 🔴 **只报错不回滚 = 坏宏留在宏栏里。** 这跟上面名字被改短那条要对称:
        --    那条握着刚建出来的索引精确删掉它,这条也必须把宏栏恢复原状,
        --    否则玩家收到一句"没写成"、而宏栏里静静躺着一份**被截掉兜底的宏**。
        --    ⚠ 措辞照样分三支 —— 说一件没发生的事("已撤掉")比不说更坏。
        local note
        if created and created > 0 then
            -- 建出来的:整个删掉,回到"本来就没有这个宏"。
            note = pcall(DeleteMacro, created)
                and "(刚建的那个已经撤掉了。)"
                or "(⚠ 撤不掉,宏栏里那份是坏的,去宏面板手动删掉。)"
        elseif oldBody then
            -- 就地改的:把旧正文写回去,**而且回读确认它真的回去了** ——
            -- "调用没报错"和"宏栏里现在是旧正文"在这个文件里已经分家过一次了。
            local okBack = pcall(EditMacro, found, name, nil, oldBody)
            local okChk, _, _, now = pcall(GetMacroInfo, found)
            note = (okBack and okChk and type(now) == "string" and now == oldBody)
                and "(原来那份已经还回去了。)"
                or "(⚠ 没能还原,宏栏里现在是被截断的那份,去宏面板改回来。)"
        else
            -- 改之前那次回读就没拿到旧正文 ⇒ 手里根本没有可还原的东西。如实说。
            note = "(⚠ 读不到改之前的正文,没法还原;宏栏里现在是被截断的那份。)"
        end
        return false, ("宏写进去被截短了(要 %d 码位,回读只有 %d)—— 上限跟我们以为的不一样。名单得更短。%s")
            :format(len, utf8len(back), note)
    end
    -- 回读拿到的不是 string(nil / 别的)时**不报错**:那只说明我们验不了,
    -- 不说明写坏了。把"验不了"当成"坏了"会让插件在一个完全正常的客户端上永远拒绝工作。

    -- 名单跟宏栏这一刻是一致的 ⇒ 清掉 dirty。**只有走到这儿才清** —— 上面每一条
    -- return false 都意味着宏栏里没有(或不是)这份名单,那时候清就是替一件没发生的事盖章。
    -- ⚠ 已知的粗糙:dirty 是**全局一个 bit**,多套方案共用。写方案 B 也会把"方案 A 改了没写"
    --   一并清掉。Preview 说的是**当前在编**的那套,所以日常单套无碍;多套时它会偏乐观。
    ns.ClearDirty()
    return true
end

-- 战斗中攒下的写入,脱战补做 —— 跟 DodoGrid/Dispel.lua 是同一套 dirty flag。
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function()
    if not next(pending) then return end
    -- 先把队列换掉再写:Write 万一又判到战斗中(不该发生,但便宜),重新排的那条
    -- 会落进新表,不会被下面这轮顺手清掉。
    local queued = pending
    pending = {}
    local db = ns.db or (ns.EnsureDB and ns.EnsureDB())
    -- 🔑 只补**现在还在 db.lists 里**的方案。战斗中被删掉的那套自然就走不到这儿,
    --    不需要另记一条"它还在不在" —— 那种状态一定会漂,而漂了没人看得出来。
    for _, L in ipairs((db and db.lists) or {}) do
        if queued[L] then
            local okW, errW = Macro.Write(L)
            -- 报一句。**不报的话这就是一个静默动作**:玩家在战斗里点了写宏、
            -- 什么也没发生,脱战后宏悄悄出现(或者悄悄没出现),两种他都分不出来。
            if okW then
                ns.Print(("脱战后已写入宏「%s」。"):format(Macro.MacroNameFor(L)))
            elseif errW then
                ns.Print(errW)
            end
        end
    end
end)
