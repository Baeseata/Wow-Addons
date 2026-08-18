-- DodoGrid :: Core.lua
-- Healer-focused party/raid frames. Route A (self-rolled SecureUnitButton, STATIC tokens).
--   * party/solo: player + party1..4 (partyContainer)
--   * raid:       raid1..40, grouped by subgroup into 小队 columns, Blizzard-style (raidContainer)
-- The two containers are swapped by a secure [group:raid] visibility state driver (also avoids the
-- player-duplicate: in a raid the player IS some raidN, so the party set is hidden). Unit attrs are
-- STATIC and never mutate, so the only combat-protected work is Layout()'s SetPoint/SetSize on the
-- buttons/anchor -- gated by InCombatLockdown and deferred to PLAYER_REGEN_ENABLED. Per-unit
-- health/status/range paint is insecure and stays live in combat.
--
-- Secret Values rule (DodoNameplate/GOTCHAS.md): never compare/arith/table-key/format a maybe-secret
-- value; guard with issecretvalue() or feed it straight to a widget SINK. Roster structure
-- (GetRaidRosterInfo subgroup, UnitGroupRolesAssigned) is NOT secret for your own group.

local ADDON, ns = ...

----------------------------------------------------------------------------------------------------
-- Secret-Values shim + helpers
----------------------------------------------------------------------------------------------------
local IsSecret = issecretvalue or function() return false end

local function Bool(v)
	if v == nil or IsSecret(v) then return false end
	return v and true or false
end

-- Integer 0-100 STEP curve (proven DodoNameplate form): secret health fraction -> whole-number percent.
local SCALE100
if C_CurveUtil and C_CurveUtil.CreateCurve then
	local c = C_CurveUtil.CreateCurve()
	if c then
		if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
			c:SetType(Enum.LuaCurveType.Step)
		end
		for i = 0, 100 do c:AddPoint(i / 100, i) end
		SCALE100 = c
	end
end

local function CopyDefaults(dst, src)
	if type(dst) ~= "table" then dst = {} end
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = CopyDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

----------------------------------------------------------------------------------------------------
-- Config
----------------------------------------------------------------------------------------------------
local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }
local RAID_UNITS  = {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end

local HEALTHBAR_TEXTURE = "Interface/Buttons/WHITE8X8"   -- flat solid color (tinted by class color)
local DEFAULT_BAR_COLOR = { 0.20, 0.60, 0.20 }
local ROLE_TEXTURE      = "Interface/LFGFrame/UI-LFG-ICON-PORTRAITROLES"
local ROLE_TCOORDS = {   -- standard FrameXML small-circle role texcoords
	TANK    = { 0, 19/64, 22/64, 41/64 },
	HEALER  = { 20/64, 39/64, 1/64, 20/64 },
	DAMAGER = { 20/64, 39/64, 22/64, 41/64 },
}

local CELL_GAP  = 1      -- vertical gap between members in a column
local GROUP_GAP = 6      -- horizontal gap between subgroup columns
local TITLE_H   = 13     -- 小队 title height above each column

local defaults = {
	pos               = { "CENTER", "CENTER", -260, 120 },
	locked            = true,
	width             = 72,
	height            = 36,
	rangeAlpha        = 0.55,
	deadAlpha         = 0.45,
	hideBlizzardRaid  = true,
	hideBlizzardParty = true,
	-- Aura indicators (Auras.lua). Category-driven only (per-spellID curation is DEAD under Secret
	-- Values). Center-slot priority is user-configurable via important.centerPriority (raid/dispel/cc).
	auras = {
		enabled    = true,
		showTimer  = true,    -- cooldown countdown numbers on icons
		showStacks = true,    -- stack count text on icons
		mine = {              -- (1) HELPFUL|PLAYER  -> small icon row, bottom-left
			enabled = true, size = 13, max = 3, hidePermanent = true, xOff = 0, yOff = 0,
		},
		important = {         -- (2) HARMFUL|RAID / RAID_IN_COMBAT / CROWD_CONTROL -> center icon
			enabled = true, size = 20, showCC = true, xOff = 0, yOff = 0,
			centerPriority = "raid",   -- who wins the single center slot: "raid" / "dispel" / "cc"
		},
		dispel = {            -- (3) HARMFUL|RAID_PLAYER_DISPELLABLE -> full-cell border (school colored)
			enabled = true, thickness = 2,
		},
		-- Click-to-dispel (Dispel.lua): secure /cast macro on each cell; spell auto-detected per spec.
		dispelClick = {
			enabled = true,
			modifier = "shift",   -- "shift" / "ctrl" / "alt" / "none"
			button = 1,           -- 1=left 2=right 3=middle 4/5=side
			spellOverride = "",   -- non-empty = use this spell name instead of auto-detect
		},
	},
}

local buttons    = {}    -- unit token -> secure button
local groupTitle = {}    -- subgroup 1..8 -> FontString
local anchor, partyContainer, raidContainer, mover, moving, dirty, posDirty

----------------------------------------------------------------------------------------------------
-- Per-unit paint (all insecure; safe in combat). Health reads go to widget SINKS.
----------------------------------------------------------------------------------------------------
local function ClassColor(unit)
	local token = UnitClassBase and UnitClassBase(unit)
	if token and not IsSecret(token) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token] then
		local c = RAID_CLASS_COLORS[token]
		return c.r, c.g, c.b
	end
	return DEFAULT_BAR_COLOR[1], DEFAULT_BAR_COLOR[2], DEFAULT_BAR_COLOR[3]
