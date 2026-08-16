local ADDON, ns = ...

-- ===========================================================================
-- DodoSays.lua  ·  saved state, board placement, slash commands.
-- ===========================================================================

local function applyDefaults(db, defaults)
	for k, v in pairs(defaults) do
		if db[k] == nil then db[k] = v end
	end
	return db
end

function ns.SavePosition(frame)
	local anchor, _, _, x, y = frame:GetPoint()
	ns.db.point = { anchor = anchor, x = x, y = y }
end

function ns.ApplyPosition()
	local frame = ns.Board.Build()
	frame:ClearAllPoints()
	local p = ns.db.point
	if p and p.anchor then
		frame:SetPoint(p.anchor, UIParent, p.anchor, p.x or 0, p.y or 0)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, -80)
	end
	frame:SetScale(ns.db.scale or 1)
end

-- --------------------------------------------------------------------------
-- Bindable taps. Global on purpose: Bindings.xml can only reach globals, and
-- clicking four wedges with a mouse while dodging is not a real plan.
--
-- Three doors lead here now -- the wedge itself, a keybinding, and
-- `/dodosays <quarter>`. The third exists because ring addons (OPie and the
-- like) can hold a macro but cannot hold a keybinding, so without a command
-- there is nothing for them to point at. All three record the same thing.
-- --------------------------------------------------------------------------
-- Returns whether the tap counted. Bindings.xml throws the answer away on
-- purpose -- a key held down out of habit between rounds is not an error worth
-- a message -- but the slash command needs it: somebody who just built a macro
-- and saw nothing happen deserves to be told why.
function DodoSays_Tap(id)
	return ns.Board.Tap(id)
end

function DodoSays_Undo()
	ns.Board.Undo()
end

