-- Options.lua — ESC → 选项 → 插件 → DodoXuefei。一页,四个控件。
--
-- ── 为什么是游标式布局(页面里一个 y 坐标都没有)──
-- DodoCombatHUD 0.13.0 每个控件手写 y,真机一跑**满屏文字互相压**。根因不是
-- "坐标算错了",是这个方法**结构上**不成立:说明文字的高度取决于它换行成几行,
-- 而那要等到运行时(中文断行 + 玩家的界面缩放 + 字体)才知道 ——
-- 手写 y 等于替一个你算不出来的量猜一个常数。canon:能靠结构保证的别靠算式保证。
-- ⇒ `Col:take(h)` 摆一个控件 y 自己往下走;`Note` 摆完当场 `GetStringHeight()` 量真高度。
--
-- ── 🔴 面板不许自己读写存档 ──
-- 「显示」存的是 `manualOff`(缺席 = 显示),尺寸有 clamp、有三个消费方。
-- 面板照直觉写一个 `on`、或者自己钳一遍范围,两份判据当场分叉,
-- 而症状是「勾选框/滑条和屏幕上那格对不上」—— 谁也看不出来是两份实现。
-- ⇒ 这个文件里**没有一处**碰 `DodoXuefeiDB`,全走 Core.lua 导出的动作。

local ADDON, ns = ...

local category, page
local Refreshers = {}
-- 刷新**只有一份实现**:面板自己点了、斜杠命令改了、打开面板,全走它。
-- 各写一遍的话它们迟早在"改完要刷哪些"上分叉,而症状是「用命令改了、面板上没跟着变」。
local function RefreshAll()
    for _, fn in ipairs(Refreshers) do pcall(fn) end
end
local COL_L  = 16
local COL_W  = 480
local FLOOR  = -545            -- canvas 页不滚动,超了下面的控件会被**静默**裁掉

local function GetVersion()
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return (meta and meta(ADDON, "Version")) or "?"
end

---------------------------------------------------------------------------------------------------
-- 游标
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

function Col:Header(text)
    local fs = self.p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetText(text)
    fs:SetTextColor(1, 0.82, 0)
    fs:SetPoint("TOPLEFT", self.x, self:take(26))
    return fs
end

-- 🔴 高度**当场量**,不写常数。`GetStringHeight()` 要在 SetWidth + SetText **之后**读 ——
--    顺序反了会读到 0,而那表现成"下一个控件压上来",跟没量一模一样。
function Col:Note(text, width)
    local fs = self.p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetWidth(width or COL_W)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    local h = math.max(12, math.ceil((fs:GetStringHeight() or 0) + 0.5))
    fs:SetPoint("TOPLEFT", self.x, self:take(h + 8))
    return fs
end

-- 内容会变的说明行(「现在为什么不显示」)。文字一换高度就变,而它下面还有控件
-- ⇒ **必须预留固定行数**,不能当场量。少这一步的症状:换个专精下面的控件整片跳。
function Col:NoteBox(lines)
    local fs = self.p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetWidth(COL_W)
    fs:SetJustifyH("LEFT")
    fs:SetPoint("TOPLEFT", self.x, self:take((lines or 1) * 14 + 8))
    return fs
end

