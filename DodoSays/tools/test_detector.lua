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
-- DodoSays.lua rides along for the slash tests at the bottom. At load it only
-- defines functions and registers a frame for ADDON_LOADED / zone changes --
-- none of which this suite fires -- so it cannot disturb anything above. The
-- files it does NOT get (Sim, Trace, Options, Minimap) are only ever reached
-- from subcommands nothing here runs.
-- Options.lua rides along for ns.DEFAULTS, which normalizeSound falls back to.
-- Its top level only declares tables and functions -- the panel is not built
-- until ns.BuildOptions() is called, which nothing here does.
local ns = H.load({ "Util.lua", "Board.lua", "Announce.lua", "Detector.lua",
	"Options.lua", "Macros.lua", "DodoSays.lua" })
-- "off" rather than false: the boolean is the PRE-0.12 shape, and leaving it
-- here would mean most of this suite runs against a value the addon no longer
-- writes -- while still looking silent, because an unrecognised mode is
-- silent. The sound section below sets this per case.
ns.db = { announce = false, sound = "off", debug = false }

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
-- Close the channel before leaving, or Detector is still mid-showing and the
-- NEXT section's channelStart is swallowed by `if state.showing then return`.
-- (Which is exactly what happened, and it made that section's board land in
-- "done" while its assertions were written for "calling".)
H.channelStop("boss1")

-- ---------------------------------------------------------------------------
io.write("The markers keep their colour when nothing is happening\n")
-- Reported live 2026-08-16: the standing board looked switched off between
-- rounds. It greyed every wedge that was not tappable, and a marker's COLOUR is
-- its identity -- the whole design rests on recognising a red cross rather than
-- reading a label, and a grey cross is harder to recognise, not easier.
--
-- So: never desaturated, anywhere. Emphasis is alpha, and exactly one thing
-- dims -- a quarter that is unsafe THIS WAVE.
-- ---------------------------------------------------------------------------
local function alphaCounts()
	local seen = {}
	for _, a in ipairs(H.alphas) do seen[a] = (seen[a] or 0) + 1 end
	return seen
end
local function greyedOut()
	local n = 0
	for _, d in ipairs(H.desaturations) do if d == true then n = n + 1 end end
	return n
end

-- Arm afresh rather than inheriting whatever the last section left behind:
-- Detector.Arm clears state.showing, and a section that starts mid-showing has
-- its channelStart swallowed and lands in a different phase than it asserts.
H.encounterStart(3508)
ns.Board.Reset()          -- idle: the board just standing there
H.clearVertexColors()
ns.Board.Show()
check("idle: four markers painted, not one greyed out", greyedOut(), 0)
check("idle: all four at full opacity", alphaCounts()[1], 4)
check("idle: none dimmed", alphaCounts()[0.62], nil)

-- Mid-round, the traffic light is on: two bright, two dim -- still in colour.
H.channelStart("boss1")
ns.Board.Tap("cross"); ns.Board.Tap("square"); ns.Board.Tap("triangle")
H.channelStop("boss1")
H.clearVertexColors()
ns.Board.Show()
check("calling: still nothing greyed out", greyedOut(), 0)
check("calling: the green and the yellow are bright", alphaCounts()[1], 2)
check("calling: the two unsafe quarters dim", alphaCounts()[0.62], 2)
H.channelStop("boss1")   -- leave the state machine idle for whoever is next

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
io.write("Slash taps: the third door in, the one a ring addon can reach\n")
-- OPie and its kind hold macros, not keybindings, so /dodosays <quarter> exists
-- to give them something to point at. Driven through the REAL registered
-- handler rather than straight at Board.Tap, because the tap is not the risk
-- here -- the dispatch is. Anything ever shadowing one of these four would drop
-- a wave out of the sequence in silence, in the fight, with nothing erroring.
-- ---------------------------------------------------------------------------
local run = assert(SlashCmdList.DODOSAYS, "DodoSays.lua registered no slash handler")

