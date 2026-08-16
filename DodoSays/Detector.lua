local ADDON, ns = ...

-- ===========================================================================
-- Detector.lua  ·  the encounter state machine.
--
-- The fight plays the memory game three times. Each round has a SHOWING half,
-- where the boss channels Sermon of Ula'tek once for the whole round and the
-- player taps the safe quarters by hand, and a CALLING half, where he casts
-- Echo of Ula'tek once per wave with no telegraph at all.
--
-- The two halves are shaped nothing alike and this file reflects that:
--
--   showing   ONE channel. No cast, no damage, no per-wave event. How many
--             waves are coming has to be inferred -- from the channel's length
--             if the client will say, from the round number if it will not.
--   calling   ONE cast per wave. Pure event. We never guess the beat.
--
--   ENCOUNTER_START ........ arm, learn the difficulty from the encounter id
--     CHANNEL_START (Sermon)  round opens, board goes live
--     CHANNEL_STOP  (Sermon)  sequence locks
--     SPELLCAST_START (Echo)  one call per wave
--   ENCOUNTER_END .......... disarm, forget the pull
--
-- What we deliberately do NOT do: read where the player is standing. The
-- client stopped handing out UnitPosition inside this arena in combat, so the
-- board is filled by hand and this file never asks the room anything.
-- ===========================================================================

local Detector = {}
ns.Detector = Detector

local equals, usableNumber, nameKey = ns.equals, ns.usableNumber, ns.nameKey
local describe = ns.describe

-- Facts the client hands over in ENCOUNTER_START -- not measurements.
-- Measured live 2026-08-15: ? reports id 3508, difficulty 208.
--
-- 🔴 This table is the DOOR, not just a lookup. An encounter that is not in it
-- does not arm the addon at all.
--
-- 2026-08-15, reported live: a five-man dungeon boss brought the board up.
-- Arming on any ENCOUNTER_START and only using the id to pick a wave count
-- meant every boss in the game qualified -- and every boss channels something,
-- so every boss looked like a sermon.
local DIFFICULTY_BY_ENCOUNTER = {
	[3508] = { key = "normal", label = "?"  },
	[3525] = { key = "hard",   label = "??" },
}

-- Matched by name first, because the id is not dependable: on ? it changes
-- between rounds, on ?? it stays put. These two are a shortcut, never a
-- requirement -- an unrecognised channel still falls through to shape.
local SERMON_KEY   = nameKey("Sermon of Ula'tek")
local ECHO_KEY     = nameKey("Echo of Ula'tek")
local SERMON_IDS   = { [1288103] = true, [1306239] = true }
local ECHO_ID      = 1288125

-- Seconds of channel per wave. Starting points only; measured rounds overwrite
-- them, so a wrong seed costs one round rather than the feature.
-- normal measured 2026-08-15 at 3.504 / 3.501 -- the seed was already right.
local SEED_SLOT = { normal = 3.503, hard = 3.003 }

-- How long one echo takes from START to landing. Measured 3.00s dead on ?,
-- six casts, spread 3.002-3.011. ?? is unmeasured, so this is a seed too --
-- and it corrects itself from the first wave of any round (see learnCast).
--
-- Measured with GetTime() against the plain UNIT_SPELLCAST_SUCCEEDED event:
-- nothing secret is touched, which is why this works at all. The cast's own
-- start/end timestamps come back <secret> and cannot be subtracted.
local SEED_CAST = 3.00

-- Waves per round, in order. Used whenever the channel's length comes back
-- secret -- which the contract says is the usual case.
local WAVES_BY_ROUND = {
	normal = { 3, 4, 5 },
	hard   = { 5, 6, 7 },
}

-- A delve is not a raid: there is no promise the client hands the nemesis a
-- boss token at all, so the units the player has to hand are watched too.
local WATCHED_UNIT = {
	boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
	target = true, focus = true,
}

local state = {
	armed      = false,
	difficulty = "normal",
	round      = 0,
	showing    = nil,   -- { unit, startedAt }
	carrier    = nil,   -- the unit that showed the current/last round
	bossGUID   = nil,
	slot       = nil,   -- learned seconds-per-wave for this pull
	castLength = nil,   -- learned START->landing for one echo, this pull
}

