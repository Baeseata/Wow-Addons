-- Core.lua — 血 DK「沸点」监视,独立版。
--
-- 它只做一件事:把「血液沸腾现在是不是被沸点强化着」摆成屏幕上一格。
--   绿 = 沸点 proc,15 秒,**倒计时归暴雪画**(见下面「为什么不能自己计时」)
--   红 = 沸点 echo,3 秒,**没有任何光环可读**,只能自己算
-- 有红显红、没红有绿显绿,两种都发光。
--
-- 🔴 出身:这是 DodoCombatHUD 里 `Boiling.lua` 那一格**抄出来的独立版**,
--    给不用整套 HUD 的人。两边是**两份实现**,canon 那条「同一不变式两份手写实现
--    = 静默分歧发生器」成立 —— 下个补丁那四个 spellID 或 glow 行为变了,
--    **两边都要改**。改这边之前先看一眼那边有没有新结论,反过来也一样。
--    对面:D:\...\AddOns\DodoCombatHUD\Boiling.lua + 它的 CLAUDE.md「沸点那一格」那节。
--
-- 🔴 抄过来**故意不一样**的地方(canon:抄先例,真正的工作量是列出哪几处必须不一样):
--    ① 尺寸读自己的 DB,不读 HUD 的 cdWidth/cdHeight —— 而且**改了要能当场生效**,
--       原版那边只 resize 外框、图标不跟(那儿是潜伏 bug,在这儿是主功能)。
--    ② 位置是**拖出来的**、存 DB;原版是从大招排的锚算出来的(它没有可拖这回事)。
--    ③ 没有 SetCdRowPad / GetCdRowAnchor —— 没有排要让,也没有排可锚。
--    ④ eligible() 少一条「自身增益排开着」。
--    ⑤ 探针(事件录制 / 符文刃舞 / 图腾槽)一行都没抄:那些是调研工具,不是功能。

local ADDON, ns = ...
ns = ns or {}

-- ---------------------------------------------------------------- 机制事实
-- 出处 = SimulationCraft `engine/class_modules/sc_death_knight.cpp:15219`,
-- 2026-08-23 在 12.1.0(build 69404)真机全部复核过:
--   · 窗口是 **15 秒**不是 12(量到 12.92s 那发心脏打击续期 → 15.03s 后过期)
--   · **续期时 GLOW_SHOW 不重发** ⇒ 自己计时会系统性撒谎(一次实测差 10.8 秒)
--     ⇒ 绿色那半的倒计时**必须交给暴雪画**,这就是为什么它走 AuraContainer
--   · echo 落地**不发 UNIT_SPELLCAST_SUCCEEDED** ⇒ 红色那 3 秒只能自己算
--   · echo 会**吃掉新 proc** 并再排一个 3 秒(能连锁),只能靠「无人施法的
--     GLOW_HIDE 正好赶上 echo 落地」认出来
--
-- 🔴 这四个 ID 是**事实的锚点**。任何一条对不上,先改这张表,别改下面的逻辑。
local ID = {
    proc   = 1265968,   -- 沸点 proc:15 秒,+50% 血沸伤害,有图标
    echo   = 1265982,   -- 沸点 echo:3 秒,标着 No Aura Icon(隐藏光环,读不到)
    boil   = 50842,     -- 血液沸腾(被 proc 高亮的那个)
    talent = 1265790,   -- 沸点(隐藏被动本体)
}
local SPEC_BLOOD = 250
local ECHO_LEN   = 3.0

-- ---------------------------------------------------------------- 模块级状态
-- 🔴 **全部在这儿声明,一个都不许漏。** DodoCombatHUD 0.9.0 首次真机就是栽在这条上:
--    `local segHost` 写在文件中部,而上面的函数体里那句 `segHost = CreateFrame(...)`
--    于是**赋的是全局变量**,读的人拿到恒 nil ⇒ 登录即崩。
--    `luac -p` 挑不出来(写全局是合法 Lua),纯函数测试也够不着框体装配。
--    ⇒ `tools/test_dxf.lua` 有一条守卫盯着这件事:**新增任何模块级 local 都要加进那份清单**。
local slot, container, bg, label          -- 框体
local buttons = {}                        -- 容器**已经建出来**的那些 aura button(改尺寸要挨个碰)
local needsResize = false                 -- 想 resize 但当时碰不得(战斗中 / 光环被扣值)
local glowOn      = false
local lookKey     = nil                   -- 解锁外观现在画的是哪一档(省掉每帧重复 SetShown)
local overrideID                          -- 血液沸腾被天赋替换掉时的新 ID
local liveFrame, autoFrame
local DB                                  -- = _G.DodoXuefeiDB,ADDON_LOADED 之后才有

local echo = { frame = nil, cd = nil, fs = nil, flashTex = nil,
               endAt = 0, landsAt = nil, flash = 0, lastFire = 0 }
local live = { armed = false, glowOffAt = nil }

-- 前向声明:下面互相调用,而 Lua 的 local 只对**声明之后**的代码可见。
local Reposition, ApplyGeom, BuildSlot, ShowSlot, HideSlot, Evaluate, Why

