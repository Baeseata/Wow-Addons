-- DodoNameplate :: Options.lua
-- Settings UI under Esc -> Options -> AddOns -> DodoNameplate, split into a General page (parent)
-- plus one subcategory page per unit group (Hostile / Friendly NPC / Party-Raid / Other Players),
-- so each kind of content has its own clearly-divided page. Canvas layout (keeps color pickers +
-- free layout). Controls bind to ns.db and call ns.Style.RefreshAll() so changes apply live.
-- All visible strings go through ns.L (Locale.lua); the language switch on General needs a /reload
-- to rebuild the (once-built) pages. Built + registered at PLAYER_LOGIN via ns.InitOptions().

local ADDON, ns = ...

local category  -- parent Settings category
local L         -- active locale table (ns.L), captured in ns.InitOptions

---------------------------------------------------------------------------------------------------
-- Control builders (parent-agnostic)
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

local function MakeCheck(parent, label, x, y, get, set)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetPoint("TOPLEFT", x, y)
	c:SetSize(24, 24)
	local fs = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("LEFT", c, "RIGHT", 2, 0)
	fs:SetText(label)
	c:SetChecked(get() ~= false)
	c:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		ns.Style.RefreshAll()
	end)
	return c
end

local function MakeSlider(parent, label, x, y, minV, maxV, step, get, set)
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
		ns.Style.RefreshAll()
	end)
	return s
end

local function MakeColor(parent, label, x, y, get, set)
	local b = CreateFrame("Button", nil, parent)
	b:SetPoint("TOPLEFT", x, y)
	b:SetSize(20, 20)
	local tex = b:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	local c = get()
	tex:SetColorTexture(c.r, c.g, c.b)

	local bd = CreateFrame("Frame", nil, b, "BackdropTemplate")
	bd:SetPoint("TOPLEFT", -1, 1)
	bd:SetPoint("BOTTOMRIGHT", 1, -1)
	bd:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	bd:SetBackdropBorderColor(0, 0, 0, 1)

	local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("LEFT", b, "RIGHT", 6, 0)
	fs:SetText(label)

	b:SetScript("OnClick", function()
		local cur = get()
		ColorPickerFrame:SetupColorPickerAndShow({
			r = cur.r, g = cur.g, b = cur.b, hasOpacity = false,
			swatchFunc = function()
				local r, g, bl = ColorPickerFrame:GetColorRGB()
				set({ r = r, g = g, b = bl })
				tex:SetColorTexture(r, g, bl)
				ns.Style.RefreshAll()
			end,
			cancelFunc = function() end,
		})
	end)
	return b
end

-- Two mutually-exclusive language buttons (radio). Changing the language only stores the choice;
-- the pages are built once, so a /reload is needed to re-localize them (a note appears on change).
local function MakeLangRadio(parent, x, y)
	local enBtn, zhBtn, note

	local function resolve()
		local loc = ns.db.locale
		if loc ~= "enUS" and loc ~= "zhCN" then
			local g = GetLocale()
			loc = (g == "zhCN" or g == "zhTW") and "zhCN" or "enUS"
		end
		return loc
	end
	local function refresh()
		local loc = resolve()
		enBtn:SetChecked(loc == "enUS")
		zhBtn:SetChecked(loc == "zhCN")
	end
	local function pick(loc)
		ns.db.locale = loc
		refresh()
		if note then note:Show() end
	end

	enBtn = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	enBtn:SetPoint("TOPLEFT", x, y)
	enBtn:SetSize(24, 24)
	local enfs = enBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	enfs:SetPoint("LEFT", enBtn, "RIGHT", 2, 0)
	enfs:SetText(L.opt_english)
	enBtn:SetScript("OnClick", function() pick("enUS") end)

	zhBtn = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	zhBtn:SetPoint("TOPLEFT", x + 120, y)
	zhBtn:SetSize(24, 24)
	local zhfs = zhBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	zhfs:SetPoint("LEFT", zhBtn, "RIGHT", 2, 0)
	-- ensure CJK renders even on a non-zh client; the fallback matches Plate.lua/Auras.lua because
	-- skinning addons are known to blank STANDARD_TEXT_FONT, and SetFont(nil, ...) is a hard error
	zhfs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12)
	zhfs:SetText(L.opt_chinese)
	zhBtn:SetScript("OnClick", function() pick("zhCN") end)

	note = Note(parent, L.note_reload, x, y - 26)
	note:SetTextColor(1, 0.5, 0.5)
	note:Hide()
	refresh()
