-- DodoGuanzhu :: Capture.lua
-- 录名单:开着录入模式时,**你选中谁就收录谁**。
--
-- 为什么监听 PLAYER_TARGET_CHANGED 而不是 hook 团队框架:
-- 点团队框架 / 点 3D 世界里的人 / 点名条,这三件事的共同结果都是「选中了那个人」——
-- 那就只监听这个结果,不用管他从哪点的。反过来,hook 暴雪的 CompactRaidFrame 是
-- 去动 secure unit button,taint 风险高,而 taint 的症状**像 bug 不像 taint**
-- (参见 canon:hook 内建冷却管理器的 item 框体 -> 图标在、位置对、就是不转圈),
-- 排查代价远高于这个功能本身的价值。
--
-- 本文件全程只**读**、只写自己的 SavedVariables 表 ⇒ 战斗中跑没问题。
-- 真正被战斗挡住的是下游写宏那一步(Macro.lua 自己 InCombatLockdown 兜),
-- 这边照常收录、照常 ns.Changed(),名单不会因为在战斗里就丢。
--
-- 🔑 名字的**归一化 / 去重 / 合法性**一律走 Core 的 ns.NormalizeName / ns.SameName /
--    ns.ValidateName。首轮这儿自己写了一份(而且跟 Slash 那份不一致:它剥 -服务器、
--    我不剥)—— 那正是 canon 说的静默分歧发生器:同一个人能进两次,而名单上那两行
--    看起来一模一样,谁都读不出哪儿错了。

local ADDON, ns = ...

------------------------------------------------------------------
-- 读值护栏
------------------------------------------------------------------

-- 🔴 兜底**不能**写成 `function() return false end`(= 「什么都不是 secret」)。
--    判据是「这个兜底到底在哪种情况下会被用上」,而它有两种,这一行分辨不出来:
--    ① 老客户端压根没有 secret 这回事 -> 认明文是对的;
--    ② 暴雪把这个全局改名 / 挪进某个命名空间,而 secret **照样存在** ->
--       认明文会让每一个 secret 一路流进 strlower / 拼接,当场崩。
--    也就是说,blanket-false 恰好在它**最该救命的那一次**(②)把「结构性保证」
--    变成结构性漏洞,而且症状是整个事件处理函数静默死掉。
--    ⇒ 兜底改成真探一次:对 secret 做 tostring 会抛错(GOTCHAS §8 实测),抛错就按 secret 算;
--      探不出问题才认明文(否则老客户端一个人都录不进去)。
-- ⚠ 探针本身也 pcall 包着,它只在 issecretvalue 缺席时才跑得到 —— 12.1 上这条是死路,
--    留着是为了「哪天它不在了」那一次不至于把插件变成崩溃源。
local IsSecret = issecretvalue or function(v)
    if v == nil then return false end
    return not pcall(tostring, v)
end

-- 这两个小函数存在的唯一理由 = 让「碰 secret」这件事**发生在 pcall 里面**。
-- 🔴 `v and true or false` 写在 pcall 外面时,只要 IsSecret 判漏一次就是一次真崩溃;
--    收进函数再 pcall,判漏的代价从「整条路径死」降到「这条判据这次读不出来」。
--    能靠结构保证的别靠算式保证 —— 算式要求上面每一道都判对,结构不要求。
local function Truthy(v) return v and true or false end
local function BlankName(n) return type(n) ~= "string" or n == "" end

