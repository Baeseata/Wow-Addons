-- DodoNameplate :: Auras.lua
-- WoW 12.1 aura display for ENEMY nameplates. Addons no longer enumerate or inspect restricted
-- aura data. CustomAuraContainerTemplate owns the filtering, assignment, and secret-safe display;
-- this module only supplies fixed filter groups and presentation sinks.

local ADDON, ns = ...
local ENEMY_PLAYER = ns.GROUP and ns.GROUP.ENEMY_PLAYER

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
-- Stack counts get an explicit SetFont below; this template is only a second line of defence for
-- the case where that SetFont fails (a skinning addon pointing STANDARD_TEXT_FONT at a bad path).
-- It must not be assumed to exist, hence the global probe.
local COUNT_TEMPLATE = _G.NumberFontNormalSmall and "NumberFontNormalSmall" or nil
local TRIM = 0.08
local GAP = 1
local MAX_POOL = 10
local CC_MAX = 3
local NAMEPLATE_MAX = 40
-- Appended to every filter string. Without it the client actively FILTERS OUT auras flagged
-- nameplate-only ("When not set, nameplate-only auras will be filtered out" -- AuraUtil.lua), which
-- is exactly the set a nameplate addon wants. Blizzard's own nameplate filters carry it.
local NP = "|INCLUDE_NAME_PLATE_ONLY"

local BORDER_CC        = { 0.85, 0.10, 0.10, 1 }
local BORDER_NORMAL    = { 0, 0, 0, 1 }
local BORDER_IMPORTANT = { 1, 0.65, 0, 1 }
local BORDER_BUFF      = { 0.10, 0.80, 0.20, 1 }
local BORDER_PURGE     = { 0.62, 0.30, 1.00, 1 }
local BORDER_DEFENSIVE = { 1, 1, 1, 1 }

local Auras = {}
ns.Auras = Auras

local bundles = {}
local initialized = false
local supported = false

local function HasAuraContainerTemplate()
	return C_XMLUtil and C_XMLUtil.GetTemplateInfo
		and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") and true or false
end

local function CanTouchAuraButtons()
	if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
		return false
	end
	if InCombatLockdown and InCombatLockdown() then
		return false
	end
	return true
end

local function AuraConfig()
	return (ns.db and ns.db.auras) or (ns.defaults and ns.defaults.auras) or {}
end

local function ApplyButtonAppearance(button, a)
	local w = a.w or 26
	local h = a.h or 26
	button:SetSize(w, h)
	button.dnpCount:SetFont(FONT, math.max(7, h - 16), "OUTLINE")
	button.dnpCooldown:SetHideCountdownNumbers(a.showTimer == false)
end

