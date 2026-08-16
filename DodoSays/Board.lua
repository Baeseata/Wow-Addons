local ADDON, ns = ...

-- ===========================================================================
-- Board.lua  ·  the four wedges the player taps, and the row that plays back.
--
-- This file knows nothing about the boss. It is handed "start recording, N
-- waves coming", it collects taps, and it is handed "light up step 3". That
-- separation is what lets /ds sim drive the exact same pixels with no encounter
-- anywhere near it -- and a board you can rehearse on out of combat is worth
-- more than one you can only ever see three times per pull.
--
-- Compass layout, not a 2x2 grid: the wedges sit N/E/S/W around a centre, so
-- the shape on screen matches the shape in the room and the minimap gives the
-- player north for free.
-- ===========================================================================

local Board = {}
ns.Board = Board

local QUADRANTS = ns.QUADRANTS

local SQUARE  = 168  -- the room: one square, split on its diagonals
local ICON_R  = 0.56 -- how far out the marker sits, as a fraction of half a side
local TRAY    = 26   -- height of the played-back sequence row
local HINT    = 40   -- fallback only; the real height is measured at build
local PAD     = 10

-- Compass positions are an implementation detail of the artwork; the player
-- only ever sees markers. Keyed by angle so the wedge files, the icon offsets
-- and the click test all read the same table.
local BY_ANGLE = {}
for _, q in ipairs(QUADRANTS) do BY_ANGLE[q.angle] = q end

local WEDGE_FILE = {
	[0]   = "Interface\\AddOns\\DodoSays\\Media\\wedge-n",
	[90]  = "Interface\\AddOns\\DodoSays\\Media\\wedge-e",
	[180] = "Interface\\AddOns\\DodoSays\\Media\\wedge-s",
	[270] = "Interface\\AddOns\\DodoSays\\Media\\wedge-w",
}

-- --------------------------------------------------------------------------
-- Which wedge does a point fall in? dx/dy are offsets from the square's
-- centre in screen coordinates, so +y is up.
--
-- The four wedges overlap as rectangles, so they cannot each be their own
-- button -- one square takes the click and this decides what was hit. Pure
-- arithmetic on purpose: it is the only part of the new board that can be
-- pinned by a test without a running client, so it is the part that carries
-- the correctness.
-- --------------------------------------------------------------------------
function Board.QuadrantAt(dx, dy)
	dx, dy = tonumber(dx) or 0, tonumber(dy) or 0
	if math.abs(dx) <= math.abs(dy) then
		return (dy >= 0 and BY_ANGLE[0] or BY_ANGLE[180]).id
	end
	return (dx >= 0 and BY_ANGLE[90] or BY_ANGLE[270]).id
end

local COLOR = {
	idle     = { 0.27, 0.28, 0.32, 0.88 },
	armed    = { 0.24, 0.26, 0.32, 0.92 },
	recorded = { 0.20, 0.62, 0.36, 0.95 },
	calling  = { 0.98, 0.62, 0.10, 1.00 },
	done     = { 0.30, 0.34, 0.40, 0.85 },
	edge     = { 0.00, 0.00, 0.00, 0.55 },
}

local frame, wedges, tray, headline, trayCells, hitbox, hintText
local hintHeight = 0

-- The hint can be switched off once the floor is marked -- it is instructions,
-- and instructions stop being useful the moment they have been followed. The
-- panel shrinks with it rather than leaving a gap where it used to be.
function Board.ApplyHint()
	if not frame then return end
	local show = not (ns.db and ns.db.hideHint)
	local h = show and hintHeight or 0

	hintText:SetShown(show)
	frame:SetHeight(SQUARE + PAD * 2 + TRAY + h + 22)
	tray:ClearAllPoints()
	tray:SetPoint("BOTTOM", frame, "BOTTOM", 0, PAD * 0.6 + h)
end

-- Forward-declared so build() can hand it to OnUpdate before it exists. The
-- body needs `sequence` and `phase`, which are declared BELOW build() -- naming
-- them inside build() would capture the globals (nil) instead of these locals.
local pulseTick

-- --------------------------------------------------------------------------
-- Flat coloured square with a hairline edge. Cheap, readable at a glance, and
-- it does not depend on any media file shipping with the package.
-- --------------------------------------------------------------------------
local function paint(tex, c)
	tex:SetColorTexture(c[1], c[2], c[3], c[4])
