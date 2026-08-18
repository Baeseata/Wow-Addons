-- DodoGrid :: Auras.lua
-- Friendly party/raid aura indicators on each cell. 12.0 Secret-Values safe (see CLAUDE.md
-- "FRIENDLY-AURA FEASIBILITY VERDICT" + DodoNameplate/GOTCHAS.md S3). Three healer categories,
-- category-driven ONLY (per-spellID curation is DEAD in instances):
--   (1) mine      : HELPFUL|PLAYER                                   -> small icon row, bottom-left
--   (2) important : HARMFUL|RAID / RAID_IN_COMBAT / CROWD_CONTROL    -> ONE center icon (priority pick)
--   (3) dispel    : HARMFUL|RAID_PLAYER_DISPELLABLE                  -> full-cell border, dispel-school colored
--
-- Enumerate via C_UnitAuras.GetUnitAuras(unit, "HELPFUL"/"HARMFUL", nil, sortRule); classify via
-- C_UnitAuras.IsAuraFilteredOutByInstanceID (server-side, NON-secret bool); every visual is driven from
-- a secret-safe SINK (SetTexture/SetCooldownFromDurationObject/SetAlphaFromBoolean/SetText/Set*Color),
-- never a Lua compare on a maybe-secret spellID/duration. Center-slot priority among the categories an
-- aura matches is user-configurable via ns.db.auras.important.centerPriority (CENTER_ORDERS presets).
--
-- COMBAT SAFETY: all aura frames are CHILDREN of the secure button. INVARIANT #2 only protects a secure
-- button's ANCESTORS / anchor-targets (moving them would move the button); descendants are NOT protected,
-- so Show/Hide/SetPoint/SetSize on these icons is legal in combat -- which is exactly when debuffs appear.
-- (v0.3.1 already does roleIcon:Show()/Hide() + b:SetAlpha() in combat on these same buttons.)

local ADDON, ns = ...

local CUA             = C_UnitAuras
local GetUnitAuras    = CUA and CUA.GetUnitAuras
local IsFilteredOut   = CUA and CUA.IsAuraFilteredOutByInstanceID
local GetAuraDuration = CUA and CUA.GetAuraDuration
local GetDispelColor  = CUA and CUA.GetAuraDispelTypeColor
local TruncateWhenZero = C_StringUtil and C_StringUtil.TruncateWhenZero
local CreateDuration  = C_DurationUtil and C_DurationUtil.CreateDuration
local SORT = Enum and Enum.UnitAuraSortRule and Enum.UnitAuraSortRule.Expiration

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local TRIM = 0.08          -- crop the default icon border (square icons -> equal crop)
local GAP  = 1
local MINE_MAX = 6         -- pool size for the mine row (config caps the visible count below this)

local CENTER_IMPORTANT = { 1, 0.65, 0, 1 }      -- RAID / RAID_IN_COMBAT -> gold
local CENTER_CC        = { 0.85, 0.10, 0.10, 1 } -- crowd control          -> red
local MINE_BORDER      = { 0, 0, 0, 0.9 }        -- my buffs               -> subtle dark
local DISPEL_FALLBACK  = { 0.62, 0.30, 1.00, 1 } -- dispellable, color API unavailable -> purple

-- Center-icon priority presets (user-configurable, ns.db.auras.important.centerPriority). Each maps a
-- category -> rank; an aura can match several categories at once (e.g. RAID-flagged AND dispellable), so
-- the engine scores every match and the highest rank wins the single center slot.
local CENTER_ORDERS = {
	raid   = { raid = 3, dispel = 2, cc = 1 },   -- 重要减益 > 可驱散 > CC (default)
	dispel = { dispel = 3, raid = 2, cc = 1 },   -- 可驱散 > 重要减益 > CC
	cc     = { cc = 3, raid = 2, dispel = 1 },   -- CC > 重要减益 > 可驱散
}

local Auras = {}
ns.Auras = Auras

