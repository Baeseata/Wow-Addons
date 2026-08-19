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

-- vararg 的第一个就是插件文件夹名(值跟以前硬编码的那个字符串一样);第二个是
-- 同插件所有文件共享的私有表 —— Options.lua 靠它拿到 ApplyLayout 这些内部函数。
local ADDON, ns = ...
ns = ns or {}
local f = CreateFrame("Frame", "DodoCombatHUDFrame", UIParent)

-- 🔑 主资源**不再写死**(0.9.0 起,原来是 `Enum.PowerType.Insanity`)。
-- `UnitPowerType("player")` 给当前专精的主资源,**零 secret 标注** ⇒ 换专精 / 德鲁伊变形
-- 自动跟上(`UNIT_DISPLAYPOWER` 本来就在监听)。
-- ⚠ 它那三个 rgb 返回值**实测是 nil**(不是 secret,是没值)⇒ 颜色只能另找路,见 PowerColor。
local POWER_NAME = {}                       -- [Enum 值] = "Insanity" / "Mana" / …
for n, v in pairs(Enum.PowerType or {}) do
    if type(v) == "number" then POWER_NAME[v] = n end
end

-- 主资源(连续,`Ctx` ⇒ 只能喂给控件自己画)
local mainPower, mainToken = nil, nil
-- 次要资源(离散,`Never` ⇒ 明文可读可算)。nil = 这个专精没有。
--   { pt = Enum值, name = "HolyPower", max = 5, mod = 1, isRune = bool }
local secondary = nil

