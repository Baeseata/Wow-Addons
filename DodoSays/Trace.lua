local ADDON, ns = ...

-- ===========================================================================
-- Trace.lua  ·  what the client actually says during the fight.
--
-- Three questions, in the order they matter:
--   1. is there an event for "this round is starting" / "the echo is starting"
--   2. is there one per wave while he PREACHES
--   3. is there one per wave while he ECHOES        <- the one that pays
--
-- Everything lands in SavedVariables rather than the chat frame: chat truncates,
-- costs the player a copy-paste at the worst possible moment, and drops the one
-- thing that matters most here -- exact timestamps.
--
-- SAFETY: every value out of the client goes through describe(). tostring() on
-- a secret throws, and a throw in a UNIT_* handler kills the handler silently.
-- A probe that dies mid-fight and still looks like it ran is worse than none.
-- ===========================================================================

local Trace = {}
ns.Trace = Trace

local d = ns.describe
local MAX = 4000

local active, t0, log, playerGUID = false, 0, nil, nil

local function stamp()
	local ok, now = pcall(GetTime)
	if not ok or type(now) ~= "number" then return 0 end
	return math.floor((now - t0) * 1000 + 0.5) / 1000
end

local function put(line)
	if not active or not log then return end
	local n = #log
	if n > MAX then return end
	if n == MAX then log[n + 1] = "!! TRACE FULL - stopped recording !!"; return end
	log[n + 1] = line
end

-- What the client will say about the cast/channel in flight on `unit`.
-- Recorded even when it refuses, because "refused" is the finding.
local function info(unit, channel)
	local fn = channel and UnitChannelInfo or UnitCastingInfo
	if type(fn) ~= "function" then return " info=<no api>" end
	local ok, name, _, _, startMS, endMS, _, _, spellID = pcall(fn, unit)
	if not ok then return " info=<threw>" end
	if name == nil and startMS == nil and endMS == nil and spellID == nil then
		return " info=none"
	end
	return (" name=%s start=%s end=%s id2=%s"):format(
		d(name), d(startMS), d(endMS), d(spellID))
end

local UNIT_EVENTS = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE",
	"UNIT_SPELLCAST_EMPOWER_STOP",
}

local WATCH = {
	boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
	target = true, focus = true, nameplate1 = true, nameplate2 = true,
	nameplate3 = true, nameplate4 = true, nameplate5 = true,
}

-- Subevents worth keeping. SPELL_DAMAGE on the player is in here on purpose:
-- if the preaching half has no unit event per wave, the venom landing on us
-- may be the only per-wave signal that exists at all.
local CLEU_KEEP = {
	SPELL_CAST_START = true, SPELL_CAST_SUCCESS = true, SPELL_CAST_FAILED = true,
	SPELL_DAMAGE = true, SPELL_MISSED = true, SPELL_PERIODIC_DAMAGE = true,
	SPELL_AURA_APPLIED = true, SPELL_AURA_REMOVED = true, SPELL_AURA_REFRESH = true,
	SPELL_SUMMON = true, UNIT_DIED = true, SPELL_EMPOWER_START = true,
}

local frame = CreateFrame("Frame")

frame:SetScript("OnEvent", function(_, event, ...)
	-- First line, every time: everything below is registered at load and fires
	-- all session long, so this is what keeps the cost at one table lookup when
	-- nobody is recording. CLEU alone is hundreds of calls a minute in combat.
	if not active then return end

	if event == "ENCOUNTER_START" then
		local id, name, diff = ...
		t0 = (pcall(GetTime) and GetTime()) or 0
		put(("%7.3f == ENCOUNTER_START id=%s name=%s diff=%s")
			:format(0, d(id), d(name), d(diff)))
		return
	end

	if event == "ENCOUNTER_END" then
		local id, name, diff, size, success = ...
		put(("%7.3f == ENCOUNTER_END id=%s success=%s")
			:format(stamp(), d(id), d(success)))
		return
	end

	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		local ok, ts, sub, _, srcGUID, srcName, _, _, dstGUID, dstName, _, _, spellID, spellName =
			pcall(CombatLogGetCurrentEventInfo)
		if not ok or not CLEU_KEEP[sub] then return end
		-- Our own damage would drown everything else; the boss is the subject.
		if srcGUID == playerGUID and sub ~= "SPELL_DAMAGE" then return end
		if srcGUID == playerGUID and dstGUID ~= playerGUID then return end
		put(("%7.3f CLEU %s src=%s dst=%s id=%s spell=%s"):format(
			stamp(), tostring(sub), d(srcName), d(dstName), d(spellID), d(spellName)))
		return
	end

	-- UNIT_SPELLCAST_*
	local unit, castGUID, spellID = ...
	if type(unit) ~= "string" or not WATCH[unit] then return end
	local channel = event:find("CHANNEL") ~= nil
	put(("%7.3f %s unit=%s id=%s%s"):format(
		stamp(), event, unit, d(spellID), info(unit, channel)))
end)