-- 勾选框。get/set 是**动作**,不是键名(见文件头那条)。
function Col:Check(label, get, set, tooltip)
    local c = CreateFrame("CheckButton", nil, self.p, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c:SetPoint("TOPLEFT", self.x, self:take(26))
    local fs = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", c, "RIGHT", 2, 0)
    fs:SetText(label)
    local function refresh() c:SetChecked(get() and true or false) end
    refresh()
    c:SetScript("OnClick", function(self2)
        set(self2:GetChecked() and true or false)
        RefreshAll()                       -- 一处改动可能让别处的说明行也变
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

-- 一个数值设置 = 滑条 + 数字输入框,**两个控件一个值**。宽 / 高 / 透明度共用这一份。
--
-- 🔴 唯一的写入口是 `ns.SetNum`,上下限只在 Core 的 `SPEC` 里声明一次。
--    两个控件各自写存档的话,它们会各自钳一遍范围、各自决定"空串算什么" ——
--    两份单独看都对,漂了没人读得出来(canon:同一不变式两份手写实现 = 静默分歧发生器)。
--    ⇒ 这儿谁都不写存档:改 → 交给 SetNum → **回读**刷新两个控件。
--    回读那一步同时兜住"被钳住了"和"输入被拒":框里显示的永远是真正存进去的值。
function Col:Num(label, key, unit)
    local lo, hi = ns.NumBounds(key)
    local top = self:take(44)

    local s = CreateFrame("Slider", nil, self.p)
    s:SetSize(200, 16)
    s:SetPoint("TOPLEFT", self.x, top - 18)
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
    lab:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3)
    lab:SetText(label)

    local e = CreateFrame("EditBox", nil, self.p, "InputBoxTemplate")
    e:SetPoint("TOPLEFT", self.x + 224, top - 16)
    e:SetSize(46, 20)
    e:SetAutoFocus(false)
    e:SetNumeric(true)                 -- 挡住非数字,少一整类脏输入
    e:SetMaxLetters(3)
    local unitFS = self.p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    unitFS:SetPoint("LEFT", e, "RIGHT", 4, 0)
    unitFS:SetText((unit or "px") .. "  (" .. lo .. "–" .. hi .. ")")

    -- ⚠ `SetValue` 自己也会触发 OnValueChanged ⇒ 回读时必须挡住,否则
    --   刷新→写入→刷新 无限套娃(而且每一圈都重算一次布局)。
    local suppress = false
    local shown                        -- 上一次**我们**渲染出去的文本
    local function refresh()
        local v = ns.GetNum(key) or lo
        suppress = true
        s:SetValue(v)
        suppress = false
        shown = tostring(v)
        e:SetText(shown)
    end
    local function push(v)
        ns.SetNum(key, v)              -- 拒收 / 钳住都由它决定
        refresh()                      -- 回读:框里显示真正存进去的那个值
    end
    refresh()

    s:SetScript("OnValueChanged", function(_, v)
        if suppress then return end
        push(math.floor(v + 0.5))
    end)
    -- 🔴 没改过就别提交。DodoCombatHUD 0.13.0 无条件挂 OnEditFocusLost ⇒
    --    面板一开一关的焦点事件就提交一次,而空串是"合法输入" ⇒ 一次误提交
    --    静默把值写坏,还自我固化。canon:宽容的默认值会替 bug 遮丑。
    local function commit()
        local txt = e:GetText() or ""
        e:ClearFocus()
        if txt == shown then return end
        push(txt)
    end
    e:SetScript("OnEnterPressed", commit)
    e:SetScript("OnEditFocusLost", commit)
    e:SetScript("OnEscapePressed", function() e:ClearFocus(); refresh() end)

    Refreshers[#Refreshers + 1] = refresh
    return s, e
end

---------------------------------------------------------------------------------------------------
-- 页面
---------------------------------------------------------------------------------------------------
local function BuildPage()
    local f = CreateFrame("Frame")
    f.name = "DodoXuefei"
    page = f
    local c = NewCol(f, COL_L)
    f.col = c

    c:Header("DodoXuefei  v" .. GetVersion())
    c:Note("血 DK「沸点」监视。屏幕上一格血液沸腾的图标:" ..
           "|cff33ff33绿 = 沸点 proc(15 秒)|r,|cffff5555红 = 那一发自动血沸还有几秒落地(3 秒)|r。" ..
           "有红显红、没红有绿显绿,两种都发光。没 proc 的时候整格是透明的。")

    c:Check("显示", ns.IsSlotShown, ns.SetSlotShown,
            "取消 = 完全关掉,而且不会再自动出现;想要回来在这儿勾上,或者 /dxf on。")

    -- 「现在为什么不显示」。🔴 一个不出现的东西必须**说出为什么** ——
    -- 不解释的话「这个专精没有沸点」和「插件坏了」在屏幕上长得一模一样。
    local status = c:NoteBox(2)
    Refreshers[#Refreshers + 1] = function()
        local why = ns.WhyNotShown()
        if why then status:SetText("|cffff8800现在不显示:|r" .. why)
        else status:SetText("|cff33ff33现在会显示。|r") end
    end

    c:Check("解锁移动", ns.IsUnlocked, ns.SetUnlocked,
            "解锁时那一格会画出蓝色边框和「拖动」两个字 —— 直接拖它换位置。摆好回来取消勾选。")
    c:Note("解锁期间它**无视专精和天赋**先显示出来,好让你在任何角色上都摆得了位置;" ..
           "取消勾选就按正常规矩来。锁着的时候那一格|cff33ff33不吃鼠标|r,不会挡住你点身后的东西。")

    c:Check("边框", ns.IsBorderOn, ns.SetBorderOn,
            "暴雪自己给 debuff 画的那张边框(atlas ui-debuff-border-default-noicon)。"
            .. "它比图标大 1/3、往外探出一圈 —— 暴雪原生就是这个比例,不是画大了。")

    c:Num("宽", "width", "px")
    c:Num("高", "height", "px")
    c:Note("滑条和右边那个框是**同一个值**,改哪个都行,当场生效。" ..
           "⚠ 战斗中改的话外框会马上变、图标要等脱战才补上 —— 暴雪不让插件在战斗里碰光环图标。")

    c:Num("不触发时的透明度", "idleAlpha", "%")
    c:Note("没 proc 的时候那一格画一张|cff33ff33灰掉的|r血液沸腾图标,好让你一眼看出"
           .. "「它在,只是还没亮」。这条调的就是那张灰图有多淡。"
           .. "|cffffff00调到 0 = 不触发时干脆不画|r(就是 1.0 那个行为)。")

    c:Note("|cff808080拖丢了?/dxf pos 位置回默认。它怎么不出现?/dxf why 会把每一环都打出来。|r")
    return f
end

function ns.RegisterOptions()
    if ns.OptionsRegistered then return end
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end

    -- 整段裹 pcall:Settings API 哪天改了形状,**插件本身不许跟着倒** ——
    -- /dxf 那套命令是完整的后路,面板只是它的皮。
    local ok, err = pcall(function()
        local f = BuildPage()
        category = Settings.RegisterCanvasLayoutCategory(f, "DodoXuefei")
        Settings.RegisterAddOnCategory(category)
        ns.OptionsCategory = category

        -- 页面只建**一次**,而专精 / 天赋会变 ⇒ 每次打开都重刷那行状态。
        f:HookScript("OnShow", function() RefreshAll() end)

        -- 🔴 canvas 页不滚动 ⇒ 超出面板高度的控件被裁掉,**而且不报错**。
        --    真实高度只有运行时知道(中文断行 + 界面缩放),所以这一条只能在这儿查。
        --    ⚠ 只在加载时吵一次,不是每次 OnShow —— 每次吵等于没吵。
        if f.col.deepest < FLOOR then
            print(("|cffff66ccDodoXuefei|r |cffff8800面板排到了 %d,超过可用高度(%d)"
                .. " —— 下面那几个控件会被裁掉。|r"):format(math.floor(f.col.deepest), FLOOR))
        end
    end)
    if ok then
        ns.OptionsRegistered = true
    else
        print("|cffff66ccDodoXuefei|r |cffff3333面板注册失败|r:" .. tostring(err)
              .. "  —— 用 /dxf 那套命令,功能不受影响。")
    end
end

-- 给 Core 用:斜杠命令改了状态之后,让开着的面板跟上 ——
-- 少这一步的症状是「/dxf off 关掉了,而面板上那个勾还亮着」,两个入口各说各话。
ns.RefreshOptions = RefreshAll