local DEFAULTS = {
    x            = 0,
    y            = -200,
    width        = 260,          -- 两根条同宽
    gap          = 3,            -- 两根条之间的缝
    locked       = true,
    bgColor      = { 0.08, 0.06, 0.12, 0.85 },
    tickColor    = { 1, 1, 1, 0.9 },
    -- 下面这根:疯狂
    -- ⚠ 关掉它时 root 的盒子要**塌成 1px**(见 ApplyLayout)。不塌的话血条和施法条之间
    -- 会留一条跟原来等高的空隙 —— 那读起来像「条没画出来」,不像「我自己关了它」。
    powerOn      = true,
    powerHeight  = 20,
    powerNumber  = true,
    powerTicks   = { 20, 40, 60, 80 },      -- 百分比
    -- 🔑 多职业:每种资源一个颜色覆盖,key = `Enum.PowerType` 的**名字**("Mana"/"HolyPower"…)。
    -- 空 = 走 Resource.lua 那张表(它的 Insanity 就是原来这里那个默认亮紫)。
    -- 🔴 原来有个**单一**的 `powerColor`,是「只有暗牧疯狂」时代的遗物,**已删** ——
    --    玩家调过的值一次性迁进 `powerColors.Insanity`(见 PLAYER_LOGIN 那块)。
    --    留着当全局色的话,换成骑士,法力条也会是紫的。
    -- ⚠ 亮度取向不变:配素图才成立 —— 配 atlas 是相乘,越乘越暗(见 powerTexture 那段)。
    powerColors  = {},
    -- 次要资源 = 离散的那批(圣能 / 连击点 / 碎片 / 真气 / 符文 / 奥术充能 / 精华)。
    -- 自己一根条、画成 N 格,**N 格加起来仍等于其它条的总宽**(缝也算在内)。
    secondaryOn     = true,
    secondaryHeight = 12,
    segGap          = 2,
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
    -- 宽高分开(2026-08-15 拍板)。⚠ 光环图标纹理本身是方的 ⇒ 宽≠高就是拉伸,
    -- 那是**要的效果**(压扁省竖直空间),不是画错了。
    -- ⚠ 这两个值有**两处**消费方:按钮自己 SetSize + AuraGroup 的 layout.elementWidth/Height。
    --    只改一处的症状是「排列间距变了、图标没变」—— 半生效比完全不生效更难看出是 bug。
    dotWidth     = 36,
    dotHeight    = 36,
    -- 🔴 这里原来是 `dotFontScale`(字号 = 图标边长 × 比例),理由写的是「不写死 px,
    -- 否则图标一改字就相对缩成一个点,同一件事得被反馈两轮」。2026-08-15 改成绝对 px,
    -- 因为**那条理由的前提没了**:它成立于只有 slash 命令的年代(改完看不见,得进游戏
    -- 再来一轮);现在 ESC 面板里三个滑条并排、拖动实时预览,反馈当场就闭环。
    -- 而且宽高一拆,「乘哪条边」本身也没有答案了。
    -- 代价照实说:改完图标大小,字号**不会**跟着走,得自己再拉一下那个滑条。
    dotFontSize  = 16,
    dotSpacing   = 2,
    dotYOffset   = 4,
    -- 一格一个 spellID,顺序 = 屏幕上从左到右的**固定**位置。
    -- 固定位置是刻意的:某个 DoT 掉了那一格就空着,其余不动。流式排列会让剩下的图标左移,
    -- 于是每次的位置都不一样 —— 监控面板要的恰恰是「该在的不在」能一眼看出来。
    -- 🔴 0.10 起是**按专精分桶**:`dots[specID] = {ids}`,内置表在 AuraSets.lua。
    --    这里留空表 = 「一个专精都没自定义过」⇒ 全走内置。
    --    ⚠ 别在这儿写默认 ID:那会让 CopyDefaults 把它填进**每一个**存档,
    --      于是"没配过"和"配成这几个"永远分不开,而 /dch dot reset 也就没了意义。
    dots         = {},
    -- ── 大招存续(施法条**下方**,左对齐往右排,流式)──────────────
    -- 流式 = 有几个画几个、没挂就不占位。它放弃了 DoT 那排的"该在的不在一眼看出来" ——
    -- 但大招没挂是你自己没按,你本来就知道;这排的价值在"还剩几秒"。
    -- ⚠ 锚在 cast.frame 的**左下角**,而且**不跟着施法条显隐动**:施法条藏起来时那段
    --   竖直空间照样占着(位置全稳换一条恒定空隙,这是明确选的,不是漏了)。
    cdsOn        = true,
    cds          = {},            -- [specID] = {ids},同上
    cdWidth      = 32,
    cdHeight     = 32,
    cdFontSize   = 14,
    cdSpacing    = 2,
    cdYOffset    = 4,             -- 离施法条下沿多远
    -- ── 别人给我的增益(血条**右上角**,竖排三格)──────────────────
    -- 上面 1 格专给嗜血一族、下面 2 格流式装其余。分两个容器是刻意的:
    -- 「嗜血必须得有」如果靠 sortMethod 排对,就成了押在一个没验过的排序行为上的需求;
    -- 给它专属一格 ⇒ **结构上**保证有位置。(canon:能靠结构保证的别靠算式保证。)
    -- ⚠ 这两排的 ID 列表**不分专精** —— 是别人给你的,跟你什么专精无关。
    raidOn       = true,
    raidWidth    = 32,
    raidHeight   = 32,
    raidFontSize = 14,
    raidSpacing  = 2,
    raidXOffset  = 4,             -- 离血条右沿多远
    -- 右侧那个 2×N 网格**每排几个**(0.11 起,老键 `raidMax` 已废 —— 它的语义是"总上限",
    -- 换成列数以后含义完全不同,**故意改名而不是复用**:老存档里那个 2 会被读成"每排 2 个",
    -- 而那跟"我配的是每排 4"在屏幕上分不开。改名 ⇒ 老存档没这个键 ⇒ CopyDefaults 填新默认。
    -- ⚠ 总容量 = raidCols * 2,其中 **A1 那个坑归嗜血**,团队增益实际拿到 raidCols*2-1 个。
    -- 撞上问题就 `/dch raidcols 3` 顶一下(改完要 /reload:maxFrameCount 只在建组时读一次)。
    raidCols     = 4,
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
local power, health, cast    -- 血量(上) / 主资源(中) / 施法(下)
-- 🔴 次要资源那三个**必须在这儿前向声明**,不能等到 LayoutSegs 那节才 `local`。
-- 0.9.0 首次真机就栽在这:声明写在 BuildHUD **下面** ⇒ BuildHUD 里那句
-- `segHost = CreateFrame(...)` 赋的是**全局**,而 ApplyLayout 读的 local upvalue 恒为 nil
-- ⇒ 登录即 `attempt to index upvalue 'segHost' (a nil value)`。
-- ⚠ 这错**语法完全合法**(写全局是合法 Lua)⇒ `luac -p` 抓不到;
--   离线测试只覆盖 Resource.lua 的纯函数,也够不着框体装配。
--   守它的是 tools/test_scope.lua(断言声明顺序)。DodoInspect 栽过同一条。
local segHost, segPool, segsDead = nil, {}, false

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

-- 主/次资源的颜色。⚠ `UnitPowerType` 的 rgb 实测是 nil,所以走 Resource.lua 那张表:
-- 玩家覆盖(DB.powerColors[名字]) > 我们自己调的表 > 官方 PowerBarColor > 灰。
local function PowerColor(name, token)
    return ns.ColorFor(name, token, DB and DB.powerColors)
end

-- 探测「这个专精现在有哪些资源」。**不查专精 ID 表**:
--   主资源 → `UnitPowerType`(零 secret 标注,明文)
--   次要资源 → `UnitPowerMax` 对「该单位没有的资源」返明文 0(canon 实测)
-- 换专精 / 德鲁伊变形都会重跑(UNIT_DISPLAYPOWER / PLAYER_SPECIALIZATION_CHANGED)。
local function RefreshResources()
    local pt, token = UnitPowerType("player")
    mainPower, mainToken = pt, token

    secondary = nil
    if not (Enum and Enum.PowerType and ns.DISCRETE_ORDER) then return end
    for _, name in ipairs(ns.DISCRETE_ORDER) do
        local v = Enum.PowerType[name]
        -- 主资源不重复画一遍;`Alternate*` 那几个 max 也是 100 且几乎总在,必须排掉
        if v and v ~= mainPower and not ns.EXCLUDE[name] then
            local max = PlainNumber(UnitPowerMax("player", v))
            -- ⚠ 上限 12 是防守:万一哪天某个「离散」资源的 max 是 100,
            --   画 100 格等于把这根条毁掉,而那读起来像布局算错了。
            if max and max > 0 and max <= 12 then
                secondary = {
                    pt = v, name = name, max = math.floor(max),
                    mod = (UnitPowerDisplayMod and PlainNumber(UnitPowerDisplayMod(v))) or 1,
                    isRune = (name == "Runes"),
                }
                break
            end
        end
    end
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
-- 🔴 这四个必须在这儿前向声明(跟 segHost 同一条规矩)——
-- 写在下面某个函数体后面的话,那些函数里的赋值会赋成**全局**,而读的人拿到恒 nil。
-- 守它的是 tools/test_scope.lua,新增模块级变量都要加进它的 NAMES 清单。
local cdBox, lustBox, raidBox = nil, nil, nil   -- { container=, buttons={}, ids={} }
-- 0.11:右侧那两排合成**一个**容器(两个 group)。rightBox 持有真容器;
-- lustBox / raidBox 退化成指向它的两个"视图"(带各自的 group 名),下游不用全改。
local rightBox = nil
local curSpec = nil                             -- 当前专精 ID(ChrSpecialization),nil = 问不出来

-- 当前专精。⚠ 两套 API 都探一下:12.x 把不少 `GetXxx` 挪进了 `C_SpecializationInfo`,
-- 而"哪个还在"我没逐个核过 —— 探测比赌便宜。两条路都没有时返回 nil,
-- 于是三排全落到"这个专精没有内置表"= 空,而 `/dch cd` 无参会把 specID 打出来
-- ⇒ 「问不出专精」和「这专精真没有」在屏幕上分得开。
local function CurrentSpecID()
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    if not (getSpec and getInfo) then return nil end
    local ok, idx = pcall(getSpec)
    if not ok or not idx then return nil end
    local ok2, id = pcall(getInfo, idx)
    if not ok2 then return nil end
    return id
end

-- 某一排现在该盯哪些 ID(玩家配过的桶 > 内置表)。列表判定全在 AuraSets.lua 那一处,
-- 这里不再判第二遍 —— 两份手写的判据必然会漂。
local function ListFor(kind)
    local list = ns.AuraList(DB, kind, curSpec)
    return list
end

local function DotFilters(spellID)
    -- includeSpellIDs 只在「敌方身上的 debuff」/「友方身上的 buff」这两格里被允许
    -- (AuraContainerUtil.CanApplyIdentityCandidateFilters)—— 我们正好落在准许的那一格,
    -- 而且**战斗中 ShouldAurasBeSecret()=true 时照样精确生效**(实测 3 个 → 1 个)。
    return { includeSpellIDs = { [spellID] = true } }
end

-- 倒计时数字归暴雪画,但那个 FontString 是**拿得到的**:`Cooldown:GetCountdownFontString()`
-- (官方接口,`FrameAPICooldownDocumentation.lua`)。拿到就能任意设字号 ——
-- 比 `SetCountdownFont(fontName)` 灵活,后者只能挑现成的 FontObject,给不了任意 px。
-- 不再吃 size 参数:字号是**它自己的**配置项了,不从图标边长推(见 DEFAULTS.dotFontSize)。
-- ⚠ 0.10 起吃一个 `fontKey`:三排各有**自己**的字号(dotFontSize / cdFontSize / raidFontSize)。
-- 共用一个的话"DoT 字号"这个名字就骗人了 —— 调它会把另外两排一起改。
local function StyleCountdown(cd, fontKey)
    if not (cd and cd.GetCountdownFontString) then return end
    pcall(function()
        local fs = cd:GetCountdownFontString()
        if not fs then return end
        local path = fs:GetFont()
        fs:SetFont(path or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
            math.max(8, math.floor(DB[fontKey] or 16)), "OUTLINE")
    end)
end

-- bucket 收本格创建过的按钮。**必须收** —— layout 的 elementWidth/Height 只管「怎么排」,
-- 按钮自己的大小要自己 SetSize(DodoNameplate 也是分开设的)。不收的话 /dch dsize 改完
-- 排列间距变了、图标没变 —— 那种半生效比完全不生效更难看出是 bug。
-- keys = { w = "dotWidth", h = "dotHeight", font = "dotFontSize" } —— 三排各传各的。
local function MakeAuraInit(bucket, keys)
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
    button.dchKeys = keys      -- 同上:resize 时要知道这颗按钮归哪一排管
    button:SetSize(DB[keys.w], DB[keys.h])
    StyleCountdown(cd, keys.font)
    bucket[#bucket + 1] = button
    end
end

-- 三排都用同一个形状建:一个容器 + 一个 group。
-- ⚠ `parent` 跟 `SetPoint` 的目标**故意分开**:parent 决定"跟谁一起消失",
--   SetPoint 只决定"在哪儿"。大招那排要锚 cast.frame(会 Hide),团队增益要锚 health.frame
--   (healthOn 能关)—— 认它们当 parent 的话,那两排会跟着一起消失,
--   而症状是「只有正在施法时才看得见大招」,完全像 bug、想不到是 parent。
--   DoT 那排是另一回事:它**本来就该**跟血条一起消失,所以它继续 parent 到 health.frame。
local function MakeAuraBox(parent, name, unit, filter, maxCount, keys, anchorPoint, dir1, dir2)
    local bucket = {}
    local ok, c = pcall(function()
        local cc = CreateFrame("AuraContainer", name, parent, "CustomAuraContainerTemplate")
        cc:SetFlowLayoutAnchorPoint(anchorPoint)
        cc:SetFlowLayoutGrowthDirection(dir1, dir2)
        cc:SetFlowLayoutMaximumLineSize(math.huge)
        cc:SetUnit(unit)
        cc:AddAuraGroup("g", filter, {
            maxFrameCount = maxCount,
            sortMethod = AuraContainerSortMethod.Expiration,
            sortDirection = AuraContainerSortDirection.Normal,
            candidateFilters = { includeSpellIDs = {} },   -- 开局先空着,ApplyAuraFilters 立刻推真的进去
            initializeFrame = MakeAuraInit(bucket, keys),
            layout = { elementSpacing = 0, elementWidth = DB[keys.w],
                       elementHeight = DB[keys.h], layoutIndex = 1 },
        })
        return cc
    end)
    if not ok then return nil, c end
    return { container = c, buttons = bucket, keys = keys }
end

local DOT_KEYS  = { w = "dotWidth",  h = "dotHeight",  font = "dotFontSize"  }
local CD_KEYS   = { w = "cdWidth",   h = "cdHeight",   font = "cdFontSize"   }
local RAID_KEYS = { w = "raidWidth", h = "raidHeight", font = "raidFontSize" }

-- ⚠ 2026-08-17 核实:**`AnchorUtil.FlowDirection.Down` 是存在的** —— Plater / DBM-Core /
-- NorthernSkyRaidTools / 我们自己的 DodoNameplate 四家在产插件全都在用它。
-- ⇒ 下面这个 fallback **从来没有触发过**,那句橙字一次都没印出来。
-- 老 CLAUDE.md 把「右侧那列横着排」的根因记成"Down 不存在",**那条是错的**;
-- 真根因是 lust/raid 的 GrowthDirection 参数传反了 + 从没设过 Axis(见 MakeRightBox)。
-- 探测本身留着当兜底(零成本),但**别再拿它解释任何症状**。
local FLOW_DOWN
local function ResolveFlowDown()
    local F = AnchorUtil and AnchorUtil.FlowDirection
    if not F then return nil end
    if F.Down then return F.Down end
    Print("|cffff8800AnchorUtil.FlowDirection.Down 不存在|r —— 右侧那列先横着排,回头得改")
    return F.Right
end

-- 右侧那个 2×N 网格(0.11):**一个容器 + 两个 group**,不是两个容器。
-- 🔑 为什么必须合成一个:嗜血要「固定占住 A1、空着也占」,团队增益要从 B1 接着排。
--    两个独立容器**做不到** —— 各自从自己的原点摆,谁也不知道对方占了哪个坑;
--    而"给它们分不同的 ID 子集"也不行:团队增益是别人给的,**事先不知道会来哪几个**。
--    同一个容器里 flow layout 按 layoutIndex 依次摆 ⇒ lust 占第 1 个坑,raid 从第 2 个起。
-- 🔑 坑位顺序靠 **Axis** 定:Vertical + 每线 2 格高 ⇒ A1,B1,A2,B2,A3,B3…(逐列、列内从上往下)
--    ⇒ 嗜血 A1 / 团队增益 B1,A2,B2,A3,B3 —— 正是要的排法。
-- 🔴 三个方法的真实语义(照 Plater / DBM-Core / NorthernSkyRaidTools / 我们自己的
--    DodoNameplate **四家在产插件的一致写法**,不是猜的):
--      SetFlowLayoutAxis(Horizontal|Vertical) = **主轴**(先横排还是先竖排)
--      SetFlowLayoutGrowthDirection(a, b)     = a 是**水平**朝向、b 是**垂直**朝向,
--                                               **不是**「主方向 / 换行方向」
--      SetFlowLayoutMaximumLineSize(n)        = **像素**,不是个数(主轴竖直时按**高**算)
--    ⚠ 老代码给 lust/raid 传的是 `(down, right)`:水平位塞了 Down、垂直位塞了 Right,
--      顺序反的;加上 Axis 从没设过(吃默认 Horizontal)+ lineSize=huge ⇒ 实际行为是
--      **「横着一排、永不换行」**。CLAUDE.md 症状表把它记成「FlowDirection.Down 不存在」——
--      **那条根因是错的**,Down 一直都在,所以 ResolveFlowDown 那句橙字从没触发过,
--      真原因一直零信号。cdBox 传的 `(right, down)` 是对的,不受影响。
local function MakeRightBox(parent, cols)
    local bucket = {}
    local rw, rh, rsp = DB.raidWidth, DB.raidHeight, DB.raidSpacing
    local ok, c = pcall(function()
        local cc = CreateFrame("AuraContainer", "DodoCombatHUDRight", parent,
            "CustomAuraContainerTemplate")
        cc:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Vertical)
        cc:SetFlowLayoutAnchorPoint("TOPLEFT")
        cc:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right,
            AnchorUtil.FlowDirection.Down)
        cc:SetFlowLayoutMaximumLineSize(2 * rh + rsp)   -- 每列 2 格(像素!)
        cc:SetUnit("player")
        -- filter 里**故意不带 PLAYER**:嗜血 / 能量灌注常常是别人放的,带上就永远筛不到。
        -- ⚠ maxFrameCount = 1:CLAUDE.md 明记「1 没实测过」(只验过 6)。这里**必须**是 1,
        --    否则嗜血组会吃掉不止 A1 那一个坑。它要是退化成"0 = 先占位"的语义,症状是
        --    **嗜血那格永远空**,而单人环境跟"没人给我嗜血"分不开 ⇒ 只能靠 /dch probe 分辨。
        cc:AddAuraGroup("lust", "HELPFUL", {
            maxFrameCount = 1,
            sortMethod = AuraContainerSortMethod.Expiration,
            sortDirection = AuraContainerSortDirection.Normal,
            candidateFilters = { includeSpellIDs = {} },
            initializeFrame = MakeAuraInit(bucket, RAID_KEYS),
            layout = { elementSpacing = rsp, elementWidth = rw,
                       elementHeight = rh, layoutIndex = 1 },
        })
        cc:AddAuraGroup("raid", "HELPFUL", {
            maxFrameCount = math.max(1, cols * 2 - 1),   -- 总坑数减掉 A1 那个
            sortMethod = AuraContainerSortMethod.Expiration,
            sortDirection = AuraContainerSortDirection.Normal,
            candidateFilters = { includeSpellIDs = {} },
            initializeFrame = MakeAuraInit(bucket, RAID_KEYS),
            layout = { elementSpacing = rsp, elementWidth = rw,
                       elementHeight = rh, layoutIndex = 2 },
        })
        return cc
    end)
    if not ok then return nil, c end
    return { container = c, buttons = bucket, keys = RAID_KEYS }
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
    -- 🔴 按 ns.DOT_SLOTS **预建固定数量**,不再按列表长度建。
    -- 理由:格数会随专精变(术士痛苦 4 个、萨满 1 个),而换专精时**不许重建框体** ——
    -- 战斗中建受保护框体大概率被拒,而那时的症状是"换了专精那排就没了"。
    -- 用不上的格子 SetEnabled(false) 收起来,filter 改一改就换专精,零框体操作。
    for i = 1, (ns.DOT_SLOTS or 4) do
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
                candidateFilters = { includeSpellIDs = {} },  -- ApplyAuraFilters 立刻推真的进去
                initializeFrame = MakeAuraInit(bucket, DOT_KEYS),
                layout = { elementSpacing = 0, elementWidth = DB.dotWidth,
                           elementHeight = DB.dotHeight, layoutIndex = 1 },
            })
            return cc
        end)
        if not ok then
            dots.dead = true
            Print("目标 DoT 那排没建起来(其余部件照常):" .. tostring(c))
            return
        end
        dots.slots[i] = { container = c, spellID = nil, buttons = bucket }
    end

    -- ── 另外三个容器 ────────────────────────────────────────────
    -- filter 里**故意不带 `PLAYER`**:嗜血和能量灌注常常是**别人**放的,
    -- 带上 PLAYER 就永远筛不到,而症状是"那格永远空着"—— 跟 ID 填错分不开。
    -- 我们看的是"挂在 player 身上的增益",来源是谁不重要。
    FLOW_DOWN = ResolveFlowDown()
    local right = AnchorUtil and AnchorUtil.FlowDirection and AnchorUtil.FlowDirection.Right
    local down = FLOW_DOWN
    -- ⚠ 三个各接各的错误。只留一个 `err` 的话,cdBox 成功而 lust 失败时会打出 `nil` ——
    --   而"给错理由比不给更坏":它会引着人去查一个根本不是根因的东西。
    local e1, e2, e3
    if right and down then
        -- 大招:施法条下方,左对齐往右排(跟 DoT 那排同一个形状,上下对称)
        cdBox, e1 = MakeAuraBox(root, "DodoCombatHUDCds", "player", "HELPFUL",
            6, CD_KEYS, "TOPLEFT", right, down)
        -- 嗜血 + 其余团队增益:**同一个容器的两个 group**(为什么见 MakeRightBox 上面那段)。
        -- lustBox / raidBox 保留成两个"视图":共享同一个 container,只是 group 名不同 ⇒
        -- 下游(filter 推送 / probe / slash 命令)照旧按两排各管各的,不必全改一遍。
        local e23
        rightBox, e23 = MakeRightBox(root, math.max(1, math.floor(DB.raidCols or 4)))
        if rightBox then
            lustBox = { container = rightBox.container, buttons = rightBox.buttons,
                        keys = RAID_KEYS, group = "lust" }
            raidBox = { container = rightBox.container, buttons = rightBox.buttons,
                        keys = RAID_KEYS, group = "raid" }
        else
            e2, e3 = e23, e23
        end
    else
        e1 = "AnchorUtil.FlowDirection 拿不到(Right=" .. tostring(right) ..
             " Down=" .. tostring(down) .. ")"
    end
    if not (cdBox and lustBox and raidBox) then
        -- 只吵一次、只停这三排:DoT 那排已经建好了,不许被它们带走
        Print("|cffff3333右侧/下方那三排没全建起来|r(DoT 和三根条照常)")
        Print("  大招:" .. (cdBox and "OK" or tostring(e1)))
        Print("  嗜血:" .. (lustBox and "OK" or tostring(e2)))
        Print("  团队增益:" .. (raidBox and "OK" or tostring(e3)))
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

    -- 次要资源的容器(格子按需往里建,见 EnsureSegs)。默认藏着 —— 没有次要资源的专精
    -- 一个格子都不该占位置,而 ApplyLayout 会按探测结果决定显不显示。
    segHost = CreateFrame("Frame", nil, root)
    segHost:SetPoint("TOPLEFT", root, "BOTTOMLEFT", 0, -DB.gap)
    segHost:Hide()

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
    local w, h, sp = DB.dotWidth, DB.dotHeight, DB.dotSpacing
    for i, slot in ipairs(dots.slots) do
        local c = slot.container
        c:SetSize(w, h)
        c:ClearAllPoints()
        -- ⚠ 横向铺开 ⇒ 步距只跟**宽**有关。宽高拆开之前这里是 (size + sp),
        -- 照抄成 (h + sp) 的话「把图标压扁」会连横向间距一起改掉。
        -- 容器 → 锚到**我们自己的**框体,这个方向是允许的。反过来(我们的对象锚到容器)
        -- 会被拒:"Anchoring disallowed ... forbidden aspects: UntrustedLayoutScriptExecution"。
        c:SetPoint("BOTTOMLEFT", health.frame, "TOPLEFT", (i - 1) * (w + sp), DB.dotYOffset)
        pcall(function()
            c:SetAuraGroupLayout("g", { elementSpacing = 0, elementWidth = w,
                                        elementHeight = h, layoutIndex = 1 })
        end)
        -- 已经建出来的按钮要单独 resize(见 MakeDotInit 上面那段)。战斗中碰按钮可能被拒,
        -- 所以逐个 pcall —— 改大小这种事等脱战再点一下 /dch dsize 就好,不值得为它加状态机。
        for _, b in ipairs(slot.buttons) do
            pcall(function() b:SetSize(w, h) end)
            StyleCountdown(b.dchCD, "dotFontSize")
        end
    end

    -- ── 另外三排的几何 ──────────────────────────────────────────
    -- ⚠ 显隐**不在这儿**管,统一归 ApplyAuraFilters —— 它同时知道"开关"和"这排有没有 ID",
    --   两处各判一次就是 canon 说的静默分歧发生器。这里只管"多大、在哪儿"。
    -- 0.11 起**只剩大招那排**用它(右侧两排合并成 rightBox,几何在下面单独算)。
    -- 原来的 `vertical` 参数已经没有调用方 ⇒ 删掉,不留恒为 false 的死分支:
    -- 留着等于让下一个人以为"这函数支持竖排",而那条路从此没人走、也没人验。
    local function box(b, bw, bh, bsp, anchorTo, myPt, itsPt, dx, dy, n)
        if not b then return end
        local c = b.container
        c:SetSize(n * bw + (n - 1) * bsp, bh)
        c:ClearAllPoints()
        c:SetPoint(myPt, anchorTo, itsPt, dx, dy)
        pcall(function()
            c:SetAuraGroupLayout("g", { elementSpacing = bsp, elementWidth = bw,
                                        elementHeight = bh, layoutIndex = 1 })
        end)
        for _, btn in ipairs(b.buttons) do
            pcall(function() btn:SetSize(bw, bh) end)
            StyleCountdown(btn.dchCD, b.keys.font)
        end
    end

    -- 大招:锚 cast.frame 的**左下角**,而且**不管施法条显不显示** ——
    -- 施法条一藏,它的框体仍在原位(LayoutBar 无条件跑过),所以这个锚点是稳的。
    -- 代价:不施法时中间恒定空着一条 castHeight,这是明确买的,不是漏了。
    box(cdBox, DB.cdWidth, DB.cdHeight, DB.cdSpacing,
        cast.frame, "TOPLEFT", "BOTTOMLEFT", 0, -(DB.cdYOffset or 4), 6)

    -- 右侧两格:**都锚 health.frame,不互相锚** ——
    -- 「我们的对象锚到容器」是被禁的(UntrustedLayoutScriptExecution),容器锚容器也别赌。
    -- 下面那格的 y 用算的,不靠链式锚点。
    -- 右侧那个 2×N 网格:0.11 起是**一个**容器,不再是上下两格各一个。
    -- A1 落在**原来嗜血格**那个位置(血条右上)⇒ 上排 = 原嗜血行、下排 = 原团队增益行,
    -- 你已经摆好的位置一个像素不动,扩的是**往右**那几列。
    local rw, rh, rsp = DB.raidWidth, DB.raidHeight, DB.raidSpacing
    if rightBox then
        local cols = math.max(1, math.floor(DB.raidCols or 4))
        local c = rightBox.container
        c:SetSize(cols * rw + (cols - 1) * rsp, 2 * rh + rsp)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", health.frame, "TOPRIGHT", DB.raidXOffset or 4, 0)
        -- ⚠ 每线的像素高**必须跟着图标大小重算** —— 它是在建组时设过一次的,
        --    不在这儿再设的话,改完 /dch rh 就不再是"每列 2 格"(会变成 1 格或 3 格),
        --    而症状是「排布突然乱了」,想不到是这行没跟上。
        pcall(function() c:SetFlowLayoutMaximumLineSize(2 * rh + rsp) end)
        -- 两个 group 各推一次 layout。漏一个的症状是「上排图标大小对、下排不对」——
        -- 半生效比不生效更难认出是 bug(跟 dotWidth 那两个消费方同一个坑)。
        pcall(function()
            c:SetAuraGroupLayout("lust", { elementSpacing = rsp, elementWidth = rw,
                                           elementHeight = rh, layoutIndex = 1 })
        end)
        pcall(function()
            c:SetAuraGroupLayout("raid", { elementSpacing = rsp, elementWidth = rw,
                                           elementHeight = rh, layoutIndex = 2 })
        end)
        for _, btn in ipairs(rightBox.buttons) do
            pcall(function() btn:SetSize(rw, rh) end)
            StyleCountdown(btn.dchCD, "raidFontSize")
        end
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