-- ---------------------------------------------------------------- secret 安全层
-- 12.x 的 secret 值**用 type() 认不出来** —— 它伪装成它顶替的那个数,
-- 只在你**使用**它的时候才炸,而 `tostring()` 本身就算一次使用。
-- ⇒ 打日志是最容易炸的地方,而它炸在事件处理里 = 整个插件静默死掉。
local function isSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, s = pcall(issecretvalue, v)
    return ok and s == true
end

local function describe(v)
    if v == nil then return "nil" end
    if isSecret(v) then return "|cffff8800SECRET|r" end
    local ok, s = pcall(tostring, v)
    if not ok then return "<unreadable>" end
    return s
end

-- 探测式调用:API 不存在 / 调用被拒 / 返回 secret,三种情况各有各的说法,
-- 别糊成一个 "nil" —— 它们对应完全不同的修法。
local function call(fn, ...)
    if type(fn) ~= "function" then return "|cffff3333没这个API|r" end
    local ok, v = pcall(fn, ...)
    if not ok then return "|cffff3333ERROR|r" end
    return describe(v)
end

local function Print(msg) print("|cffff66cc" .. ADDON .. "|r " .. msg) end

-- 装了 DodoProbe 就顺手落盘一份(探测式,没装也不崩)。给 Jerry 排查用,
-- 朋友那边只会看到聊天框那一份。
local function emit(s)
    Print(s)
    if _G.DodoProbeLog then _G.DodoProbeLog("dxf", s) end
end

-- ---------------------------------------------------------------- 存档
--
-- 🔴 **默认值一个字都不写进存档。** 每次读都走下面这个带回落的取值器,
--    存档里只留玩家真正改过的东西。理由是 DodoCombatHUD 0.12 栽过的那条:
--    `db.x = db.x or 默认` 的 `or` **只在键不存在时生效** ⇒ 某一版把默认值落了盘,
--    以后再改默认值对那个人**一点用都没有**,而自动路径是静默的
--    ⇒ 零报错,表现成「这功能就是不出现」。
--    默认值根本不进存档,也就无从变旧。同一条的另一面:
--    「缺省该是开」的开关一律存**反面**(`manualOff` 缺席 = 显示)。
--
-- 键:  width / height    图标宽高(px)。缺席 = DEF_W / DEF_H
--       x / y            相对屏幕中心的偏移。缺席 = 默认位置
--       manualOff = true 玩家在面板里取消了「显示」。缺席 = 显示
--       unlocked  = true 解锁移动中。缺席 = 锁着(默认就该是锁着,所以存正面没问题)
local DEF_W, DEF_H = 48, 48
local DEF_X, DEF_Y = 0, -140

-- 🔴 上下限是**结构性防线**,不是挑剔:0 或负数进 SetSize 当场炸,
--    而一个 3px 的格子在屏幕上等于消失了 —— 玩家再也点不着它,
--    面板里也就再没有把它调回来的入口。canon:能靠结构保证的别靠算式保证。
--    判据**只在这一处声明**,滑条、输入框、斜杠命令全走它。
local MIN_DIM, MAX_DIM = 16, 128

local function ClampDim(v)
    v = tonumber(v)
    if not v then return nil end            -- 不是数 ⇒ 整条拒收,别当 0 收下
    v = math.floor(v + 0.5)
    if v < MIN_DIM then v = MIN_DIM end
    if v > MAX_DIM then v = MAX_DIM end
    return v
end

local function Num(key, def)
    local v = type(DB) == "table" and tonumber(DB[key])
    return v or def
end

-- 尺寸**现取**,不吃文件级常量。DodoCombatHUD 那边栽过:一个「另起一排」时代的
-- 写死常量被删了而这儿还在用 ⇒ SetSize(nil, nil) 当场崩,还崩在 pcall 里,
-- 表现成「容器建不出来」,完全看不出是个悬空的常量。
local function Geom()
    return ClampDim(Num("width", DEF_W)) or DEF_W,
           ClampDim(Num("height", DEF_H)) or DEF_H
end

local function Hidden()   return type(DB) == "table" and DB.manualOff == true end
local function Unlocked() return type(DB) == "table" and DB.unlocked  == true end

-- ---------------------------------------------------------------- 绿色那半:暴雪的容器
--
-- 🔑 为什么不自己读光环:12.x 战斗中光环被**扣值**(`ShouldAurasBeSecret` 为真,
--    HELPFUL 枚举直接 ERROR)⇒ 插件读不到 expirationTime。而容器跑在 C 层拿真数据,
--    所以**它画得出来**。加上「续期时 GLOW_SHOW 不重发」那条实测:
--    自己计时必然撒谎 ⇒ 倒计时只能交给它。
local GROUP = "g"

local function tintIcon(tex, r, g, b)
    pcall(function() tex:SetDesaturated(true); tex:SetVertexColor(r, g, b) end)
end

local function CountFont(h) return math.max(8, math.floor(h * 0.45 + 0.5)) end

-- 🔴 碰 aura button 有闸:光环被扣值时 / 战斗中都碰不得。
--    碰了不是报错,是**整个初始化被掀掉** ⇒ 那一格从此空着。
--    抄的是 DodoNameplate `Auras.lua:CanTouchAuraButtons`(本机在产,已经跑了几个版本)。
local function CanTouchButtons()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return false
    end
    if InCombatLockdown and InCombatLockdown() then return false end
    return true
