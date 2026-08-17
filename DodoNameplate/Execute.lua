-- DodoNameplate :: Execute.lua
-- A 1px vertical rule at the player's execute threshold, drawn on enemy bars so you can see how
-- much health is left before the ability comes online -- rather than only learning it the moment
-- Blizzard lights the button up.
--
-- This module reads NOTHING about any unit. The line sits at a fixed fraction of the bar's WIDTH,
-- which is geometry, not data: the fill retreating past it is what tells you the target is in
-- range. That is why none of the Secret Values machinery in Tint.lua / Auras.lua appears here --
-- there is no secret to be careful with. Keep it that way. The moment this module wants to know
-- "is the target BELOW the threshold" (to recolour, to flash, to hide the line) it has to read
-- health, and health is secret; see GOTCHAS S6.
--
-- ANCHORING IS THE OPPOSITE OF THE DoT SEAM AND THAT IS THE WHOLE POINT:
--   * the DoT seam anchors to the FILL   -> it shortens with the health
--   * this rule anchors to the BAR FRAME -> it is nailed to 20% and stays visible after the fill
--     has retreated past it
-- Anchor this to the fill by mistake and you get a line that always sits at 20% *of the current
-- health*, which is a line that never tells you anything.

local ADDON, ns = ...

local Execute = {}
ns.Execute = Execute

-- Line thickness. 1px was tried first and read as too faint to catch mid-fight (2026-08-17) --
-- a vertical hairline against a busy bar is much easier to miss than the horizontal seam, which
-- has the whole width of the bar to announce itself. The line is CENTRED on the threshold, so an
-- even width splits evenly either side of it.
local LINE_WIDTH = 2

---------------------------------------------------------------------------------------------------
-- Thresholds
---------------------------------------------------------------------------------------------------
-- state:
--   "on"         -- confirmed for the CURRENT patch; the line is drawn.
--   "unverified" -- the number is plausible but has NOT been confirmed on 12.1. NOT drawn.
--   "dynamic"    -- the real threshold moves with a talent or a buff, so ONE static line would be
--                   wrong part of the time. NOT drawn. Fixing these means reading the player's own
--                   talents (legal -- your own info is never secret) and picking a value; that is a
--                   deliberate v2, not an oversight.
--
-- 🔴 A line in the wrong place is WORSE THAN NO LINE: it does not read as "unknown", it reads as
-- "you cannot execute yet" and you believe it. So anything not "on" simply is not drawn, and
-- /dnp exec says why. To promote one: confirm it in game, flip state to "on", done.
--
-- Everything below except Shadow Priest came from model training data, not from a queryable source
-- -- execute thresholds live in spell data (DB2), and unlike the API contracts there is no machine
-- -- generated file to grep. Treat every "unverified" number as a guess with a plausible shape.
local RULES = {
	-- ✅ Confirmed for 12.1: Shadow Word: Death, below 20%. (12.1 also buffed its damage ~80%,
	-- which is what makes the pre-read worth having at all.)
	[258] = { pct = 0.20, spell = "Shadow Word: Death", state = "on" },

	-- Same spell, other Priest specs -- almost certainly the same 20%, but not confirmed here.
	[256] = { pct = 0.20, spell = "Shadow Word: Death", state = "unverified" },
	[257] = { pct = 0.20, spell = "Shadow Word: Death", state = "unverified" },

	-- Warrior Execute. Base 20% -- but the Massacre talent moves it to 35%, so a static line is
	-- right only for half the builds. Talent-aware or nothing.
	[71]  = { pct = 0.20, spell = "Execute", state = "dynamic", why = "Massacre talent moves it to 35%" },
	[72]  = { pct = 0.20, spell = "Execute", state = "dynamic", why = "Massacre talent moves it to 35%" },
	[73]  = { pct = 0.20, spell = "Execute", state = "dynamic", why = "Massacre talent moves it to 35%" },

	-- Paladin Hammer of Wrath. Threshold is ignored entirely while Avenging Wrath / Crusade is up,
	-- so the line would be actively misleading during every burst window.
	[65]  = { pct = 0.20, spell = "Hammer of Wrath", state = "dynamic", why = "Avenging Wrath ignores the threshold" },
	[66]  = { pct = 0.20, spell = "Hammer of Wrath", state = "dynamic", why = "Avenging Wrath ignores the threshold" },
	[70]  = { pct = 0.20, spell = "Hammer of Wrath", state = "dynamic", why = "Avenging Wrath ignores the threshold" },

	-- Hunter Kill Shot.
	[253] = { pct = 0.20, spell = "Kill Shot", state = "unverified" },
	[254] = { pct = 0.20, spell = "Kill Shot", state = "unverified" },
	[255] = { pct = 0.20, spell = "Kill Shot", state = "unverified" },

	-- Death Knight Soul Reaper -- a different number from everyone else, so worth confirming
	-- before trusting muscle memory built on 20%.
	[250] = { pct = 0.35, spell = "Soul Reaper", state = "unverified" },
	[251] = { pct = 0.35, spell = "Soul Reaper", state = "unverified" },
	[252] = { pct = 0.35, spell = "Soul Reaper", state = "unverified" },

	-- Warlock.
	[265] = { pct = 0.20, spell = "Drain Soul", state = "unverified" },
	[267] = { pct = 0.20, spell = "Shadowburn", state = "unverified" },
}

