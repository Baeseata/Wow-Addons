-- ===========================================================================
-- harness.lua  ·  enough fake WoW to run the REAL files offline.
--
-- Deliberately a stub of the client, not a mock of our own logic: Util.lua,
-- Board.lua, Announce.lua and Detector.lua are loaded verbatim and it is their
-- actual code under test. Only CreateFrame / UnitChannelInfo / friends are fake.
--
-- Run:  lua tools/test_detector.lua     (from the addon folder)
--
-- ---------------------------------------------------------------------------
-- 🔴 THE DEFAULT WORLD IS THE LIVE WORLD.
--
-- Every value this file hands the addon is SECRET unless the test says
-- otherwise, in writing, at the call site, with H.plain(...).
--
-- It used to be the other way round -- spellID, name and GUID all arrived as
-- readable literals -- and that cost three separate live failures in one
-- evening (2026-08-15), each one found only by walking the delve again. The
-- worst: equals() answered "cannot be known", `nil == true` folded that into
-- "no", and the addon went silent for a whole fight without erroring. Every
-- test was green throughout, because every test was running down a branch the
-- real fight never takes.
--
-- So the defaults point at reality. Omitting a client value gets you the live
-- path; wanting the readable one is a decision you have to write down next to
-- the reason. And a raw literal, which is neither, is refused outright -- that
-- is the exact mistake this file exists to catch, and it now costs a red line
-- instead of a dungeon run.
--
-- ⚠ Known limit, stated rather than papered over: a real secret THROWS when
-- used, and nothing here can. Lua only lets a metatable be hung on the number
-- and string types globally, which would break arithmetic everywhere. What is
-- modelled is the gate every read goes through anyway -- issecretvalue() --
-- plus the SHAPE of the damage: minted secrets are absurd values, so code that
-- skips the gate lands on an obviously wrong answer rather than a plausible
-- one. See docs/RESEARCH-live-trace.md 4 for what was actually measured.
-- ===========================================================================

local H = {}

-- Every frame ever created, so a test can find the one that registered for a
-- given event and fire at it. Detector keeps its listener private; this is how
-- we reach it without adding a test-only backdoor to production code.
H.frames = {}

-- Everything the addon has painted since the last clear: wedge tints, icon
-- desaturation, icon alpha. Reset in install() too, and declared here so a
-- frame built during install cannot outrun them.
H.vertexColors, H.desaturations, H.alphas = {}, {}, {}
function H.clearVertexColors()
	H.vertexColors, H.desaturations, H.alphas = {}, {}, {}
end

local function noop() end

-- ---------------------------------------------------------------------------
-- Secret values
--
-- Minted well outside anything real: spell ids live around 1.3M, so 7M+ can
-- only ever be one of ours. A leak is then arithmetically loud -- a channel
-- read without the gate comes out 777 seconds long, which is 222 waves, not a
-- believable 3.
-- ---------------------------------------------------------------------------
local SECRET_BASE  = 7000000
local CHANNEL_SPAN = 777000   -- ms between a defaulted channel's start and end

local secrets, minted = {}, 0

local PlainMT = {}
PlainMT.__tostring = function(p) return "H.plain(" .. tostring(p.v) .. ")" end

-- Declare one value readable, because this test is deliberately exercising the
-- path where the client does answer. Wrapper rather than a registry on purpose:
-- the permission belongs to this call site, not to the number 1288103 forever.
function H.plain(v)
	return setmetatable({ v = v }, PlainMT)
end

local function mint(kind, tag)
	minted = minted + 1
	local v
	if kind == "number" then
		v = SECRET_BASE + minted
	else
		v = ("<secret %s #%d>"):format(tag or "value", minted)
	end
	secrets[v] = true
	return v
end

function H.secretNumber(tag) return mint("number", tag) end
function H.secretString(tag) return mint("string", tag) end
function H.isSecret(v) return secrets[v] == true end

-- A secret standing in for a REAL value, for the length of one call.
--
-- Minted secrets above are deliberately absurd so that a leak is loud. That is
-- the wrong model for exactly one question: "what if the client makes THIS
-- value secret?" -- because a live secret reports as the very thing it hides,
-- so the lookup that was going to succeed still succeeds, and only using it
-- goes off. A stand-in nobody would have looked up anyway proves nothing, and
-- proves it in green (2026-08-16: the first version of the fail-closed test
-- passed for that reason, and a mutation walked straight through it).
--
-- Scoped, because the registry is keyed by value: 3508 has to go back to being
-- an ordinary number the moment this returns.
function H.whileSecret(value, fn)
	local had = secrets[value]
	secrets[value] = true
	local ok, err = pcall(fn)
	secrets[value] = had
	if not ok then error(err, 0) end
end

-- How many client values a run declared readable, and which. Printed at the
-- end: "runs on a path live never takes" was invisible before, and a number
-- nobody can see is a number nobody defends.
H.declared = {}

