local ADDON, ns = ...

-- ===========================================================================
-- Announce.lua  ·  the half-second where the player is blind.
--
-- During the calling half there is no telegraph on the floor, so this is the
-- only thing standing between the player and a faceful of venom. It is
-- deliberately loud and deliberately dumb: one word, centre screen, plus a
-- sound. No timers, no prediction -- it speaks when the seam says a wave is
-- being called and not a moment before.
-- ===========================================================================

local Announce = {}
ns.Announce = Announce

local ARROW = "|TInterface\\CHATFRAME\\ChatFrameExpandArrow:22|t"

-- "Go here, then there." Icons only, no words: the marker is what the player
-- painted on the floor, so it is recognised rather than read, and during the
-- calling half there is no time to read anything.
--
-- The next one is drawn at 60% so the two can never be confused at a glance --
-- size alone says which is now and which is soon, with no label to parse.
-- On the last wave there is no next, and the arrow goes away with it: an arrow
-- pointing at nothing would read as "keep going" at the one moment the answer
-- is "you are done".
local function spoken(id, nextId)
	local q = ns.QUADRANT_BY_ID[id]
	if not q then return tostring(id or "?") end

	local out = ns.markerIcon(q.marker, 40)
	local nq = nextId and ns.QUADRANT_BY_ID[nextId] or nil
	if nq then
		out = out .. "  " .. ARROW .. "  " .. ns.markerIcon(nq.marker, 24)
	end
	return out
end

local holder, label, fade, fadeAlpha, bar

local function build()
	if holder then return holder end

	holder = CreateFrame("Frame", "DodoSaysAnnounce", UIParent)
	holder:SetSize(400, 80)
	holder:SetPoint("CENTER", UIParent, "CENTER", 0, 170)
	holder:SetFrameStrata("HIGH")
	holder:SetMovable(true)
	holder:SetClampedToScreen(true)
	holder:RegisterForDrag("LeftButton")
	-- Mouse OFF by default: this thing sits over the middle of the screen
	-- during a fight and must never eat a click meant for the world behind it.
	-- It is only enabled while the player is deliberately placing it.
	holder:EnableMouse(false)
	holder:SetScript("OnDragStart", function(self)
		if Announce.positioning then self:StartMoving() end
	end)
	holder:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local anchor, _, _, x, y = self:GetPoint()
		if ns.db then ns.db.announcePoint = { anchor = anchor, x = x, y = y } end
	end)
	holder:Hide()

	label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	label:SetPoint("CENTER")
	label:SetTextColor(1, 0.82, 0.10)

	-- The bar is the wave's own clock: full when the cast starts, empty when it
	-- lands. Measured on ? at 3.00s dead, but the number is handed in rather
	-- than baked, because Detector re-measures it every wave and ?? is unknown.
	bar = CreateFrame("StatusBar", nil, holder)
	bar:SetSize(300, 12)
	bar:SetPoint("TOP", label, "BOTTOM", 0, -8)
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	bar:SetStatusBarColor(0.98, 0.55, 0.05)
	bar:SetMinMaxValues(0, 1)
	bar:Hide()

	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetPoint("TOPLEFT", -1, 1)
	bar.bg:SetPoint("BOTTOMRIGHT", 1, -1)
	bar.bg:SetColorTexture(0, 0, 0, 0.65)

	fade = holder:CreateAnimationGroup()
	fadeAlpha = fade:CreateAnimation("Alpha")
	fadeAlpha:SetFromAlpha(1)
	fadeAlpha:SetToAlpha(0)
	fadeAlpha:SetDuration(0.45)
	fadeAlpha:SetStartDelay(0.6)
	fade:SetScript("OnFinished", function() holder:Hide(); bar:Hide() end)

	return holder
end