-- Dispel-school color curve (mirrors Plater_Auras.lua): a Step curve mapping the dispel-type index to a
-- color. GetAuraDispelTypeColor evaluates it C-side off the aura's (secret) dispel type, so we never read
-- the type ourselves -- it just returns a usable Color. We OWN the colors here.
local function MakeDispelCurve()
	if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step) then
		return nil
	end
	local c = C_CurveUtil.CreateColorCurve()
	if not c then return nil end
	c:SetType(Enum.LuaCurveType.Step)
	local function col(r, g, b) return CreateColor and CreateColor(r, g, b, 1) or { r = r, g = g, b = b, a = 1 } end
	c:AddPoint(0,  col(0.80, 0.00, 0.00))   -- none / physical -> red
	c:AddPoint(1,  col(0.20, 0.60, 1.00))   -- Magic   -> blue
	c:AddPoint(2,  col(0.60, 0.00, 1.00))   -- Curse   -> purple
	c:AddPoint(3,  col(0.60, 0.40, 0.00))   -- Disease -> brown
	c:AddPoint(4,  col(0.00, 0.70, 0.00))   -- Poison  -> green
	c:AddPoint(9,  col(0.80, 0.20, 0.20))   -- enrage  -> red
	c:AddPoint(11, col(0.80, 0.20, 0.20))   -- bleed   -> red
	return c
end
local DISPEL_CURVE = MakeDispelCurve()

-- A category "passes" when IsAuraFilteredOutByInstanceID returns an explicit false (non-secret bool, or
-- nil when unavailable). Treat ONLY false as a pass so a nil can never false-positive.
local function passes(unit, id, filter)
	return IsFilteredOut and IsFilteredOut(unit, id, filter) == false
end

----------------------------------------------------------------------------------------------------
-- Icon widget (tex + cooldown swipe + border + stack text). Reused for the mine row + the center icon.
----------------------------------------------------------------------------------------------------
local function CreateIcon(parent)
	local ic = CreateFrame("Frame", nil, parent)

	local tex = ic:CreateTexture(nil, "ARTWORK")
	tex:SetPoint("TOPLEFT", 1, -1)
	tex:SetPoint("BOTTOMRIGHT", -1, 1)
	tex:SetTexCoord(TRIM, 1 - TRIM, TRIM, 1 - TRIM)
	ic.tex = tex

	local cd = CreateFrame("Cooldown", nil, ic, "CooldownFrameTemplate")
	cd:SetAllPoints(tex)
	cd:SetReverse(true)                 -- dark wedge depletes (matches Blizzard / Plater)
	cd:SetDrawEdge(true)
	cd:SetFrameLevel(ic:GetFrameLevel() + 1)
	if cd.SetCountdownAbbrevThreshold then cd:SetCountdownAbbrevThreshold(60) end
	ic.cd = cd

	local b = CreateFrame("Frame", nil, ic, "BackdropTemplate")
	b:SetPoint("TOPLEFT", -1, 1)
	b:SetPoint("BOTTOMRIGHT", 1, -1)
	b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	b:SetFrameLevel(cd:GetFrameLevel() + 1)   -- above the swipe so the stack text stays on top
	ic.b = b

	local stk = b:CreateFontString(nil, "OVERLAY")
	stk:SetPoint("BOTTOMRIGHT", 1, -1)
	stk:SetJustifyH("RIGHT")
	ic.stk = stk

	ic:Hide()
	return ic
end

local function CreateRow(parent, n)
	local row = CreateFrame("Frame", nil, parent)
	row.icons = {}
	for i = 1, n do row.icons[i] = CreateIcon(row) end
	row:Hide()
	return row
end

function Auras.Create(b)
	if b.auraMine then return end
	b.auraMine   = CreateRow(b, MINE_MAX)           -- (1) my buffs, bottom-left, grow right
	b.auraCenter = CreateIcon(b)                     -- (2) important debuff, center (CreateIcon parents it to b)

	-- (3) dispellable: full-cell colored border (above the bar so it reads as a cell highlight)
	local db = CreateFrame("Frame", nil, b, "BackdropTemplate")
	db:SetFrameLevel((b:GetFrameLevel() or 1) + 6)
	db:Hide()
	b.dispelBorder = db
end

----------------------------------------------------------------------------------------------------
-- Layout: size + position the three widgets relative to the button. Insecure (children of the button),
-- safe to call any time; in practice runs at build + on config change.
----------------------------------------------------------------------------------------------------
local function LayoutRow(row, w, h, n, showTimer, showStacks)
	for i = 1, MINE_MAX do
		local ic = row.icons[i]
		ic:SetSize(w, h)
		ic:ClearAllPoints()
		if i == 1 then
			ic:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
		else
			ic:SetPoint("BOTTOMLEFT", row.icons[i - 1], "BOTTOMRIGHT", GAP, 0)
		end
		ic.stk:SetFont(FONT, math.max(7, h - 14), "OUTLINE")
		ic.stk:SetShown(showStacks ~= false)
		ic.cd:SetHideCountdownNumbers(not showTimer)
		ic:Hide()
	end
	row.max = n
	row:SetSize((w + GAP) * n, h)
