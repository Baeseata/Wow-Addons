-- DodoGrid :: Auras.lua
-- Friendly party/raid aura indicators for Retail 12.1.
--
-- Restricted auras are owned end-to-end by Blizzard's CustomAuraContainerTemplate. This module
-- declares fixed filters and presentation sinks; it never enumerates aura-event data or reads
-- an aura instance in addon Lua.

local ADDON, ns = ...

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local COUNT_TEMPLATE = _G.NumberFontNormalSmall and "NumberFontNormalSmall" or nil
local TRIM = 0.08
local GAP = 1
local MINE_MAX = 6

local CENTER_IMPORTANT = { 1, 0.65, 0, 1 }
local CENTER_CC        = { 0.85, 0.10, 0.10, 1 }
local MINE_BORDER      = { 0, 0, 0, 0.9 }
local DISPEL_FALLBACK  = { 0.62, 0.30, 1.00, 1 }

-- Center categories use one secure aura slot each and overlap at the same point. Frame level chooses
-- the winner; when a higher-priority slot is empty Blizzard hides it and the next one shows through.
-- Slots allocate one button apiece, avoiding the ten-button batch that every aura group preallocates.
local CENTER_SEQUENCES = {
	raid   = { "raid", "raidCombat", "dispel", "cc" },
	dispel = { "dispel", "raid", "raidCombat", "cc" },
	cc     = { "cc", "raid", "raidCombat", "dispel" },
}

local CENTER_FILTERS = {
	raid       = "HARMFUL|RAID",
	raidCombat = "HARMFUL|RAID_IN_COMBAT",
	dispel     = "HARMFUL|RAID_PLAYER_DISPELLABLE",
	cc         = "HARMFUL|CROWD_CONTROL",
}

local Auras = {}
ns.Auras = Auras

local bundles = setmetatable({}, { __mode = "k" })
local errorReported = false
local templateAvailable

----------------------------------------------------------------------------------------------------
-- Capability + failure containment
----------------------------------------------------------------------------------------------------
local function HasAuraContainerTemplate()
	if templateAvailable then return true end
	local getTemplateInfo = C_XMLUtil and C_XMLUtil.GetTemplateInfo
	if type(getTemplateInfo) ~= "function" then return false end
	local called, info = pcall(getTemplateInfo, "CustomAuraContainerTemplate")
	if called and info then templateAvailable = true end
	return templateAvailable == true
end

local function ErrorHandler(err)
	if not errorReported then
		errorReported = true
		local handler = geterrorhandler and geterrorhandler()
		if type(handler) == "function" then return handler(err) end
	end
	return err
end

local function DisableRecord(record)
	if record and record.container then
		pcall(record.container.SetEnabled, record.container, false)
	end
end

local function DisableBundle(bundle)
	if not bundle then return end
	DisableRecord(bundle.mine)
	DisableRecord(bundle.center)
	DisableRecord(bundle.dispel)
	bundle.failed = true
end

local function ProtectedCall(bundle, fn, construction)
	if not bundle or bundle.failed then return false end
	local ok = xpcall(fn, ErrorHandler)
	if ok then
		if not bundle.needsGeometry and not bundle.needsRestyle
			and not bundle.needsConfigRetry and not bundle.needsRefreshRetry then
			bundle.consecutiveRuntimeFailures = 0
		end
		return true
	end

	if construction then
		DisableBundle(bundle)
	else
		-- A restriction transition can reject a post-construction write for one frame. Keep that
		-- failure local and retry after the restriction lifts; only quarantine a cell after repeats.
		bundle.consecutiveRuntimeFailures = (bundle.consecutiveRuntimeFailures or 0) + 1
		bundle.needsGeometry = true
		bundle.needsRestyle = true
		bundle.needsRefreshRetry = true
		bundle.geometryKey = nil
		bundle.restyleKey = nil
		bundle.mineConfigKey = nil
		bundle.centerConfigKey = nil
		bundle.dispelConfigKey = nil
		bundle.needsConfigRetry = true
		if bundle.consecutiveRuntimeFailures >= 3 then DisableBundle(bundle) end
	end
	return false
