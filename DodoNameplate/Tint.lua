-- DodoNameplate :: Tint.lua
-- Per-spellID health-bar tinting for ENEMY nameplates, WITHOUT ever reading an aura.
--
-- Mechanism (GOTCHAS.md S5, verified end-to-end on a live plate 2026-08-17): a texture whose PARENT
-- is a CustomAuraButton draws exactly while that button is shown, and Blizzard shows the button as
-- `secretwrap(auraData ~= nil)`. So we hand Blizzard a coloured texture per spell and let IT switch
-- the texture on. This module performs zero comparisons on aura data -- it never learns which aura
-- is up, it only supplies filters and paint.
--
--   AND       = nesting. A container whose parent is another rule's button only renders while that
--               button is shown, so ancestry IS the conjunction.
--   NOT       = occlusion. "SW:P but not VT" needs no expression at all: the both-DoTs layer sits on
--               top and covers the SW:P layer. "Neither DoT" is the health bar's own colour showing
--               through, because nothing is painted over it.
--   Priority  = draw order, and it falls out for free. A longer AND-chain nests deeper, so its
--               button lands on a HIGHER frame level automatically; same-depth layers are separated
--               by OVERLAY sublevel = layer index. More specific therefore always wins.
--
-- Absence has no direct expression. Do not design a rule that needs one (PlateTweaks builds it by
-- occluding with an opaque replica of the bar); order the layers so the "neither" case is the bar.

local ADDON, ns = ...
local ENEMY_PLAYER = ns.GROUP and ns.GROUP.ENEMY_PLAYER

local NAMEPLATE_MAX = 40
-- "HARMFUL|PLAYER" = debuffs I applied. INCLUDE_NAME_PLATE_ONLY is mandatory on every filter string:
-- without it the client actively FILTERS OUT auras flagged nameplate-only, which is exactly the set
-- a nameplate addon wants (see GOTCHAS S3).
local DEFAULT_FILTER = "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY"
local MAX_SUBLEVEL = 7   -- OVERLAY draw sublevels run -8..7

---------------------------------------------------------------------------------------------------
-- Rule table
---------------------------------------------------------------------------------------------------
-- Keyed by specialization id. Each ruleset is a list of LAYERS ordered lowest priority first; a
-- layer is a set of spell IDs that must ALL be present (AND) plus the colour to paint when they are.
-- Nothing here is Shadow-specific: adding a spec means adding an entry.
--
-- `flatThreat` drops the role-aware threat red/blue for this spec (Plate.lua ThreatColor). Shadow
-- keeps a DoT on nearly everything in an instance, so the threat colour would be painted over
-- almost all of the time -- Jerry cut it 2026-08-17 so the "no DoT" state is a stable red.
--
-- The spell ID must be the ID of the AURA, which is not always the ID of the cast that applies it
-- (Rend casts 772 and applies 388539). A wrong ID simply never lights up, which is indistinguishable
-- from the whole mechanism not working -- verify a new entry against a real aura, not a tooltip.
local RULESETS = {
	-- Shadow Priest
	[258] = {
		class = "PRIEST",
		label = "Shadow Priest",
		flatThreat = true,
		layers = {
			{ spells = { 589 },        color = { 1.00, 0.55, 0.10 } },   -- Shadow Word: Pain -> orange
			{ spells = { 34914 },      color = { 0.65, 0.30, 1.00 } },   -- Vampiric Touch  -> purple
			{ spells = { 589, 34914 }, color = { 0.15, 0.50, 1.00 } },   -- both            -> blue
		},
	},
}

---------------------------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------------------------
local Tint = {}
ns.Tint = Tint

local sets = {}          -- [specID] = { rules = <ruleset>, bundles = { [unitToken] = bundle } }
local activeSpec         -- specID whose set is currently switched on; nil = tinting off
local initialized = false
local supported = false
local slotCount, groupCount = 0, 0   -- how each rule got registered (report only, never a decision)
local anchorRefusals = 0
local buildErrors = {}

local function TintConfig()
	return (ns.db and ns.db.tint) or (ns.defaults and ns.defaults.tint) or {}
end

