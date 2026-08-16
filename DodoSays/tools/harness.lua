-- ===========================================================================
-- harness.lua  ·  enough fake WoW to run the REAL files offline.
--
-- Deliberately a stub of the client, not a mock of our own logic: Util.lua,
-- Board.lua and Detector.lua are loaded verbatim and it is their actual code
-- under test. Only CreateFrame / UnitChannelInfo / friends are fake.
--
-- Run:  lua tools/test_detector.lua     (from the addon folder)
-- ===========================================================================

local H = {}

-- Every frame ever created, so a test can find the one that registered for a
-- given event and fire at it. Detector keeps its listener private; this is how
-- we reach it without adding a test-only backdoor to production code.
H.frames = {}

local function noop() end

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

	H.frames[#H.frames + 1] = f
	return f
end

function H.install()
	_G.CreateFrame = function() return newFrame() end
	_G.UIParent = newFrame()
	_G.GameTooltip = newFrame()
	_G.SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
	_G.PlaySound = noop
	_G.Settings = nil
	_G.issecretvalue = nil          -- default: nothing is secret
	_G.UnitGUID = function(unit) return "GUID-" .. tostring(unit) end
	_G.GetCursorPosition = function() return 0, 0 end
	_G.C_Map = { GetBestMapForUnit = function() return nil end }
	_G.UnitChannelInfo = function() return nil end
	_G.UnitCastingInfo = function() return nil end
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
	-- exactly what the cast bar depends on.
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

return H
