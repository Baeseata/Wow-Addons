-- DodoGuanzhu :: Options.lua
-- ESC → 选项 → 插件 → DodoGuanzhu:方案下拉 + 名单(有序)+ 两个开关 + 长度计 + 写宏按钮。
--
-- 骨架照抄 DodoShield/Options.lua(ScrollFrame + 行池 + 多方案下拉 + StaticPopup)。
-- 抄一份久经考验的先例,真正的工作量是列出**哪几处必须不一样**,这里有三处:
--   ① DodoShield 每次刷新都 SortRows(它按时间排);这里的顺序**就是优先级本身**,
--      排序等于改语义 ⇒ 行序只能由 ▲▼ 改,任何地方都不许 sort。
--   ② 多一个「录入模式」,一开就得**把整个设置窗关掉** —— 玩家要去点 3D 世界里的人,
--      面板铺在屏幕中间他就点不到。这是功能阻塞不是审美问题,省掉这步等于录入不能用。
--   ③ 写宏这个动作**战斗中客户端直接拒**(CreateMacro/EditMacro 被 block),
--      所以按钮必须真的按不动 + 屏幕上常驻一行字说清为什么(见 reasonText)。
--
-- 面板**不缓存名单副本**,一律走 ns.Current()。缓存了就会在录入 / 斜杠命令改完之后显示旧值,
-- 而"显示旧值"跟"功能没生效"在屏幕上长得一模一样,是最费排查时间的那种坏法。

local ADDON, ns = ...

local panel, category
local listDropdown, delListBtn
local memberScroll, scrollContent
local captureBtn, focusCB, selfCB
local lengthText, writeBtn, reasonText, dirtyText
local mini                                  -- 录入模式的小浮窗(UIParent 的孩子,不是 panel 的)
local rowPool = {}

local ROW_H, ROW_W = 24, 380

-- 写宏按钮的标题只在这儿写一次:Refresh 里要给它套颜色码,同一串字面量抄两遍
-- 迟早只改一处,而症状是"按钮偶尔换个名字",没人会想到去对这个。
local WRITE_LABEL = "生成 / 更新宏"

local Refresh, RefreshRows, RefreshDropdown, SyncCapture   -- 前置声明,互相调用

---------------------------------------------------------------------------------------------------
-- 队伍名册 / 职业色
---------------------------------------------------------------------------------------------------

-- 存的名字可能带 "-服务器"(跨服),队伍里读回来的同服玩家**不带**后缀(实测 GetUnitName(u,true))。
-- 两边都砍到 "-" 之前再比 —— 同一队里两个同名跨服玩家会撞,但撞了的代价只是**一个错的职业色**,
-- 宏正文用的是存进去的那个字符串原样,不经过这儿。
-- 🔴 这里原本是 ns.NormalizeName 的**第四份**手写副本(剥服务器后缀,但不转小写)。
-- 今天不可达 —— roster 建表和查表用的是同一个它,内部自洽 —— 但那正是这类副本的危险之处:
-- 它不会出错,直到某天有人只改了另外三份中的一份。委托过去,调用点一个都不用动。
-- canon 判据:「这两份不一致了谁会发现?」答不出名字,就得让其中一份变成推导出来的。
local function ShortName(n)
    return ns.NormalizeName(n)
end

-- 扫一遍 player/party1-4/raid1-40 建 名字→unit 表。
-- 🔴 故意不用 GetNumGroupMembers/IsInRaid 收窄范围:那两个没在 12.1 实测过还给不给明文,
--    而 UnitExists / UnitIsPlayer / GetUnitName 是**实测过的明文**。45 次 UnitExists 只在刷新时跑,
--    省这点开销去赌一个没量过的 API,亏。
local function BuildRoster()
    local map = {}
    local function add(u)
        if UnitExists(u) and UnitIsPlayer(u) then
            local n = ShortName(GetUnitName(u, true))
            if n and not map[n] then map[n] = u end
        end
    end
    add("player")
    for i = 1, 4 do add("party" .. i) end
    for i = 1, 40 do add("raid" .. i) end
    return map
end

local function SafeRoster()
    local ok, map = pcall(BuildRoster)
    return ok and map or {}
end

-- unit → "|cffRRGGBB";拿不到就用灰。UnitClass 的第二个返回值("PRIEST" 这种)是明文。
local function ClassHex(unit)
    if not unit then return "ff808080" end
    local ok, _, class = pcall(UnitClass, unit)
    if not ok or not class then return "ffcccccc" end
    local c
    if C_ClassColor and C_ClassColor.GetClassColor then
        local ok2, col = pcall(C_ClassColor.GetClassColor, class)
        if ok2 then c = col end
    end
    if not c and RAID_CLASS_COLORS then c = RAID_CLASS_COLORS[class] end
    if not c or not c.r then return "ffcccccc" end
    -- %x 的参数先 floor 成整数:WoW 的 Lua 5.1 会自己截断,但那是"碰巧能跑"——
    -- 同一句在 5.4 上对非整数浮点直接抛错。写成不依赖版本的形状,比记住哪个版本宽容便宜。
    local function b(v) return math.floor((v or 0) * 255 + 0.5) end
    return string.format("ff%02x%02x%02x", b(c.r), b(c.g), b(c.b))
end

---------------------------------------------------------------------------------------------------
-- 邻居模块的探问(全部 pcall + 存在性检查)
-- 五个模块并行写出来的,加载顺序 / 有没有加载成功都不该由我假设。
-- 任何一个没在,面板要**降级成能用**并说出原因,不能整页崩掉。
---------------------------------------------------------------------------------------------------

local function CaptureOn()
    if not (ns.Capture and ns.Capture.IsOn) then return false end
    local ok, on = pcall(ns.Capture.IsOn)
    return (ok and on) and true or false
end