-- --------------------------------------------------------------------------
-- Run the bar down over `seconds`. Plain arithmetic on GetTime() -- the cast's
-- own timestamps are secret and cannot be subtracted, which is precisely why
-- Detector measures the length instead of reading it.
-- --------------------------------------------------------------------------
local function runBar(seconds)
	-- No bar means build() has not run, so there is no countdown to draw.
	--
	-- ⚠ On a live client this cannot currently happen: ADDON_LOADED calls
	-- Announce.ApplyPosition() unconditionally and that builds the frame before
	-- any fight starts. The guard is here because of what it costs when that
	-- stops being true -- subscribers run inside a pcall that only reports in
	-- debug mode, so indexing nil here would die silently AND take the rest of
	-- the same handler with it. Cheap insurance against a future reshuffle of
	-- the load path, not a fix for a bug anyone has seen.
	if not bar then return end
	if not seconds or seconds <= 0 then
		bar:Hide()
		return
	end
	local ok, now = pcall(GetTime)
	if not ok then bar:Hide(); return end

	local ends, span = now + seconds, seconds
	bar:SetValue(1)
	bar:Show()
	bar:SetScript("OnUpdate", function(self)
		local ok2, t = pcall(GetTime)
		if not ok2 then self:SetScript("OnUpdate", nil); return end
		local left = ends - t
		if left <= 0 then
			self:SetValue(0)
			self:SetScript("OnUpdate", nil)
			return
		end
		self:SetValue(left / span)
	end)
end

-- --------------------------------------------------------------------------
-- Say one thing, now. Re-entrant on purpose: waves land about three seconds
-- apart, and a call that arrives while the last one is still fading must
-- replace it instantly rather than queue behind it.
-- --------------------------------------------------------------------------
-- `hold` is how long to stay fully visible before fading. For a wave call it
-- is the cast length, so the text is still on screen when the venom lands --
-- the default 0.6s would have it gone a second and a half early.
-- `alpha` dims the whole thing, icons included. Text colour cannot do that
-- job: inline |T..|t textures ignore SetTextColor entirely, so opacity is the
-- only channel that reaches the markers.
function Announce.Flash(text, r, g, b, hold, alpha)
	if ns.db and ns.db.announce == false then return end
	build()
	fade:Stop()
	label:SetText(text or "")
	label:SetTextColor(r or 1, g or 0.82, b or 0.10)
	alpha = alpha or 1
	fadeAlpha:SetFromAlpha(alpha)
	fadeAlpha:SetStartDelay(hold or 0.6)
	holder:SetAlpha(alpha)
	holder:Show()
	fade:Play()
end

-- --------------------------------------------------------------------------
-- Sound for one call. `id` is the quadrant being called, and in the voice
-- modes the file name IS that id -- so the sound cannot disagree with the icon
-- on screen unless someone renames a file.
--
-- The kit is looked up in here rather than passed in: `SOUNDKIT.FOO` at the
-- call site indexes SOUNDKIT before this function runs, so a nil SOUNDKIT
-- would blow up a beat before the guard that exists to catch it.
--
-- Everything is type-checked and pcall'd because this runs mid-pull. A missing
-- file, a renamed API or a stripped-down client must cost the player a sound
-- and nothing else -- the call-out itself is what keeps them alive.
-- --------------------------------------------------------------------------
local VOICE_ROOT = "Interface\\AddOns\\DodoSays\\Sounds\\"

local function playCall(id)
	local mode = ns.db and ns.db.sound
	local spec = mode and ns.SOUND_MODE_BY_KEY[mode]
	-- Unknown mode = silence, and that covers the pre-0.12 boolean if it ever
	-- reaches here unmigrated. Silent is the safe way to be wrong: a wrong
	-- marker spoken confidently is worse than no marker at all.
	if not spec or mode == "off" then return end

	if not spec.voice then
		if type(PlaySound) ~= "function" or not SOUNDKIT then return end
		pcall(PlaySound, SOUNDKIT.UI_RAID_BOSS_WHISPER_WARNING, "Master")
		return
	end

	local q = id and ns.QUADRANT_BY_ID[id]
	if not q or type(PlaySoundFile) ~= "function" then return end
	pcall(PlaySoundFile, VOICE_ROOT .. mode .. "\\" .. q.id .. ".ogg", "Master")
end

