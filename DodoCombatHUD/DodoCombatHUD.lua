-- DodoCombatHUD - 自绘战斗监控 HUD(暗牧优先)。
-- 「目标血量条(上) + 疯狂条(下)」同宽上下叠;以后施法条并进同一个锚点。
--
-- 🔴 铁律 - Secret Values (12.x):
--   UnitPower / UnitHealth 都恒 secret。本插件永远不许对那些值做
--   读 / 比较 / 格式化 / tostring / 算术 —— 任何一样都是硬 Lua error。
--   它们这辈子只走两条路,都是实测过吃 secret 的控件 setter:
--       StatusBar:SetValue / SetMinMaxValues      (AllowedWhenTainted)
--       FontString:SetText                        (AllowedWhenTainted,12.1 实测出真数字)
--   ⇒ **条的长度自己就是百分比**,本文件里没有任何一处在算百分比。
--   阈值是静态刻度(纯明文几何画出来),玩家用眼睛比。
--   ⚠「按值自动变色」做不成:那要一个 secret 布尔,而 secret 数值 → 布尔那一步是比较运算 = 崩。
--   (2026-08-15 实测坐实:Curve:Evaluate(secret) = ERROR,同一条 curve 喂明文 50 = ok。)
--
-- ⚠ 血条有一个**跟资源条不同**的未验环节:资源条的量程是明文(UnitPowerMax = 100),
--   而 UnitHealthMax 很可能是 secret ⇒ 血条走的是 SetMinMaxValues(0, **secret**),
--   这个组合从没测过。所以两根条各有**独立**的错误闸:血条炸了不许带走资源条。
--   最阴的失败不是报错,是**默默不接受** ⇒ 条恒满或恒空。验收判据 = 打个怪看它跟不跟着掉。

local ADDON = "DodoCombatHUD"
local f = CreateFrame("Frame", "DodoCombatHUDFrame", UIParent)

-- 疯狂。只有暗牧有 —— 判据不用查专精 ID:UnitPowerMax 对「该单位没有的能量类型」
-- 返回明文 0(canon 实测),拿它当门就够,换专精自动跟上。
local POWER = Enum.PowerType.Insanity

local DEFAULTS = {
    x            = 0,
    y            = -200,
    width        = 260,          -- 两根条同宽
    gap          = 3,            -- 两根条之间的缝
    locked       = true,
    bgColor      = { 0.08, 0.06, 0.12, 0.85 },
    tickColor    = { 1, 1, 1, 0.9 },
    -- 下面这根:疯狂
    powerHeight  = 20,
    powerNumber  = true,
    powerTicks   = { 20, 40, 60, 80 },      -- 百分比
    -- 亮紫:保住「暗牧 = 紫」的直觉,同时明度够高,暗场景里跳得出来。
    -- ⚠ 只有配素图才成立 —— 配 atlas 是相乘,越乘越暗(见上面 powerTexture 那段)。
    powerColor   = { 0.72, 0.42, 1 },
    -- 上面这根:目标血量
    healthOn     = true,
    healthHeight = 20,        -- 跟 powerHeight 对齐(两根条等高)
    healthNumber = false,        -- 默认关:BOSS 血量是八位数,噪音大于信息
    healthTicks  = { 20 },       -- 暗言术: 灭 的斩杀线
    healthColor  = { 1, 0, 0 },        -- 纯红。素图 + 纯色才染得干净
    -- 最下面这根:自己的施法 / 引导
    castOn       = true,
    castHeight   = 14,
    castColor    = { 0.95, 0.80, 0.25 },   -- 施法
    chanColor    = { 0.25, 0.80, 0.75 },   -- 引导(反向排空,颜色也分开)
    castDebug    = false,
    -- 每个引导法术的**基础时间**跳间隔(秒)。跳数 = 基础总时长 / 它。
    -- 之所以按「基础时间」存:那一侧不含急速,所以这个常数是真常数;
    -- 而急速的影响会从「基础总时长会不会变」里自己显出来 —— 用不着去读急速。
    -- [spellID] = 跳数,由 /dch chan 校准。这是**唯一**的跳数来源 ——
    -- 曾经有过一个「按基础时长自动推」的,实测作废了,见 ChannelTicks 上面那段。
    --
    -- 下面这个默认值是**量出来的,不是猜的**:2026-08-15 现场 /dch chan 校准,
    -- 15407 是游戏自己在引导开始时给的 spellID(不是我按记忆写的 —— 猜错 ID 的表现是
    -- 静默不画刻度,跟「这功能没做好」分不出来)。
    -- ⚠ 它是**默认值不是写死**:SavedVariables 里已有的值优先(CopyDefaults 只填空),
    -- 所以 /dch chan <n> 随时覆盖。天赋改了跳数 / 暴雪重做了法术时,它不会报错、
    -- 只会静静画错 —— 覆盖它就是纠正手段。
    chanTicks    = { [15407] = 6 },   -- 精神鞭笞
    -- 血条左上角:我打在目标身上的 DoT(图标 + 倒计时)
    -- 🔑 倒计时是**暴雪的 CustomAuraContainer 画的,不是我们画的**。同一次探针里
    --    `Cooldown:SetCooldown(secret)` = ERROR 而这些图标上有数字 —— 一次采样里正反对照齐了。
    dotsOn       = true,
    dotSize      = 36,
    -- 倒计时字号 = 图标边长 × 这个比例,**不写死 px**。写死的话 /dch dsize 一改,
    -- 字就相对缩成一个点,同一件事得被反馈两轮(canon 里那条教训的原型就是这个)。
    dotFontScale = 0.45,
    dotSpacing   = 2,
    dotYOffset   = 4,
    -- 一格一个 spellID,顺序 = 屏幕上从左到右的**固定**位置。
    -- 固定位置是刻意的:某个 DoT 掉了那一格就空着,其余不动。流式排列会让剩下的图标左移,
    -- 于是每次的位置都不一样 —— 监控面板要的恰恰是「该在的不在」能一眼看出来。
    -- ⚠ 这三个 ID 是 2026-08-15 探针**打印名字核对过**的,不是按记忆写的;
    --    但天赋 / 改版仍可能让它失效,而症状是「那一格永远空着」= 静静画错。
    --    `/dch dot` 无参会把每格的 ID 和法术名列出来,那是纠正入口。
    dots         = { 34914, 589, 335467 },  -- 吸血鬼之触 / 暗言术:痛 / 暗言术:癫
    -- 藏掉暴雪自己的玩家施法条(我们下面那根是自绘的,两根一起显示纯属打架)
    hideBlizzCast = false,
    -- 材质。两个而不是一个:疯狂条要的是**暴雪原生那张图**(自带配色,染色会脏),
    -- 血条要的是「纯红」⇒ 它得用一张素图才染得干净。两者共用一个配置就必然有一边难看。
    -- 值可以是 atlas 名(`SetStatusBarTexture` 直接吃 atlas 字符串,暴雪自己就这么用的)
    -- 或者 `Interface\\...` 文件路径。/dch ptex | tex 现场换。
    -- 🔴 **试过暴雪原生那张,退回来了**。暗牧的真 atlas 是 `Unit_Priest_Insanity_Fill`
    -- (实测 `/run print(PowerBarColor["INSANITY"].atlas)`;⚠ 不是按 UnitFrame.lua 那条
    -- "UI-HUD-UnitFrame-<frameType>-<portrait>-Bar-<atlasElementName>" 公式拼的 ——
    -- 暗牧的 atlasElementName 是 nil,那个 if 不成立,暴雪走的是下面那条 elseif)。
    -- 退回来的原因:**那张图本身就是暗紫**,在暴雪原生框体上能看清是因为周围有厚金属边框
    -- 和不透明底衬着;搬到一根裸条上就没这个环境了,暗场景里直接糊掉。
    -- 而且染色对 atlas 是**相乘**,只会更暗,救不回来 ⇒ 想要亮就只能用素图自己上色。
    powerTexture = "Interface\\Buttons\\WHITE8X8",
    barTexture   = "Interface\\Buttons\\WHITE8X8",
}