-- 宏正文长度(码位)。拿不到返回 nil ⇒ 调用方要按"不知道"处理,别当 0。
-- 🔴 `n <= 0` 一并收成 nil:**长度 0 的正文不存在** —— 最短的合法正文也是
--    首行的 #showtooltip 加一句 /cast 技能名,十几个码位起。所以 0 只可能是"没有正文"的另一种编码
--    (Macro.Length 的旧契约就返回 0)。在这唯一的入口收掉,下游就只需要认识 nil 一种"不知道",
--    而不是每个调用点各自记得"0 也算不知道" —— 那种约定漏一处就是屏幕上一个绿色的 0/255。
local function MacroLength()
    if not (ns.Macro and ns.Macro.Length) then return nil end
    local ok, n = pcall(ns.Macro.Length, ns.Current())
    if ok and type(n) == "number" and n > 0 then return n end
    return nil
end

-- 宏名(只给"写好了"那句反馈用)。拿不到就返回 nil ⇒ 调用方少说半句,
-- 别硬拼一个 "?" 出来充数:一个假的宏名会把玩家送去宏面板里找一个不存在的东西。
local function MacroNameNow()
    if not (ns.Macro and ns.Macro.MacroNameFor) then return nil end
    local ok, n = pcall(ns.Macro.MacroNameFor, ns.Current())
    return (ok and type(n) == "string" and n ~= "") and n or nil
end

-- 长度算不出来(Macro.Length 返回 nil)时,**为什么**算不出来。
-- 三种原因各说各的措辞 —— 一句话套所有情况,一定会在某一种上说假话。
-- ⚠ 这是**诊断**不是判据:真正拒绝写入的是 Macro.Write,我这儿只把它的沉默翻译成人话。
--    所以末尾留一支"原因不明" —— 万一 Macro 那边的判据哪天跟这儿漂了,宁可说不知道,
--    也别笃定地报一个错的原因(给错理由比不给更坏:它引着人去修一个没坏的地方)。
local function LengthUnknownWhy()
    if not (ns.Macro and ns.Macro.Length) then return "宏模块(Macro.lua)没加载" end
    -- 顺序照 Macro.BuildBody 的判断顺序来:先技能名,再名单。
    if not ns.SpellName() then return "还读不到「能量灌注」的技能名(没学会,或者刚登录还没加载完)" end
    -- 点名到人:只说"名单里有非法字符"等于让玩家自己去八个名字里翻。
    -- 🔴 校验一律走 ns.ValidateName —— Core 里那份**唯一**的规则。在这儿再手写一遍字符集
    --    就是 canon 说的静默分歧发生器:两份单独看都对,漂了没人读得出来。
    for i, name in ipairs(ns.Current().members) do
        local okName, why = ns.ValidateName(name)
        if not okName then
            return ("第 %d 位「%s」:%s"):format(i, tostring(name), why or "不合法")
        end
    end
    return "宏正文生成不出来(原因不明)"
end

-- 写宏为什么按不动。返回 nil = 可以按。
-- 一句话套所有情况会说出假话,所以每种原因各写各的措辞。
local function WriteBlockedReason()
    if not (ns.Macro and ns.Macro.Write) then
        return "宏模块(Macro.lua)没加载,写不了。"
    end
    if InCombatLockdown() then
        return "战斗中写不了宏:客户端直接 block CreateMacro / EditMacro。脱战后再按。"
    end
    if not ns.SpellName() then
        return "读不到「能量灌注」的技能名(没学会?)。宁可不写,也不写一个技能名是 nil 的宏。"
    end
    -- 长度算不出来 = BuildBody 返回了 nil = Write 走到那儿也必然拒 ⇒ 按钮**真的按不动**,
    -- 而不是让玩家按一下、再收一条红字。(上面三支已经把"模块没加载 / 技能名读不到"挑走了,
    -- 能走到这儿的 nil 基本就是名单里有拆坏宏条件的字符。)
    local n = MacroLength()
    if n == nil then
        -- 这儿**故意不重复**长度计那行的诊断:两行一字不差地并排红着,只是把面板刷成一片红,
        -- 而人会以为是两个毛病。分工 —— 长度计说"卡在哪一位",这行说"所以按不动"。
        -- ⚠ 成立的前提:走到这一支时长度计一定正在显示那句诊断(上面三支已经把
        --    模块没加载 / 战斗中 / 没技能名挑走了,剩下的 nil 两边读的是同一次 MacroLength)。
        return "生成不出宏正文,所以这颗按不动 —— 长度计那行写了是卡在哪一位。"
    end
    if n > ns.BODY_LIMIT then
        return ("宏正文 %d 码位,超上限 %d。超了会被**静默截断**成一个能用、但少几个人的宏 —— 零报错,"):format(n, ns.BODY_LIMIT)
            .. "所以这儿必须挡住。先删掉一两个人。"
    end
    return nil
end

---------------------------------------------------------------------------------------------------
-- 方案的增 / 改名 / 删(StaticPopup)
-- 弹窗 key 带 DODOGUANZHU_ 前缀:StaticPopupDialogs 是**全局共享表**,撞名就是改别人的弹窗。
---------------------------------------------------------------------------------------------------