end

local function StyleButton(button, w, h)
    button:SetSize(w, h)
    if button.dxfCooldown then
        pcall(function()
            local fs = button.dxfCooldown:GetCountdownFontString()
            if fs then
                fs:SetFont(select(1, fs:GetFont()) or STANDARD_TEXT_FONT, CountFont(h), "OUTLINE")
            end
        end)
    end
end

-- 改完尺寸要挨个碰已经建出来的 button。碰不得就记个账,脱战再补 ——
-- 🔴 **这个账必须记**:不记的话「战斗中拖了滑条」= 那次改动永远丢了,
--    而屏幕上外框已经变了、图标没变 ⇒ 半生效,比不生效更难看出是 bug。
local function RestyleButtons()
    if not CanTouchButtons() then needsResize = true; return end
    local w, h = Geom()
    for _, b in ipairs(buttons) do pcall(StyleButton, b, w, h) end
    needsResize = false
end

local function MakeContainer(parent)
    local W, H = Geom()
    local ok, c = pcall(function()
        local cc = CreateFrame("AuraContainer", "DodoXuefeiBox", parent, "CustomAuraContainerTemplate")
        cc:SetFlowLayoutAnchorPoint("TOPLEFT")
        cc:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
        cc:SetFlowLayoutMaximumLineSize(math.huge)
        cc:SetUnit("player")
        cc:AddAuraGroup(GROUP, "HELPFUL", {
            -- 语义上最多也只有 1 个,但 6 是实测跑通过的值,1 没试过,
            -- 而 DodoNameplate 那边 0 又是另一个意思 —— 三个候选三种语义,这种地方别赌。
            maxFrameCount   = 6,
            sortMethod      = AuraContainerSortMethod.Expiration,
            sortDirection   = AuraContainerSortDirection.Normal,
            candidateFilters = { includeSpellIDs = { [ID.proc] = true } },
            initializeFrame = function(button)
                local w, h = Geom()          -- ⚠ 现取:button 是**懒建**的,可能建在改尺寸之后
                local tex = button:CreateTexture(nil, "ARTWORK")
                tex:SetPoint("TOPLEFT", 1, -1)
                tex:SetPoint("BOTTOMRIGHT", -1, 1)
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                -- 🔑 画的是**血液沸腾**那张图,不是沸点自带那张 —— 你要盯的是"这一发血沸"。
                pcall(function() tex:SetTexture(C_Spell.GetSpellTexture(ID.boil)) end)
                -- 换掉容器写进来的图:**别跟它抢同一张贴图**(它每次刷新都重写)。
                -- 递一张 1x1、alpha=0 的"收数据用"贴图给它,给人看的那张它碰不到;
                -- 倒计时仍归它画 ⇒ 续期照样自动跟上。2026-08-23 真机验过。
                local sink = button:CreateTexture(nil, "BACKGROUND")
                sink:SetSize(1, 1)
                sink:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
                sink:SetAlpha(0)
                button:SetIcon(sink)
                tintIcon(tex, 0.3, 1, 0.3)
                local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
                cd:SetAllPoints(tex); cd:SetReverse(true); cd:SetDrawEdge(true)
                button:SetDurationCooldown(cd)
                button.dxfCooldown = cd
                StyleButton(button, w, h)
                buttons[#buttons + 1] = button     -- 记账:改尺寸时要挨个碰
                -- ⛔ 不接 SetApplicationCount:那个 sink 会在同一次调用里**同步**写 FontString,
                --    字体没设好就是 "Font not set",而它会把整个初始化掀掉。
            end,
            layout = { elementSpacing = 0, elementWidth = W, elementHeight = H, layoutIndex = 1 },
        })
        return cc
    end)
    if not ok then
        Print("|cffff3333建格失败|r:" .. tostring(c))
        return nil
    end
    return c
end

-- ---------------------------------------------------------------- 红色那 3 秒(echo)
--
-- 🔑 为什么这里可以自己调 `Cooldown:SetCooldown`:它的限制是
--    `SecretArguments = "AllowedWhenUntainted"` —— 挡的是**插件喂 secret**,
--    不是"插件不许调"。我们喂 GetTime() 和 3.0,都是自己算的明文 ⇒ 合法。
local function BuildEcho(parent)
    local f = CreateFrame("Frame", "DodoXuefeiEcho", parent)
    f:SetAllPoints(parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 20)     -- 盖在绿的上面

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", -1, 1)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pcall(function() tex:SetTexture(C_Spell.GetSpellTexture(ID.boil)) end)
    tintIcon(tex, 1, 0.25, 0.2)

    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints(tex); cd:SetReverse(true); cd:SetDrawEdge(true)
    pcall(function() cd:SetHideCountdownNumbers(true) end)   -- 数字自己画,要一位小数

    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("CENTER", f, "CENTER", 0, 0)

    local fl = f:CreateTexture(nil, "OVERLAY")
    fl:SetAllPoints(tex)
    fl:SetColorTexture(1, 1, 1, 1)
    fl:SetBlendMode("ADD")
    fl:SetAlpha(0)

    f:Hide()
    echo.frame, echo.cd, echo.fs, echo.flashTex = f, cd, fs, fl
end

local function EchoFire()
    if not echo.frame then return end
    local now = GetTime()
    -- 幂等:同一帧同一技能可能报两次 SUCCEEDED(2026-08-23 实测 434144 就报了两次)。
    if now - echo.lastFire < 0.1 then return end
    -- 已经在跑 = 被顶掉重排:待发那一发被逼着提前打出去了,新的重排 3 秒 ⇒ 闪一下。
    if echo.frame:IsShown() then echo.flash = 0.30 end
    echo.lastFire, echo.endAt = now, now + ECHO_LEN
    echo.landsAt = now + ECHO_LEN          -- 那一发自动血沸的落地时刻,给 GLOW_HIDE 判据用
    pcall(function() echo.cd:SetCooldown(now, ECHO_LEN) end)
    echo.frame:Show()
end

-- ---------------------------------------------------------------- 尺寸落地
--
-- 🔴 宽高有**三个**消费方,少碰一个就是「半生效」——
--    而半生效(外框变了、图标没变)比完全不生效更难看出是 bug:
--      ① 外框 slot 自己  ② 容器的 flow layout 格子  ③ **已经建出来的那些 button**
--    ③ 最容易漏,因为它在暴雪那边、要单独去碰,而且**碰它有闸**(见 CanTouchButtons)。
--    ⇒ 改尺寸只有这一个入口,滑条 / 输入框 / 斜杠命令全走它。
ApplyGeom = function()
    if not slot then return end
    local w, h = Geom()
    slot:SetSize(w, h)
    if container then
        pcall(function()
            container:SetAuraGroupLayout(GROUP, {
                elementSpacing = 0, lineSpacing = 0, groupSpacing = 0, groupLineSpacing = 0,
                forceNewLine = false,
                elementWidth = w, elementHeight = h, layoutIndex = 1,
            })
        end)
    end
    RestyleButtons()
    if echo.fs then
        pcall(function()
            echo.fs:SetFont(select(1, echo.fs:GetFont()) or STANDARD_TEXT_FONT,
                            math.max(9, math.floor(h * 0.5 + 0.5)), "OUTLINE")
        end)
    end
    if label then
        pcall(function()
            label:SetFont(select(1, label:GetFont()) or STANDARD_TEXT_FONT,
                          math.max(7, math.floor(h * 0.22 + 0.5)), "OUTLINE")
        end)
    end
    Reposition()
end

-- ---------------------------------------------------------------- 常驻状态机
-- 绿色那半靠容器自己活;红色这半没有任何光环可读、echo 落地也不发事件
-- ⇒ 必须有人盯着事件。三个信号全是明文:glow 亮/灭 + 我自己的施法。
local function resolveOverride()
    local ok, ov = pcall(function()
        return C_Spell and C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(ID.boil)
    end)
    if ok and type(ov) == "number" and not isSecret(ov) then overrideID = ov end
end

local function isBoil(id)
    if isSecret(id) or type(id) ~= "number" then return false end
    return id == ID.boil or (overrideID ~= nil and id == overrideID)
end

-- 🔴 「消耗了」不能只看一个 armed 布尔:GLOW_HIDE 和 CAST 谁先到是不保证的。
--    HIDE 先到就把 armed 清了的话,CAST 来的时候会判成"没消耗" ⇒ 红色那半永远不出现,
--    而那读起来跟"根本没出过 proc"一模一样。**用时间窗,别用布尔。**
local function consumedBy(st)
    if st.armed then return true end
    local off = st.glowOffAt
    return off ~= nil and (GetTime() - off) < 0.5
end

local function LiveOn()
    if not liveFrame then
        -- 起个名字:离线测试要够得着它,才能把那三个事件喂进去验红色那半的状态机。
        liveFrame = CreateFrame("Frame", "DodoXuefeiLive")
        liveFrame:SetScript("OnEvent", function(_, ev, a1, _, a3)
            if ev == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
                if isBoil(a1) then live.armed = true end
            elseif ev == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
                if isBoil(a1) then
                    local now = GetTime()
                    -- 🔴 glow 灭掉有**三个**原因,不是两个(2026-08-23 真机发现,
                    -- 靠「echo 归零那一刻绿的 15 跟着消失」当场定案):
                    --   ① 你打出了高亮那一发   ② 15 秒自然过期
                    --   ③ **echo 那一发把新 proc 也吃掉了** —— 它自己又排了一个 3 秒,
                    --      而它**不发任何施法事件**(已实测)⇒ 只能靠这条 HIDE 认出来。
                    -- 判据:没人刚施过法 + 这一刻正好是某个待发 echo 的落地时刻。
                    local justCast  = (now - echo.lastFire) < 0.2
                    local atEchoEnd = echo.landsAt ~= nil and math.abs(now - echo.landsAt) < 0.3
                    live.armed, live.glowOffAt = false, now
                    if (not justCast) and atEchoEnd then
                        EchoFire()          -- 链条可以继续:新的 landsAt 由它自己刷
                    end
                end
            elseif ev == "UNIT_SPELLCAST_SUCCEEDED" then
                if isSecret(a1) or a1 ~= "player" then return end   -- 先证明 unit,再碰 spellID
                if not isBoil(a3) then return end
                if consumedBy(live) then
                    live.glowOffAt = nil
                    EchoFire()
                end
            end
        end)
    end
    resolveOverride()
    live.armed, live.glowOffAt = false, nil
    echo.landsAt = nil
    liveFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    liveFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    liveFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    -- 🔑 补一次同步:/reload 或战斗中登录时 proc 可能正亮着,而那条 GLOW_SHOW 早过去了。
    -- 事件会漏,这个查询不会 —— 它返回明文 bool。
    pcall(function()
        if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed(ID.boil) then
            live.armed = true
        end
    end)
end

local function LiveOff()
    if liveFrame then liveFrame:UnregisterAllEvents() end
    if echo.frame then echo.frame:Hide() end
    echo.endAt, echo.landsAt = 0, nil
end

-- ---------------------------------------------------------------- 每帧驱动
-- 🔑 「绿现在亮着吗」**不能问容器** —— `AuraButton:IsShown()` 是 secret,结构上问不出来。
--    拿 `IsSpellOverlayed(血沸)` 当代理:明文 bool,而且它跟 proc 严格同生共死
--    (实测 glow 亮/灭就是 proc 起/落)。
local function ProcUp()
    local ok, v = pcall(function()
        return C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed(ID.boil)
    end)
    return (ok and v == true)
end

local function SetGlow(on)
    if glowOn == on or not slot then return end
    glowOn = on
    -- 搬暴雪自己那套 proc 发光(它的冷却管理器就是这么给普通框体加的),不自研:
    -- 对任意有 GetSize() 的框体成立,`.action` / `.bar` 都是 nil-safe。
    pcall(function()
        if not ActionButtonSpellAlertManager then return end
        if on then ActionButtonSpellAlertManager:ShowAlert(slot)
        else       ActionButtonSpellAlertManager:HideAlert(slot) end
    end)
end

local function RowUpdate(_, dt)
    local now = GetTime()
    local echoOn = echo.frame ~= nil and echo.endAt > now
    if echo.frame then
        if echoOn then
            if not echo.frame:IsShown() then echo.frame:Show() end
            echo.fs:SetText(("%.1f"):format(echo.endAt - now))
            if echo.flash > 0 then
                echo.flash = echo.flash - (dt or 0)
                echo.flashTex:SetAlpha(math.max(0, echo.flash / 0.30))
            end
        elseif echo.frame:IsShown() then
            echo.frame:Hide()
        end
    end
    -- 有红显红、没红有绿显绿;两种情况**都发光**。
    local active = echoOn or ProcUp()
    SetGlow(active)
    -- 空着的时候整格透明 ——「不占位」和「看不见」是两件事,而只有后者是零代价的
    -- (位置钉死不动正是反应速度的来源)。解锁摆位置时留一点底色,好让人看得见它在哪。
    -- 解锁时画出边框和「拖动」两个字。⚠ 四条边和那个字**必须一起翻** ——
    -- 只翻一半的话解锁了却看不见边界,而你正在调的就是宽和高。
    local unlocked = Unlocked()
    if bg then bg:SetAlpha(active and 0.55 or (unlocked and 0.45 or 0)) end
    local key = (unlocked and 1 or 0) + (active and 2 or 0)
    if lookKey ~= key then
        lookKey = key
        if slot and slot.dxfEdges then
            for _, t in ipairs(slot.dxfEdges) do t:SetShown(unlocked) end
        end
        if label then label:SetShown(unlocked and not active) end
    end
end

-- ---------------------------------------------------------------- 位置 / 建格
-- 位置**是拖出来的**(原版是从 HUD 的锚算出来的,它没有可拖这回事)⇒ 这边多了
-- 一个原版没有的状态:「存的位置」。`SetClampedToScreen` 兜住"拖出屏幕就再也找不回来"。
Reposition = function()
    if not slot then return end
    slot:ClearAllPoints()
    slot:SetPoint("CENTER", UIParent, "CENTER", Num("x", DEF_X), Num("y", DEF_Y))
end

-- 🔴 显隐和吃不吃鼠标**一起翻**。分开写早晚漏一个,而漏掉 EnableMouse 的症状是
--    「屏幕上有一块地方点不动」—— 一个看不见的框在挡着,想不到是它。
--    锁着的时候一律不吃鼠标:锁定的语义就是"别让我手滑挪了它,也别挡着我点东西"。
local function ApplyLock()
    if not slot then return end
    local can = slot:IsShown() and Unlocked()
    slot:EnableMouse(can and true or false)
end

BuildSlot = function()
    if slot then return true end
    if InCombatLockdown() then
        Print("|cffff3333战斗中不建框体|r —— 脱战会自动补上(受保护框体战斗中大概率被拒)。")
        return false
    end
    local w, h = Geom()
    local sf = CreateFrame("Frame", "DodoXuefeiSlot", UIParent)
    sf:SetSize(w, h)
    sf:SetMovable(true)
    sf:SetClampedToScreen(true)          -- 拖出屏幕就再也找不回来了,兜住它
    slot = sf

    bg = sf:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(sf)
    bg:SetColorTexture(0, 0, 0, 1)
    bg:SetAlpha(0)

    -- 解锁时才画的四条边 + 一个字:光靠 hover 变色**救不了发现性**
    -- (光标已经在上面才说话)。而且你正在调的就是宽和高 —— 得看得见边界。
    local edges = {}
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", 0 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0 },
                         { "TOPLEFT", "BOTTOMLEFT", 1 }, { "TOPRIGHT", "BOTTOMRIGHT", 1 } }) do
        local t = sf:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0.25, 0.75, 1, 0.9)
        t:SetPoint(e[1]); t:SetPoint(e[2])
        if e[3] > 0 then t:SetWidth(1) else t:SetHeight(1) end
        t:Hide()
        edges[#edges + 1] = t
    end
    sf.dxfEdges = edges

    label = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText("拖动")
    label:Hide()

    container = MakeContainer(sf)
    if container then
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, 0)
    end
    BuildEcho(sf)

    sf:RegisterForDrag("LeftButton")
    sf:SetScript("OnDragStart", function(self)
        if Unlocked() then self:StartMoving() end
    end)
    sf:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- 存**相对屏幕中心的偏移**,然后立刻重新锚回 CENTER ——
        -- StartMoving 会把锚点换成它自己算的那个,留着的话下次 Reposition 跟它打架。
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local us = UIParent:GetEffectiveScale()
        if cx and ux and us and us > 0 then
            local s = self:GetEffectiveScale() / us
            DB.x = math.floor(cx * s - ux + 0.5)
            DB.y = math.floor(cy * s - uy + 0.5)
        end
        Reposition()
    end)
    -- ⛔ 故意**不挂** OnEnter/OnLeave 改 alpha:RowUpdate 每帧都在算 alpha,
    --    在这儿写第二份的话下一帧就被它盖掉 —— 一个看起来在闪的 hover 高亮。
    --    canon:同一个量两份手写实现 = 静默分歧发生器。看得见靠的是边框 + 那两个字。

    -- 驱动挂在格子自己身上:它启用时一直显示(空着也占位),所以 OnUpdate 一定在跑。
    sf:SetScript("OnUpdate", RowUpdate)
    sf:Hide()
    ApplyGeom()
    return true
