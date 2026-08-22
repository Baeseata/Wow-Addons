-- DodoGrid :: Options.lua
-- Settings UI under Esc -> Options -> AddOns -> DodoGrid: a General page (parent) + a Layout
-- sub-page. Canvas layout, mirroring DodoNameplate/Options.lua. Controls bind to ns.db and apply
-- live via the ns.* exports from Core. Built + registered at PLAYER_LOGIN via ns.InitOptions().

local ADDON, ns = ...

local category

---------------------------------------------------------------------------------------------------
-- Control builders (parent-agnostic; `apply` runs after the value is stored)
---------------------------------------------------------------------------------------------------
local function Header(parent, text, x, y)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
	fs:SetTextColor(1, 0.82, 0)
	return fs
end

local function Note(parent, text, x, y)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
	return fs
end

local function MakeCheck(parent, label, x, y, get, set, apply)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetPoint("TOPLEFT", x, y)
	c:SetSize(24, 24)
	local fs = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("LEFT", c, "RIGHT", 2, 0)
	fs:SetText(label)
	c:SetChecked(get() ~= false)
	c:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		if apply then apply() end
	end)
	return c
end

local function MakeSlider(parent, label, x, y, minV, maxV, step, get, set, apply)
	local s = CreateFrame("Slider", nil, parent)
	s:SetPoint("TOPLEFT", x, y)
	s:SetSize(220, 16)
	s:SetOrientation("HORIZONTAL")
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	local th = s:GetThumbTexture()
	if th then th:SetSize(16, 16) end

	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(0.25, 0.25, 0.25, 0.9)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(5)

	local lab = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	lab:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3)
	lab:SetText(label)
	local val = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	val:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 3)

	s:SetValue(get())
	val:SetText(tostring(math.floor(get() + 0.5)))
	s:SetScript("OnValueChanged", function(self, v)
		v = math.floor(v + 0.5)
		val:SetText(tostring(v))
		set(v)
		if apply then apply() end
	end)
	return s
end

-- Sliders can fire once per rendered frame while dragging. Aura-container reconfiguration touches
-- every static unit cell, so coalesce a drag into one final apply instead of rebuilding 45 previews.
local function Debounce(delay, fn)
	local generation = 0
	return function()
		generation = generation + 1
		local ticket = generation
		if C_Timer and C_Timer.After then
			C_Timer.After(delay, function()
				if ticket == generation then fn() end
			end)
		else
			fn()
		end
	end
end

-- A button that cycles through an ordered list of { value=, label= } choices. The face reads
-- "<label>: <current choice>". No Blizzard dropdown dependency -- matches the hand-rolled toolkit.
local function MakeCycle(parent, label, x, y, choices, get, set, apply)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetPoint("TOPLEFT", x, y)
	b:SetSize(220, 22)
	local function curIndex()
		local v = get()
		for i, c in ipairs(choices) do if c.value == v then return i end end
		return 1
	end
	local function refresh() b:SetText(label .. ": " .. choices[curIndex()].label) end
	b:SetScript("OnClick", function()
		local nextI = curIndex() % #choices + 1
		set(choices[nextI].value)
		refresh()
		if apply then apply() end
	end)
	refresh()
	return b
end

-- A single-line text input (label above). Commits on Enter or focus-loss.
local function MakeEdit(parent, label, x, y, get, set, apply)
	local lab = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	lab:SetPoint("TOPLEFT", x, y)
	lab:SetText(label)
	local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	e:SetPoint("TOPLEFT", x + 4, y - 16)
	e:SetSize(200, 22)
	e:SetAutoFocus(false)
	e:SetText(get() or "")
	local function commit()
		set(e:GetText() or "")
		e:ClearFocus()
		if apply then apply() end
	end
	e:SetScript("OnEnterPressed", commit)
	e:SetScript("OnEditFocusLost", commit)
	return e
end

---------------------------------------------------------------------------------------------------
-- General page (parent)
---------------------------------------------------------------------------------------------------
local function BuildGeneralPage()
	local f = CreateFrame("Frame")
	f.name = "DodoGrid"
	Note(f, "更多设置见左侧子页(布局)。", 10, -10)

	Header(f, "隐藏暴雪默认框体", 10, -40)
	MakeCheck(f, "隐藏暴雪团队框体", 18, -68,
		function() return ns.db.hideBlizzardRaid ~= false end,
		function(v) ns.db.hideBlizzardRaid = v end,
		function() if ns.PromptReload then ns.PromptReload() end end)
	MakeCheck(f, "隐藏暴雪小队框体", 18, -96,
		function() return ns.db.hideBlizzardParty ~= false end,
		function(v) ns.db.hideBlizzardParty = v end,
		function() if ns.PromptReload then ns.PromptReload() end end)
	Note(f, "|cffff8080更改后需要重载界面生效。|r", 18, -122)
	return f