-- Our own specialization should never be secret -- a hostile player's is, but this is us. The callers
-- guard it anyway before using it as a table key or handing it to tostring, because "should never"
-- is not a guard and a secret used as an index throws (GOTCHAS S1). C_SpecializationInfo is the 12.x
-- path; the globals are the deprecated-but-working fallback (same shape as DodoInspect's).
local function PlayerSpecID()
	local idx
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
		idx = C_SpecializationInfo.GetSpecialization()
	elseif type(GetSpecialization) == "function" then
		idx = GetSpecialization()
	end
	if type(idx) ~= "number" then return nil end
	if type(GetSpecializationInfo) == "function" then
		return (GetSpecializationInfo(idx))
	end
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
		return (C_SpecializationInfo.GetSpecializationInfo(idx))
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------------
-- One "only this spell" rule on `container`. AddAuraSlot pools ONE frame; AddAuraGroup pools TEN
-- (CustomAuraContainerConstants.FrameCreationBatchSize, deliberately high to obfuscate aura counts),
-- so take the slot when it is there.
--
-- Ask THIS container at THIS moment -- never cache the answer. Blizzard_AuraContainer can load late;
-- an early probe answers "unavailable", caches it, and the whole session silently runs the ten-frame
-- path while the feature still looks switched on (GOTCHAS S5 constraint 4).
local function AddSpell(container, key, spellID, filter, initFn)
	local slot = type(container.AddAuraSlot) == "function"
		and type(container.SetAuraSlotCandidateFilters) == "function"
	local candidates = { includeSpellIDs = { [spellID] = true } }
	if slot then
		slotCount = slotCount + 1
		container:AddAuraSlot(key, filter, { initializeFrame = initFn })
		container:SetAuraSlotCandidateFilters(key, candidates)
	else
		groupCount = groupCount + 1
		container:AddAuraGroup(key, filter, { initializeFrame = initFn })
		container:SetAuraGroupCandidateFilters(key, candidates)
		container:SetAuraGroupMaxFrameCount(key, 1)
	end
end

-- Anchor to OUR proxy, never to the parent button: "our object anchored to theirs" is refused with
-- UntrustedLayoutScriptExecution; theirs-to-ours is fine (GOTCHAS S5 constraint 3).
--
-- Guarded, and this one really is harmless to lose: the container's own geometry is never read by
-- anything here, because the TEXTURES anchor to the proxy directly rather than to their container.
-- The count is reported by /dnp tint so a silent refusal still shows up somewhere.
local function NewContainer(parent, proxy)
	local c = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	c:SetEnabled(false)
	if not pcall(c.SetAllPoints, c, proxy) then anchorRefusals = anchorRefusals + 1 end
	c:SetFlowLayoutAnchorPoint("TOPLEFT")
	c:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
	c:SetFlowLayoutMaximumLineSize(math.huge)
	return c
end

-- The texture's PARENT is the aura button (that is the entire mechanism); its ANCHOR is the token's
-- proxy, which Attach re-points at the health bar's FILL. Anchoring to the fill and not to the whole
-- bar is what keeps the health level readable -- the tint replaces the fill colour instead of
-- covering the bar. PlateTweaks does the same (`AnchorToFill(tex, healthBar)`).
--
-- No SetIcon and no SetDurationCooldown on purpose: we want the button's VISIBILITY, not its icon.
local function PaintTexture(button, proxy, color, sublevel)
	local t = button:CreateTexture(nil, "OVERLAY", nil, math.min(sublevel, MAX_SUBLEVEL))
	t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	t:SetAllPoints(proxy)
	return t
end

-- One layer becomes a chain of nested containers: link N filters spells[N] and, inside its
-- initializeFrame, builds link N+1 as a child of the button that just appeared. The last link paints.
--
-- Every link is created INSIDE the previous link's initializeFrame because that instant is the only
-- legal moment: Blizzard_AuraContainerFrameProviders calls securecallfunction(initializeFrame, ...)
-- and applies DenyTaintedAccessWhenAurasAreSecret on the very next line. A late attachment is
-- refused everywhere auras are hidden -- a whole dungeon, not just its fights -- so the failure mode
-- is "works at the target dummy, does nothing in M+" (GOTCHAS S5 constraint 1).
local function BuildChain(ctx, depth, parent)
	local container = NewContainer(parent, ctx.bundle.proxy)
	local isLast = (depth == #ctx.spells)
	AddSpell(container, "tint", ctx.spells[depth], ctx.filter, function(button)
		if isLast then
			PaintTexture(button, ctx.bundle.proxy, ctx.color, ctx.sublevel)
		else
			local inner = BuildChain(ctx, depth + 1, button)
			-- The root is the switch; every inner link stays enabled and is gated by the visibility
			-- of the button it hangs from.
			inner:SetUnit(ctx.unit)
			inner:SetEnabled(true)
			ctx.bundle.nested = ctx.bundle.nested + 1
		end
	end)
	return container
end

-- The proxy is a permanent per-token stand-in for a health bar that does not exist yet. The textures
-- are built at login, inside initializeFrame, when no plate is attached to this token; they anchor to
-- the proxy, and Attach re-points the proxy at whichever plate now owns the token.
local function CreateBundle(unit, rules)
	local proxy = CreateFrame("Frame", nil, UIParent)
	proxy:SetSize(1, 1)
	-- Deliberately NOT hidden while building. SetEnabled(false) already stops the containers drawing,
	-- and building the frame batch under a hidden parent is a deviation from the path that was
	-- actually verified. If Blizzard ever deferred batch creation until first shown, the textures
	-- would be attached LATE -- which is refused wherever auras are hidden, so the bug would appear
	-- only inside instances. Not worth the guess for safety we already have. Attach/Clear may hide it
	-- afterwards; by then the buttons exist.

	local bundle = { proxy = proxy, roots = {}, nested = 0 }
	local filter = rules.filter or DEFAULT_FILTER
	for i, layer in ipairs(rules.layers) do
		if type(layer.spells) ~= "table" or #layer.spells == 0 then
			buildErrors[#buildErrors + 1] = ("layer %d has no spells"):format(i)
		else
			local root = BuildChain({
				bundle = bundle, unit = unit, spells = layer.spells,
				filter = layer.filter or filter, color = layer.color, sublevel = i,
			}, 1, proxy)
			root:SetUnit(unit)   -- permanent binding; never SetUnit(nil)
			bundle.roots[#bundle.roots + 1] = root
		end
	end
	return bundle
end

function Tint.Initialize()
	if initialized then return supported end
	initialized = true
	if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo
		and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate")) then
		return false
	end

	local _, class = UnitClass("player")
	if not class then return false end

	-- Build every ruleset belonging to this CLASS, not just the current spec's. initializeFrame is
	-- the only legal moment to attach the textures and it is refused wherever auras are hidden, so a
	-- respec inside a dungeon must not have to build anything. Spec changes only flip SetEnabled.
	for specID, rules in pairs(RULESETS) do
		if rules.class == class then
			local bundles = {}
			for i = 1, NAMEPLATE_MAX do
				bundles["nameplate" .. i] = CreateBundle("nameplate" .. i, rules)
			end
			sets[specID] = { rules = rules, bundles = bundles }
		end
	end
	if not next(sets) then return false end

	-- Flipped only once every bundle exists, so an error mid-build cannot leave the module claiming
	-- it is healthy while Attach silently no-ops forever (the shape Auras.lua was burnt by).
	supported = true
	Tint.RefreshSpec()
	return true
end

---------------------------------------------------------------------------------------------------
-- Activation
---------------------------------------------------------------------------------------------------
local function DisableSet(set)
	for _, bundle in pairs(set.bundles) do
		for _, c in ipairs(bundle.roots) do c:SetEnabled(false) end
		bundle.proxy:Hide()
		local owner = bundle.owner
		if owner then
			owner.dnpTintBundle = nil
			owner.dnpTintUnit = nil
			bundle.owner = nil
		end
	end
end

-- Recompute which spec's set is live. Cheap and idempotent; callers re-apply the plates afterwards.
function Tint.RefreshSpec()
	local want
	if supported then
		local spec = PlayerSpecID()
		-- Secret check first, before the nil compare and before the table index.
		if not ns.Guards.IsSecret(spec) and spec ~= nil and sets[spec] then want = spec end
	end
	if want == activeSpec then return activeSpec end
	if activeSpec then DisableSet(sets[activeSpec]) end
	activeSpec = want
	return activeSpec
end

function Tint.IsActive()
	if not (supported and activeSpec) then return false end
	return TintConfig().enabled ~= false
end

-- Plate.lua asks this before painting the threat colour. See `flatThreat` above.
function Tint.OverridesThreat()
	if not Tint.IsActive() then return false end
	return sets[activeSpec].rules.flatThreat == true
end

---------------------------------------------------------------------------------------------------
-- Attach / clear
---------------------------------------------------------------------------------------------------
function Tint.Clear(f)
	-- Before the early return, and unconditional: the rule is only meaningful while a tint region
	-- exists under it. A respec to a spec with no ruleset reaches Tint.Attach -> not IsActive ->
	-- here, and if this sat below the bundle check the plate would keep a black line across an
	-- otherwise plain class-coloured bar.
	if f and f.seam then f.seam:Hide() end

	local bundle = f and f.dnpTintBundle
	if not bundle then return end
	if bundle.owner == f then
		for _, c in ipairs(bundle.roots) do c:SetEnabled(false) end
		bundle.proxy:Hide()
		bundle.owner = nil
	end
	f.dnpTintBundle = nil
	f.dnpTintUnit = nil
end

function Tint.Attach(f, unit)
	if not f or not unit then return end
	if not Tint.IsActive() then Tint.Clear(f); return end

	local bundle = sets[activeSpec].bundles[unit]
	if not bundle then Tint.Clear(f); return end

	-- Plates and tokens are both recycled. Drop a stale pairing on either side before claiming this
	-- one, or a late clear from the previous owner switches off a freshly attached bundle.
	if f.dnpTintBundle and f.dnpTintBundle ~= bundle then Tint.Clear(f) end
	if bundle.owner and bundle.owner ~= f then
		bundle.owner.dnpTintBundle = nil
		bundle.owner.dnpTintUnit = nil
	end
	bundle.owner = f
	f.dnpTintBundle = bundle
	f.dnpTintUnit = unit

	-- Re-parent only when the plate actually changed: Style.Apply runs on every UNIT_FLAGS /
	-- UNIT_FACTION, and SetParent on a frame with Blizzard's aura containers hanging off it is not
	-- something to repeat for nothing.
	local proxy = bundle.proxy
	if proxy.dnpAnchoredTo ~= f.hb then
		proxy:SetParent(f.hb)
		proxy.dnpAnchoredTo = f.hb
	end

	-- Anchored to the FILL, not the bar, so the tint tracks the health level rather than covering it.
	--
	-- Enemy players get everything except a thin strip along the top, which stays class-coloured, so
	-- the plate carries two channels at full saturation (who is this / is my DoT on them). Hostile
	-- creatures take the whole fill -- they have no class-colour channel, so reserving a strip would
	-- only cost tint area. The textures never learn about any of this; they only anchor to this proxy.
	--
	-- Re-pointed every time rather than cached: the offset is derived from the CURRENT bar height, and
	-- a plate can change group under us (UNIT_FLAGS) or be relaid out with a new height.
	local fill = f.hb:GetStatusBarTexture() or f.hb
	proxy:ClearAllPoints()
	if f.group == ENEMY_PLAYER and f.splitY then
		-- f.splitY comes from LayoutPlate, which ran moments ago -- one derivation of the boundary,
		-- taken from the configured height rather than recomputed here.
		proxy:SetPoint("TOPLEFT", fill, "BOTTOMLEFT", 0, f.splitY)
		proxy:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
		-- The rule sits in the ns.TINT_SEAM pixels directly ABOVE the tint region, so it eats into
		-- neither channel: class strip on top, rule, tint below. Same fill anchor as the proxy, so
		-- the two shorten together. Re-pointed here rather than in LayoutPlate because this is the
		-- branch that already knows the plate is a tinted enemy player.
		if f.seam then
			f.seam:ClearAllPoints()
			f.seam:SetPoint("TOPLEFT", fill, "BOTTOMLEFT", 0, f.splitY + ns.TINT_SEAM)
			f.seam:SetPoint("TOPRIGHT", fill, "BOTTOMRIGHT", 0, f.splitY + ns.TINT_SEAM)
			f.seam:SetHeight(ns.TINT_SEAM)
			f.seam:Show()
		end
	else
		proxy:SetAllPoints(fill)
		-- Hostile creatures are one channel: nothing to separate, so no rule.
		if f.seam then f.seam:Hide() end
	end
	-- Unconditional, and after SetParent (which resets it): Blizzard re-levels nameplates to control
	-- overlap, so the offset has to be re-asserted rather than set once. Everything the containers
	-- create hangs below this level; Plate.lua's important-cast overlay and text layer sit above it.
	proxy:SetFrameLevel(f.hb:GetFrameLevel() + (ns.LEVEL_TINT or 2))
	proxy:Show()

	-- Tap-denied is plaintext, so this one branch is legal in Lua. A mob somebody else has claimed
	-- keeps its dimmed base colour rather than advertising our DoTs on it: no-loot outranks every
	-- tint layer, and switching the containers off is the whole implementation of that rule.
	local on = not ns.IsTapped(unit)
	for _, c in ipairs(bundle.roots) do c:SetEnabled(on) end
end

---------------------------------------------------------------------------------------------------
-- Report (/dnp tint)
---------------------------------------------------------------------------------------------------
-- The failure this exists for is silence: a cached "AddAuraSlot unavailable", a ruleset that matched
-- no class, or a spec that has no entry all look exactly like "the feature is on and nothing has a
-- DoT on it right now".
function Tint.Status()
	if not initialized then return "not initialized" end
	if not supported then
		return "unsupported (no CustomAuraContainerTemplate, or no ruleset for this class)"
	end
	local built = {}
	for specID, set in pairs(sets) do
		built[#built + 1] = ("%d=%s"):format(specID, set.rules.label or "?")
	end
	local bundle = activeSpec and sets[activeSpec].bundles["nameplate1"]
	local spec = PlayerSpecID()
	local specStr
	if ns.Guards.IsSecret(spec) then specStr = "SECRET"
	elseif spec then specStr = tostring(spec)
	else specStr = "nil" end
	return ("spec:%s active:%s built:[%s] path:%s chains:%d nested/token:%d anchorFail:%d errors:%d"):format(
		specStr, tostring(Tint.IsActive()), table.concat(built, ","),
		("slot=%d group=%d"):format(slotCount, groupCount),
		bundle and #bundle.roots or 0, bundle and bundle.nested or 0,
		anchorRefusals, #buildErrors)
end

-- Frame levels for one attached plate. This is the one measurement that tells a dead tint apart
-- from its look-alikes: "nothing painted" reads the same whether the spell ID is wrong, the texture
-- was attached too late, or the container simply ended up UNDER the health bar. The proxy is
-- re-levelled on every Attach and Blizzard's buttons hang below it, so container << hb means the
-- level never propagated through SetParent and the tint is drawing behind the fill.
function Tint.LevelReport(f)
	local bundle = f and f.dnpTintBundle
	if not bundle then return "target's plate holds no tint bundle (inactive spec, tapped, or not an enemy plate)" end
	local root = bundle.roots[1]
	local ok, lvl = pcall(function() return root and root:GetFrameLevel() end)
	local lvlStr
	if not ok then lvlStr = "REFUSED"
	elseif ns.Guards.IsSecret(lvl) then lvlStr = "SECRET"
	elseif lvl then lvlStr = tostring(lvl)
	else lvlStr = "nil" end
	return ("levels -> hb:%d proxy:%d container:%s | proxyShown:%s w:%.0f (expect container > hb)"):format(
		f.hb:GetFrameLevel(), bundle.proxy:GetFrameLevel(), lvlStr,
		tostring(bundle.proxy:IsShown()), bundle.proxy:GetWidth() or 0)
end

function Tint.Errors() return buildErrors end
function Tint.IsSupported() return supported end
