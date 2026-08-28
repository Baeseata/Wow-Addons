local ADDON, ns = ...

-- ===========================================================================
-- Macros.lua  ·  four macros, made for you, ready to drag onto a bar.
--
-- An action bar takes macros and nothing else -- there is no way to put a Lua
-- function on one -- and a ring addon (OPie and its kind) is the same: it holds
-- macros, not keybindings. So `/dodosays <quarter>` is the door and these four
-- are the handles. Everyone who wants this would otherwise make the same four
-- by hand, through the macro window, four times.
--
-- The shape here is not invented: MythicDungeonTools' focus marker and
-- NorthernSkyRaidTools' MidnightS2 helper both do exactly this on this same
-- client, and both of them gate on combat, check the slot count, and edit in
-- place rather than duplicating. Copied deliberately, including the parts that
-- look like paranoia.
-- ===========================================================================

local Macros = {}
ns.Macros = Macros

-- Raid target icons 1..8 are file ids 137001..137008. Read off the two addons
-- above rather than guessed: a wrong id here is a question mark sitting on
-- somebody's action bar, which is the sort of thing nobody reports and
-- everybody just works around.
local RAID_ICON_BASE = 137000

-- The Dodo prefix is what keeps this out of its one genuinely destructive case.
-- EditMacro on a name collision rewrites whatever was there, and what was there
-- could be the player's own macro -- so the names have to be ours beyond doubt.
-- Nothing here measures length, and the reason is our own names: the longest is
-- "Dodo Diamond" at 12 characters. It is *not* that the client caps names at
-- 16 -- that was the old claim here and it is wrong. A DodoProbe run on 12.1.0
-- build 120100 renamed a macro to 12 Chinese code points (32 bytes) and read it
-- back through C_Macro.GetMacroName intact, so the real ceiling is at least 32
-- bytes and was never measured past that. Anyone sizing a name that could get
-- long -- localised labels especially -- has to go measure it, not trust a
-- number from this comment.
function Macros.NameFor(q)  return "Dodo " .. q.label end
function Macros.BodyFor(q)  return "/dodosays " .. q.id end
function Macros.IconFor(q)  return RAID_ICON_BASE + q.marker end

local function slotsLeft()
	if type(GetNumMacros) ~= "function" then return 0 end
	local used = GetNumMacros() or 0
	return (MAX_ACCOUNT_MACROS or 120) - used
end

-- Returns made, updated, err.
--
-- Safe to run any number of times: one of ours that already exists is edited in
-- place, never duplicated, so the button can be mashed and there are still four
-- macros. The counts come back even on failure -- running out of slots halfway
-- is a real state and "it failed" would hide which half happened.
function Macros.Create()
	if type(CreateMacro) ~= "function" then return 0, 0, "noapi" end

	-- Both reference implementations refuse in combat, and the client blocks
	-- the call outright. Checked here rather than only at the button, because
	-- the button is not the only thing that will ever call this.
	if type(InCombatLockdown) == "function" and InCombatLockdown() then
		return 0, 0, "combat"
	end

	-- A quarter that was renamed leaves a macro behind under the old name, and
	-- that macro is very likely sitting on an action bar. Creating the new one
	-- beside it would leave the player pressing the stale button -- still
	-- working, thanks to the legacy fold in the slash handler, but wearing the
	-- green icon this change exists to get rid of. Editing the old entry in
	-- place keeps the bar slot, so the button on the bar simply becomes the new
	-- one. Skipped if the new name already exists, since that would be two
	-- macros collapsing into one and losing a slot the player filled.
	for old, new in pairs(ns.LEGACY_QUADRANT_IDS) do
		local q = ns.QUADRANT_BY_ID[new]
		local stale = GetMacroIndexByName("Dodo " .. old:sub(1, 1):upper() .. old:sub(2))
		if q and stale and stale > 0 and (GetMacroIndexByName(Macros.NameFor(q)) or 0) <= 0 then
			pcall(EditMacro, stale, Macros.NameFor(q), Macros.IconFor(q), Macros.BodyFor(q))
		end
	end

	local made, updated = 0, 0
	for _, q in ipairs(ns.QUADRANTS) do
		local name, icon, body = Macros.NameFor(q), Macros.IconFor(q), Macros.BodyFor(q)
		local index = GetMacroIndexByName(name)

		local ok, err
		if index and index > 0 then
			ok, err = pcall(EditMacro, index, name, icon, body)
			if ok then updated = updated + 1 end
		elseif slotsLeft() <= 0 then
			return made, updated, "noslots"
		else
			local created
			ok, err = pcall(function() created = CreateMacro(name, icon, body, nil) end)
			if ok and (not created or created == 0) then return made, updated, "noslots" end
			if ok then made = made + 1 end
		end

		-- The client throwing here is not something either reference addon has
		-- a story for, so neither do we -- except that it must not be silent.
		if not ok then return made, updated, tostring(err) end
	end

	return made, updated, nil
end

-- Built as a string rather than printed, so the wording is a thing a test can
-- hold. Every branch says what to do next: a message that only reports failure
-- leaves the player exactly where they started.
function Macros.Report(made, updated, err)
	if err == "combat" then
		return "|cff88ccffDodoSays|r cannot make macros in combat -- the client will not allow it. Try again after the fight."
	elseif err == "noslots" then
		return ("|cff88ccffDodoSays|r ran out of account macro slots (%d of 4 made). Free one in the macro window and press it again."):format(made)
	elseif err == "noapi" then
		return "|cff88ccffDodoSays|r could not reach the macro API on this client."
	elseif err then
		return "|cff88ccffDodoSays|r could not finish making the macros: " .. err
	end

	local what
	if made > 0 and updated > 0 then
		what = ("made %d and refreshed %d"):format(made, updated)
	elseif made > 0 then
		what = ("made %d"):format(made)
	else
		what = ("refreshed %d, already there"):format(updated)
	end
	return ("|cff88ccffDodoSays|r %s: Dodo Cross / Square / Diamond / Circle. Drag them from the macro window onto a bar, or point a ring addon at them."):format(what)
end