end

---------------------------------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------------------------------
local function BuildGeneralPage()
	local f = CreateFrame("Frame")
	f.name = "DodoNameplate"
	Note(f, L.note_subpages, 10, -10)

	Header(f, L.hdr_threat, 10, -40)
	MakeColor(f, L.col_normal, 20, -68,
		function() return ns.db.colorNormal end, function(c) ns.db.colorNormal = c end)
	MakeColor(f, L.col_warn, 20, -100,
		function() return ns.db.colorWarn end, function(c) ns.db.colorWarn = c end)

	Header(f, L.hdr_overlays, 10, -140)
	MakeCheck(f, L.chk_dimTapped, 18, -168,
		function() return ns.db.overlays.dimTapped end, function(v) ns.db.overlays.dimTapped = v end)
	MakeCheck(f, L.chk_hideCritter, 18, -194,
		function() return ns.db.overlays.hideCritter end, function(v) ns.db.overlays.hideCritter = v end)

	Header(f, L.hdr_misc, 10, -232)
	MakeSlider(f, L.sld_targetScale, 20, -266, 100, 160, 1,
		function() return ns.db.targetScale * 100 end, function(v) ns.db.targetScale = v / 100 end)
	MakeSlider(f, L.sld_markSize, 20, -306, 12, 64, 1,
		function() return ns.db.markSize end, function(v) ns.db.markSize = v end)

	Header(f, L.hdr_language, 10, -346)
	MakeLangRadio(f, 18, -374)
	return f
end

local function BuildGroupPage(name, gid, hasCast)
	local f = CreateFrame("Frame")
	f.name = name
	local d = ns.db.groups[gid]
	local isHostile = (gid == ns.GROUP.HOSTILE)

	-- Left column: health bar + text (+ hostile important-cast health recolor)
	Header(f, name, 10, -16)
	MakeCheck(f, L.chk_enable, 18, -44,
		function() return d.enabled end, function(v) d.enabled = v end)
	MakeSlider(f, L.sld_hpWidth, 20, -84, 60, 260, 1,
		function() return d.width end, function(v) d.width = v end)
	MakeSlider(f, L.sld_hpHeight, 20, -124, 6, 30, 1,
		function() return d.height end, function(v) d.height = v end)
	MakeCheck(f, L.chk_showName, 18, -150,
		function() return d.showName end, function(v) d.showName = v end)
	if not isHostile then   -- hostile mob name auto-sizes to the bar height; no manual size control
		MakeSlider(f, L.sld_nameSize, 20, -192, 6, 22, 1,
			function() return d.nameSize end, function(v) d.nameSize = v end)
	end
	MakeSlider(f, L.sld_levelSize, 20, -232, 6, 22, 1,
		function() return d.levelSize end, function(v) d.levelSize = v end)
	MakeSlider(f, L.sld_pctSize, 20, -272, 6, 22, 1,
		function() return d.healthSize end, function(v) d.healthSize = v end)
	if isHostile then
		Header(f, L.hdr_impHp, 10, -312)
		MakeCheck(f, L.chk_impHpRecolor, 18, -340,
			function() return d.importantHpRecolor end, function(v) d.importantHpRecolor = v end)
		MakeColor(f, L.col_impHpColor, 20, -372,
			function() return d.importantHpColor end, function(c) d.importantHpColor = c end)
	end

	-- Right column: cast bar (+ hostile cast-target bar). Cast bar width follows the healthbar.
	if hasCast then
		Header(f, L.hdr_castbar, 300, -16)
		MakeCheck(f, L.chk_showCast, 308, -44,
			function() return d.showCast end, function(v) d.showCast = v end)
		MakeSlider(f, L.sld_castHeight, 300, -84, 6, 24, 1,
			function() return d.castHeight end, function(v) d.castHeight = v end)
		MakeSlider(f, L.sld_castTextSize, 300, -124, 6, 22, 1,
			function() return d.castTextSize end, function(v) d.castTextSize = v end)
		MakeColor(f, L.col_castColor, 310, -158,
			function() return d.castColor end, function(c) d.castColor = c end)
		-- "Important cast" is a PvE/NPC flag (C_Spell.IsSpellImportant); enemy-player casts are never
		-- flagged important (and spellID is secret in active PvP), so the picker is dead for group 6.
		if gid ~= ns.GROUP.ENEMY_PLAYER then
			MakeColor(f, L.col_castImportant, 310, -190,
				function() return d.castImportantColor end, function(c) d.castImportantColor = c end)
		end

		if isHostile then
			Header(f, L.hdr_castTarget, 300, -226)
			MakeCheck(f, L.chk_castTargetShow, 308, -252,
				function() return d.castTargetShow end, function(v) d.castTargetShow = v end)
			MakeSlider(f, L.sld_castTargetHeight, 300, -290, 6, 24, 1,
				function() return d.castTargetHeight end, function(v) d.castTargetHeight = v end)
			MakeSlider(f, L.sld_castTargetWidth, 300, -330, 40, 260, 1,
				function() return d.castTargetWidth end, function(v) d.castTargetWidth = v end)
			MakeSlider(f, L.sld_castTargetTextSize, 300, -370, 6, 22, 1,
				function() return d.castTargetTextSize end, function(v) d.castTargetTextSize = v end)
			MakeColor(f, L.col_castTargetFallback, 310, -404,
				function() return d.castTargetFallbackColor end, function(c) d.castTargetFallbackColor = c end)
		end
	end
	return f
