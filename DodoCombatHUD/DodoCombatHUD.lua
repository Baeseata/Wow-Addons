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
    -- 🔴 **按资源分别关**(0.13.2)。上面那个 `secondaryOn` / `powerOn` 是全账号一份 ——
    --    在血 DK 上关掉符文,暗牧的连击点、骑士的圣能也一起没了,而那看起来像 bug。
    --    颜色早就是按资源存的(powerColors[名字]),显隐一直没跟上,这是那个缺口。
    -- 🔴 存的是**反面**(`resOff[名字] = true`,缺席 = 显示):默认值根本不进存档,
    --    也就无从变旧 —— 就是 0.12 那个「改默认值对已落盘的键无效」的通法。
    resOff          = {},
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
    -- ── 自身增益(资源条**下方**,左对齐往右排,流式)──────────────
    -- 0.12 改名:原来叫「大招存续」,而它装的其实是**自己身上的重要 buff**
    -- (骨盾这种常驻的也在里面)⇒ 跟右边那排「团队增益」(别人给的)正好成对。
    -- ⚠ DB 里的键仍是 cdsOn / cdWidth… **故意不改** —— 改了等于把你存的设置作废,
    --   而这只是个显示名。键名和显示名不一致这件事,写在这儿就够了。
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
    -- 「当资源看」那种叠层 buff(CD_STACK_STYLE)的层数字号,**按图标高的百分比**。
    -- 相对而不是绝对:改图标大小时字号自动跟上,不用两处一起调。
    -- 普通格的角标是 42%(StyleCount 里那个);居中要压得住图标,所以默认给到 92%。
    stackFontPct = 92,
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

-- ---------------------------------------------------------------- 角色私有存档
-- 0.12:**位置按角色存**,别的(颜色 / 尺寸 / 法术表 / 开关)仍按账号存。
-- 理由:同一账号不同职业的这一叠本来就不一样高(次要资源条根数不同、开不开),
-- 而颜色和图标大小是审美,换个号不该重设一遍。
-- 🔴 只搬 x/y 这两个键,不整体搬库 —— 整体搬等于**把你现有的设置全作废**,
--   而那是个不可逆的代价,换来的只是"存得更整齐"。
local CharDB
local function InitCharDB()
    DodoCombatHUDCharDB = DodoCombatHUDCharDB or {}
    CharDB = DodoCombatHUDCharDB
    -- 一次性继承:这个角色第一次加载新版时,从账号库那份把位置抄过来。
    -- 少了这一步,所有老角色升级当天会**一起跳回屏幕中央**,而没人会想到是存档层换了。
    if CharDB.x == nil then CharDB.x = (DB and DB.x) or DEFAULTS.x end
    if CharDB.y == nil then CharDB.y = (DB and DB.y) or DEFAULTS.y end
end

local function Print(msg)
    print("|cffff66cc" .. ADDON .. "|r " .. msg)
end

-- ---------------------------------------------------------------- 构件

local root, testMode = nil, false
-- 拖拽整个 HUD 的那对函数。**声明在这儿、赋值在 BuildHUD 里** ——
-- 占位框(配置模式)和沸点那一格都要用同一对,而它们在别的地方建。
-- ⚠ 声明写晚了那两句赋值就成了全局变量,而 `luac -p` 挑不出任何毛病
--    (0.9.0 的 segHost 就是这么崩的,tools/test_scope.lua 守着这条)。
local HudDragStart, HudDragStop = nil, nil
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
local lustBox, raidBox = nil, nil               -- { container=, buttons={}, ids={} }
-- 自身增益排:0.13 起是**固定格位**,一格一个独立容器(跟 dots 完全同形)。
-- 🔴 为什么不是"一个容器 + 一个 group":那样图标的左右顺序归**暴雪**按 Expiration 算
--    (扒过 AuraUtil.ExpirationAuraCompare 的原文),我们连递都递不进去 ——
--    而玩家要能在面板里排顺序。**你没法给一个顺序会自己变的东西排序。**
-- 🔴 也不是"一个容器 + N 个 group 用 layoutIndex 排":那押在「空组会不会塌陷」上,
--    而那个行为至今没定案;DoT 那排当初做成一格一容器正是为了躲它。
--    多几个框体换"结构上保证",便宜(DodoNameplate 建 120 个)。
local cdRow = { slots = {} }                    -- slots[i] = { container=, spellID=, buttons={} }
local cdOverflowSig = nil                       -- 上次报过的"配得比格子多"签名,防重复吵
-- 配置模式(0.13.2):点开显示全部**该显示**的框体,好拖;再点一下恢复。
-- 声明放这儿(跟别的模块状态一起)是**故意的**:占位框的显隐要在 LayoutDots 里定,
-- 而那个函数在文件中部 —— 声明写晚了那句赋值就成了全局变量,
-- 而 `luac -p` 挑不出任何毛病(0.9.0 的 segHost 就是这么崩的,tools/test_scope.lua 守着)。
local configMode = false
local preConfigLocked = nil
-- 0.11:右侧那两排合成**一个**容器(两个 group)。rightBox 持有真容器;
-- lustBox / raidBox 退化成指向它的两个"视图"(带各自的 group 名),下游不用全改。
local rightBox = nil
-- 大招那排左侧要留出多少像素给别人钉一个固定格(沸点)。
-- 由 Boiling.lua 通过 ns.SetCdRowPad 推进来 —— 只有它知道那个格现在在不在。
local cdRowPad = 0
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

-- **HUD 用这个**(隐藏的不占格);`ListFor` 是**配置**表,给面板和 /dch 用。
-- 🔴 两个函数而不是给 ListFor 加个开关:面板必须看得见隐藏的那几行(不然勾不回来),
--    HUD 必须只看见可见的。一个函数两种语义,调用处迟早传错那个参数,
--    而症状是"隐藏了还在显示"或者"面板里那行没了"—— 两个都不像同一个 bug。
local function VisibleFor(kind)
    local list = ns.VisibleAuraList(DB, kind, curSpec)
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
-- 层数用的字体模板。**必须带字体建出来** —— 见下面 SetApplicationCount 那段。
local COUNT_TEMPLATE = _G.NumberFontNormalSmall and "NumberFontNormalSmall" or nil

local function StyleCount(fs, iconH)
    if not fs then return end
    pcall(function()
        local path = fs:GetFont()
        fs:SetFont(path or STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF",
            math.max(8, math.floor((tonumber(iconH) or 32) * 0.42)), "OUTLINE")
    end)
end

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

