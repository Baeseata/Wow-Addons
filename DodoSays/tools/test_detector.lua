-- ===========================================================================
-- test_detector.lua  ·  offline logic tests. Run from the addon folder:
--
--     lua tools/test_detector.lua
--
-- These load the real Util/Board/Announce/Detector and drive them through the
-- real event handler. The only fakes are client APIs.
--
-- 🔴 Everything the client hands over here is SECRET, because that is what was
-- measured in the arena on 2026-08-15: spellID, name, cast timestamps and
-- UnitGUID, all of them. A test that wants a readable value says so at the
-- call site with H.plain(...) -- there are a handful, each with its reason
-- written next to it, and the run prints the tally at the end.
--
-- The one that matters most is FENCE: on ?? the second boss ("Echo of
-- Azta'rec") casts abilities that also read as "Echo of ...", and the reference
-- implementation logged a hard round losing 2 of its 5 calls to it. If that
-- test ever goes green with the identity check removed, the fence is
-- decorative.
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

assert(H.listenerFor("ENCOUNTER_START"), "Detector registered no OnEvent handler")

-- ---------------------------------------------------------------------------
io.write("Util: three answers, three branches\n")
-- The whole addon hangs off equals() having a third answer. On 2026-08-15 the
-- caller wrote `equals(...) == true`, which folds "cannot be known" back into
-- "no", and the fight went by in silence. So the contract gets pinned here
-- rather than left to the one comment nobody reads twice.
-- ---------------------------------------------------------------------------
local probeNumber = H.secretNumber("probe")
local probeName   = H.secretString("probe name")

check("equals answers plainly when it can",   ns.equals(1, 1), true)
check("equals still says no when it can",     ns.equals(1, 2), false)
check("equals says NIL -- not false -- when it cannot know",
	ns.equals(probeNumber, 1), nil)
check("a secret is not a usable number",      ns.usableNumber(probeNumber), nil)
check("a readable one is",                    ns.usableNumber(1288103), 1288103)
check("describe never leaks a secret",        ns.describe(probeNumber), "<secret>")
check("nameKey refuses a secret name",        ns.nameKey(probeName), nil)

check("nameKey folds the straight apostrophe",
	ns.nameKey("Sermon of Ula'tek"), "sermonofulatek")
check("nameKey folds the typographic one",
	ns.nameKey("Sermon of Ula\226\128\153tek"), "sermonofulatek")
check("nameKey is case-blind",
	ns.nameKey("ECHO OF ULA'TEK"), ns.nameKey("Echo of Ula'tek"))

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
io.write("A full normal round, exactly as the client gives it\n")
-- Nothing readable anywhere in here except the encounter id. This is the whole
-- fight as measured.
-- ---------------------------------------------------------------------------
H.encounterStart(3508)
check("encounter id picked the difficulty", ns.Detector.state.difficulty, "normal")

H.channelStart("boss1")
check("round opened", (lastOf("round") or {})[1], "round")
check("unreadable channel falls back to the round table",
	(lastOf("round") or {})[2], 3)

ns.Board.Tap("cross"); ns.Board.Tap("square"); ns.Board.Tap("triangle")
check("three taps recorded", #ns.Board.Sequence(), 3)

H.channelStop("boss1")
check("sequence locked at three", (lastOf("lock") or {})[2], 3)

H.cast("boss1")
check("first call is the first tap", (lastOf("call") or {})[3], "cross")
H.cast("boss1")
check("second call is the second tap", (lastOf("call") or {})[3], "square")

-- ---------------------------------------------------------------------------
io.write("Channel length beats the round table when the client allows it\n")
-- DECLARED READABLE, and the only test that is: the point of it is the branch
-- where the client does hand over the channel's clock. It never has in this
-- arena -- but the wave count is the one number a future patch could start
-- answering, and code that only runs on ?? needs somewhere to be wrong safely.
-- ---------------------------------------------------------------------------
H.encounterStart(3525)
check("hard difficulty", ns.Detector.state.difficulty, "hard")

-- 21.021s at the hard seed of 3.003s/wave = 7 waves, which is round 3 on hard --
-- and the round table would have said 5, so this proves measurement wins.
H.channelStart("boss1", { from = H.plain(1000), to = H.plain(22021) })
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
H.cast("boss1")
check("no calls while still showing", countOf("call"), before)

H.channelStop("boss1")
check("locked at five", (lastOf("lock") or {})[2], 5)

-- Echo of Azta'rec: different unit, and -- the nasty part -- an ability whose
-- name also folds to "echoof...".
--
-- DECLARED READABLE on purpose. Both the id and the name are handed over
-- saying yes, so the only thing left refusing this cast is identity. It also
-- pins the ORDER: the handler asks isOurBoss before it asks what the spell is,
-- and if anyone ever swaps those two lines this goes red.
before = countOf("call")
H.cast("boss2", { id = H.plain(1288125), name = H.plain("Echo of Ula'tek") })
check("the add's cast was refused", countOf("call"), before)

H.cast("boss1")
check("the real boss still gets through", countOf("call"), before + 1)
check("and it called the first tap", (lastOf("call") or {})[3], "cross")

-- ---------------------------------------------------------------------------
io.write("The main phase keeps casting: the wave count is the only fence\n")
-- Measured on ? (docs/RESEARCH-live-trace.md 5): identifyEcho falls through to
-- "place" on every single cast, and "is this our boss casting" stays true for
-- the whole main phase. 114 UNIT_SPELLCAST_START in that pull; 7 were echoes.
-- The trace shows casts at 41.0s and 45.9s, seconds after a three-wave round
-- ended at 39.3s. Nothing but "we have already called them all" stops those.
-- ---------------------------------------------------------------------------
H.encounterStart(3508)
H.channelStart("boss1")
check("round opened with nothing readable at all", (lastOf("round") or {})[2], 3)

ns.Board.Tap("cross"); ns.Board.Tap("square"); ns.Board.Tap("triangle")
H.channelStop("boss1")

local base = countOf("call")
for _ = 1, 3 do H.cast("boss1") end
check("three waves called", countOf("call"), base + 3)
check("finish fired at the last wave", (log[#log] or {})[1], "finish")

H.cast("boss1")   -- rotation, 41.0s in the trace
H.cast("boss1")   -- rotation, 45.9s
check("main-phase rotation is not mistaken for calls", countOf("call"), base + 3)

-- ---------------------------------------------------------------------------
io.write("The cast bar measures itself\n")
-- The bar cannot read the cast's own clock -- start and end are secret. So it
-- times START -> SUCCEEDED with GetTime(), which is plain. ? measured 3.00s;
-- ?? is unmeasured, and this is what stops that from mattering.
-- ---------------------------------------------------------------------------
check("seeded at the ? measurement", ns.Detector.CastLength(), 3.00)

H.encounterStart(3508)
H.channelStart("boss1")
ns.Board.Tap("cross"); ns.Board.Tap("square")
H.channelStop("boss1")

H.cast("boss1")
check("the call hands the bar a length", (lastOf("call") or {})[4], 3.00)

H.now = H.now + 2.5
H.landed("boss1")
check("learned from where it actually landed", ns.Detector.CastLength(), 2.5)

H.cast("boss1")
check("next wave's bar uses the learned value", (lastOf("call") or {})[4], 2.5)

-- A SUCCEEDED arriving 40s later is not this wave landing -- it is some other
-- event, or the player alt-tabbed. Learning from it would wreck every bar for
-- the rest of the pull, and the bar is the thing keeping them alive.
H.now = H.now + 40
H.landed("boss1")
check("an absurd gap is refused", ns.Detector.CastLength(), 2.5)

-- ---------------------------------------------------------------------------
io.write("Identity when the GUID cannot be read -- and when it can\n")
-- The bug that actually shipped, 2026-08-15. UnitGUID comes back secret inside
-- this arena, so equals() answered nil, `nil == true` read as "not our boss",
-- and not a single wave was ever called. The board filled, locked, and then
-- went silent for the whole fight -- no error, no clue, nothing to grep for.
-- ---------------------------------------------------------------------------
H.encounterStart(3508)
H.channelStart("boss1")
ns.Board.Tap("cross"); ns.Board.Tap("square")
H.channelStop("boss1")

-- 🔴 The first half of that bug, pinned on its own. guidOf() must hand back
-- nil rather than the secret: a secret is TRUTHY, so storing one makes
-- `if state.bossGUID then` true forever and shuts off every fallback behind
-- it. Measured 2026-08-16 -- with only the second half fixed, removing this
-- filter left the whole suite green, so the two halves could have been
-- dismantled one at a time with nothing objecting until it was live again.
check("a secret GUID is not stored as though it were one",
	ns.Detector.state.bossGUID, nil)

local g0 = countOf("call")
H.cast("boss1")
check("waves ARE called when the GUID cannot be read", countOf("call"), g0 + 1)

-- The ?? fence has to survive losing its best evidence: with no comparable
-- GUID it falls back to the carrier, and the carrier is still not boss2.
H.cast("boss2")
check("the add is still refused on carrier alone", countOf("call"), g0 + 1)

H.cast("boss1")
check("and the real boss still gets through", countOf("call"), g0 + 2)

-- DECLARED READABLE. The other half of isOurBoss -- the branch that compares
-- GUIDs -- has no other way to be exercised, because the client never lets it
-- run here. It is the insurance policy for the day it does, and an untested
-- insurance policy is not one.
H.plainGUIDs(true)
H.encounterStart(3508)
H.channelStart("boss1")
ns.Board.Tap("triangle"); ns.Board.Tap("circle")
H.channelStop("boss1")

local p0 = countOf("call")
H.cast("boss2")
check("with readable GUIDs the add is refused BY GUID", countOf("call"), p0)
H.cast("boss1")
check("and the boss is recognised by it", countOf("call"), p0 + 1)
check("calling the right quarter", (lastOf("call") or {})[3], "triangle")
H.plainGUIDs(false)

-- ---------------------------------------------------------------------------
io.write("The board gets out of the way when the round is over\n")
-- Reported live: after the echoes the board just sat there, and the wedges
-- still looked clickable. Two rules -- clear when done, tappable only while
-- he is preaching -- but the timing is the subtle half: "finish" arrives on
-- the LAST wave's START, with a whole cast still to run.
-- ---------------------------------------------------------------------------
H.encounterStart(3508)
H.channelStart("boss1")
check("tappable while preaching", ns.Board.Tap("cross"), true)
ns.Board.Tap("square")
H.channelStop("boss1")

check("NOT tappable once he is echoing", ns.Board.Tap("triangle"), false)
check("and the sequence did not grow", #ns.Board.Sequence(), 2)

H.cast("boss1")
H.cast("boss1")   -- last wave: finish fires

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
H.channelStart("boss1")
check("new round is up", ns.Board.IsShown(), true)
ns.Board.Tap("cross")
H.now = H.now + 10
H.runTimers()
check("the stale clear did not wipe the new round", #ns.Board.Sequence(), 1)
check("and the board is still up", ns.Board.IsShown(), true)

-- ---------------------------------------------------------------------------
io.write("Traffic light: green here, yellow next, red everywhere else\n")
-- The one thing on this board that has to be right in half a second, so it is
-- a pure function reading (sequence, phase, callIndex) -- no frame, no client,
-- no timing. PaintPlan() and QuadrantAt() are the two parts of Board.lua that
-- can kill you and the two parts a test can pin outright.
-- ---------------------------------------------------------------------------
local function shades()
	local p = ns.Board.PaintPlan()
	local out = {}
	for _, q in ipairs(ns.QUADRANTS) do out[#out + 1] = q.id .. "=" .. p.shade[q.id] end
	return table.concat(out, " ")
end

ns.Board.Reset()
ns.Board.SetPersistent(false)
check("idle: nothing is coloured", shades(),
	"cross=idle square=idle triangle=idle circle=idle")

H.encounterStart(3508)
H.channelStart("boss1")
check("preaching, nothing tapped: no traffic light yet", shades(),
	"cross=armed square=armed triangle=armed circle=armed")

ns.Board.Tap("cross"); ns.Board.Tap("triangle"); ns.Board.Tap("square")
check("preaching: tapped ones are BLUE, not green", shades(),
	"cross=recorded square=recorded triangle=recorded circle=armed")

-- 🔴 The lock, before any echo has been announced. CHANNEL_STOP and the first
-- echo land on the same hundredth of a second, so if the light waited to be
-- told about wave one it would light up after the wave that needs it most.
H.channelStop("boss1")
check("at the lock the light is ALREADY on wave one", shades(),
	"cross=now square=unsafe triangle=next circle=unsafe")
check("and the headline agrees with the green wedge", ns.Board.Phase(), "calling")

H.cast("boss1")   -- wave 1 announced; the board was already saying this
check("wave 1 announced: nothing moved, it was right already", shades(),
	"cross=now square=unsafe triangle=next circle=unsafe")

H.cast("boss1")   -- wave 2
check("wave 2: green walks to the triangle, yellow to the square", shades(),
	"cross=unsafe square=next triangle=now circle=unsafe")

H.cast("boss1")   -- wave 3, the last one
check("last wave: one green, three red, NO yellow", shades(),
	"cross=unsafe square=now triangle=unsafe circle=unsafe")

-- 🔴 "finish" arrives on the LAST wave's START, with a whole cast still to run.
-- The light must survive it: that wave has no next quarter to fall back on.
-- (The first version of Board.Finish moved to phase=done here and this test
-- caught it -- the last wave was the only one that never turned green.)
ns.Board.Finish(0.1)
check("finish fired, and the last wave is STILL green", shades(),
	"cross=unsafe square=now triangle=unsafe circle=unsafe")

H.now = H.now + 1
H.runTimers()
check("the light goes out once that wave has landed", shades(),
	"cross=idle square=idle triangle=idle circle=idle")
check("and it did not restart at wave one", ns.Board.Phase(), "idle")

-- Nothing tapped at all. The round locks straight to done -- there is no wave
-- to point at, and a board of red would read as "all four are wrong" rather
-- than "I have nothing for you".
ns.Board.Reset()
H.channelStart("boss1")
H.channelStop("boss1")
check("nothing recorded: greyed out, not a wall of red", shades(),
	"cross=done square=done triangle=done circle=done")

-- Same quarter twice in a row. Green wins; no wedge is yellow. This pins the
-- BRANCH ORDER inside PaintPlan -- ask "now" first -- because swapping those
-- two reads like a tidy-up and turns the wedge you are standing on yellow,
-- i.e. "leave". ⚠ The tray underneath follows the same plan and is NOT pinned
-- offline: its cells are painted with SetColorTexture, which the frame
-- background and every swatch border also use, so counting colours there
-- proves nothing. That half is eyes-on-the-live-client only.
ns.Board.Reset()
H.channelStart("boss1")
ns.Board.Tap("circle"); ns.Board.Tap("circle"); ns.Board.Tap("cross")
H.channelStop("boss1")
check("repeat: green wins and no wedge is yellow", shades(),
	"cross=unsafe square=unsafe triangle=unsafe circle=now")
H.cast("boss1")   -- wave 1: the board was already showing it
H.cast("boss1")   -- wave 2, the second circle
check("second of the pair: yellow appears again for what follows", shades(),
	"cross=next square=unsafe triangle=unsafe circle=now")

-- ---------------------------------------------------------------------------
io.write("...and the light actually reaches the wedges\n")
-- PaintPlan() being right proves the DECISION. Whether refresh() paints what it
-- decided is a second claim, and the seam between two correct halves is exactly
-- where nobody is looking. Counts are enough: four wedges get tinted per
-- refresh, and the traffic light has a shape no other phase produces.
-- ---------------------------------------------------------------------------
local function tintCounts()
	local seen = {}
	for _, c in ipairs(H.vertexColors) do
		local key = ("%.2f,%.2f,%.2f"):format(c[1] or 0, c[2] or 0, c[3] or 0)
		seen[key] = (seen[key] or 0) + 1
	end
	return seen
end

ns.Board.Reset()
H.channelStart("boss1")
ns.Board.Tap("cross"); ns.Board.Tap("square"); ns.Board.Tap("triangle")
H.channelStop("boss1")

H.clearVertexColors()
ns.Board.Show()          -- one full repaint of the locked board
local seen = tintCounts()
check("exactly one wedge painted green", seen["0.16,0.72,0.30"], 1)
check("exactly one painted yellow",      seen["0.94,0.78,0.12"], 1)
check("the other two painted red",       seen["0.66,0.16,0.16"], 2)
check("and no wedge kept the old orange", seen["0.98,0.62,0.10"], nil)

-- The colour collision, pinned. `recorded` was green once, which made green
-- say "I wrote this one down" while he preaches and "stand here NOW" while he
-- echoes -- the same colour, on the same board, giving opposite instructions.
-- Nothing above would notice it coming back: the shade is still NAMED
-- "recorded", so PaintPlan stays green all the way through.
ns.Board.Reset()
H.channelStart("boss1")
ns.Board.Tap("cross"); ns.Board.Tap("square")
H.clearVertexColors()
ns.Board.Show()
check("nothing is traffic-light green while he is still preaching",
	tintCounts()["0.16,0.72,0.30"], nil)

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

H.encounterStart(2900)          -- some dungeon boss
check("a dungeon boss does not arm it", ns.Detector.state.armed, false)

local quiet = countOf("call")
H.channelStart("boss1")
check("his channel opens no board", ns.Board.IsShown(), false)

H.channelStop("boss1")
H.cast("boss1")
check("and his casts call nothing", countOf("call"), quiet)

-- An id we cannot read is treated exactly like a stranger. Fail closed: being
-- silently absent from a fight costs one pull, popping up in every dungeon
-- costs all of them.
H.encounterStart(nil)
check("an unreadable encounter id does not arm either", ns.Detector.state.armed, false)

-- The documented risk, rehearsed: the id is the ONE client value still readable
-- in here (measured 3508 / difficulty 208), and the whole door hangs off it. If
-- a patch makes it secret, this addon must go quiet -- not open the board over
-- every boss in the game. usableNumber is what makes that true, so the day
-- someone "simplifies" it away, this is the line that objects.
--
-- 🔴 It has to be OUR id wearing the cloak. The first version of this test used
-- a freshly minted secret, which is not in the difficulty table at all -- so it
-- failed closed because the number was a stranger, not because it was secret,
-- and dropping usableNumber() from Arm() walked straight through it green
-- (measured 2026-08-16). A secret reports as the value it hides; the lookup
-- that was going to succeed still succeeds.
H.whileSecret(3508, function() H.encounterStart(3508) end)
check("a SECRET encounter id fails closed too", ns.Detector.state.armed, false)

H.encounterStart(3525)
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

H.encounterStart(3508)
H.channelStart("boss1")

local pv = countOf("preview")
ns.Board.Tap("triangle")
check("nothing on the first tap of three", countOf("preview"), pv)
ns.Board.Tap("cross")
check("heads-up on the second of three", countOf("preview"), pv + 1)
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

H.encounterStart(3508)
H.channelStart("boss1")
ns.Board.Tap("cross"); ns.Board.Tap("square"); ns.Board.Tap("circle")
H.channelStop("boss1")
for _ = 1, 3 do H.cast("boss1") end

H.now = H.now + 20
H.runTimers()
check("still standing after the round cleared", ns.Board.IsShown(), true)
check("but emptied out", #ns.Board.Sequence(), 0)

ns.Board.SetPersistent(false)
H.encounterEnd(3508)
H.now = H.now + 20
H.runTimers()
check("packs away once we leave", ns.Board.IsShown(), false)

-- ---------------------------------------------------------------------------
-- The tally. Every client value in this run was unreadable except these, and
-- each one is a deliberate line in a comment above. If this number starts
-- climbing, the suite is drifting back onto a path the fight never takes --
-- which is exactly how three bugs shipped in one evening.
-- ---------------------------------------------------------------------------
io.write(("\n%d client value(s) declared readable: %s\n")
	:format(#H.declared, table.concat(H.declared, ", ")))
io.write(("%d passed, %d failed\n"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