-- 把四排的筛选条件推下去 + 决定每排显不显示。**换专精走的就是这条路** ——
-- 一个框体都不新建(战斗中建受保护框体会被拒),只改 filter,已验证的路子。
-- ⚠ SetEnabled 只在**这条路上**调(不散到 LayoutDots 去):这里同时知道"开关"和"这排有没有
--    ID",分成两处判必然漂。0.11 起它有**三个**落点、各管各的一类容器,别再读成"只有一处":
--      · 独占容器(大招)—— ApplyBoxFilter 里,靠 `not b.group` 守着
--      · DoT 固定格位   —— 每格一个,按 `sid ~= nil` 收起
--      · 右侧共享容器   —— ApplyAuraFilters 末尾统一开关(两排任一有 ID 就留着)
local function ListFilters(list)
    local set = {}
    for i = 1, #list do set[list[i]] = true end
    return { includeSpellIDs = set }
end

-- 🔴 `b.sig` 只在**推送成功之后**才记。原来它写在 pcall 外面 ——
--    一次偶发失败会被**固化成永久故障**:标记成「推过了」⇒ 从此永不重试 ⇒ 容器的
--    candidateFilters 一直停在建组时那份,而 `nil` 在暴雪那边是**全放行**
--    (`AuraContainerUtil.DoesAuraPassCandidateFilters` 第一行)⇒ 那一格显示你身上**所有**
--    增益,**且全程零报错**。2026-08-16 真撞过:三格各画了一个场景 buff(「火语者的结果」),
--    而 sig 里躺着完整的真表 —— **`sig` 有值 ≠ filter 生效了**,那次就是被它骗过去的。
-- ⚠ 如实标注:这里拆掉的是**放大器**,不是诊断出的根因。「第一次为什么会推失败」**仍然未知**
--    (暴雪那侧 `auraGroup:SetCandidateFilters` 的实现不在可读的 Lua 源码里)。
--    失败改成吵一句 —— 下次再撞上就有错误原文,而不是又一次静默固化。
local function ApplyBoxFilter(b, list, on)
    if not b then return end
    local g = b.group or "g"          -- 0.11:右侧两排共享一个容器,靠 group 名区分
    local sig = table.concat(list, ",")
    if sig ~= b.sig then
        local ok, err = pcall(function()
            b.container:SetAuraGroupCandidateFilters(g, ListFilters(list))
        end)
        if ok then
            b.sig = sig          -- 只有成功才记 ⇒ 失败时下次刷新会自动重试
        else
            Print("|cffff3333aura filter 推送失败|r(" .. g .. ",下次刷新重试):" .. tostring(err))
        end
    end
    -- 🔴 `SetEnabled` 是**容器级**的,不是 group 级 ⇒ 共享容器的那两排**不能各调各的**:
    --    嗜血列表空的时候它会把整个容器关掉,**连带团队增益一起消失**,
    --    而症状是「右边整片没了」—— 看起来像 filter 挂了,其实是被自己人关的。
    --    ⇒ 带 group 的(= 共享)交给 ApplyAuraFilters 统一开关;独占容器的照旧自己管。
    if not b.group then
        pcall(function() b.container:SetEnabled(on and #list > 0) end)
    end
end

-- 目标能不能承载「我上的 DoT」这个概念 —— **这是 filter 推不推得下去的前提,不是显示偏好**。
-- 暴雪的 `AuraContainerUtil.CanApplyIdentityCandidateFilters` 只禁两格:**友方身上的 debuff**
-- 和敌方身上的 buff。我们这排正是「HARMFUL 挂在 target 上」⇒ **目标是友方、或压根没目标时,
-- includeSpellIDs 落进被禁的那一格,被静默丢掉**(不抛错,pcall 看不见)⇒ 容器退回
-- 「没有 candidate filter」,而 nil 在暴雪那边是**全放行** ⇒ 那一格画的是「我在他身上的
-- 全部 debuff」,三格于是画同样的东西,且全程零报错。
-- 🔴 问不出来(pcall 失败)一律按**不合格**算:说不清自己在什么状态就按最严的走 ——
--    反过来写的话,一个读不到的判据会变成「那就推吧」,而推不下去正是这个 bug 的入口。
local function DotUnitEligible()
    local okE, exists = pcall(UnitExists, "target")
    if not okE or not exists then return false end
    local okA, assist = pcall(UnitCanAssist, "player", "target")
    if not okA then return false end
    return not assist
end

-- ① 目标 DoT:固定格位。列表短于 DOT_SLOTS 时,多出来的格子收起来 ——
--    别留一个空框体在那儿,那会让"这专精只有 1 个 DoT"看起来像"另外三个掉了"。
--
-- 🔴 **单独抽出来,因为它必须在每次换目标时重跑**(0.11.1)。原来它只是 ApplyAuraFilters
--    里的一段,而那个函数只在开局 / 换专精 / 动设置时跑 —— 也就是说 filter **一辈子只推一次**,
--    而那一次多半发生在**没目标或友方目标**上(登录那一刻)。撞上就是永久退化:
--    `slot.spellID` 记下了「推过了」⇒ 从此不再回头 ⇒ 三格永远画一样的东西。
--    ⇒ 记的语义也跟着改了:不再是「我打算推什么」,而是「**在一个合格的目标上**真推下去的是什么」。
local function ApplyDotFilters()
    if not dots.built then return end
    local dotList = ListFor("dots")
    local dotOn = DB.dotsOn ~= false and DB.healthOn ~= false
    local eligible = DotUnitEligible()
    for i, slot in ipairs(dots.slots) do
        local sid = dotList[i]
        if not sid then
            slot.spellID = nil          -- 收起这格:没有推送动作,直接记
        elseif not eligible then
            -- 🔴 目标不合格 ⇒ **把记录清掉**,下次遇到合格目标强制重推一次。
            --    理由:`slot.spellID` 的语义是「我确信这一格现在筛的是它」,而一次不合格的
            --    目标恰恰证明我们不再确信 —— 留着它就等于拿一个过期的把握去跳过重推,
            --    而「跳过重推」正是这个 bug 每一次的最后一环。重推很便宜(换目标本来就要
            --    UpdateAllAuras 全刷一遍),用它换掉「万一那次推送其实没落地」这一整类。
            slot.spellID = nil
        elseif sid ~= slot.spellID then
            -- 跟 ApplyBoxFilter 同一个洞(理由见那儿的长注释):`slot.spellID` 原来写在 pcall
            -- 外面 ⇒ 推送失败照样记 ⇒ 永不重试。**修类不修例**,两处一起改。
            local ok, err = pcall(function()
                slot.container:SetAuraGroupCandidateFilters("g", DotFilters(sid))
            end)
            if ok then
                slot.spellID = sid
            else
                Print("|cffff3333DoT 第 " .. i .. " 格 filter 推送失败|r(下次刷新重试):"
                    .. tostring(err))
            end
        end
        -- 🔴 fail-closed:目标不合格(友方 / 没目标)时**这排整个收起来**。
        --    留着的话它画的必然是「没经过筛选的那一堆」—— 一格空着是个可读的状态,
        --    一格画着**不该它画的东西**是在撒谎,而监控面板撒谎比不显示贵得多。
        pcall(function() slot.container:SetEnabled(dotOn and sid ~= nil and eligible) end)
    end
end

local function ApplyAuraFilters()
    if not dots.built then return end

    ApplyDotFilters()

    -- ② 大招 ③ 嗜血 ④ 其余团队增益
    ApplyBoxFilter(cdBox, ListFor("cds"), DB.cdsOn ~= false)
    local lustList, raidList = ListFor("lust"), ListFor("raid")
    ApplyBoxFilter(lustBox, lustList, DB.raidOn ~= false)
    ApplyBoxFilter(raidBox, raidList, DB.raidOn ~= false)
    -- 共享容器统一开关(见 ApplyBoxFilter 里那段):**两排任一有 ID 就留着**。
    -- 写成 `and` 的话,把嗜血那排删空就会顺手干掉团队增益 —— 而删空是个合法状态。
    if rightBox then
        local on = DB.raidOn ~= false and (#lustList > 0 or #raidList > 0)
        pcall(function() rightBox.container:SetEnabled(on) end)
    end
end

-- 专精变了就重取列表。⚠ 三排里只有 DoT 和大招跟专精走,团队增益那两排是全局表 ——
-- 但一起刷没有害处,而分开写就多一处要记得同步的地方。
local function RefreshSpec()
    curSpec = CurrentSpecID()
    ApplyAuraFilters()
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
-- ── 次要资源(离散,画成 N 格)──────────────────────────────────
-- 用**独立控件**而不是一根条上画刻度:离散资源的语义就是「几颗」,而且毁灭术那种
-- 「第 4 颗填了一半」只有独立控件画得出来(一根连续条画不出颗粒边界)。
-- ⚠ segHost / segPool / segsDead 的 `local` 在**文件上方**跟 power/health/cast 一起声明 ——
--   放这儿的话 BuildHUD(在上面)会赋成全局,见那边的注释。别再挪回来。

local function EnsureSegs(n)
    if not segHost then return end
    for i = #segPool + 1, n do
        local b = CreateFrame("StatusBar", nil, segHost)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.55)
        b:SetMinMaxValues(0, 1)   -- 每格自己就是 0..1,填多少由 ns.SegmentFill 算
        b:SetValue(0)
        segPool[i] = b
    end
end

local function LayoutSegs()
    if not segHost then return end
    local show = (secondary ~= nil) and (DB.secondaryOn ~= false) and not segsDead
    segHost:SetShown(show)
    if not show then return end

    local n   = secondary.max
    local gap = DB.segGap or 2
    local w   = ns.SegmentGeometry(DB.width, n, gap)
    local h   = DB.secondaryHeight or 12
    EnsureSegs(n)
    segHost:SetSize(DB.width, h)

    local col = PowerColor(secondary.name, nil)
    for i = 1, #segPool do
        local b = segPool[i]
        if i <= n then
            b:SetSize(w, h)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", segHost, "TOPLEFT", (i - 1) * (w + gap), 0)
            -- ⚠ SetStatusBarTexture 会换掉那个 Texture 对象 ⇒ 颜色必须**在它之后**再设
            --   (跟 LayoutBar 同一个坑)
            b:SetStatusBarTexture(ResolveTexture(DB.barTexture))
            b:SetStatusBarColor(col[1], col[2], col[3])
            b:Show()
        else
            b:Hide()
        end
    end
end

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
    -- 疯狂条关掉时 root **塌成 1px**:root 的盒子就是疯狂条那一格(power.frame 对它
    -- SetAllPoints ⇒ 真正决定疯狂条高度的是这一行,不是下面 LayoutBar 那个 SetSize),
    -- 而血条锚它上沿、施法条锚它下沿 ⇒ 不塌就留一条等高空隙,像「条没画出来」。
    -- 用 1 不用 0:高度 0 的框体行为不一致,1px 肉眼已经看不出来。
    root:SetSize(DB.width, (DB.powerOn ~= false) and DB.powerHeight or 1)
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", DB.x, DB.y)
    root:EnableMouse(not DB.locked)

    -- 颜色跟着**当前主资源**走(暗牧紫 / 骑士法力蓝 / 猫德能量黄…),不再是写死那个紫。
    LayoutBar(power, DB.powerHeight, DB.powerTicks,
        PowerColor(POWER_NAME[mainPower], mainToken), DB.powerNumber, DB.powerTexture)
    LayoutBar(health, DB.healthHeight, DB.healthTicks, DB.healthColor, DB.healthNumber, DB.barTexture)

    health.frame:ClearAllPoints()
    health.frame:SetPoint("BOTTOMLEFT", root, "TOPLEFT", 0, DB.gap)
    health.frame:EnableMouse(not DB.locked)

    -- 施法条的刻度是**跟着当前引导现算**的(每个法术跳数不同),不能走 LayoutBar 那套静态刻度。
    LayoutBar(cast, DB.castHeight, {}, DB.castColor, false, DB.barTexture)

    -- 次要资源那根插在「主资源」和「施法条」中间 ⇒ **锚链是活的**:
    -- 它显示时施法条挂它下面,不显示时施法条直接挂 root 下面。
    -- 少这一步的症状是「关掉它以后中间空一条」或者「两根条叠在一起」。
    segHost:ClearAllPoints()
    segHost:SetPoint("TOPLEFT", root, "BOTTOMLEFT", 0, -DB.gap)
    LayoutSegs()

    local castAnchor = segHost:IsShown() and segHost or root
    cast.frame:ClearAllPoints()
    cast.frame:SetPoint("TOPLEFT", castAnchor, "BOTTOMLEFT", 0, -DB.gap)
    cast.frame:EnableMouse(not DB.locked)

    BuildDots()
    LayoutDots()
    -- 几何跟筛选是两件事,但**每次都得一起跑**:ApplyLayout 会被开关 / 滑条 / 换专精
    -- 各条路径调到,而少了这一句的症状是「面板里一改,那排就空了」——
    -- 因为新建的容器 filter 还是开局那个空的。
    ApplyAuraFilters()
    ApplyBlizzCastBar()
end

-- ---------------------------------------------------------------- 驱动

local hasPower = false

-- 门:UnitPowerMax 对「没有的能量类型」返明文 0。万一哪天连 Max 也变 secret,
-- 就没法比大小了 —— 此时「有值」本身说明这个资源存在,别 fail-closed 把条藏了。
local function RefreshAvailability()
    -- mainPower 为 nil 时 UnitPowerMax 按「当前主资源」解释(契约里 powerType 是 Nilable),
    -- 所以探测还没跑过也不会炸。
    local raw = UnitPowerMax("player", mainPower)
    local plain = PlainNumber(raw)
    if plain then hasPower = plain > 0 else hasPower = (raw ~= nil) end
    -- 两个条件是不同性质的:hasPower = 「这个角色有没有这种资源」(游戏说了算),
    -- powerOn = 「我想不想看」(玩家说了算)。任一为否都不显示,但别把它们合成一个。
    power.frame:SetShown((hasPower or testMode) and DB.powerOn ~= false)
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

-- 次要资源的驱动。这批资源实测全是 `C_Secrets` 的 `Never` ⇒ **明文,可读可算**,
-- 不需要主资源那套「一个数都别读」的纪律。
-- ⚠ 但仍然 PlainNumber 挡一道:哪天暴雪把某个资源收紧成 secret,`raw / mod` 那步会当场炸,
--   而它跑在 OnUpdate 里 = 每帧刷屏。挡住的话最坏也只是这根条不动。
local function FeedSegs()
    if segsDead or not (segHost and secondary and segHost:IsShown()) then return end
    local n = secondary.max
    local ok, err = pcall(function()
        if secondary.isRune then
            -- 符文每格有**自己的**冷却 ⇒ 用不了 SegmentFill,走 RuneFills:
            -- 就绪的排前面填满,冷却中的按剩余时间升序、按进度部分填充。
            -- (`GetRuneCooldown` 零 secret 标注,三个返回值全明文 —— 契约 + VFlow 双证。)
            local runes = {}
            for i = 1, n do
                local s, d, ready = GetRuneCooldown(i)
                runes[i] = { start = s, duration = d, ready = ready }
            end
            local fills = ns.RuneFills(runes, GetTime())
            for i = 1, n do
                if segPool[i] then segPool[i]:SetValue(fills[i] or 0) end
            end
        else
            -- unmodified 的原始值 / displayMod = 带小数的精确颗数(毁灭术 3.5 就是这么来的)
            local raw = PlainNumber(UnitPower("player", secondary.pt, true))
            if raw then
                local exact = ns.ExactValue(raw, secondary.mod)
                for i = 1, n do
                    if segPool[i] then segPool[i]:SetValue(ns.SegmentFill(exact, i)) end
                end
            end
        end
    end)
    if not ok then
        segsDead = true
        segHost:Hide()
        Print("|cffff3333次要资源条停手了|r(只报这一次)")
        Print("  原文:" .. tostring(err))
        Print("  其它条不受影响。多半是那个资源被收紧成 secret 了 —— 跑 /dp 重量。")
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
        -- 标签用资源名而不是写死「疯狂条」—— 它只在报错时露面,而报错时最需要知道
        -- 「是哪个资源出的事」(换专精之后尤其)。
        Feed(power, (POWER_NAME[mainPower] or "主资源") .. " 条",
            function() return UnitPowerMax("player", mainPower) end,
            function() return UnitPower("player", mainPower) end, DB.powerNumber)
    end

    -- 次要资源(离散那批)。它走的是**明文**路径,跟上面主资源那套 secret 纪律无关。
    FeedSegs()

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
    Print("从上到下:目标 DoT / 目标血量 / 主资源 / 次要资源 / 施法引导")
    Print("  现在的主资源 = " .. tostring(POWER_NAME[mainPower] or "?") ..
          "(刻度 " .. table.concat(DB.powerTicks, "/") .. "%)" ..
          (secondary and ("  次要 = " .. secondary.name .. " " .. secondary.max .. " 格") or ""))
    Print("  /dch unlock | lock          解锁拖动 / 锁回去(抓哪根都行)")
    Print("  /dch test                   演示模式(两根都填上,方便摆位置)")
    Print("  /dch width 260              两根条同宽")
    Print("  /dch gap 3                  两根条之间的缝")
    Print("  /dch power|health|cast      主资源条 / 目标血条 / 施法条 开关")
    Print("  /dch pheight|hheight|cheight 20  条高(p=主资源 h=血量 c=施法)")
    Print("  /dch pticks | hticks 20     刻度(百分比,逗号分隔)")
    Print("  /dch pnumber | hnumber      条上那个数字 开/关")
    Print("  /dch chan 4                 给**刚引导过**的那个法术定跳数")
    Print("  /dch castdebug              引导时打印 实际/基础时长 + 跳数")
    Print("  /dch dots                   血条左上角的目标 DoT 图标 开/关")
    Print("  /dch dot                    列出各格的 spellID 和法术名(核对用)")
    Print("  /dch dot 1 34914            改第 1 格盯哪个法术  |  /dch dot reset 回内置")
    Print("  ── 施法条下方:大招存续(流式)──")
    Print("  /dch cds                    这排 开/关")
    Print("  /dch cd                     列出来 | cd add 31884 | cd del 31884 | cd reset")
    Print("  /dch cdw|cdh|cdfont|cdsp|cdy  宽 / 高 / 字号 / 间距 / 离施法条多远")
    Print("  ── 血条右上角:别人给我的增益(上 1 格嗜血 + 下 2 格流式)──")
    Print("  /dch buffs                  这两格 开/关")
    Print("  /dch lust                   嗜血那格:列出来 | lust add|del <id> | lust reset")
    Print("  /dch buff                   下面那两格:同上")
    Print("  /dch rw|rh|rfont|rsp|rx     宽 / 高 / 字号 / 间距 / 离血条多远")
    Print("  /dch raidcols 4             右侧网格每排几个(共 2 排;改完要 /reload)")
    Print("  ⚠ DoT 和大招**按专精分别存**;嗜血和团队增益是全职业一份(别人给的,跟专精无关)")
    Print("  /dch dsize 36               DoT 图标宽高一起设(现在 " ..
          tostring(DB.dotWidth) .. " x " .. tostring(DB.dotHeight) .. ")")
    Print("  /dch dw | dh 36             DoT 图标宽 / 高 单独设(要压扁就用这两个)")
    Print("  /dch dfont 16               DoT 倒计时字号 px(现在 " ..
          tostring(DB.dotFontSize) .. ",**不再**跟图标走)")
    Print("  /dch ptex | tex             主资源条 / 血条+施法条 的材质(atlas 名或路径)")
    Print("  /dch res                    看现在探测到哪些资源(换职业先跑这条)")
    Print("  /dch secondary              次要资源条(圣能/连击点/碎片…)开关")
    Print("  /dch sheight 12 | sgap 2    次要资源条 高度 / 格与格之间的缝")
    Print("  /dch pcolor|scolor 1 0 0    主 / 次 资源颜色(**按资源分别存**)")
    Print("  /dch hcolor|ccolor|ncolor 1 0 0   血 / 施法 / 引导 颜色")
    Print("  /dch bgcolor 0.03 0.02 0.05 1   条背景(第四个 = 不透明度,调到 1 隔断场景)")
    Print("  /dch blizzcast              藏掉/放回**暴雪自己**那根施法条")
    Print("  /dch reset                  回默认位置和尺寸")
    Print("  开关和尺寸也在 ESC → 选项 → 插件 → DodoCombatHUD(拖滑条实时预览)。")
    Print("  ⚠ DoT 法术 / 刻度 / 引导跳数只能在这儿改 —— 那个面板给不了输入框。")
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

-- 资源颜色现在是**按资源分**的(DB.powerColors[资源名]),不再是一个全局色 ⇒
-- 单独一个 setter:它要先知道「现在这根条画的是哪个资源」才知道往哪格写。
local function SetResourceColor(name, arg, label)
    if not name then
        Print(label .. ":现在没探测到这个资源(换个专精 / 变个形再试)")
        return
    end
    local r, g, b = string.match(arg or "", "^([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)$")
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if r and g and b then
        DB.powerColors = DB.powerColors or {}
        DB.powerColors[name] = { r, g, b }
        ApplyLayout()
        Print(string.format("%s(%s)= %.2f %.2f %.2f", label, name, r, g, b))
    else
        local c = ns.ColorFor(name, nil, DB.powerColors)
        Print(string.format("%s(%s):给三个 0-1 的数,现在 %.2f %.2f %.2f",
            label, name, c[1] or 0, c[2] or 0, c[3] or 0))
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

-- 四排 aura 的列表命令。**这三条命令的存在理由跟当初做 /dch dot 一模一样**:
-- spellID 填错 / 天赋改版让它失效时**不报错**,只是那一格永远空着 ——
-- 跟「这排没配」「这专精没有」分不开。列出 ID + 法术名是唯一的纠正入口。
-- 🔑 而且右侧那两排**单人根本验不出来**(嗜血要有人放、能量灌注要另一个牧师)⇒
--    在那两排上,这条命令是单人环境下**唯一**能确认 ID 对不对的东西。
local function SpellLabel(id)
    local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    return tostring(n or "|cffff3333<这个 ID 查不到法术>|r")
end

local function AuraCmd(kind, label, arg, slotted)
    local list = ListFor(kind)
    local _, custom = ns.AuraList(DB, kind, curSpec)
    local sub, rest = string.match(arg or "", "^(%a*)%s*(%d*)$")
    local id = tonumber(rest)

    -- 🔴 按专精那两排要写存档就得有 specID,而 `t[nil] = v` 在 Lua 里是硬错误
    -- ⇒ 玩家会看到一串读不懂的红字堆栈,而根因("问不出专精")一个字都没提。
    --    早退 + 说人话;读列表不受影响(那条路会回落到"这个专精没有内置表"= 空)。
    if ns.PER_SPEC[kind] and curSpec == nil and (arg or "") ~= "" then
        Print(label .. ":|cffff3333现在问不出当前专精|r,这一排改不了(先 /dch " ..
              (slotted and "dot" or "cd") .. " 无参看一眼)")
        return
    end

    if sub == "reset" then
        ns.ResetAuraList(DB, kind, curSpec)
        ApplyAuraFilters(); ApplyLayout()
        Print(label .. ":回内置表(" .. #ListFor(kind) .. " 个)")
        return
    elseif sub == "add" and id then
        if ns.ListAdd(list, id) then
            ns.SetAuraList(DB, kind, curSpec, list)
            ApplyAuraFilters()
            Print(label .. " + " .. id .. "  " .. SpellLabel(id))
        else
            Print(label .. ":" .. id .. " 已经在里面了")
        end
        return
    elseif sub == "del" and id then
        if ns.ListRemove(list, id) then
            ns.SetAuraList(DB, kind, curSpec, list)
            ApplyAuraFilters()
            Print(label .. " - " .. id)
        else
            Print(label .. ":里面没有 " .. id)
        end
        return
    end

    -- 固定格位那排(DoT)另有 `<格号> <spellID>` 的形状
    if slotted then
        local n, s = string.match(arg or "", "^(%d+)%s+(%d+)$")
        n, s = tonumber(n), tonumber(s)
        if n and s then
            if n >= 1 and n <= (ns.DOT_SLOTS or 4) then
                list[n] = s
                ns.SetAuraList(DB, kind, curSpec, list)
                ApplyAuraFilters()
                Print(string.format("%s 第 %d 格 -> %d  %s", label, n, s, SpellLabel(s)))
            else
                Print(label .. ":只有 1-" .. (ns.DOT_SLOTS or 4) .. " 格")
            end
            return
        end
    end

    -- 无参 = 列出来。**specID 一起打**:它是 nil 的话三排全空,而那跟"这专精没有"长得一样。
    Print(("%s —— %s(专精 %s)"):format(label,
        custom and "|cffffcc00你自己配的|r" or "内置表", tostring(curSpec or "|cffff3333问不出来|r")))
    if #list == 0 then
        Print("  (空)")
    end
    for i, sid in ipairs(list) do
        Print(string.format("  %d.  %-8d %s", i, sid, SpellLabel(sid)))
    end
    if slotted then
        Print("  改:/dch dot <格号> <spellID>   回内置:/dch dot reset")
    else
        Print("  改:add <spellID> / del <spellID> / reset")
    end
end

-- ── 🔬 `/dch probe` —— aura filter 现在到底生没生效。**保留**,不是临时探针。
-- 留着的理由:2026-08-16 那次「三格各画一个场景 buff」的**根因至今未知**(只拆掉了放大器,
-- 见 ApplyBoxFilter 上面那段),复发时这是唯一能一步定性的手段。
-- 🔑 它自带对照物:「我身上 HELPFUL 光环 = N 个」。**N = 0 时这次结果零信息量** ——
--    三格是空的会变成必然结果,跟 filter 好坏无关(canon:跑 A/B 前先确认计数器会动)。
-- 只打印 + 重推一次**本来就该推的**那个 filter,不改任何配置。
local function ProbeAuraFilters()
    -- 同时进聊天框和 DodoProbe 的落盘日志。探测式调用 ⇒ 没装 DodoProbe 也不会崩。
    local function emit(s)
        Print(s)
        if _G.DodoProbeLog then _G.DodoProbeLog("dch", s) end
    end
    emit("---- aura filter 探针 ----")
    -- ① 地基:暴雪源码里只有「assistable 单位身上的 helpful buff」才准用 includeSpellIDs。
    --    这条若是 false,CanApplyIdentityCandidateFilters 直接返回 false ⇒ 整块筛选被跳过。
    local ok0, v = pcall(UnitCanAssist, "player", "player")
    emit("  UnitCanAssist(player,player) = " .. (ok0 and tostring(v) or ("ERROR " .. tostring(v))))
    emit("  dots.built=" .. tostring(dots.built) .. "  dots.dead=" .. tostring(dots.dead))
    -- ③ 对照物:我身上现在到底有几个 HELPFUL 光环。
    --    这个数是 0 的话,「三格是空的」就是必然结果、跟 filter 好坏无关 = 零信息量
    --    (canon:跑 A/B 前先确认你那个计数器现在真的会动)。
    --    只数个数、**一个字段值都不碰** —— 碰了万一是 secret 当场炸。
    local n = 0
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or type(a) ~= "table" then break end
        n = n + 1
    end
    emit("  我身上 HELPFUL 光环 = " .. n .. " 个   (若 = 0,这次对照零信息量)")
    -- ④ DoT 那排。**0.11.1 之前这个探针根本没覆盖它** —— 而 2026-08-16 那次坏的就是这排,
    --    2026-08-18 又复发了一次。它跟右边三排**准入规则不同**(HARMFUL 挂在 target 上
    --    ⇒ 目标必须是敌方),所以右边三排全绿完全不替它背书。
    local okT, hasT   = pcall(UnitExists, "target")
    local okA, assist = pcall(UnitCanAssist, "player", "target")
    emit(("  target 存在=%s  可协助=%s  ⇒ DoT filter 准入 %s"):format(
        okT and tostring(hasT) or "ERROR", okA and tostring(assist) or "ERROR",
        DotUnitEligible() and "|cff33ff33合格|r" or "|cffff3333不合格(友方/无目标)|r"))
    -- 对照物:目标身上「我上的 debuff」有几个。0 的话「这排是空的」是必然结果、
    -- 跟 filter 好坏无关 = 零信息量(canon:跑 A/B 前先确认你那个计数器现在真的会动)。
    -- 只数个数,**一个字段值都不碰** —— 碰了万一是 secret 当场炸。
    local nt = 0
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HARMFUL|PLAYER")
        if not ok or type(a) ~= "table" then break end
        nt = nt + 1
    end
    emit("  目标身上我上的 debuff = " .. nt .. " 个   (若 = 0,这排空着属必然)")
    for i, slot in ipairs(dots.slots) do
        local want = ListFor("dots")[i]
        local how
        if not want then
            how = "跳过(这格没配)"
        elseif not DotUnitEligible() then
            how = "|cffff3333跳过(目标不合格)|r"
        else
            local ok, err = pcall(function()
                slot.container:SetAuraGroupCandidateFilters("g", DotFilters(want))
            end)
            how = ok and "|cff33ff33OK|r" or ("|cffff3333FAILED|r " .. tostring(err))
        end
        emit(("  dot%d: 该盯=%s  已推=%s  重推=%s"):format(
            i, tostring(want), tostring(slot.spellID), how))
    end
    for _, e in ipairs({ { "cds", cdBox }, { "lust", lustBox }, { "raid", raidBox } }) do
        local name, b = e[1], e[2]
        if not b then
            emit("  " .. name .. ": |cffff3333容器不存在|r")
        else
            local list = ListFor(name)
            -- ② 绕开 sig 缓存重推一次,把错误原文打出来
            local ok, err = pcall(function()
                b.container:SetAuraGroupCandidateFilters(b.group or "g", ListFilters(list))
            end)
            emit(("  %s: #list=%d  sig=%s  推送=%s"):format(name, #list, tostring(b.sig),
                ok and "|cff33ff33OK|r" or ("|cffff3333FAILED|r " .. tostring(err))))
        end
    end
    emit("  ⇒ 跑完哪一排当场变空 = 那排之前 filter 确实没推下去")
    emit("---- 探针完(/reload 后结果落进 DodoProbe.lua)----")
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
    elseif cmd == "probe"   then ProbeAuraFilters()
    elseif cmd == "health"  then Toggle("healthOn", "目标血条")
    elseif cmd == "cast"    then Toggle("castOn", "施法条")
    elseif cmd == "power"   then
        Toggle("powerOn", "主资源条")
        -- Toggle 只调 ApplyLayout(改盒子大小),**显隐归 RefreshAvailability 管** ——
        -- 少这一句的症状是「盒子塌了、条还在」,而那看起来像布局算错了。
        RefreshAvailability()
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
    elseif cmd == "ptex"   then SetTex("powerTexture", rawArg, "主资源条材质")
    elseif cmd == "tex"    then SetTex("barTexture", rawArg, "血条/施法条材质")
    elseif cmd == "bgcolor" then SetColor("bgColor", arg, "条背景")
    elseif cmd == "pcolor" then
        SetResourceColor(POWER_NAME[mainPower], arg, "主资源颜色")
    elseif cmd == "scolor" then
        SetResourceColor(secondary and secondary.name, arg, "次要资源颜色")
    elseif cmd == "secondary" then
        Toggle("secondaryOn", "次要资源条")
    elseif cmd == "sheight" then SetNum("secondaryHeight", arg, 4, 200)
    elseif cmd == "sgap"    then SetNum("segGap", arg, 0, 40)
    elseif cmd == "res" then
        -- 现在到底探测到了什么 —— 换职业后第一件要问的事。
        -- 没有它的话「次要资源条没出现」跟「这专精本来就没有」分不出来。
        Print("主资源:" .. tostring(POWER_NAME[mainPower]) ..
              "(" .. tostring(mainToken) .. ")")
        if secondary then
            Print(string.format("次要资源:%s  %d 格  displayMod=%s%s",
                secondary.name, secondary.max, tostring(secondary.mod),
                secondary.isRune and "  (符文:每格独立冷却)" or ""))
        else
            Print("次要资源:无(这个专精没有离散资源,或者被 max<=12 那道防守挡了)")
        end
    elseif cmd == "hcolor" then SetColor("healthColor", arg, "血条颜色")
    elseif cmd == "ccolor" then SetColor("castColor", arg, "施法颜色")
    elseif cmd == "ncolor" then SetColor("chanColor", arg, "引导颜色")
    elseif cmd == "dots" then Toggle("dotsOn", "目标 DoT 图标")
    elseif cmd == "dsize" then
        -- 宽高拆开之后这条留着当「两个一起设」的快捷方式 —— 手指不用改,而且多数时候
        -- 想要的就是方的。要压扁再用 dw / dh 单独调。
        local n = tonumber(arg)
        if n and n >= 8 and n <= 120 then
            DB.dotWidth, DB.dotHeight = math.floor(n), math.floor(n)
            ApplyLayout()
            Print("DoT 图标 = " .. DB.dotWidth .. " x " .. DB.dotHeight)
        else
            Print(string.format("给个 8-120 的数(现在 %d x %d)",
                DB.dotWidth or 36, DB.dotHeight or 36))
        end
    elseif cmd == "dw"    then SetNum("dotWidth",  arg, 8, 120)
    elseif cmd == "dh"    then SetNum("dotHeight", arg, 8, 120)
    elseif cmd == "dfont" then SetNum("dotFontSize", arg, 8, 60)
    elseif cmd == "blizzcast" then
        Toggle("hideBlizzCast", "藏掉暴雪施法条")
        ApplyBlizzCastBar(true)   -- true = 如果是刚关掉这个开关,把条恢复一次
    elseif cmd == "dot"  then AuraCmd("dots", "目标 DoT",   arg, true)
    elseif cmd == "cd"   then AuraCmd("cds",  "大招存续",   arg, false)
    elseif cmd == "lust" then AuraCmd("lust", "嗜血那一格", arg, false)
    elseif cmd == "buff" then AuraCmd("raid", "团队增益",   arg, false)
    elseif cmd == "cds"    then Toggle("cdsOn",  "大招那排")
    elseif cmd == "buffs"  then Toggle("raidOn", "右侧团队增益")
    elseif cmd == "cdw"    then SetNum("cdWidth",      arg, 8, 120)
    elseif cmd == "cdh"    then SetNum("cdHeight",     arg, 8, 120)
    elseif cmd == "cdfont" then SetNum("cdFontSize",   arg, 8, 60)
    elseif cmd == "cdsp"   then SetNum("cdSpacing",    arg, 0, 40)
    elseif cmd == "cdy"    then SetNum("cdYOffset",    arg, -50, 100)
    elseif cmd == "rw"     then SetNum("raidWidth",    arg, 8, 120)
    elseif cmd == "rh"     then SetNum("raidHeight",   arg, 8, 120)
    elseif cmd == "rfont"  then SetNum("raidFontSize", arg, 8, 60)
    elseif cmd == "rsp"    then SetNum("raidSpacing",  arg, 0, 40)
    elseif cmd == "rx"     then SetNum("raidXOffset",  arg, -50, 200)
    elseif cmd == "raidcols" or cmd == "raidmax" then
        -- ⚠ maxFrameCount 只在**建组**那一刻读一次 ⇒ 改完必须 /reload。不说这句的话
        --   「改了没反应」跟「这个值没用」分不开。
        -- `raidmax` 留成别名:老习惯打进去不该静默什么都不发生 —— 但**语义已经变了**
        --   (从"总上限"变成"每排几个"),所以顺口说一句,别让他按老含义理解这个数。
        if cmd == "raidmax" then
            Print("  |cffffcc00raidmax 已改名 raidcols|r,而且含义变了:现在是**每排几个**(共 2 排)")
        end
        SetNum("raidCols", arg, 1, 6)
        Print("  ⚠ 要 |cffffcc00/reload|r 之后才生效(建组时只读一次)")
    elseif cmd == "pnumber" then Toggle("powerNumber", "主资源数字")
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

-- ---------------------------------------------------------------- 对外(给 Options.lua)

-- 这几个都是 local function,别的文件够不着 ⇒ 显式挂上共享表。
-- DB 不用导出:它就是全局 `DodoCombatHUDDB` 的同一个引用(不是拷贝)⇒ 面板改的值
-- 和 slash 改的值天生是一份,不需要任何同步。
-- ⚠ 每个都挡一下 DB:面板理论上不可能在 PLAYER_LOGIN 之前被点开,但这层挡极便宜,
-- 而没有它的失败形态是 nil index —— 那会把**整个** Settings 面板掀掉,不只是我们这一页。
ns.ApplyLayout         = function()        if DB then ApplyLayout() end end
ns.RefreshAvailability = function()        if DB then RefreshAvailability() end end
ns.ApplyBlizzCastBar   = function(restore) if DB then ApplyBlizzCastBar(restore) end end
ns.LayoutDots          = function()        if DB then LayoutDots() end end
ns.DEFAULTS            = DEFAULTS

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

        -- v0.7 → v0.8:DoT 图标宽高拆开 + 倒计时字号从「比例」改成绝对 px。
        -- 🔴 **必须跑在 CopyDefaults 之前**:那个函数一跑,dotWidth/dotHeight 就被填成
        -- 默认值(非 nil)⇒ 下面 `== nil` 的判据永远不成立 ⇒ 他调过的尺寸静默丢掉,
        -- 而症状只是「下次登录图标变回 36」,零报错。
        -- 判据用「老键还在不在」,不另加 uiPassXXX 标记:老键被搬空本身就是「搬过了」,
        -- 自证且幂等,不用再记一个状态。
        if saved and saved.dotSize ~= nil then
            if saved.dotWidth  == nil then saved.dotWidth  = saved.dotSize end
            if saved.dotHeight == nil then saved.dotHeight = saved.dotSize end
            if saved.dotFontSize == nil then
                -- 按他**当时那个**比例换算,不是按默认比例 —— 换算完字号跟他现在看到的一样大,
                -- 于是这次改动对他而言是「多了两个滑条」,不是「字自己变了」。
                saved.dotFontSize = math.max(8,
                    math.floor(saved.dotSize * (saved.dotFontScale or 0.45) + 0.5))
            end
            saved.dotSize = nil
        end
        -- 死配置清掉(跟上面 chanInterval 同一个理由:留着会替一个不存在的机制背书)。
        if saved then saved.dotFontScale = nil end

        -- v0.8 → v0.9:资源条泛化。`powerColor` 曾是**全局一个色**(那时只有暗牧疯狂),
        -- 现在颜色按资源分。搬进 `powerColors.Insanity` 而不是直接丢:
        -- 丢了他手调的紫就没了;留着当全局色则换成骑士时法力条也是紫的 —— **两头都错**。
        -- 判据同样用「老键还在不在」,自证且幂等,不另记标记。
        if saved and saved.powerColor ~= nil then
            saved.powerColors = saved.powerColors or {}
            if saved.powerColors.Insanity == nil then
                saved.powerColors.Insanity = saved.powerColor
            end
            saved.powerColor = nil
        end

        -- v0.9.1:暗牧疯狂条修回亮紫。**成因链值得留着**(它解释了为什么会是白的):
        -- `uiPass20260815` 那块把 powerColor 设成白 {1,1,1} —— 那个值只在**配 atlas 材质**
        -- 「不染色」时才成立;而紧接着那两块「把 atlas 换回素图 + 改亮紫」的精确匹配
        -- **对这份存档从没成立过**(它的 powerTexture 一直就是 WHITE8X8)⇒ 白留了下来,
        -- 配素图就是一根白条。0.9.0 的迁移如实把这个白搬进了 powerColors.Insanity。
        -- ⇒ **删掉那个覆盖**(不是改写成亮紫):删掉才会回落到 Resource.lua 的 COLORS.Insanity,
        --    以后调那张表他也跟着变;写死一份就又多一个会漂的副本。
        -- 判据用**精确匹配那个已知错值**:他要是自己调过别的颜色,这里不匹配 ⇒ 不动他的设置。
        if saved and type(saved.powerColors) == "table" then
            local c = saved.powerColors.Insanity
            if type(c) == "table" and c[1] == 1 and c[2] == 1 and c[3] == 1 then
                saved.powerColors.Insanity = nil
            end
        end

        -- ⚠ CopyDefaults 逐键补默认值,对定长表(颜色 rgb/rgba)无害,但对**变长数组**是错的:
        -- 你把刻度删成两条,下次登录会被默认值把第 3、4 条悄悄补回来。
        -- 两个 ticks 是这里仅有的变长数组 —— 单独拎出来,不让它们参与合并。
        -- v0.9.2 → v0.10:`dots` 从扁平数组变成**按专精分桶**。必须在 CopyDefaults 之前
        -- (跟上面几条同一个理由),而且要先知道当前专精 —— 老那份是他上次玩的那个号的。
        -- 🔴 不迁的后果不是"丢设置":暗牧存的三个 ID 会原样带到骑士身上,那排**永远空**
        --    而且自愈不了(存档里有值,内置表永远填不进去)。判据和幂等性见 AuraSets.lua。
        -- 🔴 AuraSets.lua 是 0.10 新加的文件。它没加载起来时(TOC 少一行 / 只 /reload 没重启
        -- 客户端 / 那个文件语法错)后果不是"少一个功能",是**四排 aura 全崩** ——
        -- 而症状会是一串 `attempt to call a nil value`,根因一个字都没提。吵一句,别静默。
        if type(ns.AuraList) ~= "function" then
            Print("|cffff3333AuraSets.lua 没加载|r —— 四排 aura 全停。" ..
                  "TOC 里少了那一行,或者新文件要**完整重启客户端**才认(/reload 不重扫)。")
            ns.AuraList = function() return {}, false end
            ns.SetAuraList = function() return false end
            ns.ResetAuraList = function() return false end
            ns.MigrateDotsToBuckets = function() return false end
            ns.ListAdd, ns.ListRemove = function() return false end, function() return false end
            ns.DOT_SLOTS = 0
        end

        curSpec = CurrentSpecID()
        ns.MigrateDotsToBuckets(saved, curSpec)

        local savedPT = saved and saved.powerTicks
        local savedHT = saved and saved.healthTicks
        -- ⚠ `dots` / `cds` **不再**需要从 CopyDefaults 里拎出来:它们的默认值现在是**空表**,
        --    CopyDefaults 递归进去一个键都加不了 ⇒ 玩家的桶原样留着。
        --    (那个"变长数组要单独拎"的规矩只对**有非空默认值**的键成立,两个 ticks 就是。)
        DodoCombatHUDDB = CopyDefaults(DEFAULTS, saved or {})
        DB = DodoCombatHUDDB
        if type(savedPT) == "table" and #savedPT > 0 then DB.powerTicks  = savedPT end
        if type(savedHT) == "table" and #savedHT > 0 then DB.healthTicks = savedHT end

        BuildHUD()
        -- 先探测再布局:ApplyLayout 要知道画几格、用什么颜色,而那全来自探测结果。
        -- 顺序反了的话首次登录会画成「没有次要资源 + 灰色主条」,而下一次事件才自愈 ——
        -- 那种「重登一次就好了」最难查。
        RefreshResources()
        ApplyLayout()
        RefreshAvailability()
        -- ESC 面板。注册失败不许影响 HUD 本身 ⇒ Options.lua 里整段 pcall,
        -- 这里只判它在不在(TOC 少一行、或那个文件语法错,都表现成函数不存在)。
        if ns.RegisterOptions then ns.RegisterOptions() end
        f:SetScript("OnUpdate", OnUpdate)
        Print("已加载。/dch 看命令,/dch res 看当前探测到哪些资源")
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- ⚠ 只刷 DoT 那排。另外三排绑的是 `player`,换目标跟它们没关系 ——
        --   以后别照抄这一句给它们加上。
        -- 🔴 **顺序要紧,而且两步都要**(0.11.1):先重推 filter、再刷数据。
        --    filter 的准入取决于**当前目标是敌是友**(见 DotUnitEligible),
        --    所以「换目标」正是它唯一可能从不合格变合格的时刻;只调 RefreshDots
        --    的话,登录时没推下去的那次就再也补不上了。
        if DB then ApplyDotFilters(); RefreshDots() end
    elseif event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
        -- 德鲁伊变形 / 换专精会走这里,而那时**资源类型整个换了**(能量↔法力↔星能)
        -- ⇒ 必须重探测 + 重布局,不能只刷显隐。少这一步的症状是
        -- 「变了形,条还是上一形态的颜色和格数」—— 看着像没刷新,其实是没重探。
        if unit == "player" and DB then
            RefreshResources(); ApplyLayout(); RefreshAvailability()
        end
    elseif DB then
        -- PLAYER_SPECIALIZATION_CHANGED / PLAYER_ENTERING_WORLD 走这儿。
        -- 🔴 `RefreshSpec` 必须跟这三个一起跑,**别单开一个分支** ——
        --    单开的话它会把 PLAYER_SPECIALIZATION_CHANGED 从这条 catch-all 里抢走,
        --    于是换专精不再重探资源,资源条停在**上一个专精**的颜色和格数上。
        --    (这次写的时候真就先写错成那样了。)
        RefreshSpec()
        RefreshResources(); ApplyLayout(); RefreshAvailability()
    end
end)