end

---------------------------------------------------------------------------------------------------
-- Layout sub-page
---------------------------------------------------------------------------------------------------
local function BuildLayoutPage()
	local f = CreateFrame("Frame")
	f.name = "布局"
	local applyLayout = Debounce(0.08, function()
		if ns.RefreshLayout then ns.RefreshLayout() end
	end)
	Header(f, "单元格尺寸", 10, -16)
	MakeSlider(f, "宽度", 20, -56, 40, 160, 1,
		function() return ns.db.width end, function(v) ns.db.width = v end,
		applyLayout)
	MakeSlider(f, "高度", 20, -100, 16, 60, 1,
		function() return ns.db.height end, function(v) ns.db.height = v end,
		applyLayout)

	Header(f, "位置(相对屏幕中心)", 10, -140)
	MakeSlider(f, "X 偏移", 20, -180, -1200, 1200, 1,
		function() return ns.db.pos[3] end,
		function(v) ns.db.pos[1] = "CENTER"; ns.db.pos[2] = "CENTER"; ns.db.pos[3] = v end,
		function() if ns.RestorePos then ns.RestorePos() end end)
	MakeSlider(f, "Y 偏移", 20, -224, -800, 800, 1,
		function() return ns.db.pos[4] end,
		function(v) ns.db.pos[1] = "CENTER"; ns.db.pos[2] = "CENTER"; ns.db.pos[4] = v end,
		function() if ns.RestorePos then ns.RestorePos() end end)
	MakeCheck(f, "锁定框体(取消勾选后拖动蓝色块移动)", 18, -256,
		function() return ns.db.locked end,
		function(v) ns.db.locked = v end,
		function() if ns.ApplyLock then ns.ApplyLock() end end)

	Header(f, "透明度", 10, -296)
	MakeSlider(f, "距离过远 (%)", 20, -336, 0, 100, 5,
		function() return ns.db.rangeAlpha * 100 end,
		function(v) ns.db.rangeAlpha = v / 100 end,
		function() if ns.RefreshAll then ns.RefreshAll() end end)
	MakeSlider(f, "死亡 / 离线 (%)", 20, -380, 0, 100, 5,
		function() return ns.db.deadAlpha * 100 end,
		function(v) ns.db.deadAlpha = v / 100 end,
		function() if ns.RefreshAll then ns.RefreshAll() end end)
	return f
end

---------------------------------------------------------------------------------------------------
-- Auras sub-page (ns.db.auras). Three healer categories; category-driven only (no per-spellID lists
-- in instances). Changes apply live via ns.ApplyAuras (re-layout + re-update every cell).
---------------------------------------------------------------------------------------------------
local function BuildAuraPage()
	local f = CreateFrame("Frame")
	f.name = "光环"
	local a = ns.db.auras
	local apply = Debounce(0.08, function()
		if ns.ApplyAuras then ns.ApplyAuras() end
	end)

	Note(f, "三类光环指示器。副本内只能按暴雪固定分类过滤,无法按法术 ID 自定义白名单。", 10, -10)

	-- Left column: 总开关 + ① 我施放的增益
	Header(f, "总开关", 10, -40)
	MakeCheck(f, "启用光环指示器", 18, -66,
		function() return a.enabled end, function(v) a.enabled = v end, apply)

	Header(f, "① 我施放的增益(左下小图标)", 10, -102)
	MakeCheck(f, "显示", 18, -128,
		function() return a.mine.enabled end, function(v) a.mine.enabled = v end, apply)
	MakeCheck(f, "隐藏常驻增益(无时限,如耐力/智力)", 18, -156,
		function() return a.mine.hidePermanent end, function(v) a.mine.hidePermanent = v end, apply)
	MakeSlider(f, "图标大小", 20, -198, 8, 24, 1,
		function() return a.mine.size end, function(v) a.mine.size = v end, apply)
	MakeSlider(f, "最大数量", 20, -242, 1, 6, 1,
		function() return a.mine.max end, function(v) a.mine.max = v end, apply)
	MakeSlider(f, "横向偏移", 20, -286, -20, 40, 1,
		function() return a.mine.xOff end, function(v) a.mine.xOff = v end, apply)
	MakeSlider(f, "纵向偏移", 20, -330, -10, 30, 1,
		function() return a.mine.yOff end, function(v) a.mine.yOff = v end, apply)

	-- Right column: ② 重要减益 + ③ 可驱散 + 全局
	Header(f, "② 重要减益(居中大图标)", 300, -40)
	MakeCheck(f, "显示", 308, -66,
		function() return a.important.enabled end, function(v) a.important.enabled = v end, apply)
	MakeCheck(f, "包含控制效果(CC)", 308, -94,
		function() return a.important.showCC end, function(v) a.important.showCC = v end, apply)
	MakeCycle(f, "中心优先", 308, -122, {
			{ value = "raid",   label = "重要减益" },
			{ value = "dispel", label = "可驱散"   },
			{ value = "cc",     label = "控制(CC)" },
		},
		function() return a.important.centerPriority or "raid" end,
		function(v) a.important.centerPriority = v end, apply)
	MakeSlider(f, "图标大小", 310, -168, 12, 32, 1,
		function() return a.important.size end, function(v) a.important.size = v end, apply)
	MakeSlider(f, "横向偏移", 310, -212, -30, 30, 1,
		function() return a.important.xOff end, function(v) a.important.xOff = v end, apply)
	MakeSlider(f, "纵向偏移", 310, -256, -20, 20, 1,
		function() return a.important.yOff end, function(v) a.important.yOff = v end, apply)

	Header(f, "③ 可驱散减益(整格描边,按学派上色)", 300, -298)
	MakeCheck(f, "显示", 308, -324,
		function() return a.dispel.enabled end, function(v) a.dispel.enabled = v end, apply)
	MakeSlider(f, "描边粗细", 310, -366, 1, 5, 1,
		function() return a.dispel.thickness end, function(v) a.dispel.thickness = v end, apply)

	Header(f, "全局", 300, -406)
	MakeCheck(f, "显示倒计时数字", 308, -432,
		function() return a.showTimer end, function(v) a.showTimer = v end, apply)
	MakeCheck(f, "显示层数", 308, -460,
		function() return a.showStacks end, function(v) a.showStacks = v end, apply)
	return f