end

-- Same colours, but for a texture that already has artwork in it: the wedge
-- masks are white, so the tint IS the colour.
local function tint(tex, c)
	tex:SetVertexColor(c[1], c[2], c[3], c[4])
end

-- Blizzard's raid-target sheet is 4 across, 2 down, quarter-sized cells.
-- Computed here rather than calling SetRaidTargetIconTexture so this file
-- depends on texture methods only -- which is what lets the offline harness
-- run it without stubbing a global.
local function setMarker(tex, marker)
	tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	local i = (marker or 1) - 1
	local x, y = i % 4, math.floor(i / 4)
	tex:SetTexCoord(x * 0.25, (x + 1) * 0.25, y * 0.25, (y + 1) * 0.25)
end

-- Which wedge is the cursor over right now? Shared by the click handler and
-- the hover highlight so the two can never disagree about where the mouse is.
local function cursorQuadrant()
	if not hitbox or type(GetCursorPosition) ~= "function" then return nil end
	local x, y = GetCursorPosition()
	local scale = hitbox:GetEffectiveScale()
	if type(x) ~= "number" or type(scale) ~= "number" or scale == 0 then return nil end
	local cx = (hitbox:GetLeft() or 0) + hitbox:GetWidth() / 2
	local cy = (hitbox:GetBottom() or 0) + hitbox:GetHeight() / 2
	return Board.QuadrantAt(x / scale - cx, y / scale - cy)
end

local function makeSwatch(parent, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)

	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	paint(b.bg, COLOR.idle)

	b.edge = b:CreateTexture(nil, "BORDER")
	b.edge:SetPoint("TOPLEFT", -1, 1)
	b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
	paint(b.edge, COLOR.edge)
	b.edge:SetDrawLayer("BACKGROUND", -1)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("CENTER")
	b.icon:SetSize(size * 0.64, size * 0.64)
	b.icon:Hide()

	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	b.text:SetPoint("CENTER")

	b.order = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.order:SetPoint("BOTTOMRIGHT", -3, 3)

	return b
end

-- --------------------------------------------------------------------------
-- Build once, on demand. Nothing here runs at load: an addon that draws frames
-- before the player has ever met the boss is an addon that costs everyone
-- memory for nothing.
-- --------------------------------------------------------------------------
local function build()
	if frame then return frame end

	local span = SQUARE

	frame = CreateFrame("Frame", "DodoSaysBoard", UIParent)
	frame:SetSize(span + PAD * 2, span + PAD * 2 + TRAY + HINT + 22)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, -80)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetClampedToScreen(true)
	frame:SetScript("OnDragStart", function(self)
		if not (ns.db and ns.db.locked) then self:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if ns.SavePosition then ns.SavePosition(self) end
	end)

	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetAllPoints()
	frame.bg:SetColorTexture(0, 0, 0, 0.30)

	headline = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	headline:SetPoint("TOP", frame, "TOP", 0, -6)

	-- One square button under everything. The four wedges are alpha masks that
	-- overlap as rectangles, so they cannot each own their clicks -- this takes
	-- the click and QuadrantAt() decides which triangle was actually hit.
	hitbox = CreateFrame("Button", nil, frame)
	hitbox:SetSize(span, span)
	hitbox:SetPoint("TOP", headline, "BOTTOM", 0, -4)
	hitbox:RegisterForClicks("LeftButtonUp")
	hitbox:SetScript("OnClick", function()
		local id = cursorQuadrant()
		if not id then return end
		-- Refused taps get a blink rather than silence. The board stands there
		-- all fight; pressing it between rounds is a reasonable thing to try,
		-- and "nothing happened at all" reads as broken rather than as "not yet".
		if not Board.Tap(id) then Board.Nudge(id) end
	end)

	local half = span / 2

	wedges = {}
	for _, q in ipairs(QUADRANTS) do
		local rad = math.rad(q.angle)
		local w = {}

		w.tex = hitbox:CreateTexture(nil, "ARTWORK")
		w.tex:SetAllPoints(hitbox)
		w.tex:SetTexture(WEDGE_FILE[q.angle])
		w.tex:SetDrawLayer("ARTWORK", 0)

		-- Pulsed white wash for the quarter being called. Above the wedge but
		-- below the marker, so it lights the ground rather than washing out
		-- the one icon the player is trying to read.
		w.flash = hitbox:CreateTexture(nil, "ARTWORK")
		w.flash:SetAllPoints(hitbox)
		w.flash:SetTexture(WEDGE_FILE[q.angle])
		w.flash:SetVertexColor(1, 1, 1, 1)
		w.flash:SetDrawLayer("ARTWORK", 1)
		w.flash:SetAlpha(0)
		w.flash:Hide()

		w.icon = hitbox:CreateTexture(nil, "OVERLAY")
		w.icon:SetSize(30, 30)
		w.icon:SetPoint("CENTER", hitbox, "CENTER",
			math.sin(rad) * half * ICON_R, math.cos(rad) * half * ICON_R)
		setMarker(w.icon, q.marker)

		w.order = hitbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		w.order:SetPoint("TOP", w.icon, "BOTTOM", 0, -1)

		wedges[q.id] = w
	end

	frame:SetScript("OnUpdate", function(_, elapsed)
		if pulseTick then pulseTick(elapsed) end
	end)

	-- The board is only useful if the floor agrees with it. Which quarter gets
	-- the cross does not matter -- only that the ground and this picture are
	-- the same way round.
	hintText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hintText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 5)
	hintText:SetWidth(span)
	hintText:SetJustifyH("CENTER")
	hintText:SetText("Mark the floor to match.\nCross toward the boss, then clockwise.")

	-- Measured, not assumed. The first version reserved a fixed 26px for two
	-- lines; the text wrapped to four at this width and climbed straight into
	-- the tray, which then drew a grey cell across the middle of it.
	local measured = hintText.GetStringHeight and hintText:GetStringHeight() or nil
	hintHeight = (type(measured) == "number" and measured > 4)
		and math.ceil(measured) + 8 or HINT

	tray = CreateFrame("Frame", nil, frame)
	tray:SetSize(span, TRAY)
	trayCells = {}

	Board.ApplyHint()

	frame:Hide()
	return frame
