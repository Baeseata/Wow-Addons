-- DodoGuanzhu :: Preview.lua
-- 一个小浮标:实时显示「下次按那个宏,灌注会落到谁头上」+ 射程附注。
--
-- 这个文件存在的唯一理由是射程那条硬伤:宏条件里**没有**射程判断
-- (12.1 实测 `inrange` 是个未识别条件、被直接忽略,走近走远条件纹丝不动),
-- 而 `C_Spell.IsSpellInRange(10060, unit)` 是明文、跟着距离实时变。
-- ⇒ 把「按下去才发现空了」提前成「按之前就看得见」。
--
-- 🔴 全文最重要的一条纪律:**主判断严格照宏的逻辑算,即不考虑射程。**
--    射程(和掉线)只作为附注挂在旁边,绝不参与挑人。
--    预览要是自作主张跳过一个超距离的人,屏幕上说的就不是按下去会发生的事 ——
--    而宏才是真正执行的那个。同一条规则两份实现会静默漂,且两边单独看都完全正常。

local ADDON, ns = ...

local IsSecret = issecretvalue or function() return false end

----------------------------------------------------------------------------------------------------
-- 明文读取的小包装
----------------------------------------------------------------------------------------------------
-- 这插件的全部价值在于不崩。q() 把「函数不存在 / 调用报错 / 返回的是 secret」三种坏结果
-- 统一压成 nil —— 它们在这儿的处置完全一样(当作不知道),分开写只会让每个调用点多三行。
local function q(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if not ok or IsSecret(v) then return nil end
	return v
end

-- 别写成 `v and true` —— 老 API 有返 0/1 的历史,而 Lua 里 **0 是真**,
-- 那会把「否」读成「是」,而且失败方向正好是「看着一切正常」。
local function truth(v)
	if v == nil or v == false or v == 0 then return false end
	return true
end

-- 拼进字符串之前的最后一道闸:只有非空 string 才配进 `..`。
-- 🔴 实撞:`members = { {} }`(存档被别的插件写坏 / 手改 SavedVariables)→ RowText 里
--    `.. e.name` 抛 "attempt to concatenate a table value"。而这段挂在 OnUpdate 上
--    ⇒ 不是崩一次,是**每 0.25 秒崩一次**,刷屏刷到把真正有用的报错顶出去。
-- 归一化只在两个地方发生(Candidates 产出 e.name、RowText 消费 e.name),两处共用这一个函数 ——
-- 各写一份 `type(x)=="string"` 就是 canon 说的静默分歧发生器,而且两份的 fallback 文案会漂。
local function Nameable(v, fallback)
	if type(v) == "string" and v ~= "" then return v end
	return fallback
end

-- 显示名。**必须用 GetUnitName(unit, true)**,不能用 UnitName ——
-- 🔴 `UnitName` 的服务器在**第二个**返回值里,而 q() 只取第一个 ⇒ 跨服的人显示名被
--    静默剥掉 "-服务器",屏幕上两个不同服的同名玩家长得一模一样,玩家对不上号。
--    `GetUnitName(u, true)` 一个返回值就带后缀(同服不带、跨服带),不用自己拼。
local function UnitLabel(unit)
	return q(GetUnitName, unit, true)
end

-- 名字 → unit token。**这个解析全插件只有一个来源:ns.Macro.TokenFor。**
-- 「队友的名字能不能直接当 unit 用」是唯一一个没在真人队伍里验过的假设
-- (12.1 实测:主城陌生人 `[@名字,help]` 和 `[@名字,exists]` 都判假)。
-- 它被隔离在 Macro 那一个函数里,预览这边要是自己再写一遍,将来证伪那天就会只改一处,
-- 另一处静默留着继续跑 —— 而两边看起来都对。
-- 每次现取、不缓存:Macro.lua 在 .toc 里确实排在本文件前面,但别把加载顺序变成隐性依赖。
local function TokenFor(name)
	local t = ns.Macro and ns.Macro.TokenFor and q(ns.Macro.TokenFor, name)
	return t or name
end

local function Exists(u)  return truth(q(UnitExists, u)) end
local function CanHelp(u) return truth(q(UnitCanAssist, "player", u)) end   -- 宏条件 help
local function Dead(u)    return truth(q(UnitIsDeadOrGhost, u)) end         -- 宏条件 nodead 的反面
-- 只有明确回 false 才算掉线;拿不到(nil)是「不知道」,不是「掉线」。
local function Offline(u) return q(UnitIsConnected, u) == false end

-- 射程是**三态**,别塌成 bool:「够不着」要报警,「不知道」只能说不知道。
-- 把后者当前者会在每个读不到的场合喊一次狼来了,喊几次这一行就没人看了。
-- 只用 C_Spell 那个:旧全局 IsSpellInRange 在 12.x 已移除,调用直接 ERROR。
local function RangeOf(unit)
	if not C_Spell then return nil end
	local v = q(C_Spell.IsSpellInRange, ns.PI_SPELL_ID, unit)
	if v == nil then return nil end
	return truth(v)
end

-- 职业色。⚠ 拿 secret 当表 key 会直接报错,而这段跑在 OnUpdate 里 ⇒ 一崩就是每帧刷屏。
-- 所以宁可返 nil 用默认色,也不能让它有机会抛。
local function ClassRGB(unit)
	local ok, _, token = pcall(UnitClass, unit)
	if not ok or token == nil or IsSecret(token) then return nil end
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
	if not c then return nil end
	return c.r, c.g, c.b
end

-- %02x 必须喂整数:0.25 * 255 = 63.75,而 WoW 的 Lua 5.1 会**静默截断**成 63 ——
-- 本机 5.4 直接抛「number has no integer representation」才把它逼出来。
-- 换句话说,不写这个 floor 的话游戏里也不会报错,只是颜色悄悄差一档、永远没人发现。
local function Colored(unit, text)
	local r, g, b = ClassRGB(unit)
	if not r then return text end
	return ("|cff%02x%02x%02x%s|r"):format(
		math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), text)