end

---------------------------------------------------------------------------------------------------
-- Auras sub-page (shared config ns.db.auras). Applies to enemy plates (hostile mobs + enemy players).
---------------------------------------------------------------------------------------------------
local function BuildAuraPage()
	local f = CreateFrame("Frame")
	f.name = L.page_auras
	local a = ns.db.auras
	Note(f, L.note_auras, 10, -10)
	Header(f, L.hdr_auraCats, 10, -40)
	MakeCheck(f, L.chk_auraEnable, 18, -68,
		function() return a.enabled end, function(v) a.enabled = v end)
	MakeCheck(f, L.chk_auraMine, 18, -96,
		function() return a.mine end, function(v) a.mine = v end)
	MakeCheck(f, L.chk_auraCC, 18, -124,
		function() return a.cc end, function(v) a.cc = v end)
	MakeCheck(f, L.chk_auraImportant, 18, -152,
		function() return a.important end, function(v) a.important = v end)
	MakeCheck(f, L.chk_auraBuffs, 18, -180,
		function() return a.buffs end, function(v) a.buffs = v end)
	MakeCheck(f, L.chk_auraPurge, 18, -208,
		function() return a.purge end, function(v) a.purge = v end)
	MakeCheck(f, L.chk_auraDefensive, 18, -236,
		function() return a.defensive end, function(v) a.defensive = v end)
	Header(f, L.hdr_auraLayout, 10, -272)
	MakeSlider(f, L.sld_auraCount, 20, -306, 1, 10, 1,
		function() return a.max end, function(v) a.max = v end)
	MakeSlider(f, L.sld_auraW, 20, -346, 12, 40, 1,
		function() return a.w end, function(v) a.w = v end)
	MakeSlider(f, L.sld_auraH, 20, -386, 12, 40, 1,
		function() return a.h end, function(v) a.h = v end)
	MakeCheck(f, L.chk_auraTimer, 18, -414,
		function() return a.showTimer end, function(v) a.showTimer = v end)
	return f
end