-- 「当资源看」的叠层 buff 样式(0.13.5,倒计时开关 0.13.6 修):**层数居中放大 + 不画倒计时**。
-- 名单在 `ns.CD_STACK_STYLE`(AuraSets.lua),判据是 **spellID 不是格位** —— 理由见那张表。
--
-- 🔴 为什么倒计时是「照常递给暴雪、只关它的显示开关」而不是「压根不递」:
--    `SetDurationCooldown` 交出去就收不回来,而**同一颗 button 会被换专精后的下一个法术复用**
--    ⇒ 不递的话「增强萨切成元素萨,第一格从此没倒计时」,而那读起来完全像 bug、
--    想不到是上一个专精留下的。开关是**可逆**的,跟着 spellID 走。
-- 🔴 **0.13.6 修的那个:别跟暴雪的显隐对抗,用它自己的开关。**
--    第一版写的是 `SetScript("OnShow", cd.Hide)` + `SetAlpha(0)` + `Hide()` 三道 ——
--    真机症状是**秒数照样画在正中间、把层数盖了个严实**。两个原因叠在一起:
--    ① 三条包在**同一个 pcall** 里,第一条 `SetScript`(暴雪的受保护 button)一抛,
--       后两条根本没执行 —— 「一个 catch 包多条语句」的 Lua 版,零报错;
--    ② 就算它没抛,方向也是错的:关倒计时**有官方开关**,
--       `DodoGrid/Auras.lua:263` / `DodoNameplate/Auras.lua:62` 早就在同一种
--       CustomAuraButton 上用对了。**下次先 grep 自己的在产插件,别先想怎么对抗。**
-- ⚠ `button:IsShown()` 是 secret(canon 坑 2)⇒ 这套东西**结构上没法自动验**,
--    只能拿眼睛看 —— 上面那个 bug 就是这么漏到真机的:测试全绿,而它一个字都测不到。
local function ApplyStackStyle(b, on, iconH)
    if not b then return end
    on = on and true or false
    local pct = tonumber(DB and DB.stackFontPct) or 92
    -- 🔴 **故意没有幂等检查,别再加回来。**(0.13.7 加过,当天就咬了。)
    --    `StyleCount` 每次 restyle 都**无条件**把层数字号设回角标档(42%),而它排在本函数之前。
    --    只要这里因为「参数没变」提前 return,字号就停在 42% ⇒ **比不做这个功能时还小**。
    --    症状极毒:button 刚建那次是对的(走 MakeAuraInit),之后**任何一次 ApplyLayout**
    --    (改设置 / 换目标 / 换专精)都会把它打回去 ⇒ 「时好时坏」,而两个函数单独看都对。
    -- 🔑 通法:**两个函数写同一个属性,而其中一个是无条件的 ⇒ 另一个就不能有提前 return。**
    --    幂等在这儿只省几次 SetFont(ApplyLayout 是低频的),换来一个会自己复发的 bug,不值。
    --    你自己的 DodoGrid / DodoNameplate 也是每次无条件设,跟它们保持一致。
    local fs = b.dchCount
    if fs then
        -- 一条一个 pcall,理由同下面 cd 那段:包在一起的话第一条抛掉后面全不执行,而且零报错。
        pcall(function() fs:ClearAllPoints() end)
        if on then
            pcall(function() fs:SetPoint("CENTER", b, "CENTER", 0, 0) end)
            pcall(function() fs:SetJustifyH("CENTER") end)
            -- 居中要比角标大得多才压得住图标(角标是 42%)。可调:`/dch stackfont`。
            pcall(function()
                local path = fs:GetFont()
                fs:SetFont(path or STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF",
                    math.max(10, math.floor((tonumber(iconH) or 32) * pct / 100)), "OUTLINE")
            end)
        else
            pcall(function() fs:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1) end)
            pcall(function() fs:SetJustifyH("RIGHT") end)
            -- 🔴 **0.13.11:字号也必须在这儿归位,别指望 `StyleCount` 兜底。**
            --    上面那段说「靠 StyleCount 无条件复位」—— 那只在 `ApplyLayout` 那条路上成立。
            --    `ApplyCdFilters` 那条路**根本不经过 `StyleCount`**,而
            --    `/dch cd add|del|<格号> <id>` 三条命令只调 `ApplyAuraFilters()`、
            --    **没有**跟着 `ApplyLayout()`(hide/show/reset 三条是成对的,这三条漏了)
            --    ⇒ 手动把某格从漩涡武器换成别的法术后,层数是个**缩在右下角的超大数字**,
            --    要等下一次换专精 / 改滑条 / reload 才纠正。又一次「reload 一下就好了」。
            -- 🔑 这是本节那条通法的**第三个实例**,所以这次用结构修而不是再加一个调用点:
            --    **让这个函数在两个方向上都定义那个属性** ⇒ 谁先谁后都不影响结果。
            --    复用 `StyleCount` 而不是把 0.42 抄第二遍 —— 同一个不变式两份手写实现迟早漂。
            StyleCount(fs, iconH)
        end
    end
    local cd = b.dchCD
    if cd then
        -- 🔴 **一条一个 pcall。** 0.13.5 第一版把三条包在同一个 pcall 里,
        --    第一条(`SetScript`,在暴雪的受保护 button 上)一抛,**后两条根本没执行**
        --    ⇒ 秒数照常画在正中间,把层数盖了个严实。
        --    「一个 catch 包多条语句」在 Lua 里就长这样,而它零报错。
        -- 🔑 而且对抗本身就是错的:关倒计时**有官方开关**,`DodoGrid/Auras.lua:263` 和
        --    `DodoNameplate/Auras.lua:62` 早就在同一种 CustomAuraButton 上用对了
        --    (`SetHideCountdownNumbers(a.showTimer == false)`)。canon:搬它,别重造它。
        pcall(function() cd:SetHideCountdownNumbers(on) end)  -- 秒数(就是盖住层数那个)
        pcall(function() cd:SetDrawSwipe(not on) end)         -- 转圈那片暗色
        pcall(function() cd:SetDrawEdge(not on) end)          -- 转圈前沿那道亮边
        -- ⚠ `not on` 不是 `false`:普通格从没设过 bling,默认就是开 ⇒ 写死 false
        --    会顺手改掉**其他所有职业**那排的观感,而那不是这次要动的东西。
        pcall(function() cd:SetDrawBling(not on) end)         -- 转完那下闪光
    end
end

