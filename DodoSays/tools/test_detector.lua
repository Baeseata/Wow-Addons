-- ===========================================================================
-- test_detector.lua  ·  offline logic tests. Run from the addon folder:
--
--     lua tools/test_detector.lua
--
-- These load the real Util/Board/Announce/Detector and drive them through the
-- real event handler. The only fakes are client APIs.
--
-- The one that matters is FENCE: on ?? the second boss ("Echo of Azta'rec")
-- casts abilities that also read as "Echo of ...", and the reference
-- implementation logged a hard round losing 2 of its 5 calls to it. If that
-- test ever goes green with the identity check removed, the fence is decorative.
-- ===========================================================================

package.path = "tools/?.lua;" .. package.path
local H = require("harness")

local pass, fail = 0, 0
local function check(name, got, want)
	if got == want then
		pass = pass + 1
	else
		fail = fail + 1
		io.write(("  FAIL  %s\n         got %s, want %s\n")
			:format(name, tostring(got), tostring(want)))
	end
end

H.install()
local ns = H.load({ "Util.lua", "Board.lua", "Announce.lua", "Detector.lua" })
ns.db = { announce = false, sound = false, debug = false }

-- Record everything crossing the replay seam.
local log = {}
ns.Subscribe(function(event, a, b, c) log[#log + 1] = { event, a, b, c } end)
local function lastOf(event)
	for i = #log, 1, -1 do if log[i][1] == event then return log[i] end end
end
local function countOf(event)
	local n = 0
	for _, e in ipairs(log) do if e[1] == event then n = n + 1 end end
	return n
end

local listener = H.listenerFor("ENCOUNTER_START")
local fire = listener and listener._scripts.OnEvent
assert(fire, "Detector registered no OnEvent handler")

-- Client stubs the tests re-point as they go.
local channelling, castName = nil, nil
_G.UnitChannelInfo = function(unit)
	if not channelling or channelling.unit ~= unit then return nil end
	return channelling.name or "Sermon of Ula'tek", nil, nil,
		channelling.from, channelling.to, nil, nil, channelling.id
end
_G.UnitCastingInfo = function() return castName end

-- ---------------------------------------------------------------------------
io.write("Util\n")
-- ---------------------------------------------------------------------------
check("nameKey folds the straight apostrophe",
	ns.nameKey("Sermon of Ula'tek"), "sermonofulatek")
check("nameKey folds the typographic one",
	ns.nameKey("Sermon of Ula\226\128\153tek"), "sermonofulatek")
check("nameKey is case-blind",
	ns.nameKey("ECHO OF ULA'TEK"), ns.nameKey("Echo of Ula'tek"))
check("equals is nil, not false, when unknowable",
	ns.equals(1, 1), true)

-- ---------------------------------------------------------------------------
io.write("Marker layout\n")
-- The player paints these on the floor before the pull, so the addon's idea of
-- the order has to match theirs exactly. Nothing on screen would look wrong if
-- this drifted -- the wedges would just quietly mean different patches of
-- ground -- so it gets pinned here.
-- ---------------------------------------------------------------------------
local order = {}
for _, q in ipairs(ns.QUADRANTS) do
	order[#order + 1] = ("%s/%d@%d"):format(q.id, q.marker, q.angle)
end
check("clockwise from cross", table.concat(order, " "),
	"cross/7@0 square/6@90 triangle/4@180 circle/2@270")
check("icon escape points at the right file",
	ns.markerIcon(7, 40),
	"|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:40|t")

-- ---------------------------------------------------------------------------
io.write("Wave table\n")
-- ---------------------------------------------------------------------------
check("normal round 1", ns.Detector.WavesFor("normal", 1), 3)
check("normal round 3", ns.Detector.WavesFor("normal", 3), 5)
check("hard round 1",   ns.Detector.WavesFor("hard", 1),   5)
check("hard round 3",   ns.Detector.WavesFor("hard", 3),   7)
check("past the end clamps rather than nils",
	ns.Detector.WavesFor("hard", 9), 7)

-- ---------------------------------------------------------------------------
io.write("A full normal round\n")
-- ---------------------------------------------------------------------------
fire(nil, "ENCOUNTER_START", 3508)
check("encounter id picked the difficulty", ns.Detector.state.difficulty, "normal")

channelling = { unit = "boss1", from = nil, to = nil, id = 1288103 }
fire(nil, "UNIT_SPELLCAST_CHANNEL_START", "boss1", "cast-1", 1288103)
check("round opened", (lastOf("round") or {})[1], "round")
check("unreadable channel falls back to the round table",
	(lastOf("round") or {})[2], 3)

ns.Board.Tap("cross"); ns.Board.Tap("square"); ns.Board.Tap("triangle")
check("three taps recorded", #ns.Board.Sequence(), 3)

channelling = nil
fire(nil, "UNIT_SPELLCAST_CHANNEL_STOP", "boss1", "cast-1", 1288103)
check("sequence locked at three", (lastOf("lock") or {})[2], 3)

fire(nil, "UNIT_SPELLCAST_START", "boss1", "cast-2", 1288125)
check("first call is the first tap", (lastOf("call") or {})[3], "cross")
fire(nil, "UNIT_SPELLCAST_START", "boss1", "cast-3", 1288125)
check("second call is the second tap", (lastOf("call") or {})[3], "square")

-- ---------------------------------------------------------------------------
io.write("Channel length beats the round table when the client allows it\n")
-- ---------------------------------------------------------------------------
fire(nil, "ENCOUNTER_START", 3525)
check("hard difficulty", ns.Detector.state.difficulty, "hard")

-- 21.0s at the hard seed of 3.003s/wave = 7 waves, which is round 3 on hard --
-- and the round table would have said 5, so this proves measurement wins.
channelling = { unit = "boss1", from = 1000, to = 22021, id = 1306239 }
fire(nil, "UNIT_SPELLCAST_CHANNEL_START", "boss1", "c", 1306239)
check("measured channel overrode the seed", (lastOf("round") or {})[2], 7)

-- ---------------------------------------------------------------------------
io.write("Fence: the ?? add must not steal calls\n")
-- ---------------------------------------------------------------------------
for _, q in ipairs({ "cross", "square", "triangle", "circle", "cross" }) do
	ns.Board.Tap(q)
end
check("five taps recorded", #ns.Board.Sequence(), 5)

-- A stray cast WHILE still showing must be ignored outright: accepting one
-- here would shift the whole run onto the wrong quarters.
local before = countOf("call")
fire(nil, "UNIT_SPELLCAST_START", "boss1", "stray", 1288125)
check("no calls while still showing", countOf("call"), before)

channelling = nil
fire(nil, "UNIT_SPELLCAST_CHANNEL_STOP", "boss1", "c", 1306239)
check("locked at five", (lastOf("lock") or {})[2], 5)

-- Echo of Azta'rec: different unit, different GUID, and -- the nasty part --
-- an ability whose name also folds to "echoof...". Name and id both say yes.
-- Only identity says no.
before = countOf("call")
castName = "Echo of Ula'tek"
fire(nil, "UNIT_SPELLCAST_START", "boss2", "add-cast", 1288125)
check("the add's cast was refused", countOf("call"), before)

fire(nil, "UNIT_SPELLCAST_START", "boss1", "real-1", 1288125)
check("the real boss still gets through", countOf("call"), before + 1)
check("and it called the first tap", (lastOf("call") or {})[3], "cross")

-- ---------------------------------------------------------------------------
io.write("The real client: everything secret, wave count is the only fence\n")
-- Measured on ? 2026-08-15 (trace in docs/RESEARCH-live-trace.md): spellID,
-- name, start and end ALL come back <secret>. So identifyEcho can never answer
-- by id or by name -- it falls through to "place" on every single cast, and
-- "is our boss casting" stays true for the whole main phase.
--
-- Every test above ran on plaintext, i.e. on a path the real fight never takes.
-- This one runs the path it does take.
-- ---------------------------------------------------------------------------
local SECRET = { [1288125] = true, ["<secret name>"] = true, [90210] = true }
_G.issecretvalue = function(v) return SECRET[v] == true end
castName = "<secret name>"

fire(nil, "ENCOUNTER_START", 3508)
channelling = { unit = "boss1", name = "<secret name>",
                from = 90210, to = 90210, id = 1288125 }
fire(nil, "UNIT_SPELLCAST_CHANNEL_START", "boss1", "c", 1288125)
check("round opened with nothing readable at all", (lastOf("round") or {})[2], 3)

ns.Board.Tap("cross"); ns.Board.Tap("square"); ns.Board.Tap("triangle")
channelling = nil
fire(nil, "UNIT_SPELLCAST_CHANNEL_STOP", "boss1", "c", 1288125)

local base = countOf("call")
for i = 1, 3 do fire(nil, "UNIT_SPELLCAST_START", "boss1", "echo" .. i, 1288125) end
check("three waves called", countOf("call"), base + 3)
check("finish fired at the last wave", (log[#log] or {})[1], "finish")

-- The rotation coming back. In the real trace this is 41.0s and 45.9s, seconds
-- after a three-wave round ended at 39.3s.
fire(nil, "UNIT_SPELLCAST_START", "boss1", "rotation1", 1288125)
fire(nil, "UNIT_SPELLCAST_START", "boss1", "rotation2", 1288125)
check("main-phase rotation is not mistaken for calls", countOf("call"), base + 3)

-- ---------------------------------------------------------------------------
io.write("The cast bar measures itself\n")
-- The bar cannot read the cast's own clock -- start and end are secret. So it
-- times START -> SUCCEEDED with GetTime(), which is plain. ? measured 3.00s;
-- ?? is unmeasured, and this is what stops that from mattering.
-- ---------------------------------------------------------------------------
check("seeded at the ? measurement", ns.Detector.CastLength(), 3.00)

fire(nil, "ENCOUNTER_START", 3508)
channelling = { unit = "boss1", name = "<secret name>",
                from = 90210, to = 90210, id = 1288125 }
fire(nil, "UNIT_SPELLCAST_CHANNEL_START", "boss1", "c2", 1288125)
ns.Board.Tap("cross"); ns.Board.Tap("square")
channelling = nil
fire(nil, "UNIT_SPELLCAST_CHANNEL_STOP", "boss1", "c2", 1288125)

fire(nil, "UNIT_SPELLCAST_START", "boss1", "w1", 1288125)
check("the call hands the bar a length", (lastOf("call") or {})[4], 3.00)

H.now = H.now + 2.5
fire(nil, "UNIT_SPELLCAST_SUCCEEDED", "boss1", "w1", 1288125)
check("learned from where it actually landed", ns.Detector.CastLength(), 2.5)

fire(nil, "UNIT_SPELLCAST_START", "boss1", "w2", 1288125)
check("next wave's bar uses the learned value", (lastOf("call") or {})[4], 2.5)

-- A SUCCEEDED arriving 40s later is not this wave landing -- it is some other
-- event, or the player alt-tabbed. Learning from it would wreck every bar for
-- the rest of the pull, and the bar is the thing keeping them alive.
H.now = H.now + 40
fire(nil, "UNIT_SPELLCAST_SUCCEEDED", "boss1", "w2", 1288125)
check("an absurd gap is refused", ns.Detector.CastLength(), 2.5)

-- ---------------------------------------------------------------------------
io.write("Live client: UnitGUID is secret too\n")
-- The bug that actually shipped, 2026-08-15. UnitGUID comes back secret inside
-- this arena, so equals() answered nil, `nil == true` read as "not our boss",
-- and not a single wave was ever called. The board filled, locked, and then
-- went silent for the whole fight -- no error, no clue, nothing to grep for.
--
-- Every earlier test missed it because the harness handed out a plaintext GUID,
-- i.e. a path the real fight never takes.
-- ---------------------------------------------------------------------------
local SECRET_GUID = "<secret guid>"
SECRET[SECRET_GUID] = true
_G.UnitGUID = function() return SECRET_GUID end

fire(nil, "ENCOUNTER_START", 3508)
channelling = { unit = "boss1", name = "<secret name>",
                from = 90210, to = 90210, id = 1288125 }
fire(nil, "UNIT_SPELLCAST_CHANNEL_START", "boss1", "g", 1288125)
ns.Board.Tap("cross"); ns.Board.Tap("square")
channelling = nil
fire(nil, "UNIT_SPELLCAST_CHANNEL_STOP", "boss1", "g", 1288125)

local g0 = countOf("call")
fire(nil, "UNIT_SPELLCAST_START", "boss1", "gw1", 1288125)
check("waves ARE called when the GUID cannot be read", countOf("call"), g0 + 1)

-- The ?? fence has to survive losing its best evidence: with no comparable
-- GUID it falls back to the carrier, and the carrier is still not boss2.
fire(nil, "UNIT_SPELLCAST_START", "boss2", "add", 1288125)
check("the add is still refused on carrier alone", countOf("call"), g0 + 1)

fire(nil, "UNIT_SPELLCAST_START", "boss1", "gw2", 1288125)
check("and the real boss still gets through", countOf("call"), g0 + 2)

-- ---------------------------------------------------------------------------
io.write("The board gets out of the way when the round is over\n")
-- Reported live: after the echoes the board just sat there, and the wedges
-- still looked clickable. Two rules -- clear when done, tappable only while
-- he is preaching -- but the timing is the subtle half: "finish" arrives on
-- the LAST wave's START, with a whole cast still to run.
-- ---------------------------------------------------------------------------
fire(nil, "ENCOUNTER_START", 3508)
channelling = { unit = "boss1", name = "<secret name>",
                from = 90210, to = 90210, id = 1288125 }
fire(nil, "UNIT_SPELLCAST_CHANNEL_START", "boss1", "z", 1288125)
check("tappable while preaching", ns.Board.Tap("cross"), true)
ns.Board.Tap("square")
channelling = nil
fire(nil, "UNIT_SPELLCAST_CHANNEL_STOP", "boss1", "z", 1288125)

check("NOT tappable once he is echoing", ns.Board.Tap("triangle"), false)
check("and the sequence did not grow", #ns.Board.Sequence(), 2)

fire(nil, "UNIT_SPELLCAST_START", "boss1", "z1", 1288125)
fire(nil, "UNIT_SPELLCAST_START", "boss1", "z2", 1288125)   -- last wave: finish fires

H.now = H.now + 0.5
H.runTimers()
check("still up while the last wave is in the air", ns.Board.IsShown(), true)

H.now = H.now + 10
H.runTimers()
check("gone once that wave has landed", ns.Board.IsShown(), false)
check("and it cleared itself", #ns.Board.Sequence(), 0)

-- A new round starting before a pending clear fires must win outright --
-- a stale timer wiping a live recording would be far worse than a board
-- that lingers.
channelling = { unit = "boss1", name = "<secret name>",
                from = 90210, to = 90210, id = 1288125 }
fire(nil, "UNIT_SPELLCAST_CHANNEL_START", "boss1", "z3", 1288125)
check("new round is up", ns.Board.IsShown(), true)
ns.Board.Tap("cross")
H.now = H.now + 10
H.runTimers()
check("the stale clear did not wipe the new round", #ns.Board.Sequence(), 1)
check("and the board is still up", ns.Board.IsShown(), true)

-- ---------------------------------------------------------------------------
io.write("Call-out: this mark, arrow, next mark at 60%\n")
-- The board's pulse has no offline coverage (it is pixels on a timer). This
-- does: which marks go in the call-out, at what size, and the one rule with a
-- real failure mode -- an arrow on the LAST wave would read as "keep going" at
-- the exact moment the answer is "you are done".
-- ---------------------------------------------------------------------------
local S = ns.Announce.Spoken
local both, alone = S("cross", "square"), S("cross", nil)

check("current mark at full size",  both:find("UI%-RaidTargetingIcon_7:40") ~= nil, true)
check("next mark at 60% of it",     both:find("UI%-RaidTargetingIcon_6:24") ~= nil, true)
check("arrow between them",         both:find("ChatFrameExpandArrow") ~= nil, true)
check("last wave: mark still there", alone:find("UI%-RaidTargetingIcon_7:40") ~= nil, true)
check("last wave: no arrow",        alone:find("ChatFrameExpandArrow"), nil)

-- ---------------------------------------------------------------------------
io.write("Square board: which triangle took the click\n")
-- The four wedges overlap as rectangles, so one square button takes every
-- click and this decides what was hit. Screen coordinates: +y is up.
-- ---------------------------------------------------------------------------
local QA = ns.Board.QuadrantAt
check("straight up    -> cross",    QA(0, 50),   "cross")
check("straight right -> square",   QA(50, 0),   "square")
check("straight down  -> triangle", QA(0, -50),  "triangle")
check("straight left  -> circle",   QA(-50, 0),  "circle")
check("up, leaning right, still north", QA(20, 50), "cross")
check("right, leaning up, still east",  QA(50, 20), "square")
check("exactly on the NE diagonal",     QA(30, 30), "cross")
check("exactly on the SW diagonal",     QA(-30, -30), "triangle")
check("dead centre does not error",     QA(0, 0), "cross")

-- The wedges are alpha masks generated by tools/gen_wedges.py. If they are not
-- in the package the board renders as nothing at all -- an empty square with
-- four markers floating in it -- and no code path errors to say so.
for _, w in ipairs({ "n", "e", "s", "w" }) do
	local fh = io.open("Media/wedge-" .. w .. ".tga", "rb")
	check("Media/wedge-" .. w .. ".tga is present", fh ~= nil, true)
	if fh then fh:close() end
end

-- ---------------------------------------------------------------------------
io.write("Only Azta'rec -- every other boss is somebody else's problem\n")
-- Reported live 2026-08-15: a five-man dungeon boss brought the board up.
-- EVERY boss channels something, so the encounter id has to be the door and
-- not merely a hint about wave counts.
-- ---------------------------------------------------------------------------
ns.Board.Reset()
ns.Board.Hide()

fire(nil, "ENCOUNTER_START", 2900)          -- some dungeon boss
check("a dungeon boss does not arm it", ns.Detector.state.armed, false)

local quiet = countOf("call")
channelling = { unit = "boss1", name = "<secret name>",
                from = 90210, to = 90210, id = 1288125 }
fire(nil, "UNIT_SPELLCAST_CHANNEL_START", "boss1", "d", 1288125)
check("his channel opens no board", ns.Board.IsShown(), false)

channelling = nil
fire(nil, "UNIT_SPELLCAST_CHANNEL_STOP", "boss1", "d", 1288125)
fire(nil, "UNIT_SPELLCAST_START", "boss1", "d2", 1288125)
check("and his casts call nothing", countOf("call"), quiet)

-- An id we cannot read is treated exactly like a stranger. Fail closed: being
-- silently absent from a fight costs one pull, popping up in every dungeon
-- costs all of them.
fire(nil, "ENCOUNTER_START", nil)
check("an unreadable encounter id does not arm either", ns.Detector.state.armed, false)

fire(nil, "ENCOUNTER_START", 3525)
check("?? does arm", ns.Detector.state.armed, true)
check("and is read as hard", ns.Detector.state.difficulty, "hard")
check("and says so at the pull",
	(H.printed[#H.printed] or ""):find("5 / 6 / 7") ~= nil, true)

-- ---------------------------------------------------------------------------
io.write("Heads-up: where the echo starts, before it starts\n")
-- The channel stop and the first echo land on the same hundredth of a second,
-- so there is no gap to react in. The only place left to buy time is DURING
-- the last sermon wave -- which the taps, not any clock, tell us about.
-- ---------------------------------------------------------------------------
local P = ns.Announce.Preview
check("an arrow into the mark", P("square"):find("ChatFrameExpandArrow") ~= nil, true)
check("mark at full size",      P("square"):find("UI%-RaidTargetingIcon_6:40") ~= nil, true)
check("and no second mark",     P("square"):find("RaidTargetingIcon_%d+:24"), nil)

fire(nil, "ENCOUNTER_START", 3508)
channelling = { unit = "boss1", name = "<secret name>",
                from = 90210, to = 90210, id = 1288125 }
fire(nil, "UNIT_SPELLCAST_CHANNEL_START", "boss1", "p", 1288125)

local p0 = countOf("preview")
ns.Board.Tap("triangle")
check("nothing on the first tap of three", countOf("preview"), p0)
ns.Board.Tap("cross")
check("heads-up on the second of three", countOf("preview"), p0 + 1)
check("it points at the FIRST tap, not the newest",
	(lastOf("preview") or {})[2], "triangle")

-- ---------------------------------------------------------------------------
io.write("Standing board while inside the delve\n")
-- Between rounds the board should still be there: a place to rest the mouse,
-- and a thing you can drag into position before a pull rather than during one.
-- Outside the delve it packs itself away -- that half is what keeps it from
-- turning into wallpaper.
-- ---------------------------------------------------------------------------
ns.Board.Reset()   -- previous section left it mid-round
ns.Board.SetPersistent(true)
check("up as soon as we are inside", ns.Board.IsShown(), true)
check("and idle, so nothing is tappable", ns.Board.Tap("cross"), false)

fire(nil, "ENCOUNTER_START", 3508)
channelling = { unit = "boss1", name = "<secret name>",
                from = 90210, to = 90210, id = 1288125 }
fire(nil, "UNIT_SPELLCAST_CHANNEL_START", "boss1", "sb", 1288125)
ns.Board.Tap("cross"); ns.Board.Tap("square"); ns.Board.Tap("circle")
channelling = nil
fire(nil, "UNIT_SPELLCAST_CHANNEL_STOP", "boss1", "sb", 1288125)
for i = 1, 3 do fire(nil, "UNIT_SPELLCAST_START", "boss1", "sb" .. i, 1288125) end

H.now = H.now + 20
H.runTimers()
check("still standing after the round cleared", ns.Board.IsShown(), true)
check("but emptied out", #ns.Board.Sequence(), 0)

ns.Board.SetPersistent(false)
fire(nil, "ENCOUNTER_END", 3508)
H.now = H.now + 20
H.runTimers()
check("packs away once we leave", ns.Board.IsShown(), false)

-- ---------------------------------------------------------------------------
io.write(("\n%d passed, %d failed\n"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
