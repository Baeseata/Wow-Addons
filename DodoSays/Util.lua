local ADDON, ns = ...

-- ===========================================================================
-- Util.lua  ·  the secret-safe layer, and nothing else.
--
-- Under 12.x a secret value is NOT detectable by `type`: it reports as the
-- number or string it stands in for, and only goes off when you *use* it.
-- Touching one throws, and a throw inside a UNIT_* handler takes the whole
-- feature down without a word.
--
-- So: every value that came from the client is proved usable before it is
-- used, and `tostring` counts as a use -- which makes debug logging the single
-- most likely place to blow up. describe() exists for exactly that.
-- ===========================================================================

ns.ADDON = ADDON

-- --------------------------------------------------------------------------
-- Is this value secret? Wrapped in pcall because a build may not ship the API
-- at all -- in which case nothing is secret and every read is plain.
--
-- DELIBERATE COPY -- do NOT fold this into the shared Dodo library.
-- DodoSays ships standalone on CurseForge, and the CF zip contains exactly one
-- folder: .github/workflows/curseforge-release.yml does `cd "$ADDON"` and packs
-- only that tree. So `Interface\AddOns\Dodo\` does not exist for anyone who
-- installs from CF, and anything reached via `_G.Dodo` is nil there. Requiring
-- the shared lib would take the addon down on every non-developer machine.
--
-- The same predicate is hand-written in four addons. They MUST all be kept in
-- the same shape -- type probe, then pcall, then normalise to a real boolean:
--     DodoSays/Util.lua       (this one)
--     DodoGuanzhu/Macro.lua
--     DodoNameplate/Guards.lua
--     DodoUnholy/Rotation.lua
-- Change one, change all four. If you find one that differs, that difference
-- is the bug -- fix it toward this shape, do not copy it outward. (No line
-- numbers on purpose: they rot. Grep `issecretvalue` to find them.)
--
-- Why each piece earns its place:
--   * type probe  -- clients that never shipped the API leave the global nil,
--                    and calling nil is a hard error, not a "false".
--   * pcall       -- `issecretvalue` itself may throw; a throw inside a UNIT_*
--                    handler takes the whole feature down without a word.
--   * `== true`   -- collapses the answer to a REAL boolean at the boundary.
--                    Note this is the opposite of equals() below, which must
--                    stay three-state; see its comment for the fight that cost.
-- --------------------------------------------------------------------------
local function isSecret(v)
	if type(issecretvalue) ~= "function" then return false end
	local ok, secret = pcall(issecretvalue, v)
	return ok and secret == true
end

-- --------------------------------------------------------------------------
-- Three-state equality: true / false / nil.
--
-- nil means "cannot be known", which is a DIFFERENT answer from false and is
-- the entire reason this function exists.
--
-- 🔴 The rule is NOT "compare with == true". That is what this comment used to
-- say, and Detector.isOurBoss followed it to the letter -- `equals(...) == true`
-- -- which folds "cannot be known" straight back into "no". On live that meant
-- every single echo was judged not-our-boss and the addon went silent for a
-- whole fight without erroring (2026-08-15).
--
-- The rule is: THREE answers need THREE branches. If the only places you have
-- to go are yes and no, you have not finished handling this function's output.
-- When it says nil, go ask something else.
-- --------------------------------------------------------------------------
local function equals(a, b)
	if isSecret(a) or isSecret(b) then return nil end
	local ok, same = pcall(function() return a == b end)
	if not ok then return nil end
	return same
end

-- --------------------------------------------------------------------------
-- The number, if we are allowed to have it; nil otherwise. Anything that has
-- to be compared, subtracted or formatted goes through here first.
-- --------------------------------------------------------------------------
local function usableNumber(v)
	if v == nil or isSecret(v) then return nil end
	if type(v) ~= "number" then return nil end
	local ok, finite = pcall(function() return v == v and v ~= math.huge end)
	if not ok or not finite then return nil end
	return v
end

-- --------------------------------------------------------------------------
-- Safe for logs. Never let a debug line be the thing that kills the addon.
-- --------------------------------------------------------------------------
local function describe(v)
	if v == nil then return "nil" end
	if isSecret(v) then return "<secret>" end
	local ok, s = pcall(tostring, v)
	if not ok then return "<unreadable>" end
	return s
end

-- --------------------------------------------------------------------------
-- Compare spell/aura names with the punctuation and the case stripped out.
--
-- "Ula'tek" carries an apostrophe, and the client may hand back a typographic
-- one where a log had a plain one. An exact match fails silently on that --
-- silently being the problem, since the fallback path then looks like a
-- mechanic change rather than a quoting difference.
-- --------------------------------------------------------------------------
local function nameKey(name)
	if name == nil or isSecret(name) then return nil end
	if type(name) ~= "string" then return nil end
	local ok, key = pcall(function()
		return (name:lower():gsub("[^%a%d]", ""))
	end)
	if not ok or key == "" then return nil end
	return key
end

-- --------------------------------------------------------------------------
-- The four quarters, named by the raid marker the player drops on that patch
-- of floor before the pull. Clockwise from Cross.
--
-- Markers and not compass points, because the identity has to survive the one
-- thing that is guaranteed to change mid-fight: which way the player is
-- facing. A marker is painted on the ground and does not rotate with the
-- camera, so "the square one" needs no mental arithmetic at the exact moment
-- there is no time for any -- whereas "north" does, every single wave.
--
-- The addon cannot read the room (no UnitPosition in here, see
-- docs/RESEARCH-snakesays-source.md 2.4), so what the wedges mean is whatever
-- the player decided on the floor. This table just has to agree with them
-- about the order, and clockwise-from-Cross is that agreement.
--
-- `angle` is degrees clockwise from up, which is how the board lays them out.
-- `marker` is Blizzard's raid target index -- the icon comes from it.
-- --------------------------------------------------------------------------
-- 🔴 The third one is the purple DIAMOND (3) and not the green triangle (4),
-- and that is not a style choice. Venomfall Deeps has a green floor, and a
-- player reported the green marker being close to invisible on it -- which is
-- the one failure this addon cannot absorb, since the marker on the ground is
-- the only thing naming a quarter. Purple, red, blue and orange are four
-- colours that survive that floor; a "tidier" all-shapes set does not.
-- The order is still clockwise from Cross; only which icon sits at 180 moved.
local QUADRANTS = {
	{ id = "cross",   marker = 7, label = "Cross",   angle =   0 },
	{ id = "square",  marker = 6, label = "Square",  angle =  90 },
	{ id = "diamond", marker = 3, label = "Diamond", angle = 180 },
	{ id = "circle",  marker = 2, label = "Circle",  angle = 270 },
}

-- Quarter ids that used to exist, mapped to what they are now. A macro sitting
-- on somebody's action bar says `/dodosays triangle` and keeps saying it after
-- the upgrade -- nothing rewrites a macro body -- so without this the tap is
-- swallowed mid-fight and the sequence is silently one short. That is the
-- expensive kind of quiet: no error, and the wrong quarter called later.
local LEGACY_QUADRANT_IDS = { triangle = "diamond" }

-- Inline icon for a font string. Blizzard ships one file per marker, which is
-- cheaper to reason about than atlas coordinates when it goes in text.
local function markerIcon(marker, size)
	size = size or 0
	return ("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:%d|t")
		:format(marker or 1, size)
end

local QUADRANT_BY_ID = {}
for i, q in ipairs(QUADRANTS) do
	q.index = i
	QUADRANT_BY_ID[q.id] = q
end

-- --------------------------------------------------------------------------
-- How loud a call is. Four states rather than a switch, because "silent" and
-- "the stock chime" are genuinely different answers: someone who turned sound
-- off wants silence, and someone who never touched the setting is leaning on
-- the chime that has been there since the first build. Collapsing those two
-- would quietly change the default behaviour for everyone already installed.
--
-- `key` on the voice rows doubles as the folder under Sounds/, and the file
-- inside is named for the quadrant id -- so a new language is one row here
-- plus four files, with no mapping table that can drift out of step with the
-- quadrants. (`voice` is what separates "plays a file" from "plays a chime";
-- nothing keys off the language itself.)
-- --------------------------------------------------------------------------
local SOUND_MODES = {
	{ key = "off",  label = "Silent",
	  tip = "No sound on calls at all." },
	{ key = "beep", label = "Chime",
	  tip = "Blizzard's raid-warning chime. This is the long-standing default." },
	{ key = "zh",   label = "Voice (Chinese)", voice = true,
	  tip = "Speaks the marker: cross, square, diamond, circle." },
	{ key = "en",   label = "Voice (English)", voice = true,
	  tip = "Speaks the marker: cross, square, diamond, circle." },
}

local SOUND_MODE_BY_KEY = {}
for _, m in ipairs(SOUND_MODES) do SOUND_MODE_BY_KEY[m.key] = m end

-- Longest round anyone can be shown, read off the wave table rather than
-- written down twice. If the fight ever grows an eighth wave, correcting
-- Detector's WAVES_BY_ROUND is enough and the board follows.
local function maxOf(byRound)
	local most = 0
	for _, waves in pairs(byRound) do
		for _, n in ipairs(waves) do
			if n > most then most = n end
		end
	end
	return most
end

-- --------------------------------------------------------------------------
-- The replay seam.
--
-- Detector emits into this during a pull; Sim emits the identical events with
-- no encounter in sight. Everything downstream (board, announcer) subscribes
-- and cannot tell which one is talking -- so rehearsing offline exercises the
-- real display path, not a mock of it.
-- --------------------------------------------------------------------------
local listeners = {}

local function subscribe(fn)
	listeners[#listeners + 1] = fn
end

local function emit(event, ...)
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn, event, ...)
		-- A broken subscriber must not take the rest of the run down with it:
		-- the whole point of this addon is the two seconds where the player is
		-- blind, and a silent board then is worse than a lua error later.
		if not ok and ns.db and ns.db.debug then
			print("|cffff6666DodoSays|r subscriber failed on " .. describe(event) .. ": " .. describe(err))
		end
	end
end

ns.Subscribe      = subscribe
ns.Emit           = emit
ns.isSecret       = isSecret
ns.equals         = equals
ns.usableNumber   = usableNumber
ns.describe       = describe
ns.nameKey        = nameKey
ns.QUADRANTS      = QUADRANTS
ns.QUADRANT_BY_ID = QUADRANT_BY_ID
ns.LEGACY_QUADRANT_IDS = LEGACY_QUADRANT_IDS
ns.markerIcon     = markerIcon
ns.SOUND_MODES       = SOUND_MODES
ns.SOUND_MODE_BY_KEY = SOUND_MODE_BY_KEY
ns.maxOf          = maxOf
