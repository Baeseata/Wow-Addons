local ADDON, ns = ...

-- ===========================================================================
-- Minimap.lua  ·  the button on the minimap ring, and the little panel it opens.
--
-- Hand-rolled rather than LibDBIcon: one button, one angle saved to disk, and
-- no library to ship or keep in step. The whole thing is under a hundred lines
-- and it cannot break in a way that is somebody else's to fix.
-- ===========================================================================

local Mini = {}
ns.Mini = Mini

-- Derived from the minimap rather than written down: addons and UI scale both
-- resize it, and a constant that is right on this machine is exactly the kind
-- of thing that puts the button in the wrong place on another one.
local function ring()
	local w = Minimap and Minimap:GetWidth() or nil
	if type(w) ~= "number" or w <= 0 then return 80 end
	return w / 2 + 10
end

-- A murloc head. Chosen for being impossible to mistake for a serious addon,
-- and for being a classic-era icon that has been in the game forever.
-- ⚠ If the button ever renders blank, this path is the first suspect --
-- the client draws nothing and says nothing when an icon is missing.
local ICON = "Interface\\Icons\\INV_Misc_Head_Murloc_01"

local button, panel

local function place(angle)
	if not button or not Minimap then return end
	local rad, r = math.rad(angle or 200), ring()
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER",
		math.cos(rad) * r, math.sin(rad) * r)
end

Mini.Place = place

-- 🔴 The scale here must be the MINIMAP's, not UIParent's.
--
-- GetCenter() answers in the frame's own coordinate space, while
-- GetCursorPosition() answers in raw screen pixels. Dividing the cursor by
-- UIParent's scale lands it in UIParent's space -- a different space whenever
-- anything has resized the minimap, which is most setups. The offset that
-- creates is not small and not stable: the first frame of a drag threw the
-- button across the screen.
local function angleFromCursor()
	if not Minimap or type(GetCursorPosition) ~= "function" then return nil end

	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	if type(mx) ~= "number" or type(px) ~= "number"
		or type(scale) ~= "number" or scale == 0 then
		return nil
	end

	local dx, dy = px / scale - mx, py / scale - my
	if dx == 0 and dy == 0 then return nil end

	-- 5.1 has math.atan2; later versions fold it into a two-argument math.atan.
	local atan2 = math.atan2 or math.atan
	return math.deg(atan2(dy, dx))
end