-- ⛔ The heads-up is deliberately SILENT, and 0.12 shipped a version that was
-- not. Two things went wrong the moment it had a voice (measured in a live
-- rehearsal, invisible in every test):
--
--   * It fires while the player is still tapping quarters, so a spoken
--     "cross" lands on top of them pressing diamond -- it reads as feedback
--     on the tap they just made, naming a different quarter.
--   * Board.lua emits it on `>= expected - 1`, so the last two taps each
--     trigger one. Identical Flash content made that invisible on screen;
--     sound is what exposed it.
--
-- The deeper reason it should never have had one: the preview happens while
-- the player's eyes are ON the board, placing taps -- the dimmed arrow says it
-- fine. Speech earns its place in the echo half, when their eyes are on the
-- floor and the bar is running. One sound, one meaning: "stand here now".

-- The heads-up shown while the last sermon wave is still landing: an arrow
-- into where the echo will start. No cast bar, because nothing is being cast
-- yet, and dimmed, because "go here next" must not be mistaken for "go here".
local function preview(id)
	local q = ns.QUADRANT_BY_ID[id]
	if not q then return "" end
	return ARROW .. "  " .. ns.markerIcon(q.marker, 40)
end

Announce.Spoken  = spoken
Announce.Preview = preview

function Announce.ApplyPosition()
	build()
	local p = ns.db and ns.db.announcePoint
	if p and p.anchor then
		holder:ClearAllPoints()
		holder:SetPoint(p.anchor, UIParent, p.anchor, p.x or 0, p.y or 0)
	end
end

-- --------------------------------------------------------------------------
-- Placement mode: hold a sample call-out on screen so it can be dragged.
--
-- A sample rather than a special "drag me" box, because what matters is where
-- the ICONS land -- an empty placeholder of a different size would be placed
-- correctly and still be wrong.
-- --------------------------------------------------------------------------
function Announce.SetPositioning(on)
	build()
	Announce.positioning = on and true or false
	Announce.ApplyPosition()
	holder:EnableMouse(Announce.positioning)

	if Announce.positioning then
		fade:Stop()
		label:SetText(spoken("cross", "square"))
		label:SetTextColor(1, 0.82, 0.10)
		holder:SetAlpha(1)
		holder:Show()
		bar:SetScript("OnUpdate", nil)
		bar:SetValue(0.62)
		bar:Show()
	else
		bar:SetScript("OnUpdate", nil)
		bar:Hide()
		fade:Stop()
		holder:Hide()
	end
end

ns.Subscribe(function(event, a, b, c)
	if event == "call" then
		local step, castLength = tonumber(a) or 0, c
		-- Read straight off the board rather than threaded through the event:
		-- Detector and Sim both drive that same sequence, so this works
		-- identically in a pull and in a rehearsal.
		local nextId = ns.Board.Sequence()[step + 1]
		-- Sound first, deliberately. It is the one channel that still works
		-- when the player's eyes are on the floor, and putting it ahead of the
		-- drawing means no amount of frame trouble downstream can swallow it --
		-- which is exactly what used to happen. Structure, not vigilance.
		playCall(b)
		Announce.Flash(spoken(b, nextId), nil, nil, nil, castLength)
		runBar(castLength)

	elseif event == "preview" then
		-- Held for a long time on purpose: it must survive until the echo
		-- actually starts, and the very first call replaces it anyway.
		Announce.Flash(preview(a), nil, nil, nil, 30, 0.55)

	elseif event == "lock" then
		local n = tonumber(a) or 0
		if n > 0 then
			Announce.Flash(("GET READY  (%d)"):format(n), 0.55, 0.85, 1)
		else
			-- Nothing was tapped. Saying so beats a board that just sits there:
			-- the player needs to know they are on their own for this round.
			Announce.Flash("NOTHING RECORDED", 1, 0.35, 0.35)
		end

	-- No "finish" branch on purpose. Detector emits it on the LAST wave's
	-- START -- that wave still has a full cast to run, so anything done here
	-- (hiding, or worse, freezing the bar at full) blanks the display at the
	-- exact moment it matters most. Let the bar finish on its own clock.

	elseif event == "reset" then
		if bar then bar:SetScript("OnUpdate", nil); bar:Hide() end
		if holder then fade:Stop(); holder:Hide() end
	end
end)