end

---------------------------------------------------------------------------------------------------
-- 驱散 sub-page (ns.db.auras.dispelClick). Click-to-dispel: bind + auto-detected spell + override.
---------------------------------------------------------------------------------------------------
local function BuildDispelPage()
	local f = CreateFrame("Frame")
	f.name = "驱散"
	local d = ns.db.auras.dispelClick
	local function apply() if ns.ApplyDispel then ns.ApplyDispel() end end

	Note(f, "点击友方格子施放你的驱散法术,配合\"③ 可驱散\"边框使用。", 10, -10)

	Header(f, "点击驱散", 10, -44)
	MakeCheck(f, "启用", 18, -70,
		function() return d.enabled end, function(v) d.enabled = v end, apply)
	MakeCycle(f, "修饰键", 18, -104, {
			{ value = "shift", label = "Shift" },
			{ value = "ctrl",  label = "Ctrl"  },
			{ value = "alt",   label = "Alt"   },
			{ value = "none",  label = "无"    },
		},
		function() return d.modifier or "shift" end,
		function(v) d.modifier = v end, apply)
	MakeCycle(f, "鼠标键", 18, -140, {
			{ value = 1, label = "左键" }, { value = 2, label = "右键" }, { value = 3, label = "中键" },
			{ value = 4, label = "侧键4" }, { value = 5, label = "侧键5" },
		},
		function() return d.button or 1 end,
		function(v) d.button = v end, apply)
	Note(f, "|cffffcc00左键默认选中、右键默认菜单;绑到它们会覆盖该默认动作。|r", 18, -170)
	Note(f, "战斗中更改设置,下次脱战后生效。", 18, -188)

	Header(f, "驱散法术", 10, -206)
	local spellNote = Note(f, "", 18, -232)
	local function refreshSpell()
		local s = ns.Dispel and ns.Dispel.Resolve and ns.Dispel.Resolve()
		spellNote:SetText("当前: |cff66ccff" .. (s or "无(此专精无可用驱散)") .. "|r")
	end
	refreshSpell()
	f:SetScript("OnShow", refreshSpell)
	MakeEdit(f, "手动覆盖(留空 = 自动识别)", 18, -264,
		function() return d.spellOverride end,
		function(v) d.spellOverride = v end,
		function() apply(); refreshSpell() end)
	return f
end

---------------------------------------------------------------------------------------------------
-- Registration (PLAYER_LOGIN, ns.db ready). Idempotent.
---------------------------------------------------------------------------------------------------
function ns.InitOptions()
	if category or not ns.db or not Settings or not Settings.RegisterCanvasLayoutCategory then
		return
	end
	category = Settings.RegisterCanvasLayoutCategory(BuildGeneralPage(), "DodoGrid")
	Settings.RegisterAddOnCategory(category)
	Settings.RegisterCanvasLayoutSubcategory(category, BuildLayoutPage(), "布局")
	Settings.RegisterCanvasLayoutSubcategory(category, BuildAuraPage(), "光环")
	Settings.RegisterCanvasLayoutSubcategory(category, BuildDispelPage(), "驱散")
end

function ns.OpenOptions()
	if category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
	end
end
