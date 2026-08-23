-- DodoCombatHUD - Options.lua
-- ESC → 选项 → 插件 → DodoCombatHUD。两层:
--   主页      = 「要显示什么」(各部件开关)
--   UI 子页   = 「显示成多大」(尺寸)
--
-- 🔴 这套 Settings API 只造得出四种控件:checkbox / slider / dropdown / colorswatch,
--    **没有任何文本输入**(查的是 Blizzard_Settings_Shared/Blizzard_Settings.lua 的
--    导出函数表,不是 wiki)。⇒ DoT 法术 ID、两根条的刻度、引导跳数这三样
--    **结构上进不了这个面板**,只能留在 /dch —— 主页底下那行提示就是干这个用的。
--    没有那行提示的话,人会在面板里找一个根本不在这儿的东西,然后以为功能没做。
--
-- ⚠ 子页靠 RegisterVerticalLayoutSubcategory(parent, name) 的 parent 关系自己挂上树,
--    **只有顶层那个**要 RegisterAddOnCategory。这一条是照着上面那份源码的形状写的,
--    真机第一次跑要确认子页真的出现在左边(没出现的话就是这里少一次注册)。

local ADDON, ns = ...

-- 版本号从 TOC 现读,不在这儿写第二份 —— 写死的那份迟早跟真实 build 漂。
local function GetVersion()
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return (meta and meta(ADDON, "Version")) or "?"
end

-- 一个 bool 一个勾。
-- 🔴 getValue 里**展开写,不用 `db and db[k] ~= false or default` 那个惯用法** ——
--    那个写法在「值确实是 false」时会走进 or 那支、把 default(true) 端回去,
--    症状是「我关掉的开关下次打开面板又是勾着的」。DodoInspect 在同族写法上栽过一次。
local function AddCheckbox(category, variable, key, label, tooltip, onChanged)
    local default = ns.DEFAULTS[key] ~= false
    local setting = Settings.RegisterProxySetting(
        category, variable, Settings.VarType.Boolean, label, default,
        function()
            local db = DodoCombatHUDDB
            if not db then return default end
            return db[key] ~= false
        end,
        function(value)
            local db = DodoCombatHUDDB
            if not db then return end
            db[key] = value and true or false
            onChanged()
        end)
    Settings.CreateCheckbox(category, setting, tooltip)
end

-- 一个数值一个滑条(整数 px)。步进恒为 1:这些量全是像素,给小数没有意义,
-- 而带小数的读数会让人以为它比实际更精细。
local function AddSlider(category, variable, key, label, tooltip, lo, hi, onChanged)
    local default = ns.DEFAULTS[key]
    local setting = Settings.RegisterProxySetting(
        category, variable, Settings.VarType.Number, label, default,
        function()
            local db = DodoCombatHUDDB
            if not db then return default end
            return tonumber(db[key]) or default
        end,
        function(value)
            local db = DodoCombatHUDDB
            if not db then return end
            db[key] = math.floor((tonumber(value) or default) + 0.5)
            onChanged()
        end)
    local options = Settings.CreateSliderOptions(lo, hi, 1)
    -- 存在性兜底:这个 mixin 换过名字的话,滑条照样能用,只是右边没有 "36 px" 那个读数。
    if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
            function(v) return tostring(math.floor(v + 0.5)) .. " px" end)
    end
    Settings.CreateSlider(category, setting, options, tooltip)
end

-- 小节标题。存在性兜底:这个 initializer 哪天换名字,少一行标题而已,
-- 别让它把整页掀掉(整段还在外面的 pcall 里,这里只是让失败更小)。
local function AddHeader(layout, text)
    if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end
end

