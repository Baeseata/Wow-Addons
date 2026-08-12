-- DodoNameplate :: Classification.lua
-- Sort a nameplate unit into ONE identity group (DESIGN.md section 1).
-- Every maybe-secret boolean goes through Guards.Bool; 12.1 additionally marks UnitInRaid as
-- secret when unit identity is restricted. Never branch on these returns before the guard.
-- Self is NOT detected here (UnitIsUnit(unit,"player") is Secret); the personal-resource plate
-- is handled separately in Core (step 4+).

local ADDON, ns = ...
local Guards = ns.Guards

-- Group ids. Keep in sync with DESIGN.md section 1.
local GROUP = {
	SELF         = 1,  -- personal resource plate (handled outside Classify)
	PARTY        = 2,  -- party / raid member
	FRIENDLY     = 3,  -- other friendly player
	FRIENDLY_NPC = 4,  -- non-attackable NPC (vendor / quest giver)
	HOSTILE      = 5,  -- hostile creature, incl. neutral (reaction color differs)
	ENEMY_PLAYER = 6,  -- hostile player (Phase 2)
}
ns.GROUP = GROUP

ns.GROUP_NAME = {
	[1] = "Self", [2] = "Party/Raid", [3] = "Friendly Player",
	[4] = "Friendly NPC", [5] = "Hostile", [6] = "Enemy Player",
}

-- Returns a GROUP id for the given nameplate unit token.
function ns.Classify(unit)
	local isPlayer  = Guards.Bool(UnitIsPlayer(unit))
	local canAttack = Guards.Bool(UnitCanAttack("player", unit))

	if isPlayer then
		if canAttack then
			return GROUP.ENEMY_PLAYER
		end
		if Guards.Bool(UnitInParty(unit)) or Guards.Bool(UnitInRaid(unit)) then
			return GROUP.PARTY
		end
		return GROUP.FRIENDLY
	end

	-- NPC / creature
	if canAttack then
		return GROUP.HOSTILE        -- neutral lands here too; reaction color handled later
	end
	return GROUP.FRIENDLY_NPC
end

-- Tapped (claimed by someone else) creature? Overlay, layered on HOSTILE (DESIGN.md section 1).
function ns.IsTapped(unit)
	return Guards.Bool(UnitIsTapDenied(unit))
end

-- Critter / trivial unit (small ambient animals). UnitClassification "minus" = trivial.
function ns.IsCritter(unit)
	local c = UnitClassification(unit)
	if Guards.IsSecret(c) or c == nil then return false end
	return c == "minus"
end