end

----------------------------------------------------------------------------------------------------
-- 候选清单 —— 挑人的顺序在本文件里只写这一遍
----------------------------------------------------------------------------------------------------
local ST_OK, ST_NO, ST_UNKNOWN = "ok", "no", "unknown"

-- 按**宏的顺序**列出全部候选:焦点组 → 名单逐个 → [@player]。
-- 只判 help / nodead 两样,跟宏条件一一对应;射程和掉线算出来只挂在 e.range / e.offline 上,
-- **不进 e.state**。Next() 和面板的每一行都读这一份返回值。
local function Candidates(list)
	local out = {}
	if type(list) ~= "table" then return out end

	if list.useFocus then
		local e = { unit = "focus", label = "焦点" }
		if not Exists("focus") then      e.state, e.why = ST_NO, "没设焦点"
		elseif Dead("focus") then        e.state, e.why = ST_NO, "死亡"
		elseif not CanHelp("focus") then e.state, e.why = ST_NO, "不可助"
		else                             e.state = ST_OK end
		-- ⚠ 兜底值**不能**跟 label 同字("焦点")—— 那样没设焦点时这两个字段是同一个串,
		--   渲染出来是「✗ 焦点 焦点 没设焦点」。真机截图抓到的,离线 stub 验不出来
		--   (stub 里没人去看那行**长什么样**,只断言了字段有没有值)。
		--   兜底留空,让 label 自己说话;why 那半已经写了"没设焦点"。
		e.name = Exists("focus") and Nameable(UnitLabel("focus"), "?") or ""
		e.range, e.offline = RangeOf("focus"), Offline("focus")
		out[#out + 1] = e
	end

	-- `list.members` 不是表就当空 —— ipairs 拿到非表会当场抛,而这条路径每 0.25 秒走一次。
	local members = (type(list.members) == "table") and list.members or {}
	for i, name in ipairs(members) do
		local label = ("#%d"):format(i)
		if type(name) ~= "string" then
			-- 存档里这一项压根不是名字(外部插件写坏 / 手改 SavedVariables)。
			-- 不能悄悄跳过:悄悄跳过 = 屏幕上少一行而没人知道为什么,
			-- 而 Macro.BuildBody 碰到它是**整个宏都写不出来**,那才是玩家真会撞上的后果。
			out[#out + 1] = { unit = "none", label = label, name = "(坏数据)",
			                  state = ST_NO, why = "存档里这一项不是名字" }
		else
			local u = TokenFor(name)
			-- 🔴 显示名一律用**名单里存的那个字符串**,不是从 unit 现读回来的那个。
			--    理由跟本文件开头那条纪律同源:宏正文里写进去的就是这个字符串,
			--    屏幕上显示别的(哪怕"更准")就等于说了一件跟按下去不一样的事。
			--    顺带把跨服后缀的问题一并关掉 —— 存的时候带 "-服务器",显示就带。
			local e = { unit = u, label = label, name = name }
			-- 解析不出 unit ⇒ 标「?」而不是「✗」:我们看不到这个人,这跟「看得到但不行」是两回事。
			if not Exists(u) then            e.state, e.why = ST_UNKNOWN, "不在队伍"
			elseif Dead(u) then              e.state, e.why = ST_NO, "死亡"
			elseif not CanHelp(u) then       e.state, e.why = ST_NO, "不可助"
			else                             e.state = ST_OK end
			if e.state ~= ST_UNKNOWN then
				e.range, e.offline = RangeOf(u), Offline(u)
			end
			out[#out + 1] = e
		end
	end

	if list.selfLast then
		-- `[@player]` 后面**没有任何条件** ⇒ 它永远成立,自己死了也成立。
		-- 所以状态恒为可给;死没死只当附注 —— 拿它去改判定,说的就跟宏不是一件事了。
		local e = { unit = "player", label = "自己", name = Nameable(UnitLabel("player"), "自己"),
		            state = ST_OK, range = true }   -- 自己给自己没有距离问题,真去问反而可能拿到 nil
		e.dead = Dead("player")
		out[#out + 1] = e
	end

	return out
end

local Preview = {}
ns.Preview = Preview

-- 下次会给谁。返回 name, sourceLabel, inRange(三态:true/false/nil)。
-- 没有任何候选成立 ⇒ 返回 nil。那是个真状态:关了「兜底给自己」而名单全不可用时,
-- 宏一个分支都不匹配,按下去**什么都不会发生** —— 这值得让人看见,不该悄悄显示成给自己。
function Preview.Next(list)
	-- 🔴 传进来的不是表就当没传。实撞:`Preview.Next(2)`(顺手把"第几套"当参数递进来)
	--    直接抛 "attempt to index a number value";而传字符串反倒不抛,于是这个坑
	--    只在某些调用方手滑时现形。挡在入口比让每个调用方记得传对便宜得多。
	if type(list) ~= "table" then list = nil end
	list = list or ns.Current()
	if type(list) ~= "table" then return nil end
	for _, e in ipairs(Candidates(list)) do
		if e.state == ST_OK then return e.name, e.label, e.range end
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- 浮标
----------------------------------------------------------------------------------------------------
-- 状态记号一律用 ASCII + 颜色,**不用 ✅/❌ 这类表情符号**:WoW 自带字体不保证有那些字形,
-- 缺了就是一列空白 —— 而这个失败我在本机验不了(没有客户端),属于"赌它是哪种怪癖"。
-- 颜色扛语义,字符只管占位。
local MARK = {
	[ST_OK]      = "|cff40ff40+|r",
	[ST_NO]      = "|cffff4040x|r",
	[ST_UNKNOWN] = "|cff999999?|r",
}

-- WIDTH 从 200 加到 250:真机上跨服名字被截断了(`Phoenìxr-Sargeras...`)。
-- ⚠ 200 是照「同服短名」估的,而跨服名要多带一个 `-服务器` —— 名单里放跨服队友
--    在大米/团本里是**常态不是边角**,估宽时按同服算等于按最短的那种算。
local WIDTH, PAD, ROW_H = 250, 8, 13
local ROWS_TOP = PAD + 43          -- header(13) + main(17) + warn(13) 三行的总高
local DIRTY_H = 26                 -- 「名单没写进宏」那条横幅的高度(两行小字),不显示时为 0

local frame, rows
local rowsExtra = 0                -- 横幅当前占掉多少高度。候选行的锚点全跟着它走

local function Round(v) return math.floor(v + 0.5) end

-- db 里只有 x/y 两个数(Core 定的形状),而 StartMoving 之后 GetPoint 给回来的是任意锚点。
-- 所以拖完要换算回「相对屏幕中心的偏移」再存,并**当场重新锚一次** ——
-- 不然存的数和眼睛看到的位置对不上,下次登录才发现。
-- 两者同 scale(没给浮标单独 SetScale)⇒ 直接相减合法;哪天给它 SetScale 了记得先换算。
local function SavePos(self)
	local cx, cy = self:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if not cx or not ux then return end
	local p = ns.db.preview
	p.x, p.y = Round(cx - ux), Round(cy - uy)
	self:ClearAllPoints()
	self:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
end

-- 候选行的纵坐标要跟着横幅让位 ⇒ 锚点不能只在建的时候设一次。
local function AnchorRow(fs, i)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(ROWS_TOP + rowsExtra + (i - 1) * ROW_H))
end

local function Row(i)
	if rows[i] then return rows[i] end
	local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetWidth(WIDTH - PAD * 2)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	rows[i] = fs
	AnchorRow(fs, i)
	return fs
end

-- 只在真的变了才重排。横幅一亮一灭是低频事件,而 Repaint 每 0.25 秒跑一次 ——
-- 每帧无脑 SetPoint 一整列也不会错,只是白烧。
local function SetRowsExtra(v)
	if v == rowsExtra then return end
	rowsExtra = v
	for i, fs in ipairs(rows) do AnchorRow(fs, i) end
end

local function Build()
	if frame then return frame end
	ns.EnsureDB()
	rows = {}

	-- UIParent 的孩子,且**不被任何 secure frame 挂着或锚定** ⇒ Show/Hide/SetPoint 在战斗中全合法。
	-- ⚠ 别照抄 DodoGrid/Dispel.lua 那条 OOC-only + dirty flag 的纪律:那条管的是 SetAttribute
	--   和被 secure button 传染的框体,跟这个纯显示浮标是两回事,照抄只会白白让战斗中不刷新。
	frame = CreateFrame("Frame", "DodoGuanzhuPreview", UIParent)
	frame:SetSize(WIDTH, ROWS_TOP + PAD)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.45)

	-- 解锁时才亮的边。canon:能拖的东西必须**看得出**能拖 ——
	-- 一个没有任何边框的黑块,玩家不会想到去按住它拖,hover 变色救不了发现性。
	--
	-- 🔴 首轮这里是**一张**贴图,`BORDER` 层 + TOPLEFT(-1,1)/BOTTOMRIGHT(1,-1) 锚满父框 ——
	--    那不是一圈边,是一个比面板大 1px 的**实心矩形**;而 BORDER 在 BACKGROUND 之上
	--    ⇒ 0.45 的黑底被整块盖成 0.55 的蓝,一解锁整个面板变蓝。
	--    实心块和边框在代码里长得几乎一模一样,只有画出来才看得出区别 —— 所以这儿画四条线。
	-- 两端都锚在父框上(不写死长度)⇒ 面板高度随候选行数变时,竖线自己跟着长,
	--    不需要任何人在 SetHeight 那边记得同步一个数字(canon:能靠结构保证的别靠算式保证)。
	frame.edge = {}
	local function EdgeLine()
		local t = frame:CreateTexture(nil, "BORDER")
		t:SetColorTexture(0.25, 0.65, 1, 0.9)
		t:Hide()
		frame.edge[#frame.edge + 1] = t
		return t
	end
	local top, bottom, left, right = EdgeLine(), EdgeLine(), EdgeLine(), EdgeLine()
	-- 画在框**里**边缘,不是外面:外面那 1px 会被 SetClampedToScreen 挤到屏幕外看不见。
	top:SetPoint("TOPLEFT", frame, "TOPLEFT")
	top:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
	top:SetHeight(1)
	bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
	bottom:SetHeight(1)
	left:SetPoint("TOPLEFT", frame, "TOPLEFT")
	left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
	left:SetWidth(1)
	right:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
	right:SetWidth(1)

	frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.header:SetPoint("TOPLEFT", PAD, -PAD)
	frame.header:SetJustifyH("LEFT")

	frame.main = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.main:SetPoint("TOPLEFT", PAD, -(PAD + 13))
	frame.main:SetWidth(WIDTH - PAD * 2)
	frame.main:SetJustifyH("LEFT")
	frame.main:SetWordWrap(false)

	frame.warn = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.warn:SetPoint("TOPLEFT", PAD, -(PAD + 30))
	frame.warn:SetWidth(WIDTH - PAD * 2)
	frame.warn:SetJustifyH("LEFT")
	frame.warn:SetWordWrap(false)

	-- 「名单改了但还没写进宏」的横幅。占一整个自己的带(两行),候选行往下让 DIRTY_H。
	-- 🔴 这条**必须是一句话**,不能只把主行换个颜色 —— 颜色只对已经知道这个规矩的人说话,
	--    而会撞上这个坑的恰恰是不知道的人:他改完名单直接按宏,拿到的是旧名单。
	-- 换行必须**显式**允许:上面三行都写着 SetWordWrap(false),照抄过来这两行就会被截成一行。
	-- (默认本来就是允许,但依赖默认值会让下一个人读不出这是故意的。)
	-- 文案两行各自都比 184px 短,不会再自己折出第三行来撑破这条带。
	frame.dirty = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.dirty:SetPoint("TOPLEFT", PAD, -ROWS_TOP)
	frame.dirty:SetWidth(WIDTH - PAD * 2)
	frame.dirty:SetJustifyH("LEFT")
	frame.dirty:SetJustifyV("TOP")
	frame.dirty:SetWordWrap(true)
	frame.dirty:Hide()

	frame:SetScript("OnDragStart", function(self)
		if ns.db.preview.locked then return end
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePos(self)
	end)

	local p = ns.db.preview
	frame:SetPoint("CENTER", UIParent, "CENTER", p.x or 0, p.y or -180)
	frame:Hide()
	return frame
end

-- 一行候选长这样:`+ #2 张三  远`
local function RowText(e)
	-- Nameable 是拼接前的最后一道:e.name 理论上在 Candidates 就已经是 string 了,
	-- 但这一行是**真正会抛**的那一行,而它抛在 OnUpdate 上 = 每 0.25 秒刷一次屏。
	local nm = Nameable(e.name, "?")
	local t = MARK[e.state] .. " |cff888888" .. Nameable(e.label, "?") .. "|r "
	t = t .. ((e.state == ST_UNKNOWN) and nm or Colored(e.unit, nm))
	if e.state == ST_OK then
		-- 附注,不改判定:「远」是够不着,「?距」是读不到 —— 两者必须分得开。
		if e.range == false then t = t .. "  |cffff4040远|r"
		elseif e.range == nil then t = t .. "  |cff999999?距|r" end
		if e.offline then t = t .. "  |cffff4040掉线|r" end
		if e.dead then t = t .. "  |cffff8800死|r" end        -- 只有「自己」会走到这儿
	elseif e.why then
		t = t .. "  |cff999999" .. e.why .. "|r"
	end
	return t
end

local function Repaint()
	if not frame or not frame:IsShown() then return end
	local list = ns.Current()
	if not list then return end
	local cands = Candidates(list)

	frame.header:SetText("|cff88ccff灌注顺位|r  " .. (list.name or ""))

	local pick
	for _, e in ipairs(cands) do
		if e.state == ST_OK then pick = e; break end
	end

	if pick then
		frame.main:SetText("→ " .. Colored(pick.unit, pick.name))
		local warn = {}
		if pick.range == false then warn[#warn + 1] = "|cffff4040距离不够|r"
		elseif pick.range == nil then warn[#warn + 1] = "|cff999999射程未知|r" end
		if pick.offline then warn[#warn + 1] = "|cffff4040已掉线|r" end
		if pick.dead then warn[#warn + 1] = "|cffff8800自己死着|r" end
		frame.warn:SetText(table.concat(warn, "  "))
	else
		frame.main:SetText("|cffff4040→ 没人可给|r")
		frame.warn:SetText("|cff999999名单全不可用,且没开兜底给自己|r")
	end

	-- 🔴 浮标算的是**名单**,而按下去执行的是**已经写进宏栏的那份宏** —— 两者不同步时
	--    上面那句「→ 某某」说的是一件当下不成立的事,而且它看着完全正常(这才是最坏的一种错)。
	--    ns.IsDirty() 是 Core 那边的唯一入口:名单一改就置位,Macro.Write 成功才清。
	local dirty = ns.IsDirty and ns.IsDirty() and true or false
	if dirty then
		frame.dirty:SetText("|cffffd000[!] 名单改过了,还没写进宏|r\n"
			.. "|cffff8800现在按宏,给的还是旧名单|r")
		frame.dirty:Show()
		SetRowsExtra(DIRTY_H)
	else
		frame.dirty:Hide()
		SetRowsExtra(0)
	end

	for i, e in ipairs(cands) do Row(i):SetText(RowText(e)); rows[i]:Show() end
	for i = #cands + 1, #rows do rows[i]:Hide() end
	frame:SetHeight(ROWS_TOP + rowsExtra + #cands * ROW_H + PAD)
end

-- Repaint 的唯一对外入口。**每个调用点都走它**,别有谁绕过去直接调 Repaint。
-- 🔴 理由:Repaint 挂在 OnUpdate 上 ⇒ 一次 error 不是崩一次,是每 0.25 秒崩一次刷屏,
--    而且会把真正有用的报错顶出去(实撞:members = { {} } → concatenate a table value)。
-- 出错要**看得见**:静默失败会让浮标一直显示上一帧的名字 —— 那是个看着完全正常的错。
-- 报只报一次(修好后重新置位),否则光是那个报错本身就成了刷屏源。
local reportedErr = false
local function SafeRepaint()
	local ok, err = pcall(Repaint)
	if ok then reportedErr = false; return end
	pcall(function() frame.main:SetText("|cffff4040→ 预览出错|r") end)
	if not reportedErr then
		reportedErr = true
		-- err 是 Lua 运行期错误,永远是字符串,不会是 secret —— 这里 tostring 安全。
		ns.Print("预览刷新出错(浮标已停在上一帧):" .. tostring(err))
	end
end

----------------------------------------------------------------------------------------------------
-- 刷新节流 + 事件 + 对外接口
----------------------------------------------------------------------------------------------------
-- 射程要实时,而事件里没有「距离变了」这种东西 ⇒ 只能自己按秒轮询。
-- 0.25s 一跑,一次最多算 10 个 unit 的四五个明文查询,便宜到不用心疼;
-- OnUpdate 无脑但**结构上不可能漏刷**,比挑一堆事件去拼一个不完整的覆盖面强。
local acc = 0
local function OnUpdate(_, dt)
	acc = acc + dt
	if acc < 0.25 then return end
	acc = 0
	SafeRepaint()
end

local function SetEdgeShown(shown)
	for _, t in ipairs(frame.edge) do
		if shown then t:Show() else t:Hide() end
	end
end

local function Apply()
	Build()
	local p = ns.db.preview
	-- 锁上就别吃点击:一个杵在屏幕中间、又不能拖的黑块挡住底下的东西是最烦的。
	frame:EnableMouse(not p.locked)
	SetEdgeShown(not p.locked)
	if p.enabled then
		frame:Show()
		acc = 0
		frame:SetScript("OnUpdate", OnUpdate)
		SafeRepaint()
	else
		frame:Hide()
		-- 关掉是**真把 OnUpdate 摘掉**,不是进函数再 return —— 后者每帧仍要进一次 Lua。
		frame:SetScript("OnUpdate", nil)
	end
end

-- 重新按 db 应用一遍(显隐 / 锁定)再重画。Options 改完设置调它就够,
-- 不用记得「改了 locked 还要另外调一个函数」—— 那种要记的规矩迟早漏。
function Preview.Refresh() Apply() end

function Preview.SetShown(shown)
	ns.EnsureDB()
	ns.db.preview.enabled = shown and true or false
	Apply()
end

function Preview.Toggle()
	ns.EnsureDB()
	Preview.SetShown(not ns.db.preview.enabled)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")   -- db 已就绪(SavedVariables 先于 ADDON_LOADED 到位)
ev:RegisterEvent("GROUP_ROSTER_UPDATE")     -- 队伍变了 ⇒ 名字解析得出解析不出全变
ev:RegisterEvent("PLAYER_FOCUS_CHANGED")    -- 焦点组是第一顺位,换焦点直接换人
-- 目标**不参与**挑人(宏里没有 @target)。留着是因为设焦点的常见手法就是先选目标再 /focus,
-- 于是这一下几乎总是紧接着一次 PLAYER_FOCUS_CHANGED —— 早刷一帧,零成本。别当成正确性依赖。
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then Apply() else SafeRepaint() end
end)

-- 名单被改了(加人 / 删人 / 换套)⇒ 行数和顺序都会变,而且 dirty 也会跟着置位。
-- frame 还没建时 Repaint 第一行就 return,是空转,安全。
if ns.OnChanged then ns.OnChanged(SafeRepaint) end
