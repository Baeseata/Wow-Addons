-- DodoGuanzhu :: Slash.lua
-- /dgz —— **这是完整的后路,面板只是它的皮。**
-- 立场直接抄 DodoCombatHUD/Options.lua 文件尾那段:Settings API 哪天换形状、或者
-- Options.lua 自己在加载时报错,插件的**每一个**能力都还得够得着。落到写法上是两条:
--   ① 本文件不依赖任何别的模块能加载成功,跨模块调用一律先探在不在;
--   ② 别人没加载时要报「**谁**没加载」,而不是抛一个 nil index 的 Lua 错误 ——
--      后者会让人以为是自己命令打错了,然后去改一条本来就对的命令。
--
-- 🔑 这个文件**不做任何「谁该吃灌注」的决策**:射程/存活的判定归 Preview,宏正文归 Macro,
--    名字的规范化/比较/合法性归 Core(ns.NormalizeName / ns.SameName / ns.ValidateName),
--    战斗中能不能写宏归 Macro.Write —— 这儿只干两件事:改数据、把数据念出来。
--    多写一份别人已经有的判断,两处迟早漂,而且两边单独看都对
--    (同一不变式两份手写实现 = 静默分歧发生器)。
--    ⚠ 反过来也成立:**别在门口替别人拦**。首轮这儿先拦了「战斗中不许写宏」,
--    规则本身没错,但它把 Macro.Write「战斗中排队、脱战自动补写」整条更好的路给短路了 ——
--    判据不是「两处判断会不会漂」,是「我拦掉的这条路,它自己会不会做得更好」。
--
-- ⚠ 参数解析只把**命令词**转小写,`rest` 一律保原样。原因是名字和方案名可以是中文,而
--    `%a` / `%w` 这些字符类**不匹配非 ASCII 字节**(`("张三"):match("^%a+$")` = nil)⇒
--    全文切参数只用 `%S` 和 `.-`。反过来 `string.lower` 在 C locale 下只动 A-Z 那 26 个字节,
--    中文名原样通过,所以拿它做大小写不敏感比对是安全的(不是「凑合能用」,是真安全)。

local ADDON, ns = ...

local Slash = {}
ns.Slash = Slash

local ERR = "|cffff5555"      -- 出错 / 越界:红
local OK  = "|cff66ff66"      -- 成功:绿
local HI  = "|cffffcc00"      -- 值:黄
local DIM = "|cff888888"      -- 旁白 / 下一步提示:灰
local R   = "|r"

-- 任何可能被 12.x 拒掉或压根不存在的调用都从这儿过。返回 nil 而不是抛错 ——
-- 一条命令死掉可以,整个后路死掉不行。
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if ok then return a end
    return nil
end

-- 探一个兄弟模块在不在。**不 return 错误码,直接把话说完** —— 这条消息的读者是玩家,
-- 他要知道的是「哪个文件没起来 + 现在能干什么」,不是一个 bool。
local function Need(modName, fnName)
    local mod = ns[modName]
    if type(mod) == "table" and type(mod[fnName]) == "function" then return mod[fnName], mod end
    ns.Print(ERR .. modName .. ".lua 没加载(或它自己报错了)" .. R ..
             " —— 这条命令用不了。其余命令照常:/dgz help")
    return nil
end

-- 🔴 名字的**规范化 / 比较 / 合法性**这三件事,本文件一个字都不自己写 ——
--    全部走 Core 的 ns.NormalizeName / ns.SameName / ns.ValidateName。
--    首轮这儿有过自己的一份(剥 `-服务器` 后缀)而 Capture 那份不剥:两份单独看都对,
--    症状是「面板说这人重复了、宏里却站着两个他」,漂了没有任何一处读得出来。
--    ⚠ 这里**不探 ns.SameName 在不在**(别处调兄弟模块一律先探):Core.lua 是这个文件的
--    调用方 —— 它没加载的话连 ns 都不存在,这个文件根本不会被跑到,探测是永远为真的死代码。

-- 名单数组。Core 建的表一定带 members,但 SavedVariables 是玩家机器上的一个文件:
-- 手改过 / 被别的插件写过 / 上个版本留下的形状,都可能让它不是表。
-- Capture 对同一个字段是防御性的(先 type 检查再用)⇒ 这边不防的话,同一份坏数据
-- 在一处静默、在另一处抛 Lua 错,而抛错那处会被玩家读成「我命令打错了」。
-- 顺手就地修好:返回的是**真表**,调用方写进去的东西不会掉。
local function Members(L)
    if type(L) ~= "table" then return {} end
    if type(L.members) ~= "table" then L.members = {} end
    return L.members