end

local function UpdateColor(b, unit)
	b.hb:SetStatusBarColor(ClassColor(unit))
end

local function UpdateName(b, unit)
	b.nameFS:SetText(UnitName(unit) or "")
end

local function UpdateRole(b, unit)
	local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
	local tc = (role and not IsSecret(role)) and ROLE_TCOORDS[role] or nil
	if tc then
		b.roleIcon:SetTexCoord(tc[1], tc[2], tc[3], tc[4]); b.roleIcon:Show()
	else
		b.roleIcon:Hide()
	end
end

local function UpdateStatusText(b, unit)
	if not Bool(UnitIsConnected(unit)) then
		b.status:SetText("离线"); b.status:SetTextColor(0.6, 0.6, 0.6); b.status:Show(); return true
	end
	if Bool(UnitIsDeadOrGhost(unit)) then
		b.status:SetText(Bool(UnitIsGhost(unit)) and "鬼魂" or "死亡")
		b.status:SetTextColor(0.9, 0.4, 0.4); b.status:Show(); return true
	end
	b.status:SetText(""); b.status:Hide(); return false
end

local function UpdateHealth(b, unit)
	if not unit or not UnitExists(unit) then return end
	local h    = UnitHealth(unit)
	local hmax = UnitHealthMax(unit)
	b.hb:SetMinMaxValues(0, hmax)   -- secret-safe sink
	b.hb:SetValue(h)                -- secret-safe sink

	local noHealth = UpdateStatusText(b, unit)
	if noHealth then
		b.hpPct:SetText(""); b.hpPctSign:Hide()
		return
	end

	if not IsSecret(h) and not IsSecret(hmax) and hmax and hmax > 0 then
		b.hpPct:SetText(("%.0f"):format(100 * h / hmax)); b.hpPctSign:Show()
	elseif SCALE100 and UnitHealthPercent then
		local p = UnitHealthPercent(unit, true, SCALE100)
		if p == nil then
			b.hpPct:SetText(""); b.hpPctSign:Hide()
		elseif IsSecret(p) then
			b.hpPct:SetText(p); b.hpPctSign:Show()
		else
			b.hpPct:SetText(("%.0f"):format(p)); b.hpPctSign:Show()
		end
	else
		b.hpPct:SetText(""); b.hpPctSign:Hide()
	end
end