local DB

local function CopyDefaults(src, dst)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- 唯一允许拿 secret 值做判断的形状:先问它是不是 secret,是就当「没有明文」。
-- 绝不写成 `v > 0` —— 对 secret 比较是崩,而且崩在 OnUpdate 里 = 每帧刷屏。
local function PlainNumber(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    if type(v) ~= "number" then return nil end
    return v
end

local function Print(msg)
    print("|cffff66cc" .. ADDON .. "|r " .. msg)
end

-- ---------------------------------------------------------------- 构件

local root, testMode = nil, false
local power, health, cast    -- 血量(上) / 疯狂(中) / 施法(下)

-- 一个条 = 底 + StatusBar + 数字 + 刻度池 + **自己的**错误闸。
-- dead 是逐条的:血条那条路没验过,它挂了不该把已经好用的资源条一起停掉。
-- 材质名写错的默认后果是**条变成一片空白**——零报错,看着像「这功能坏了」。
-- 所以 atlas 一律先问 GetAtlasInfo 存不存在;不存在就回落到素图并**吵一句**。
-- (canon:宽容的默认值会替 bug 遮丑 —— 这里故意选不宽容的那个。)
local TEX_FALLBACK = "Interface\\Buttons\\WHITE8X8"
local texWarned = {}
local function ResolveTexture(name)
    if type(name) ~= "string" or name == "" then return TEX_FALLBACK end
    if name:find("\\") then return name end            -- 看着是文件路径,交给引擎
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) then return name end
    if not texWarned[name] then
        texWarned[name] = true
        Print("材质 |cffff8800" .. name .. "|r 不存在(atlas 名打错了?)—— 先用素图顶着")
    end
    return TEX_FALLBACK
end

local function MakeBar(parent)
    local b = { ticks = {}, dead = false }
    b.frame = CreateFrame("Frame", nil, parent)
    b.bg = b.frame:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bar = CreateFrame("StatusBar", nil, b.frame)
    b.bar:SetPoint("TOPLEFT", b.frame, "TOPLEFT", 1, -1)
    b.bar:SetPoint("BOTTOMRIGHT", b.frame, "BOTTOMRIGHT", -1, 1)
    b.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    -- 数字和刻度都挂 OVERLAY,否则条填满了就把它们盖住 —— 而刻度正是这东西的全部意义。
    b.text = b.bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER", b.bar, "CENTER", 0, 0)
    -- 施法条要「左边法术名 / 右边剩余秒数」,别的条用不上,建了藏着。
    b.left = b.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.left:SetPoint("LEFT", b.bar, "LEFT", 3, 0)
    b.left:Hide()
    b.right = b.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.right:SetPoint("RIGHT", b.bar, "RIGHT", -3, 0)
    b.right:Hide()
    return b
end

-- 刻度是纯明文几何,没有任何 secret 参与 ⇒ 它永远不会崩,也永远不会因为读不到值而画错位置。
-- 用**条**的宽度不是外框的宽度:条被 1px 边框内缩过,而填充按条的宽度铺。
local function LayoutBar(b, height, ticks, color, showNumber, tex)
    b.frame:SetSize(DB.width, height)
    b.bg:SetColorTexture(unpack(DB.bgColor))
    b.bar:SetStatusBarTexture(ResolveTexture(tex))
    -- ⚠ SetStatusBarTexture 会换掉那个 Texture 对象 ⇒ 颜色必须**在它之后**再设一遍,
    -- 否则新材质带着默认白色上场,你看到的是「改了材质颜色就没了」。
    b.bar:SetStatusBarColor(unpack(color))
    b.text:SetShown(showNumber)
    for _, t in ipairs(b.ticks) do t:Hide() end
    local w = DB.width - 2
    for i, pct in ipairs(ticks) do
        local t = b.ticks[i]
        if not t then
            t = b.bar:CreateTexture(nil, "OVERLAY")
            b.ticks[i] = t
        end
        t:SetColorTexture(unpack(DB.tickColor))
        t:SetSize(1, height - 2)
        t:ClearAllPoints()
        t:SetPoint("LEFT", b.bar, "LEFT", math.floor(w * pct / 100 + 0.5), 0)
        t:Show()
    end
end

-- ---------------------------------------------------------------- 目标 DoT(血条左上角)

-- 自己读光环是死路:战斗中目标光环三种读法**全 ERROR**(不是 secret,是压根没值 ⇒ 画都没得画)。
-- 活路是暴雪的 secure 容器 —— 我们只喂它筛选条件,它自己去取数据、自己画图标和倒计时。
-- 整套照搬 DodoNameplate 那条已经在 CurseForge 上跑着的路,**唯一不一样的地方**:
-- 它绑的是 `nameplateN`(要求目标有名条),我们绑 `"target"`(2026-08-15 实测通过)。
local dots = { slots = {}, built = false, dead = false }