ns.EXECUTE_RULES = RULES

---------------------------------------------------------------------------------------------------
-- Current spec
---------------------------------------------------------------------------------------------------
local function ExecuteConfig()
	return (ns.db and ns.db.execute) or (ns.defaults and ns.defaults.execute) or {}
end

-- Same shape as Tint.lua's: our own spec should never be secret, but "should never" is not a guard
-- and a secret used as a table index throws (GOTCHAS S1).
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

-- The rule for this spec, whatever its state -- Status() wants the "unverified"/"dynamic" ones too
-- so it can explain the silence.
function Execute.Rule()
	local spec = PlayerSpecID()
	if spec == nil or ns.Guards.IsSecret(spec) then return nil end
	return RULES[spec], spec
end

-- Only a confirmed rule draws. Anything else stays invisible on purpose.
function Execute.IsActive()
	if ExecuteConfig().enabled == false then return false end
	local rule = Execute.Rule()
	return rule ~= nil and rule.state == "on"
end

---------------------------------------------------------------------------------------------------
-- Apply / clear
---------------------------------------------------------------------------------------------------
function Execute.Clear(f)
	if f and f.execLine then f.execLine:Hide() end
end

-- Called for enemy plates only (Plate.lua already has IsEnemyPlate); friendly units can't be
-- executed, so there is nothing to mark.
function Execute.Apply(f)
	if not f or not f.execLine then return end
	if not Execute.IsActive() then Execute.Clear(f); return end

	local rule = Execute.Rule()
	-- Width comes from the CONFIGURED value stashed by LayoutPlate, for the same reason splitY does:
	-- hb sizes itself through SetAllPoints, so hb:GetWidth() is unresolved and reads 0 on the first
	-- frame -- which would silently park every line hard against the left edge.
	local w = f.barWidth
	if not w or w <= 0 then Execute.Clear(f); return end

	-- Nailed to the BAR, not the fill: the fill crossing this line is the whole signal.
	f.execLine:ClearAllPoints()
	f.execLine:SetPoint("TOP",    f.hb, "TOPLEFT",    w * rule.pct, 0)
	f.execLine:SetPoint("BOTTOM", f.hb, "BOTTOMLEFT", w * rule.pct, 0)
	f.execLine:SetWidth(LINE_WIDTH)
	f.execLine:Show()
end

---------------------------------------------------------------------------------------------------
-- Report (/dnp exec)
---------------------------------------------------------------------------------------------------
-- The failure this exists for: "no line" is the correct output for three completely different
-- situations -- your spec has no execute at all, it has one whose number nobody confirmed, or it
-- has one whose number moves with a talent. Without this they are indistinguishable from a bug.
function Execute.Status()
	local rule, spec = Execute.Rule()
	local specStr = spec and tostring(spec) or "unknown"
	if ExecuteConfig().enabled == false then
		return ("spec:%s -> disabled (execute.enabled = false)"):format(specStr)
	end
	if not rule then
		return ("spec:%s -> no execute ability on record for this spec, no line"):format(specStr)
	end
	if rule.state == "on" then
		return ("spec:%s -> %s at %d%%, line ON"):format(specStr, rule.spell, rule.pct * 100)
	end
	if rule.state == "dynamic" then
		return ("spec:%s -> %s: NO line. Threshold is not fixed (%s). A static line would be wrong "
			.. "part of the time; confirm how you want it handled before switching it on.")
			:format(specStr, rule.spell, rule.why or "moves with a talent or buff")
	end
	return ("spec:%s -> %s: NO line. %d%% is unconfirmed for this patch. Verify in game, then set "
		.. "state = \"on\" for spec %s in Execute.lua.")
		:format(specStr, rule.spell, rule.pct * 100, specStr)
end