local function InRange(unit)
	if unit == "player" then return true end
	local inRange, checked = UnitInRange(unit)
	if IsSecret(checked) or checked == false then return true end   -- guard the secret 2nd return first
	if IsSecret(inRange) then return true end
	return inRange and true or false
end

local function UpdateAlpha(b, unit)
	if not Bool(UnitIsConnected(unit)) or Bool(UnitIsDeadOrGhost(unit)) then
		b:SetAlpha(ns.db.deadAlpha)
	elseif InRange(unit) then
		b:SetAlpha(1)
	else
		b:SetAlpha(ns.db.rangeAlpha)
	end
end

local function UpdateAll(b, unit)
	UpdateName(b, unit)
	UpdateColor(b, unit)
	UpdateRole(b, unit)
	UpdateHealth(b, unit)
	UpdateAlpha(b, unit)
	if ns.Auras then ns.Auras.Update(b, unit) end
end

----------------------------------------------------------------------------------------------------
-- Button construction (secure; runs once at login, out of combat)
----------------------------------------------------------------------------------------------------
local function StyleButton(b)
	local hb = CreateFrame("StatusBar", nil, b)
	hb:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)          -- 1px inset; the frame bg shows through as a border
	hb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
	hb:SetStatusBarTexture(HEALTHBAR_TEXTURE)
	hb:SetStatusBarColor(DEFAULT_BAR_COLOR[1], DEFAULT_BAR_COLOR[2], DEFAULT_BAR_COLOR[3])
	b.hb = hb

	local bg = b:CreateTexture(nil, "BACKGROUND")        -- parented to b: fills the 1px gutter = the border
	bg:SetAllPoints(b)
	bg:SetColorTexture(0, 0, 0, 0.85)

	local border = CreateFrame("Frame", nil, b, "BackdropTemplate")
	border:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
	border:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
	border:SetBackdropBorderColor(0, 0, 0, 0.9)

	-- role icon: TOP-LEFT corner (Blizzard placement)
	local roleIcon = hb:CreateTexture(nil, "OVERLAY")
	roleIcon:SetSize(13, 13)
	roleIcon:SetPoint("TOPLEFT", hb, "TOPLEFT", 3, -2)
	roleIcon:SetTexture(ROLE_TEXTURE)
	roleIcon:Hide()
	b.roleIcon = roleIcon

	-- name: top band, left-justified next to the role icon
	local nameFS = hb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	nameFS:SetPoint("TOPLEFT", roleIcon, "TOPRIGHT", 2, 1)
	nameFS:SetPoint("TOPRIGHT", hb, "TOPRIGHT", -3, -2)
	nameFS:SetJustifyH("LEFT")
	nameFS:SetWordWrap(false)
	nameFS:SetMaxLines(1)
	b.nameFS = nameFS

	-- status (离线/死亡/鬼魂): greyed font, bottom-centered (mutually exclusive with the percent)
	local status = hb:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	status:SetPoint("BOTTOM", hb, "BOTTOM", 0, 2)
	status:SetWordWrap(false)
	status:SetMaxLines(1)
	status:Hide()
	b.status = status

	-- health %: bottom-right, clears the top name row
	local pct = hb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pct:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", -13, 2)
	pct:SetJustifyH("RIGHT")
	b.hpPct = pct

	local sign = hb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sign:SetPoint("LEFT", pct, "RIGHT", 1, 0)
	sign:SetText("%")
	sign:Hide()
	b.hpPctSign = sign
end