local function DotFilters(spellID)
    -- includeSpellIDs 只在「敌方身上的 debuff」/「友方身上的 buff」这两格里被允许
    -- (AuraContainerUtil.CanApplyIdentityCandidateFilters)—— 我们正好落在准许的那一格,
    -- 而且**战斗中 ShouldAurasBeSecret()=true 时照样精确生效**(实测 3 个 → 1 个)。
    return { includeSpellIDs = { [spellID] = true } }
end

-- 倒计时数字归暴雪画,但那个 FontString 是**拿得到的**:`Cooldown:GetCountdownFontString()`
-- (官方接口,`FrameAPICooldownDocumentation.lua`)。拿到就能任意设字号 ——
-- 比 `SetCountdownFont(fontName)` 灵活,后者只能挑现成的 FontObject,给不了任意 px。
local function StyleDotCountdown(cd, size)
    if not (cd and cd.GetCountdownFontString) then return end
    pcall(function()
        local fs = cd:GetCountdownFontString()
        if not fs then return end
        local path = fs:GetFont()
        fs:SetFont(path or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
            math.max(8, math.floor(size * (DB.dotFontScale or 0.45) + 0.5)), "OUTLINE")
    end)
end

-- bucket 收本格创建过的按钮。**必须收** —— layout 的 elementWidth/Height 只管「怎么排」,
-- 按钮自己的大小要自己 SetSize(DodoNameplate 也是分开设的)。不收的话 /dch dsize 改完
-- 排列间距变了、图标没变 —— 那种半生效比完全不生效更难看出是 bug。
local function MakeDotInit(bucket)
    return function(button)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetIcon(icon)

    -- ⚠ 这个 Cooldown 是**交给暴雪**的(SetDurationCooldown),我们自己永远不调它的
    -- SetCooldown —— 那个方法是 AllowedWhenUntainted,插件喂 secret 直接 ERROR。
    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:SetReverse(true)
    cd:SetDrawEdge(true)
    button:SetDurationCooldown(cd)

    local border = CreateFrame("Frame", nil, button, "BackdropTemplate")
    border:SetAllPoints(button)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    border:SetBackdropBorderColor(0, 0, 0, 1)
    border:SetFrameLevel(cd:GetFrameLevel() + 1)
    -- 故意不接 SetApplicationCount:那个 sink 会在同一次调用里同步写进 FontString,
    -- 字体没设好就是 "FontString:SetText(): Font not set",而它会把整个初始化掀掉。
    -- 层数对这三个 DoT 没用,不值得为它冒这个险。
    button.dchCD = cd          -- 留个引用:改大小/字号时要回头找它
    button:SetSize(DB.dotSize, DB.dotSize)
    StyleDotCountdown(cd, DB.dotSize)
    bucket[#bucket + 1] = button
    end
end

local function BuildDots()
    if dots.built or dots.dead then return end
    if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo
            and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate")) then
        dots.dead = true
        return
    end
    -- 一格一个**独立容器**。不是「一个容器三个 group」—— flow layout 会跳过空组,
    -- 掉一个 DoT 后面的就全部左移。多两个框体换位置恒定,便宜(DodoNameplate 建 120 个)。
    for i = 1, #DB.dots do
        local bucket = {}
        local ok, c = pcall(function()
            local cc = CreateFrame("AuraContainer", "DodoCombatHUDDot" .. i,
                health.frame, "CustomAuraContainerTemplate")
            cc:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
            cc:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right,
                AnchorUtil.FlowDirection.Up)
            cc:SetFlowLayoutMaximumLineSize(math.huge)
            cc:SetUnit("target")
            cc:AddAuraGroup("g", "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY", {
                -- 6 而不是 1:语义上每格最多也只可能有 1 个(includeSpellIDs 只放一个 ID 进来),
                -- 但 6 是探针里**实测跑通过**的值,1 没试过。DodoNameplate 那边 0 的含义还是
                -- 「先占位、稍后配」——三个候选值三种语义,这种地方别赌,用已经量过的那个。
                maxFrameCount = 6,
                sortMethod = AuraContainerSortMethod.Expiration,
                sortDirection = AuraContainerSortDirection.Normal,
                candidateFilters = DotFilters(DB.dots[i]),
                initializeFrame = MakeDotInit(bucket),
                layout = { elementSpacing = 0, elementWidth = DB.dotSize,
                           elementHeight = DB.dotSize, layoutIndex = 1 },
            })
            return cc
        end)
        if not ok then
            dots.dead = true
            Print("目标 DoT 那排没建起来(其余部件照常):" .. tostring(c))
            return
        end
        dots.slots[i] = { container = c, spellID = DB.dots[i], buttons = bucket }
    end
    dots.built = true
end

local function BuildHUD()
    -- root 的盒子 = **资源条**那一格,锚点就是老版本存下来的 x/y
    -- ⇒ 你已经摆好的位置一个像素都不动,血条往上长。
    root = CreateFrame("Frame", "DodoCombatHUDRoot", UIParent)
    root:SetClampedToScreen(true)
    root:SetMovable(true)

    local function startDrag() if not DB.locked then root:StartMoving() end end
    local function stopDrag()
        root:StopMovingOrSizing()
        local _, _, _, x, y = root:GetPoint()
        DB.x, DB.y = math.floor(x + 0.5), math.floor(y + 0.5)
    end
    root:RegisterForDrag("LeftButton")
    root:SetScript("OnDragStart", startDrag)
    root:SetScript("OnDragStop", stopDrag)

    power = MakeBar(root)
    power.frame:SetAllPoints(root)

    health = MakeBar(root)
    health.frame:SetPoint("BOTTOMLEFT", root, "TOPLEFT", 0, DB.gap)
    -- 血条也能抓着拖,否则解锁后只有下面那根是把手,很难受。
    health.frame:SetMovable(true)
    health.frame:RegisterForDrag("LeftButton")
    health.frame:SetScript("OnDragStart", startDrag)
    health.frame:SetScript("OnDragStop", stopDrag)

    cast = MakeBar(root)
    cast.frame:SetPoint("TOPLEFT", root, "BOTTOMLEFT", 0, -DB.gap)
    cast.left:Show()
    cast.right:Show()
    cast.frame:SetMovable(true)
    cast.frame:RegisterForDrag("LeftButton")
    cast.frame:SetScript("OnDragStart", startDrag)
    cast.frame:SetScript("OnDragStop", stopDrag)
    cast.frame:Hide()