end

-- auto = 这次是自动判定触发的(换专精 / 换天赋 / 脱战补建),不是人敲的命令。
-- 🔴 自动路径**既不吭声、也不写存盘**。只做前者的话,自动收起会被记成"你手动关的"
--    ⇒ 换回血 DK 也不再出现,而那个状态一旦写进 SavedVariables,**重登也修不好**。
-- 🔴 ShowSlot / HideSlot 是**纯动作**:不吭声、不写存档、不做判断。
--    「该不该出现」只由 Evaluate 一处说了算,「玩家允不允许」只由 ns.SetSlotShown 一处写。
--    早先把"清 manualOff"写在这儿,后果是面板上勾一下「显示」就**无条件**显示 ——
--    法师身上也会冒出一个永远空的框,而那看起来完全像插件坏了。
ShowSlot = function()
    if not BuildSlot() then return end
    ApplyGeom()
    slot:Show()
    -- ⚠ 容器"收不收事件""什么时候重画"**都**挂在 IsVisible() 上 ⇒ 先 Show 再 SetEnabled。
    if container then pcall(function() container:SetEnabled(true) end) end
    ApplyLock()
    LiveOn()
end

HideSlot = function()
    if not slot then return end
    LiveOff()
    SetGlow(false)
    if container then pcall(function() container:SetEnabled(false) end) end
    slot:Hide()
    ApplyLock()                                   -- 隐藏了就别再吃鼠标(见 ApplyLock 上面那段)