function Mini.Build()
	if button or not Minimap then return button end

	button = CreateFrame("Button", "DodoSaysMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")

	-- Geometry lifted verbatim from LibDBIcon: 17px at TOPLEFT(7,-6), with the
	-- icon's own baked-in border cropped off by the texcoord. Not centred, and
	-- that is the point -- the ring artwork is not centred either, so anything
	-- placed by arithmetic ends up sitting visibly high and left. Hundreds of
	-- addons use these exact numbers.
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	local ring = button:CreateTexture(nil, "OVERLAY")
	ring:SetSize(53, 53)
	ring:SetPoint("TOPLEFT")
	ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	button:SetScript("OnDragStart", function(self) self.dragging = true end)
	button:SetScript("OnDragStop", function(self) self.dragging = false end)
	button:SetScript("OnUpdate", function(self)
		if not self.dragging then return end
		local a = angleFromCursor()
		if not a then return end
		if ns.db then ns.db.minimapAngle = a end
		place(a)
	end)

	button:SetScript("OnClick", function() Mini.Toggle() end)

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("DodoSays", 1, 1, 1)
		GameTooltip:AddLine("Click for settings.", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Drag to move around the ring.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	place(ns.db and ns.db.minimapAngle or 200)
	return button
end

-- ===========================================================================
-- The panel. Everything lives here rather than half here and half in the
-- Settings window: there are five switches in total, and splitting five
-- switches across two places costs more than it saves.
--
-- Tooltips instead of a paragraph of body text. The first version had a
-- three-line blurb under a fixed-height frame -- the text wrapped past what
-- had been reserved for it and the buttons sat on top of it. Twice in one
-- evening, same mistake. Nothing here is measured any more; the height is a
-- sum of things whose sizes are set right above it.
-- ===========================================================================

local ROW = 26
local TOGGLES = {
	{ key = "__position", label = "Position the call-out",
	  tip = "Puts a sample call-out on screen so you can drag it where you want. Switches itself off when this window closes." },
	{ key = "hideHint", label = "Hide the floor-marking hint",
	  tip = "The two lines under the board telling you to mark the floor. Once you have marked it, they are just taking up room." },
	{ key = "announce", label = "Centre-screen call-outs",
	  tip = "The big marker during the echo. This is the part that keeps you alive." },
	{ key = "sound", label = "Sound on each call",
	  tip = "Fires with the call-out, for when your eyes are on the floor." },
	{ key = "locked", label = "Lock the board in place",
	  tip = "Stops the board being dragged. It still shows and still takes clicks." },
}

local function buildPanel()
	if panel then return panel end

	panel = CreateFrame("Frame", "DodoSaysPanel", UIParent)
	panel:SetSize(280, 150)
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("DIALOG")
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	panel:SetClampedToScreen(true)

	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.04, 0.04, 0.05, 0.94)

	local edge = panel:CreateTexture(nil, "BORDER")
	edge:SetPoint("TOPLEFT", -1, 1)
	edge:SetPoint("BOTTOMRIGHT", 1, -1)
	edge:SetColorTexture(0.35, 0.35, 0.40, 0.9)
	edge:SetDrawLayer("BACKGROUND", -1)

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -11)
	title:SetText("DodoSays")

	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 1, 1)
	close:SetScript("OnClick", function() Mini.Hide() end)

	panel.checks = {}
	local y = -38
	for _, t in ipairs(TOGGLES) do
		local cb = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
		cb:SetPoint("TOPLEFT", 12, y)
		cb.Text:SetText(t.label)
		cb:SetScript("OnClick", function(self)
			local on = self:GetChecked() and true or false
			if t.key == "__position" then
				ns.Announce.SetPositioning(on)
			else
				ns.db[t.key] = on
				if t.key == "hideHint" then ns.Board.ApplyHint() end
			end
		end)
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(t.label, 1, 1, 1)
			GameTooltip:AddLine(t.tip, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", function() GameTooltip:Hide() end)

		panel.checks[t.key] = cb
		y = y - ROW
	end

	local board = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	board:SetPoint("TOPLEFT", 16, y - 8)
	board:SetSize(140, 22)
	board:SetText("Show the board")
	board:SetScript("OnClick", function()
		ns.ApplyPosition()
		ns.Board.Show()
	end)

	-- Four macros, one press. They are the only way onto an action bar, and the
	-- only thing a ring addon can be pointed at -- the why is in Macros.lua. On
	-- its own row rather than beside the board button: 280px does not hold two
	-- labels this long, and crowding this panel is how both of its layout bugs
	-- started.
	local macros = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	macros:SetPoint("TOPLEFT", 16, y - 8 - ROW)
	macros:SetSize(140, 22)
	macros:SetText("Create 4 macros")
	macros:SetScript("OnClick", function()
		print(ns.Macros.Report(ns.Macros.Create()))
	end)
	macros:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Create 4 macros", 1, 1, 1)
		GameTooltip:AddLine("Dodo Cross / Square / Triangle / Circle, each carrying its own " ..
			"raid marker as the icon. Drag them from the macro window onto a bar, or point " ..
			"a ring addon such as OPie at them. Pressing this again refreshes them; it never " ..
			"makes more than four.", nil, nil, nil, true)
		GameTooltip:AddLine("The client will not allow this in combat.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	macros:SetScript("OnLeave", function() GameTooltip:Hide() end)
	panel.macros = macros

	panel:SetHeight(math.abs(y) + 8 + 22 + ROW + 14)
	panel:Hide()
	return panel
end

function Mini.Show()
	buildPanel()
	for _, t in ipairs(TOGGLES) do
		local on
		if t.key == "__position" then
			on = ns.Announce.positioning
		else
			on = ns.db and ns.db[t.key]
		end
		panel.checks[t.key]:SetChecked(on and true or false)
	end

	-- A button that cannot work has to look like one. The client refuses macro
	-- edits in combat, and "I pressed it and nothing happened" is the worst way
	-- to find that out. (Combat starting while the window is already open leaves
	-- it looking pressable -- the click still refuses and says why, which is the
	-- half that matters.)
	if panel.macros then
		panel.macros:SetEnabled(not (InCombatLockdown and InCombatLockdown()))
	end

	panel:Show()
end

-- Closing the window turns placement mode off with it. Leaving a sample
-- call-out stuck on screen because a checkbox was still ticked in a window
-- that is no longer open would be its own little bug.
function Mini.Hide()
	if panel then panel:Hide() end
	ns.Announce.SetPositioning(false)
end

function Mini.Toggle()
	if panel and panel:IsShown() then Mini.Hide() else Mini.Show() end
end