function ns.RegisterOptions()
    if ns.OptionsRegistered then return end
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end

    local ok = pcall(function()
        local category, layout = Settings.RegisterVerticalLayoutCategory("DodoCombatHUD")
        AddHeader(layout, "DodoCombatHUD  v" .. GetVersion())

        -- 主页 = 「要显示什么」。判据:「这东西出不出现在屏幕上」放这页,
        -- 「它多大」放 UI 子页。混着放两页都会变成一锅乱炖。
        AddCheckbox(category, "DCH_POWER_ON", "powerOn", "主资源条",
            "当前专精的主资源(暗牧疯狂 / 骑士法力 / 猫德能量…),跟着专精和德鲁伊形态自动切换。这个角色没有这种资源时它本来就是空的,关掉能把那一格收走。",
            function() ns.ApplyLayout(); ns.RefreshAvailability() end)

        AddCheckbox(category, "DCH_HEALTH_ON", "healthOn", "目标血条",
            "中间那根。⚠ 关掉它,上面那排目标 DoT 图标会跟着不显示 —— 它们锚在血条上沿。",
            ns.ApplyLayout)

        AddCheckbox(category, "DCH_CAST_ON", "castOn", "施法 / 引导条",
            "最上面那根,画自己的施法和引导。引导的跳数刻度要用 /dch chan 现场校准一次。",
            ns.ApplyLayout)

        AddCheckbox(category, "DCH_DOTS_ON", "dotsOn", "目标 DoT 图标",
            "血条左上角那排,我打在目标身上的 DoT + 倒计时。位置是固定的 —— 掉了哪个就空哪一格,后面的不会左移。",
            ns.ApplyLayout)

        AddCheckbox(category, "DCH_CDS_ON", "cdsOn", "自身增益图标",
            "资源条**下方**那排,自己身上的重要 buff 还剩多久(骨盾这种常驻的也在里面)。流式排列(有几个画几个)—— 跟上面那排 DoT 不一样,它不留空位。0.12 起施法条挪到了整叠最下:它是唯一「框体一直在、内容时有时无」的东西,夹在中间会白占一条地。",
            ns.ApplyLayout)

        AddCheckbox(category, "DCH_RAID_ON", "raidOn", "别人给我的增益",
            "血条**右上角**那一竖列:最上面一格专给嗜血一族(不跟任何东西抢位置),下面两格装能量灌注 / 外部保命这些。⚠ 这两格单人基本验不出来(嗜血要有人放、能量灌注要另一个牧师)—— 用 /dch lust 和 /dch buff 列出 ID 核对。",
            ns.ApplyLayout)

        AddCheckbox(category, "DCH_SECONDARY_ON", "secondaryOn", "次要资源条",
            "圣能 / 连击点 / 灵魂碎片 / 真气 / 符文 / 奥术充能 / 精华这类「数颗数」的资源,画成一排格子夹在主资源和施法条之间。没有这类资源的专精不会占位置。毁灭术的碎片会显示成「三颗半」——那一颗的进度也画得出来。",
            ns.ApplyLayout)

        AddHeader(layout, "条上的数字")

        AddCheckbox(category, "DCH_POWER_NUMBER", "powerNumber", "主资源数字",
            "在主资源条上叠一个数字。", ns.ApplyLayout)

        AddCheckbox(category, "DCH_HEALTH_NUMBER", "healthNumber", "血量数字",
            "在目标血条上叠一个数字。默认关:BOSS 血量是八位数,噪音大于信息。", ns.ApplyLayout)

        AddHeader(layout, "暴雪自带界面")

        AddCheckbox(category, "DCH_HIDE_BLIZZ_CAST", "hideBlizzCast",
            "藏掉暴雪自己的施法条",
            "我们那根施法条是自绘的,两根一起显示纯属打架。⚠ 取消勾选会把暴雪那根恢复一次,之后就撒手 —— 你自己用编辑模式关掉它的话,我们不会再把它打开。",
            function() ns.ApplyLayout(); ns.ApplyBlizzCastBar(true) end)

        -- 这一节没有控件,它就是一行字。理由见文件头:三样东西进不了这个面板,
        -- 不说的话人会在这儿翻找,然后以为功能没做。
        AddHeader(layout, "DoT 盯哪几个法术 / 条上的刻度 / 引导跳数 → 只能用 /dch 改")

        -- ── UI 子页 = 「显示成多大」 ──────────────────────────────
        -- 跟顶层一样返回 (category, layout) —— 第二个是子页自己的版面,小节标题要挂它,
        -- 挂到主页那个 layout 上会把标题加到**另一页**去。
        local ui, uiLayout = Settings.RegisterVerticalLayoutSubcategory(category, "UI")

        AddCheckbox(ui, "DCH_LOCKED", "locked", "锁定位置",
            "取消勾选就能拖动。血条 / 主资源 / 施法条**哪根都能抓**(次要资源那排格子抓不动,它太薄了)。摆好记得勾回来。",
            ns.ApplyLayout)

        AddSlider(ui, "DCH_WIDTH", "width", "所有条的长度",
            "全部同宽,一个值管到底 —— 次要资源那排格子加起来也等于这个长度(缝算在里面)。",
            40, 1200, ns.ApplyLayout)

        AddSlider(ui, "DCH_GAP", "gap", "条与条之间的缝",
            "上下相邻两根条之间留多少像素。", 0, 100, ns.ApplyLayout)

        AddHeader(uiLayout, "三根条的高度(屏幕上从上往下)")

        AddSlider(ui, "DCH_HEALTH_H", "healthHeight", "目标血条 高度",
            "屏幕上从上往下第二根。", 4, 200, ns.ApplyLayout)

        AddSlider(ui, "DCH_POWER_H", "powerHeight", "主资源条 高度",
            "⚠ 它同时是整个 HUD 的锚点盒子 —— 关掉主资源条时这一格会塌成 1px,上下两根会靠拢。",
            4, 200, ns.ApplyLayout)

        AddSlider(ui, "DCH_CAST_H", "castHeight", "施法 / 引导条 高度",
            "最下面那根。", 4, 200, ns.ApplyLayout)

        AddSlider(ui, "DCH_SECONDARY_H", "secondaryHeight", "次要资源条 高度",
            "那排格子有多高(圣能 / 连击点 / 碎片…)。", 4, 200, ns.ApplyLayout)

        AddSlider(ui, "DCH_SEG_GAP", "segGap", "格与格之间的缝",
            "⚠ 缝是**算在总宽里**的 —— 一排格子加起来仍然等于其它条的长度,所以缝调大了每格就变细。",
            0, 40, ns.ApplyLayout)

        AddHeader(uiLayout, "目标 DoT 图标")

        AddSlider(ui, "DCH_DOT_W", "dotWidth", "DoT 图标 宽",
            "血条左上角那排图标的宽度。", 8, 120, ns.ApplyLayout)

        AddSlider(ui, "DCH_DOT_H", "dotHeight", "DoT 图标 高",
            "⚠ 跟宽不相等时图标会被拉伸(光环贴图本身是方的)。想压扁省竖直空间就调这个。",
            8, 120, ns.ApplyLayout)

        AddSlider(ui, "DCH_DOT_FONT", "dotFontSize", "DoT 倒计时 字号",
            "图标上那个倒计时数字的绝对像素。⚠ 它**不再**跟着图标大小走 —— 调完图标记得回来看一眼这个。",
            8, 60, ns.ApplyLayout)

        AddSlider(ui, "DCH_DOT_SPACING", "dotSpacing", "DoT 图标间距",
            "相邻两格之间留多少像素。", 0, 40, ns.ApplyLayout)

        AddSlider(ui, "DCH_DOT_YOFF", "dotYOffset", "DoT 离血条的距离",
            "那排图标底边离血条上沿多高。", -50, 50, ns.ApplyLayout)

        AddHeader(uiLayout, "自身增益图标(资源条下方)")

        AddSlider(ui, "DCH_CD_W", "cdWidth", "大招图标 宽", "", 8, 120, ns.ApplyLayout)
        AddSlider(ui, "DCH_CD_H", "cdHeight", "大招图标 高",
            "⚠ 跟宽不相等时图标会被拉伸(光环贴图本身是方的)。", 8, 120, ns.ApplyLayout)
        AddSlider(ui, "DCH_CD_FONT", "cdFontSize", "大招倒计时 字号",
            "三排各有自己的字号 —— 调这个不会动 DoT 那排。", 8, 60, ns.ApplyLayout)
        AddSlider(ui, "DCH_CD_SPACING", "cdSpacing", "大招图标间距", "", 0, 40, ns.ApplyLayout)
        AddSlider(ui, "DCH_CD_YOFF", "cdYOffset", "大招离施法条多远",
            "那排图标顶边离施法条下沿多少像素。", -50, 100, ns.ApplyLayout)

        AddHeader(uiLayout, "别人给我的增益(血条右上角)")

        AddSlider(ui, "DCH_RAID_W", "raidWidth", "增益图标 宽", "", 8, 120, ns.ApplyLayout)
        AddSlider(ui, "DCH_RAID_H", "raidHeight", "增益图标 高", "", 8, 120, ns.ApplyLayout)
        AddSlider(ui, "DCH_RAID_FONT", "raidFontSize", "增益倒计时 字号", "", 8, 60, ns.ApplyLayout)
        AddSlider(ui, "DCH_RAID_SPACING", "raidSpacing", "增益图标间距",
            "竖着排,这是上下两格之间的缝。", 0, 40, ns.ApplyLayout)
        AddSlider(ui, "DCH_RAID_XOFF", "raidXOffset", "增益离血条多远",
            "那一竖列左边离血条右沿多少像素。", -50, 200, ns.ApplyLayout)

        -- ⚠ 放在最后:子页先挂到 parent 上,再把整棵树注册进 AddOns 列表。
        Settings.RegisterAddOnCategory(category)
        ns.OptionsCategory = category
        ns.OptionsUICategory = ui
    end)

    -- 整段裹 pcall:Settings API 哪天改了形状,**HUD 本身不许跟着倒** ——
    -- /dch 那套命令是完整的后路,面板只是它的皮。
    ns.OptionsRegistered = ok or nil
end