end

-- ---------------------------------------------------------------- 什么时候该出现
-- 判据**只在这一处声明**。四条,任一不成立就不该占着屏幕:
--   ① 没被手动关掉  ② 解锁摆位置中(先于专精闸 —— 不然非血 DK 根本摆不了位置)
--   ③ 血 DK  ④ **点了沸点天赋**
-- ⚠ ④ 不能省:没点沸点的血 DK 那格永远是空的,而"空着占位"在这儿是纯噪音 ——
--   它不是"该在的不在",是"压根不该有"。
local function eligible()
    if Hidden() then return false end
    if Unlocked() then return true end

    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    if type(getSpec) ~= "function" or type(getInfo) ~= "function" then return false end
    local ok, idx = pcall(getSpec)
    if not ok or not idx then return false end
    local ok2, id = pcall(getInfo, idx)
    if not ok2 or id ~= SPEC_BLOOD then return false end

    local ok3, known = pcall(IsPlayerSpell, ID.talent)
    return ok3 and known == true
end

Evaluate = function()
    local want  = eligible()
    local shown = slot ~= nil and slot:IsShown()
    if want and not shown then ShowSlot()
    elseif (not want) and shown then HideSlot()
    elseif want and shown then ApplyLock() end
end

-- ---------------------------------------------------------------- /dxf why
-- 「它怎么不出现」有六七个可能的断点,而从屏幕上看**全都长得一样**。
-- 这个命令把每一环单独打出来,一次问清楚,别靠猜 —— 尤其是这插件要给别人用,
-- 而对方没法自己 debug:一条命令能省掉一整轮来回。
Why = function()
    emit("---- 沸点格为什么没出现 ----")
    emit("  ① 被手动关过? manualOff = " .. tostring(DB and DB.manualOff) .. "  (nil/false = 没关过)")
    emit("  ② 解锁摆位置中? unlocked = " .. tostring(DB and DB.unlocked) .. "  (true 时会无视③④直接显示)")
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    local sid
    if type(getSpec) == "function" and type(getInfo) == "function" then
        local ok, idx = pcall(getSpec)
        if ok and idx then local ok2, id = pcall(getInfo, idx); if ok2 then sid = id end end
    end
    emit(("  ③ 专精 = %s(血 DK 要 %d)"):format(describe(sid), SPEC_BLOOD))
    emit("  ④ 沸点天赋 IsPlayerSpell(" .. ID.talent .. ") = " .. call(IsPlayerSpell, ID.talent))
    emit("  ⇒ |cffffff00eligible() = " .. tostring(eligible()) .. "|r")
    emit("  ⑤ 战斗中 = " .. tostring(InCombatLockdown()))
    emit(("  ⑥ 格子建了=%s 显示中=%s 吃鼠标=%s"):format(
        tostring(slot ~= nil),
        tostring(slot ~= nil and slot:IsShown()),
        tostring(slot ~= nil and slot:IsMouseEnabled())))
    local w, h = Geom()
    emit(("  ⑦ 容器建了=%s 已建按钮=%d 待补尺寸=%s 现在能碰按钮=%s"):format(
        tostring(container ~= nil), #buttons, tostring(needsResize), tostring(CanTouchButtons())))
    emit(("  ⑧ 宽x高 = %dx%d   位置 = %d, %d(相对屏幕中心)"):format(
        w, h, Num("x", DEF_X), Num("y", DEF_Y)))
    emit("  ⑨ 光环被扣值? = " .. call(C_Secrets and C_Secrets.ShouldAurasBeSecret)
         .. "   血沸正高亮? = " .. tostring(ProcUp()))
    emit("---- 完,整段发我 ----")
end

-- ---------------------------------------------------------------- 事件
-- 起个名字:离线冒烟测试要够得着它才能把 ADDON_LOADED 喂进来,
-- 而那一步不喂的话 DB 永远是 nil ⇒ 后面所有路径都在"提前 return"里空转。
autoFrame = CreateFrame("Frame", "DodoXuefeiEvents")
autoFrame:SetScript("OnEvent", function(_, ev, arg1)
    if ev == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        -- 头一次装:说一句怎么摆位置。**平时一个字都不吭** —— 每次登录都刷一行是噪音,
        -- 而"装了没反应 / 这东西怎么挪"恰恰是唯一会真发生的那个问题,只说这一次。
        local fresh = (_G.DodoXuefeiDB == nil)
        _G.DodoXuefeiDB = type(_G.DodoXuefeiDB) == "table" and _G.DodoXuefeiDB or {}
        DB = _G.DodoXuefeiDB
        if ns.RegisterOptions then pcall(ns.RegisterOptions) end
        if fresh then
            Print("已装上。血 DK 点了|cffffff00沸点|r天赋就会自动出现一格(在屏幕中间偏下)。")
            Print("  挪位置:|cff33ff33/dxf unlock|r 然后直接拖那个蓝框,摆好 |cff33ff33/dxf lock|r。")
            Print("  改大小 / 开关:ESC → 选项 → 插件 → DodoXuefei。出问题跑 |cff33ff33/dxf why|r。")
        end
        return
    end
    if ev == "PLAYER_REGEN_ENABLED" and needsResize then pcall(RestyleButtons) end
    -- 延后一拍:登录那一刻专精 / 天赋信息不一定就绪,而这儿判错的后果是
    -- 「它今天就是不出现」—— 没有任何东西会来重试。
    C_Timer.After(1, function() pcall(Evaluate) end)
end)
for _, ev in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD",
    "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE",
    "PLAYER_REGEN_ENABLED",     -- 战斗中拒建过的 / 拒改尺寸的,脱战补上
}) do
    -- 逐个 pcall:某个补丁把事件改名了的话,只该少一个触发点,
    -- 不该让整个文件在加载期抛出去(那会让**整个插件**没加载,而症状是"它彻底不见了")。
    pcall(function() autoFrame:RegisterEvent(ev) end)