end

local function LayoutDots()
    if not dots.built then return end
    local size, sp = DB.dotSize, DB.dotSpacing
    for i, slot in ipairs(dots.slots) do
        local c = slot.container
        c:SetSize(size, size)
        c:ClearAllPoints()
        -- 容器 → 锚到**我们自己的**框体,这个方向是允许的。反过来(我们的对象锚到容器)
        -- 会被拒:"Anchoring disallowed ... forbidden aspects: UntrustedLayoutScriptExecution"。
        c:SetPoint("BOTTOMLEFT", health.frame, "TOPLEFT", (i - 1) * (size + sp), DB.dotYOffset)
        pcall(function()
            c:SetAuraGroupLayout("g", { elementSpacing = 0, elementWidth = size,
                                        elementHeight = size, layoutIndex = 1 })
        end)
        -- 已经建出来的按钮要单独 resize(见 MakeDotInit 上面那段)。战斗中碰按钮可能被拒,
        -- 所以逐个 pcall —— 改大小这种事等脱战再点一下 /dch dsize 就好,不值得为它加状态机。
        for _, b in ipairs(slot.buttons) do
            pcall(function() b:SetSize(size, size) end)
            StyleDotCountdown(b.dchCD, size)
        end
        c:SetEnabled(DB.dotsOn ~= false and DB.healthOn ~= false)
    end
end

-- 换目标时容器**不会自己刷**:它只按 unit token 注册 UNIT_AURA,PLAYER_TARGET_CHANGED
-- 不在它的事件表里。暴雪把 UpdateAllAuras 留成公开的就是为了这个,它自己的注释写着
-- "Exposed to allow external events to trigger refreshes where needed (e.g. target changes)"。
local function RefreshDots()
    if not dots.built then return end
    for _, slot in ipairs(dots.slots) do
        pcall(function() slot.container:UpdateAllAuras() end)
    end
end

-- 改某一格的 spellID 后把筛选推下去(不用重建容器)
local function ApplyDotFilters()
    if not dots.built then return end
    for i, slot in ipairs(dots.slots) do
        local sid = DB.dots[i]
        if sid and sid ~= slot.spellID then
            pcall(function() slot.container:SetAuraGroupCandidateFilters("g", DotFilters(sid)) end)
            slot.spellID = sid
        end
    end
end

-- 暴雪自己的开关(CastingBarFrame.lua 里 1407 / 1448 就是拿它开关的),不是 Hide()+
-- UnregisterAllEvents 那种野路子。⚠ 但暴雪**会自己把它设回 true** ——
-- OverlayPlayerCastingBarMixin:EndReplacingPlayerBar() 在载具 / 覆盖施法条结束时无条件设 true。
-- 所以这不是「设一次就完了」,得每帧对一下(里面那个字段比较,开销可忽略)。
-- 不盯着的话症状是「坐了趟载具下来,暴雪的施法条又冒出来了」—— 谁也联想不到根因。
-- 🔴 守护只往**一个方向**走。第一版写成「每帧确保 showCastbar == (not hideBlizzCast)」——
-- 那在开关关着的时候会每帧把施法条**打开**,于是跟「用户自己用编辑模式/别的插件关掉它」
-- 直接打架,而症状是「我关了它又回来了」,谁也想不到是这个插件干的。
-- ⇒ 开关关着时我们一行都不碰;只有从开着切回关着的那一下,才恢复一次然后撒手。
local function ApplyBlizzCastBar(restoreNow)
    local bar = _G.PlayerCastingBarFrame
    if not bar or not bar.SetAndUpdateShowCastbar then return end
    if DB.hideBlizzCast then
        if bar.showCastbar ~= false then
            pcall(function() bar:SetAndUpdateShowCastbar(false) end)
        end
    elseif restoreNow then
        pcall(function() bar:SetAndUpdateShowCastbar(true) end)
    end
end

local function ApplyLayout()
    root:SetSize(DB.width, DB.powerHeight)
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", DB.x, DB.y)
    root:EnableMouse(not DB.locked)

    LayoutBar(power, DB.powerHeight, DB.powerTicks, DB.powerColor, DB.powerNumber, DB.powerTexture)
    LayoutBar(health, DB.healthHeight, DB.healthTicks, DB.healthColor, DB.healthNumber, DB.barTexture)

    health.frame:ClearAllPoints()
    health.frame:SetPoint("BOTTOMLEFT", root, "TOPLEFT", 0, DB.gap)
    health.frame:EnableMouse(not DB.locked)

    -- 施法条的刻度是**跟着当前引导现算**的(每个法术跳数不同),不能走 LayoutBar 那套静态刻度。
    LayoutBar(cast, DB.castHeight, {}, DB.castColor, false, DB.barTexture)
    cast.frame:ClearAllPoints()
    cast.frame:SetPoint("TOPLEFT", root, "BOTTOMLEFT", 0, -DB.gap)
    cast.frame:EnableMouse(not DB.locked)

    BuildDots()
    LayoutDots()
    ApplyBlizzCastBar()
end

-- ---------------------------------------------------------------- 驱动

local hasPower = false

-- 门:UnitPowerMax 对「没有的能量类型」返明文 0。万一哪天连 Max 也变 secret,
-- 就没法比大小了 —— 此时「有值」本身说明这个资源存在,别 fail-closed 把条藏了。
local function RefreshAvailability()
    local raw = UnitPowerMax("player", POWER)
    local plain = PlainNumber(raw)
    if plain then hasPower = plain > 0 else hasPower = (raw ~= nil) end
    power.frame:SetShown(hasPower or testMode)
end

-- 每根条自己一个 pcall + 自己一个闸。血条那条路(量程是 secret)从没验过,
-- 它挂了不许把已经好用的资源条一起停掉 —— 所以 dead 是逐条的,不是全局的。
local function Feed(b, label, maxFn, valFn, showNumber)
    if b.dead then return end
    local ok, err = pcall(function()
        b.bar:SetMinMaxValues(0, maxFn())
        b.bar:SetValue(valFn())
        if showNumber then b.text:SetText(valFn()) end
    end)
    if not ok then
        b.dead = true
        b.frame:Hide()
        Print("|cffff3333" .. label .. " 停手了|r(只报这一次,每帧报错会刷屏)")
        Print("  原文:" .. tostring(err))
        Print("  另一根条不受影响。多半是某个 setter 不再吃 secret —— 跑 /dp 重量。")
    end