-- A value on its way from the client into the addon.
--
--   nil            the client would not say -- the measured live answer for
--                  every field routed through here -- so it becomes a fresh
--                  unreadable stand-in
--   H.plain(x)     the test wants the readable path and has said so
--   a minted secret passed back through
--   anything else  a raw literal, i.e. the mistake. Refused, loudly, here.
local function fromClient(field, given, kind)
	if given == nil then return mint(kind, field) end
	if getmetatable(given) == PlainMT then
		H.declared[#H.declared + 1] = field
		return given.v
	end
	if secrets[given] then return given end
	error(("%s = %s is a raw literal, and live hands this back <secret> " ..
		"(measured 2026-08-15, docs/RESEARCH-live-trace.md 4).\n" ..
		"       Leave it out to get the live path, or write H.plain(%s) and " ..
		"say in a comment why the readable one is the point of this test.")
		:format(field, tostring(given), tostring(given)), 3)
end

-- ---------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------
local FrameMT = {}
FrameMT.__index = function(self, key)
	-- Any setter/getter we did not bother to model is a no-op returning the
	-- frame, which keeps chained UI calls from exploding mid-test.
	local fn = function(_, ...) return self end
	rawset(self, key, fn)
	return fn
end

local function newFrame()
	local f = setmetatable({}, FrameMT)
	f._events, f._scripts, f._shown = {}, {}, false

	function f:RegisterEvent(e) self._events[e] = true end
	function f:UnregisterEvent(e) self._events[e] = nil end
	function f:SetScript(which, fn) self._scripts[which] = fn end
	function f:GetScript(which) return self._scripts[which] end
	function f:Show() self._shown = true end
	function f:Hide() self._shown = false end
	function f:IsShown() return self._shown end
	function f:GetWidth() return 200 end
	function f:GetHeight() return 200 end
	function f:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
	function f:CreateTexture() return newFrame() end
	function f:CreateFontString() return newFrame() end
	function f:CreateAnimationGroup() return newFrame() end
	function f:CreateAnimation() return newFrame() end
	function f:SetText(t) self._text = t end
	function f:GetText() return self._text end

	-- Recorded, not swallowed. The board deciding on a colour and the board
	-- actually painting it are two different claims, and a pure PaintPlan()
	-- test only ever proves the first one -- the seam between them would have
	-- nobody looking at it.
	function f:SetVertexColor(r, g, b, a)
		self._vertex = { r, g, b, a }
		H.vertexColors[#H.vertexColors + 1] = { r, g, b, a }
	end

	-- Same reason as SetVertexColor: what the board DECIDED about an icon and
	-- what it actually did to the texture are two claims, and only one of them
	-- is a pure function anybody can test.
	function f:SetDesaturated(on) self._desat = on; H.desaturations[#H.desaturations + 1] = on end
	function f:SetAlpha(a) self._alpha = a; H.alphas[#H.alphas + 1] = a end
	function f:GetAlpha() return self._alpha end

	H.frames[#H.frames + 1] = f
	return f
end

-- ---------------------------------------------------------------------------
-- What the client currently believes. Tests write it through the helpers
-- below; the stubs only ever read it.
-- ---------------------------------------------------------------------------
local world = { channel = nil, casting = {}, guid = {}, plainGUID = false }

-- `unit` is channelling. Every field defaults to unreadable, which is what was
-- measured: name, start, end and spellID all came back <secret> on ?.
--
-- Both ends of a defaulted channel are minted far apart on purpose. A
-- zero-length one would fall through to the round table and look correct; 777
-- seconds cannot be mistaken for anything.
function H.channelling(unit, spec)
	spec = spec or {}
	assert((spec.from == nil) == (spec.to == nil),
		"declare both ends of the channel or neither -- one alone is not a duration")

	local from, to
	if spec.from == nil then
		from = mint("number", "channel start")
		to   = from + CHANNEL_SPAN
		secrets[to] = true
	else
		from = fromClient("channel start", spec.from, "number")
		to   = fromClient("channel end",   spec.to,   "number")
	end

	world.channel = {
		unit = unit,
		name = fromClient("channel name",    spec.name, "string"),
		id   = fromClient("channel spellID", spec.id,   "number"),
		from = from,
		to   = to,
	}
	return world.channel
end

function H.notChannelling() world.channel = nil end

function H.casting(unit, name)
	world.casting[unit] = fromClient("cast name", name, "string")
end

-- Readable GUIDs, for the one test that proves identity-by-GUID works when the
-- client allows it. Off by default: in this arena it does not.
function H.plainGUIDs(on)
	world.plainGUID = on and true or false
	-- Counted like any other H.plain: it is the same decision, just a switch
	-- rather than an argument, and a tally that quietly skips it under-reports
	-- how much of the suite is off the live path.
	if world.plainGUID then H.declared[#H.declared + 1] = "UnitGUID" end
end

function H.install()
	_G.CreateFrame = function() return newFrame() end
	_G.UIParent = newFrame()
	_G.GameTooltip = newFrame()
	_G.SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
	_G.PlaySound = noop
	_G.Settings = nil
	_G.GetCursorPosition = function() return 0, 0 end
	_G.C_Map = { GetBestMapForUnit = function() return nil end }

	secrets, minted = {}, 0
	H.declared = {}
	H.vertexColors, H.desaturations, H.alphas = {}, {}, {}
	world = { channel = nil, casting = {}, guid = {}, plainGUID = false }

	-- Always installed. The old default -- no such API, therefore nothing is
	-- secret -- is the shape of the bug this file now exists to prevent.
	_G.issecretvalue = function(v) return secrets[v] == true end

	_G.UnitGUID = function(unit)
		if world.plainGUID then return "GUID-" .. tostring(unit) end
		local g = world.guid[unit]
		if not g then
			-- One per unit, and each one unreadable. Distinct because they are
			-- distinct in the room: collapsing them would hand the ?? fence a
			-- fake pass.
			g = mint("string", "guid " .. tostring(unit))
			world.guid[unit] = g
		end
		return g
	end

	_G.UnitChannelInfo = function(unit)
		local c = world.channel
		if not c or c.unit ~= unit then return nil end
		return c.name, nil, nil, c.from, c.to, nil, nil, c.id
	end

	_G.UnitCastingInfo = function(unit) return world.casting[unit] end

	-- Timers are queued, never fired on the spot. Running them immediately
	-- would make "the board stays up until the last wave lands" untestable --
	-- the delay IS the behaviour here, not an implementation detail.
	H.timers = {}
	_G.C_Timer = {
		NewTicker = function() return newFrame() end,
		After = function(seconds, fn)
			H.timers[#H.timers + 1] = { at = H.now + (seconds or 0), fn = fn }
		end,
	}
	-- A clock the tests drive by hand. Real GetTime() would make anything that
	-- measures a duration untestable offline -- and measuring durations is
	-- exactly what the cast bar depends on. Plain, because it IS plain on live:
	-- it is the only clock left once the cast's own timestamps go secret.
	H.now = 1000
	_G.GetTime = function() return H.now end

	H.printed = {}
	_G.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		H.printed[#H.printed + 1] = table.concat(parts, " ")
	end
end

-- Load the addon files in .toc order, sharing one `...` namespace exactly the
-- way the client does.
function H.load(files)
	local ns = {}
	for _, f in ipairs(files) do
		local chunk = assert(loadfile(f))
		chunk("DodoSays", ns)
	end
	return ns
end

-- Fire every timer whose moment has come. Returns how many ran.
function H.runTimers()
	local ran, keep = 0, {}
	for _, t in ipairs(H.timers) do
		if t.at <= H.now then
			ran = ran + 1
			if t.fn then pcall(t.fn) end
		else
			keep[#keep + 1] = t
		end
	end
	H.timers = keep
	return ran
end

-- The frame that registered for `event` -- i.e. Detector's private listener.
function H.listenerFor(event)
	for _, f in ipairs(H.frames) do
		if f._events and f._events[event] and f._scripts and f._scripts.OnEvent then
			return f
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Events, as the client delivers them
--
-- Named helpers rather than raw fire() calls, because the payload is client
-- data too: UNIT_SPELLCAST_START carries the spellID, and that arriving as a
-- readable 1288125 in a test is the same lie as UnitGUID returning one.
-- ---------------------------------------------------------------------------
function H.fire(event, ...)
	local f = assert(H.listenerFor(event), "nothing registered for " .. tostring(event))
	return f._scripts.OnEvent(f, event, ...)
end

-- The declared exception. encounterID was measured READABLE (3508, difficulty
-- 208) and the whole door hangs off it, so a literal here is the truth rather
-- than a shortcut. Pass H.secretNumber(...) to rehearse the day that changes --
-- the addon is supposed to fail closed, and there is a test that says so.
function H.encounterStart(id) return H.fire("ENCOUNTER_START", id) end
function H.encounterEnd(id)   return H.fire("ENCOUNTER_END", id) end

function H.channelStart(unit, spec)
	local c = H.channelling(unit, spec)
	return H.fire("UNIT_SPELLCAST_CHANNEL_START", unit,
		mint("string", "cast guid"), c.id)
end

function H.channelStop(unit)
	local c = world.channel
	local id = (c and c.unit == unit) and c.id or mint("number", "cast spellID")
	if c and c.unit == unit then H.notChannelling() end
	return H.fire("UNIT_SPELLCAST_CHANNEL_STOP", unit,
		mint("string", "cast guid"), id)
end

-- One cast starting. `spec.name` feeds UnitCastingInfo for the length of it,
-- because that is what the client does -- the name is only there to be asked
-- for while the cast is in the air.
function H.cast(unit, spec)
	spec = spec or {}
	local id = fromClient("cast spellID", spec.id, "number")
	world.casting[unit] = fromClient("cast name", spec.name, "string")
	return H.fire("UNIT_SPELLCAST_START", unit, mint("string", "cast guid"), id)
end

function H.landed(unit)
	world.casting[unit] = nil
	return H.fire("UNIT_SPELLCAST_SUCCEEDED", unit,
		mint("string", "cast guid"), mint("number", "cast spellID"))
end

return H