end

-- ---------------------------------------------------------------- 给面板用
-- 🔴 **面板不许自己读写存档里那个键。** 存的是 `manualOff`(缺席 = 显示)而不是 `on`,
--    面板那边要是照直觉写一个 `on`,两份判据当场分叉,而症状是
--    「勾选框和屏幕上那格对不上」—— 谁也看不出来是两个键。
--    ⇒ 只暴露**动作**,不暴露键名。尺寸同理:clamp 只在 ClampDim 一处声明,
--    滑条和输入框都得从这个门走,不然两个控件迟早各自钳出不同的值。
ns.DimBounds  = function() return MIN_DIM, MAX_DIM end
ns.GetDim     = function(key)
    local w, h = Geom()
    if key == "width" then return w end
    if key == "height" then return h end
end
ns.SetDim     = function(key, v)
    if key ~= "width" and key ~= "height" then return nil end
    local n = ClampDim(v)
    if not n then return nil end          -- 整条拒收(空串 / 不是数),别当 0 收下
    if not DB then return nil end
    DB[key] = n
    ApplyGeom()
    return n
end
ns.IsSlotShown   = function() return not Hidden() end
ns.SetSlotShown  = function(v)
    if not DB then return end
    -- ⚠ 展开写,别用 `v and nil or true` —— **`a and nil or b` 恒等于 b**
    --   (`and nil` 必然假,永远落到 or 那一支)⇒ 那个开关会完全失效,而且两个方向都错。
    --   开 = **删键**,不是写 false:写 false 就是把默认值落了盘。
    if v then DB.manualOff = nil else DB.manualOff = true end
    Evaluate()                           -- 该不该真出现,仍旧只由那一处判据决定
    if v then
        local why = ns.WhyNotShown()
        if why then emit("允许显示了,但现在还不会出现 —— " .. why)
        else emit("沸点格:|cff33ff33开|r —— 有 3 显红、没红有 15 显绿,都发光。") end
    else
        emit("沸点格:关。想要回来在面板里勾上,或者 `/dxf on`。")
    end