end

-- 施法条定义在下面(它要用到 LayoutBar / cast),这里先占个名字给 OnUpdate 用。
local UpdateCast

local elapsed = 0
local function OnUpdate(_, dt)
    elapsed = elapsed + dt
    -- 20fps 对资源/血量够,施法条会看出台阶 ⇒ 整体提到 50fps。三根条一秒 150 次 setter,不值一提。
    if elapsed < 0.02 then return end
    elapsed = 0

    -- 盯着暴雪那根条:它会被暴雪自己在载具/覆盖条结束时设回来(见 ApplyBlizzCastBar)。
    -- 这里只是一次字段比较,不相等才动手。
    ApplyBlizzCastBar()

    if testMode then
        power.bar:SetMinMaxValues(0, 100); power.bar:SetValue(65)
        if DB.powerNumber then power.text:SetText("65") end
        health.frame:SetShown(DB.healthOn)
        health.bar:SetMinMaxValues(0, 100); health.bar:SetValue(35)
        if DB.healthNumber then health.text:SetText("35") end
        cast.frame:SetShown(DB.castOn)
        cast.bar:SetMinMaxValues(0, 100); cast.bar:SetValue(50)
        cast.bar:SetStatusBarColor(unpack(DB.chanColor))
        cast.left:SetText("施法条"); cast.right:SetText("1.5")
        return
    end

    -- 事件驱动要赌「UNIT_POWER_FREQUENT 在值 secret 时照样开火」,那个赌注我验不了。
    -- OnUpdate 无脑但结构上不可能漏刷 —— 一个测不了的机制不如一个无聊但一定对的。
    if hasPower then
        Feed(power, "疯狂条",
            function() return UnitPowerMax("player", POWER) end,
            function() return UnitPower("player", POWER) end, DB.powerNumber)
    end

    -- UnitExists 是明文布尔,拿它当门安全。
    if DB.healthOn and not health.dead and UnitExists("target") then
        health.frame:Show()
        Feed(health, "目标血条",
            function() return UnitHealthMax("target") end,
            function() return UnitHealth("target") end, DB.healthNumber)
    else
        health.frame:Hide()
    end

    -- 施法条走的是明文数据,不用 Feed 那套 secret 纪律;它自己会认出「这个法术被单独标了」。
    UpdateCast()
end

-- ---------------------------------------------------------------- 施法 / 引导

-- 自己的施法信息是**明文**:谓词按单位判(「被查的不是玩家本人或其宠物」才 secret),
-- 查 "player" 不满足条件 ⇒ 不 secret。这是三根条里唯一**能读能算**的一根。
local castCur = { id = nil, name = nil, start = 0, stop = 0, chan = false, baseTotal = nil }

local BASETIME = (Enum and Enum.DurationTimeModifier and Enum.DurationTimeModifier.BaseTime) or 1

-- 跳数 = 基础时间的总时长 / 基础跳间隔。
-- 🔑 为什么不像 Gnosis 那样读急速再调跳数:UnitSpellHaste 是 SecretWhenUnitStatsRestricted,
-- **战斗中读不到** ⇒ 那条路对我们是关的。而 GetTotalDuration(BaseTime) 不含急速,
-- 除法两边都是常数 ⇒ 跳数自然稳;万一暴雪是靠「加跳」给急速收益的,基础总时长会跟着变,
-- 这个式子照样跟得上。用不着知道急速是多少。
-- 跳数只有一条路:你校准存下来的那个整数。i/N 这几根线在任何急速下都对 ——
-- 条本身就是那次引导的真实时长,等分它跟急速无关。
--
-- 🔴 原来还有一条「基础时长 ÷ 基础跳间隔」的自动路,**2026-08-15 实测作废**:
--   UnitChannelDuration 确实能用(契约这次是对的),但 BaseTime 的读数 == RealTime、
--   modRate 恒 1.000 ⇒ 那个"基础时长"里**照样含急速**,modRate 根本不是急速。
--   拿它去除一个固定间隔,急速一变跳数就漂(实测同一个精神鞭笞 3.82s → 3.58s,
--   按 3 跳校准出的间隔,到 3.0s 时会算成 2 跳)。
--   **一个会随急速悄悄给出错误跳数的自动机制,比没有更坏** —— 删掉,不做成"永不开火的分支"。
-- 时长照旧读出来喂给 castdebug:它是我们发现上面这件事的唯一渠道,留着。
local function ChannelTicks(spellID)
    local baseTotal, modRate
    local ok, dur = pcall(UnitChannelDuration, "player")
    if ok and dur ~= nil then
        local ok2, bt = pcall(function() return dur:GetTotalDuration(BASETIME) end)
        local _,  mr = pcall(function() return dur:GetModRate() end)
        if ok2 then baseTotal = PlainNumber(bt) end
        modRate = PlainNumber(mr)
    end
    -- 没校准过就**不画** —— 画错的刻度比不画更坏:它会教你一个错的节奏,
    -- 而且看起来完全像个正经功能。
    return DB.chanTicks[spellID], baseTotal, modRate
end

local function LayoutChannelTicks(n)
    for _, t in ipairs(cast.ticks) do t:Hide() end
    if not n or n < 2 then return end
    local w = DB.width - 2
    for i = 1, n - 1 do
        local t = cast.ticks[i]
        if not t then t = cast.bar:CreateTexture(nil, "OVERLAY"); cast.ticks[i] = t end
        t:SetColorTexture(unpack(DB.tickColor))
        t:SetSize(1, DB.castHeight - 2)
        t:ClearAllPoints()
        t:SetPoint("LEFT", cast.bar, "LEFT", math.floor(w * i / n + 0.5), 0)
        t:Show()
    end
end