end

function Auras.Layout(b)
	if not b.auraMine then return end
	local a    = (ns.db and ns.db.auras) or {}
	local mine = a.mine or {}
	local imp  = a.important or {}
	local dsp  = a.dispel or {}
	local showTimer  = a.showTimer ~= false
	local showStacks = a.showStacks ~= false

	-- (1) mine row
	local mw = mine.size or 13
	local mn = math.max(1, math.min(mine.max or 3, MINE_MAX))
	LayoutRow(b.auraMine, mw, mw, mn, showTimer, showStacks)
	b.auraMine:ClearAllPoints()
	b.auraMine:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2 + (mine.xOff or 0), 2 + (mine.yOff or 0))

	-- (2) center icon
	local cs = imp.size or 20
	local ic = b.auraCenter
	ic:SetSize(cs, cs)
	ic:ClearAllPoints()
	ic:SetPoint("CENTER", b, "CENTER", imp.xOff or 0, imp.yOff or 0)
	ic.stk:SetFont(FONT, math.max(8, cs - 12), "OUTLINE")
	ic.stk:SetShown(showStacks ~= false)
	ic.cd:SetHideCountdownNumbers(not showTimer)

	-- (3) dispel border (full cell, thickness configurable)
	local t = math.max(1, dsp.thickness or 2)
	b.dispelBorder:ClearAllPoints()
	b.dispelBorder:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
	b.dispelBorder:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
	b.dispelBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = t })
end

----------------------------------------------------------------------------------------------------
-- Assign one aura to one icon. All sinks; safe under secret.
----------------------------------------------------------------------------------------------------
local function Assign(ic, unit, aura, hidePermanent, br, bg, bb, ba)
	ic.tex:SetTexture(aura.icon)   -- fileID -> texture sink

	local dur = GetAuraDuration and GetAuraDuration(unit, aura.auraInstanceID)
	if not dur and CreateDuration then
		dur = CreateDuration()
		dur:SetTimeFromEnd(0, 0, 1)   -- 0-duration fallback (permanent aura: no swipe, no number)
	end
	if dur and ic.cd.SetCooldownFromDurationObject and ic.cd.SetAlphaFromBoolean then
		ic.cd:SetCooldownFromDurationObject(dur)
		ic.cd:SetAlphaFromBoolean(dur:IsZero(), 0, 1)   -- hide swipe when permanent (secret-safe sink)
	end

	if TruncateWhenZero then ic.stk:SetText(TruncateWhenZero(aura.applications)) end

	if br then ic.b:SetBackdropBorderColor(br, bg, bb, ba) end

	-- "hide permanent buffs" (mine row only): drive the whole icon's alpha off IsZero via a sink, so an
	-- always-on buff (Fortitude/Intellect) renders invisible without a Lua compare on the secret duration.
	-- NOTE: this DIMS in place -- it cannot reclaim the slot (that would need a Lua test on the secret
	-- duration). Expiration sort puts permanents last, so they never displace a timed buff; the only
	-- artifact is a blank trailing gap when the row is not full. Accepted secret-safe tradeoff.
	if hidePermanent and dur and ic.SetAlphaFromBoolean then
		ic:SetAlphaFromBoolean(dur:IsZero(), 0, 1)
	else
		ic:SetAlpha(1)
	end
	ic:Show()
end