-- ---------------------------------------------------------------------------
-- Where are we?
--
-- ✅ 2634 MEASURED 2026-08-16, standing inside the delve: C_Map.GetBestMapForUnit
-- ("player") returns 2634, plainly and out of combat. (It arrived here as an
-- unverified number copied from SnakeSays' Core.lua; it is ours now.)
--
-- Also measured in the same run, for whoever needs the other ids:
--   UnitPosition's 4th return (the world/instance map) = 3079
--   GetInstanceInfo -> Venomfall Deeps / "scenario" / instanceID 3079
--   (the measuring client is zhCN, so the NAME came back localised -- which is
--    exactly why nothing in here ever compares against it. The id is the fact.)
--
-- It still fails CLOSED -- unknown map, or a map id the client will not hand
-- over, means no standing board. A wrong answer here has a shape we have
-- already been bitten by: the board turning up somewhere it has no business
-- being. `/ds where` prints what the client actually says.
-- ---------------------------------------------------------------------------
local DELVE_MAPS = { [2634] = true }   -- Venomfall Deeps

local function mapNow()
	if type(C_Map) ~= "table" or type(C_Map.GetBestMapForUnit) ~= "function" then
		return nil
	end
	local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
	if not ok then return nil end
	return ns.usableNumber(id)
end

local function inTheDelve()
	local id = mapNow()
	return id ~= nil and DELVE_MAPS[id] == true
end

-- Called on zone changes and at login. Standing board while in the delve;
-- packed away everywhere else.
function ns.RefreshPresence()
    local here = inTheDelve()
    ns.Board.SetPersistent(here)
    if here then
        ns.ApplyPosition()
        ns.Board.Show()
    elseif ns.Detector and not ns.Detector.state.armed then
        ns.Board.Hide()
    end
end

BINDING_HEADER_DODOSAYS = "DodoSays"
BINDING_NAME_DODOSAYS_TAP_CROSS    = "Safe: Cross"
BINDING_NAME_DODOSAYS_TAP_SQUARE   = "Safe: Square"
BINDING_NAME_DODOSAYS_TAP_TRIANGLE = "Safe: Triangle"
BINDING_NAME_DODOSAYS_TAP_CIRCLE   = "Safe: Circle"
BINDING_NAME_DODOSAYS_UNDO         = "Undo last tap"

local function inCombat()
	if type(InCombatLockdown) ~= "function" then return false end
	return InCombatLockdown() and true or false
end

local HELP = {
	"|cff88ccffDodoSays|r  -- Azta'rec memory game",
	"  |cffffd100/ds cross|r|cffffd100 square triangle circle|r   tap that quarter",
	"  |cffffd100/ds show|r / |cffffd100hide|r    the board",
	"  |cffffd100/ds sim [n]|r        rehearse a round of n waves (no boss needed)",
	"  |cffffd100/ds go|r             lock the tapped run and play it back",
	"  |cffffd100/ds undo|r           drop the last tap",
	"  |cffffd100/ds lock|r           toggle dragging",
	"  |cffffd100/ds panel|r          settings window (or click the murloc on the minimap)",
	"  |cffffd100/ds where|r          what map the client thinks you are on",
	"  |cffffd100/ds config|r         options",
	"  |cffffd100/ds trace|r          record every event the fight fires, then /reload",
	"  |cffffd100before the pull|r drop raid markers on the floor, clockwise:",
	"    cross -> square -> triangle -> circle",
	"  three ways to tap: click a wedge, bind keys under Key Bindings > DodoSays,",
	"    or put |cffffd100/dodosays cross|r in a macro -- that is the one a ring",
	"    addon such as OPie can hold, since those take macros and not bindings.",
}

local function slash(msg)
	local cmd, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")

	-- Quarters first, ahead of every subcommand, and the order is the point.
	-- This is the only branch anybody runs mid-fight, and if something ever
	-- shadowed one of these four the failure would be silence: no error, no
	-- message, one wave missing from the sequence and a wrong call later. A
	-- subcommand losing to a quarter would at worst annoy somebody standing in
	-- a city. tools/test_detector.lua pins the direction that matters.
	--
	-- The names are read off QUADRANT_BY_ID rather than written out again here:
	-- a second copy of cross/square/triangle/circle is a second thing to keep
	-- in step with the board.
	if ns.QUADRANT_BY_ID[cmd] then
		if DodoSays_Tap(cmd) then return end

		-- Nothing recorded. Between rounds that is ordinary and a message every
		-- time would be noise -- but the first run of this command is always
		-- somebody standing in a city who just built the macro and wants to
		-- know whether they typed it right. So: quiet in the fight, helpful
		-- outside it. (The keybindings stay silent either way; they get held
		-- down out of habit, this gets typed on purpose.)
		if not inCombat() then
			print("|cff88ccffDodoSays|r takes taps only while Azta'rec is preaching. " ..
				"|cffffd100/ds sim 5|r rehearses a round right here.")
		end
		return

	elseif cmd == "show" then
		ns.ApplyPosition()
		ns.Board.Show()

	elseif cmd == "hide" then
		ns.Board.Hide()

	elseif cmd == "sim" then
		ns.ApplyPosition()
		ns.Sim.Round(tonumber(rest))

	elseif cmd == "go" then
		ns.Sim.Go()

	elseif cmd == "undo" then
		ns.Board.Undo()

	elseif cmd == "lock" then
		ns.db.locked = not ns.db.locked
		print("|cff88ccffDodoSays|r board " .. (ns.db.locked and "locked." or "unlocked."))

	elseif cmd == "config" then
		ns.BuildOptions()
		if Settings and ns.settingsCategory then
			Settings.OpenToCategory(ns.settingsCategory:GetID())
		end

	elseif cmd == "trace" then
		if rest == "off" then
			print(("|cff88ccffDodoSays|r trace stopped, %d line(s) saved. |cffffd100/reload|r to write them to disk.")
				:format(ns.Trace.Stop()))
		else
			ns.Trace.Start()
			print("|cff88ccffDodoSays|r trace |cff44ff44ON|r. Pull the boss, play the whole fight, then |cffffd100/reload|r.")
			print("  (nothing is printed while recording -- that is deliberate, chat would lag the fight)")
			local bad = ns.Trace.Failed()
			if #bad > 0 then
				-- Said out loud rather than only written to the log: an event
				-- that would not register means a whole class of answer is
				-- missing from this run, and you want to know that BEFORE the pull.
				print("|cffff6666  refused to register:|r " .. table.concat(bad, ", "))
			end
		end

	elseif cmd == "panel" or cmd == "ui" then
		ns.Mini.Toggle()

	elseif cmd == "where" then
		local id = mapNow()
		print(("|cff88ccffDodoSays|r map = %s   known delve = %s")
			:format(tostring(id), tostring(id ~= nil and DELVE_MAPS[id] == true)))
		if type(GetInstanceInfo) == "function" then
			local ok, name, itype, _, _, _, _, instanceID = pcall(GetInstanceInfo)
			if ok then
				print(("  instance = %s  type = %s  id = %s")
					:format(tostring(name), tostring(itype), tostring(instanceID)))
			end
		end
		print("  |cffffd100if you are standing in Venomfall Deeps and 'known delve' says false, send me these numbers|r")

	elseif cmd == "tracecount" then
		print(("|cff88ccffDodoSays|r %d line(s) recorded, active=%s")
			:format(ns.Trace.Count(), tostring(ns.Trace.IsActive())))

	elseif cmd == "reset" then
		ns.db.point = nil
		ns.ApplyPosition()

	else
		for _, line in ipairs(HELP) do print(line) end
	end
end

SLASH_DODOSAYS1 = "/ds"
SLASH_DODOSAYS2 = "/dodosays"
SlashCmdList.DODOSAYS = slash

local boot = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
	boot:RegisterEvent(e)
end

boot:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" then
		if name ~= ADDON then return end
		self:UnregisterEvent("ADDON_LOADED")

		DodoSaysDB = DodoSaysDB or {}
		ns.db = applyDefaults(DodoSaysDB, ns.DEFAULTS)

		ns.BuildOptions()
		ns.ApplyPosition()
		ns.Announce.ApplyPosition()
		ns.Mini.Build()
		return
	end

	-- Zone changes fire before the map is settled often enough to matter, so
	-- ask again a moment later rather than trusting the first answer.
	if not ns.db then return end
	ns.RefreshPresence()
	if C_Timer and C_Timer.After then
		C_Timer.After(2, function() if ns.db then ns.RefreshPresence() end end)
	end
end)