end

Board.Build = build

-- The run being recorded or replayed. `expected` is provisional on purpose:
-- the wave count is a guess from the round number until the channel's measured
-- length says otherwise, so the tray has to be able to grow and shrink.
local sequence, expected, phase, callIndex = {}, 0, "idle", 0

local function layoutTray()
	local n = math.max(expected, #sequence, 1)
	local cell = math.min(22, math.floor(SQUARE / n) - 3)

	for i = 1, n do
		local c = trayCells[i]
		if not c then
			c = makeSwatch(tray, cell)
			c.order:Hide()
			c:EnableMouse(false)
			trayCells[i] = c
		end
		c:SetSize(cell, cell)
		c._cell = cell   -- refresh() sizes the icon from this; it has no other
		                 -- way to know, and GetWidth() would be a lie under test
		c:ClearAllPoints()
		c:SetPoint("LEFT", tray, "LEFT",
			(tray:GetWidth() - (cell + 3) * n + 3) / 2 + (i - 1) * (cell + 3), 0)
		c:Show()
	end
	for i = n + 1, #trayCells do trayCells[i]:Hide() end
end

-- --------------------------------------------------------------------------
-- Repaint everything from (sequence, phase, callIndex). One function, called
-- after every state change, so there is no way for the wedges and the tray to
-- disagree about what step we are on.
-- --------------------------------------------------------------------------
local function refresh()
	if not frame then return end

	local live = (phase == "calling") and sequence[callIndex] or nil

	-- Tappable ONLY while he is preaching. Outside that the wedges are muted
	-- and take no clicks at all -- not merely ignored, actually dead to the
	-- mouse. A control that looks live and does nothing reads as broken; a
	-- greyed-out one reads as "not now", which is the truth.
	local tappable = (phase == "showing")
	-- The mouse stays enabled even when taps are refused. The board stands
	-- there for the whole fight, so it has to feel alive -- hover lights the
	-- wedge, a press blinks it. Board.Tap() is the real gate, not the cursor.
	hitbox:EnableMouse(true)

	for _, q in ipairs(QUADRANTS) do
		local w = wedges[q.id]
		-- Lit = you may tap it, OR it is the one to stand in right now. Two
		-- different reasons for the same brightness, and that is fine: both
		-- mean "this one matters this second".
		local lit = tappable or (live == q.id)
		w.icon:SetDesaturated(not lit)
		-- 0.30 was tuned back when the board only existed during a round. It
		-- now stands there the whole time you are in the delve, where it has to
		-- stay legible enough to aim at and to check the floor against.
		w.icon:SetAlpha(lit and 1 or 0.62)

		local hits = {}
		for i, id in ipairs(sequence) do
			if id == q.id then hits[#hits + 1] = i end
		end

		if live == q.id then
			tint(w.tex, COLOR.calling)
		elseif phase == "showing" and #hits > 0 then
			tint(w.tex, COLOR.recorded)
		elseif phase == "idle" then
			tint(w.tex, COLOR.idle)
		elseif phase == "calling" or phase == "done" then
			tint(w.tex, COLOR.done)
		else
			tint(w.tex, COLOR.armed)
		end

		w.order:SetText(#hits > 0 and table.concat(hits, ",") or "")
	end

	layoutTray()
	for i, c in ipairs(trayCells) do
		if c:IsShown() then
			local id = sequence[i]
			local q = id and ns.QUADRANT_BY_ID[id] or nil
			if q then
				setMarker(c.icon, q.marker)
				local s = math.max((c._cell or 16) - 3, 8)
				c.icon:SetSize(s, s)
				c.icon:Show()
			else
				c.icon:Hide()
			end
			if phase == "calling" and i == callIndex then
				paint(c.bg, COLOR.calling)
			elseif id then
				paint(c.bg, phase == "showing" and COLOR.recorded or COLOR.done)
			else
				paint(c.bg, COLOR.armed)
			end
		end
	end

	if phase == "showing" then
		headline:SetText(("Tap the safe quarter  %d / %d"):format(#sequence, expected))
	elseif phase == "calling" then
		headline:SetText(("GO  %d / %d"):format(callIndex, #sequence))
	elseif phase == "done" then
		headline:SetText("Round complete")
	else
		headline:SetText("DodoSays")
	end
end

-- --------------------------------------------------------------------------
-- Pulse the quarter currently being called.
--
-- Hand-rolled on OnUpdate rather than an AnimationGroup: it is four lines of
-- arithmetic, it runs offline under the test harness, and it has no opinion
-- about what happens when its target is hidden mid-play. The wedges cannot be
-- clicked here -- but they are still the clearest picture of the room, so they
-- go on saying where to stand.
-- --------------------------------------------------------------------------
local pulse, nudgeId, nudgeLeft = 0, nil, 0
local NUDGE_TIME = 0.35

-- A refused press. Not an error -- just "not this second".
function Board.Nudge(id)
	if not ns.QUADRANT_BY_ID[id] then return end
	nudgeId, nudgeLeft = id, NUDGE_TIME
end

pulseTick = function(elapsed)
	elapsed = elapsed or 0
	pulse = pulse + elapsed

	if nudgeLeft > 0 then
		nudgeLeft = nudgeLeft - elapsed
		if nudgeLeft <= 0 then nudgeId, nudgeLeft = nil, 0 end
	end

	-- No hover highlight. The first version lit a wedge from the cursor's angle
	-- alone, which is true no matter where on the screen the mouse actually is
	-- -- so a quarter glowed while the pointer sat somewhere else entirely.
	-- Clicks are feedback enough, and they cannot be wrong about their target.
	local liveId = (phase == "calling") and sequence[callIndex] or nil
	local wave = 0.10 + 0.38 * (0.5 + 0.5 * math.sin(pulse * 7.5))

	for _, q in ipairs(QUADRANTS) do
		local f = wedges[q.id].flash
		local alpha = 0

		if q.id == liveId then
			alpha = wave                                   -- stand here NOW
		elseif q.id == nudgeId then
			alpha = 0.45 * (nudgeLeft / NUDGE_TIME)        -- you pressed it
		end

		if alpha > 0 then
			f:SetAlpha(alpha)
			f:Show()
		else
			f:Hide()
		end
	end
end

-- --------------------------------------------------------------------------
-- Clear and get out of the way, `seconds` from now.
--
-- One token, so a round starting while a clear is pending simply wins: a stale
-- timer firing into a live recording would wipe the board mid-round, and that
-- is a far worse bug than the one this function exists to fix.
-- --------------------------------------------------------------------------
local clearToken = 0
local persistent = false

-- Inside the delve the board stays on screen between rounds: somewhere to rest
-- the mouse, and somewhere to drag into place BEFORE a pull instead of during
-- one. Outside, it packs itself away.
function Board.SetPersistent(on)
	persistent = on and true or false
	if persistent then Board.Show() end
end

function Board.IsPersistent() return persistent end

local function scheduleClear(seconds)
	clearToken = clearToken + 1
	local mine = clearToken
	if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
	C_Timer.After(seconds, function()
		if mine ~= clearToken then return end
		Board.Reset()
		if not persistent then Board.Hide() end
	end)
end

-- ===========================================================================
-- Public surface. Detector drives this during a pull; Sim drives the very same
-- calls offline. Nothing below can tell the two apart, which is the point.
-- ===========================================================================

function Board.Show() build(); frame:Show(); refresh() end
function Board.Hide() if frame then frame:Hide() end end
function Board.IsShown() return frame and frame:IsShown() end
function Board.Sequence() return sequence end
function Board.Phase() return phase end

function Board.Reset()
	sequence, expected, phase, callIndex = {}, 0, "idle", 0
	if frame then refresh() end
end

-- A round has started. `waves` is the best guess available right now.
function Board.BeginRound(waves)
	clearToken = clearToken + 1   -- outrun any clear still pending from last round
	sequence, callIndex = {}, 0
	expected = tonumber(waves) or 0
	phase = "showing"
	Board.Show()
end

-- The measured channel disagreed with the guess. Cheap on purpose: a wrong
-- seed costs a redraw, not a run.
function Board.SetExpected(waves)
	expected = tonumber(waves) or expected
	refresh()
end

-- The player named a safe quarter. Extra taps past the expected count are
-- still accepted -- the count is provisional and being right about the room
-- matters more than being right about the guess.
function Board.Tap(id)
	if phase ~= "showing" then return false end
	if not ns.QUADRANT_BY_ID[id] then return false end
	sequence[#sequence + 1] = id
	refresh()

	-- Second-to-last tap means the final sermon wave is landing right now, and
	-- the echo starts the instant the channel stops -- measured at the same
	-- hundredth of a second. So this is the last chance to say where it begins
	-- while there is still time to be moving there.
	--
	-- Driven off the taps rather than a clock: the player IS the clock here,
	-- and the sermon half hands out no per-wave event to sync against anyway.
	if #sequence >= math.max(expected - 1, 1) then
		ns.Emit("preview", sequence[1])
	end
	return true
end

function Board.Undo()
	if phase ~= "showing" or #sequence == 0 then return false end
	sequence[#sequence] = nil
	refresh()
	return true
end

-- Preaching stopped. Whatever is on the board is the run now.
function Board.LockSequence()
	phase = (#sequence > 0) and "calling" or "done"
	callIndex = 0
	refresh()
	return #sequence
end

-- One wave is being called. Returns the quarter so Announce can say it.
function Board.Call(step)
	if phase ~= "calling" then return nil end
	callIndex = tonumber(step) or (callIndex + 1)
	refresh()
	return sequence[callIndex]
end

-- `hold` = how long to stay up before clearing off the screen.
--
-- It is NOT zero, and that is the whole subtlety: "finish" fires on the LAST
-- wave's START, and that wave still has its entire cast to run. Clearing now
-- would blank the board at the exact moment the player is still running to the
-- last quarter. Detector passes cast length plus a breath.
function Board.Finish(hold)
	phase = "done"
	callIndex = 0
	refresh()
	scheduleClear(tonumber(hold) or 1.5)
end

-- Subscribed here rather than wired from the entry point so that the board
-- reacts to a replay whether it came from a real pull or from /ds sim, with
-- nothing in between deciding which is allowed.
ns.Subscribe(function(event, a)
	if     event == "round"    then Board.BeginRound(a)
	elseif event == "expected" then Board.SetExpected(a)
	elseif event == "lock"     then Board.LockSequence()
	elseif event == "call"     then Board.Call(a)
	elseif event == "finish"   then Board.Finish(a)
	elseif event == "reset"    then Board.Reset()
	end
end)