----------------------------------------------------------------------------------------------------
-- Update one cell. Driven off the button's UNIT_AURA. Combat-safe (operates only on button children).
----------------------------------------------------------------------------------------------------
function Auras.Update(b, unit)
	local a = ns.db and ns.db.auras
	if not b.auraMine or not GetUnitAuras or not a then return end
	if a.enabled == false then Auras.Clear(b); return end

	local mine = a.mine or {}
	local imp  = a.important or {}
	local dsp  = a.dispel or {}

	---------------------------------------------------------------- (1) my buffs -> mine row
	local mineSlot = 0
	if mine.enabled ~= false then
		local maxN = b.auraMine.max or 3
		local hidePerm = mine.hidePermanent ~= false
		local helpful = GetUnitAuras(unit, "HELPFUL", nil, SORT)
		if helpful then
			for _, aura in ipairs(helpful) do
				if mineSlot >= maxN then break end
				if passes(unit, aura.auraInstanceID, "HELPFUL|PLAYER") then
					mineSlot = mineSlot + 1
					Assign(b.auraMine.icons[mineSlot], unit, aura, hidePerm,
						MINE_BORDER[1], MINE_BORDER[2], MINE_BORDER[3], MINE_BORDER[4])
				end
			end
		end
	end
	for i = mineSlot + 1, MINE_MAX do b.auraMine.icons[i]:Hide() end
	b.auraMine:SetShown(mineSlot > 0)

	---------------------------------------------------------------- (2) center icon + (3) dispel border
	local wantCenter = imp.enabled ~= false
	local wantDispel = dsp.enabled ~= false
	local wantCC     = imp.showCC ~= false
	local order      = CENTER_ORDERS[imp.centerPriority] or CENTER_ORDERS.raid
	local centerAura, centerRank, centerCat   -- centerCat: "raid" / "dispel" / "cc"
	local dispelAura

	if wantCenter or wantDispel then
		local harmful = GetUnitAuras(unit, "HARMFUL", nil, SORT)
		if harmful then
			for _, aura in ipairs(harmful) do
				local id = aura.auraInstanceID
				local isDispel = passes(unit, id, "HARMFUL|RAID_PLAYER_DISPELLABLE")
				if wantDispel and not dispelAura and isDispel then
					dispelAura = aura   -- first (soonest-expiring) dispellable wins the border color
				end
				if wantCenter then
					-- An aura can match several categories at once (e.g. RAID-flagged AND dispellable), so
					-- score every match and let the configured `order` pick the winner -- don't stop at the
					-- first. Strict > keeps the soonest-expiring within a tier (list is Expiration-sorted).
					local rank, cat
					if passes(unit, id, "HARMFUL|RAID") or passes(unit, id, "HARMFUL|RAID_IN_COMBAT") then
						rank, cat = order.raid, "raid"
					end
					if isDispel and order.dispel > (rank or 0) then
						rank, cat = order.dispel, "dispel"
					end
					if wantCC and order.cc > (rank or 0) and passes(unit, id, "HARMFUL|CROWD_CONTROL") then
						rank, cat = order.cc, "cc"
					end
					if rank and rank > (centerRank or 0) then
						centerAura, centerRank, centerCat = aura, rank, cat
					end
				end
			end
		end
	end

	if centerAura then
		if centerCat == "raid" then
			Assign(b.auraCenter, unit, centerAura, false,
				CENTER_IMPORTANT[1], CENTER_IMPORTANT[2], CENTER_IMPORTANT[3], CENTER_IMPORTANT[4])
		elseif centerCat == "cc" then
			Assign(b.auraCenter, unit, centerAura, false,
				CENTER_CC[1], CENTER_CC[2], CENTER_CC[3], CENTER_CC[4])
		else   -- dispel: color the icon border by school too
			local col = GetDispelColor and GetDispelColor(unit, centerAura.auraInstanceID, DISPEL_CURVE)
			if col then
				Assign(b.auraCenter, unit, centerAura, false, col.r, col.g, col.b, col.a)
			else
				Assign(b.auraCenter, unit, centerAura, false,
					DISPEL_FALLBACK[1], DISPEL_FALLBACK[2], DISPEL_FALLBACK[3], DISPEL_FALLBACK[4])
			end
		end
	else
		b.auraCenter:Hide()
	end

	if dispelAura then
		local col = GetDispelColor and GetDispelColor(unit, dispelAura.auraInstanceID, DISPEL_CURVE)
		if col then
			b.dispelBorder:SetBackdropBorderColor(col.r, col.g, col.b, col.a)
		else
			b.dispelBorder:SetBackdropBorderColor(
				DISPEL_FALLBACK[1], DISPEL_FALLBACK[2], DISPEL_FALLBACK[3], DISPEL_FALLBACK[4])
		end
		b.dispelBorder:Show()
	else
		b.dispelBorder:Hide()
	end
end

function Auras.Clear(b)
	if not b.auraMine then return end
	for i = 1, MINE_MAX do b.auraMine.icons[i]:Hide() end
	b.auraMine:Hide()
	b.auraCenter:Hide()
	b.dispelBorder:Hide()
end
