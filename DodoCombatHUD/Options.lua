-- DodoCombatHUD - Options.lua
-- ESC → 选项 → 插件 → DodoCombatHUD。一个主页 + 五个子页,**按屏幕上那一块切**,
-- 不按「开关 / 尺寸」切:一个东西的开关、大小、颜色、盯哪几个法术全在同一页。
--
--   主页     全局:位置 / 条宽 / 缝 / 背景 / 材质 / 三个按钮
--   目标     目标血条 + 它上面那排 DoT 图标
--   资源     主资源条 + 次要资源条
--   自身增益 资源条下方那排(**图形化编辑**:按专精、显隐、排顺序)+ 沸点专格
--   团队增益 血条右上角那个网格(嗜血 + 别人给的)
--   施法引导 最下面那根 + 引导跳数
--
-- ── 为什么是 canvas 页 ──
-- 0.12 那版用 RegisterVerticalLayoutCategory,并且在这儿写着「这套 API 只造得出
-- checkbox/slider/dropdown/colorswatch 四种,没有文本输入 ⇒ 法术 ID / 刻度 / 引导跳数
-- **结构上**进不了面板」。**那条是错的**(2026-08-23 扒 Blizzard_SettingControls.lua
-- 的导出表核实):还有按钮、可折叠小节、四种组合控件,而且
-- `Settings.RegisterCanvasLayoutSubcategory(父category, 自建frame, 名字)` 让你自己建框体。
-- 选 canvas 的实际理由:法术表的图形化编辑 / 要打字的输入框 / 三个按钮,都装不下。
-- 代价:**canvas 页里的控件进不了设置面板那个搜索框**。认了(全家桶九个插件都这样)。
--
-- ── 🔴 0.13.1:布局改成**游标式**,页面里不许再出现硬编码 y ──
--
-- 0.13.0 每个控件都手写 y 坐标,真机一跑**满屏文字互相压**。根因不是"坐标算错了",
-- 是这个方法**结构上**不成立:`Note` 的高度取决于它换行成几行,而那要等到运行时
-- (中文断行 + 玩家的界面缩放 + 字体)才知道 —— 手写 y 等于替一个你算不出来的量
-- 猜一个常数。canon:**能靠结构保证的别靠算式保证。**
--
-- ⇒ 现在每一列是一个游标(`NewCol`):摆一个控件,y 自己往下走;`Note` 摆完当场
--   `GetStringHeight()` 读真实高度再推。页面代码里一个 y 坐标都没有,
--   `tools/test_options.lua` 有一条 guard 盯着"别再写回来"。
--
-- ⚠ canvas 页**不滚动**:超出面板高度的控件被裁掉且不报错。游标会记住每列的最低点,
--   超了就在聊天框吵一句(离线量不出真实高度,只有运行时知道)。

local ADDON, ns = ...

local category
local Refreshers = {}          -- 打开面板时要重跑的刷新函数(专精 / 主资源 / 最后那个引导都会变)

local COL_L, COL_R = 16, 352   -- 两列的左边界
local COL_W = 300              -- 每列可用宽度(文本换行按它算)
local FLOOR = -545             -- 面板可用高度,超了就吵一句

local function DB() return DodoCombatHUDDB end

-- 版本号从 TOC 现读,不在这儿写第二份 —— 写死的那份迟早跟真实 build 漂。
local function GetVersion()
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return (meta and meta(ADDON, "Version")) or "?"
end

---------------------------------------------------------------------------------------------------
-- 游标:一列里从上往下摆控件,y 自动走
---------------------------------------------------------------------------------------------------

local Col = {}
Col.__index = Col

local function NewCol(parent, x)
    return setmetatable({ p = parent, x = x, y = -14, deepest = -14 }, Col)
end

-- 占掉 h 像素,返回这一块的**顶边** y。所有 SetPoint 都用它的返回值。
function Col:take(h)
    local top = self.y
    self.y = self.y - h
    if self.y < self.deepest then self.deepest = self.y end
    return top
end

function Col:gap(h) self:take(h or 10) end

function Col:Header(text)
    local fs = self.p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetText(text)
    fs:SetTextColor(1, 0.82, 0)
    fs:SetPoint("TOPLEFT", self.x, self:take(26))
    return fs
end

-- 🔴 高度**当场量**,不写常数。`GetStringHeight()` 要在 SetWidth + SetText **之后**读 ——
--    顺序反了会读到 0,而那表现成"下一个控件压上来",跟没量一模一样。
--    下限 12:万一某个 build 上它返回 0,至少还是一行的位置,不会整列坍在一起。
function Col:Note(text, width)
    local fs = self.p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetWidth(width or COL_W)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    local h = math.max(12, math.ceil((fs:GetStringHeight() or 0) + 0.5))
    fs:SetPoint("TOPLEFT", self.x, self:take(h + 8))
    return fs
end

-- 内容会变的说明行(比如「现在这根画的是 XXX」)。文字一换高度就变,
-- 而它下面还有别的控件 ⇒ **必须预留固定行数**,不能当场量。
-- 少这一步的症状:换个专精,下面的控件全往上跳或者被压。
function Col:NoteBox(lines)
    local fs = self.p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetWidth(COL_W)
    fs:SetJustifyH("LEFT")
    fs:SetPoint("TOPLEFT", self.x, self:take((lines or 1) * 13 + 8))
    return fs
end