local function AddList(name)
    name = (name or ""):match("^%s*(.-)%s*$")
    if name == "" then ns.Print("方案名不能是空的。"); return end
    if ns.ListByName(name) then ns.Print("已经有一个叫「" .. name .. "」的方案了。"); return end
    local db = ns.db
    db.lists[#db.lists + 1] = ns.NewList(name)
    db.editing = #db.lists
    ns.Changed()
end

local function RenameList(name)
    name = (name or ""):match("^%s*(.-)%s*$")
    if name == "" then ns.Print("方案名不能是空的。"); return end
    local exist, idx = ns.ListByName(name)
    if exist and idx ~= ns.db.editing then ns.Print("已经有一个叫「" .. name .. "」的方案了。"); return end
    ns.Current().name = name
    ns.Changed()
end

-- 删到只剩一个就停手:0 个方案时 ns.Current() 会返回 nil,而下游每一处都假设它有东西。
-- 与其让每个调用方各自防一遍,不如在这唯一的入口保证"永远至少一套"。
local function DeleteCurrentList()
    local db = ns.db
    if #db.lists <= 1 then ns.Print("只剩一个方案了,删不得。"); return end
    table.remove(db.lists, db.editing)
    db.editing = math.min(db.editing, #db.lists)
    ns.Changed()
end

StaticPopupDialogs["DODOGUANZHU_NEW_LIST"] = {
    text = "新方案叫什么?", button1 = "确定", button2 = "取消", hasEditBox = true,
    OnShow = function(self) self.editBox:SetText(""); self.editBox:SetFocus() end,
    OnAccept = function(self) AddList(self.editBox:GetText()) end,
    EditBoxOnEnterPressed = function(self) AddList(self:GetText()); self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["DODOGUANZHU_RENAME_LIST"] = {
    text = "改成什么名字?", button1 = "确定", button2 = "取消", hasEditBox = true,
    OnShow = function(self)
        self.editBox:SetText(ns.Current().name or "")
        self.editBox:HighlightText(); self.editBox:SetFocus()
    end,
    OnAccept = function(self) RenameList(self.editBox:GetText()) end,
    EditBoxOnEnterPressed = function(self) RenameList(self:GetText()); self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["DODOGUANZHU_DELETE_LIST"] = {
    text = "删掉当前方案?名单一起没。", button1 = "删", button2 = "算了",
    OnAccept = DeleteCurrentList,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

---------------------------------------------------------------------------------------------------
-- 名单行(行池)
--
-- 符号选择:▲ ▼ × 三个都在 GB2312 里,中文字体必有字形。
-- ⛔ 别用 ✖(U+2716)/ ✕(U+2715)那类装饰符号 —— 它们不在 GB2312/GBK 里,
--    中文客户端的字体不保证有字形,渲染出来是个空白方块,而"按钮上什么都没有"
--    看起来跟"按钮坏了"一模一样。这条没在游戏里实测,是按字符集覆盖挑的稳妥值。
---------------------------------------------------------------------------------------------------

local function CreateRow()
    local row = CreateFrame("Frame", nil, scrollContent)
    row:SetSize(ROW_W, ROW_H)
    row:EnableMouse(true)               -- FontString 收不了鼠标,灰名字的 tooltip 只能挂在行上

    row.idx = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.idx:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.idx:SetWidth(22)
    row.idx:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row, "LEFT", 32, 0)
    row.name:SetWidth(246)
    row.name:SetJustifyH("LEFT")

    row.del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.del:SetSize(24, 20)
    row.del:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.del:SetText("×")

    row.down = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.down:SetSize(24, 20)
    row.down:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
    row.down:SetText("▼")

    row.up = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.up:SetSize(24, 20)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
    row.up:SetText("▲")

    row:SetScript("OnEnter", function(self)
        if not self.warn then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.who or "", 1, 1, 1)
        GameTooltip:AddLine("这人不在你的队伍/团队里。", 1, 0.4, 0.4)
        GameTooltip:AddLine("宏里的 @名字 只在队伍/团队范围内解析得成 unit ——", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("不在队伍时那一段条件判假,会直接跳到下一个人。", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("名字留着没坏处(进了队就自动生效),只是现在不顶用。", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function GetRow(i)
    if not rowPool[i] then rowPool[i] = CreateRow() end
    return rowPool[i]
end

-- 交换两行 = 改优先级。改完广播,让预览 / 长度计一起跟上。
local function Swap(i, j)
    local m = ns.Current().members
    if not m[i] or not m[j] then return end
    m[i], m[j] = m[j], m[i]
    ns.Changed()
end

RefreshRows = function()
    if not scrollContent then return end
    local L = ns.Current()
    local roster = SafeRoster()

    for _, r in pairs(rowPool) do r:Hide() end

    for i, name in ipairs(L.members) do
        local r = GetRow(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, -(i - 1) * ROW_H)
        r:Show()

        local unit = roster[ShortName(name)]
        r.who, r.warn = name, (unit == nil)
        r.idx:SetText(i .. ".")
        -- 不在队伍的,除了变灰还**明写**一行后缀:变灰本身有歧义(禁用?离线?),
        -- 而 tooltip 只在鼠标已经放上去时才说话 —— 不知道有这回事的人永远不会放上去。
        if unit then
            r.name:SetText("|c" .. ClassHex(unit) .. name .. "|r")
        else
            r.name:SetText("|cff808080" .. name .. "|r |cff666666· 不在队伍|r")
        end

        r.up:SetEnabled(i > 1)
        r.down:SetEnabled(i < #L.members)
        local idx = i
        r.up:SetScript("OnClick", function() Swap(idx, idx - 1) end)
        r.down:SetScript("OnClick", function() Swap(idx, idx + 1) end)
        r.del:SetScript("OnClick", function()
            table.remove(ns.Current().members, idx)
            ns.Changed()
        end)
    end

    scrollContent:SetHeight(math.max(1, #L.members * ROW_H))
end

---------------------------------------------------------------------------------------------------
-- 录入模式的小浮窗
--
-- 为什么必须有它:录入靠玩家去点 3D 世界里的角色,而设置面板是一整块铺在屏幕中间的东西 ——
-- 面板开着就点不到人。所以录入一开,先把整个设置窗**关掉**,只留这个小窗。
-- 🔴 它是 UIParent 的孩子,不是 panel 的 —— 挂在 panel 下面的话,设置窗一关它跟着没,
--    那就等于没做。
-- 「加当前目标」这个按钮是兜一个具体的坑:玩家想加的人**已经是他的目标**时,
--    再点一次不会产生"目标变了"这件事,靠事件驱动的录入就收不到 ⇒ 得给一条手动的路。
---------------------------------------------------------------------------------------------------

-- 🔴 调 Capture.AddTarget 而不是自己 UnitExists 一遍再 AddUnit("target"):
--    那边已经写了同一套校验 + 提示语。同一条不变式手写两份 = 静默分歧发生器 ——
--    两份单独看都对,哪天它那边改了判据(比如加个"不能收自己"),我这份还照旧,
--    而两条路径给出的拒绝理由会不一样,没人分得清哪个是真的。
local function AddTargetNow()
    if not (ns.Capture and ns.Capture.AddTarget) then ns.Print("录入模块(Capture.lua)没加载。"); return end
    pcall(ns.Capture.AddTarget)
end

local function BuildMini()
    local f = CreateFrame("Frame", "DodoGuanzhuCaptureWindow", UIParent, "BackdropTemplate")
    -- 高度按**最长**那句提示留,不是按默认那句:默认那句剩下的余量是一条没人声明过的
    -- 安全带,加一句两行的提示就吃光了,而后果是文字压在下面两颗按钮上(看着像坏了)。
    f:SetSize(260, 132)
    f:SetPoint("TOP", UIParent, "TOP", 0, -160)   -- 顶上,别挡住屏幕中间那片要点的地方
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    -- 位置故意**不存盘**:这个窗只在录入那几十秒里存在,存位置是多一份没人维护的状态。
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
        })
        f:SetBackdropColor(0, 0, 0, 0.88)
        f:SetBackdropBorderColor(0.35, 0.7, 1, 0.9)
    end

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", f, "TOP", 0, -10)
    f.title:SetText("|cffffcc00配置名字中|r")

    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.count:SetPoint("TOP", f.title, "BOTTOM", 0, -8)

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.hint:SetPoint("TOP", f.count, "BOTTOM", 0, -6)
    f.hint:SetWidth(240)

    f.addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.addBtn:SetSize(110, 22)
    f.addBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    f.addBtn:SetText("加当前目标")
    f.addBtn:SetScript("OnClick", AddTargetNow)

    f.doneBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.doneBtn:SetSize(90, 22)
    f.doneBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    f.doneBtn:SetText("完成")
    f.doneBtn:SetScript("OnClick", function()
        if ns.Capture and ns.Capture.Stop then pcall(ns.Capture.Stop) end
        SyncCapture()
    end)

    f:Hide()
    return f
end

-- 设置窗还挡着没有。录入要去点 3D 世界里的人,那个大框铺在屏幕中间就点不到。
local function SettingsInTheWay()
    return (SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown()) and true or false
end

local function RefreshMini()
    if not mini then return end
    local n, max = #ns.Current().members, ns.MAX_MEMBERS
    local color = (n >= max) and "|cffffcc00" or "|cff66ff66"
    mini.count:SetText(("已收录 %s%d|r / %d"):format(color, n, max))
    if n >= max then
        mini.hint:SetText("|cffffcc00名单满了,先 × 掉一个再加。|r")
        mini.addBtn:SetEnabled(false)
    else
        mini.addBtn:SetEnabled(true)
        -- 两种"设置窗还开着"的措辞分开写:战斗中那次是我们**故意**不关的,
        -- 说成"挡着你点人"会让人以为插件没反应过来,然后他会去按第二次。
        if not SettingsInTheWay() then
            mini.hint:SetText("点世界里的人添加 · 已经是目标就按下面那颗")
        elseif InCombatLockdown() then
            mini.hint:SetText("|cffffcc00设置窗还开着(战斗中关不掉)。按 ESC 自己关。|r")
        else
            mini.hint:SetText("|cffffcc00设置窗还开着,挡着你点人。按 ESC 关掉。|r")
        end
    end
end

-- 把整个设置窗关掉。藏我们这一页没用 —— 它是 SettingsPanel 的孩子,挡住视线的是那个大框。
-- 🔴 战斗中不碰它。HideUIPanel 走的是暴雪那套**受保护**的面板管理(UIParent 的 panel 栈),
--    插件在战斗中去调,轻则被 C 层拒(那个"界面操作被插件阻止"的弹窗),重则把 taint
--    抹到 SettingsPanel 上带去别的地方。而 pcall **拦不住这种事** —— 它不是 Lua 报错,
--    是 C 层拒绝执行,pcall 里看着一切正常。
--    ⇒ 这属于"我永远验不了的行为"(战斗中的 taint 只有真机能测),所以不赌它是哪种怪癖:
--      战斗中直接不做,并且让小窗把这件事**说出来** —— 不说的话,玩家看到的是
--      "点世界里的人没反应",他会去怀疑录入坏了,而真相只是那块大框还挡着。
local function StepAside()
    if not SettingsInTheWay() then return end
    if InCombatLockdown() then return end
    pcall(HideUIPanel, SettingsPanel)
end

-- 录入状态跟面板对齐。
-- 🔴 为什么是轮询而不是回调:录入可以被**别人**开关(斜杠命令 / 收满 8 人 Capture 自己停),
--    而模块契约里没给"状态变了"的回调。0.3 秒比一次布尔,代价可以忽略;
--    赌"只有我会改这个状态"的代价是小窗留在屏幕上关不掉。
SyncCapture = function()
    local on = CaptureOn()
    if on and not mini then mini = BuildMini() end
    if on then
        if not mini:IsShown() then StepAside(); mini:Show() end
        RefreshMini()
    elseif mini and mini:IsShown() then
        mini:Hide()
    end
    if captureBtn then
        captureBtn:SetText(on and "完成配置" or "配置名字")
    end
end

---------------------------------------------------------------------------------------------------
-- 面板
---------------------------------------------------------------------------------------------------

local countText, mouseCB

-- db.capture 由 Core 的 DEFAULTS 建;这儿再兜一层,免得空表时 setter 往 nil 上写。
local function CapDB()
    ns.db.capture = ns.db.capture or {}
    return ns.db.capture
end

local function MakeCheck(parent, label, x, y, get, set, tip)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetPoint("TOPLEFT", x, y)
    c:SetSize(26, 26)
    local fs = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", c, "RIGHT", 2, 0)
    fs:SetText(label)
    c:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        ns.Changed()
    end)
    -- 🔴 get 真的被用起来:c.DodoSync 是这个勾**唯一**的读值路径。
    --    首轮这个形参从头到尾没被调用过 —— 三个调用点各传了一个 getter 闭包,而真正决定
    --    勾选状态的是 Refresh 里另外三条内联表达式 ⇒ 同一个事实写了两遍。两份单独看都对,
    --    哪天一边改了没有任何东西会发现(canon:同一不变式两份手写实现 = 静默分歧发生器)。
    -- ⚠ 字段名带 Dodo 前缀:裸叫 c.Sync 会遮住 widget 元表上任何同名方法,而暴雪哪天
    --    加一个,我们收不到任何提示 —— 跟弹窗 key 带 DODOGUANZHU_ 前缀是同一个理由。
    c.DodoSync = function() c:SetChecked(get() and true or false) end
    if tip then
        c:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(label, 1, 1, 1)
            GameTooltip:AddLine(tip, 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return c
end

RefreshDropdown = function()
    if not listDropdown then return end
    listDropdown:SetupMenu(function(_, root)
        for i, L in ipairs(ns.db.lists) do
            local idx = i
            root:CreateRadio(L.name or ("方案" .. i),
                function() return ns.db.editing == idx end,
                -- "view":切下拉是**纯换视图** —— 每套方案有自己独立的宏,什么都没编辑。
                -- 不加这个参数的话面板会当场打出「名单改过了,还没写进宏」(实测复现过)。
                function() ns.db.editing = idx; ns.Changed("view") end)
        end
    end)
    listDropdown:SetDefaultText(ns.Current().name or "方案")
    listDropdown:GenerateMenu()
end

local function BuildPanel()
    panel = CreateFrame("Frame", "DodoGuanzhuOptionsPanel")
    panel.name = "DodoGuanzhu"
    panel:Hide()

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("DodoGuanzhu · 能量灌注顺位")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetWidth(540); sub:SetJustifyH("LEFT")
    sub:SetText("生成一个宏:按下去时,宏自己从名单第一个人开始挑,挑到第一个能给的就给他,都给不出去才给自己。"
        .. "|cff808080挑人这件事全在宏条件里,插件在战斗中不做任何决策。|r")
    -- 这儿故意不写「斜杠命令是 /xx」:那个词归 Slash.lua 定,我这边抄一份就是第二个真相源,
    -- 它改了名字这行字会静静地开始撒谎,而没有任何东西会来提醒。

    -- ── 方案 ────────────────────────────────────────────────────────────────
    local lab = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lab:SetPoint("TOPLEFT", 16, -76)
    lab:SetText("方案:")

    listDropdown = CreateFrame("DropdownButton", "DodoGuanzhuListDropdown", panel, "WowStyle1DropdownTemplate")
    listDropdown:SetPoint("LEFT", lab, "RIGHT", 6, 0)
    listDropdown:SetWidth(170)

    local newBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    newBtn:SetSize(60, 22)
    newBtn:SetPoint("LEFT", listDropdown, "RIGHT", 8, 0)
    newBtn:SetText("新建")
    newBtn:SetScript("OnClick", function() StaticPopup_Show("DODOGUANZHU_NEW_LIST") end)

    local renBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    renBtn:SetSize(70, 22)
    renBtn:SetPoint("LEFT", newBtn, "RIGHT", 4, 0)
    renBtn:SetText("改名")
    renBtn:SetScript("OnClick", function() StaticPopup_Show("DODOGUANZHU_RENAME_LIST") end)

    delListBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    delListBtn:SetSize(60, 22)
    delListBtn:SetPoint("LEFT", renBtn, "RIGHT", 4, 0)
    delListBtn:SetText("删除")
    delListBtn:SetScript("OnClick", function() StaticPopup_Show("DODOGUANZHU_DELETE_LIST") end)
    -- 只剩一套时它是**真的按不动**的(Refresh 里 SetEnabled(false)),按不动就得说出为什么。
    delListBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("删除当前方案", 1, 1, 1)
        if #ns.db.lists <= 1 then
            GameTooltip:AddLine("只剩这一套了,删不得 —— 一套都不剩的话,面板和宏都没有名单可读。", 1, 0.4, 0.4, true)
        else
            GameTooltip:AddLine("连里面的名单一起删,删完不可撤销。", 0.9, 0.9, 0.9, true)
        end
        GameTooltip:Show()
    end)
    delListBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── 名单 ────────────────────────────────────────────────────────────────
    local h2 = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h2:SetPoint("TOPLEFT", 16, -122)
    h2:SetText("名单(第 1 行优先级最高)")

    countText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    countText:SetPoint("LEFT", h2, "RIGHT", 10, 0)

    local n2 = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    n2:SetPoint("TOPLEFT", 18, -144)
    n2:SetWidth(540); n2:SetJustifyH("LEFT")
    n2:SetText("|cff808080▲▼ 调顺序,× 删人。灰掉的名字不在队伍里,宏跑到那一段会直接跳过。|r")

    captureBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    captureBtn:SetSize(110, 24)
    captureBtn:SetPoint("TOPLEFT", 18, -168)
    captureBtn:SetText("配置名字")
    captureBtn:SetScript("OnClick", function()
        if not (ns.Capture and ns.Capture.Toggle) then ns.Print("录入模块(Capture.lua)没加载。"); return end
        pcall(ns.Capture.Toggle)
        SyncCapture()   -- 立刻同步,别等 0.3s 的 ticker:那段空窗期看起来就像"点了没反应"
    end)

    -- 🔴 这个勾必须有,不是顺手加的:Capture.AddMouseover 在通道关着时的拒绝语是
    --    「鼠标指向通道关着(去设置里打开)」—— 而在此之前,设置里**根本没有这个开关**。
    --    一条把人指向不存在的地方的错误提示,比没有提示更坏。
    mouseCB = MakeCheck(panel, "鼠标指向也能收", 136, -166,
        function() return CapDB().alsoMouseover ~= false end,
        function(v) CapDB().alsoMouseover = v end,
        "团队框架上左键被配成点击施法时,目标压根不变,PLAYER_TARGET_CHANGED 一次都不来 —— "
        .. "那种情况只能靠鼠标指向这条通道收人。")

    local capNote = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    capNote:SetPoint("TOPLEFT", 18, -194)
    capNote:SetText("|cff808080录入一开,设置窗会自动关掉 —— 面板铺着就点不到世界里的人。|r")

    memberScroll = CreateFrame("ScrollFrame", "DodoGuanzhuMemberScroll", panel, "UIPanelScrollFrameTemplate")
    memberScroll:SetPoint("TOPLEFT", 18, -212)
    memberScroll:SetSize(ROW_W + 20, 144)
    scrollContent = CreateFrame("Frame", nil, memberScroll)
    scrollContent:SetSize(ROW_W, 1)
    memberScroll:SetScrollChild(scrollContent)

    -- ── 两个开关 ────────────────────────────────────────────────────────────
    focusCB = MakeCheck(panel, "焦点组排最前", 16, -396,
        function() return ns.Current().useFocus end,
        function(v) ns.Current().useFocus = v end,
        "在名单最前面插一段 [@focus,help,nodead]。焦点常年挂着灌注目标时最省事。")

    selfCB = MakeCheck(panel, "末尾兜底给自己", 16, -424,
        function() return ns.Current().selfLast end,
        function(v) ns.Current().selfLast = v end,
        "结尾加 [@player]。名单里一个都给不出去时,灌自己也比这一下白按强。")

    -- ── 长度计 + 写宏 ───────────────────────────────────────────────────────
    lengthText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lengthText:SetPoint("TOPLEFT", 20, -456)

    -- 「加当前目标」:一步到位,不用先进录入模式。
    -- 🔑 位置紧贴名单下沿(列表 -212 起、高 144 ⇒ 到 -356),因为它干的事就是**往这张名单里加**
    --    —— 一个按钮该长在它作用的东西旁边。
    -- ⚠ 故意**不做成禁用态**:要判"现在能不能加"就得把 Capture 的那套过滤
    --    (是玩家 / 可帮助 / 不是自己 / 没重复 / 没满)在这儿重写一遍 —— 那是第二份手写实现,
    --    必然跟 Capture 漂。让它永远可点,由 AddTarget 现场判并说出真正的原因。
    --    (canon:谁知道原因谁说话。)
    local addTargetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addTargetBtn:SetSize(140, 24)
    addTargetBtn:SetPoint("TOPLEFT", 18, -364)
    addTargetBtn:SetText("加当前目标")
    addTargetBtn:SetScript("OnClick", function()
        if not (ns.Capture and ns.Capture.AddTarget) then
            ns.Print("录入模块(Capture.lua)没加载。"); return
        end
        pcall(ns.Capture.AddTarget)
        if ns.Options and ns.Options.Refresh then pcall(ns.Options.Refresh) end
    end)
    addTargetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("加当前目标", 1, 1, 1)
        GameTooltip:AddLine("把你现在选中的那个人加到名单末尾。", nil, nil, nil, true)
        GameTooltip:AddLine("要连着加好几个人,用左上角的「配置名字」——"
            .. "那会开录入模式,之后你点谁就自动收谁。", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    addTargetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    writeBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    writeBtn:SetSize(140, 24)
    writeBtn:SetPoint("TOPLEFT", 18, -478)
    writeBtn:SetText(WRITE_LABEL)
    writeBtn:SetScript("OnClick", function()
        -- 按钮此刻应该是禁用的(Refresh 里挡过了),但 pcall(nil.Write, ...) 是在 pcall **之外**
        -- 就炸的那种写法 —— 索引 nil 发生在参数求值期。多这一行,坏的顺序也不会变成红字。
        if not (ns.Macro and ns.Macro.Write) then ns.Print("宏模块(Macro.lua)没加载。"); return end
        -- 🔴 pcall 吐**三个**值:(pcall 自己成没成, Write 的第 1 个返回值, Write 的第 2 个)。
        --    首轮只接了两个 ⇒ err 拿到的其实是 Write 的布尔第一返回值,`if not ok` 恒假,
        --    于是 Write 返回 (false, "名单第 1 位「张,三」…") 时面板**一个字都不打**:
        --    玩家按了按钮,屏幕上什么也没有,而宏根本没写进去。
        --    三种结局的修法完全不同,所以分开报。
        local pok, ok, err = pcall(ns.Macro.Write, ns.Current())
        if not pok then
            -- Write 自己抛了异常(不该发生)。这一支里错误消息在 **ok** 那个位置上。
            ns.Print("写宏时插件自己抛错了:" .. tostring(ok))
        elseif not ok then
            -- err 按 Macro.lua 的契约就是一句完整的可读中文,原样打。
            -- ⛔ 别加"写宏失败:"前缀 —— 战斗中那条 err 是"已排队,脱战后自动写入",
            --    套上前缀就成了一句自相矛盾的话,而人只会记住"失败"两个字。
            ns.Print(err or "写宏没成,而且没给原因 —— 这本身是个 bug。")
        else
            -- ✅ 成功也得说一句。首轮那句"成功了不由我报,Macro 自己会报"是**错的**:
            --    Macro.Write 只在**脱战补写**那条路径上 ns.Print,直接按这颗按钮它一声不吭
            --    ⇒ 成功和失败在屏幕上长得一模一样(都是什么都没有),而这颗按钮的全部
            --    可观测后果都在宏面板里 —— 玩家不去翻就永远不知道成没成。
            local mname = MacroNameNow()
            if mname then
                ns.Print(("宏「%s」写好了 —— 去宏面板把它拖上快捷栏。"):format(mname))
            else
                ns.Print("宏写好了 —— 去宏面板把它拖上快捷栏。")
            end
            Refresh()   -- Write 成功会 ClearDirty,面板得跟着把"改过了还没写"那行撤掉
        end
    end)
    writeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("生成 / 更新宏", 1, 1, 1)
        local why = WriteBlockedReason()
        if why then
            GameTooltip:AddLine(why, 1, 0.4, 0.4, true)
        else
            GameTooltip:AddLine("写进宏库(同名的就地改写,不会越写越多)。写完去宏面板拖上快捷栏。", 0.9, 0.9, 0.9, true)
        end
        GameTooltip:Show()
    end)
    writeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- 「名单改过了、还没写进宏」的常驻提示,摆在按钮**右边**。
    -- 它跟下面那行 reasonText 说的不是一件事(那行说"为什么按不动"),两句不能共用一个位置:
    -- 名单改过 + 正在战斗是可以同时成立的,挤在一起就得有一句被吃掉。
    dirtyText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    dirtyText:SetPoint("LEFT", writeBtn, "RIGHT", 10, 0)
    dirtyText:SetWidth(380); dirtyText:SetJustifyH("LEFT")

    -- 按不动的原因是**常驻一行字**,不是只靠 tooltip:tooltip 只在鼠标已经放上去时才说话,
    -- 而"按钮灰着"这件事本身有歧义(坏了?没做完?)—— 人不会为了一个他以为坏了的按钮去悬停。
    reasonText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    reasonText:SetPoint("TOPLEFT", 18, -510)
    reasonText:SetWidth(540); reasonText:SetJustifyH("LEFT")

    panel:SetScript("OnShow", function() Refresh() end)
end

---------------------------------------------------------------------------------------------------
-- 刷新
---------------------------------------------------------------------------------------------------

Refresh = function()
    SyncCapture()                       -- 小浮窗跟"面板建没建/开没开"无关,先同步它
    if not panel or not panel:IsShown() then return end

    local db = ns.db or ns.EnsureDB()
    local L = ns.Current()

    RefreshDropdown()
    RefreshRows()

    -- 每个勾的读值规则只在 MakeCheck 的 get 里声明一次,这儿只负责叫它同步。
    focusCB.DodoSync()
    selfCB.DodoSync()
    mouseCB.DodoSync()
    countText:SetText(("|cff808080%d / %d 人|r"):format(#L.members, ns.MAX_MEMBERS))
    delListBtn:SetEnabled(#db.lists > 1)

    -- 长度计。🔴 这行不是装饰:超了 ns.BODY_LIMIT 客户端会**静默截断**,
    -- 截出来是一个语法完整、能按、只是少几个人的宏 —— 零报错、零提示,
    -- 靠人眼在游戏里发现"怎么老是不给三号位"要花很久。所以宁可在这儿吵。
    --
    -- 🔴 nil 那一支是契约的另一半:Macro.Length 生成不出正文时返回 **nil**,不是 0。
    --    以前它返回 0、而这儿照数字那条路显示 ⇒ 屏幕上会出现一个**绿色的 "0 / 255"**:
    --    一个看着最健康的数,恰恰出现在最坏的时候(技能名还没加载 / 名单里有拆坏条件的字符
    --    —— 这两种 Write 都会当场拒)。所以 nil 走一条**画不出数字**的路:灰的 "— / 255"
    --    加一句为什么,结构上就没法被读成"很宽裕"。
    local n = MacroLength()
    if n == nil then
        lengthText:SetText(("|cff808080宏长度:— / %d 码位|r  |cffff8080(%s)|r")
            :format(ns.BODY_LIMIT, LengthUnknownWhy()))
    elseif n > ns.BODY_LIMIT then
        lengthText:SetText(("宏长度:|cffff4040%d|r / %d 码位 |cffff4040(超了)|r"):format(n, ns.BODY_LIMIT))
    elseif n > ns.BODY_LIMIT - 20 then
        lengthText:SetText(("宏长度:|cffffcc00%d|r / %d 码位"):format(n, ns.BODY_LIMIT))
    else
        lengthText:SetText(("宏长度:|cff66ff66%d|r / %d 码位"):format(n, ns.BODY_LIMIT))
    end

    local why = WriteBlockedReason()
    writeBtn:SetEnabled(why == nil)
    reasonText:SetText(why and ("|cffff8080" .. why .. "|r") or "")

    -- 「名单改过了,还没写进宏」。
    -- 🔑 它为什么必须显示:Preview 预测的是**名单**,而按下去真正执行的是**已经写进宏栏的
    --    那份宏** —— 两者可以不同步。不说这句,面板就在用"下次会给谁"的口气,
    --    描述一件当下不成立的事。
    -- 🔴 反过来**不成立**:dirty = false 不等于"宏跟名单一致"。这个标记只活在本次登录期间
    --    (不存盘),而宏本身在宏面板里还能被玩家手改。⇒ 为真时才说话,为假时闭嘴,
    --    永远不要在这儿写一句"已是最新" —— 那是一句我们证明不了的话。
    local dirty = ns.IsDirty()
    if not dirty then
        dirtyText:SetText("")
    elseif why == nil then
        dirtyText:SetText("|cffffcc00名单改过了,还没写进宏 —— 按左边那颗。|r")
    else
        -- 改过了、但这会儿按不动。不重复下面那行的理由,免得同一件事两种说法。
        dirtyText:SetText("|cffffcc00名单改过了,还没写进宏。|r")
    end
    -- 高亮只在**真按得动**的时候给:一颗按不动的按钮亮着,是在邀请一个做不到的动作。
    writeBtn:SetText((dirty and why == nil) and ("|cffffcc00" .. WRITE_LABEL .. "|r") or WRITE_LABEL)
end

-- 合并式延迟刷新:0.5 秒内的多次请求只跑一次 Refresh。
-- 两处用它,理由不同但形状一样:
--   ① GROUP_ROSTER_UPDATE 在进副本 / 团队重组时**连着来一串**,而一次 Refresh 里有
--      GenerateMenu 重建整个下拉 + 45 次 UnitExists —— 一串事件全量刷是白烧。
--   ② 脱战补写宏那条路:Macro 和我各自挂了 PLAYER_REGEN_ENABLED,而**谁先跑没有保证**
--      (跟文件末尾那条"不挂 ADDON_LOADED"同一个理由)。我先跑的话 ClearDirty 还没发生,
--      面板会挂着一行"改过了还没写"的假话不动 ⇒ 晚半秒再刷一次收口。
-- ⚠ 只做尾沿,第一个请求也要等满 0.5s。前沿立刻刷的话,一串事件里第一条被刷、后面的被吃掉,
--    最后停在**中间某个状态**上 —— 那是最难发现的坏法(画面不空、只是不对)。
local refreshQueued = false
local function RefreshSoon()
    if refreshQueued then return end
    -- 没有 C_Timer 就退化成立刻刷:节流是省开销的,不是正确性的一部分,不能因为它缺席就不刷。
    if not (C_Timer and C_Timer.After) then Refresh(); return end
    refreshQueued = true
    C_Timer.After(0.5, function()
        refreshQueued = false
        Refresh()
    end)
end

---------------------------------------------------------------------------------------------------
-- 注册 + 对外接口
---------------------------------------------------------------------------------------------------

local function EnsurePanel()
    if panel then return end
    ns.EnsureDB()                       -- 幂等;Open() 可能比 PLAYER_LOGIN 先被人叫到
    BuildPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, "DodoGuanzhu")
        if ok and cat then
            -- ⛔ 这儿原本有一行 `cat.ID = "DodoGuanzhu"` —— **已删,它是那个 bug 的元凶嫌疑**。
            -- 它把暴雪自己分配的内部 ID 覆盖成了字符串,而 Open() 正是拿 cat:GetID() 去
            -- OpenToCategory 查表 ⇒ 查不到就静默什么都不做。
            -- 真机症状:左键小地图图标**毫无反应**,右键(走 Preview.Toggle)正常。
            category = cat
            local okReg, errReg = pcall(Settings.RegisterAddOnCategory, cat)
            if not okReg then ns.Print("注册设置分类失败:" .. tostring(errReg)) end
        else
            ns.Print("建设置面板失败:" .. tostring(cat))
        end
    end
end

ns.Options = {
    Open = function()
        EnsurePanel()
        if not (category and Settings and Settings.OpenToCategory) then
            ns.Print("打不开设置面板(暴雪的 Settings API 没就位)。先用 |cffffd100/dgz help|r 那套命令。")
            return
        end
        -- 🔴 pcall **必须看返回值**。原来这儿是裸 pcall 不接结果 ⇒ 失败完全静默,
        --    症状就是"点了没反应",而"没反应"是最难查的一种报错。
        --    canon:catch 里吞异常是定时炸弹;这是它在 Lua 里的同一个形状。
        local id = category.GetID and category:GetID() or category
        local ok, err = pcall(Settings.OpenToCategory, id)
        if not ok then
            ns.Print("打开设置面板出错:" .. tostring(err))
            ns.Print("  暂时先用 |cffffd100/dgz|r 那套命令,功能是全的。")
        end
    end,
    Refresh = function() Refresh() end,
}

-- 🔴 挂 PLAYER_LOGIN 不挂 ADDON_LOADED:Core 也在 ADDON_LOADED 里建 DB,
--    两个 frame 注册同一个事件时谁先跑**没有保证**,而我这边一开始就要读 ns.db。
--    PLAYER_LOGIN 一定排在所有 ADDON_LOADED 之后,EnsureDB 又是幂等的,等它零成本。
local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:RegisterEvent("GROUP_ROSTER_UPDATE")   -- 进出队 → 职业色 / 灰名字要跟着变
init:RegisterEvent("PLAYER_REGEN_DISABLED") -- 进战斗 → 写宏按钮当场变按不动
init:RegisterEvent("PLAYER_REGEN_ENABLED")  -- 脱战 → 放它回来
init:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        EnsurePanel()
        ns.OnChanged(Refresh)
        -- 录入状态的轮询。别改成"只在面板开着时跑"—— 小浮窗恰恰活在面板关掉之后。
        if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(0.3, SyncCapture) end
        Refresh()
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- 名册变动只影响显示层(职业色 / "不在队伍"那个灰标),晚半秒没有任何代价 ⇒ 走节流。
        RefreshSoon()
    else
        -- 进战 / 脱战:这两条必须**立刻**刷 —— 写宏按钮的可按性当场就变了,
        -- 而"按钮状态慢半拍"在屏幕上恰好长得像"按钮坏了"。
        Refresh()
        -- 脱战再补一发延迟的:Macro 可能正在这一帧把战斗中排队的宏写掉(然后 ClearDirty),
        -- 而它跟我谁先收到这个事件没有保证。
        if event == "PLAYER_REGEN_ENABLED" then RefreshSoon() end
    end
end)