local function BuildButton(unit, parent)
	-- frame TYPE MUST be "Button" or clicks never fire. Created out of combat only. Positioned by Layout().
	local b = CreateFrame("Button", "DodoGrid_" .. unit, parent, "SecureUnitButtonTemplate")
	b:SetSize(ns.db.width, ns.db.height)

	b:SetAttribute("unit", unit)             -- STATIC token; never changes
	b:SetAttribute("*type1", "target")
	b:SetAttribute("*type2", "togglemenu")
	b:SetAttribute("toggleForVehicle", true)
	b:RegisterForClicks("AnyDown")
	RegisterUnitWatch(b)                      -- secure Show/Hide on UnitExists("unit"), even in combat

	StyleButton(b)
	if ns.Auras then ns.Auras.Create(b); ns.Auras.Layout(b) end   -- aura widgets are button children (combat-safe)

	b:RegisterUnitEvent("UNIT_HEALTH", unit)
	b:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
	b:RegisterUnitEvent("UNIT_CONNECTION", unit)
	b:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
	b:RegisterUnitEvent("UNIT_AURA", unit)
	b:RegisterEvent("PLAYER_ENTERING_WORLD")
	b:SetScript("OnEvent", function(self, event)
		if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
			UpdateHealth(self, unit)
		elseif event == "UNIT_NAME_UPDATE" then
			UpdateName(self, unit); UpdateColor(self, unit)
		elseif event == "UNIT_AURA" then
			if ns.Auras then ns.Auras.Update(self, unit) end
		else
			UpdateAll(self, unit)
		end
	end)

	buttons[unit] = b
end