function UpdateCast()
    if not DB.castOn then cast.frame:Hide(); return end

    -- ⚠ 两个 API 的返回顺序**第 7 位起就分叉了**(引导是 notInterruptible,施法是 castID),
    -- spellID 一个在第 8 位一个在第 9 位。抄错了条照画、只是画的是别的东西,而且不报错。
    -- 顺序取自暴雪自己的 CastingBarFrame.lua,不是凭印象。
    local name, _, _, startMs, endMs, _, _, chanSpellID = UnitChannelInfo("player")
    local isChan, spellID = true, chanSpellID
    if name == nil then
        local n2, _, _, s2, e2, _, _, _, castSpellID = UnitCastingInfo("player")
        name, startMs, endMs, spellID, isChan = n2, s2, e2, castSpellID, false
    end
    if name == nil then
        cast.frame:Hide()
        -- ⚠ **绝不能**在这里清 castCur:/dch chan 是给「刚才那个引导」定跳数的,
        -- 而人手打字必然发生在引导**结束之后**。清了 = 那条命令永远报「先引导一次」,
        -- 而它自己打印的提示语还在说"刚才那个" —— 提示语和行为对不上,最坑。
        return
    end

    -- canon 记着谓词末尾留了「个别法术可被单独标成永远 secret」的口子。真撞上时,
    -- 这里会拿到 secret 的时间戳 —— 与其让下面那几行算术当场崩,不如**认出来**并说清楚。
    local s, e = PlainNumber(startMs), PlainNumber(endMs)
    if not s or not e then
        cast.frame:Hide()
        if not cast.warned then
            cast.warned = true
            Print("「" .. tostring(name) .. "」的施法信息是 secret(个别法术能被单独标成这样),")
            Print("  施法条对它画不出来。别的法术不受影响。")
        end
        return
    end

    local total = e - s
    if total <= 0 then cast.frame:Hide(); return end

    if castCur.id ~= spellID or castCur.start ~= s or castCur.chan ~= isChan or castCur.stop ~= e then
        castCur.id, castCur.name, castCur.start, castCur.stop, castCur.chan = spellID, name, s, e, isChan
        local n, baseTotal, modRate
        if isChan then n, baseTotal, modRate = ChannelTicks(spellID) end
        castCur.baseTotal = baseTotal
        LayoutChannelTicks(n)
        if DB.castDebug then
            Print(string.format("%s %s (id=%s) | 实际 %.2fs | 基础 %s | modRate %s | 跳数 %s",
                isChan and "引导" or "施法", tostring(name), tostring(spellID), total / 1000,
                baseTotal and string.format("%.2fs", baseTotal) or "-",
                modRate and string.format("%.3f", modRate) or "-", tostring(n or "-")))
        end
    end

    local elapsed = GetTime() * 1000 - s
    if elapsed < 0 then elapsed = 0 elseif elapsed > total then elapsed = total end

    cast.frame:Show()
    cast.bar:SetStatusBarColor(unpack(isChan and DB.chanColor or DB.castColor))
    cast.bar:SetMinMaxValues(0, total)
    cast.bar:SetValue(isChan and (total - elapsed) or elapsed)   -- 引导是反向排空
    cast.left:SetText(name)
    cast.right:SetFormattedText("%.1f", (total - elapsed) / 1000)
end

-- ---------------------------------------------------------------- 命令

local function Help()
    Print("上=目标血量(刻度 " .. table.concat(DB.healthTicks, "/") ..
          "%) / 下=疯狂(刻度 " .. table.concat(DB.powerTicks, "/") .. "%)")
    Print("  /dch unlock | lock          解锁拖动 / 锁回去(抓哪根都行)")
    Print("  /dch test                   演示模式(两根都填上,方便摆位置)")
    Print("  /dch width 260              两根条同宽")
    Print("  /dch gap 3                  两根条之间的缝")
    Print("  /dch health | cast          目标血条 / 施法条 开关")
    Print("  /dch pheight|hheight|cheight 20  条高(p=疯狂 h=血量 c=施法)")
    Print("  /dch pticks | hticks 20     刻度(百分比,逗号分隔)")
    Print("  /dch pnumber | hnumber      条上那个数字 开/关")
    Print("  /dch chan 4                 给**刚引导过**的那个法术定跳数")
    Print("  /dch castdebug              引导时打印 实际/基础时长 + 跳数")
    Print("  /dch dots                   血条左上角的目标 DoT 图标 开/关")
    Print("  /dch dot                    列出各格的 spellID 和法术名(核对用)")
    Print("  /dch dot 1 34914            改第 1 格盯哪个法术")
    Print("  /dch dsize 45               DoT 图标大小(现在 " .. tostring(DB.dotSize) .. ")")
    Print("  /dch dfont 0.45             DoT 倒计时字号 = 图标 × 这个比例(跟着图标走)")
    Print("  /dch ptex | tex             疯狂条 / 血条+施法条 的材质(atlas 名或路径)")
    Print("  /dch pcolor|hcolor|ccolor|ncolor 1 0 0   四种颜色(疯狂/血/施法/引导)")
    Print("  /dch bgcolor 0.03 0.02 0.05 1   条背景(第四个 = 不透明度,调到 1 隔断场景)")
    Print("  /dch blizzcast              藏掉/放回**暴雪自己**那根施法条")
    Print("  /dch reset                  回默认位置和尺寸")
end

-- 第四个值(alpha)可给可不给 —— 背景那条要它,三根条的填充色用不上。
-- 不给就按三位存,`SetColorTexture` / `SetStatusBarColor` 对三位都合法(alpha 默认 1)。
local function SetColor(key, arg, label)
    local r, g, b, a = string.match(arg or "", "^([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s*([%d%.]*)$")
    r, g, b, a = tonumber(r), tonumber(g), tonumber(b), tonumber(a)
    if r and g and b then
        DB[key] = a and { r, g, b, a } or { r, g, b }
        ApplyLayout()
        Print(string.format("%s = %.2f %.2f %.2f%s", label, r, g, b,
            a and string.format(" %.2f", a) or ""))
    else
        local c = DB[key] or {}
        Print(string.format("%s:给三个 0-1 的数(背景可加第四个 = 不透明度),现在 %.2f %.2f %.2f %.2f",
            label, c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1))
    end
end

local function SetTex(key, arg, label)
    if not arg or arg == "" then
        Print(label .. " = " .. tostring(DB[key]))
        Print("  改:/dch " .. (key == "powerTexture" and "ptex" or "tex") ..
              " <atlas名 或 Interface\\\\路径>")
        return
    end
    DB[key] = arg
    ApplyLayout()
    -- 不在这儿判对错:ResolveTexture 会在真正上屏那一刻校验并吵,
    -- 判两遍就会出现「这边说没问题、那边回落了」的分裂。
    Print(label .. " -> " .. arg)
end

-- 数字命令统一走这里:范围校验只写一次,省得每加一个尺寸就抄一遍。
local function SetNum(key, arg, lo, hi)
    local n = tonumber(arg)
    if n and n >= lo and n <= hi then
        DB[key] = math.floor(n); ApplyLayout(); Print(key .. " = " .. DB[key])
    else
        Print("给个 " .. lo .. "-" .. hi .. " 的数(现在是 " .. tostring(DB[key]) .. ")")
    end