end

local function CanTouchAuraButtons()
	local shouldBeSecret = C_Secrets and C_Secrets.ShouldAurasBeSecret
	if type(shouldBeSecret) == "function" then
		local ok, secret = pcall(shouldBeSecret)
		if not ok or secret then return false end
	end
	if InCombatLockdown and InCombatLockdown() then return false end
	return true
end

local function CanChangeProtectedGeometry()
	return not (InCombatLockdown and InCombatLockdown())
end

----------------------------------------------------------------------------------------------------
-- Dispel-school color curve. Blizzard evaluates it on the secret aura and applies the result to the
-- registered border textures; addon Lua never receives or branches on the aura's dispel type.
----------------------------------------------------------------------------------------------------
local function MakeDispelCurve()
	if not (C_CurveUtil and C_CurveUtil.CreateColorCurve
		and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step) then
		return nil
	end

	local ok, curve = pcall(function()
		local value = C_CurveUtil.CreateColorCurve()
		if not value then return nil end
		value:SetType(Enum.LuaCurveType.Step)
		local function Color(r, g, b)
			return CreateColor and CreateColor(r, g, b, 1) or { r = r, g = g, b = b, a = 1 }
		end
		value:AddPoint(0,  Color(0.80, 0.00, 0.00))
		value:AddPoint(1,  Color(0.20, 0.60, 1.00))
		value:AddPoint(2,  Color(0.60, 0.00, 1.00))
		value:AddPoint(3,  Color(0.60, 0.40, 0.00))
		value:AddPoint(4,  Color(0.00, 0.70, 0.00))
		value:AddPoint(9,  Color(0.80, 0.20, 0.20))
		value:AddPoint(11, Color(0.80, 0.20, 0.20))
		return value
	end)
	return ok and curve or nil
end

local DISPEL_CURVE = MakeDispelCurve()
local DISPEL_TEXTURE_STYLE = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
	and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset

----------------------------------------------------------------------------------------------------
-- Presentation primitives. Every child of a CustomAuraButton is completely configured before it is
-- handed to a Set*/Add* sink; those calls synchronously update the display.
----------------------------------------------------------------------------------------------------
local function DisableAuraButtonMouse(button)
	button:EnableMouse(false)
	if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
	if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
end

local function CreateEdgeTextures(parent, color)
	local edges = {}
	for i = 1, 4 do
		local edge = parent:CreateTexture(nil, "OVERLAY")
		edge:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
		edges[i] = edge
	end
	return edges
end

local function SetEdgeThickness(edges, thickness)
	local t = math.max(1, thickness or 1)
	local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]

	top:ClearAllPoints()
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(t)

	bottom:ClearAllPoints()
	bottom:SetPoint("BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT")
	bottom:SetHeight(t)

	left:ClearAllPoints()
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(t)

	right:ClearAllPoints()
	right:SetPoint("TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT")
	right:SetWidth(t)
end

local function CanRegisterDispelTextures(button)
	return type(button.AddDispelTypeTexture) == "function" and DISPEL_TEXTURE_STYLE ~= nil
end

local function RegisterDispelTextures(button, edges)
	if not CanRegisterDispelTextures(button) then
		for _, edge in ipairs(edges) do
			edge:SetColorTexture(DISPEL_FALLBACK[1], DISPEL_FALLBACK[2],
				DISPEL_FALLBACK[3], DISPEL_FALLBACK[4])
		end
		return
	end

	local options = {
		style = DISPEL_TEXTURE_STYLE,
		showWhenHarmful = true,
		showWhenHelpful = false,
		showWithoutDispelType = true,
		customDispelColorCurve = DISPEL_CURVE,
	}
	for _, edge in ipairs(edges) do button:AddDispelTypeTexture(edge, options) end
end

local function AuraConfig()
	return (ns.db and ns.db.auras) or {}
end

local function ConfigKey(...)
	local parts = {}
	for index = 1, select("#", ...) do
		parts[index] = tostring(select(index, ...))
	end
	return table.concat(parts, "\31")
end