end

----------------------------------------------------------------------------------------------------
-- 队伍侧:名字 ←→ unit token
----------------------------------------------------------------------------------------------------

-- 当前能直接寻址的所有友方 unit。solo 时只有 player —— 这不是退化情况,恰恰是**最常见**的
-- 排名单时机(赛前一个人站在主城摆顺位),所以它必须走得通、且报出来的话得说人话。
local function GroupUnits()
    local units = { "player" }
    local n = safe(GetNumGroupMembers) or 0
    if safe(IsInRaid) then
        for i = 1, n do units[#units + 1] = "raid" .. i end
    else
        for i = 1, n - 1 do units[#units + 1] = "party" .. i end   -- 小队里 n 含自己 ⇒ party 只到 n-1
    end
    return units
end

-- 名字 → unit token,**只在队伍/团队里找**。
-- 🔴 这不是「查不到就算了」:实测 12.1.0 主城陌生人的 `[@名字,exists]` 和 `[@名字,help]` 都判假
--    (裸的 `[@名字]` 倒是成立,名字被原样当目标传下去了 —— 但**条件**解析不了)。
--    ⇒「不在队伍」本身就是一条要念给玩家听的事实:那一段宏条件在开打前会一直判假、直接顺到下一位。
local function UnitForName(name)
    if not name then return nil end
    for _, u in ipairs(GroupUnits()) do
        if ns.SameName(safe(GetUnitName, u, true), name) then return u end
    end
    return nil
end

-- 职业色。UnitClass 的第二个返回是 "PRIEST" 这种 token,明文可读(实测)。
-- ⚠ 优先用 RAID_CLASS_COLORS[token].colorStr;自己拿 r/g/b 拼时 **必须先 math.floor**。
--    两个运行时在这儿行为不一样:游戏里是 5.1(`%x` 碰上 191.25 静默截断),本机跑逻辑测试的
--    是 5.4(**直接抛错**:number has no integer representation)。floor 一下两边才一致 ——
--    否则「本机测得过的代码」和「游戏里跑的代码」会在同一行上分家。实测法师(无 colorStr,
--    0.25*255 = 63.75)正好走这条路,不是理论风险。
local function Colored(name, unit)
    if unit then
        local class = safe(function() return select(2, UnitClass(unit)) end)
        local c = (type(class) == "string") and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then
            if c.colorStr then return "|c" .. c.colorStr .. name .. R end
            return ("|cff%02x%02x%02x%s|r"):format(
                math.floor((c.r or 1) * 255 + 0.5),
                math.floor((c.g or 1) * 255 + 0.5),
                math.floor((c.b or 1) * 255 + 0.5), name)
        end
    end
    return DIM .. name .. R          -- 灰 = 不在队伍,或者职业读不出来
end

-- 一行一个人。状态只报**看得见的客观事实**(在不在队伍/死没死/掉没掉线/能不能增益),
-- 不报「下一个会给谁」—— 那是 Preview 的活,在这儿再算一遍就是第二套判断顺序。
local function MemberLine(i, name)
    local u = UnitForName(name)
    local tag
    if not u then
        tag = DIM .. "不在队伍 —— 这一段判假,宏会直接顺到下一位" .. R
    elseif safe(UnitIsConnected, u) == false then
        tag = ERR .. "离线" .. R
    elseif safe(UnitIsDeadOrGhost, u) then
        tag = ERR .. "已阵亡(nodead 判假,跳过)" .. R
    elseif safe(UnitCanAssist, "player", u) == false then
        tag = ERR .. "帮不了(help 判假,跳过)" .. R
    else
        tag = OK .. "在队伍里,可给" .. R
    end
    return ("  %s%d.%s %s  %s"):format(HI, i, R, Colored(name, u), tag)
end

-- 宏正文长度。长度**只问 Macro.Length**,这儿绝不自己数一遍 —— 码位怎么算是 Macro 的事,
-- 抄一份过来的话两边哪天不一致谁都发现不了(而症状是宏被客户端从右边截断,末尾几位人间蒸发)。
local function LengthLine(L)
    local Length = ns.Macro and ns.Macro.Length
    if type(Length) ~= "function" then return DIM .. "(Macro.lua 没加载,量不了长度)" .. R end
    -- 🔴 Macro.Length 生成不出正文时返回 **nil**(不是 0)。这条分支必须自己说话,
    --    绝不能退回去打一个 "0/255" —— 那是**看起来最健康的一个数**,而它恰好出现在
    --    最坏的时候(技能名还没就绪 / 名单里有拆坏条件的字符),于是玩家读到「还很宽裕」,
    --    然后 /dgz write 当场失败,他会去找一个根本不存在的长度问题。
    --    safe() 里 Length 自己抛错也落到这儿,同一句话覆盖两种情况:正文都是没有。
    local n = safe(Length, L)
    if type(n) ~= "number" then
        return ERR .. "宏正文生成不出来 —— 量不了长度" .. R ..
               DIM .. "(技能名还没拿到?名单里有 [ ] , ; | 或空格?/dgz show 看细节)" .. R
    end
    local s = ("宏正文 %d/%d 码位"):format(n, ns.BODY_LIMIT)
    if n > ns.BODY_LIMIT then
        return ERR .. s .. " —— 超了!客户端会从右边截断,排在后面的人直接消失" .. R
    end
    return s
end

-- 改完数据统一走这儿。**那句「要 /dgz write」每次都跟着走**:名单改了但没写宏的话,
-- 屏幕上什么都不会变,而「我改了却没反应」是最容易被当成插件坏掉的一种表现。
-- (就算 Macro 那边挂了 OnChanged 自动写,再写一次也是幂等的 —— 这句话最坏也只是多余,不会错。)
local function AfterEdit(msg)
    safe(ns.Changed)
    ns.Print(msg)
    ns.Print(LengthLine(ns.Current()) .. "  " .. DIM .. "改完要 /dgz write 才进宏" .. R)
end

-- 把「序号或名字」解析成序号。tonumber 优先是安全的:WoW 角色名不可能是纯数字。
local function ResolveIndex(L, arg)
    if not arg or arg == "" then return nil, "要一个序号或名字。/dgz list 看序号" end
    local m = Members(L)
    local n = tonumber(arg)
    if n then
        n = math.floor(n)
        if #m == 0 then return nil, "名单是空的" end
        if n < 1 or n > #m then
            return nil, ("序号 %d 不在 1..%d 里"):format(n, #m)
        end
        return n
    end
    for i, nm in ipairs(m) do
        if ns.SameName(nm, arg) then return i end
    end
    return nil, ("名单里没有「%s」"):format(arg)
end

----------------------------------------------------------------------------------------------------
-- 命令表
-- 🔑 help **从这张表生成**,不另写一份清单。两份手写的清单只会漂,而漂的方向永远是
--    「新命令没写进 help」= 做了等于没做(玩家找不到的功能不存在)。
----------------------------------------------------------------------------------------------------

local CMDS, ORDER = {}, {}
local function Def(name, usage, desc, fn)
    CMDS[name] = { usage = usage, desc = desc, run = fn }
    ORDER[#ORDER + 1] = name
end

-- 别名不进 help:它们是给手指的,不是给眼睛的。
local ALIAS = {
    ["?"] = "help", h = "help", ls = "list", rm = "del", remove = "del",
    delete = "del", macro = "write", body = "show", cap = "capture",
}

Def("list", "list", "打印当前名单(序号 / 职业色 / 在不在队伍里)", function()
    local L = ns.Current()
    ns.Print(("方案 %s%s%s   焦点优先 %s   末尾给自己 %s"):format(
        HI, tostring(L.name), R,
        L.useFocus and (OK .. "开" .. R) or (DIM .. "关" .. R),
        L.selfLast and (OK .. "开" .. R) or (ERR .. "关" .. R)))
    local m = Members(L)
    if #m == 0 then
        ns.Print(DIM .. "  (空名单)" .. R .. " —— /dgz add <名字>,或者 /dgz capture 用鼠标点着录")
    else
        for i, nm in ipairs(m) do ns.Print(MemberLine(i, tostring(nm))) end
    end
    -- 兜底那一位单独说:它不是「名单里的第 9 个人」,是止损位 —— 关掉它等于宁可不放也不给自己。
    if L.selfLast then
        ns.Print(DIM .. "  末位兜底:[@player](上面全判假才轮到自己)" .. R)
    else
        ns.Print(ERR .. "  末尾兜底关着 —— 上面全给不出去时这个宏什么都不放。" .. R ..
                 DIM .. " /dgz self 打开" .. R)
    end
    ns.Print(LengthLine(L))
    -- 🔑 这一整屏念的是**名单**,而按下去执行的是**宏栏里那份宏** —— 两者可以不同步。
    --    不说这句的话,上面每一行都在用"下次会给谁"的口气描述一件当下不成立的事。
    if safe(ns.IsDirty) then
        ns.Print(ERR .. "  名单改过了,还没写进宏" .. R ..
                 DIM .. " —— 上面这些是「写进去之后」的样子,现在按宏还是老的。/dgz write" .. R)
    end
end)

Def("add", "add <名字>", "把一个人加到名单末尾(优先级最低)", function(rest)
    if rest == "" then ns.Print("用法:/dgz add <名字>"); return end
    local L = ns.Current()
    local m = Members(L)
    if #m >= ns.MAX_MEMBERS then
        ns.Print(ERR .. ("名单满了(上限 %d 人)"):format(ns.MAX_MEMBERS) .. R ..
                 " —— 先 /dgz del <序号> 腾个位置")
        return
    end
    for i, nm in ipairs(m) do
        if ns.SameName(nm, rest) then
            ns.Print(("「%s」已经在名单第 %d 位了。想提前用 /dgz up %d"):format(tostring(nm), i, i))
            return
        end
    end
    -- 队伍里有这个人 ⇒ 用**游戏给的那个写法**存,别存玩家手打的那份。
    -- 大小写、跨服后缀这些差异在宏条件里是判真判假的分界,而手打出来的错拼在名单上
    -- 看起来完全正常 —— 那一段会永远判假,表现是「这个人永远轮不到」而不是报错。
    -- 🔴 存的是 GetUnitName(u, true) 的**完整**返回(跨服会带 `-服务器`),这里**故意不剥后缀**:
    --    跨服单位在宏条件里通常必须写全名,剥掉服务器后缀那一段就永远判假。
    --    而比对那侧走 ns.SameName(它内部剥了再比)⇒ 玩家打短名一样找得到、一样拦得住重复。
    --    ⇒ 「存全名 / 比短名」是**故意**不对称的,别顺手把两边统一 —— 统一到哪一边都会坏一半。
    local u = UnitForName(rest)
    local stored = u and (safe(GetUnitName, u, true) or rest) or rest
    -- 🔴 合法性走 ns.ValidateName —— **只有 Core 那一份**(首轮这儿、Capture、Macro 各有各的规则)。
    --    校验对象是 stored,不是玩家打的那串:真正要进宏正文的是它。
    --    ⚠ 拒收的理由要说到后果那一层:这不是「这一位不生效」,是 **整个宏写不出来** ——
    --    Macro 的 clauses() 碰到一个坏名字就整条 fallback 链不生成,名单里其他人跟着一起没。
    --    录进来再让 write 天天报错,是把一个"现在就能说清"的错误推迟成一个"看不出为什么"的错误。
    local vok, vwhy = ns.ValidateName(stored)
    if not vok then
        ns.Print(ERR .. ("「%s」这个名字不能进宏:%s"):format(tostring(stored), tostring(vwhy)) .. R)
        ns.Print(DIM .. "没录进去 —— 录了的话整个宏都写不出来(不只是这一位),而名单看着完全正常。" .. R)
        return
    end
    m[#m + 1] = stored
    if u then
        AfterEdit(("第 %d 位:%s  %s"):format(#m, Colored(stored, u), OK .. "(队伍里找到了)" .. R))
    else
        AfterEdit(("第 %d 位:%s  %s"):format(#m, Colored(stored, nil),
            DIM .. "(不在队伍,原样存下 —— 名字拼错的话这一段会永远判假)" .. R))
    end
end)

Def("del", "del <序号|名字>", "从名单里删掉一个", function(rest)
    local L = ns.Current()
    local i, why = ResolveIndex(L, rest)
    if not i then ns.Print(ERR .. why .. R); return end
    local gone = table.remove(Members(L), i)
    AfterEdit(("删了第 %d 位「%s」"):format(i, tostring(gone)))
end)

Def("up", "up <序号|名字>", "往上挪一位(优先级升高)", function(rest)
    local L = ns.Current()
    local i, why = ResolveIndex(L, rest)
    if not i then ns.Print(ERR .. why .. R); return end
    local m = Members(L)
    if i == 1 then ns.Print(("「%s」已经在第 1 位了"):format(tostring(m[1]))); return end
    m[i], m[i - 1] = m[i - 1], m[i]
    AfterEdit(("「%s」上移到第 %d 位"):format(tostring(m[i - 1]), i - 1))
end)

Def("down", "down <序号|名字>", "往下挪一位(优先级降低)", function(rest)
    local L = ns.Current()
    local i, why = ResolveIndex(L, rest)
    if not i then ns.Print(ERR .. why .. R); return end
    local m = Members(L)
    if i == #m then ns.Print(("「%s」已经在最后了"):format(tostring(m[i]))); return end
    m[i], m[i + 1] = m[i + 1], m[i]
    AfterEdit(("「%s」下移到第 %d 位"):format(tostring(m[i + 1]), i + 1))
end)

Def("clear", "clear", "清空当前方案的名单", function()
    local L = ns.Current()
    local m = Members(L)
    if #m == 0 then ns.Print("名单本来就是空的"); return end
    -- 没有 undo ⇒ 把清掉的名字原样打出来,想反悔照着 add 回去。
    -- (与其加一道 StaticPopup 确认,不如让「撤销」这件事不需要确认框也做得到。)
    -- ⚠ 不用 table.concat:它碰到非字符串元素直接抛错,而那会发生在 wipe **之前**
    --    ⇒ 玩家看到「命令出错」而名单一个人没少,查起来完全摸不着头脑。
    local names = {}
    for i, nm in ipairs(m) do names[i] = tostring(nm) end
    names = table.concat(names, "  ")
    -- 🔴 就地清,别 `L.members = {}` 换一张新表:Preview / Options / Capture 里任何一处
    --    正拿着旧表的引用(缓存、闭包、迭代中),换表之后它们会对着一张**没人再更新**的表
    --    继续念名字 —— 面板显示得好好的,而宏里早就空了。就地 wipe 的话所有引用一起归零。
    if type(wipe) == "function" then
        wipe(m)
    else
        for i = #m, 1, -1 do m[i] = nil end
    end
    AfterEdit(("清空了 —— 刚才是:%s%s%s"):format(HI, names, R))
end)

Def("capture", "capture", "开/关鼠标点人录名单", function()
    local fn = Need("Capture", "Toggle"); if not fn then return end
    -- Capture.Start/Stop **两条路都自己把状态打出来了**(开的那条还带当前人数)。
    -- 这儿再念一遍就是同一件事说两行 —— 玩家读到的不是"更清楚",是"我是不是按了两次"。
    -- 只补 Capture 故意留白的那一半:它注释里写明不写死斜杠命令名(命令名归这个文件定,
    -- 写死在它那儿的话,哪天改名那行字会安安静静地开始撒谎)。
    local on = safe(fn)     -- Toggle 返回切换后的状态
    if on == nil then
        -- Toggle 抛错 / 什么都没返回 ⇒ Capture 那边多半也没来得及说话。
        -- 这里必须留一行:命令打下去屏幕上一个字都没有,是最难查的一种"坏了"。
        ns.Print("录制开关切了一下 —— 状态读不出来,以 Capture 自己打的那行为准。")
    elseif on then
        ns.Print(DIM .. "再来一次 " .. R .. HI .. "/dgz capture" .. R .. DIM .. " 关掉;" ..
                 "点不动的人(他已经是当前目标)用 " .. R .. HI .. "/dgz grab" .. R .. DIM ..
                 ",团队框架左键点击施法就用 " .. R .. HI .. "/dgz mouse" .. R .. DIM .. "。" .. R)
    end
end)

Def("grab", "grab [unit]", "把当前目标加进名单(可带 focus / mouseover)", function(rest)
    local fn = Need("Capture", "AddUnit"); if not fn then return end
    local unit = (rest ~= "" and rest:lower()) or "target"
    -- 先自己确认这个 unit 真存在。让 AddUnit 去撞空当然也行,但那样报出来的话是
    -- 「加不了」,而玩家要听的是「你没选人」—— 差一句就得多试一轮。
    if not safe(UnitExists, unit) then
        ns.Print(ERR .. ("`%s` 上没有人"):format(unit) .. R .. " —— 先选中一个人再 /dgz grab")
        return
    end
    safe(fn, unit)      -- 加没加得进、满没满、重不重复,由 Capture 自己报(它有全部上下文)
end)

Def("mouse", "mouse", "把鼠标指着的那个人加进名单(团队框架左键点击施法时用)", function()
    local fn = Need("Capture", "AddMouseover"); if not fn then return end
    -- 🔴 这条命令的存在理由,不是"多一个入口":团队框架的左键被配成**点击施法**时,
    --    点人根本不改变目标 ⇒ PLAYER_TARGET_CHANGED 一次都不来,capture 录入模式对着这种
    --    框架是完全哑的。这是第二条录入通道。
    --    (首轮 Capture.AddMouseover 全仓库零调用方 = 一段没有入口的功能,连带 db.capture.alsoMouseover
    --     这个配置项整个不可达 —— 有实现、有配置、没人按得到,跟没做一模一样。)
    -- ⚠ 跟 `/dgz grab mouseover` **不是重复**:grab 走 AddUnit,不看 alsoMouseover 那个开关;
    --    这条走 AddMouseover,受它管。想删一条之前先想清楚删掉的是哪一半语义。
    local pok, ok, why = pcall(fn)
    if not pok then
        ns.Print(ERR .. "录入出错:" .. R .. tostring(ok))
        return
    end
    -- ⛔ 这儿**不补任何回声**。Capture.AddMouseover 每条路径都自己说了话,含
    -- 「通道被设置关掉了」那条(Capture.lua:233)。
    -- 🔴 上一版这儿有个补丁,依据是注释里那句「只有通道关着那条是静默返回的」——
    --    **那句断言在 Capture 补完反馈之后就变假了**,结果同一句话打两遍,
    --    正是它自己想避免的噪音。两个模块各自"补反馈"就会撞成这样。
    -- ⇒ 规矩:**谁知道原因谁说话**。Capture 是唯一知道为什么被拒的那层,回声归它。
end)

Def("focus", "focus", "开/关「焦点排最前」", function()
    local L = ns.Current()
    L.useFocus = not L.useFocus
    AfterEdit("焦点优先:" .. (L.useFocus and (OK .. "开" .. R .. "([@focus,help,nodead] 插在名单最前)")
                                          or (DIM .. "关" .. R)))
end)

Def("self", "self", "开/关「末尾兜底给自己」", function()
    local L = ns.Current()
    L.selfLast = not L.selfLast
    if L.selfLast then
        AfterEdit("末尾兜底:" .. OK .. "开" .. R .. "(前面全给不出去才 [@player])")
    else
        -- 特意用红的:关掉它不是省一段条件,是让这个宏在「一个人都给不出去」时**什么都不放**。
        AfterEdit("末尾兜底:" .. ERR .. "关 —— 名单全判假时这个宏会空放一下" .. R)
    end
end)

Def("set", "set <方案名>", "切换当前在编的方案", function(rest)
    if rest == "" then ns.Print("用法:/dgz set <方案名>"); return end
    local L, i = ns.ListByName(rest)
    if not L then
        local names = {}
        for _, x in ipairs(ns.db.lists) do names[#names + 1] = x.name end
        ns.Print(ERR .. ("没有叫「%s」的方案"):format(rest) .. R ..
                 "  现有:" .. HI .. table.concat(names, "  ") .. R)
        return
    end
    ns.db.editing = i
    -- 名字一律 tostring:方案名来自 SavedVariables,不保证还是字符串,而 `%s` 碰上表/数字
    -- 的行为在两个运行时并不一致 —— 这一行崩掉的话,方案其实**已经切过去了**,
    -- 屏幕上却只有一句"命令出错",玩家会以为没切成然后再切一次。
    AfterEdit(("切到方案 %s%s%s(%d 人)"):format(HI, tostring(L.name), R, #Members(L)))
end)

Def("new", "new <方案名>", "新建一个方案并切过去", function(rest)
    if rest == "" then ns.Print("用法:/dgz new <方案名>"); return end
    if ns.ListByName(rest) then
        ns.Print(ERR .. ("已经有叫「%s」的方案了"):format(rest) .. R .. " —— /dgz set 它就行")
        return
    end
    -- ⚠ ns.NewList 只**造表**、不入库(读过 Core.lua 确认的)⇒ 入库和切 editing 归调用方。
    --   照字面把它当「新建方案」用的话,建完会发现方案列表里没有它,而返回值看着完全正常。
    local db = ns.db
    db.lists[#db.lists + 1] = ns.NewList(rest)
    db.editing = #db.lists
    AfterEdit(("建好方案 %s%s%s 并切过去了(空名单)"):format(HI, rest, R))
end)

Def("rmlist", "rmlist <方案名>", "删掉一个方案", function(rest)
    if rest == "" then ns.Print("用法:/dgz rmlist <方案名>"); return end
    local db = ns.db
    if #db.lists <= 1 then
        ns.Print(ERR .. "只剩最后一个方案了,删不得" .. R .. " —— 想清人用 /dgz clear")
        return
    end
    local L, i = ns.ListByName(rest)
    if not L then ns.Print(ERR .. ("没有叫「%s」的方案"):format(rest) .. R); return end
    local macroName = ns.Macro and ns.Macro.MacroNameFor and safe(ns.Macro.MacroNameFor, L)
    table.remove(db.lists, i)
    -- editing 是个**下标**,删一行之后它可能指到别人身上 ⇒ 这三行必须跟着删走。
    if db.editing > i then db.editing = db.editing - 1
    elseif db.editing == i then db.editing = math.min(i, #db.lists) end
    if db.editing < 1 then db.editing = 1 end
    AfterEdit(("删了方案「%s」,现在在编 %s%s%s"):format(rest, HI, ns.Current().name, R))
    -- 宏不替他删:删宏是个不可逆的写操作,而且那个宏可能已经拖在动作条上了。
    -- 说清楚它还在、叫什么名字,比替他做主强。
    if macroName then
        ns.Print(DIM .. ("对应的宏「%s」还留在宏面板里,不要了自己删。"):format(macroName) .. R)
    end
end)

Def("write", "write", "把当前方案写进宏", function()
    local Write = Need("Macro", "Write"); if not Write then return end
    -- 🔴 这儿**故意不预先拦战斗、也不预先查技能名**。首轮两道都拦了,理由写的是
    --    「InCombatLockdown() 是同一个实时状态读,两处读不会漂」—— 那句话本身没错,
    --    错的是拦这一下的**后果**:Macro.Write 在战斗中会把这次写入**排进队列**,
    --    PLAYER_REGEN_ENABLED 一到自动补写;在门口先 return 掉,等于把这条更好的路整个短路 ——
    --    玩家出了战斗还得记得自己再打一次 /dgz write,而他多半不记得,于是宏一直是老的。
    --    ⇒ 判据不是「两处读会不会漂」,是「我拦掉的这条路,它自己会不会做得更好」。
    --    技能名同理:Macro.Write 自己查,而且它的措辞比这儿的完整(说明了为什么宁可不写)。
    local ok, a, b = pcall(Write, ns.Current())
    if not ok then
        ns.Print(ERR .. "写宏时报错:" .. R .. tostring(a))
        return
    end
    -- 返回值形状**故意读得宽**:Macro.lua 是同一批里另一只手写的,契约只写了 Write(list)、
    -- 没写它返回什么。三种常见形状(true/err、只返回一句话、nil+原因)都吃得下。
    -- 判据是「宁可打得难看,也不能把结果吞掉」—— 吞掉的话玩家没法知道宏到底写没写。
    if a == true then
        ns.Print(OK .. "宏写好了。" .. R .. (b and (" " .. tostring(b)) or
                 " 去宏面板把它拖到动作条上。"))
    elseif a == nil or a == false then
        -- 原因**原样打出来**,一个字不改写:Macro 那边给的是整句中文,而且分得出
        -- 「真失败」和「战斗中已排队、脱战自动补写」。在这儿加工措辞 = 又一份会漂的文案。
        -- 用红色是准确的 —— 排了队也意味着**此刻宏栏里还是老的那份**,那正是要他看见的事。
        ns.Print(ERR .. "宏没写进去:" .. R .. tostring(b or "(Macro 没给原因)"))
    elseif type(a) == "string" then
        ns.Print(a)                             -- DodoSays/Macros.Report 那种「返回一整句话」的形状
    else
        ns.Print(("Macro.Write 回了:%s / %s"):format(tostring(a), tostring(b)))
    end
end)

Def("show", "show", "打印宏正文全文 + 长度", function()
    local Build = Need("Macro", "BuildBody"); if not Build then return end
    local body = safe(Build, ns.Current())
    if type(body) ~= "string" then
        ns.Print(ERR .. "宏正文生成不出来" .. R .. "(技能名没拿到?先 /dgz list 看看名单)")
        return
    end
    ns.Print(LengthLine(ns.Current()))
    -- 逐行打:正文里有 \n,一次性丢给 print 会挤成一行、`/cast` 那串条件根本看不清,
    -- 而这条命令存在的全部意义就是让人**逐段核对宏条件的顺序**。
    for line in (body .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then ns.Print("|cffffffff" .. line .. R) end
    end
end)

Def("preview", "preview", "开/关「下次会给谁」的浮窗", function()
    local fn = Need("Preview", "Toggle"); if not fn then return end
    safe(fn)
    -- 🔴 成功路径一个字都不打是不行的:关掉的那一下屏幕上**少了**一个东西 ——
    --    这跟"命令根本没执行"长得一模一样,玩家只能靠猜。
    -- 状态直接读 db.preview.enabled:那就是 Preview.SetShown 写的那一份真相
    --    (它没有 IsShown 之类的读接口,而在这儿自己判一遍开关就是第二套判断顺序)。
    -- ⚠ 只报**这个开关的状态**,不替它解释"为什么你看不见" —— 浮标的位置只在建的时候
    --    从 db 锚一次(读过 Preview.lua 确认),所以"关掉再开就会回到存的位置"这种话是假的,
    --    而给错理由比不给更坏:它会带着人去反驳一条根本不存在的规矩。
    local pv = (ns.db and ns.db.preview) or {}
    if pv.enabled then
        ns.Print(OK .. "预览浮窗:开" .. R .. DIM .. "(念的是名单,按下去的还是宏栏里那份)" .. R)
    else
        ns.Print(DIM .. "预览浮窗:关(名单和宏都不受影响)" .. R)
    end
end)

Def("help", "help", "列出全部命令", function()
    ns.Print("命令(" .. HI .. "/dgz" .. R .. " 或 " .. HI .. "/dodoguanzhu" .. R .. "):")
    ns.Print(("  %s/dgz%s  %s(不带参数)打开面板%s"):format(HI, R, DIM, R))
    for _, name in ipairs(ORDER) do
        local e = CMDS[name]
        ns.Print(("  %s/dgz %s%s  %s— %s%s"):format(HI, e.usage, R, DIM, e.desc, R))
    end
    ns.Print(DIM .. "面板只是这些命令的皮 —— 面板打不开时,这里一样能把活干完。" .. R)
end)

----------------------------------------------------------------------------------------------------
-- 分发 + 注册
----------------------------------------------------------------------------------------------------

-- 不带参数 = 开面板。Options 没起来时**不能只是静默** —— 玩家会以为插件坏了,
-- 而实际上除了那张皮以外一切都还在。
local function OpenPanel()
    local Open = ns.Options and ns.Options.Open
    if type(Open) == "function" then
        local ok, err = pcall(Open)
        if ok then return end
        ns.Print(ERR .. "面板打不开:" .. R .. tostring(err))
    else
        ns.Print(ERR .. "面板没加载(Options.lua 报错了?)" .. R)
    end
    ns.Print(DIM .. "不影响用:全部功能都在命令里。/dgz help" .. R)
end

local function Dispatch(msg)
    safe(ns.EnsureDB)     -- 防守:正常路径下 Core 早建好了,但一条后路不该假设别人跑过
    local raw = msg or ""
    -- 只小写**命令词**;rest 保原样(中文名 / 大小写敏感的角色名都靠这一条活着)。
    -- 顺带把多余空格吃掉:`^%s*` 吃前导,`%s*$` 吃尾随,中间那个 `%s*` 吃命令和参数之间的一串。
    local cmd = (raw:match("^%s*(%S*)") or ""):lower()
    local rest = raw:match("^%s*%S*%s*(.-)%s*$") or ""
    if cmd == "" then return OpenPanel() end

    local entry = CMDS[ALIAS[cmd] or cmd]
    if not entry then
        ns.Print(ERR .. ("不认识「%s」"):format(cmd) .. R)
        -- 🔴 别在这儿直接 `CMDS.help.run("")` —— 那是全文件唯一一条**没被 pcall 罩住**的调用路径,
        --    而它偏偏跑在"玩家已经打错了一次"的时刻:help 里哪天崩一下,屏幕上给出的会是
        --    一条 Lua 错误,他只会更确信是自己命令打错了,然后继续改一条本来就对的命令。
        --    修法是让它**落到下面同一条 pcall 上**,而不是在这儿再补第二个 pcall(修类不修例)。
        entry, rest = CMDS.help, ""
    end
    -- 每条命令各自裹一层:一条命令写崩了,别把整个 /dgz 带走。
    -- 报错时明说「这是 bug 不是你打错了」—— 否则人会去反复改一条本来就对的命令。
    local ok, err = pcall(entry.run, rest)
    if not ok then
        ns.Print(ERR .. "命令出错:" .. R .. tostring(err))
        ns.Print(DIM .. "这是插件的 bug,不是你打错了。别的命令照常:/dgz help" .. R)
    end
end

local inited
function Slash.Init()
    if inited then return end       -- Core 在 ADDON_LOADED 调一次;重复注册没害处,但没必要
    inited = true
    SLASH_DODOGUANZHU1 = "/dgz"
    SLASH_DODOGUANZHU2 = "/dodoguanzhu"
    SlashCmdList.DODOGUANZHU = Dispatch
end

-- 登录时报一行。**不是客套** —— 一个没人知道怎么打开的功能等于不存在,
-- 而这个插件平时完全不显形(它的产物是一个宏,躺在动作条上)。
-- 放 PLAYER_LOGIN 而不是 ADDON_LOADED:后者在加载画面里,那行字没人看得见。
local hello = CreateFrame("Frame")
hello:RegisterEvent("PLAYER_LOGIN")
hello:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    Slash.Init()                    -- 兜底:Core 那条路万一没跑到,命令也得在
    ns.Print("已加载。" .. HI .. "/dgz" .. R .. " 开面板," ..
             HI .. "/dgz help" .. R .. " 看全部命令。")
end)