end
ns.IsUnlocked    = function() return Unlocked() end
ns.SetUnlocked   = function(v)
    if not DB then return end
    if v then DB.unlocked = true else DB.unlocked = nil end   -- ⚠ 删键,不写 false;同样展开写
    Evaluate()                            -- 解锁要让它现身好摆位置;上锁要按真判据收回去
    ApplyLock()
end
-- 面板拿它写那行状态。**画灰必须同时说出为什么** —— 一个点不动又不解释的控件读起来像"坏了"。
ns.WhyNotShown = function()
    if Hidden() then return "你在上面取消了「显示」。" end
    if Unlocked() then return nil end
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    if type(getSpec) ~= "function" or type(getInfo) ~= "function" then return "现在问不出当前专精。" end
    local ok, idx = pcall(getSpec)
    if not ok or not idx then return "现在问不出当前专精。" end
    local ok2, id = pcall(getInfo, idx)
    if not ok2 then return "现在问不出当前专精。" end
    if id ~= SPEC_BLOOD then return "这个专精不是血 DK —— 只有血 DK 有沸点。" end
    local ok3, known = pcall(IsPlayerSpell, ID.talent)
    if not (ok3 and known == true) then return "血 DK,但**没点沸点天赋** —— 点上就自动出现。" end
    return nil