-- 🔴 读值一律展开写成 `d[key] ~= false`,**别用 `d and d[k] ~= false or default`** ——
--    值确实是 false 时那个惯用法会走进 `or` 那支、把默认值(true)端回来,症状是
--    「我关掉的开关,下次打开面板又勾上了」。DodoInspect 在同族写法上栽过一次。
function Col:Check(label, key, tooltip, apply)
    local c = CreateFrame("CheckButton", nil, self.p, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c:SetPoint("TOPLEFT", self.x, self:take(26))
    local fs = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", c, "RIGHT", 2, 0)
    fs:SetText(label)
    local function refresh()
        local d = DB()
        if d then c:SetChecked(d[key] ~= false) else c:SetChecked(ns.DEFAULTS[key] ~= false) end
    end
    refresh()
    c:SetScript("OnClick", function(self2)
        local d = DB(); if not d then return end
        d[key] = self2:GetChecked() and true or false
        if apply then apply() end
    end)
    if tooltip and tooltip ~= "" then
        c:SetScript("OnEnter", function(self2)
            GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    Refreshers[#Refreshers + 1] = refresh
    return c
end

-- 勾选框,但值不在 DB 顶层(比如"只隐藏这一种资源",存的是 resOff[资源名])。
-- get 返回 nil = 这个东西现在不存在 ⇒ 画灰 + 点不动(原因由调用方在旁边那行说明)。
function Col:CheckFn(label, get, set, tooltip)
    local c = CreateFrame("CheckButton", nil, self.p, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c:SetPoint("TOPLEFT", self.x, self:take(26))
    local fs = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", c, "RIGHT", 2, 0)
    local function refresh()
        local v = get()
        c:SetEnabled(v ~= nil)
        c:SetChecked(v == true)
        fs:SetText(label())
    end
    refresh()
    c:SetScript("OnClick", function(self2) set(self2:GetChecked() and true or false); refresh() end)
    if tooltip then
        c:SetScript("OnEnter", function(self2)
            GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
            GameTooltip:SetText(fs:GetText() or "", 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    Refreshers[#Refreshers + 1] = refresh
    return c
end

-- 整数像素滑条,标题在条的正上方 ⇒ 这一格要 14(字) + 16(条) + 余量。
function Col:Slider(label, lo, hi, key, apply, unit)
    local top = self:take(38)
    local s = CreateFrame("Slider", nil, self.p)
    s:SetSize(200, 16)
    s:SetPoint("TOPLEFT", self.x, top - 16)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(1)
    s:SetObeyStepOnDrag(true)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local th = s:GetThumbTexture(); if th then th:SetSize(16, 16) end
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.25, 0.25, 0.25, 0.9)
    track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(5)

    local lab = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lab:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3); lab:SetText(label)
    local val = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    val:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 3)

    local suffix = unit or " px"
    local function cur()
        local d = DB()
        return math.floor((tonumber(d and d[key]) or ns.DEFAULTS[key] or lo) + 0.5)
    end
    local function refresh() s:SetValue(cur()); val:SetText(cur() .. suffix) end
    refresh()
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        val:SetText(v .. suffix)
        local d = DB(); if not d then return end
        -- ⚠ 只在**真的变了**时 apply:SetValue 自己也会触发这个回调,
        --   不挡的话打开面板就把整套布局重算一遍。
        if d[key] ~= v then d[key] = v; if apply then apply() end end
    end)
    Refreshers[#Refreshers + 1] = refresh
    return s
end

-- 色块。get 返回 {r,g,b[,a]} 数组(存档里就是这个形状),set 收同样的形状。
-- get 返回 nil = 这个东西现在不存在(比如换了专精没这个资源)⇒ 画灰 + 点不动。
-- 🔴 「点不动」必须配「说出为什么」—— 一个变灰又不解释的控件读起来像"坏了"。
--    说明那一句归调用方(它才知道原因),这里只负责挡住。
function Col:Color(label, get, set, hasAlpha)
    local b = CreateFrame("Button", nil, self.p)
    b:SetSize(18, 18)
    b:SetPoint("TOPLEFT", self.x, self:take(26))
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(b)
    local bd = CreateFrame("Frame", nil, b, "BackdropTemplate")
    bd:SetPoint("TOPLEFT", -1, 1); bd:SetPoint("BOTTOMRIGHT", 1, -1)
    bd:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    bd:SetBackdropBorderColor(0, 0, 0, 1)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", b, "RIGHT", 6, 0)
    fs:SetText(label)

    local function refresh()
        local c = get()
        tex:SetColorTexture((c and c[1]) or 0.5, (c and c[2]) or 0.5, (c and c[3]) or 0.5, 1)
        tex:SetDesaturated(c == nil)
        b:SetEnabled(c ~= nil)
    end
    refresh()
    b:SetScript("OnClick", function()
        local c = get(); if not c then return end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = c[1] or 1, g = c[2] or 1, b = c[3] or 1,
            opacity = c[4] or 1, hasOpacity = hasAlpha and true or false,
            swatchFunc = function()
                local r, g, bl = ColorPickerFrame:GetColorRGB()
                if hasAlpha then set({ r, g, bl, ColorPickerFrame:GetColorAlpha() or 1 })
                else set({ r, g, bl }) end
                refresh()
            end,
            opacityFunc = function()
                local r, g, bl = ColorPickerFrame:GetColorRGB()
                set({ r, g, bl, ColorPickerFrame:GetColorAlpha() or 1 })
                refresh()
            end,
            cancelFunc = function() end,
        })
    end)
    Refreshers[#Refreshers + 1] = refresh
    return b
end

function Col:Button(text, w, onClick)
    local b = CreateFrame("Button", nil, self.p, "UIPanelButtonTemplate")
    b:SetSize(w or 120, 22)
    b:SetPoint("TOPLEFT", self.x, self:take(28))
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- 同一行摆两个按钮(第二个横向偏移,不再占一行高度)。
function Col:Button2(text, w, dx, onClick)
    local b = CreateFrame("Button", nil, self.p, "UIPanelButtonTemplate")
    b:SetSize(w or 120, 22)
    b:SetPoint("TOPLEFT", self.x + dx, self.y + 28)   -- 贴回上一行
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- 单行文本输入,标题在上、框在下。
--
-- 🔴 **只在文字真的改过时才提交。**(0.13.1 修,这是个会毁数据的 bug)
--    原来 `commit` 无条件挂在 OnEditFocusLost 上 ⇒ 面板一开一关的焦点事件就会拿
--    **当前框里的内容**提交一次。而刻度那两个框的 `set` 认得空串(空串 = 合法地清掉刻度)
--    ⇒ 一次误提交就把玩家的刻度**写没了**,而且**自我固化**:写没了以后框永远是空的,
--    下次再误提交还是空。零报错、看起来就像"这个框不显示值"。
--    ⇒ 记住上次渲染出去的文本,一样就什么都不做。
--    canon:「宽容的默认值会替 bug 遮丑」—— 空串是合法输入,所以误提交是静默且破坏性的。
function Col:Edit(label, w, get, set, numeric)
    local top = self:take(44)
    local lab = self.p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lab:SetPoint("TOPLEFT", self.x, top)
    lab:SetText(label)
    local e = CreateFrame("EditBox", nil, self.p, "InputBoxTemplate")
    e:SetPoint("TOPLEFT", self.x + 6, top - 18)
    e:SetSize(w or 180, 22)
    e:SetAutoFocus(false)
    if numeric then e:SetNumeric(true) end

    local shown = nil                     -- 上一次**我们**渲染出去的文本
    local function refresh()
        shown = get() or ""
        e:SetText(shown)
    end
    refresh()
    local function commit()
        local txt = e:GetText() or ""
        e:ClearFocus()
        if txt == shown then return end   -- ← 没改过就别提交(见上面那段)
        set(txt)
        refresh()                         -- 回读:输入被拒 / 被规整过时,框里要显示真正存进去的值
    end
    e:SetScript("OnEnterPressed", commit)
    e:SetScript("OnEditFocusLost", commit)
    e:SetScript("OnEscapePressed", function() e:ClearFocus(); refresh() end)
    Refreshers[#Refreshers + 1] = refresh
    return e
end

-- 「20,40,60」这种逗号分隔的百分比刻度,存成数组。
-- 非法输入**整条拒收**并回读原值,不做"能解析几个算几个" —— 半生效的刻度
-- 会教你一个错的节奏,而它看起来完全像个正经功能。
local function TicksToText(t)
    local out = {}
    for i = 1, #(t or {}) do out[i] = tostring(t[i]) end
    return table.concat(out, ",")
end

local function TextToTicks(s)
    local out = {}
    for piece in tostring(s or ""):gmatch("[^,%s]+") do
        local n = tonumber(piece)
        if not n or n < 0 or n > 100 then return nil end
        out[#out + 1] = math.floor(n + 0.5)
    end
    return out
end

-- 刻度那两个框共用的读写。⚠ 存档里那个键必须**保持是同一个数组**的语义,
-- 空数组 = 玩家真的把刻度清了(合法),所以这儿不做"空了就回默认"。
local function ticksIO(key)
    return function() local d = DB(); return d and TicksToText(d[key]) end,
           function(v)
               local t = TextToTicks(v); local d = DB()
               if t and d then d[key] = t; ns.ApplyLayout() end
           end
end

---------------------------------------------------------------------------------------------------
-- 图形化法术表编辑器
--
-- 一行 = 一格:[图标] [显示勾] [格号. 法术名 (ID)] [^] [v] [x]
--
-- 🔴 「显示勾」和「x 删除」是**两件事**,必须都给:
--      · 取消勾选 = 我暂时不想看,**配置和名次都留着**,勾回来还在原处
--      · x        = 从表里移除(内置表的话,想找回来只能整张「回内置」)
--    只给删除的话,玩家为了"这次不看"会去删,然后再也排不回原来的顺序。
--
-- 🔴 列的是**配置表**(ns.AuraList),不是可见表 —— 隐藏的那几行必须还在列表里,
--    否则你再也勾不回来。HUD 那侧才用 VisibleAuraList。
--
-- 🔴 `reorder` = 这一排的左右顺序**由我们决定**吗?
--      · dots / cds  = 固定格位,第 N 个 ID 就在第 N 格 ⇒ true,给 ^ v
--      · lust / raid = 暴雪排序的流式网格(sortMethod = Expiration)⇒ **false**
--    那两排绝不能给 ^ v:那是一个**点了不会有任何变化**的控件,比不给更坏 ——
--    它会让人以为自己排错了,反复去调一个根本不生效的东西。
---------------------------------------------------------------------------------------------------

local ROW_H = 22

-- `pinned` = 这一排最左边那个**不归列表管**的固定格(现在只有血 DK 的沸点)。
-- 🔴 它必须**画在列表里**,不能只给个单独的勾选框(0.13.1 就是那么做的,错了):
--    屏幕上血 DK 是 7 个图标,而列表说"占 6/8 格"、里面的 `1.` 对应屏幕第 2 格
--    ⇒ **配置面板在撒谎**。它不能移不能删,但它得在那儿,而且得占第 1 号。
--    形状:{ eligible=fn(返回 能不能显示, 为什么不能), get=fn, set=fn, icon=spellID, label= }
function Col:AuraEditor(kind, maxRows, cap, reorder, visibleRows, pinned)
    local parent = self.p
    local rows, pinRow, refresh = {}, nil, nil
    local shownRows = math.min(visibleRows or maxRows, maxRows)

    local status = self:NoteBox(1)
    local note   = self:NoteBox(2)
    note:SetTextColor(1, 0.45, 0.45)

    -- ⚠ canvas 页自己**不滚动**,而团队增益内置 23 个 —— 直接铺开会被面板裁掉,
    --   而且不报错。所以行统一装进一个 ScrollFrame:短表看不出区别,长表能滚。
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetSize(300, shownRows * ROW_H)
    scroll:SetPoint("TOPLEFT", self.x, self:take(shownRows * ROW_H + 6))
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(300, (maxRows + 1) * ROW_H)
    scroll:SetScrollChild(child)

    local function spec() return ns.CurrentSpec() end
    local function perSpec() return ns.PER_SPEC[kind] ~= nil end
    local function listNow() return ns.AuraList(DB(), kind, spec()) end

    -- 存回去 + 推 filter + 重画。三件事必须一起 ——
    -- 只存不推的话屏幕上什么都不变,而那看起来像"面板没接上"。
    local function commitList(list)
        if not ns.SetAuraList(DB(), kind, spec(), list) then
            note:SetText("现在问不出当前专精,这一排改不了。")
            return false
        end
        ns.ApplyAuraFilters()
        refresh()
        return true
    end

    -- 行的**纵向位置每次刷新时才定**:固定格在不在会让整列上下挪一行,
    -- 而它跟着专精变。建的时候钉死的话,换到血 DK 就会有两行叠在一起。
    -- 名字列的右边界:有 ^ v 时按钮从 216 起,没有时 x 从 260 起 —— 各留 6px 缝。
    local NAME_RIGHT = reorder and 210 or 254
    local ID_W = 44

    local function placeRow(r, vis)
        local top = -(vis - 1) * ROW_H
        r.icon:ClearAllPoints();  r.icon:SetPoint("TOPLEFT", 0, top - 2)
        r.check:ClearAllPoints(); r.check:SetPoint("TOPLEFT", 20, top)
        r.text:ClearAllPoints();  r.text:SetPoint("TOPLEFT", 44, top - 4)
        r.text:SetWidth(NAME_RIGHT - 44 - ID_W - 4)
        if r.id then
            r.id:ClearAllPoints()
            r.id:SetPoint("TOPRIGHT", child, "TOPLEFT", NAME_RIGHT, top - 4)
            r.id:SetWidth(ID_W)
        end
        if r.up then
            r.up:ClearAllPoints();   r.up:SetPoint("TOPLEFT", 216, top)
            r.down:ClearAllPoints(); r.down:SetPoint("TOPLEFT", 238, top)
        end
        if r.del then r.del:ClearAllPoints(); r.del:SetPoint("TOPLEFT", 260, top) end
    end

    -- 一行的框体。`withButtons=false` 用于固定格:它不能移也不能删,
    -- 🔴 而"不能删"的表达方式是**根本不给那个按钮**,不是给一个点了没反应的。
    local function newRowWidgets(withButtons)
        local r = {}
        r.icon = child:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- 削掉暴雪图标那圈自带边框

        r.check = CreateFrame("CheckButton", nil, child, "UICheckButtonTemplate")
        r.check:SetSize(22, 22)

        -- 名字和 spellID **分成两个** FontString:ID 右对齐单独一列。
        -- 🔴 挤在一起写的话,名字一长就把 ID 顶出去被截掉(`SetWordWrap(false)` 是静默截断)
        --    ——「鲜血女王的精华 (43...」。而 ID 正是「填错了要改哪个」的唯一线索,
        --    名字反而是查不到时会变红字的那个信号,截掉一半也还认得出。
        --    ⇒ 会被牺牲的那个必须是名字,不是 ID。顺带 ID 对齐成一列,好扫。
        r.text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)                     -- 名字太长就截断,绝不换行(会撑破行高)
        r.id = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.id:SetJustifyH("RIGHT")
        r.id:SetWordWrap(false)

        if withButtons then
            local function tinyBtn(label)
                local b = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
                b:SetSize(20, 18); b:SetText(label)
                return b
            end
            if reorder then r.up, r.down = tinyBtn("^"), tinyBtn("v") end
            r.del = tinyBtn("x")
        end
        return r
    end

    local TIP = "取消勾选 = 不占格位,但配置和名次都留着,勾回来还在原处。想彻底删掉用右边那个 x。"

    local function makeRow(i)
        local r = newRowWidgets(true)
        r.check:SetScript("OnEnter", function(self2)
            GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
            GameTooltip:SetText("显示这一格", 1, 1, 1)
            GameTooltip:AddLine(TIP, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        r.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if r.up then
            r.up:SetScript("OnClick", function()
                local l = listNow(); if ns.ListMove(l, i, -1) then commitList(l) end
            end)
            r.down:SetScript("OnClick", function()
                local l = listNow(); if ns.ListMove(l, i, 1) then commitList(l) end
            end)
        end
        r.del:SetScript("OnClick", function()
            local l = listNow()
            local id = l[i]; if not id then return end
            -- 删的同时把它的「隐藏」标记也清掉。留着的话以后 add 回同一个 ID 时
            -- 它会莫名其妙不显示,而屏幕上完全看不出为什么。
            ns.SetAuraHidden(DB(), kind, spec(), id, false)
            ns.ListRemove(l, id)
            commitList(l)
        end)
        r.check:SetScript("OnClick", function(self2)
            local id = listNow()[i]; if not id then return end
            ns.SetAuraHidden(DB(), kind, spec(), id, not self2:GetChecked())
            ns.ApplyAuraFilters()
            refresh()
        end)
        return r
    end

    for i = 1, maxRows do rows[i] = makeRow(i) end

    if pinned then
        pinRow = newRowWidgets(false)
        pinRow.icon:SetTexture(
            (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(pinned.icon)) or 134400)
        pinRow.check:SetScript("OnClick", function(self2)
            pinned.set(self2:GetChecked() and true or false)
            refresh()
        end)
        pinRow.check:SetScript("OnEnter", function(self2)
            GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
            GameTooltip:SetText("显示这一格", 1, 1, 1)
            GameTooltip:AddLine(pinned.tip or "这一格位置固定,不能移动也不能删除。", nil, nil, nil, true)
            GameTooltip:Show()
        end)
        pinRow.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- 添加行:输入框 + 两个按钮,同一行。
    local addTop = self:take(30)
    local addBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    addBox:SetPoint("TOPLEFT", self.x + 6, addTop)
    addBox:SetSize(84, 22)
    addBox:SetAutoFocus(false)
    addBox:SetNumeric(true)

    local function doAdd()
        local id = tonumber(addBox:GetText())
        addBox:SetText(""); addBox:ClearFocus()
        if not id or id <= 0 then
            note:SetText("要填一个 spellID(正整数)。")
            return
        end
        local l = listNow()
        for i = 1, #l do
            if l[i] == id then note:SetText(id .. " 已经在里面了。") return end
        end
        -- 🔴 固定格位那两排有硬上限:超出的格子**没有容器**,多填的 ID 会静默消失 ——
        --    "我明明加了却没出现"跟"ID 填错了"在屏幕上分不开。必须挡住并说清楚。
        if cap and #l >= cap then
            note:SetText(("已经 %d 个,满了(上限 %d 格)—— 先删掉或取消勾选一个。"):format(#l, cap))
            return
        end
        if #l >= maxRows then
            note:SetText(("这个编辑器最多列 %d 行,再多就只能用 /dch 改了。"):format(maxRows))
            return
        end
        ns.ListAdd(l, id)
        if commitList(l) then note:SetText("已加入:" .. ns.SpellLabel(id)) end
    end
    addBox:SetScript("OnEnterPressed", doAdd)
    addBox:SetScript("OnEscapePressed", function() addBox:SetText(""); addBox:ClearFocus() end)

    local addBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addBtn:SetPoint("TOPLEFT", self.x + 96, addTop)
    addBtn:SetSize(50, 22); addBtn:SetText("添加")
    addBtn:SetScript("OnClick", doAdd)

    local resetBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    resetBtn:SetPoint("TOPLEFT", self.x + 152, addTop)
    resetBtn:SetSize(66, 22); resetBtn:SetText("回内置")
    resetBtn:SetScript("OnClick", function()
        if not ns.ResetAuraList(DB(), kind, spec()) then
            note:SetText("现在问不出当前专精,这一排改不了。")
            return
        end
        -- 隐藏标记一并清掉:「回内置」的语义是"这一排回到出厂状态",
        -- 留着标记的话内置表那几个会**回来但不显示**,读起来像"回内置没生效"。
        local d = DB()
        if d and type(d.hidden) == "table" and type(d.hidden[kind]) == "table" then
            if perSpec() then
                if spec() then d.hidden[kind][spec()] = nil end
            else
                d.hidden[kind] = nil
            end
        end
        ns.ApplyAuraFilters()
        refresh()
        note:SetText("已回到内置表。")
    end)

    local function hideRow(r)
        if not r then return end
        r.icon:Hide(); r.check:Hide(); r.text:Hide()
        if r.id then r.id:Hide() end
        if r.del then r.del:Hide() end
        if r.up then r.up:Hide(); r.down:Hide() end
    end

    refresh = function()
        local d, sp = DB(), spec()
        -- 🔴 按专精那两排,specID 问不出来时**说人话**,别画一张空列表 ——
        --    空列表跟"这个专精本来就没有"长得一模一样,而两者的下一步完全不同。
        if perSpec() and sp == nil then
            status:SetText("|cffff3333问不出当前专精|r —— 这一排暂时改不了(切一下专精 / 重登)。")
            hideRow(pinRow)
            for i = 1, maxRows do hideRow(rows[i]) end
            addBox:Hide(); addBtn:Hide(); resetBtn:Hide()
            return
        end
        addBox:Show(); addBtn:Show(); resetBtn:Show()

        -- 固定格在不在 —— 它跟着专精和天赋走,所以每次刷新都要重问。
        local pinOn, pinWhy = false, nil
        if pinned then pinOn, pinWhy = pinned.eligible() end
        local offset = pinOn and 1 or 0
        if pinOn then
            placeRow(pinRow, 1)
            local on = pinned.get()
            pinRow.icon:SetDesaturated(not on)
            pinRow.check:SetChecked(on and true or false)
            pinRow.check:Show(); pinRow.icon:Show()
            -- 🔴 明写「固定」两个字。它不能移不能删,而屏幕上跟别的行长得一样 ——
            --    不写的话人会去找它的 ^ v,找不到就以为是 bug。
            pinRow.text:SetFormattedText("%s1. %s", on and "" or "|cff707070", pinned.label)
            pinRow.text:Show()
            -- 固定格没有 spellID 那一列(它不是列表里的项)⇒ 那一列写「固定」。
            pinRow.id:SetText("固定"); pinRow.id:Show()
        else
            hideRow(pinRow)
        end

        local list, custom = ns.AuraList(d, kind, sp)
        local vis = #(ns.VisibleAuraList(d, kind, sp))
        local head = custom and "|cffffcc00你自己配的|r" or "内置表"
        if cap then
            -- 🔴 数**屏幕上真有几格**,把固定格算进去。0.13.1 报的是列表自己的
            --    6/8,而屏幕上是 7 个 —— 那就是配置面板在撒谎。
            local shownPin = (pinOn and pinned.get()) and 1 or 0
            status:SetFormattedText("%s —— 屏幕上 %d / %d 格%s%s", head,
                vis + shownPin, cap + offset,
                (#list > vis) and ("(另有 " .. (#list - vis) .. " 个没勾)") or "",
                pinOn and "(第 1 格是沸点专格)" or "")
        else
            status:SetFormattedText("%s —— %d 个%s", head, #list,
                (#list > vis) and ("(其中 " .. (#list - vis) .. " 个没勾)") or "")
        end
        if pinned and not pinOn and pinWhy then
            note:SetText("|cff808080沸点专格:" .. pinWhy .. "。|r")
        end
        -- ⚠ 列表比编辑器能列的还长时**要说出来**。canon:静默截断读起来跟"全都在"
        --   一模一样,而这里恰恰是"我配的那个怎么不见了"最容易发生的地方。
        if #list > maxRows then
            note:SetText(("还有 %d 个没列出来(这个编辑器最多 %d 行)—— 用 /dch 看全部。")
                :format(#list - maxRows, maxRows))
        end
        local total = #list + offset
        child:SetHeight(math.max(shownRows, total) * ROW_H)
        -- 装得下就把滚动条收起来:一条永远滑不动的滚动条只是噪音。
        if scroll.ScrollBar then scroll.ScrollBar:SetShown(total > shownRows) end

        for i = 1, maxRows do
            local r, id = rows[i], list[i]
            if not id then
                hideRow(r)
            else
                placeRow(r, i + offset)
                local hidden = ns.IsAuraHidden(d, kind, sp, id)
                local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
                r.icon:SetTexture(tex or 134400)          -- 134400 = 问号图标
                r.icon:SetDesaturated(hidden)
                r.icon:Show()
                r.check:SetChecked(not hidden); r.check:Show()
                -- 🔴 序号 = **屏幕上的格号**(算上固定格)。不加 offset 的话血 DK 的
                --    「1.」指的是屏幕上第 2 格 —— 而那正是 0.13.1 那个撒谎的形状。
                --    名字查不到就红字 —— 那是填错 ID 唯一看得见的地方。
                r.text:SetFormattedText("%s%d. %s",
                    hidden and "|cff707070" or "", i + offset, ns.SpellLabel(id))
                r.text:Show()
                r.id:SetText(tostring(id)); r.id:Show()
                if r.up then
                    -- 🔴 第一格的 ^ 和最后一格的 v 必须**点不动**,不是点了没反应。
                    --    ⚠ 有固定格时,列表第 1 项的 ^ 仍然是灰的 —— 它换不到固定格前面去。
                    r.up:SetEnabled(i > 1); r.up:Show()
                    r.down:SetEnabled(i < #list); r.down:Show()
                end
                r.del:Show()
            end
        end
    end

    Refreshers[#Refreshers + 1] = refresh
    refresh()
    return refresh
end

---------------------------------------------------------------------------------------------------
-- 页面
---------------------------------------------------------------------------------------------------

local pages = {}

local function Page(name)
    local f = CreateFrame("Frame")
    f.name = name
    f.cols = {}
    pages[#pages + 1] = f
    return f
end

local function L(f) local c = NewCol(f, COL_L); f.cols[#f.cols + 1] = c; return c end
local function R(f) local c = NewCol(f, COL_R); f.cols[#f.cols + 1] = c; return c end

local function colorGet(key) return function() local d = DB(); return d and d[key] end end
local function colorSet(key, apply)
    return function(v) local d = DB(); if d then d[key] = v; if apply then apply() end end end
end

local function BuildMainPage()
    local f = Page("DodoCombatHUD")
    local c = L(f)
    c:Header("DodoCombatHUD  v" .. GetVersion())
    c:Note("屏幕上从上到下:目标 DoT 图标 / 目标血条 / 主资源条 / 次要资源条 / 自身增益图标 / 施法引导条。左边每一页管其中一块。", 640)
    c:Check("锁定位置", "locked",
        "取消勾选就能拖。血条 / 主资源 / 施法条**哪根都能抓**(次要资源那排格子抓不动,它太薄)。摆好记得勾回来。",
        ns.ApplyLayout)
    -- 🔴 只给**一个**模式按钮。配置模式 = 演示模式 + aura 占位框 + 自动解锁,
    --    它完全盖住演示模式 —— 并排放两个"看起来差不多"的按钮,人只会去猜该点哪个。
    --    (`/dch test` 还留着,想只填假数据不解锁的时候用。)
    local cfgBtn
    local function cfgText() return ns.IsConfigMode() and "配置模式:开" or "配置模式:关" end
    cfgBtn = c:Button(cfgText(), 130, function()
        ns.ToggleConfig()
        cfgBtn:SetText(cfgText())
        for _, fn in ipairs(Refreshers) do pcall(fn) end
    end)
    c:Button2("回默认位置和尺寸", 150, 140, function()
        ns.ResetGeometry()
        for _, fn in ipairs(Refreshers) do pcall(fn) end
    end)
    Refreshers[#Refreshers + 1] = function() cfgBtn:SetText(cfgText()) end
    c:Note("配置模式:三根条填上假数据、aura 每个格子画一个占位框、并**自动解锁**,摆完再点一次全部还原(包括原来的锁定状态)。")
    c:Note("|cff33ff33那些占位框本身就能拖|r —— 抓哪个都行,拖的都是整叠 HUD,不用去够那三根条。")
    c:Note("⚠ aura 那几排的占位框**里面是空的** —— 图标是暴雪容器画的,我们塞不进假光环。空框不代表那一格有问题。")
    c:Slider("所有条的长度", 40, 1200, "width", ns.ApplyLayout)
    c:Note("全部同宽,一个值管到底 —— 次要资源那排格子加起来也等于这个长度(缝算在里面)。")
    c:Slider("条与条之间的缝", 0, 100, "gap", ns.ApplyLayout)
    c:Note("|cff808080面板做不到的都在 /dch 里。|r")

    local r = R(f)
    r:Header("配色")
    r:Color("条背景", colorGet("bgColor"), colorSet("bgColor", ns.ApplyLayout), true)
    r:Note("第四个通道是不透明度 —— 调到 1 就能把身后的场景完全隔断。")
    r:Color("刻度线", colorGet("tickColor"), colorSet("tickColor", ns.ApplyLayout), true)
    r:Header("材质")
    r:Edit("主资源条", 260,
        function() local d = DB(); return d and d.powerTexture end,
        function(v) local d = DB(); if d then d.powerTexture = v; ns.ApplyLayout() end end)
    r:Edit("血条 / 施法条", 260,
        function() local d = DB(); return d and d.barTexture end,
        function(v) local d = DB(); if d then d.barTexture = v; ns.ApplyLayout() end end)
    r:Note("可以填 atlas 名(暴雪自己就这么用)或者 Interface 路径。两个分开是刻意的:主资源要暴雪原生那张自带配色的图,血条要一张素图才染得干净。")
    r:Check("藏掉暴雪自己的施法条", "hideBlizzCast",
        "我们那根是自绘的,两根一起显示纯属打架。⚠ 取消勾选会把暴雪那根恢复一次,之后就撒手。",
        function() ns.ApplyLayout(); ns.ApplyBlizzCastBar(true) end)
    return f
end

local function BuildTargetPage()
    local f = Page("目标")
    local c = L(f)
    c:Header("目标血条")
    c:Check("显示目标血条", "healthOn",
        "中间那根。⚠ 关掉它,上面那排 DoT 图标会跟着不显示 —— 它们锚在血条上沿。", ns.ApplyLayout)
    c:Check("条上叠血量数字", "healthNumber",
        "默认关:BOSS 血量是八位数,噪音大于信息。", ns.ApplyLayout)
    c:Slider("血条高度", 4, 200, "healthHeight", ns.ApplyLayout)
    c:Color("血条颜色", colorGet("healthColor"), colorSet("healthColor", ns.ApplyLayout))
    do local get, set = ticksIO("healthTicks"); c:Edit("刻度(百分比,逗号分隔)", 200, get, set) end
    c:Note("默认 20 = 暗言术:灭的斩杀线。⚠ 刻度是**静态几何**,不是按血量算的 —— 12.x 里血量是 secret,插件读不到也算不了,只能画一条线给你用眼睛比。填了非法值整条不收,框里会退回原值。")
    c:Header("盯哪几个法术")
    c:AuraEditor("dots", ns.DOT_SLOTS or 4, ns.DOT_SLOTS or 4, true)

    local r = R(f)
    r:Header("目标 DoT 图标")
    r:Check("显示这一排", "dotsOn",
        "血条左上角,我打在目标身上的 DoT + 倒计时。**固定格位** —— 掉了哪个就空哪一格,后面的不会左移。",
        ns.ApplyLayout)
    r:Note("⚠ 目标是友方或者没目标时这排会整个收起来:暴雪只允许「敌方身上的 debuff」这种筛选,友方目标上筛选会被静默丢掉,那时画出来的是没筛过的一堆 —— 宁可不显示,也不能撒谎。")
    r:Slider("图标宽", 8, 120, "dotWidth", ns.ApplyLayout)
    r:Slider("图标高", 8, 120, "dotHeight", ns.ApplyLayout)
    r:Slider("倒计时字号", 8, 60, "dotFontSize", ns.ApplyLayout)
    r:Slider("图标间距", 0, 40, "dotSpacing", ns.ApplyLayout)
    r:Slider("离血条多远", -50, 50, "dotYOffset", ns.ApplyLayout)
    r:Note("⚠ 宽高不相等时图标会被拉伸(光环贴图本身是方的)。倒计时字号**不跟着图标走** —— 调完图标记得回来看一眼。")
    return f
end

local function resourceColorGet(nameFn)
    return function()
        local n = nameFn(); if not n then return nil end
        local d = DB()
        return ns.ColorFor(n, nil, d and d.powerColors)
    end
end

local function resourceColorSet(nameFn)
    return function(v)
        local n = nameFn(); if not n then return end
        local d = DB(); if not d then return end
        d.powerColors = d.powerColors or {}
        d.powerColors[n] = { v[1], v[2], v[3] }
        ns.ApplyLayout()
    end
end

-- ⚠ 资源颜色是**按资源名**存的(DB.powerColors["RunicPower"] / ["Mana"] …),不是一个全局色 ——
--   一个全局色会让"换个专精条就变色了"变成 bug。所以这两个色块要先问
--   "这根条现在画的是哪个资源",问不出来就画灰,并在下面那行说明原因。
local function BuildResourcePage()
    local f = Page("资源")
    local c = L(f)
    c:Header("主资源条")
    c:Check("显示主资源条", "powerOn",
        "当前专精的主资源(暗牧疯狂 / 骑士法力 / 血 DK 符文能量…),跟着专精和德鲁伊形态自动切换。⚠ 它同时是整叠 HUD 的锚点盒子 —— 关掉时这一格会塌成 1px,上下两根靠拢。",
        function() ns.ApplyLayout(); ns.RefreshAvailability() end)
    c:Check("条上叠数字", "powerNumber", "", ns.ApplyLayout)
    c:Slider("条高", 4, 200, "powerHeight", ns.ApplyLayout)
    local mainName = function() return ns.MainResourceName() end
    c:Color("主资源颜色", resourceColorGet(mainName), resourceColorSet(mainName))
    local mainNote = c:NoteBox(2)
    local function refreshMainNote()
        local n = ns.MainResourceName()
        mainNote:SetText(n and ("现在这根画的是:|cffffcc00" .. n .. "|r(颜色按资源分别存)")
            or "|cffff3333现在探测不到主资源|r —— 颜色改不了(换个专精 / 变个形再看)。")
    end
    refreshMainNote(); Refreshers[#Refreshers + 1] = refreshMainNote
    -- 🔴 上面那个「显示主资源条」是**全账号一份** —— 在血 DK 上关掉,暗牧的疯狂条
    --    也一起没了,而那看起来像 bug。颜色早就是按资源存的,显隐一直没跟上。
    c:CheckFn(function()
            local n = ns.MainResourceName()
            return n and ("单独显示 " .. n) or "单独显示(现在探测不到)"
        end,
        function()
            local n = ns.MainResourceName(); if not n then return nil end
            return not ns.IsResHidden(n)
        end,
        function(v)
            local n = ns.MainResourceName(); if n then ns.SetResHidden(n, not v) end
        end,
        "只管**这一种**资源。换个职业/专精不受影响 —— 存的是资源名,不是一个全局开关。")

    do local get, set = ticksIO("powerTicks"); c:Edit("刻度(百分比,逗号分隔)", 200, get, set) end
    c:Note("⚠ 跟血条那条一样是**静态几何**:主资源的值是 secret,插件读不到、也不许拿它做比较 —— 条的长度自己就是百分比,刻度只是给你眼睛用的参照。")

    local r = R(f)
    r:Header("次要资源条")
    r:Check("显示次要资源条", "secondaryOn",
        "圣能 / 连击点 / 灵魂碎片 / 真气 / 符文 / 奥术充能 / 精华这类「数颗数」的资源,画成一排格子。没有这类资源的专精不会占位置。",
        function() ns.ApplyLayout(); ns.RefreshAvailability() end)
    r:Slider("条高", 4, 200, "secondaryHeight", ns.ApplyLayout)
    r:Slider("格与格之间的缝", 0, 40, "segGap", ns.ApplyLayout)
    r:Note("⚠ 缝是**算在总宽里**的 —— 一排格子加起来仍然等于其它条的长度,所以缝调大了每格就变细。")
    local secName = function() return ns.SecondaryName() end
    r:Color("次要资源颜色", resourceColorGet(secName), resourceColorSet(secName))
    local secNote = r:NoteBox(2)
    local function refreshSecNote()
        local n = ns.SecondaryName()
        secNote:SetText(n and ("现在这排画的是:|cffffcc00" .. n .. "|r")
            or "|cff808080这个专精没有离散资源(或者被 max<=12 那道防守挡了)。|r")
    end
    refreshSecNote(); Refreshers[#Refreshers + 1] = refreshSecNote
    r:CheckFn(function()
            local n = ns.SecondaryName()
            return n and ("单独显示 " .. n) or "单独显示(这专精没有)"
        end,
        function()
            local n = ns.SecondaryName(); if not n then return nil end
            return not ns.IsResHidden(n)
        end,
        function(v)
            local n = ns.SecondaryName(); if n then ns.SetResHidden(n, not v) end
        end,
        "只管**这一种**资源(血 DK 的符文 / 骑士的圣能 / 盗贼的连击点…)。上面那个「显示次要资源条」是全账号一份,这个不是。")

    r:Note("毁灭术的碎片会显示成「三颗半」—— 那半颗的进度也画得出来。符文按谁先冷却好排在前面。")
    return f
end

-- 这一页是本次改版的核心。0.13 起这排从**流式**改成**固定格位**,
-- 就是为了让下面这个编辑器里的「顺序」有地方生效 ——
-- 流式那版的左右顺序归暴雪按剩余时间算,我们连递都递不进去,
-- **你没法给一个顺序会自己变的东西排序。**
local function BuildSelfPage()
    local f = Page("自身增益")
    local c = L(f)
    c:Header("自身增益图标")
    c:Check("显示这一排", "cdsOn",
        "资源条**下方**那排:自己身上的重要 buff 还剩多久(骨盾这种常驻的也在里面)。",
        function() ns.ApplyLayout(); if ns.BoilingEvaluate then pcall(ns.BoilingEvaluate) end end)

    c:Header("盯哪几个 buff(按专精)")
    c:Note("勾 = 显示。取消勾选**不删配置、也不动名次**,勾回来还在原处。^ v 排左右顺序 —— 屏幕上从左到右就是这个顺序。")
    -- 🔴 沸点那一格**画在列表里**,当第 1 行,不能移不能删。
    --    0.13.1 把它做成了列表外一个单独的勾选框 —— 错了:屏幕上血 DK 是 7 个图标,
    --    而列表说"占 6/8 格"、里面的「1.」对应屏幕第 2 格 ⇒ **配置面板在撒谎**。
    --    Jerry 原话就是「15+3 那个 aura 不能动,其他的可以显示/隐藏、可以调左右位置」——
    --    「不能动」的意思是它在列表里、只是动不了,不是它不在列表里。
    -- ⚠ 开关只走 Boiling.lua 导出的动作,**不在这儿读写那个键**
    --    (它存的是 db.bpSlot.manualOff,缺席 = 开)—— 两份手写的判据必然会漂。
    c:AuraEditor("cds", ns.CD_SLOTS or 8, ns.CD_SLOTS or 8, true, nil, {
        icon  = 50842,        -- 血液沸腾:那一格画的就是它的图标
        -- ⚠ 这一行的宽度是固定的、而且**不换行**(换行会撑破行高)⇒ 长了就被静默截断。
        --    详细说明放 tooltip 里,行里只留名字 —— 第一版写成
        --    「沸点(15 秒 proc / 3 秒 echo)」,后面那个「(固定)」直接被切掉了。
        label = "沸点",
        tip   = "15 秒 proc 显绿、3 秒 echo 显红,都发光。它钉死在最左那格,其余图标顺次右移;取消勾选就把那一格收起来,其余图标左移一格。",
        eligible = function()
            if not ns.BoilingEligible then return false, "Boiling.lua 没加载" end
            return ns.BoilingEligible()
        end,
        get = function() return ns.BoilingSlotOn and ns.BoilingSlotOn() end,
        set = function(v) if ns.BoilingSetSlot then ns.BoilingSetSlot(v) end end,
    })

    local r = R(f)
    r:Header("大小 / 位置")
    r:Slider("图标宽", 8, 120, "cdWidth", ns.ApplyLayout)
    r:Slider("图标高", 8, 120, "cdHeight", ns.ApplyLayout)
    r:Slider("倒计时字号", 8, 60, "cdFontSize", ns.ApplyLayout)
    r:Slider("图标间距", 0, 40, "cdSpacing", ns.ApplyLayout)
    r:Slider("离资源条多远", -50, 100, "cdYOffset", ns.ApplyLayout)
    r:Note("⚠ 这排是**固定格位**:没挂的 buff 那一格空着(透明,看不见,但占地方)—— 换来的是每个图标的位置永远不动。想省地方就把不看的那几个取消勾选。")
    r:Note("⚠ 格子摆得比条长时会探出去(自绘不裁)。血 DK 内置 6 个 + 沸点格 = 7 格,32px 图标约 238px,而条宽默认 260。")
    return f
end

local function BuildRaidPage()
    local f = Page("团队增益")
    local c = L(f)
    c:Header("别人给我的增益")
    c:Check("显示这个网格", "raidOn",
        "血条**右上角**那个 2xN 网格:左上第一格专给嗜血一族(空着也占住),其余格子装能量灌注 / 外部保命这些。",
        ns.ApplyLayout)
    -- 🔴 这两排**没有** ^ v。它们是暴雪排序的流式网格(sortMethod = Expiration),
    --    顺序不归我们管 —— 给一个点了不会有任何变化的按钮,比不给更坏。
    -- ⚠ 长说明挪去右列了:这一列装两个编辑器已经贴着面板底边,
    --   而 canvas 页超出的部分是**被裁掉且不报错**的。
    c:Header("嗜血那一格")
    c:AuraEditor("lust", 10, nil, false, 3)
    c:Header("其余团队增益")
    c:AuraEditor("raid", 30, nil, false, 5)

    local r = R(f)
    r:Header("大小 / 排布")
    r:Slider("图标宽", 8, 120, "raidWidth", ns.ApplyLayout)
    r:Slider("图标高", 8, 120, "raidHeight", ns.ApplyLayout)
    r:Slider("倒计时字号", 8, 60, "raidFontSize", ns.ApplyLayout)
    r:Slider("图标间距", 0, 40, "raidSpacing", ns.ApplyLayout)
    r:Slider("离血条多远", -50, 200, "raidXOffset", ns.ApplyLayout)
    r:Slider("每排几个", 1, 8, "raidCols", ns.ApplyLayout, " 个")
    r:Note("|cffff8800改「每排几个」之后要 /reload|r —— 那个值只在建组的时候读一次,不重载的话屏幕上不会变(而那看起来像滑条没接上)。")
    r:Note("网格总容量 = 每排几个 x 2,其中**左上第一格归嗜血**,团队增益实际拿到剩下那些。")
    r:Note("|cff808080这两张表是全职业一份 —— 别人给你的东西跟你什么专精无关,所以它们不按专精分。|r")
    r:Note("⚠ 这两排**单人验不出来** —— 嗜血要有人放、能量灌注要另一个牧师。「我没看见它」在单人环境下永远分不清「ID 填错」和「没人给我放」。左边两张表列出 ID + 法术名,名字查不到会显示红字,那是唯一能当场核对的手段。")
    return f
end

-- 🔑 施法条是整叠里**唯一能做真逻辑**的一根:自己的施法信息全明文
--    (谓词按单位判,"被查的不是玩家本人或其宠物"才 secret)。血量和资源那两根只能画、不能算。
local function BuildCastPage()
    local f = Page("施法引导")
    local c = L(f)
    c:Header("施法 / 引导条")
    c:Check("显示这根条", "castOn",
        "整叠最下面那根,画自己的施法和引导。0.12 把它挪到最下,因为它是唯一「框体一直在、内容时有时无」的东西 —— 夹在中间时那条地平时空着,却把下面所有东西往下推一整条。",
        ns.ApplyLayout)
    c:Slider("条高", 4, 200, "castHeight", ns.ApplyLayout)
    c:Color("施法颜色", colorGet("castColor"), colorSet("castColor", ns.ApplyLayout))
    c:Color("引导颜色", colorGet("chanColor"), colorSet("chanColor", ns.ApplyLayout))
    c:Note("引导是**反向排空**的(从满到空),跟施法正好相反 —— 两个颜色分开就是为了一眼认出现在是哪种。")
    c:Check("引导时打印读数(排查用)", "castDebug",
        "每次引导往聊天框打一行:实际时长 / 基础时长 / modRate / 当前跳数。平时别开。", nil)

    local r = R(f)
    r:Header("引导跳数")
    r:Note("🔴 **没有任何 API 给得出「这个引导几跳」** —— 整份 UnitDocumentation 里没有 numTicks/tickPeriod 这类字段,暴雪自己的施法条也只给**充能**法术画段,连最主流的 Quartz 都是硬编码的。所以只能你看一眼实际节奏,定一次。")
    r:Note("⚠ 没校准过的法术**不画刻度** —— 画错的刻度比不画更坏:它教你一个错的节奏,而且看起来完全像个正经功能。")
    local chanLabel = r:NoteBox(2)
    local chanTop = r:take(28)
    local chanEdit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    chanEdit:SetPoint("TOPLEFT", r.x + 6, chanTop)
    chanEdit:SetSize(60, 22)
    chanEdit:SetAutoFocus(false)
    chanEdit:SetNumeric(true)
    local chanMsg = r:NoteBox(2)

    local function refreshChan()
        local id, name
        if ns.LastChannel then id, name = ns.LastChannel() end
        local d = DB()
        if not id then
            chanLabel:SetText("|cff808080还没见过任何引导 —— 先引导一次(比如精神鞭笞),再回来这儿填跳数。|r")
            chanEdit:Hide()
            return
        end
        chanEdit:Show()
        chanLabel:SetFormattedText("最后那个引导:|cffffcc00%s|r (id=%d),它现在几跳:",
            tostring(name or "?"), id)
        chanEdit:SetText(tostring((d and d.chanTicks and d.chanTicks[id]) or ""))
    end
    chanEdit:SetScript("OnEnterPressed", function(self2)
        local id = ns.LastChannel and (ns.LastChannel())
        local n = tonumber(self2:GetText())
        self2:ClearFocus()
        local d = DB()
        if not (id and d) then return end
        if n and n >= 1 and n <= 30 then
            d.chanTicks = d.chanTicks or {}
            d.chanTicks[id] = n
            chanMsg:SetText(("|cff33ff33定成 %d 跳|r,下次引导就按这个等分。"):format(n))
        else
            chanMsg:SetText("|cffff3333要填 1-30 之间的整数。|r")
        end
        refreshChan()
    end)
    chanEdit:SetScript("OnEscapePressed", function(self2) self2:ClearFocus(); refreshChan() end)
    refreshChan(); Refreshers[#Refreshers + 1] = refreshChan
    r:Note("|cff808080也可以用 /dch chan 4 —— 跟这儿是同一个东西。|r")
    return f
end

---------------------------------------------------------------------------------------------------
-- 注册
---------------------------------------------------------------------------------------------------

function ns.RegisterOptions()
    if ns.OptionsRegistered then return end
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end

    -- 整段裹 pcall:Settings API 哪天改了形状,**HUD 本身不许跟着倒** ——
    -- /dch 那套命令是完整的后路,面板只是它的皮。
    local ok, err = pcall(function()
        local main = BuildMainPage()
        category = Settings.RegisterCanvasLayoutCategory(main, "DodoCombatHUD")

        BuildTargetPage(); BuildResourcePage(); BuildSelfPage()
        BuildRaidPage(); BuildCastPage()

        -- ⚠ 子页**必须在 RegisterAddOnCategory 之前**全挂完 —— 先注册再挂,
        --   挂上去的那几页不会出现在左边的树里(而且不报错)。
        for i = 2, #pages do
            Settings.RegisterCanvasLayoutSubcategory(category, pages[i], pages[i].name)
        end

        Settings.RegisterAddOnCategory(category)
        ns.OptionsCategory = category

        -- 🔴 页面只建**一次**,而专精 / 主资源 / 最后那个引导都会变 ⇒ 每次打开都重刷。
        --    **每一页都要挂,不能只挂主页** —— 点左边树是**直接进子页**的,主页压根不 Show。
        --    只挂主页的话,那些"按专精重刷"在正常使用路径上一次都不会跑,
        --    而它在开发时看着完全正常(因为你总是先打开主页)。
        for _, p in ipairs(pages) do
            p:HookScript("OnShow", function()
                for _, fn in ipairs(Refreshers) do pcall(fn) end
            end)
        end

        -- 🔴 canvas 页不滚动 ⇒ 超出面板高度的控件被裁掉,**而且不报错**。
        --    真实高度只有运行时知道(中文断行 + 界面缩放),所以这一条只能在这儿查。
        --    ⚠ 只在**加载时吵一次**,不是每次 OnShow —— 每次吵等于没吵。
        for _, p in ipairs(pages) do
            for _, cc in ipairs(p.cols) do
                if cc.deepest < FLOOR then
                    print(("|cffff66ccDodoCombatHUD|r |cffff8800「%s」页有一列排到了 %d,"
                        .. "超过面板高度(%d)—— 下面那几个控件会被裁掉。|r")
                        :format(p.name, math.floor(cc.deepest), FLOOR))
                end
            end
        end
    end)

    if not ok then
        print("|cffff66ccDodoCombatHUD|r 设置面板没建起来(/dch 照常可用):" .. tostring(err))
    end
    ns.OptionsRegistered = ok or nil
end