function Detector.CastLength()
	return state.castLength or SEED_CAST
end

Detector.state = state

function Detector.WavesFor(difficulty, round)
	local table_ = WAVES_BY_ROUND[difficulty] or WAVES_BY_ROUND.normal
	return table_[round] or table_[#table_] or 3
end

function Detector.SlotFor(difficulty)
	return state.slot or SEED_SLOT[difficulty] or SEED_SLOT.normal
end

-- A GUID we are not allowed to read is the same as no GUID at all. Returning
-- the secret itself would be worse than useless: it is truthy, so it looks
-- like an answer and shuts off every fallback behind it.
--
-- 🔴 This filter and the three-branch shape of isOurBoss below are a PAIR, and
-- 2026-08-16 measured what that means: break either one alone and the suite
-- stays green, because the other one covers for it. Break both and the suite
-- lights up -- which is exactly the bug that shipped on the 15th. So "I removed
-- it and nothing failed" is not evidence that either half is redundant.
local function guidOf(unit)
	if type(UnitGUID) ~= "function" then return nil end
	local ok, guid = pcall(UnitGUID, unit)
	if not ok or guid == nil or ns.isSecret(guid) then return nil end
	return guid
end

-- --------------------------------------------------------------------------
-- Is this cast ours to listen to?
--
-- This is the whole of the ?? problem. The second boss there is a unit named
-- "Echo of Azta'rec" whose ordinary abilities also read as "Echo of ...", so
-- "it came from a boss frame" lets every one of them through -- the reference
-- implementation logged a hard round spending two of its five calls on the
-- add. Identity, not origin:
--
--   by GUID     when the client will hand one over
--   by carrier  otherwise -- the boss that showed the waves is the boss that
--               calls them back, so anything from a different unit is not ours
-- --------------------------------------------------------------------------
-- 🔴 2026-08-15, live: the first version wrote
--       return equals(guidOf(unit), state.bossGUID) == true
--     and NOTHING WAS EVER CALLED. UnitGUID comes back secret in here, so
--     equals() answered nil -- "cannot be known" -- and `nil == true` collapsed
--     that into a flat no. The stored bossGUID was itself the secret, which is
--     truthy, so the carrier fallback below could never be reached either.
--
--     `== true` was the letter of the rule in Util.lua and the exact opposite
--     of its point. Three states means three branches: yes, no, and ask
--     something else. Collapsing the third into "no" here killed the entire
--     feature in total silence -- the board still filled, still locked, and
--     then simply never spoke.
local function isOurBoss(unit)
	if state.bossGUID then
		local same = equals(guidOf(unit), state.bossGUID)
		if same ~= nil then return same end
		-- unknowable: fall through and identify by carrier instead
	end
	if state.carrier then return unit == state.carrier end
	return WATCHED_UNIT[unit] == true
end

-- --------------------------------------------------------------------------
-- Is `unit` channelling the Sermon, and for how long?
--
-- Returns { duration } (duration may be nil) plus how we decided, or nil.
-- --------------------------------------------------------------------------
local function findSermonChannel(unit)
	if type(UnitChannelInfo) ~= "function" then return nil end
	local ok, name, _, _, startMS, endMS, _, _, spellID = pcall(UnitChannelInfo, unit)
	if not ok then return nil end

	-- Everything nil means "not channelling". That has to be told apart from
	-- "channelling something the client will not describe", which looks
	-- identical field by field and means the opposite.
	if name == nil and startMS == nil and endMS == nil and spellID == nil then
		return nil
	end

	local key = nameKey(name)
	if key and key ~= SERMON_KEY then return nil, "named something else" end

	local id = usableNumber(spellID)
	local how = key and "name" or ((id and SERMON_IDS[id]) and "id" or "shape")

	-- An id we do not know is not evidence against: on ? it changes every
	-- round, so this still falls through to shape.
	local from, to = usableNumber(startMS), usableNumber(endMS)
	if not from or not to or to <= from then
		return { duration = nil }, how
	end
	return { duration = (to - from) / 1000 }, how
end

-- --------------------------------------------------------------------------
-- Is this cast the wave call? Three ways of asking, because the client may
-- refuse the first two.
--
-- The third (by place) is fenced hard: our boss only, and never while a round
-- is still being shown -- a stray cast accepted mid-showing would shift the
-- whole run onto the wrong quarters, which is worse than missing a call.
-- --------------------------------------------------------------------------
local function identifyEcho(unit, spellID)
	local byID = equals(spellID, ECHO_ID)
	if byID ~= nil then return byID, "id" end

	if type(UnitCastingInfo) == "function" then
		local ok, name = pcall(UnitCastingInfo, unit)
		local key = ok and nameKey(name) or nil
		if key then return key == ECHO_KEY, "name" end
	end

	if state.showing then return false, "still showing" end
	return isOurBoss(unit), "place"
end

local function trace(...)
	if not (ns.db and ns.db.debug) then return end
	local out = {}
	for i = 1, select("#", ...) do out[i] = describe((select(i, ...))) end
	print("|cff88ccffDodoSays|r " .. table.concat(out, " "))
end

-- ===========================================================================
-- Transitions
-- ===========================================================================

local callCount, lastDuration, pendingCall = 0, nil, nil

-- --------------------------------------------------------------------------
-- A wave landed. Time it, so the bar for the NEXT one is the truth rather than
-- a constant -- ?? is unmeasured and may well not be 3.00s.
--
-- Only ever consulted right after a call went out (pendingCall non-nil), which
-- is what keeps the other ~200 SUCCEEDED events of a pull out of it. The first
-- one to arrive wins and clears the flag, so the duplicate reports on
-- boss1/target/nameplate are ignored for free.
-- --------------------------------------------------------------------------
local function onSucceeded(unit)
	if not pendingCall then return end
	if not isOurBoss(unit) then return end

	local ok, now = pcall(GetTime)
	local started = pendingCall
	pendingCall = nil
	if not ok or type(now) ~= "number" then return end

	local dt = now - started
	-- A wave is seconds. Anything outside that came from something else, and
	-- learning from it would poison every bar for the rest of the pull.
	if dt > 0.5 and dt < 10 then
		state.castLength = dt
		trace("cast length learned", dt)
	end
end

-- Returns true if this encounter is ours. Everything else stays asleep.
function Detector.Arm(encounterID)
	local id = usableNumber(encounterID)
	local diff = id and DIFFICULTY_BY_ENCOUNTER[id] or nil

	if not diff then
		-- Not Azta'rec -- or an id the client would not let us read. Either way
		-- we stay out of it, deliberately fail-closed: an addon that is quietly
		-- absent from a fight it does not understand costs one pull; one that
		-- pops a memory board over a dungeon boss costs every pull.
		if state.armed then Detector.Disarm() end
		trace("ignored encounter", encounterID)
		return false
	end

	state.armed      = true
	state.difficulty = diff.key
	state.round      = 0
	state.showing    = nil
	state.carrier    = nil
	state.bossGUID   = nil
	state.slot       = nil
	state.castLength = nil   -- difficulty may have changed; relearn from scratch
	ns.Emit("reset")
	trace("armed", state.difficulty, "encounter", encounterID)

	-- Said out loud, once, at the pull. It answers "did it recognise which
	-- difficulty I am on" before the first intermission rather than after --
	-- and on ?? that is the difference between expecting 3 waves and 5.
	if not (ns.db and ns.db.quiet) then
		print(("|cff88ccffDodoSays|r armed for Azta'rec |cffffd100%s|r  (%d / %d / %d waves)")
			:format(diff.label, Detector.WavesFor(diff.key, 1),
				Detector.WavesFor(diff.key, 2), Detector.WavesFor(diff.key, 3)))
	end
	return true
end

function Detector.Disarm()
	state.armed   = false
	state.showing = nil
	ns.Emit("finish", 0.5)   -- fight is over; no wave in the air, so clear promptly
	trace("disarmed")
end

local function beginShowing(unit, channel, how)
	state.round   = state.round + 1
	state.showing = { unit = unit }
	state.carrier = unit
	state.bossGUID = state.bossGUID or guidOf(unit)
	callCount, lastDuration, pendingCall = 0, channel.duration, nil

	-- Waves from the measured channel where the client allowed it, from the
	-- round number where it did not. Provisional either way: the calling half
	-- has the final say and the board is built to be corrected.
	local waves
	if channel.duration then
		waves = math.floor(channel.duration / Detector.SlotFor(state.difficulty) + 0.5)
	end
	if not waves or waves < 1 then
		waves = Detector.WavesFor(state.difficulty, state.round)
	end

	trace("round", state.round, "via", how, "waves", waves, "unit", unit)
	ns.Emit("round", waves)
end

local function endShowing()
	if not state.showing then return end
	state.showing = nil
	local n = #ns.Board.Sequence()
	trace("locked", n)
	ns.Emit("lock", n)
end

local function onCall(unit, how)
	local seq = ns.Board.Sequence()

	-- The round ends when every recorded wave has been called, and this check
	-- is the ONLY thing that ends it.
	--
	-- Measured 2026-08-15 on ?: spellID, name, start and end all come back
	-- <secret> for this boss, so identifyEcho falls through to "place" every
	-- single time -- and "is this our boss casting" is true for the whole main
	-- phase too. Without this line the ordinary rotation (Noxious Bile, Soul
	-- Extinction, ...) keeps arriving as calls: the trace shows casts at 41.0s
	-- and 45.9s, seconds after a three-wave round finished at 39.3s.
	--
	-- It also covers the other end: before the first round seq is empty, so
	-- 0 >= 0 stops the pre-pull rotation from being counted as anything.
	if callCount >= #seq then return end

	callCount = callCount + 1
	local id = seq[callCount]
	local okNow, now = pcall(GetTime)
	pendingCall = okNow and now or nil

	trace("call", callCount, id, "via", how, "unit", unit)
	ns.Emit("call", callCount, id, Detector.CastLength())

	-- The calling half is the only place the true wave count is ever visible,
	-- so this is where a wrong seed gets corrected -- for the next round, not
	-- this one.
	if lastDuration and callCount > 0 then
		state.slot = lastDuration / callCount
	end

	-- Hand the board a hold time rather than letting it guess: this fires on
	-- the last wave's START, so the round is not over for another whole cast.
	if callCount >= #seq then
		ns.Emit("finish", Detector.CastLength() + 1.5)
	end
end

Detector.BeginShowing = beginShowing
Detector.EndShowing   = endShowing
Detector.OnCall       = onCall

-- ===========================================================================
-- Wiring
--
-- Plain RegisterEvent plus a table lookup on the unit token, rather than
-- RegisterUnitEvent: that call takes at most two units and we have to watch
-- five boss frames plus target and focus, because a delve may hand the nemesis
-- no boss token at all (PROBE-CHECKLIST 2).
-- ===========================================================================

local listener = CreateFrame("Frame")

listener:SetScript("OnEvent", function(_, event, a, b, c)
	if event == "ENCOUNTER_START" then
		Detector.Arm(a)
		return
	elseif event == "ENCOUNTER_END" then
		if state.armed then Detector.Disarm() end
		return
	end

	if not state.armed then return end

	local unit = a
	if type(unit) ~= "string" or not WATCHED_UNIT[unit] then return end

	if event == "UNIT_SPELLCAST_CHANNEL_START" then
		if state.showing then return end
		local channel, how = findSermonChannel(unit)
		if channel then beginShowing(unit, channel, how) end

	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		-- Only the unit that opened the round may close it. On ?? the add is
		-- channelling its own things and must not end our recording.
		if state.showing and state.showing.unit == unit then endShowing() end

	elseif event == "UNIT_SPELLCAST_START" then
		if state.showing then return end
		if not isOurBoss(unit) then return end
		local yes, how = identifyEcho(unit, c)
		if yes then onCall(unit, how) end

	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		onSucceeded(unit)
	end
end)

for _, e in ipairs({
	"ENCOUNTER_START", "ENCOUNTER_END",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED",
}) do
	listener:RegisterEvent(e)
end