end
ns.Why = Why

-- ---------------------------------------------------------------- /dxf
SLASH_DODOXUEFEI1 = "/dxf"
SLASH_DODOXUEFEI2 = "/xuefei"
SlashCmdList["DODOXUEFEI"] = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "why" then
        Why()
    elseif cmd == "on" then
        ns.SetSlotShown(true)
    elseif cmd == "off" then
        ns.SetSlotShown(false)
    elseif cmd == "unlock" then
        ns.SetUnlocked(true);  emit("解锁了 —— 直接拖那个蓝框换位置,摆好回来 `/dxf lock`。")
    elseif cmd == "lock" then
        ns.SetUnlocked(false); emit("锁上了(不再吃鼠标,不挡你点东西)。")
    elseif cmd == "w" or cmd == "h" then
        local key = (cmd == "w") and "width" or "height"
        local got = ns.SetDim(key, arg)
        if got then emit(("%s = %d"):format(cmd == "w" and "宽" or "高", got))
        else
            local lo, hi = ns.DimBounds()
            emit(("要一个 %d–%d 之间的数。现在 %s = %d"):format(lo, hi, cmd, ns.GetDim(key)))
        end
    elseif cmd == "pos" then
        if DB then DB.x, DB.y = nil, nil end
        Reposition()
        emit("位置回默认(屏幕中心偏下)。")
    else
        local w, h = Geom()
        emit(("沸点格:%s | 宽x高 %dx%d | 位置 %d,%d | %s"):format(
            Hidden() and "|cffff5555关|r" or "|cff33ff33开|r",
            w, h, Num("x", DEF_X), Num("y", DEF_Y),
            Unlocked() and "|cffffff00解锁中|r" or "锁着"))
        local why = ns.WhyNotShown()
        if why then emit("  现在不显示,因为:" .. why) end
        Print("  /dxf on|off  显示 / 不显示")
        Print("  /dxf unlock|lock  解锁拖动 / 锁上")
        Print("  /dxf w <数>  /dxf h <数>  宽 / 高(也可以在 ESC → 选项 → 插件 → DodoXuefei 里拉滑条)")
        Print("  /dxf pos     位置回默认(拖丢了用这个)")
        Print("  /dxf why     它为什么不出现 —— 把整段发给 Doodo")
    end
    -- 命令改完状态,开着的面板要跟上(见 Options.lua 里 ns.RefreshOptions 那段)。
    if ns.RefreshOptions then pcall(ns.RefreshOptions) end
end