local function CreateButtonInitializer(record, borderColor)
	return function(button)
		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", 1, -1)
		icon:SetPoint("BOTTOMRIGHT", -1, 1)
		icon:SetTexCoord(TRIM, 1 - TRIM, TRIM, 1 - TRIM)
		button:SetIcon(icon)

		local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
		cooldown:SetAllPoints(icon)
		cooldown:SetReverse(true)
		cooldown:SetDrawEdge(true)
		if cooldown.SetCountdownAbbrevThreshold then cooldown:SetCountdownAbbrevThreshold(60) end
		if cooldown.SetMinimumCountdownDuration then cooldown:SetMinimumCountdownDuration(0) end
		cooldown:SetFrameLevel(button:GetFrameLevel() + 1)
		button:SetDurationCooldown(cooldown)

		local border = CreateFrame("Frame", nil, button, "BackdropTemplate")
		border:SetAllPoints(button)
		border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		border:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
		border:SetFrameLevel(cooldown:GetFrameLevel() + 1)

		local count = border:CreateFontString(nil, "OVERLAY", COUNT_TEMPLATE)
		count:SetPoint("BOTTOMRIGHT", 1, -1)
		count:SetJustifyH("RIGHT")

		-- Order matters: SetApplicationCount writes into the FontString synchronously inside that
		-- same call (CustomAuraButton -> UpdateAuraDisplay -> ApplyApplicationCount -> SetText),
		-- so the string must already carry a font when ownership transfers. Handing it over bare
		-- and fonting it afterwards raises "FontString:SetText(): Font not set", which unwinds
		-- AddAuraGroup and aborts Initialize on the first of 280 groups. Register last.
		button.dnpCooldown = cooldown
		button.dnpCount = count
		ApplyButtonAppearance(button, AuraConfig())
		button:SetApplicationCount(count)

		record.buttons[#record.buttons + 1] = button
	end
end

local function GroupLayout(index, w, h)
	return {
		elementSpacing = GAP,
		lineSpacing = 0,
		-- 0, not GAP: all groups share one visual row and elementSpacing already separates the
		-- icons. AnchorUtil.ApplyFlowLayout adds groupSpacing once before each further non-empty
		-- group, which RowWidth() does not model -- the row's last icon gets clipped by 1-3px.
		groupSpacing = 0,
		groupLineSpacing = 0,
		forceNewLine = false,
		elementWidth = w,
		elementHeight = h,
		layoutIndex = index,
	}
end

local function AddGroup(record, key, filter, index, borderColor, candidateFilters)
	record.groups[#record.groups + 1] = key
	record.container:AddAuraGroup(key, filter .. NP, {
		maxFrameCount = 0,
		sortMethod = AuraContainerSortMethod.Expiration,
		sortDirection = AuraContainerSortDirection.Normal,
		candidateFilters = candidateFilters,
		initializeFrame = CreateButtonInitializer(record, borderColor),
		layout = GroupLayout(index, 26, 26),
	})
end

local function CreateContainer(unit, suffix, anchorPoint, verticalDirection)
	local name = "DodoNameplateAura" .. suffix .. unit:match("%d+")
	local container = CreateFrame("AuraContainer", name, UIParent, "CustomAuraContainerTemplate")
	local record = {
		container = container,
		buttons = {},
		groups = {},
		anchorPoint = anchorPoint,
		needsRestyle = false,
	}

	container:SetFlowLayoutAnchorPoint(anchorPoint)
	container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, verticalDirection)
	container:SetFlowLayoutMaximumLineSize(math.huge)
	container:SetUnit(unit) -- SetUnit requires a string; this binding is permanent.
	container:SetEnabled(false)
	return record
end

local function CreateBundle(unit)
	local up = AnchorUtil.FlowDirection.Up
	local down = AnchorUtil.FlowDirection.Down
	local bundle = {
		unit = unit,
		main = CreateContainer(unit, "Main", "BOTTOMLEFT", up),
		cc = CreateContainer(unit, "CC", "BOTTOMLEFT", up),
		buff = CreateContainer(unit, "Buff", "TOPLEFT", down),
	}

	-- Main groups are mutually exclusive when priority highlighting is enabled.
	AddGroup(bundle.main, "priority", "HARMFUL|PLAYER", 1, BORDER_IMPORTANT,
		{ nameplateShowPersonal = true, isPriorityAura = true })
	AddGroup(bundle.main, "mine", "HARMFUL|PLAYER", 2, BORDER_NORMAL,
		{ nameplateShowPersonal = true, isPriorityAura = false })

	AddGroup(bundle.cc, "cc", "HARMFUL|CROWD_CONTROL", 1, BORDER_CC)

	-- BIG_DEFENSIVE and EXTERNAL_DEFENSIVE must be separate groups: combining both positive
	-- components in one filter is an intersection, not an OR operation.
	AddGroup(bundle.buff, "purge", "HELPFUL|RAID_PLAYER_DISPELLABLE", 1, BORDER_PURGE)
	AddGroup(bundle.buff, "bigDefensive", "HELPFUL|BIG_DEFENSIVE", 2, BORDER_DEFENSIVE)
	AddGroup(bundle.buff, "externalDefensive", "HELPFUL|EXTERNAL_DEFENSIVE|!BIG_DEFENSIVE", 3, BORDER_DEFENSIVE)
	AddGroup(bundle.buff, "generic", "HELPFUL", 4, BORDER_BUFF)

	bundles[unit] = bundle
end

function Auras.Initialize()
	if initialized then return supported end
	initialized = true
	if not HasAuraContainerTemplate() then return false end

	for i = 1, NAMEPLATE_MAX do
		CreateBundle("nameplate" .. i)
	end
	-- Flipped only once every bundle exists. Setting it before the loop let an error mid-loop
	-- leave the module claiming it was healthy (IsSupported() == true) while `bundles` was empty,
	-- so Attach silently no-opped forever with nothing further logged.
	supported = true
	return true
end

local function CreateClipRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetClipsChildren(true)
	return row
end

function Auras.Create(f)
	if f.auras then return end
	f.auras = CreateClipRow(f)
	f.auraCC = CreateClipRow(f)
	f.auraBuff = CreateClipRow(f)
end

local function RowWidth(w, count)
	return math.max(1, ((w + GAP) * count) - GAP)
end

function Auras.Layout(f)
	if not f.auras then return end
	local a = AuraConfig()
	local w, h = a.w or 26, a.h or 26
	local mainCount = math.max(1, math.min(a.max or 4, MAX_POOL))
	local buffCount = math.max(1, math.min(a.buffMax or 3, MAX_POOL))
	local alpha = a.alpha or 0.85

	f.auras:SetSize(RowWidth(w, mainCount), h)
	f.auras:ClearAllPoints()
	f.auras:SetPoint("BOTTOMLEFT", f.hb, "TOPLEFT", 0, a.yOffset or 5)
	f.auras:SetAlpha(alpha)

	f.auraCC:SetSize(RowWidth(w, CC_MAX), h)
	f.auraCC:ClearAllPoints()
	f.auraCC:SetPoint("BOTTOMLEFT", f.hb, "TOPRIGHT", 0, 0)
	f.auraCC:SetAlpha(alpha)

	f.auraBuff:SetSize(RowWidth(w, buffCount), h)
	f.auraBuff:ClearAllPoints()
	f.auraBuff:SetPoint("TOPLEFT", f.hb, "BOTTOMRIGHT", 0, 0)
	f.auraBuff:SetAlpha(alpha)
end

local function AttachRecord(record, row)
	if record.parent == row then return end
	record.container:SetParent(row)
	record.container:ClearAllPoints()
	record.container:SetPoint(record.anchorPoint, row, record.anchorPoint, 0, 0)
	record.parent = row
end

local function RestyleRecord(record, a)
	if not CanTouchAuraButtons() then
		record.needsRestyle = true
		return
	end
	for _, button in ipairs(record.buttons) do
		ApplyButtonAppearance(button, a)
	end
	record.needsRestyle = false
end

local function ConfigureGroup(record, key, filter, candidateFilters, maxCount, index, w, h)
	local c = record.container
	c:SetAuraGroupFilterString(key, filter .. NP)
	c:SetAuraGroupCandidateFilters(key, candidateFilters)
	c:SetAuraGroupMaxFrameCount(key, maxCount)
	c:SetAuraGroupSortMethod(key, AuraContainerSortMethod.Expiration, AuraContainerSortDirection.Normal)
	c:SetAuraGroupLayout(key, GroupLayout(index, w, h))
end

local function ConfigureMain(bundle, a, w, h, mainCount)
	local wantPriority = a.important ~= false
	local wantMine = a.mine ~= false
	local filter = "HARMFUL|PLAYER"
	if a.cc ~= false then filter = filter .. "|!CROWD_CONTROL" end

	ConfigureGroup(bundle.main, "priority", filter,
		{ nameplateShowPersonal = true, isPriorityAura = true },
		wantPriority and mainCount or 0, 1, w, h)

	local mineCandidates = { nameplateShowPersonal = true }
	if wantPriority then mineCandidates.isPriorityAura = false end
	ConfigureGroup(bundle.main, "mine", filter, mineCandidates,
		wantMine and mainCount or 0, 2, w, h)
end

local function ConfigureCC(bundle, a, w, h)
	ConfigureGroup(bundle.cc, "cc", "HARMFUL|CROWD_CONTROL", nil,
		a.cc ~= false and CC_MAX or 0, 1, w, h)
end

local function ConfigureBuffs(bundle, f, a, w, h, buffCount)
	local wantPurge = a.purge ~= false and ns.playerCanPurge == true
	local wantDefensive = a.defensive ~= false and f.group == ENEMY_PLAYER
	local wantGeneric = a.buffs == true

	ConfigureGroup(bundle.buff, "purge", "HELPFUL|RAID_PLAYER_DISPELLABLE", nil,
		wantPurge and buffCount or 0, 1, w, h)

	local purgeExclusion = wantPurge and "|!RAID_PLAYER_DISPELLABLE" or ""
	ConfigureGroup(bundle.buff, "bigDefensive", "HELPFUL|BIG_DEFENSIVE" .. purgeExclusion, nil,
		wantDefensive and buffCount or 0, 2, w, h)
	ConfigureGroup(bundle.buff, "externalDefensive",
		"HELPFUL|EXTERNAL_DEFENSIVE|!BIG_DEFENSIVE" .. purgeExclusion, nil,
		wantDefensive and buffCount or 0, 3, w, h)

	local genericFilter = "HELPFUL"
	if wantPurge then genericFilter = genericFilter .. "|!RAID_PLAYER_DISPELLABLE" end
	if wantDefensive then
		genericFilter = genericFilter .. "|!BIG_DEFENSIVE|!EXTERNAL_DEFENSIVE"
	end
	ConfigureGroup(bundle.buff, "generic", genericFilter, nil,
		wantGeneric and buffCount or 0, 4, w, h)
end

local function ConfigureBundle(bundle, f)
	local a = AuraConfig()
	local w, h = a.w or 26, a.h or 26
	local mainCount = math.max(1, math.min(a.max or 4, MAX_POOL))
	local buffCount = math.max(1, math.min(a.buffMax or 3, MAX_POOL))

	ConfigureMain(bundle, a, w, h, mainCount)
	ConfigureCC(bundle, a, w, h)
	ConfigureBuffs(bundle, f, a, w, h, buffCount)

	RestyleRecord(bundle.main, a)
	RestyleRecord(bundle.cc, a)
	RestyleRecord(bundle.buff, a)

	local enabled = a.enabled ~= false
	bundle.main.container:SetEnabled(enabled)
	bundle.cc.container:SetEnabled(enabled)
	bundle.buff.container:SetEnabled(enabled)
end

function Auras.Attach(f, unit)
	if not f or not unit then return end
	-- Bundles are built once at login so per-nameplate setup isn't paid on every
	-- NAME_PLATE_UNIT_ADDED. This is a cost-placement choice, NOT an API requirement: AddAuraGroup
	-- has no login gate, and Blizzard's own provider allocates further batches on demand while
	-- auras are secret. The up-front batch exists to obfuscate aura COUNTS, not to pin setup to
	-- login. (The previous comment here asserted a Blizzard constraint that does not exist.)
	if not initialized or not supported then return end

	local bundle = bundles[unit]
	if not bundle then
		Auras.Clear(f)
		return
	end

	Auras.Create(f)
	if f.dnpAuraBundle and f.dnpAuraBundle ~= bundle then Auras.Clear(f) end
	if bundle.owner and bundle.owner ~= f then
		bundle.owner.dnpAuraBundle = nil
		bundle.owner.dnpAuraUnit = nil
	end
	bundle.owner = f
	AttachRecord(bundle.main, f.auras)
	AttachRecord(bundle.cc, f.auraCC)
	AttachRecord(bundle.buff, f.auraBuff)
	f.dnpAuraBundle = bundle
	f.dnpAuraUnit = unit
	ConfigureBundle(bundle, f)
end

function Auras.Refresh(f)
	if f and f.dnpAuraUnit then Auras.Attach(f, f.dnpAuraUnit) end
end

function Auras.Clear(f)
	local bundle = f and f.dnpAuraBundle
	if not bundle then return end
	if bundle.owner == f then
		bundle.main.container:SetEnabled(false)
		bundle.cc.container:SetEnabled(false)
		bundle.buff.container:SetEnabled(false)
		bundle.owner = nil
	end
	f.dnpAuraBundle = nil
	f.dnpAuraUnit = nil
end

function Auras.IsSupported()
	return supported
end