end

local function SetTicks(key, arg)
    local t = {}
    for n in string.gmatch(arg, "[%d%.]+") do
        local v = tonumber(n)
        if v and v > 0 and v < 100 then t[#t + 1] = v end
    end
    if #t > 0 then
        DB[key] = t; ApplyLayout(); Print(key .. " = " .. table.concat(t, "/") .. " %")
    else
        Print("例:/dch pticks 20,40,60,80(百分比,0-100 之间)")
    end
end

local function Toggle(key, label)
    DB[key] = not DB[key]; ApplyLayout()
    Print(label .. " " .. (DB[key] and "开" or "关"))
end

SLASH_DODOCOMBATHUD1 = "/dch"
SLASH_DODOCOMBATHUD2 = "/dodocombathud"
SlashCmdList.DODOCOMBATHUD = function(msg)
    local cmd, arg = string.match(string.lower(msg or ""), "^%s*(%S*)%s*(.-)%s*$")
    -- ⚠ 上面那行把参数一起小写了。对数字/开关无所谓,但 atlas 名和文件路径**必须保原样**——
    -- 压成小写后 GetAtlasInfo 查不到,就会报「材质不存在」并回落,而名字明明是对的。
    local rawArg = string.match(msg or "", "^%s*%S*%s*(.-)%s*$")
    -- v0.1 的命令保留成别名,手指不用改。
    if cmd == "height" then cmd = "pheight" end
    if cmd == "ticks"  then cmd = "pticks"  end
    if cmd == "number" then cmd = "pnumber" end

    if cmd == "unlock" then
        DB.locked = false; ApplyLayout(); Print("已解锁 —— 拖它。摆好了 /dch lock")
    elseif cmd == "lock" then
        DB.locked = true; ApplyLayout(); Print("锁上了")
    elseif cmd == "test" then
        testMode = not testMode
        RefreshAvailability()
        Print(testMode and "演示模式开(血 35% / 疯狂 65%)" or "演示模式关")
    elseif cmd == "health"  then Toggle("healthOn", "目标血条")
    elseif cmd == "cast"    then Toggle("castOn", "施法条")
    elseif cmd == "castdebug" then Toggle("castDebug", "施法条读数打印")
    elseif cmd == "cheight" then SetNum("castHeight", arg, 4, 200)
    elseif cmd == "chan" then
        -- 跳数不写死在代码里:没有任何 API 给得出「这个引导几跳」(整份 UnitDocumentation
        -- 里没有 numTicks/tickPeriod 这类字段,暴雪自己的施法条也只给**充能**法术画段),
        -- 所以由你看一眼实际节奏定一次,反解成基础间隔存下来,之后自动跟着急速走。
        local n = tonumber(arg)
        if not castCur.id then
            Print("先引导一次(比如精神鞭笞)再跑这条 —— 它是给**刚才那个**引导定跳数的。")
        elseif n and n >= 1 and n <= 30 then
            DB.chanTicks[castCur.id] = n
            -- 把 spellID 一起打出来:要把这个跳数烤成代码里的默认值,就得有**游戏自己给的**
            -- 那个 ID。猜一个 ID 写进去,猜错的表现是静默不画,跟「没做好」分不出来。
            Print(string.format("「%s」(id=%s)定成 %d 跳,下次引导就按这个等分。",
                tostring(castCur.name or "?"), tostring(castCur.id), n))
        else
            Print("例:/dch chan 4")
        end
    elseif cmd == "ptex"   then SetTex("powerTexture", rawArg, "疯狂条材质")
    elseif cmd == "tex"    then SetTex("barTexture", rawArg, "血条/施法条材质")
    elseif cmd == "bgcolor" then SetColor("bgColor", arg, "条背景")
    elseif cmd == "pcolor" then SetColor("powerColor", arg, "疯狂条颜色")
    elseif cmd == "hcolor" then SetColor("healthColor", arg, "血条颜色")
    elseif cmd == "ccolor" then SetColor("castColor", arg, "施法颜色")
    elseif cmd == "ncolor" then SetColor("chanColor", arg, "引导颜色")
    elseif cmd == "dots" then Toggle("dotsOn", "目标 DoT 图标")
    elseif cmd == "dsize" then SetNum("dotSize", arg, 8, 120)
    elseif cmd == "dfont" then
        local n = tonumber(arg)
        if n and n >= 0.15 and n <= 1.0 then
            DB.dotFontScale = n
            ApplyLayout()
            Print(string.format("DoT 字号比例 = %.2f(图标 %d px ⇒ 字 %d px)",
                n, DB.dotSize, math.max(8, math.floor(DB.dotSize * n + 0.5))))
        else
            Print(string.format("给个 0.15-1.0 的比例(现在 %.2f ⇒ 字 %d px)",
                DB.dotFontScale or 0.45,
                math.max(8, math.floor(DB.dotSize * (DB.dotFontScale or 0.45) + 0.5))))
        end
    elseif cmd == "blizzcast" then
        Toggle("hideBlizzCast", "藏掉暴雪施法条")
        ApplyBlizzCastBar(true)   -- true = 如果是刚关掉这个开关,把条恢复一次
    elseif cmd == "dot" then
        -- 无参 = 列出来。这条命令的存在理由:烤死的 spellID 失效时**不会报错**,
        -- 只会让那一格永远空着 —— 跟「这功能没做好」分不出来。列出名字是唯一的纠正入口。
        local idx, sid = string.match(arg, "^(%d+)%s+(%d+)$")
        if idx and sid then
            idx, sid = tonumber(idx), tonumber(sid)
            if dots.slots[idx] then
                DB.dots[idx] = sid
                ApplyDotFilters()
                Print(string.format("第 %d 格 -> %d  %s", idx, sid,
                    tostring(C_Spell.GetSpellName(sid))))
            else
                Print("没有第 " .. idx .. " 格(现在 " .. #DB.dots .. " 格)")
            end
        else
            Print("目标 DoT 各格(改:/dch dot <格号> <spellID>):")
            for i, id in ipairs(DB.dots) do
                Print(string.format("  %d.  %-8d %s", i, id,
                    tostring(C_Spell.GetSpellName(id))))
            end
        end
    elseif cmd == "pnumber" then Toggle("powerNumber", "疯狂数字")
    elseif cmd == "hnumber" then Toggle("healthNumber", "血量数字")
    elseif cmd == "width"   then SetNum("width", arg, 40, 1200)
    elseif cmd == "gap"     then SetNum("gap", arg, 0, 100)
    elseif cmd == "pheight" then SetNum("powerHeight", arg, 4, 200)
    elseif cmd == "hheight" then SetNum("healthHeight", arg, 4, 200)
    elseif cmd == "pticks"  then SetTicks("powerTicks", arg)
    elseif cmd == "hticks"  then SetTicks("healthTicks", arg)
    elseif cmd == "reset" then
        DB.x, DB.y, DB.width, DB.gap = DEFAULTS.x, DEFAULTS.y, DEFAULTS.width, DEFAULTS.gap
        DB.powerHeight, DB.healthHeight = DEFAULTS.powerHeight, DEFAULTS.healthHeight
        ApplyLayout(); Print("位置和尺寸已还原")
    else
        Help()
    end
end

-- ---------------------------------------------------------------- 生命周期

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:RegisterEvent("UNIT_MAXPOWER")
f:RegisterEvent("UNIT_DISPLAYPOWER")
f:RegisterEvent("PLAYER_TARGET_CHANGED")

f:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        local saved = DodoCombatHUDDB

        -- v0.1 → v0.2 迁移:老版本只有一根条,键名没前缀。不迁的话你摆好的尺寸
        -- 会被默认值顶掉,而且看起来像「插件把我的设置弄丢了」。
        if saved and saved.powerHeight == nil then
            if saved.height ~= nil          then saved.powerHeight = saved.height end
            if saved.showNumber ~= nil      then saved.powerNumber = saved.showNumber end
            if type(saved.ticks) == "table" then saved.powerTicks  = saved.ticks end
            if saved.barColor ~= nil        then saved.powerColor  = saved.barColor end
            saved.height, saved.showNumber, saved.ticks, saved.barColor = nil, nil, nil, nil
        end

        -- v0.3 那个「基础时长 ÷ 基础跳间隔」的自动推导实测作废后,SavedVariables 里
        -- 会留下一个没人读的 chanInterval。清掉:留着不会出错,但下次谁读这个文件
        -- 会以为那个机制还在 —— 死配置的代价从来不是运行时,是它替一个不存在的东西背书。
        if saved then saved.chanInterval = nil end

        -- v0.5 → v0.6 材质那轮:两根条的配色是「素图 + 自选色」时代定的,
        -- 换成 atlas 之后旧值会让新材质发脏。一次性顶掉这两个键(**只这两个**),
        -- 并留一个标记 —— 否则他后来手动调回去,下次登录又被顶一遍,那种「设置自己会变」
        -- 是最难查的一类 bug。
        if saved and saved.uiPass20260815 == nil then
            saved.uiPass20260815 = true
            saved.powerColor  = { 1, 1, 1 }
            saved.healthColor = { 1, 0, 0 }
        end
        -- 另起一个标记而不是塞进上面那块:上一块可能已经跑过了(标记已置 true),
        -- 塞进去就永远不会执行 —— 而症状是「他说改了 45,我这儿还是 26」。
        -- 迁移块的判据是「这一次改动跑没跑过」,不是「哪一批 UI 调整」。
        if saved and saved.uiPass20260815b == nil then
            saved.uiPass20260815b = true
            saved.dotSize = 45
        end
        -- 这条不用标记,用**精确匹配那个错值**:上一版把疯狂条 atlas 猜成了下面这个名字(不存在)。
        -- 好处是他要是已经自己 /dch ptex 设成了别的,这里就不匹配 ⇒ 不动他的设置。
        -- 「顶掉一个已知的错值」比「按批次顶」更准,因为判据是值本身而不是时间。
        if saved and saved.powerTexture == "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Insanity" then
            saved.powerTexture = "Unit_Priest_Insanity_Fill"
        end
        -- 暴雪原生那张试过了、退回素图 + 亮紫(理由见 DEFAULTS.powerTexture 那段)。
        -- 同样用**精确匹配那个值**:他要是自己 /dch ptex 换成了别的,这里就不动。
        -- 颜色跟着一起顶,因为 {1,1,1} 是「配 atlas 时不染色」才成立的,配素图就是一根白条。
        if saved and saved.powerTexture == "Unit_Priest_Insanity_Fill" then
            saved.powerTexture = "Interface\\Buttons\\WHITE8X8"
            saved.powerColor   = { 0.72, 0.42, 1 }
        end
        -- 血条对齐疯狂条:抄他**当前**的 powerHeight,不是抄默认值 —— 他可能早调过。
        -- 一次性设成相等而不是让 healthHeight 永远跟随:跟随的话 /dch hheight 就变成
        -- 一个「设了没反应」的命令,那种沉默的失效比高度不齐难查得多。
        if saved and saved.uiPass20260815d == nil then
            saved.uiPass20260815d = true
            saved.healthHeight = saved.powerHeight or DEFAULTS.powerHeight
            saved.dotSize = 36
        end

        -- ⚠ CopyDefaults 逐键补默认值,对定长表(颜色 rgb/rgba)无害,但对**变长数组**是错的:
        -- 你把刻度删成两条,下次登录会被默认值把第 3、4 条悄悄补回来。
        -- 两个 ticks 是这里仅有的变长数组 —— 单独拎出来,不让它们参与合并。
        local savedPT = saved and saved.powerTicks
        local savedHT = saved and saved.healthTicks
        local savedDots = saved and saved.dots      -- 同上:变长数组,删掉一格不许被默认值补回来
        DodoCombatHUDDB = CopyDefaults(DEFAULTS, saved or {})
        DB = DodoCombatHUDDB
        if type(savedPT) == "table" and #savedPT > 0 then DB.powerTicks  = savedPT end
        if type(savedHT) == "table" and #savedHT > 0 then DB.healthTicks = savedHT end
        if type(savedDots) == "table" and #savedDots > 0 then DB.dots = savedDots end

        BuildHUD()
        ApplyLayout()
        RefreshAvailability()
        f:SetScript("OnUpdate", OnUpdate)
        Print("已加载(血条在上、疯狂在下)。/dch 看命令")
    elseif event == "PLAYER_TARGET_CHANGED" then
        if DB then RefreshDots() end
    elseif event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
        if unit == "player" and DB then RefreshAvailability() end
    elseif DB then
        RefreshAvailability()
    end
end)