----------------------------------------------------------------------------------------------------
-- Roster + layout
----------------------------------------------------------------------------------------------------
-- ordered model: { mode, entries = { {unit, subgroup}, ... } }. All reads here are unrestricted.
local function BuildRoster()
	if IsInRaid() then
		local entries = {}
		for i = 1, GetNumGroupMembers() do
			local name, _, subgroup = GetRaidRosterInfo(i)   -- subgroup = return #3
			if name then
				entries[#entries + 1] = { unit = "raid" .. i, subgroup = subgroup or 1 }
			end
		end
		return { mode = "raid", entries = entries }
	elseif IsInGroup() then
		local entries = { { unit = "player", subgroup = 1 } }   -- partyN excludes the player
		for i = 1, GetNumGroupMembers() - 1 do
			entries[#entries + 1] = { unit = "party" .. i, subgroup = 1 }
		end
		return { mode = "party", entries = entries }
	end
	return { mode = "solo", entries = { { unit = "player", subgroup = 1 } } }
end

-- Positions buttons + sizes the anchor (for the mover). PROTECTED ops -> out of combat only.
local function Layout()
	if InCombatLockdown() then dirty = true; return end
	dirty = false
	local CELL_W, CELL_H = ns.db.width, ns.db.height
	local roster = BuildRoster()

	if roster.mode == "raid" then
		local cols = {}
		for _, e in ipairs(roster.entries) do
			cols[e.subgroup] = cols[e.subgroup] or {}
			local c = cols[e.subgroup]; c[#c + 1] = e.unit
		end
		local colIndex, maxRows = 0, 0
		for sg = 1, 8 do
			local c = cols[sg]
			if c and #c > 0 then
				local x = colIndex * (CELL_W + GROUP_GAP)
				local t = groupTitle[sg]
				t:ClearAllPoints()
				t:SetPoint("BOTTOMLEFT", raidContainer, "TOPLEFT", x, 2)
				t:SetFormattedText(GROUP_NUMBER or "Group %d", sg)
				t:Show()
				for row, unit in ipairs(c) do
					local b = buttons[unit]
					b:ClearAllPoints()
					b:SetSize(CELL_W, CELL_H)
					b:SetPoint("TOPLEFT", raidContainer, "TOPLEFT", x, -((row - 1) * (CELL_H + CELL_GAP)))
					if row > maxRows then maxRows = row end
				end
				colIndex = colIndex + 1
			else
				groupTitle[sg]:Hide()
			end
		end
		anchor:SetSize(math.max(1, colIndex * (CELL_W + GROUP_GAP) - GROUP_GAP),
		               math.max(1, maxRows * (CELL_H + CELL_GAP) - CELL_GAP))
	else
		for sg = 1, 8 do groupTitle[sg]:Hide() end
		for row, e in ipairs(roster.entries) do
			local b = buttons[e.unit]
			b:ClearAllPoints()
			b:SetSize(CELL_W, CELL_H)
			b:SetPoint("TOP", partyContainer, "TOP", 0, -((row - 1) * (CELL_H + CELL_GAP)))
		end
		anchor:SetSize(CELL_W, math.max(1, #roster.entries * (CELL_H + CELL_GAP) - CELL_GAP))
	end
end

local function RefreshAll()
	for _, b in pairs(buttons) do
		local u = b:GetAttribute("unit")
		if u and UnitExists(u) then UpdateAll(b, u) end
	end
end

----------------------------------------------------------------------------------------------------
-- Anchor, containers, mover
----------------------------------------------------------------------------------------------------
local function RestorePos()
	if InCombatLockdown() then posDirty = true; return end   -- anchor is protected-by-propagation
	posDirty = false
	local p = ns.db.pos
	anchor:ClearAllPoints()
	anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local function SavePos()
	local point, _, relPoint, x, y = anchor:GetPoint()
	ns.db.pos = { point, relPoint, x, y }
end

local function ApplyLock()
	if ns.db.locked then mover:Hide() else mover:Show() end
end

local function BuildAnchor()
	anchor = CreateFrame("Frame", "DodoGridAnchor", UIParent)
	anchor:SetSize(ns.db.width, ns.db.height)
	anchor:SetMovable(true)
	anchor:SetClampedToScreen(true)
	RestorePos()

	-- Two containers parent the secure buttons; a [group:raid] visibility driver swaps them securely
	-- (works in combat) and structurally avoids the player-duplicate. Both overlay the anchor.
	partyContainer = CreateFrame("Frame", "DodoGridParty", anchor)
	partyContainer:SetAllPoints(anchor)
	raidContainer = CreateFrame("Frame", "DodoGridRaid", anchor)
	raidContainer:SetAllPoints(anchor)
	RegisterStateDriver(partyContainer, "visibility", "[group:raid] hide; show")
	RegisterStateDriver(raidContainer,  "visibility", "[group:raid] show; hide")

	for sg = 1, 8 do
		local t = raidContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		t:Hide()
		groupTitle[sg] = t
	end

	-- UIParent child (NOT a child of anchor): anchor is protected-by-propagation in combat; a child of
	-- it would inherit that and block mover:Show/Hide in combat.
	mover = CreateFrame("Frame", nil, UIParent)
	mover:SetAllPoints(anchor)
	mover:SetFrameStrata("HIGH")
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	mover:Hide()

	local mb = mover:CreateTexture(nil, "BACKGROUND")
	mb:SetAllPoints(mover)
	mb:SetColorTexture(0.1, 0.5, 0.9, 0.35)
	local ml = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	ml:SetPoint("CENTER")
	ml:SetText("DodoGrid\n拖动定位")

	mover:SetScript("OnDragStart", function()
		if InCombatLockdown() then return end
		anchor:StartMoving(); moving = true
	end)
	mover:SetScript("OnDragStop", function()
		if InCombatLockdown() then return end   -- PLAYER_REGEN_DISABLED already ended any in-combat drag
		anchor:StopMovingOrSizing(); moving = false
		SavePos()
	end)
end

----------------------------------------------------------------------------------------------------
-- Exports for Options.lua / HideBlizzard.lua (aliases onto the file-local closures, set at load)
----------------------------------------------------------------------------------------------------
ns.Layout     = Layout
ns.RefreshAll = RefreshAll
ns.RestorePos = RestorePos
ns.ApplyLock  = ApplyLock
function ns.RefreshLayout() Layout(); RefreshAll() end

-- Generic per-button iterator for sibling modules (Dispel.lua re-applies click-cast attributes via this).
function ns.ForEachButton(fn)
	for _, b in pairs(buttons) do fn(b) end
end

-- Re-apply aura layout + state to every cell (called from Options after an aura setting changes).
function ns.ApplyAuras()
	if not ns.Auras then return end
	for _, b in pairs(buttons) do
		ns.Auras.Layout(b)
		local u = b:GetAttribute("unit")
		if u and UnitExists(u) then ns.Auras.Update(b, u) else ns.Auras.Clear(b) end
	end
end

----------------------------------------------------------------------------------------------------
-- Slash
----------------------------------------------------------------------------------------------------
local function Print(msg) print("|cff66ccffDodoGrid|r: " .. msg) end

SLASH_DODOGRID1 = "/dodogrid"
SLASH_DODOGRID2 = "/dg"
SlashCmdList.DODOGRID = function(arg)
	arg = (arg or ""):lower():gsub("%s+", "")
	if arg == "reset" then
		if InCombatLockdown() then Print("战斗中无法重置位置。"); return end
		ns.db.pos = { "CENTER", "CENTER", 0, 0 }
		RestorePos()
		Print("位置已重置到屏幕中央。")
	elseif arg == "lock" then
		ns.db.locked = true; ApplyLock(); Print("已锁定。")
	elseif arg == "unlock" then
		ns.db.locked = false; ApplyLock(); Print("已解锁,拖动蓝色块移动;/dg lock 锁定。")
	elseif arg == "config" or arg == "options" then
		if ns.OpenOptions then ns.OpenOptions() end
	else
		ns.db.locked = not ns.db.locked; ApplyLock()
		Print(ns.db.locked and "已锁定。" or "已解锁,拖动蓝色块移动。")
	end
end

----------------------------------------------------------------------------------------------------
-- Boot
----------------------------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("GROUP_ROSTER_UPDATE")
boot:RegisterEvent("PLAYER_ROLES_ASSIGNED")
boot:RegisterEvent("PLAYER_REGEN_DISABLED")
boot:RegisterEvent("PLAYER_REGEN_ENABLED")
boot:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		DodoGridDB = CopyDefaults(DodoGridDB, defaults)
		ns.db = DodoGridDB
		if ns.ApplyHideBlizzard then ns.ApplyHideBlizzard() end   -- hide Blizzard group frames (self combat-gates)

		if InCombatLockdown() then return end   -- defensive; PLAYER_LOGIN is never in combat
		BuildAnchor()
		for _, u in ipairs(PARTY_UNITS) do BuildButton(u, partyContainer) end
		for _, u in ipairs(RAID_UNITS)  do BuildButton(u, raidContainer)  end
		Layout()
		RefreshAll()
		ApplyLock()
		if ns.InitOptions then ns.InitOptions() end

		C_Timer.NewTicker(0.25, function()
			for _, b in pairs(buttons) do
				local u = b:GetAttribute("unit")
				if u and b:IsVisible() and UnitExists(u) then UpdateAlpha(b, u) end   -- skip hidden container
			end
		end)

		Print("已加载 (v0.5.0)。/dg 解锁移动,/dg config 打开设置。")

	elseif event == "GROUP_ROSTER_UPDATE" then
		if ns.db then Layout(); RefreshAll() end          -- Layout() self-gates combat via dirty

	elseif event == "PLAYER_ROLES_ASSIGNED" then
		if ns.db then
			for _, b in pairs(buttons) do
				local u = b:GetAttribute("unit")
				if u and UnitExists(u) then UpdateRole(b, u) end
			end
		end

	elseif event == "PLAYER_REGEN_DISABLED" then
		-- combat starting: end any in-progress drag and re-lock while the anchor is still mutable.
		if anchor and moving then anchor:StopMovingOrSizing(); moving = false; SavePos() end
		if ns.db then ns.db.locked = true; ApplyLock() end

	elseif event == "PLAYER_REGEN_ENABLED" then
		-- combat ended: flush any deferred reposition / re-layout.
		if ns.db then
			if posDirty then RestorePos() end
			if dirty then Layout() end
			RefreshAll()
		end
	end
end)