-- bucket 收本格创建过的按钮。**必须收** —— layout 的 elementWidth/Height 只管「怎么排」,
-- 按钮自己的大小要自己 SetSize(DodoNameplate 也是分开设的)。不收的话 /dch dsize 改完
-- 排列间距变了、图标没变 —— 那种半生效比完全不生效更难看出是 bug。
-- keys = { w = "dotWidth", h = "dotHeight", font = "dotFontSize" } —— 三排各传各的。
-- slot(可选)= 这一格的 slot 表。**只有自身增益排传** —— 传了才认得出「这格现在装的是谁」,
--   因为 button 是暴雪按需建的,建的时候 filter 早推好了 ⇒ slot.spellID 已经是对的。
local function MakeAuraInit(bucket, keys, slot)
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
    -- 层数:右下角。骨盾 / 鲜血女王的精华 这种叠层 buff 全靠它。
    -- 🔴 顺序是**硬要求**:`SetApplicationCount` 会在**同一次调用里同步**写进这个 FontString
    --    (CustomAuraButton → UpdateAuraDisplay → ApplyApplicationCount → SetText),
    --    所以交出去之前它必须**已经带着字体**。裸着递过去、事后再设字体 =
    --    "FontString:SetText(): Font not set",而它会把 AddAuraGroup 整个掀掉
    --    ⇒ 症状是「这一排整个建不出来」,完全看不出是字体的事。
    --    配方抄 `DodoNameplate/Auras.lua:88`(那儿是真机跑通的),register last。
    -- ⚠ 层数是 secret,我们**读不到也比不了** ⇒ 「1 层就别画」这种过滤自己做不了,
    --    只能是暴雪那边什么行为就什么行为。
    local count = button:CreateFontString(nil, "OVERLAY", COUNT_TEMPLATE)
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    count:SetJustifyH("RIGHT")
    button.dchCount = count
    StyleCount(count, DB[keys.h])
    -- 最后一道保险:字体真没设上就**别交**给它 —— 宁可这一格没层数,
    -- 也不能把整排掀掉。(StyleCount 是 pcall 的,失败时静默,所以这里要自己确认。)
    if select(1, count:GetFont()) then
        button:SetApplicationCount(count)
    end
    button.dchCD = cd          -- 留个引用:改大小/字号时要回头找它
    button.dchKeys = keys      -- 同上:resize 时要知道这颗按钮归哪一排管
    button:SetSize(DB[keys.w], DB[keys.h])
    StyleCountdown(cd, keys.font)
    -- 叠层样式:**必须在 StyleCountdown 之后** —— 那个会把倒计时字体重设一遍,
    -- 顺序反了的话它会把我们刚藏起来的东西又碰一遍(现在不会,但别留这个坑)。
    if slot then
        ApplyStackStyle(button, ns.CD_STACK_STYLE and slot.spellID
            and ns.CD_STACK_STYLE[slot.spellID], DB[keys.h])
    end
    bucket[#bucket + 1] = button
    end
end

-- 🔴 `parent` 跟 `SetPoint` 的目标**故意分开**:parent 决定"跟谁一起消失",
--   SetPoint 只决定"在哪儿"。自身增益和团队增益都 parent 到 `root`,只**锚**别的框体 ——
--   认被锚的那个当 parent 的话,它一 Hide 这排就跟着全没,
--   而症状是「只有正在施法时才看得见」,完全像 bug、想不到是 parent。
--   DoT 那排是另一回事:它**本来就该**跟血条一起消失,所以它 parent 到 health.frame。
--
-- 0.13 起四排的形状是:DoT / 自身增益 = **一格一个独立容器**(顺序由我们定);
-- 嗜血 + 团队增益 = 一个共享容器两个 group(见 MakeRightBox)。
-- 原来那个通用的 `MakeAuraBox`(一个容器一个 group)最后一个调用方是自身增益排,
-- 它改成逐格之后就没人用了 ⇒ **已删**。别照着这段注释把它加回来:
-- 一个零调用方的构造函数会让下一个人以为"还有第三种形状可选"。

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
--      真原因一直零信号。自身增益那排传的 `(right, down)` 是对的,不受影响。
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

-- ── 配置模式的占位框(0.13.2)────────────────────────────────────
--
-- 🔴 aura 那几排的图标是**暴雪容器**画的,我们没法给它塞假光环 ⇒ 配置模式里
--    那几排只能画一个跟真格子**同位置同大小**的空框。对"摆位置"来说那就够了,
--    但要写明白:框里是空的**不代表**那一格有问题。
--
-- ⚠ parent 给容器的 parent(不是容器本身):「我们的框体锚到光环容器」是被禁的
--   (UntrustedLayoutScriptExecution),而且它在 pcall 里抛,症状会是"占位框整个不见了"。
local function MakeSlotMark(parent, label)
    local f = CreateFrame("Frame", nil, parent)
    f:SetFrameStrata("HIGH")
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0.15, 0.55, 1, 0.22)
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1 },
                         { "TOPLEFT", "BOTTOMLEFT", 1, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 0 } }) do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0.4, 0.8, 1, 0.9)
        t:SetPoint(e[1]); t:SetPoint(e[2])
        if e[3] > 0 then t:SetWidth(1) else t:SetHeight(1) end
    end
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER")
    fs:SetText(label)

    -- 🔴 占位框本身就是拖拽把手 —— 配置模式下 aura 那几排占了屏幕上不小一块,
    --    而那块地方原来是**抓不住的**(条才能抓)。挂的是模块层那对 Hud* 函数,
    --    不是另写一份"也拖 root"的代码。
    -- ⚠ EnableMouse 归 LayoutDots 跟显隐一起管:配置模式外这些框是隐藏的,
    --    但**隐藏的框体照样能吃鼠标** —— 不关的话它会把底下的东西挡住,
    --    而症状是"这块地方点不动了",完全想不到是几个看不见的框。
    f:EnableMouse(false)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() if HudDragStart then HudDragStart() end end)
    f:SetScript("OnDragStop",  function() if HudDragStop  then HudDragStop()  end end)
    -- 悬停高亮。⚠ 它**救不了发现性**(光标已经在上面才说话)——
    --   "占位框能直接拖"这句得写在开配置模式时那条消息里,canon 那条讲的就是这个。
    f:SetScript("OnEnter", function(self) bg:SetColorTexture(0.25, 0.75, 1, 0.4) end)
    f:SetScript("OnLeave", function(self) bg:SetColorTexture(0.15, 0.55, 1, 0.22) end)

    f:Hide()
    return f
end