ns.Board.Reset()
H.encounterStart(3508)
H.channelStart("boss1")

H.printed = {}
for _, q in ipairs(ns.QUADRANTS) do run(q.id) end
check("every quarter reaches the board", #ns.Board.Sequence(), #ns.QUADRANTS)
-- A tap that worked says nothing. Worth pinning rather than assuming: the
-- first cut of this had DodoSays_Tap returning nothing at all, so the command
-- recorded the tap AND then explained why it had not -- four lines of chat per
-- round, each of them a lie, and every other check here still green.
check("a tap that counted keeps quiet", #H.printed, 0)
check("in the order it was typed",
	table.concat(ns.Board.Sequence(), ","), "cross,square,triangle,circle")

run("SQUARE")
check("case is not a trap for whoever writes the macro", #ns.Board.Sequence(), 5)
run("   circle   ")
check("neither is stray whitespace", #ns.Board.Sequence(), 6)
run("cirlce")
check("a typo taps nothing at all", #ns.Board.Sequence(), 6)
run("undo")
check("and undo is still the subcommand, not a quarter", #ns.Board.Sequence(), 5)

-- Outside the sermon half nothing records either way; what differs is whether
-- it says so. In a city that line is the entire point -- somebody has just
-- built the macro and is checking it. In the fight it would be one more thing
-- on top of the one thing they are trying to read.
H.channelStop("boss1")
ns.Board.Reset()

H.inCombat(false)
H.printed = {}
run("cross")
check("outside the sermon nothing is recorded", #ns.Board.Sequence(), 0)
check("and out of combat it explains itself", #H.printed > 0, true)

H.inCombat(true)
H.printed = {}
run("cross")
check("but in the fight it stays shut", #H.printed, 0)
H.inCombat(false)

-- ---------------------------------------------------------------------------
io.write("Made macros: four of them, and each one actually works\n")
-- A macro body and a slash handler are two artefacts that are each perfectly
-- fine on their own, and nothing structural makes them agree. Rename a quarter
-- or the command and every macro already sitting on somebody's action bar
-- points at nothing -- no error, anywhere, ever. So the bodies are not compared
-- against a string here; they are taken apart the way the client takes a macro
-- line apart, and run.
-- ---------------------------------------------------------------------------
local made, updated, err = ns.Macros.Create()
check("four macros made", made, 4)
check("nothing to refresh on a clean slate", updated, 0)
check("and no complaint", err, nil)

local byName = {}
for _, m in ipairs(H.macros()) do byName[m.name] = m end
check("named after the marker, Dodo-prefixed", byName["Dodo Triangle"] ~= nil, true)
check("icon is the raid marker's own file id", byName["Dodo Cross"].icon, 137007)
check("and the big orange one for circle",    byName["Dodo Circle"].icon, 137002)

local longest = 0
for _, q in ipairs(ns.QUADRANTS) do
	longest = math.max(longest, #ns.Macros.NameFor(q))
end
check("every name fits the client's 16 characters", longest <= 16, true)

local made2, updated2 = ns.Macros.Create()
check("pressing it twice makes nothing new", made2, 0)
check("it refreshes the same four", updated2, 4)
check("so there are still four", #H.macros(), 4)

-- Dispatched the way the client dispatches: the first word chooses a handler,
-- the rest is the argument. Looked up rather than called directly, and that is
-- the entire point of this block -- calling SlashCmdList.DODOSAYS by hand makes
-- a body pointing at a command that does not exist still "work", which is
-- exactly what the first version of this test did, and the A/B walked through
-- it (four checks red, the one that mattered green).
local registered = {
	[SLASH_DODOSAYS1] = SlashCmdList.DODOSAYS,
	[SLASH_DODOSAYS2] = SlashCmdList.DODOSAYS,
}

ns.Board.Reset()
H.encounterStart(3508)
H.channelStart("boss1")
for _, q in ipairs(ns.QUADRANTS) do
	local slashWord, rest = byName[ns.Macros.NameFor(q)].body:match("^(%S+)%s*(.*)$")
	local handler = registered[slashWord]
	check(q.id .. ": macro calls a command this addon really registered",
		handler ~= nil, true)
	if handler then handler(rest) end
end
check("and all four bodies land on the board",
	table.concat(ns.Board.Sequence(), ","), "cross,square,triangle,circle")

H.inCombat(true)
local _, _, combatErr = ns.Macros.Create()
check("in combat it refuses outright", combatErr, "combat")
check("and touches nothing", #H.macros(), 4)
check("the refusal says what to do instead",
	ns.Macros.Report(0, 0, "combat"):find("after the fight") ~= nil, true)
H.inCombat(false)

-- Running out of slots halfway is a real state on a real account, and "it
-- failed" would hide which half happened.
H.clearMacros()
H.fillMacroSlots(118)
local m4, u4, e4 = ns.Macros.Create()
check("it fills what it can", m4, 2)
check("then says it ran out", e4, "noslots")
check("and the message counts what it managed",
	ns.Macros.Report(m4, u4, e4):find("2 of 4") ~= nil, true)
H.clearMacros()

-- ---------------------------------------------------------------------------
io.write("Sound: four modes, and the voice must name the quarter on screen\n")
-- The failure that matters here is not silence -- it is the addon confidently
-- saying "square" while the icon says "cross". Silence is survivable; a wrong
-- marker walks the player into the venom believing they are safe. So every
-- assertion below is on WHICH file was asked for, never on how many played.
-- ---------------------------------------------------------------------------
local VOICE = "Interface\\AddOns\\DodoSays\\Sounds\\"

-- `call` carries (step, id, castLength) and `preview` carries just the id --
-- same seam, different shapes -- so this puts the id where each one reads it.
local function soundsFor(mode, event, id)
	ns.db.sound = mode
	H.clearSounds()
	if event == "preview" then ns.Emit(event, id) else ns.Emit(event, 0, id, 1) end
	return H.sounds()
end

-- Does the call handler reach its own last line in the barest state there is,
-- with nothing built and nothing drawn?
--
-- ⚠ This has to stay FIRST in the section. The moment anything above sets
-- announce = true, Flash builds the countdown bar, runBar's nil branch stops
-- being reachable, and this quietly becomes an assertion about nothing.
-- ⚠ It is also not reproducing a live client: ADDON_LOADED calls
-- Announce.ApplyPosition(), which builds that frame long before any pull. What
-- it buys is a tripwire on the handler as a whole -- emit() swallows
-- subscriber errors outside debug mode, so with nothing watching that channel
-- any future line that throws mid-handler costs everything after it in
-- silence. Debug mode is the only place that error surfaces.
ns.db.debug, ns.db.sound = true, "off"
local printedBefore = #H.printed
ns.Emit("call", 0, "cross", 1)
local died = false
for i = printedBefore + 1, #H.printed do
	if tostring(H.printed[i]):find("subscriber failed") then died = true end
end
check("the call handler runs to the end, nothing drawn", died, false)
ns.db.debug = false

local s = soundsFor("off", "call", "cross")
check("silent means silent", #s, 0)

s = soundsFor("beep", "call", "cross")
check("the chime still fires", #s, 1)
check("and it is a kit, not a file", s[1] and s[1].kind, "kit")

s = soundsFor("zh", "call", "cross")
check("a voice mode plays a file instead", s[1] and s[1].kind, "file")
check("out of its own language folder", s[1] and s[1].ref, VOICE .. "zh\\cross.ogg")
check("and does not also chime", #s, 1)

-- Every quarter, not one sample. A mapping that is right for cross and wrong
-- for circle is precisely the bug this cannot afford, and it is invisible
-- until you walk all four -- which is also why the file is named for the
-- quadrant id rather than the marker number the pack shipped with.
for _, q in ipairs(ns.QUADRANTS) do
	local got = soundsFor("zh", "call", q.id)[1]
	check("zh " .. q.id .. " speaks " .. q.id, got and got.ref, VOICE .. "zh\\" .. q.id .. ".ogg")
	got = soundsFor("en", "call", q.id)[1]
	check("en " .. q.id .. " speaks " .. q.id, got and got.ref, VOICE .. "en\\" .. q.id .. ".ogg")
end

-- The heads-up is silent in EVERY mode, including the voices. It fires while
-- the player is still tapping quarters, so anything audible there arrives as
-- feedback on the tap they just made while naming a different quarter -- and
-- Board.lua emits it on `>= expected - 1`, so the last two taps each get one.
-- 0.12 shipped with a voice here and both problems showed up in the first live
-- rehearsal. The dimmed arrow already says it, to eyes that are on the board.
--
-- ⚠ All three assert zero, which is the weakest shape a check can have: they
-- would pass equally well if sound were broken everywhere. What proves the
-- channel actually works is the call block above -- these only say the preview
-- stays out of it.
for _, mode in ipairs({ "zh", "en", "beep" }) do
	check("the heads-up stays silent in " .. mode, #soundsFor(mode, "preview", "square"), 0)
end

-- Both ways of being handed something the mode table does not know. Silence is
-- the deliberate answer to both: guessing a quarter is how a player dies.
check("an unknown mode is silent, not an error", #soundsFor("klingon", "call", "cross"), 0)
check("so is a quarter that does not exist", #soundsFor("zh", "call", "nowhere"), 0)

-- The regression that this section was written blind to and caught anyway:
-- switching the centre-screen text off must not take the sound with it. They
-- are separate switches, and what linked them was a nil index inside the
-- subscriber pcall -- silent outside debug mode, so on a live client it would
-- read as "the voices just don't work for me" with nothing to point at.
ns.db.announce = true
local withText = soundsFor("zh", "call", "cross")[1]
ns.db.announce = false
local withoutText = soundsFor("zh", "call", "cross")[1]
check("the voice does not depend on the centre-screen text",
	withoutText and withoutText.ref, withText and withText.ref)
check("and it is still the right quarter", withoutText and withoutText.ref, VOICE .. "zh\\cross.ogg")


-- The pre-0.12 boolean. Nothing else in this suite reaches migrateDB -- it
-- runs on the ADDON_LOADED path, which the offline run never fires -- and an
-- install that silently went mute on upgrade would never be reported as a bug,
-- only uninstalled.
check("an install that had sound on keeps its chime", ns.migrateDB({ sound = true }).sound, "beep")
check("one that had it off stays off",                ns.migrateDB({ sound = false }).sound, "off")
check("a real mode is left alone",                    ns.migrateDB({ sound = "en" }).sound, "en")
check("and an untouched install is left to defaults", ns.migrateDB({}).sound, nil)

-- normalizeSound, and the bug it was written for. 0.12 shipped with `sound`
-- still listed in Minimap.lua's toggle table, whose shared OnClick writes
-- `self:GetChecked() and true or false` -- so opening the panel most people
-- actually use and touching that row stamped a boolean over the mode key and
-- muted the addon, while the box stayed ticked. Nothing pointed at it: an
-- unrecognised mode is silent by design.
-- ⚠ Of these two, only the SECOND can tell whether migrateDB still runs inside
-- normalizeSound. `true` maps to "beep" and the fallback default is also
-- "beep", so the first line stays green with the migration ripped out --
-- measured, not assumed. `false` is the only input where the two paths part.
check("a stale boolean normalises to the chime", ns.normalizeSound({ sound = true }).sound, "beep")
check("and false to silence",                    ns.normalizeSound({ sound = false }).sound, "off")
check("a real mode is left alone",               ns.normalizeSound({ sound = "zh" }).sound, "zh")
check("junk falls back to the default",          ns.normalizeSound({ sound = "klingon" }).sound, ns.DEFAULTS.sound)
check("so does a missing value",                 ns.normalizeSound({}).sound, ns.DEFAULTS.sound)
check("and the default is itself a real mode",   ns.SOUND_MODE_BY_KEY[ns.DEFAULTS.sound] ~= nil, true)

-- The structural half: no panel may drive `sound` through a boolean toggle
-- again. Reading the source because the table is a local -- and reading BOTH
-- panels, because the whole failure was that only one of them got updated.
for _, f in ipairs({ "Minimap.lua", "Options.lua" }) do
	local fh = io.open(f, "r")
	local src = fh and fh:read("*a") or ""
	if fh then fh:close() end
	check(f .. " was read at all", #src > 0, true)
	check("no boolean toggle row owns sound in " .. f,
		src:find('key%s*=%s*"sound"', 1, false), nil)
end

ns.db.sound = "off"

-- ---------------------------------------------------------------------------
io.write("Shipped files carry no stray CJK\n")
-- The CF listing and everything in the package are English. A Chinese
-- character that slips into a shipped file is the sort of thing nobody notices
-- until it is already on the store page.
--
-- The file list is DERIVED FROM THE TOC, not written out here: a file added to
-- the addon is covered automatically. A hand-kept list stops covering things
-- the first time someone forgets to extend it, and stays green while doing so.
-- ---------------------------------------------------------------------------
local function slurp(p)
	local fh = io.open(p, "r")
	if not fh then return nil end
	local s = fh:read("*a"); fh:close(); return s
end

local shipped, tocSrc = { "DodoSays.toc", "README.md", "Bindings.xml" }, slurp("DodoSays.toc")
for line in (tocSrc or ""):gmatch("[^\r\n]+") do
	local f = line:match("^%s*([%w_]+%.lua)%s*$")
	if f then shipped[#shipped + 1] = f end
end
check("the toc yielded its lua files", #shipped > 8, true)

local function hasCJK(s)
	local ok, found = pcall(function()
		for _, cp in utf8.codes(s) do
			if (cp >= 0x3000 and cp <= 0x303F) or (cp >= 0x4E00 and cp <= 0x9FFF)
				or (cp >= 0xFF00 and cp <= 0xFFEF) then return true end
		end
		return false
	end)
	return ok and found or false
end

-- The one sanctioned exception: the credit naming the voice actor. Her name in
-- Chinese is how she is actually known, and dropping it would make the
-- attribution worse at the single thing attribution exists to do.
--
-- ⚠ Anchored to the credit line itself, never to the file. Any OTHER Chinese
-- in README.md still fails -- a file-sized exemption is how a guard quietly
-- stops covering anything while still reporting green.
local function exempt(path, line)
	return path == "README.md" and line:find("Xia Yike", 1, true) ~= nil
end

local offenders, exempted = {}, 0
for _, f in ipairs(shipped) do
	local src = slurp(f)
	check(f .. " was readable", src ~= nil, true)
	for line in (src or ""):gmatch("[^\r\n]+") do
		if hasCJK(line) then
			if exempt(f, line) then exempted = exempted + 1
			else offenders[#offenders + 1] = f .. " | " .. line:sub(1, 70) end
		end
	end
end
check("no CJK outside the credit line", offenders[1], nil)
-- Reverse assertion: the exemption does exactly one job. If this number climbs,
-- someone widened the exemption instead of fixing whatever tripped it.
check("the exemption covers exactly one line", exempted, 1)
-- ...and the scanner must actually be able to see CJK, or every check above is
-- vacuously green. (This file lives in tools/ and never ships.)
check("the scanner can see CJK at all", hasCJK("夏一可"), true)
check("and does not fire on plain ASCII", hasCJK("Xia Yike, CC BY-ND 4.0"), false)

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