local function CenterLevel(record, key, a)
	local important = a.important or {}
	local sequence = CENTER_SEQUENCES[important.centerPriority] or CENTER_SEQUENCES.raid
	for index, candidate in ipairs(sequence) do
		if candidate == key then
			-- One slot owns a button, cooldown (+1), and overlay (+2). Leave a full level between
			-- visual stacks so a lower-priority cooldown/count can never bleed over the winner.
			return record.baseLevel + ((#sequence - index + 1) * 4)
		end
	end
	return record.baseLevel
end

local function ApplyIconAppearance(button, a)
	local mine = a.mine or {}
	local important = a.important or {}
	local size
	if button.dgAuraRole == "mine" then
		size = mine.size or 13
	else
		size = important.size or 20
	end

	button:SetSize(size, size)
	button.dgCount:SetFont(FONT, math.max(7, size - (button.dgAuraRole == "mine" and 14 or 12)), "OUTLINE")
	button.dgCount:SetShown(a.showStacks ~= false)
	button.dgCooldown:SetHideCountdownNumbers(a.showTimer == false)
	SetEdgeThickness(button.dgEdges, 1)
end

local function ApplyCenterSlotGeometry(record, button, a)
	local important = a.important or {}
	local level = CenterLevel(record, button.dgCenterKey, a)
	button:ClearAllPoints()
	button:SetPoint("CENTER", record.anchor, "CENTER", important.xOff or 0, important.yOff or 0)
	button:SetFrameLevel(level)
	button.dgCooldown:SetFrameLevel(level + 1)
	button.dgOverlay:SetFrameLevel(level + 2)
end

local function ApplyDispelOverlayAppearance(button, a)
	local dispel = a.dispel or {}
	local width = (ns.db and ns.db.width) or 72
	local height = (ns.db and ns.db.height) or 36
	button:SetSize(width + 2, height + 2)
	button:ClearAllPoints()
	button:SetPoint("TOPLEFT", button.dgAnchor, "TOPLEFT", -1, 1)
	SetEdgeThickness(button.dgEdges, dispel.thickness or 2)
end

local function CreateIconInitializer(record, role, border, centerKey)
	return function(button)
		DisableAuraButtonMouse(button)
		button.dgAuraRole = role
		button.dgCenterKey = centerKey

		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", 1, -1)
		icon:SetPoint("BOTTOMRIGHT", -1, 1)
		icon:SetTexCoord(TRIM, 1 - TRIM, TRIM, 1 - TRIM)

		local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
		cooldown:SetAllPoints(icon)
		cooldown:SetReverse(true)
		cooldown:SetDrawEdge(true)
		if cooldown.SetCountdownAbbrevThreshold then cooldown:SetCountdownAbbrevThreshold(60) end
		if cooldown.SetMinimumCountdownDuration then cooldown:SetMinimumCountdownDuration(0) end
		cooldown:SetFrameLevel(button:GetFrameLevel() + 1)

		-- Keep the border and stack count above the cooldown swipe. The count is still a valid
		-- descendant sink for SetApplicationCount, matching Blizzard's ownership rules.
		local overlay = CreateFrame("Frame", nil, button)
		overlay:SetAllPoints(button)
		overlay:SetFrameLevel(cooldown:GetFrameLevel() + 1)

		local count = overlay:CreateFontString(nil, "OVERLAY", COUNT_TEMPLATE)
		count:SetPoint("BOTTOMRIGHT", 1, -1)
		count:SetJustifyH("RIGHT")

		local dynamicDispel = border == "dispel"
		local edgeColor = dynamicDispel and { 1, 1, 1, 1 } or border
		local edges = CreateEdgeTextures(overlay, edgeColor)

		button.dgIcon = icon
		button.dgCooldown = cooldown
		button.dgCount = count
		button.dgEdges = edges
		button.dgOverlay = overlay
		ApplyIconAppearance(button, AuraConfig())
		if centerKey then ApplyCenterSlotGeometry(record, button, AuraConfig()) end

		-- Register sinks only after every region has its final font, size, anchors, and baseline style.
		button:SetIcon(icon)
		button:SetDurationCooldown(cooldown)
		button:SetApplicationCount(count)
		if dynamicDispel then RegisterDispelTextures(button, edges) end

		record.buttons[#record.buttons + 1] = button
	end
end

local function CreateDispelOverlayInitializer(record)
	return function(button)
		DisableAuraButtonMouse(button)
		button.dgAuraRole = "dispelOverlay"
		button.dgAnchor = record.anchor
		local dynamicDispel = CanRegisterDispelTextures(button)
		local edges = CreateEdgeTextures(button, dynamicDispel and { 1, 1, 1, 1 } or DISPEL_FALLBACK)
		button.dgEdges = edges
		ApplyDispelOverlayAppearance(button, AuraConfig())
		RegisterDispelTextures(button, edges)
		record.buttons[#record.buttons + 1] = button
	end
end

----------------------------------------------------------------------------------------------------
-- Container construction
----------------------------------------------------------------------------------------------------
local function GroupLayout(index, width, height)
	return {
		elementSpacing = GAP,
		lineSpacing = 0,
		groupSpacing = GAP,
		groupLineSpacing = 0,
		forceNewLine = false,
		elementWidth = width,
		elementHeight = height,
		layoutIndex = index,
	}
end

local function NewRecord(parent, unit, frameLevel)
	local container = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	container:EnableMouse(false)
	-- Match Blizzard's supported construction order: bind the permanent static token before groups or
	-- slots are registered, then keep the container disabled until initial configuration is complete.
	container:SetEnabled(false)
	container:SetUnit(unit)
	container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	container:SetSize(1, 1)
	container:SetFlowLayoutAnchorPoint("TOPLEFT")
	container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
	container:SetFlowLayoutMaximumLineSize(math.huge)
	if frameLevel then container:SetFrameLevel(frameLevel) end
	return { container = container, buttons = {}, slots = {}, anchor = parent, baseLevel = frameLevel or 1 }
end

local function AddGroup(record, key, filter, initializer, width, height)
	record.container:AddAuraGroup(key, filter, {
		maxFrameCount = 0,
		sortMethod = AuraContainerSortMethod.Expiration,
		sortDirection = AuraContainerSortDirection.Normal,
		candidateFilters = {},
		initializeFrame = initializer,
		layout = GroupLayout(1, width, height),
	})
end

local function AddSlot(record, key, filter, initializer)
	local button = record.container:AddAuraSlot(key, filter, {
		sortMethod = AuraContainerSortMethod.Expiration,
		sortDirection = AuraContainerSortDirection.Normal,
		candidateFilters = {},
		initializeFrame = initializer,
	})
	record.slots[key] = button
	return button
end

local function BuildBundle(bundle, button, unit)
	local baseLevel = button:GetFrameLevel() or 1
	local a = AuraConfig()
	local mine = a.mine or {}
	local mineSize = mine.size or 13

	bundle.mine = NewRecord(button, unit, baseLevel + 5)
	AddGroup(bundle.mine, "mine", "HELPFUL|PLAYER",
		CreateIconInitializer(bundle.mine, "mine", MINE_BORDER), mineSize, mineSize)

	bundle.center = NewRecord(button, unit, baseLevel + 7)
	AddSlot(bundle.center, "raid", CENTER_FILTERS.raid,
		CreateIconInitializer(bundle.center, "center", CENTER_IMPORTANT, "raid"))
	AddSlot(bundle.center, "raidCombat", CENTER_FILTERS.raidCombat,
		CreateIconInitializer(bundle.center, "center", CENTER_IMPORTANT, "raidCombat"))
	AddSlot(bundle.center, "dispel", CENTER_FILTERS.dispel,
		CreateIconInitializer(bundle.center, "center", "dispel", "dispel"))
	AddSlot(bundle.center, "cc", CENTER_FILTERS.cc,
		CreateIconInitializer(bundle.center, "center", CENTER_CC, "cc"))

	bundle.dispel = NewRecord(button, unit, baseLevel + 9)
	AddSlot(bundle.dispel, "dispel", CENTER_FILTERS.dispel,
		CreateDispelOverlayInitializer(bundle.dispel))

end

----------------------------------------------------------------------------------------------------
-- Runtime configuration. Container inbound methods remain the only path used while auras are secret.
----------------------------------------------------------------------------------------------------
local function ApplyGeometry(bundle, a)
	local mine = a.mine or {}

	bundle.mine.container:ClearAllPoints()
	bundle.mine.container:SetPoint("BOTTOMLEFT", bundle.button, "BOTTOMLEFT",
		2 + (mine.xOff or 0), 2 + (mine.yOff or 0))
	bundle.geometryKey = ConfigKey(mine.xOff or 0, mine.yOff or 0)
	bundle.needsGeometry = false
end

local function RestyleButtons(bundle, a)
	for _, button in ipairs(bundle.mine.buttons) do ApplyIconAppearance(button, a) end
	for _, button in ipairs(bundle.center.buttons) do
		ApplyIconAppearance(button, a)
		ApplyCenterSlotGeometry(bundle.center, button, a)
	end
	for _, button in ipairs(bundle.dispel.buttons) do ApplyDispelOverlayAppearance(button, a) end
	local mine = a.mine or {}
	local important = a.important or {}
	local dispel = a.dispel or {}
	bundle.restyleKey = ConfigKey(a.showTimer ~= false, a.showStacks ~= false,
		mine.size or 13, important.size or 20, important.xOff or 0, important.yOff or 0,
		important.centerPriority or "raid", dispel.thickness or 2,
		(ns.db and ns.db.width) or 72, (ns.db and ns.db.height) or 36)
	bundle.needsRestyle = false
end

local function ConfigureMine(bundle, a)
	local mine = a.mine or {}
	local size = mine.size or 13
	local maxCount = math.max(1, math.min(mine.max or 3, MINE_MAX))
	local candidates = mine.hidePermanent ~= false and { maxDuration = math.huge } or nil
	local configKey = ConfigKey(a.enabled ~= false, mine.enabled ~= false, size, maxCount,
		mine.hidePermanent ~= false)
	if bundle.mineConfigKey == configKey then return end
	local c = bundle.mine.container
	c:SetAuraGroupCandidateFilters("mine", candidates)
	c:SetAuraGroupMaxFrameCount("mine", maxCount)
	c:SetAuraGroupSortMethod("mine", AuraContainerSortMethod.Expiration, AuraContainerSortDirection.Normal)
	c:SetAuraGroupLayout("mine", GroupLayout(1, size, size))
	c:SetEnabled(a.enabled ~= false and mine.enabled ~= false)
	bundle.mineConfigKey = configKey
end

local function ConfigureCenter(bundle, a)
	local important = a.important or {}
	local configKey = ConfigKey(a.enabled ~= false, important.enabled ~= false,
		important.showCC ~= false)
	if bundle.centerConfigKey == configKey then return end

	local c = bundle.center.container
	for key in pairs(CENTER_FILTERS) do
		local candidates = key == "cc" and important.showCC == false and { maxDuration = 0 } or nil
		c:SetAuraSlotCandidateFilters(key, candidates)
		c:SetAuraSlotSortMethod(key, AuraContainerSortMethod.Expiration, AuraContainerSortDirection.Normal)
	end
	c:SetEnabled(a.enabled ~= false and important.enabled ~= false)
	bundle.centerConfigKey = configKey
end

local function ConfigureDispel(bundle, a)
	local dispel = a.dispel or {}
	local configKey = ConfigKey(a.enabled ~= false, dispel.enabled ~= false)
	if bundle.dispelConfigKey == configKey then return end
	local c = bundle.dispel.container
	c:SetAuraSlotSortMethod("dispel", AuraContainerSortMethod.Expiration, AuraContainerSortDirection.Normal)
	c:SetEnabled(a.enabled ~= false and dispel.enabled ~= false)
	bundle.dispelConfigKey = configKey
end

local function ApplyLayout(bundle)
	local a = AuraConfig()
	local mine = a.mine or {}
	local geometryKey = ConfigKey(mine.xOff or 0, mine.yOff or 0)
	if bundle.geometryKey ~= geometryKey and CanChangeProtectedGeometry() then
		ApplyGeometry(bundle, a)
	elseif bundle.geometryKey ~= geometryKey then
		bundle.needsGeometry = true
	end

	local important = a.important or {}
	local dispel = a.dispel or {}
	local restyleKey = ConfigKey(a.showTimer ~= false, a.showStacks ~= false,
		mine.size or 13, important.size or 20, important.xOff or 0, important.yOff or 0,
		important.centerPriority or "raid", dispel.thickness or 2,
		(ns.db and ns.db.width) or 72, (ns.db and ns.db.height) or 36)
	if bundle.restyleKey ~= restyleKey and CanTouchAuraButtons() then
		RestyleButtons(bundle, a)
	elseif bundle.restyleKey ~= restyleKey then
		bundle.needsRestyle = true
	end

	ConfigureMine(bundle, a)
	ConfigureCenter(bundle, a)
	ConfigureDispel(bundle, a)
	bundle.needsConfigRetry = false
	bundle.cleared = false
end

local function UpdateAllContainers(bundle)
	bundle.mine.container:UpdateAllAuras()
	bundle.center.container:UpdateAllAuras()
	bundle.dispel.container:UpdateAllAuras()
end

----------------------------------------------------------------------------------------------------
-- Public API used by Core.lua
----------------------------------------------------------------------------------------------------
function Auras.Create(button, unit)
	if not button or not HasAuraContainerTemplate() then return false end
	local existing = bundles[button]
	if existing then return not existing.failed end
	if InCombatLockdown and InCombatLockdown() then return false end

	if type(unit) ~= "string" then
		local ok, value = pcall(button.GetAttribute, button, "unit")
		if ok then unit = value end
	end
	if type(unit) ~= "string" or unit == "" then return false end

	local bundle = { button = button, unit = unit }
	bundles[button] = bundle
	local ok = ProtectedCall(bundle, function()
		BuildBundle(bundle, button, unit)
	end, true)
	return ok
end

function Auras.Layout(button)
	local bundle = bundles[button]
	if not bundle or bundle.failed then return false end
	return ProtectedCall(bundle, function() ApplyLayout(bundle) end)
end

function Auras.Refresh(button)
	if not button then return false end
	local bundle = bundles[button]
	local created = false
	if not bundle then
		local unit
		local ok, value = pcall(button.GetAttribute, button, "unit")
		if ok then unit = value end
		if not Auras.Create(button, unit) then return false end
		bundle = bundles[button]
		created = true
	end
	if not bundle or bundle.failed then return false end
	return ProtectedCall(bundle, function()
		-- Normal callers use Layout then Refresh. Only a newly created or explicitly cleared bundle
		-- needs Refresh itself to restore its current configuration first.
		if created or bundle.cleared then ApplyLayout(bundle) end
		UpdateAllContainers(bundle)
		bundle.needsRefreshRetry = false
	end)
end

function Auras.Clear(button)
	local bundle = bundles[button]
	if not bundle then return end
	DisableRecord(bundle.mine)
	DisableRecord(bundle.center)
	DisableRecord(bundle.dispel)
	bundle.mineConfigKey = nil
	bundle.centerConfigKey = nil
	bundle.dispelConfigKey = nil
	bundle.cleared = true
end

function Auras.FlushDeferred()
	local canGeometry = CanChangeProtectedGeometry()
	local canRestyle = CanTouchAuraButtons()
	if not canGeometry and not canRestyle then return false end

	local refreshed = false
	for _, bundle in pairs(bundles) do
		if not bundle.failed and (bundle.needsGeometry or bundle.needsRestyle
			or bundle.needsConfigRetry or bundle.needsRefreshRetry) then
			local ok = ProtectedCall(bundle, function()
				-- ApplyLayout also retries filter/enable changes whose first inbound call was rejected.
				-- Its own guards leave button geometry/style deferred until both restrictions are clear.
				ApplyLayout(bundle)
				if bundle.needsRefreshRetry then
					UpdateAllContainers(bundle)
					bundle.needsRefreshRetry = false
				end
			end)
			refreshed = ok or refreshed
		end
	end
	return refreshed
end

function Auras.IsSupported()
	return HasAuraContainerTemplate()
end