-- 显隐 + 吃不吃鼠标,**一起翻**。分开写的话早晚漏一个,而漏掉 EnableMouse 的症状是
-- 「HUD 附近有一块地方点不动」—— 几个看不见的框在挡着,想不到是它们。
-- 🔴 锁上了就别吃鼠标:锁定的语义是"别让我手滑挪了它",占位框不能是那条规矩的例外。
local function ShowMark(mark, on)
    if not mark then return end
    mark:SetShown(on and true or false)
    mark:EnableMouse((on and not (DB and DB.locked)) and true or false)
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
        dots.slots[i] = { container = c, spellID = nil, buttons = bucket,
                          mark = MakeSlotMark(health.frame, tostring(i)) }
    end

    -- ── 另外三个容器 ────────────────────────────────────────────
    -- filter 里**故意不带 `PLAYER`**:嗜血和能量灌注常常是**别人**放的,
    -- 带上 PLAYER 就永远筛不到,而症状是"那格永远空着"—— 跟 ID 填错分不开。
    -- 我们看的是"挂在 player 身上的增益",来源是谁不重要。
    FLOW_DOWN = ResolveFlowDown()
    local right = AnchorUtil and AnchorUtil.FlowDirection and AnchorUtil.FlowDirection.Right
    local down = FLOW_DOWN
    -- ⚠ 三个各接各的错误。只留一个 `err` 的话,自身增益成功而 lust 失败时会打出 `nil` ——
    --   而"给错理由比不给更坏":它会引着人去查一个根本不是根因的东西。
    local e1, e2, e3
    if right and down then
        -- 自身增益:资源条下方,**一格一个独立容器**(跟上面 DoT 那排逐字同形)。
        -- 按 ns.CD_SLOTS 预建固定数量,不按列表长度建 —— 格数随专精变,而**换专精不许重建
        -- 框体**(战斗中建受保护框体大概率被拒,症状是"换了专精那排就没了")。
        -- 用不上的格子 SetEnabled(false) 收起来,换专精只改 filter。
        --
        -- ⚠ 这排**不需要** DoT 那道准入闸(DotUnitEligible)。暴雪的
        --   CanApplyIdentityCandidateFilters 只禁两格:友方身上的 debuff、敌方身上的 buff;
        --   我们这排是「**友方(自己)身上的 buff**」= 永远在准许区。
        for i = 1, (ns.CD_SLOTS or 8) do
            local bucket = {}
            -- 🔴 slot 表**先建**,好让 initializeFrame 的闭包捕得住它 ——
            --    暴雪按需建 button 时要回头问「这格现在装的是谁」(叠层样式按 spellID 判)。
            --    先 pcall 再建 slot 的话闭包里那个 upvalue 恒为 nil,而症状是
            --    「样式永远不生效」,跟名单填错分不开。
            local slot = { container = nil, spellID = nil, buttons = bucket, mark = nil }
            local okc, cc = pcall(function()
                local c = CreateFrame("AuraContainer", "DodoCombatHUDCd" .. i,
                    root, "CustomAuraContainerTemplate")
                c:SetFlowLayoutAnchorPoint("TOPLEFT")
                c:SetFlowLayoutGrowthDirection(right, down)
                c:SetFlowLayoutMaximumLineSize(math.huge)
                c:SetUnit("player")
                -- filter 里**故意不带 PLAYER**:自身增益里有些是别人给的(外部保命),
                -- 带上就永远筛不到,而症状是"那格永远空着"—— 跟 ID 填错分不开。
                c:AddAuraGroup("g", "HELPFUL", {
                    maxFrameCount = 6,                 -- 6 是探针实测跑通过的值(理由同 DoT 那排)
                    sortMethod = AuraContainerSortMethod.Expiration,
                    sortDirection = AuraContainerSortDirection.Normal,
                    candidateFilters = { includeSpellIDs = {} },
                    initializeFrame = MakeAuraInit(bucket, CD_KEYS, slot),
                    layout = { elementSpacing = 0, elementWidth = DB.cdWidth,
                               elementHeight = DB.cdHeight, layoutIndex = 1 },
                })
                return c
            end)
            if not okc then e1 = cc break end
            slot.container = cc
            slot.mark = MakeSlotMark(root, tostring(i))
            cdRow.slots[i] = slot
        end
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
    if not (cdRow.slots[1] and lustBox and raidBox) then
        -- 只吵一次、只停这三排:DoT 那排已经建好了,不许被它们带走
        Print("|cffff3333右侧/下方那三排没全建起来|r(DoT 和三根条照常)")
        Print("  自身增益:" .. (cdRow.slots[1] and ("OK(" .. #cdRow.slots .. " 格)") or tostring(e1)))
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

    -- 🔴 赋给**模块层**那两个 local(上面声明过),不是新建两个局部函数 ——
    --    配置模式的占位框和沸点那一格都要挂同一对。各写一份的话,
    --    "从条上拖"和"从占位框上拖"迟早会在存位置这件事上分叉。
    HudDragStart = function() if not DB.locked then root:StartMoving() end end
    HudDragStop = function()
        root:StopMovingOrSizing()
        local _, _, _, x, y = root:GetPoint()
        CharDB.x, CharDB.y = math.floor(x + 0.5), math.floor(y + 0.5)
    end
    local startDrag, stopDrag = HudDragStart, HudDragStop
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
        -- 占位框跟容器**同一次算出来**,不另写一份坐标 —— 两份手写的几何必然会漂,
        -- 而漂了以后"配置模式里框的位置跟真图标对不上"是最难查的那种。
        if slot.mark then
            slot.mark:SetSize(w, h)
            slot.mark:ClearAllPoints()
            slot.mark:SetPoint("BOTTOMLEFT", health.frame, "TOPLEFT", (i - 1) * (w + sp), DB.dotYOffset)
            -- 显隐也在这儿定,不另开一个函数:位置和"该不该显示"分两处算,
            -- 早晚会漂成"框在这儿、图标在那儿"。判据取自跟 HUD 同一个 VisibleFor。
            ShowMark(slot.mark, configMode and DB.dotsOn ~= false and DB.healthOn ~= false
                and i <= #VisibleFor("dots"))
        end
        pcall(function()
            c:SetAuraGroupLayout("g", { elementSpacing = 0, elementWidth = w,
                                        elementHeight = h, layoutIndex = 1 })
        end)
        -- 已经建出来的按钮要单独 resize(见 MakeDotInit 上面那段)。战斗中碰按钮可能被拒,
        -- 所以逐个 pcall —— 改大小这种事等脱战再点一下 /dch dsize 就好,不值得为它加状态机。
        for _, b in ipairs(slot.buttons) do
            pcall(function() b:SetSize(w, h) end)
            StyleCountdown(b.dchCD, "dotFontSize")
            StyleCount(b.dchCount, h)
        end
    end

    -- ── 另外三排的几何 ──────────────────────────────────────────
    -- ⚠ 显隐**不在这儿**管,统一归 ApplyAuraFilters —— 它同时知道"开关"和"这排有没有 ID",
    --   两处各判一次就是 canon 说的静默分歧发生器。这里只管"多大、在哪儿"。

    -- 自身增益:0.12 起锚**资源条底**(次要资源;它关掉时回落 root),不再锚施法条 ——
    -- 施法条已经挪到最下了。左边 cdRowPad 像素留给沸点那个固定格(Boiling.lua 推进来的),
    -- 它没启用时 pad = 0,别的专精一个像素都不受影响。
    local cdAnchor = segHost:IsShown() and segHost or root
    do
        local cw, ch, csp = DB.cdWidth, DB.cdHeight, DB.cdSpacing
        for i, slot in ipairs(cdRow.slots) do
            local c = slot.container
            c:SetSize(cw, ch)
            c:ClearAllPoints()
            -- ⚠ 横向铺开 ⇒ 步距只跟**宽**有关(照抄成 ch 的话"压扁图标"会连横向间距一起改)。
            -- cdRowPad 是沸点那个固定格占掉的左侧留白,它没启用时是 0。
            c:SetPoint("TOPLEFT", cdAnchor, "BOTTOMLEFT",
                cdRowPad + (i - 1) * (cw + csp), -(DB.cdYOffset or 4))
            if slot.mark then
                slot.mark:SetSize(cw, ch)
                slot.mark:ClearAllPoints()
                slot.mark:SetPoint("TOPLEFT", cdAnchor, "BOTTOMLEFT",
                    cdRowPad + (i - 1) * (cw + csp), -(DB.cdYOffset or 4))
                ShowMark(slot.mark, configMode and DB.cdsOn ~= false and i <= #VisibleFor("cds"))
            end
            pcall(function()
                c:SetAuraGroupLayout("g", { elementSpacing = 0, elementWidth = cw,
                                            elementHeight = ch, layoutIndex = 1 })
            end)
            -- 这一格现在装的是不是「当资源看」的叠层 buff。**每次 ApplyLayout 都重判** ——
            -- button 会被换专精后的下一个法术复用,只在建的时候判一次的话样式会跟着上一个专精走。
            local stack = ns.CD_STACK_STYLE and slot.spellID and ns.CD_STACK_STYLE[slot.spellID]
            for _, b in ipairs(slot.buttons) do
                pcall(function() b:SetSize(cw, ch) end)
                StyleCountdown(b.dchCD, "cdFontSize")
                StyleCount(b.dchCount, ch)
                -- ⚠ 必须排在上面两个之后:StyleCount 会把字号改回角标那档(42%),
                --   而居中那档是 `DB.stackFontPct`(默认 92%)—— 反过来的话
                --   「层数居中了但还是小字」,看起来像位置对了、字号忘了改,
                --   想不到是两个函数在打架。(0.13.11 前这里写的是「0.62」,是个从没存在过的旧值。)
                ApplyStackStyle(b, stack, ch)
            end
        end
    end

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
        -- 右侧是**一个** 2xN 网格容器 ⇒ 占位框也只要一个,罩住整片。
        -- (逐格罩没意义:那几格的位置归暴雪的 flow layout 算,我们本来就不控制。)
        if not rightBox.mark then rightBox.mark = MakeSlotMark(root, "团队增益") end
        rightBox.mark:SetSize(cols * rw + (cols - 1) * rsp, 2 * rh + rsp)
        rightBox.mark:ClearAllPoints()
        rightBox.mark:SetPoint("TOPLEFT", health.frame, "TOPRIGHT", DB.raidXOffset or 4, 0)
        ShowMark(rightBox.mark, configMode and DB.raidOn ~= false and DB.healthOn ~= false)
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
            StyleCount(btn.dchCount, rh)
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
    -- 自身增益那排也刷。换目标时它其实不需要(它绑的是 player),但**换专精 / 改列表**
    -- 之后需要 —— 而那两条路都汇进这里。多刷 8 个容器的代价远小于
    -- "改完设置得等下一次光环事件才看得见"那种查不出来的迟滞。
    for _, slot in ipairs(cdRow.slots) do
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

-- 一个判据「是不是**明文的真**」。secret / 问不出来 ⇒ 一律 false。
-- 🔴 `issecretvalue` 必须**排在取值之前**:secret 保留原生类型,`type(v)=="boolean"` 挡不住它,
--    而报错是在**比较**那一刻抛的(canon:12.x secret 的第一课)。
-- 🔴 末尾是 **truthy 判断,不是 `v == true`**。第一版写的 `== true` 差点发出去 ——
--    暴雪的 Unit* 系有一大批**返回 `1`/`nil` 而不是 `true`/`false`** 的老 API,
--    真撞上的话这个判据恒为假 ⇒ **DoT 那排从此一次都不显示**。而它 fail-closed、不报错、
--    看起来完全像"目标一直不合格" —— 比原来那个 bug 更难查。
--    secret 已经在上面挡掉了,所以这儿放宽到 truthy 是安全的。
--    (是 tools/test_dotgate.lua 那条 A/B 空转、去查为什么空转时逼出来的。)
local function PlainTruthy(v)
    if type(issecretvalue) == "function" then
        local okS, isS = pcall(issecretvalue, v)
        if not okS or isS then return false end   -- 是 secret,或连问都问不出来 ⇒ 按最严的算
    end
    return v ~= nil and v ~= false
end

-- 目标能不能承载「我上的 DoT」这个概念 —— **这是 filter 推不推得下去的前提,不是显示偏好**。
-- 暴雪的 `AuraContainerUtil.CanApplyIdentityCandidateFilters` 只禁两格:**友方身上的 debuff**
-- 和敌方身上的 buff。我们这排正是「HARMFUL 挂在 target 上」⇒ **目标是友方、或压根没目标时,
-- includeSpellIDs 落进被禁的那一格,被静默丢掉**(不抛错,pcall 看不见)⇒ 容器退回
-- 「没有 candidate filter」,而 nil 在暴雪那边是**全放行** ⇒ 那一格画的是「我在他身上的
-- 全部 debuff」,三格于是画同样的东西,且全程零报错。
--
-- 🔴 **判据用 `UnitCanAttack` 的正向式,不用 `not UnitCanAssist`**(0.11.2 改)。
--    第一版写的是「不可协助 ⇒ 合格」—— 那是**负向谓词**,凡是"不可协助"的东西(读不出来、
--    nil、secret、跨阵营、载具、相位不同…)统统被反授成"合格"。canon 那条
--    「PERMISSIVE policy 用负向谓词 = 反授其它全部」讲的就是这个形状:**授权用等号,别用不等号。**
--    实撞(2026-08-19):团里一个友方目标上 `UnitCanAssist` 返回 **false** ——
--    于是第一版判成"合格"、照推不误,而 filter 该被暴雪丢的照样丢 ⇒ **修了个寂寞**。
--    `UnitCanAttack` 是正向的:它为真才合格,读不到就不合格,天然 fail-closed。
--
-- ⚠ **两个判据都要在真机上量过才算数**(`/dch probe` 现在把 4 个来源一起打出来)——
--    「城里对陌生人是明文」不替「副本里对团友」背书,那是两个环境。
local function DotUnitEligible()
    local okE, exists = pcall(UnitExists, "target")
    if not okE or not PlainTruthy(exists) then return false end
    local okA, canAttack = pcall(UnitCanAttack, "player", "target")
    if not okA then return false end
    return PlainTruthy(canAttack)
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
    local dotList = VisibleFor("dots")
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

-- ② 自身增益:固定格位(0.13)。跟 ApplyDotFilters 逐条对称,**只差一样** ——
--    没有那道准入闸。暴雪的 CanApplyIdentityCandidateFilters 只禁「友方身上的 debuff」
--    和「敌方身上的 buff」;我们这排是"自己身上的 buff",永远在准许区。
--    ⇒ 别照抄 DoT 那边的 eligible 判据过来,那会平白让这排在没目标时消失。
--
-- 🔴 `slot.spellID` 只在**推送成功之后**才记(跟 DoT / ApplyBoxFilter 同一个洞,修类不修例):
--    写在 pcall 外面的话,一次偶发失败会被固化成永久故障 ——「推过了」⇒ 从此不重试
--    ⇒ 容器停在建组时那份空 filter,而**空 candidateFilters 在暴雪那边是「全放行」**
--    ⇒ 那一格显示你身上**所有**增益,且全程零报错。
local function ApplyCdFilters()
    if not dots.built then return end
    local list = VisibleFor("cds")
    local on = DB.cdsOn ~= false
    -- 🔴 0.13 之前这排是**流式、无上限**的 ⇒ 老存档完全可能有超过 CD_SLOTS 个 ID,
    --    而多出来的那些现在**没有容器可用 = 静默消失**。canon:静默截断读起来跟
    --    "全都在" 一模一样,所以必须吵一句 —— 而且要说清是哪几个掉了。
    --    只在签名变化时吵(换专精 / 改列表),不刷屏。
    if #list > #cdRow.slots then
        local sig = tostring(curSpec) .. ":" .. #list
        if cdOverflowSig ~= sig then
            cdOverflowSig = sig
            Print(("|cffff8800自身增益配了 %d 个,但只有 %d 格|r —— 第 %d 个之后的**不会显示**。")
                :format(#list, #cdRow.slots, #cdRow.slots))
            Print("  /dch cd 看列表,del 或 hide 掉几个。")
        end
    end
    for i, slot in ipairs(cdRow.slots) do
        local sid = list[i]
        if not sid then
            slot.spellID = nil            -- 收起这格:没有推送动作,直接记
        elseif sid ~= slot.spellID then
            local ok, err = pcall(function()
                slot.container:SetAuraGroupCandidateFilters("g", DotFilters(sid))
            end)
            if ok then
                slot.spellID = sid
            else
                Print("|cffff3333自身增益第 " .. i .. " 格 filter 推送失败|r(下次刷新重试):"
                    .. tostring(err))
            end
        end
        -- 🔴 **叠层样式跟着 `spellID` 走,不等下一次 `ApplyLayout`。**
        --    样式的判据是 `slot.spellID`,而它是**这里**写的;`ApplyLayout` 里那次 restyle
        --    只是顺带重申。两者顺序在某些路径上是反的(换专精:`ApplyLayout` 先跑,
        --    读到的还是**上一个专精**的 spellID)⇒ 那次 restyle 会把按钮设成普通样式,
        --    而之后**没有任何东西**会再来纠正 ⇒ 秒数回到正中间、层数缩回右下角。
        -- ⚠ 症状特征是「**reload 一下就好了**」——因为 reload 重建了一切、把错状态冲掉。
        --    canon:「重启一下就好」要问清它买到什么时候。**买到下一次换专精。**
        -- 🔑 通法:**状态的应用要挂在「写这个状态的地方」,不是挂在「碰巧也会跑的地方」。**
        local stack = ns.CD_STACK_STYLE and slot.spellID and ns.CD_STACK_STYLE[slot.spellID]
        for _, b in ipairs(slot.buttons) do
            ApplyStackStyle(b, stack, DB.cdHeight)
        end
        pcall(function() slot.container:SetEnabled(on and sid ~= nil) end)
    end
end

local function ApplyAuraFilters()
    if not dots.built then return end

    ApplyDotFilters()

    -- ② 大招 ③ 嗜血 ④ 其余团队增益
    ApplyCdFilters()
    local lustList, raidList = VisibleFor("lust"), VisibleFor("raid")
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

-- 这一种资源被单独关掉了吗。⚠ 判据只声明这一处,主资源和次要资源共用 ——
-- 两处各判一次就是 canon 说的静默分歧发生器。
local function ResHidden(name)
    if not name then return false end
    local t = DB and DB.resOff
    return type(t) == "table" and t[name] == true
end

local function LayoutSegs()
    if not segHost then return end
    local show = (secondary ~= nil) and (DB.secondaryOn ~= false) and not segsDead
                 and not ResHidden(secondary.name)
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
    -- 🔴 判据必须跟 RefreshAvailability 那句**完全一致**(全局开关 + 按资源单独关),
    --   少一半的症状是「关掉符文以后中间空一条」—— 而那跟布局算错分不开。
    local powerShown = (DB.powerOn ~= false) and not ResHidden(POWER_NAME[mainPower])
    root:SetSize(DB.width, powerShown and DB.powerHeight or 1)
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", CharDB.x, CharDB.y)
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

    -- 0.12:施法条挪到**最下**,大招那排提到资源条正下方。
    -- 理由:施法条是整叠里唯一"框体一直在、内容时有时无"的东西 ——
    -- 夹在中间时它那条地平时是空的,却把下面所有东西往下推一整条。
    -- 🔴 位置**用算的**,不锚到自身增益那排的容器:「我们的框体锚到光环容器」是被禁的
    --    (Anchoring disallowed ... UntrustedLayoutScriptExecution),而它在 pcall 里抛,
    --    症状会是"施法条整个不见了",完全看不出是锚点的事。
    local castAnchor = segHost:IsShown() and segHost or root
    local cdReserve = (DB.cdsOn ~= false)
                      and ((DB.cdYOffset or 4) + DB.cdHeight + DB.gap) or 0
    cast.frame:ClearAllPoints()
    cast.frame:SetPoint("TOPLEFT", castAnchor, "BOTTOMLEFT", 0, -(DB.gap + cdReserve))
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

-- ── 配置模式(0.13.2)──────────────────────────────────────────
--
-- 「点开就显示全部**该显示**的框体,好拖;再点一下恢复」。
-- 它 = 演示模式(三根条填假数据强制显示)+ aura 每格一个占位框 + 自动解锁。
--
-- 🔴 「该显示」的判据**取自跟 HUD 同一个来源**(VisibleFor + 那几个开关),
--    不另写一份 —— 两份手写的判据必然会漂,而漂了以后
--    "配置模式里有框、退出去却没图标"跟"那一格坏了"分不开。
-- ⚠ 占位框里是**空的**,因为 aura 图标是暴雪容器画的、我们塞不进假光环。
--    空框 ≠ 那一格有问题,退出配置模式才看得到真东西。
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
    power.frame:SetShown((hasPower or testMode) and DB.powerOn ~= false
        and not ResHidden(POWER_NAME[mainPower]))
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
    Print("  /dch config                 配置模式:全部框体摆出来 + 自动解锁,再敲一次收工")
    Print("  /dch sres [main]            只隐藏/显示**这一种**资源(次要 / 加 main = 主资源)")
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
    Print("  ── 资源条下方:自身增益(**固定格位**,顺序由你定;施法条已挪到最下)──")
    Print("  /dch cds                    这排 开/关")
    Print("  /dch cd                     列出来 | cd 2 195181 改第 2 格 | cd add|del <id>")
    Print("  /dch cd hide|show <id>      不占格 / 放回来(配置和名次都留着)| cd reset 回内置")
    Print("  /dch cdw|cdh|cdfont|cdsp|cdy  宽 / 高 / 字号 / 间距 / 离施法条多远")
    Print("  /dch stackfont 92           叠层 buff(漩涡武器…)层数字号,**按图标高的百分比**")
    Print("  /dch stackdbg               叠层样式探针:每格的 spellID / 命中没命中 / 当前字号")
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
    Print("  /dch bp [秒|now|stop|expire] 血 DK 沸点探针(只读只打印)")
    Print("  /dch bp row [off|reset]     血 DK 自身 buff 排(骨盾/沸点…,可拖,存盘)")
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

-- `slotted` 现在传的是**这一排的 slash 命令名**("dot" / "cd"),不是布尔 ——
-- 0.13 起自身增益也是固定格位,两排都需要 `<格号> <spellID>` 那个形状,
-- 而提示语里得说出正确的命令名。传布尔的话提示只能写死一个,那就会教错人。
local SLOT_CAP = { dots = "DOT_SLOTS", cds = "CD_SLOTS" }

local function AuraCmd(kind, label, arg, slotted)
    -- 🔴 这里用**配置表**(ListFor),不是可见表 —— 面板和命令都必须看得见被隐藏的那几行,
    --    否则隐藏一个之后它从列表里消失了,你再也勾不回来。HUD 那侧才用 VisibleFor。
    local list = ListFor(kind)
    local _, custom = ns.AuraList(DB, kind, curSpec)
    local cap = SLOT_CAP[kind] and (ns[SLOT_CAP[kind]] or 4) or nil
    local sub, rest = string.match(arg or "", "^(%a*)%s*(%d*)$")
    local id = tonumber(rest)

    -- 🔴 按专精那两排要写存档就得有 specID,而 `t[nil] = v` 在 Lua 里是硬错误
    -- ⇒ 玩家会看到一串读不懂的红字堆栈,而根因("问不出专精")一个字都没提。
    --    早退 + 说人话;读列表不受影响(那条路会回落到"这个专精没有内置表"= 空)。
    if ns.PER_SPEC[kind] and curSpec == nil and (arg or "") ~= "" then
        Print(label .. ":|cffff3333现在问不出当前专精|r,这一排改不了(先 /dch " ..
              tostring(slotted or "cd") .. " 无参看一眼)")
        return
    end

    if sub == "reset" then
        ns.ResetAuraList(DB, kind, curSpec)
        ApplyAuraFilters(); ApplyLayout()
        Print(label .. ":回内置表(" .. #ListFor(kind) .. " 个)")
        return
    elseif sub == "hide" and id then
        -- 隐藏 ≠ 删除:配置留着、名次留着,勾回来还在原处。
        ns.SetAuraHidden(DB, kind, curSpec, id, true)
        ApplyAuraFilters(); ApplyLayout()
        Print(label .. ":隐藏 " .. id .. "  " .. SpellLabel(id) .. "(`show " .. id .. "` 放回来)")
        return
    elseif sub == "show" and id then
        ns.SetAuraHidden(DB, kind, curSpec, id, false)
        ApplyAuraFilters(); ApplyLayout()
        Print(label .. ":显示 " .. id .. "  " .. SpellLabel(id))
        return
    elseif sub == "add" and id then
        -- 🔴 固定格位那两排有硬上限:超出的格子**没有容器**,而多填的 ID 会静默消失 ——
        --    "我明明加了却没出现"跟"ID 填错了"在屏幕上分不开。所以这里必须挡住并说清楚。
        -- ⚠ 挡的是**配置表**的长度,不是可见表 —— 可见 <= 配置恒成立,
        --    按可见表挡的话「隐藏两个 → 加两个 → 再取消隐藏」会当场溢出,
        --    而溢出的那两格是**静默消失**的。
        local dup = false
        for i = 1, #list do if list[i] == id then dup = true end end
        if not dup and cap and #list >= cap then
            Print(label .. ":|cffff3333已经 " .. #list .. " 个,满了|r(上限 " .. cap ..
                  " 格)—— 先 del 或 hide 掉一个")
            return
        end
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
            if n >= 1 and n <= (cap or 4) then
                list[n] = s
                ns.SetAuraList(DB, kind, curSpec, list)
                ApplyAuraFilters()
                Print(string.format("%s 第 %d 格 -> %d  %s", label, n, s, SpellLabel(s)))
            else
                Print(label .. ":只有 1-" .. (cap or 4) .. " 格")
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
    -- 序号 = **格号**(固定格位那两排),而且隐藏的那几行也要列出来 ——
    -- 不列的话玩家再也 show 不回来,而且"我配的那个哪去了"跟"ID 填错了"分不开。
    for i, sid in ipairs(list) do
        local hidden = ns.IsAuraHidden(DB, kind, curSpec, sid)
        Print(string.format("  %d.  %-8d %s%s", i, sid, SpellLabel(sid),
            hidden and "   |cff888888[已隐藏]|r" or ""))
    end
    if cap then
        local vis = #VisibleFor(kind)
        Print(("  占 %d / %d 格%s"):format(vis, cap,
            vis < #list and ("(另有 " .. (#list - vis) .. " 个隐藏着,不占格)") or ""))
    end
    if slotted then
        Print(("  改:/dch %s <格号> <spellID>   加/删:add|del <spellID>   回内置:/dch %s reset")
            :format(slotted, slotted))
        Print(("  显隐:/dch %s hide <spellID> | show <spellID>   ← 留着配置,只是不占格")
            :format(slotted))
    else
        Print("  改:add <spellID> / del <spellID> / hide <spellID> / show <spellID> / reset")
    end
end

-- ── 🔬 `/dch stackdbg` —— 叠层样式(CD_STACK_STYLE)到底有没有落到按钮上。
-- 留着的理由:这套东西**结构上没法自动验**(`button:IsShown()` 是 secret,画出来什么样
-- 测试一个字都够不着)⇒ 一旦「看着不对」,唯一的定性手段就是把判据链每一环的**当前值**打出来。
-- canon 那条:症状是「功能不生效而代码看着没问题」时,先打判据链,别读代码。
-- 只读明文字段(spellID / 字号 / 锚点),**一个 secret 都不碰**。
local function StackDebug()
    Print("---- 叠层样式探针 ----")
    Print("  stackFontPct = " .. tostring(DB and DB.stackFontPct) ..
          "   cdHeight = " .. tostring(DB and DB.cdHeight))
    local styled = 0
    for _ in pairs(ns.CD_STACK_STYLE or {}) do styled = styled + 1 end
    Print("  CD_STACK_STYLE 有 " .. styled .. " 条" ..
          (ns.CD_STACK_STYLE and ns.CD_STACK_STYLE[344179] and "(344179 在)" or
           "|cffff3333(344179 不在!)|r"))
    Print("  当前专精 curSpec = " .. tostring(curSpec))
    for i, slot in ipairs((cdRow and cdRow.slots) or {}) do
        local sid = slot.spellID
        if sid or #slot.buttons > 0 then
            local hit = sid and ns.CD_STACK_STYLE and ns.CD_STACK_STYLE[sid]
            Print(("  第%d格 id=%s %s  命中=%s  已建按钮=%d")
                :format(i, tostring(sid), sid and SpellLabel(sid) or "-",
                        hit and "|cff33ff33是|r" or "|cffff3333否|r", #slot.buttons))
            for j, b in ipairs(slot.buttons) do
                local okf, _, size = pcall(function() return b.dchCount:GetFont() end)
                local okp, pt = pcall(function() return b.dchCount:GetPoint() end)
                Print(("      按钮%d 层数字号=%s 锚=%s"):format(j,
                    okf and tostring(size) or "?", okp and tostring(pt) or "?"))
            end
        end
    end
    Print("  判读:命中=是 而字号≈cdHeight*pct/100、锚=CENTER ⇒ 样式生效了。")
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
    -- 🔴 **先报被测对象是谁。** 上一版没打印目标身份 ⇒ 一份读数拿回来之后,
    --    「那到底是哪个目标」只能靠回忆,而回忆和读数打架时谁也说服不了谁
    --    (canon:凡采样类探针,输出里必须报出被测对象的身份)。
    -- 🔴 **四个来源一起打,不靠单一判据。** 2026-08-19 实撞:团里友方目标上
    --    `UnitCanAssist` 返回 false —— 拿它单独反推敌友会得出一个干净的错结论。
    --    名字可能是 secret ⇒ 拼进字符串前必须先问,直接 tostring 会当场崩。
    local function show(fn, ...)
        local ok, v = pcall(fn, ...)
        if not ok then return "ERROR" end
        if type(issecretvalue) == "function" then
            local okS, isS = pcall(issecretvalue, v)
            if not okS then return "?" end
            if isS then return "SECRET" end
        end
        return tostring(v)
    end
    emit(("  target: 名字=%s  玩家=%s  在队伍=%s"):format(
        show(UnitName, "target"), show(UnitIsPlayer, "target"),
        show(UnitPlayerOrPetInParty, "target")))
    emit(("  敌友四个来源: CanAttack=%s  CanAssist=%s  IsFriend=%s  Reaction=%s"):format(
        show(UnitCanAttack, "player", "target"), show(UnitCanAssist, "player", "target"),
        show(UnitIsFriend, "player", "target"), show(UnitReaction, "player", "target")))
    emit(("  target 存在=%s  ⇒ DoT filter 准入 %s   (判据 = CanAttack 必须是明文 true)"):format(
        show(UnitExists, "target"),
        DotUnitEligible() and "|cff33ff33合格|r" or "|cffff3333不合格(友方/无目标/读不到)|r"))
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
    -- 自身增益:0.13 起跟 DoT 一样是固定格位 ⇒ 逐格报,不再当"一个容器一排"报。
    -- ⚠ 这排的"该盯"取的是**可见表**(隐藏的不占格),跟真正推下去的是同一个来源;
    --   拿配置表来报的话,隐藏一个之后 probe 会说"该盯 5 个"而实际推了 4 个,
    --   那条读数会把人引去查 filter,而根本没有 filter 的事。
    for i, slot in ipairs(cdRow.slots) do
        local want = VisibleFor("cds")[i]
        local how
        if not want then
            how = "跳过(这格没配 / 被隐藏)"
        else
            local ok, err = pcall(function()
                slot.container:SetAuraGroupCandidateFilters("g", DotFilters(want))
            end)
            how = ok and "|cff33ff33OK|r" or ("|cffff3333FAILED|r " .. tostring(err))
        end
        emit(("  cd%d: 该盯=%s  已推=%s  重推=%s"):format(
            i, tostring(want), tostring(slot.spellID), how))
    end
    for _, e in ipairs({ { "lust", lustBox }, { "raid", raidBox } }) do
        local name, b = e[1], e[2]
        if not b then
            emit("  " .. name .. ": |cffff3333容器不存在|r")
        else
            local list = VisibleFor(name)
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
    elseif cmd == "config" then
        -- 跟面板上那个按钮走**同一段代码**,不许各写一份(canon:同一不变式两份实现)。
        local on = ns.ToggleConfig()
        Print(on and "配置模式|cff33ff33开|r —— 全部该显示的框体都摆出来了,已解锁,拖吧。再敲一次收工。"
                  or "配置模式|cffff3333关|r —— 位置和锁定都还原了。")
        if on then
            Print("  |cff33ff33那些占位框本身就能拖|r —— 不用去够那三根条。")
            Print("  ⚠ aura 那几排画的是**空占位框**:图标是暴雪容器画的,塞不进假光环。")
            Print("    框里空着**不代表**那一格有问题,退出配置模式才看得到真东西。")
        end
    elseif cmd == "sres" then
        -- 按资源单独隐藏。全局那个 /dch secondary 是**全账号一份** ——
        -- 在血 DK 上关掉符文,暗牧的连击点也一起没了,而那看起来像 bug。
        local which = (arg == "main") and POWER_NAME[mainPower] or (secondary and secondary.name)
        if not which then
            Print("现在探测不到" .. ((arg == "main") and "主资源" or "次要资源") ..
                  "(/dch res 看一眼)。用法:/dch sres [main]")
            return
        end
        local now = not ns.IsResHidden(which)
        ns.SetResHidden(which, now)
        Print(("%s:%s(只影响这一种资源,别的角色不受牵连)"):format(
            which, now and "|cffff3333隐藏|r" or "|cff33ff33显示|r"))
    elseif cmd == "probe"   then ProbeAuraFilters()
    elseif cmd == "stackdbg" then StackDebug()
    elseif cmd == "bp"      then if ns.BoilingProbe then ns.BoilingProbe(arg) else Print("Boiling.lua 没加载") end
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
    elseif cmd == "dot"  then AuraCmd("dots", "目标 DoT",   arg, "dot")
    elseif cmd == "cd" or cmd == "self" then AuraCmd("cds", "自身增益", arg, "cd")
    elseif cmd == "lust" then AuraCmd("lust", "嗜血那一格", arg, false)
    elseif cmd == "buff" then AuraCmd("raid", "团队增益",   arg, false)
    elseif cmd == "cds"    then Toggle("cdsOn",  "大招那排")
    elseif cmd == "buffs"  then Toggle("raidOn", "右侧团队增益")
    elseif cmd == "cdw"    then SetNum("cdWidth",      arg, 8, 120)
    elseif cmd == "cdh"    then SetNum("cdHeight",     arg, 8, 120)
    elseif cmd == "cdfont" then SetNum("cdFontSize",   arg, 8, 60)
    -- 百分比而不是绝对字号:图标一改大小它自动跟上(跟 cdfont 那种绝对值是两种东西,别合并)
    elseif cmd == "stackfont" then SetNum("stackFontPct", arg, 30, 200)
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
        CharDB.x, CharDB.y = DEFAULTS.x, DEFAULTS.y     -- 位置是角色私有的
        DB.width, DB.gap = DEFAULTS.width, DEFAULTS.gap
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
ns.ApplyLayout         = function()        if DB and CharDB then ApplyLayout() end end
ns.RefreshAvailability = function()        if DB then RefreshAvailability() end end
ns.ApplyBlizzCastBar   = function(restore) if DB then ApplyBlizzCastBar(restore) end end
-- ── 0.13 面板要用的 ────────────────────────────────────────────
-- 改完法术表要走这条:光改 DB 不推 filter 的话,屏幕上什么都不会变,
-- 而那看起来像"面板没接上",是最费时间的一类误判。
ns.ApplyAuraFilters    = function()        if DB then ApplyAuraFilters(); RefreshDots() end end
-- 面板是**按当前专精**画的 ⇒ 它必须能问到专精。返回 nil = 问不出来,
-- 那时按专精那两页要显示一句人话,而不是画一张空列表(空列表跟"这专精没有"分不开)。
ns.CurrentSpec         = function()        return curSpec end
-- 「最后见过的那个引导」——`/dch chan` 和面板都靠它定跳数。
-- ⚠ 它**故意不在引导结束时清掉**:人手打字必然发生在引导结束之后,清了就永远用不上
--   (0.11 栽过这条,而且当时提示语还写着「刚才那个」—— 提示语和行为对不上)。
ns.LastChannel         = function()        return castCur.id, castCur.name end
ns.SpellLabel          = SpellLabel
-- 主资源 / 次要资源现在叫什么 —— 颜色是**按资源名**存的(DB.powerColors[名字]),
-- 面板得先知道"这根条现在画的是哪个资源"才知道往哪一格写。nil = 没探测到。
ns.MainResourceName    = function()        return POWER_NAME[mainPower] end
ns.SecondaryName       = function()        return secondary and secondary.name end
-- ⚠ 这儿曾经有 ns.SetLocked / ns.ToggleTest / ns.IsTestMode 三个导出。
--   0.13.2 面板把「演示模式」按钮换成「配置模式」、锁定改成直接绑 DB.locked 之后,
--   它们**一个调用方都没有了** ⇒ 删掉(canon:留一个零调用方的函数,
--   等于让下一个人以为还有这条路可走)。演示模式本身还在,入口是 `/dch test`。
--   `tools/test_options.lua` 有一条 guard 盯着"别再养出零调用方的导出"。
-- 配置模式:开 = 演示模式 + 占位框 + 解锁;关 = 全部还原。
-- 🔴 锁定状态要**记住进来之前是什么**再还原,不能一律锁回去 ——
--    本来就没锁着的人退出配置模式会突然被锁上,而他不知道是谁锁的。
ns.ToggleConfig        = function()
    if not DB then return false end
    configMode = not configMode
    testMode = configMode
    if configMode then
        preConfigLocked = DB.locked
        DB.locked = false
    elseif preConfigLocked ~= nil then
        DB.locked = preConfigLocked
        preConfigLocked = nil
    end
    ApplyLayout()
    RefreshAvailability()
    -- 沸点那一格归 Boiling.lua 自己,它有自己的暗底 ⇒ 递一声,别在这儿画第二个框。
    if ns.BoilingSetConfig then pcall(ns.BoilingSetConfig, configMode) end
    return configMode
end
ns.IsConfigMode        = function()        return configMode end
-- 把任意框体接成「拖它 = 拖整个 HUD」的把手。给 Boiling.lua 那一格用。
-- 🔴 导出的是**动作**不是那对函数本身:别的文件拿到函数就能绕过 DB.locked 自己调,
--    而"锁定"这条规矩只该有一处判(HudDragStart 里那句)。
ns.MakeDragHandle      = function(frame)
    if type(frame) ~= "table" or not frame.RegisterForDrag then return end
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() if HudDragStart then HudDragStart() end end)
    frame:SetScript("OnDragStop",  function() if HudDragStop  then HudDragStop()  end end)
end
-- 「这一种资源单独关掉了没有」+ 开关。判据只在 ResHidden 那一处声明,这里只是门面。
ns.IsResHidden         = function(name)    return ResHidden(name) end
ns.SetResHidden        = function(name, hidden)
    if not (DB and name) then return end
    DB.resOff = type(DB.resOff) == "table" and DB.resOff or {}
    -- 存反面:显示时**把键删掉**,不写 false —— 写 false 就是把默认值落盘了,
    -- 而那正是 0.12 那个「改默认值对已落盘的键无效」的坑。
    DB.resOff[name] = hidden and true or nil
    ApplyLayout()
    RefreshAvailability()
end
-- 「回默认位置和尺寸」= /dch reset 那一条,一个字都不多做 ——
-- 按钮和命令走同一段代码,不许各写一份(canon:同一不变式两份实现 = 静默分歧发生器)。
ns.ResetGeometry       = function()
    if not DB then return end
    CharDB.x, CharDB.y = DEFAULTS.x, DEFAULTS.y
    DB.width, DB.gap = DEFAULTS.width, DEFAULTS.gap
    DB.powerHeight, DB.healthHeight = DEFAULTS.powerHeight, DEFAULTS.healthHeight
    ApplyLayout()
end
ns.DEFAULTS            = DEFAULTS
-- 自身增益那排的锚点与几何,给 Boiling.lua 在它左边钉固定格用。
-- ⚠ 锚认到 **segHost 为止**,不认施法条 —— 施法条是**瞬态的**(只在施法时 Show),
--   拿它当锚会让下面的东西一施法就跳。
-- ⚠ 这儿曾经还有 ns.GetHudRoot / ns.GetHudBottom,零调用方,0.13.2 删了
--   (它俩想表达的"root 只是主资源那一格、真正的底是 segHost"已经写在这条里了)。
-- 返回:锚框体, y 偏移(相对该框体 BOTTOMLEFT)
ns.GetCdRowAnchor      = function()
    if not DB then return nil end
    local a = (segHost and segHost:IsShown()) and segHost or root
    return a, -(DB.cdYOffset or 4)
end
-- 推左侧留白并立刻重排。⚠ 只改几何,不碰 filter —— 两件事分开,
-- 免得"挪个位置"顺手把某一排的筛选也重置了。
ns.SetCdRowPad         = function(px)
    if not DB then return end
    cdRowPad = tonumber(px) or 0
    LayoutDots()
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
        InitCharDB()          -- ⚠ 必须在 DB 就位**之后**:它要从账号库继承一次位置
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
