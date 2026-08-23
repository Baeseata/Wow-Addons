-- DodoCombatHUD - Options.lua
-- ESC → 选项 → 插件 → DodoCombatHUD。一个主页 + 五个子页,**按屏幕上那一块切**,
-- 不按「开关 / 尺寸」切:一个东西的开关、大小、颜色、盯哪几个法术全在同一页。
-- (0.12 那版是分层切的 —— 调一个东西要在两页之间来回跳,而且"它在哪一页"没有判据。)
--
--   主页     全局:位置 / 条宽 / 缝 / 背景 / 材质 / 三个按钮
--   目标     目标血条 + 它上面那排 DoT 图标
--   资源     主资源条 + 次要资源条
--   自身增益 资源条下方那排(**图形化编辑**:按专精、显隐、排顺序)+ 沸点专格
--   团队增益 血条右上角那个网格(嗜血 + 别人给的)
--   施法引导 最下面那根 + 引导跳数
--
-- ── 为什么是 canvas 页,不是 0.12 那套 RegisterVerticalLayoutCategory ──
--
-- 🔴 老版本这儿写着「这套 Settings API 只造得出 checkbox / slider / dropdown / colorswatch,
--    没有任何文本输入 ⇒ DoT 法术 ID / 刻度 / 引导跳数**结构上**进不了面板」。
--    **那条是错的**(2026-08-23 扒 Blizzard_SettingControls.lua 的导出表核实的):
--    它还有 CreateSettingsButtonInitializer(按钮)、ExpandableSection(可折叠小节)
--    和四种组合控件;而且 `Settings.RegisterCanvasLayoutSubcategory(父category, 自建frame, 名字)`
--    让你**自己建框体**,爱放什么放什么。别再照那句话下"做不到"的结论。
--
-- 选 canvas 的实际理由是这三样在 vertical-layout 里装不下:
--   ① 法术表的图形化编辑(图标 + 名字 + 显隐 + 上下移 + 删)
--   ② 刻度 / 引导跳数这类要**打字**的东西
--   ③ 「解锁拖动 / 演示模式 / 回默认」这三个本来就该是按钮
-- 代价照实记:**canvas 页里的控件进不了设置面板那个搜索框**。认了 ——
-- 本机九个 Dodo 插件(Grid / Nameplate / Cursor / Numbers / Says / Map / Quest /
-- GatherMate / Guanzhu)全都是 canvas,这是家里的房规,不是这次拍脑袋。
--
-- ⚠ canvas 页**不滚动**:内容超出面板高度就是被裁掉,而且不报错。所以每页排成两列,
--   左列 x=16 右列 x=352,纵向别超过 ~540。加东西前先数一眼。
--
-- ⚠ 页面只建**一次**,而专精会变 ⇒ 凡按专精画的东西都挂 OnShow 重刷(见 Refreshers)。

local ADDON, ns = ...

local category
local Refreshers = {}          -- 打开面板时要重跑的刷新函数(专精可能已经变了)

local LEFT, RIGHT = 16, 352
local SLIDER_W = 200

local function DB() return DodoCombatHUDDB end

-- 版本号从 TOC 现读,不在这儿写第二份 —— 写死的那份迟早跟真实 build 漂。
local function GetVersion()
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return (meta and meta(ADDON, "Version")) or "?"
end

---------------------------------------------------------------------------------------------------
-- 控件工厂(形状照抄本机在产的 DodoGrid / DodoNameplate,不自创第二套写法)
---------------------------------------------------------------------------------------------------