-- ===========================================================================
-- Registration happens HERE, at load, and never again.
--
-- 2026-08-15, two findings, the second one correcting the first:
--
--   a) registering from the slash command threw ADDON_ACTION_FORBIDDEN on
--      Frame:RegisterEvent(). Diagnosed as taint (user input is a tainted
--      execution path). Moved registration to load time.
--   b) it threw AGAIN, from `main chunk` -- so taint was NOT the cause, or at
--      least not all of it. A load-time chunk is clean. What is left is that
--      one specific EVENT is protected and cannot be registered by an addon on
--      any path at all. It threw once, so exactly one of the list is refused.
--
-- (a) is left written down because the fix it produced is right anyway --
-- registering at load is cheaper and survives /reload -- but the REASON in (a)
-- is disproved. Do not carry it forward as fact.
--
-- Each call is pcall'd and the failures are KEPT, not swallowed: which events
-- refuse to register at all is itself one of the answers we came for, and a
-- probe that silently registered nothing looks exactly like a fight that fired
-- nothing.
-- ===========================================================================
local REGISTER_FAILED = {}
local BUILD = "?"
do
	local ok, _, build = pcall(GetBuildInfo)
	if ok and build then BUILD = build end

	-- ⚠ COMBAT_LOG_EVENT_UNFILTERED is deliberately NOT registered any more.
	--
	-- Measured 2026-08-15: it throws ADDON_ACTION_FORBIDDEN even from a clean
	-- load-time chunk -- 12.x refuses combat log to addons outright. We HAVE
	-- that answer; retrying it every single load buys nothing and costs a
	-- forbidden call, and a forbidden call taints whatever is on the stack.
	--
	-- Suspected (NOT proven) cause of boss health bars disappearing the same
	-- evening. Removing it is cheap either way, so it goes first and the
	-- diagnosis comes after.
	REGISTER_FAILED[#REGISTER_FAILED + 1] = "COMBAT_LOG_EVENT_UNFILTERED (known refused, no longer attempted)"

	local wanted = { "ENCOUNTER_START", "ENCOUNTER_END" }
	for _, e in ipairs(UNIT_EVENTS) do wanted[#wanted + 1] = e end

	for _, e in ipairs(wanted) do
		pcall(frame.RegisterEvent, frame, e)

		-- pcall is NOT the check. ADDON_ACTION_FORBIDDEN is an event, not
		-- necessarily a lua error -- BugGrabber catches it by listening for it,
		-- not by wrapping the call -- so a refused registration can come back
		-- from pcall looking perfectly successful.
		--
		-- Asking the frame what is actually registered is a different question
		-- with a different failure mode, which is the whole point: the hand and
		-- the eye must not be the same organ.
		local asked, on = pcall(frame.IsEventRegistered, frame, e)
		if not asked or not on then
			REGISTER_FAILED[#REGISTER_FAILED + 1] = e
		end
	end
end

function Trace.Start()
	active, log = true, {}
	t0 = (pcall(GetTime) and GetTime()) or 0
	local ok, guid = pcall(UnitGUID, "player")
	playerGUID = ok and guid or nil

	-- Point SavedVariables at the live table, not a copy taken later. The
	-- player should not have to remember to stop the trace: /reload or logout
	-- serialises whatever is here, so the data survives even if the run ends
	-- with a corpse run and a rage quit.
	DodoSaysDB = DodoSaysDB or {}
	DodoSaysDB.trace = log

	put(("%7.3f == TRACE START build=%s"):format(0, d(BUILD)))
	for _, e in ipairs(REGISTER_FAILED) do
		put("       !! could not register " .. e)
	end
end

-- No UnregisterAllEvents here: unregistering from a slash command is the same
-- tainted path that made registering blow up, and there is nothing to gain --
-- `active` already gates every line.
function Trace.Stop()
	active = false
	return log and #log or 0
end

function Trace.Count() return log and #log or 0 end
function Trace.IsActive() return active end
function Trace.Failed() return REGISTER_FAILED end