-- 所有 unit 判据都走这里,回三种值:true / false / nil(= 读不出来)。
-- ⚠ nil 和 false 必须分得开:false = 「确实不是」,nil = 「这条判据这会儿失明」,
-- 两者在「是不是我自己」那一步的处置完全不同(见 IsSelf)。
local function ReadBool(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    if IsSecret(v) then return nil end
    local ok2, b = pcall(Truthy, v)
    if not ok2 then return nil end
    return b
end

-- 名字。⚠ 两层坑叠在一起:
-- ① GetUnitName 是 FrameXML 的 **Lua** 函数,由我们调用时跑在污染上下文里,
--    碰到 secret 领域会**自己抛错**(DodoInspect 1.3.1 就是这么崩的)⇒ 必须 pcall。
-- ② 抛不抛错之外,返回值本身也可能是 secret,而 **secret 的 type() 仍然是 "string"**
--    ⇒ 只判 type 会在下一步拼接时才炸。IsSecret 必须排在 type 前面。
-- 第二参数 true = 跨服带 "-服务器" 后缀、同服不带(实测),这正是宏里 @名字 要的形态。
local function ReadName(unit)
    local ok, n = pcall(GetUnitName, unit, true)
    if not ok then return nil end
    if IsSecret(n) then return nil end
    local ok2, blank = pcall(BlankName, n)
    if not ok2 or blank then return nil end
    return n
end

-- 是不是自己。UnitIsUnit **不是**永远明文(DodoGrid 那边明确记着它 secret-when-restricted),
-- 所以它读不出来时要有后手:此时名字已经确认是明文了(调用方在这之前就取到了),
-- 拿它跟自己的名字比一次 —— 自己的名字对自己永远明文。
-- ⚠ 比较走 ns.SameName,不自己 strlower:跨服后缀那条规则只许有一份。
-- 两条都失明才放行:宁可让一个自己进名单(顶多浪费一个位置,selfLast 那条还在),
-- 也不要因为读不到就把一个真队友挡在外面。
local function IsSelf(unit, name)
    local same = ReadBool(UnitIsUnit, unit, "player")
    if same ~= nil then return same end
    local me = ReadName("player")
    if me and name then return ns.SameName(me, name) end
    return false
end

------------------------------------------------------------------
-- 收录
------------------------------------------------------------------

local Capture = { on = false }
ns.Capture = Capture

local function MaxMembers() return ns.MAX_MEMBERS or 8 end

-- 上一句「跳过」说的是什么。
-- 🔑 去重的键是**整句话**,不是理由的分类:按分类去重会把「张三已经在名单里了」和
--    「李四已经在名单里了」当成同一句吞掉,于是李四那次玩家什么都听不到。
--    整句话一字不差地重复,才是真的零信息量。
local lastSkip

-- 判断 + 落库,**不说话**。返回 ok, 名字或拒绝理由, 要不要闭嘴。
-- 判据全是明文 API(12.1.0 实测:UnitIsPlayer / UnitCanAssist / GetUnitName 都给真值),
-- 唯一 secret 的是 UnitInRange —— 而这儿压根不需要射程:名单是**预设**的顺位,
-- 录的时候那人在不在射程内跟他该不该排第二毫无关系。
--
-- ⚠ 故意**不**按「死了 / 掉线」过滤:那两个是此刻的瞬时状态,不是这个人的顺位。
-- 死人该不该跳过是**施法那一刻**的事,由宏条件里的 nodead 现场判 —— 录名单时挡掉他,
-- 等于把一个临时状态永久烧进配置里。
local function TryAdd(unit)
    if type(unit) ~= "string" or unit == "" then return false, "没给单位", true end
    -- 「那儿没人」要闭嘴:清除目标也发 PLAYER_TARGET_CHANGED,每次都喊一声纯噪音。
    if ReadBool(UnitExists, unit) ~= true then return false, "那儿没人", true end

    -- 挡 NPC / 宠物 / 图腾:它们能被选中,但 @名字 在宏里解析不成友方玩家。
    if ReadBool(UnitIsPlayer, unit) ~= true then
        return false, "不是玩家(NPC / 宠物 / 图腾)"
    end
    -- 挡敌对。UnitCanAssist 比 UnitIsFriend 严:它问的正是「我能不能对他放增益」,
    -- 跟宏里那个 help 条件是同一个语义 ⇒ 这里放行的,宏那边才判得成立。
    if ReadBool(UnitCanAssist, "player", unit) ~= true then
        return false, "帮不了他(敌对 / 中立)"
    end

    -- 名字要在自我检测**之前**取:IsSelf 的后手要拿它去比。
    local name = ReadName(unit)
    if not name then
        -- 竞技场 / 战场里敌对玩家的名字是 secret,写不进宏。如实说,别装作没发生。
        return false, "名字读不出来(secret,写不进宏)"
    end

    -- 🔴 录入时就挡非法字符,而不是等写宏时才发现。
    --    否则症状是「录得进去、名单上有他、写宏整个失败」= 错在 A 处报在 B 处,
    --    是最难查的那种形状。用的是写宏那边同一个 ns.ValidateName,不许再写一份。
    local okName, why = ns.ValidateName(name)
    if not okName then return false, ("%s:%s"):format(name, why or "名字不合法") end

    if IsSelf(unit, name) then
        -- 自己由末尾的 [@player] 兜底,进名单纯属浪费一个位置和一段正文预算。
        return false, "这是你自己(末尾兜底已经管了)"
    end

    local list = ns.Current()
    if not list then return false, "没有可编辑的名单" end
    list.members = list.members or {}

    -- 去重走 ns.SameName:它剥 -服务器 后缀再比,而 Slash 那边也是同一个函数。
    -- 不剥的话同一个人跨服 / 同服各能进一次,而名单上那两行看着完全一样。
    for _, m in ipairs(list.members) do
        if ns.SameName(m, name) then return false, name .. " 已经在名单里了" end
    end

    if #list.members >= MaxMembers() then
        return false, ("名单满了(%d 人),先删一个再加"):format(MaxMembers())
    end

    list.members[#list.members + 1] = name
    ns.Changed()        -- 顺带把 dirty 立起来:名单变了 = 宏栏里那份过期了
    return true, name
end

-- 收录一个单位到**当前在编的那套名单**,并把结果**说出来**。返回 ok, 名字 / 拒绝理由。
--
-- 🔴 反馈为什么必须住在这个函数里,而不是外面包一层「会说话的版本」:
--    首轮就是包了一层 —— 而真正接上线的两条路(录入事件、/dgz grab)调的都是**里面**
--    这个,于是「会说话的那条路没人走,走的那条路不说话」。玩家点了个人、屏幕一动不动,
--    他分不出「插件没收」和「插件坏了」,而这两件事的下一步动作完全相反。
--    ⇒ 反馈跟着**动作**走,不跟着包装走。
-- quietRepeat 只给事件路径用:同一句「跳过」连着说第二遍时闭嘴(换目标会很频繁,
--    而一句一字不差的重复没有任何新信息)。成功永远报,理由变了永远报。
function Capture.AddUnit(unit, quietRepeat)
    local ok, why, silent = TryAdd(unit)

    if ok then
        lastSkip = nil
        local list = ns.Current()
        local n = #((list and list.members) or {})
        ns.Print(("已收录 |cff00ff00%s|r(%d/%d)"):format(why, n, MaxMembers()))
        -- 满了就自己关掉录入模式:否则接下来每选一个人都刷一行「名单满了」,
        -- 而用户此刻的真实意图早就完成了。
        -- ⚠ 因果顺序:先说**为什么**关,关这个动作自己再报 —— 首轮反过来了,
        --    屏幕上先冒「录入模式已关」再冒「名单已满」,读起来像它自己抽风关的。
        if n >= MaxMembers() then
            Capture.Stop(("名单已满(%d/%d),录入模式自动关闭。"):format(n, MaxMembers()))
        end
        return true, why
    end

    if not silent then
        local line = "|cffff8800跳过|r:" .. tostring(why)
        if not (quietRepeat and lastSkip == line) then
            ns.Print(line)
        end
        lastSkip = line
    end
    return false, why
end

------------------------------------------------------------------
-- 两条显式入口(都会说话:玩家主动按的,永不静默)
------------------------------------------------------------------

-- 显式「把当前目标加进来」。
-- 🔴 这条不是锦上添花,是**必需的兜底**:PLAYER_TARGET_CHANGED 只在目标真的**变了**
-- 才触发 —— 你想收的那个人如果已经是当前目标(比如刚给他放过技能),
-- 再点他一次事件根本不发火,表现就是「点了没反应」。
function Capture.AddTarget()
    if ReadBool(UnitExists, "target") ~= true then
        ns.Print("|cffff8800你现在没有目标。|r")
        return false, "没有目标"
    end
    return Capture.AddUnit("target")     -- 不传 quietRepeat:主动按的必须每次都有回音
end

-- 第二通道:鼠标指向。给那些**左键被配成点击施法**的团队框架用 ——
-- 那种框架上左键根本不改变目标,PLAYER_TARGET_CHANGED 一次都不会来。
-- ⚠ 这里只提供函数,**不自己抢按键绑定**:抢键位是全局副作用,
-- 而这插件的全部价值在于不给人添乱。入口由 Slash 那边的斜杠子命令暴露 ——
-- ⚠ 故意不在这儿写出那条命令叫什么:命令名归 Slash.lua 定,抄一份在注释里就是两处维护,
--    哪天他改了名字这行会安安静静地开始撒谎(Start() 那句提示同理)。
-- 也**没有** Bindings.xml ⇒ 这个通道不会出现在暴雪的键位设置里;想要一键的人
-- 得自己把那条斜杠命令做成宏再挂键位 —— 那是他的键位,不是我们的。
function Capture.AddMouseover()
    local db = ns.db or (ns.EnsureDB and ns.EnsureDB())
    local cap = (db and db.capture) or {}
    -- ⚠ 判据是 `== false` 不是 `not cap.alsoMouseover`:默认值是 true,而没配过的库里
    --    这个字段是 nil ⇒ 写成 not 会让「从没进过设置」的人被挡在外面。
    --    Options 那边读的也是 `~= false`,两边同一个口径。
    if cap.alsoMouseover == false then
        ns.Print("|cffff8800鼠标指向通道关着|r —— 去设置面板勾上「鼠标指向也能收」。")
        return false, "鼠标指向通道关着"
    end
    if ReadBool(UnitExists, "mouseover") ~= true then
        ns.Print("|cffff8800鼠标底下没人。|r")
        return false, "没有鼠标指向单位"
    end
    return Capture.AddUnit("mouseover")
end

------------------------------------------------------------------
-- 录入模式开关
------------------------------------------------------------------

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_TARGET_CHANGED" then return end
    -- 不在这儿先 UnitExists 一遍:那是 AddUnit 自己的第一道判据,而且它对
    -- 「那儿没人」本来就闭嘴。在两处各写一遍 = 又一个静默分歧发生器。
    Capture.AddUnit("target", true)
end)

function Capture.IsOn()
    return Capture.on and true or false
end

-- 🔑 事件**只在录入模式期间注册**。常驻注册 + 在 handler 里判开关也能跑,
-- 但那样这插件在不用的时候仍然每次换目标都进一次我们的 Lua ——
-- 一个「预设名单」类插件平时的正确开销是零。
function Capture.Start()
    if Capture.on then return end
    Capture.on = true
    lastSkip = nil          -- 新一轮录入,上一轮说过什么不该影响这一轮的第一句
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    local list = ns.Current()
    ns.Print(("|cff00ff00录入模式已开|r —— 选中谁就收录谁(当前 %d/%d)。"):format(
        #((list and list.members) or {}), MaxMembers()))
    -- 这句是为上面那个「已经是当前目标就不触发」的坑准备的。
    -- ⚠ 故意不写死具体的斜杠子命令:命令名归 Slash.lua 定,写死在这儿就成了两处维护、
    -- 哪天他改了名字这行会安安静静地开始撒谎。
    ns.Print("|cff888888点的人如果已经是当前目标,事件不会触发 —— 用「加当前目标」那条命令。|r")
end

-- why = 关掉的**原因**,由调用方给。默认那句是玩家自己关的情况。
-- 满员自动关那条走这个参数,是为了让「因为满了」和「所以关了」出现在同一句里 ——
-- 拆成两行时它们的顺序总会有一个是反的,而反过来读像插件自己抽风。
function Capture.Stop(why)
    if not Capture.on then return end
    Capture.on = false
    f:UnregisterEvent("PLAYER_TARGET_CHANGED")
    lastSkip = nil
    ns.Print(why or "录入模式已关。")
end

function Capture.Toggle()
    if Capture.on then Capture.Stop() else Capture.Start() end
    return Capture.on
end

-- 录入模式**不进 SavedVariables**,故意的:它是个「我现在正在配名单」的瞬时状态。
-- 存下来的话,下次登录随手点个人就被悄悄收进名单,而用户根本不记得自己开过。