---------------------------------------------------------------------------------------------------
-- Registration (PLAYER_LOGIN, ns.db + ns.L ready). Idempotent.
---------------------------------------------------------------------------------------------------
function ns.InitOptions()
	if category or not ns.db or not Settings or not Settings.RegisterCanvasLayoutCategory then
		return
	end
	L = ns.L
	category = Settings.RegisterCanvasLayoutCategory(BuildGeneralPage(), "DodoNameplate")
	Settings.RegisterAddOnCategory(category)

	local function sub(name, gid, hasCast)
		Settings.RegisterCanvasLayoutSubcategory(category, BuildGroupPage(name, gid, hasCast), name)
	end
	sub(L.page_hostile, ns.GROUP.HOSTILE, true)
	sub(L.page_enemyPlayer, ns.GROUP.ENEMY_PLAYER, true)
	Settings.RegisterCanvasLayoutSubcategory(category, BuildAuraPage(), L.page_auras)
	sub(L.page_friendlyNpc, ns.GROUP.FRIENDLY_NPC, true)
	sub(L.page_party, ns.GROUP.PARTY, false)
	sub(L.page_other, ns.GROUP.FRIENDLY, false)
end

function ns.OpenOptions()
	if category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
	end
end

---------------------------------------------------------------------------------------------------
-- Slash: /dnp opens options; /dnp test runs the classification probe; /dnp tint reports the tinting.
---------------------------------------------------------------------------------------------------
SLASH_DODONAMEPLATE1 = "/dnp"
SlashCmdList.DODONAMEPLATE = function(msg)
	msg = (msg or ""):lower():gsub("%s+", "")
	if msg == "tint" then
		-- Every way this feature fails is silent -- an unbuilt ruleset, a spec with no entry, or the
		-- ten-frame fallback path all look exactly like "nothing has a DoT on it right now".
		if not ns.Tint then print("|cff66ccffDodoNameplate|r tint -> module not loaded"); return end
		print("|cff66ccffDodoNameplate|r tint -> " .. ns.Tint.Status())
		for _, e in ipairs(ns.Tint.Errors()) do
			print("|cff66ccffDodoNameplate|r tint |cffff3333!|r " .. e)
		end
		local plate = C_NamePlate.GetNamePlateForUnit("target")
		print("|cff66ccffDodoNameplate|r tint " ..
			(plate and plate.dnp and ns.Tint.LevelReport(plate.dnp) or "no styled plate for target"))
		return
	end
	if msg == "test" then
		local unit = "target"
		if not UnitExists(unit) then
			print("|cff66ccffDodoNameplate|r: no target -- target something and retry.")
			return
		end
		local g = ns.Classify(unit)
		local tapped = ns.IsTapped(unit) and " (tapped)" or ""
		local rmi = GetRaidTargetIndex(unit)
		local rmiStr
		if issecretvalue and issecretvalue(rmi) then rmiStr = "SECRET"
		elseif rmi then rmiStr = tostring(rmi)
		else rmiStr = "none" end
		local cls = UnitClassBase(unit)
		local clsStr
		if issecretvalue and issecretvalue(cls) then clsStr = "SECRET"
		elseif cls then clsStr = tostring(cls)
		else clsStr = "nil" end
		print(("|cff66ccffDodoNameplate|r: target -> group %d = %s%s | role: %s | raidMark: %s | class: %s"):format(
			g, ns.GROUP_NAME[g] or "?", tapped, ns.isTank and "TANK" or "DPS/Healer", rmiStr, clsStr))
		local plate = C_NamePlate.GetNamePlateForUnit("target")
		local pf = plate and plate.dnp
		if pf and pf.mark then
			local m = pf.mark
			print(("|cff66ccffDodoNameplate|r mark -> shown:%s w:%.0f tex:%s"):format(
				tostring(m:IsShown()), m:GetWidth() or 0, tostring(m:GetTexture())))
		else
			print("|cff66ccffDodoNameplate|r mark -> no styled plate for target (group disabled / not a tracked plate)")
		end
		return
	end
	ns.OpenOptions()
end