local function Header(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    fs:SetTextColor(1, 0.82, 0)
    return fs
end

local function Note(parent, text, x, y, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    fs:SetWidth(width or 320)
    fs:SetText(text)
    return fs
end

-- 🔴 读值一律展开写成 `d[key] ~= false`,**别用 `d and d[k] ~= false or default`** ——
--    值确实是 false 时那个惯用法会走进 `or` 那支、把默认值(true)端回来,症状是
--    「我关掉的开关,下次打开面板又勾上了」。DodoInspect 在同族写法上栽过一次。
local function MakeCheck(parent, label, x, y, key, tooltip, apply)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetPoint("TOPLEFT", x, y)
    c:SetSize(24, 24)
    local fs = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", c, "RIGHT", 2, 0)
    fs:SetText(label)
    local function refresh()
        local d = DB()
        if d then c:SetChecked(d[key] ~= false) else c:SetChecked(ns.DEFAULTS[key] ~= false) end
    end
    refresh()
    c:SetScript("OnClick", function(self)
        local d = DB(); if not d then return end
        d[key] = self:GetChecked() and true or false
        if apply then apply() end
    end)
    if tooltip and tooltip ~= "" then
        c:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    Refreshers[#Refreshers + 1] = refresh
    return c
end

-- 整数像素滑条。步进恒为 1:这些量全是像素,小数没有意义,而带小数的读数
-- 会让人以为它比实际更精细。
local function MakeSlider(parent, label, x, y, lo, hi, key, apply, unit)
    local s = CreateFrame("Slider", nil, parent)
    s:SetPoint("TOPLEFT", x, y)
    s:SetSize(SLIDER_W, 16)
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
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        val:SetText(v .. suffix)
        local d = DB(); if not d then return end
        -- ⚠ 只在**真的变了**的时候 apply:SetValue 自己也会触发这个回调,
        --   不挡的话打开面板就会把整套布局重算一遍(还会盖掉别处刚改的值)。
        if d[key] ~= v then d[key] = v; if apply then apply() end end
    end)
    Refreshers[#Refreshers + 1] = refresh
    return s
end

local function MakeButton(parent, text, x, y, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(w or 120, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function Page(name)
    local f = CreateFrame("Frame")
    f.name = name
    return f
end

-- 色块。get 返回 {r,g,b[,a]} 数组(存档里就是这个形状),set 收同样的形状。
-- ⚠ 用 ColorPickerFrame:SetupColorPickerAndShow —— 这是 DodoNameplate 在产的写法。
--   别去手搓老的 OpenColorPicker 那套(它在 11.x 改过一次形状)。
local function MakeColor(parent, label, x, y, get, set, hasAlpha)
    local b = CreateFrame("Button", nil, parent)
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(18, 18)
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
        local c = get() or { 1, 1, 1 }
        tex:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1)
        -- 取不到这个资源时(比如换了专精)把块画灰 + 点不动。
        -- 🔴 「点不动」和「说出为什么」必须一起做:只变灰的话它读起来像"坏了"。
        b:SetEnabled(get() ~= nil)
        tex:SetDesaturated(get() == nil)
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

-- 单行文本输入,回车或失焦提交(照抄 DodoGrid 的 MakeEdit)。
-- 🔴 提交完**回读一次**:输入被拒 / 被规整过时,框里必须显示**真正存进去的那个值**。
--    少这一步的话,框里留着你打的字、而生效的是别的 —— 那种"看起来生效了"最费时间。
local function MakeEdit(parent, label, x, y, w, get, set)
    local lab = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lab:SetPoint("TOPLEFT", x, y)
    lab:SetText(label)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetPoint("TOPLEFT", x + 6, y - 16)
    e:SetSize(w or 180, 22)
    e:SetAutoFocus(false)
    local function refresh() e:SetText(get() or "") end
    refresh()
    local function commit()
        set(e:GetText() or "")
        e:ClearFocus()
        refresh()
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

---------------------------------------------------------------------------------------------------
-- 图形化法术表编辑器
--
-- 一行 = 一格:[图标] [显示勾] [格号. 法术名 (ID)] [▲] [▼] [✕]
--
-- 🔴 「显示勾」和「✕ 删除」是**两件事**,必须都给:
--      · 取消勾选 = 我暂时不想看,**配置和名次都留着**,勾回来还在原处
--      · ✕        = 从表里移除(内置表的话,想找回来只能整张「回内置」)
--    只给删除的话,玩家为了"这次不看"会去删,然后再也排不回原来的顺序。
--
-- 🔴 列的是**配置表**(ns.AuraList),不是可见表 —— 隐藏的那几行必须还在列表里,
--    否则你再也勾不回来。HUD 那侧才用 VisibleAuraList。
--
-- ⚠ 行是**池化**的:页面只建一次,而列表长度随专精变。多出来的行 Hide 掉,
--   不重建框体(战斗中建框体会被拒,而面板完全可能在战斗中打开)。
---------------------------------------------------------------------------------------------------

local ROW_H = 22

-- reorder = 这一排的左右顺序**由我们决定**吗?
--   · dots / cds  = 固定格位,第 N 个 ID 就在第 N 格 ⇒ true,给 ^ v
--   · lust / raid = 暴雪排序的流式网格(sortMethod = Expiration)⇒ **false**
-- 🔴 lust/raid 那两排绝不能给 ^ v:那是一个**点了不会有任何变化**的控件。
--    canon:「你按不动的东西要挡住并说出原因」,而"给了却没用"比不给更坏 ——
--    它会让人以为自己排错了,反复去调一个根本不生效的东西。
local function MakeAuraEditor(parent, x, y, kind, maxRows, cap, reorder, visibleRows)
    local rows = {}
    local refresh

    local status = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", x, y)
    status:SetJustifyH("LEFT"); status:SetWidth(300)

    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
    note:SetPoint("TOPLEFT", x, y - 16)
    note:SetJustifyH("LEFT"); note:SetWidth(300)

    -- ⚠ canvas 页自己**不滚动**,而团队增益内置 23 个 —— 直接铺开会被面板裁掉,
    --   而且不报错。所以行统一装进一个 ScrollFrame:短表看不出区别,长表能滚。
    local shownRows = math.min(visibleRows or maxRows, maxRows)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", x, y - 32)
    scroll:SetSize(300, shownRows * ROW_H)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(300, maxRows * ROW_H)
    scroll:SetScrollChild(child)

    local function spec() return ns.CurrentSpec() end
    local function perSpec() return ns.PER_SPEC[kind] ~= nil end
    local function listNow() return ns.AuraList(DB(), kind, spec()) end

    -- 存回去 + 推 filter + 重画。三件事必须一起 ——
    -- 只存不推的话屏幕上什么都不变,而那看起来像"面板没接上"。
    local function commitList(list)
        if not ns.SetAuraList(DB(), kind, spec(), list) then
            note:SetText("|cffff3333现在问不出当前专精,这一排改不了。|r")
            return false
        end
        ns.ApplyAuraFilters()
        refresh()
        return true
    end

    local function makeRow(i)
        local top = -(i - 1) * ROW_H
        local r = {}

        r.icon = child:CreateTexture(nil, "ARTWORK")
        r.icon:SetPoint("TOPLEFT", 0, top - 1)
        r.icon:SetSize(18, 18)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- 削掉暴雪图标那圈自带边框

        r.check = CreateFrame("CheckButton", nil, child, "UICheckButtonTemplate")
        r.check:SetPoint("TOPLEFT", 20, top)
        r.check:SetSize(22, 22)
        r.check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("显示这一格", 1, 1, 1)
            GameTooltip:AddLine("取消勾选 = 不占格位,但配置和名次都留着,勾回来还在原处。想彻底删掉用右边那个 x。", nil, nil, nil, true)
            GameTooltip:Show()
        end)
        r.check:SetScript("OnLeave", function() GameTooltip:Hide() end)

        r.text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("TOPLEFT", 46, top - 4)
        r.text:SetJustifyH("LEFT")
        r.text:SetWidth(reorder and 184 or 230)

        local function tinyBtn(dx, label)
            local b = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
            b:SetPoint("TOPLEFT", dx, top)
            b:SetSize(20, 18)
            b:SetText(label)
            return b
        end
        if reorder then
            r.up   = tinyBtn(232, "^")
            r.down = tinyBtn(254, "v")
            r.up:SetScript("OnClick", function()
                local l = listNow(); if ns.ListMove(l, i, -1) then commitList(l) end
            end)
            r.down:SetScript("OnClick", function()
                local l = listNow(); if ns.ListMove(l, i, 1) then commitList(l) end
            end)
        end
        r.del = tinyBtn(276, "x")
        r.del:SetScript("OnClick", function()
            local l = listNow()
            local id = l[i]; if not id then return end
            -- 删的同时把它的「隐藏」标记也清掉。留着的话以后 add 回同一个 ID 时
            -- 它会莫名其妙不显示,而屏幕上完全看不出为什么。
            ns.SetAuraHidden(DB(), kind, spec(), id, false)
            ns.ListRemove(l, id)
            commitList(l)
        end)
        r.check:SetScript("OnClick", function(self)
            local id = listNow()[i]; if not id then return end
            ns.SetAuraHidden(DB(), kind, spec(), id, not self:GetChecked())
            ns.ApplyAuraFilters()
            refresh()
        end)
        return r
    end

    for i = 1, maxRows do rows[i] = makeRow(i) end

    local addY = y - 40 - shownRows * ROW_H
    local addBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    addBox:SetPoint("TOPLEFT", x + 6, addY)
    addBox:SetSize(84, 22)
    addBox:SetAutoFocus(false)
    addBox:SetNumeric(true)

    local function doAdd()
        local id = tonumber(addBox:GetText())
        addBox:SetText(""); addBox:ClearFocus()
        if not id or id <= 0 then
            note:SetText("|cffff3333要填一个 spellID(正整数)。|r")
            return
        end
        local l = listNow()
        for i = 1, #l do
            if l[i] == id then note:SetText("|cffff8800" .. id .. " 已经在里面了。|r") return end
        end
        -- 🔴 固定格位那两排有硬上限:超出的格子**没有容器**,多填的 ID 会静默消失 ——
        --    "我明明加了却没出现"跟"ID 填错了"在屏幕上分不开。必须挡住并说清楚。
        if cap and #l >= cap then
            note:SetText(("|cffff3333已经 %d 个,满了(上限 %d 格)—— 先删掉或取消勾选一个。|r")
                :format(#l, cap))
            return
        end
        if #l >= maxRows then
            note:SetText(("|cffff3333这个编辑器最多列 %d 行,再多就只能用 /dch 改了。|r"):format(maxRows))
            return
        end
        ns.ListAdd(l, id)
        if commitList(l) then note:SetText("已加入:" .. ns.SpellLabel(id)) end
    end
    addBox:SetScript("OnEnterPressed", doAdd)
    addBox:SetScript("OnEscapePressed", function() addBox:SetText(""); addBox:ClearFocus() end)

    MakeButton(parent, "添加", x + 96, addY + 1, 50, doAdd)
    MakeButton(parent, "回内置", x + 152, addY + 1, 66, function()
        if not ns.ResetAuraList(DB(), kind, spec()) then
            note:SetText("|cffff3333现在问不出当前专精,这一排改不了。|r")
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
        r.icon:Hide(); r.check:Hide(); r.text:Hide(); r.del:Hide()
        if r.up then r.up:Hide(); r.down:Hide() end
    end

    refresh = function()
        local d = DB()
        local sp = spec()
        -- 🔴 按专精那两排,specID 问不出来时**说人话**,别画一张空列表 ——
        --    空列表跟"这个专精本来就没有"长得一模一样,而两者的下一步完全不同。
        if perSpec() and sp == nil then
            status:SetText("|cffff3333现在问不出当前专精|r —— 这一排暂时改不了(切一下专精 / 重登)。")
            for i = 1, maxRows do hideRow(rows[i]) end
            addBox:Hide()
            return
        end
        addBox:Show()

        local list, custom = ns.AuraList(d, kind, sp)
        local vis = #(ns.VisibleAuraList(d, kind, sp))
        local head = custom and "|cffffcc00你自己配的|r" or "内置表"
        if cap then
            status:SetFormattedText("%s —— 占 %d / %d 格%s", head, vis, cap,
                (#list > vis) and ("(另有 " .. (#list - vis) .. " 个没勾,不占格)") or "")
        else
            status:SetFormattedText("%s —— %d 个%s", head, #list,
                (#list > vis) and ("(其中 " .. (#list - vis) .. " 个没勾)") or "")
        end
        -- ⚠ 列表比编辑器能列的还长时**要说出来**。canon:静默截断读起来跟"全都在"
        --   一模一样,而这里恰恰是"我配的那个怎么不见了"最容易发生的地方。
        if #list > maxRows then
            note:SetText(("|cffff8800还有 %d 个没列出来(这个编辑器最多 %d 行)—— 用 /dch 看全部。|r")
                :format(#list - maxRows, maxRows))
        end
        child:SetHeight(math.max(shownRows, #list) * ROW_H)

        for i = 1, maxRows do
            local r = rows[i]
            local id = list[i]
            if not id then
                hideRow(r)
            else
                local hidden = ns.IsAuraHidden(d, kind, sp, id)
                local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
                r.icon:SetTexture(tex or 134400)          -- 134400 = 问号图标
                r.icon:SetDesaturated(hidden)
                r.icon:Show()
                r.check:SetChecked(not hidden); r.check:Show()
                -- 序号 = 格号(固定格位那两排);名字查不到就红字 —— 那是填错 ID 唯一看得见的地方。
                r.text:SetFormattedText("%s%d. %s  |cff808080(%d)|r",
                    hidden and "|cff707070" or "", i, ns.SpellLabel(id), id)
                r.text:Show()
                if r.up then
                    -- 🔴 第一格的 ^ 和最后一格的 v 必须**点不动**,不是点了没反应。
                    r.up:SetEnabled(i > 1); r.up:Show()
                    r.down:SetEnabled(i < #list); r.down:Show()
                end
                r.del:Show()
            end
        end
    end

    Refreshers[#Refreshers + 1] = refresh
    refresh()
    -- 编辑器整体占多高 —— 调用方拿它接着往下摆,别在外面手算(算错了就是控件叠在一起)。
    return addY - 30
end

---------------------------------------------------------------------------------------------------
-- 主页:全局(位置 / 尺寸 / 配色 / 材质 / 按钮)
---------------------------------------------------------------------------------------------------

local function colorGet(key) return function() local d = DB(); return d and d[key] end end
local function colorSet(key, apply)
    return function(v) local d = DB(); if d then d[key] = v; if apply then apply() end end end
end

local function BuildMainPage()
    local f = Page("DodoCombatHUD")
    Header(f, "DodoCombatHUD  v" .. GetVersion(), LEFT, -12)
    Note(f, "屏幕上从上到下:目标 DoT 图标 / 目标血条 / 主资源条 / 次要资源条 / 自身增益图标 / 施法引导条。左边每一页管其中一块。", LEFT, -38, 640)

    MakeCheck(f, "锁定位置", LEFT, -76, "locked",
        "取消勾选就能拖。血条 / 主资源 / 施法条**哪根都能抓**(次要资源那排格子抓不动,它太薄)。摆好记得勾回来。",
        ns.ApplyLayout)

    local testBtn
    testBtn = MakeButton(f, ns.IsTestMode() and "演示模式:开" or "演示模式:关", LEFT, -104, 130, function()
        testBtn:SetText(ns.ToggleTest() and "演示模式:开" or "演示模式:关")
    end)
    MakeButton(f, "回默认位置和尺寸", LEFT + 140, -104, 150, function()
        ns.ResetGeometry()
        for _, fn in ipairs(Refreshers) do pcall(fn) end
    end)
    Note(f, "演示模式把两根条填上假数据,方便摆位置(它不写存档,关掉就没了)。", LEFT, -132, 320)

    MakeSlider(f, "所有条的长度", LEFT, -176, 40, 1200, "width", ns.ApplyLayout)
    Note(f, "全部同宽,一个值管到底 —— 次要资源那排格子加起来也等于这个长度(缝算在里面)。", LEFT, -200, 320)
    MakeSlider(f, "条与条之间的缝", LEFT, -240, 0, 100, "gap", ns.ApplyLayout)

    Header(f, "配色", RIGHT, -70)
    MakeColor(f, "条背景", RIGHT, -96, colorGet("bgColor"), colorSet("bgColor", ns.ApplyLayout), true)
    Note(f, "第四个通道是不透明度 —— 调到 1 就能把身后的场景完全隔断。", RIGHT, -118, 280)
    MakeColor(f, "刻度线", RIGHT, -150, colorGet("tickColor"), colorSet("tickColor", ns.ApplyLayout), true)

    Header(f, "材质", RIGHT, -186)
    MakeEdit(f, "主资源条", RIGHT, -212, 260,
        function() local d = DB(); return d and d.powerTexture end,
        function(v) local d = DB(); if d then d.powerTexture = v; ns.ApplyLayout() end end)
    MakeEdit(f, "血条 / 施法条", RIGHT, -256, 260,
        function() local d = DB(); return d and d.barTexture end,
        function(v) local d = DB(); if d then d.barTexture = v; ns.ApplyLayout() end end)
    Note(f, "可以填 atlas 名(暴雪自己就这么用)或者 Interface\\... 路径。两个分开是刻意的:主资源要暴雪原生那张自带配色的图,血条要一张素图才染得干净。", RIGHT, -300, 280)

    MakeCheck(f, "藏掉暴雪自己的施法条", RIGHT, -350, "hideBlizzCast",
        "我们那根是自绘的,两根一起显示纯属打架。⚠ 取消勾选会把暴雪那根恢复一次,之后就撒手 —— 你自己用编辑模式关掉它的话,我们不会再打开它。",
        function() ns.ApplyLayout(); ns.ApplyBlizzCastBar(true) end)

    Note(f, "|cff808080全部设置也能用 /dch 改(面板做不到的都在那儿)。|r", LEFT, -290, 320)
    return f
end

---------------------------------------------------------------------------------------------------
-- 子页 ①「目标」:目标血条 + 它上面那排 DoT 图标
---------------------------------------------------------------------------------------------------

local function BuildTargetPage()
    local f = Page("目标")
    Header(f, "目标血条", LEFT, -12)
    MakeCheck(f, "显示目标血条", LEFT, -38, "healthOn",
        "中间那根。⚠ 关掉它,上面那排 DoT 图标会跟着不显示 —— 它们锚在血条上沿。",
        ns.ApplyLayout)
    MakeCheck(f, "条上叠血量数字", LEFT, -64, "healthNumber",
        "默认关:BOSS 血量是八位数,噪音大于信息。", ns.ApplyLayout)
    MakeSlider(f, "血条高度", LEFT, -106, 4, 200, "healthHeight", ns.ApplyLayout)
    MakeColor(f, "血条颜色", LEFT, -136, colorGet("healthColor"),
        colorSet("healthColor", ns.ApplyLayout))

    MakeEdit(f, "刻度(百分比,逗号分隔)", LEFT, -168, 200,
        function() local d = DB(); return d and TicksToText(d.healthTicks) end,
        function(v)
            local t = TextToTicks(v); local d = DB()
            if t and d then d.healthTicks = t; ns.ApplyLayout() end
        end)
    Note(f, "默认 20 = 暗言术:灭 的斩杀线。⚠ 刻度是**静态几何**,不是按血量算的 —— 12.x 里血量是 secret,插件读不到也算不了,只能给你画一条线用眼睛比。填了非法值整条不收,框里会退回原值。", LEFT, -212, 320)

    Header(f, "目标 DoT 图标", RIGHT, -12)
    MakeCheck(f, "显示这一排", RIGHT, -38, "dotsOn",
        "血条左上角,我打在目标身上的 DoT + 倒计时。**固定格位** —— 掉了哪个就空哪一格,后面的不会左移。",
        ns.ApplyLayout)
    Note(f, "⚠ 目标是友方或者没目标时这排会整个收起来:暴雪只允许「敌方身上的 debuff」这种筛选,友方目标上筛选会被静默丢掉,那时画出来的是没筛过的一堆 —— 宁可不显示,也不能撒谎。", RIGHT, -66, 280)

    MakeSlider(f, "图标宽", RIGHT, -130, 8, 120, "dotWidth", ns.ApplyLayout)
    MakeSlider(f, "图标高", RIGHT, -166, 8, 120, "dotHeight", ns.ApplyLayout)
    MakeSlider(f, "倒计时字号", RIGHT, -202, 8, 60, "dotFontSize", ns.ApplyLayout)
    MakeSlider(f, "图标间距", RIGHT, -238, 0, 40, "dotSpacing", ns.ApplyLayout)
    MakeSlider(f, "离血条多远", RIGHT, -274, -50, 50, "dotYOffset", ns.ApplyLayout)
    Note(f, "⚠ 宽高不相等时图标会被拉伸(光环贴图本身是方的)。倒计时字号**不跟着图标走** —— 调完图标记得回来看一眼。", RIGHT, -300, 280)

    Header(f, "盯哪几个法术", LEFT, -262)
    MakeAuraEditor(f, LEFT, -288, "dots", ns.DOT_SLOTS or 4, ns.DOT_SLOTS or 4, true)
    return f
end

---------------------------------------------------------------------------------------------------
-- 子页 ②「资源」:主资源条 + 次要资源条
--
-- ⚠ 颜色是**按资源名**存的(DB.powerColors["Insanity"] / ["Mana"] …),不是一个全局色 ——
--   一个全局色会让"换个专精条就变色了"变成 bug。所以这两个色块要先问
--   "这根条现在画的是哪个资源",问不出来就画灰 + 说明原因。
---------------------------------------------------------------------------------------------------

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

local function BuildResourcePage()
    local f = Page("资源")
    Header(f, "主资源条", LEFT, -12)
    MakeCheck(f, "显示主资源条", LEFT, -38, "powerOn",
        "当前专精的主资源(暗牧疯狂 / 骑士法力 / 猫德能量…),跟着专精和德鲁伊形态自动切换。⚠ 它同时是整叠 HUD 的锚点盒子 —— 关掉时这一格会塌成 1px,上下两根靠拢。",
        function() ns.ApplyLayout(); ns.RefreshAvailability() end)
    MakeCheck(f, "条上叠数字", LEFT, -64, "powerNumber", "", ns.ApplyLayout)
    MakeSlider(f, "条高", LEFT, -106, 4, 200, "powerHeight", ns.ApplyLayout)

    local mainName = function() return ns.MainResourceName() end
    MakeColor(f, "主资源颜色", LEFT, -136, resourceColorGet(mainName), resourceColorSet(mainName))
    local mainNote = Note(f, "", LEFT, -158, 320)
    local function refreshMainNote()
        local n = ns.MainResourceName()
        mainNote:SetText(n and ("现在这根画的是:|cffffcc00" .. n .. "|r(颜色按资源分别存)")
            or "|cffff3333现在探测不到主资源|r —— 颜色改不了(换个专精 / 变个形再看)。")
    end
    refreshMainNote(); Refreshers[#Refreshers + 1] = refreshMainNote

    MakeEdit(f, "刻度(百分比,逗号分隔)", LEFT, -190, 200,
        function() local d = DB(); return d and TicksToText(d.powerTicks) end,
        function(v)
            local t = TextToTicks(v); local d = DB()
            if t and d then d.powerTicks = t; ns.ApplyLayout() end
        end)
    Note(f, "⚠ 跟血条那条一样是**静态几何**:主资源的值是 secret,插件读不到、也不许拿它做比较 —— 条的长度自己就是百分比,刻度只是给你眼睛用的参照。", LEFT, -234, 320)

    Header(f, "次要资源条", RIGHT, -12)
    MakeCheck(f, "显示次要资源条", RIGHT, -38, "secondaryOn",
        "圣能 / 连击点 / 灵魂碎片 / 真气 / 符文 / 奥术充能 / 精华这类「数颗数」的资源,画成一排格子。没有这类资源的专精不会占位置。",
        function() ns.ApplyLayout(); ns.RefreshAvailability() end)
    MakeSlider(f, "条高", RIGHT, -80, 4, 200, "secondaryHeight", ns.ApplyLayout)
    MakeSlider(f, "格与格之间的缝", RIGHT, -116, 0, 40, "segGap", ns.ApplyLayout)
    Note(f, "⚠ 缝是**算在总宽里**的 —— 一排格子加起来仍然等于其它条的长度,所以缝调大了每格就变细。", RIGHT, -142, 280)

    local secName = function() return ns.SecondaryName() end
    MakeColor(f, "次要资源颜色", RIGHT, -180, resourceColorGet(secName), resourceColorSet(secName))
    local secNote = Note(f, "", RIGHT, -202, 280)
    local function refreshSecNote()
        local n = ns.SecondaryName()
        secNote:SetText(n and ("现在这排画的是:|cffffcc00" .. n .. "|r")
            or "|cff808080这个专精没有离散资源(或者被 max<=12 那道防守挡了)。|r")
    end
    refreshSecNote(); Refreshers[#Refreshers + 1] = refreshSecNote
    Note(f, "毁灭术的碎片会显示成「三颗半」—— 那半颗的进度也画得出来。符文按谁先冷却好排在前面。", RIGHT, -228, 280)
    return f
end

---------------------------------------------------------------------------------------------------
-- 子页 ③「自身增益」:资源条下方那排 + 沸点专格
--
-- 这一页是本次改版的核心。0.13 起这排从**流式**改成**固定格位**,
-- 就是为了让下面这个编辑器里的「顺序」有地方生效 ——
-- 流式那版的左右顺序归暴雪按剩余时间算,我们连递都递不进去,
-- **你没法给一个顺序会自己变的东西排序。**
---------------------------------------------------------------------------------------------------

local function BuildSelfPage()
    local f = Page("自身增益")
    Header(f, "自身增益图标", LEFT, -12)
    MakeCheck(f, "显示这一排", LEFT, -38, "cdsOn",
        "资源条**下方**那排:自己身上的重要 buff 还剩多久(骨盾这种常驻的也在里面)。",
        function() ns.ApplyLayout(); if ns.BoilingEvaluate then pcall(ns.BoilingEvaluate) end end)

    -- 沸点专格。⚠ 它不是 DB 顶层的一个键 ⇒ 不能用 MakeCheck,得自己接。
    local bpCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    bpCheck:SetPoint("TOPLEFT", LEFT, -64)
    bpCheck:SetSize(24, 24)
    local bpLabel = bpCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bpLabel:SetPoint("LEFT", bpCheck, "RIGHT", 2, 0)
    bpLabel:SetText("血 DK:沸点专格(最左那格)")
    local bpNote = Note(f, "", LEFT + 24, -86, 300)
    local function refreshBp()
        if not ns.BoilingEligible then
            bpCheck:SetEnabled(false); bpCheck:SetChecked(false)
            bpNote:SetText("|cff808080Boiling.lua 没加载。|r")
            return
        end
        local ok, why = ns.BoilingEligible()
        bpCheck:SetEnabled(ok)
        bpCheck:SetChecked(ok and ns.BoilingSlotOn() or false)
        -- 🔴 点不动的时候必须说出为什么 —— 一个变灰又不解释的勾选框读起来像"坏了"。
        bpNote:SetText(ok
            and "15 秒 proc 显绿、3 秒 echo 显红,都发光。它**位置固定**在最左,其余图标顺次右移。"
            or ("|cff808080" .. (why or "现在用不上") .. "。|r"))
    end
    bpCheck:SetScript("OnClick", function(self)
        if ns.BoilingSetSlot then ns.BoilingSetSlot(self:GetChecked() and true or false) end
        refreshBp()
    end)
    refreshBp(); Refreshers[#Refreshers + 1] = refreshBp

    Header(f, "盯哪几个 buff(按专精)", LEFT, -116)
    Note(f, "勾 = 显示。取消勾选**不删配置、也不动名次**,勾回来还在原处。^ v 排左右顺序 —— 屏幕上从左到右就是这个顺序。", LEFT, -140, 320)
    MakeAuraEditor(f, LEFT, -178, "cds", ns.CD_SLOTS or 8, ns.CD_SLOTS or 8, true)

    Header(f, "大小 / 位置", RIGHT, -12)
    MakeSlider(f, "图标宽", RIGHT, -44, 8, 120, "cdWidth", ns.ApplyLayout)
    MakeSlider(f, "图标高", RIGHT, -80, 8, 120, "cdHeight", ns.ApplyLayout)
    MakeSlider(f, "倒计时字号", RIGHT, -116, 8, 60, "cdFontSize", ns.ApplyLayout)
    MakeSlider(f, "图标间距", RIGHT, -152, 0, 40, "cdSpacing", ns.ApplyLayout)
    MakeSlider(f, "离资源条多远", RIGHT, -188, -50, 100, "cdYOffset", ns.ApplyLayout)
    Note(f, "⚠ 这排是**固定格位**:没挂的 buff 那一格空着(透明,看不见,但占地方)—— 换来的是每个图标的位置永远不动。想省地方就把不看的那几个取消勾选。", RIGHT, -216, 280)
    Note(f, "⚠ 格子摆得比条长时会探出去(自绘不裁)。血 DK 内置 6 个 + 沸点格 = 7 格,32px 图标约 238px,而条宽默认 260。", RIGHT, -268, 280)
    return f
end

---------------------------------------------------------------------------------------------------
-- 子页 ④「团队增益」:血条右上角那个 2×N 网格
---------------------------------------------------------------------------------------------------

local function BuildRaidPage()
    local f = Page("团队增益")
    Header(f, "别人给我的增益", LEFT, -12)
    MakeCheck(f, "显示这个网格", LEFT, -38, "raidOn",
        "血条**右上角**那个 2xN 网格:左上第一格专给嗜血一族(空着也占住,不跟任何东西抢位置),其余格子装能量灌注 / 外部保命这些。",
        ns.ApplyLayout)
    Note(f, "⚠ 这两排**单人验不出来** —— 嗜血要有人放、能量灌注要另一个牧师。「我没看见它」在单人环境下永远分不清「ID 填错」和「没人给我放」。下面两张表列出 ID + 法术名,名字查不到会显示红字,那是唯一能当场核对的手段。", LEFT, -66, 320)

    -- 🔴 这两排**没有** ^ v。它们是暴雪排序的流式网格(sortMethod = Expiration),
    --    顺序不归我们管 —— 给一个点了不会有任何变化的按钮,比不给更坏:
    --    它会让人以为自己排错了,反复去调一个根本不生效的东西。
    Header(f, "嗜血那一格", LEFT, -136)
    -- 行是**预建**的(池化)⇒ maxRows 直接决定登录时建多少框体。
    -- 内置 7 个,给到 10 留点余量就够;再多的用 /dch lust add。
    MakeAuraEditor(f, LEFT, -162, "lust", 10, nil, false, 4)

    Header(f, "其余团队增益", LEFT, -300)
    -- 内置 23 个,给到 30。⚠ 别为了"以防万一"往大了写:每行 4 个框体,
    -- 这一个数字就能让登录时多建上百个框体,而它平时完全看不出来。
    MakeAuraEditor(f, LEFT, -326, "raid", 30, nil, false, 6)

    Header(f, "大小 / 排布", RIGHT, -12)
    MakeSlider(f, "图标宽", RIGHT, -44, 8, 120, "raidWidth", ns.ApplyLayout)
    MakeSlider(f, "图标高", RIGHT, -80, 8, 120, "raidHeight", ns.ApplyLayout)
    MakeSlider(f, "倒计时字号", RIGHT, -116, 8, 60, "raidFontSize", ns.ApplyLayout)
    MakeSlider(f, "图标间距", RIGHT, -152, 0, 40, "raidSpacing", ns.ApplyLayout)
    MakeSlider(f, "离血条多远", RIGHT, -188, -50, 200, "raidXOffset", ns.ApplyLayout)
    MakeSlider(f, "每排几个", RIGHT, -224, 1, 8, "raidCols", ns.ApplyLayout, " 个")
    Note(f, "|cffff8800改「每排几个」之后要 /reload|r —— 那个值只在建组的时候读一次,不重载的话屏幕上不会变(而那看起来像滑条没接上)。", RIGHT, -252, 280)
    Note(f, "网格总容量 = 每排几个 x 2,其中**左上第一格归嗜血**,团队增益实际拿到剩下那些。", RIGHT, -300, 280)
    Note(f, "|cff808080这两张表是全职业一份 —— 别人给你的东西跟你什么专精无关,所以它们不按专精分。|r", RIGHT, -340, 280)
    return f
end

---------------------------------------------------------------------------------------------------
-- 子页 ⑤「施法引导」:最下面那根 + 引导跳数
--
-- 🔑 这是整叠里**唯一能做真逻辑**的一根:自己的施法信息全明文(谓词按单位判,
--    "被查的不是玩家本人或其宠物"才 secret)。血量和资源那两根只能画、不能算。
---------------------------------------------------------------------------------------------------

local function BuildCastPage()
    local f = Page("施法引导")
    Header(f, "施法 / 引导条", LEFT, -12)
    MakeCheck(f, "显示这根条", LEFT, -38, "castOn",
        "整叠最下面那根,画自己的施法和引导。0.12 把它挪到最下,因为它是唯一「框体一直在、内容时有时无」的东西 —— 夹在中间时那条地平时空着,却把下面所有东西往下推一整条。",
        ns.ApplyLayout)
    MakeSlider(f, "条高", LEFT, -80, 4, 200, "castHeight", ns.ApplyLayout)
    MakeColor(f, "施法颜色", LEFT, -112, colorGet("castColor"), colorSet("castColor", ns.ApplyLayout))
    MakeColor(f, "引导颜色", LEFT, -140, colorGet("chanColor"), colorSet("chanColor", ns.ApplyLayout))
    Note(f, "引导是**反向排空**的(从满到空),跟施法正好相反 —— 两个颜色分开就是为了一眼认出现在是哪种。", LEFT, -168, 320)

    MakeCheck(f, "引导时打印读数(排查用)", LEFT, -212, "castDebug",
        "每次引导往聊天框打一行:实际时长 / 基础时长 / modRate / 当前跳数。平时别开。", nil)

    Header(f, "引导跳数", RIGHT, -12)
    Note(f, "🔴 **没有任何 API 给得出「这个引导几跳」** —— 整份 UnitDocumentation 里没有 numTicks/tickPeriod 这类字段,暴雪自己的施法条也只给**充能**法术画段,连最主流的 Quartz 都是硬编码的。所以只能你看一眼实际节奏,定一次。", RIGHT, -38, 280)
    Note(f, "⚠ 没校准过的法术**不画刻度** —— 画错的刻度比不画更坏:它教你一个错的节奏,而且看起来完全像个正经功能。", RIGHT, -122, 280)

    local chanLabel = Note(f, "", RIGHT, -172, 280)
    local chanEdit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    chanEdit:SetPoint("TOPLEFT", RIGHT + 6, -196)
    chanEdit:SetSize(60, 22)
    chanEdit:SetAutoFocus(false)
    chanEdit:SetNumeric(true)
    local chanMsg = Note(f, "", RIGHT, -224, 280)

    local function refreshChan()
        local id, name = nil, nil
        if ns.LastChannel then id, name = ns.LastChannel() end
        local d = DB()
        if not id then
            chanLabel:SetText("|cff808080还没见过任何引导 —— 先引导一次(比如精神鞭笞),再回来这儿填跳数。|r")
            chanEdit:Hide()
            return
        end
        chanEdit:Show()
        chanLabel:SetFormattedText("最后那个引导:|cffffcc00%s|r  (id=%d),它现在几跳:",
            tostring(name or "?"), id)
        chanEdit:SetText(tostring((d and d.chanTicks and d.chanTicks[id]) or ""))
    end
    chanEdit:SetScript("OnEnterPressed", function(self)
        local id = ns.LastChannel and select(1, ns.LastChannel())
        local n = tonumber(self:GetText())
        self:ClearFocus()
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
    chanEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); refreshChan() end)
    refreshChan(); Refreshers[#Refreshers + 1] = refreshChan

    Note(f, "|cff808080也可以用 /dch chan 4 —— 跟这儿是同一个东西。|r", RIGHT, -260, 280)
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

        local pages = { main,
            BuildTargetPage(), BuildResourcePage(), BuildSelfPage(),
            BuildRaidPage(), BuildCastPage() }

        -- ⚠ 子页**必须在 RegisterAddOnCategory 之前**全挂完 —— 先注册再挂,
        --   挂上去的那几页不会出现在左边的树里(而且不报错)。
        for i = 2, #pages do
            Settings.RegisterCanvasLayoutSubcategory(category, pages[i], pages[i].name)
        end

        Settings.RegisterAddOnCategory(category)
        ns.OptionsCategory = category

        -- 🔴 页面只建**一次**,而专精 / 主资源 / 最后那个引导都会变 ⇒ 每次打开都重刷。
        --    少这一步的症状是"面板里显示的是上次登录时那个专精的表",而它读起来
        --    完全像"我配的东西丢了"。
        --
        -- 🔴 **每一页都要挂,不能只挂主页** —— 点左边树是**直接进子页**的,主页压根不 Show。
        --    只挂主页的话,那些"按专精重刷"在正常使用路径上一次都不会跑,
        --    而它在开发时看着完全正常(因为你总是先打开主页)。
        --    canon:「我这条验收路径,把那段新代码执行到了吗」。
        for _, p in ipairs(pages) do
            p:HookScript("OnShow", function()
                for _, fn in ipairs(Refreshers) do pcall(fn) end
            end)
        end
    end)

    if not ok then
        print("|cffff66ccDodoCombatHUD|r 设置面板没建起来(/dch 照常可用):" .. tostring(err))
    end
    ns.OptionsRegistered = ok or nil
end
