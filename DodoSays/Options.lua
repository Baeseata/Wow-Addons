local ADDON, ns = ...

-- ===========================================================================
-- Options.lua  ·  four switches and a reset. Deliberately small.
--
-- Everything worth configuring here is about how loud the addon is, because
-- the one thing it does is unconditional: during the calling half you need to
-- know where to stand. There is no "off" for that short of disabling it.
-- ===========================================================================

ns.DEFAULTS = {
	locked   = false,
	announce = true,
	sound    = true,
	debug    = false,
	hideHint = false, -- the two lines under the board about marking the floor
	point    = nil,   -- { anchor, x, y }  board
	scale    = 1.0,
	announcePoint = nil,   -- { anchor, x, y }  centre-screen call-out
	minimapAngle  = 200,   -- degrees around the minimap ring
}

local SWITCHES = {
	{ key = "announce", label = "Centre-screen call-outs",
	  tip = "The big word during the calling half. This is the part that keeps you alive." },
	{ key = "sound",    label = "Play a sound on each call",
	  tip = "Fires with the call-out. Useful when your eyes are on the floor, not the HUD." },
	{ key = "locked",   label = "Lock the board in place",
	  tip = "Stops it being dragged. The board still shows and still takes clicks." },
	{ key = "debug",    label = "Debug trace to chat",
	  tip = "Prints how each round and call was identified (name / id / shape / place). Noisy." },
}

local built

function ns.BuildOptions()
	if built then return built end

	local panel = CreateFrame("Frame")
	panel.name = "DodoSays"

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("DodoSays")

	local blurb = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	blurb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	blurb:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
	blurb:SetJustifyH("LEFT")
	blurb:SetText("Azta'rec memory game. Tap the safe quarter while he preaches; " ..
		"it calls them back while he echoes.  |cffffd100/ds|r for commands.")

	local anchor = blurb
	for _, s in ipairs(SWITCHES) do
		local cb = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
		cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
		cb.Text:SetText(s.label)
		cb:SetChecked(ns.db[s.key] and true or false)
		cb:SetScript("OnClick", function(self)
			ns.db[s.key] = self:GetChecked() and true or false
		end)
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(s.label, 1, 1, 1)
			GameTooltip:AddLine(s.tip, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
		anchor = cb
	end

	local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	reset:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -18)
	reset:SetSize(150, 22)
	reset:SetText("Reset board position")
	reset:SetScript("OnClick", function()
		ns.db.point = nil
		if ns.ApplyPosition then ns.ApplyPosition() end
	end)

	if Settings and Settings.RegisterCanvasLayoutCategory then
		-- ⚠ Do NOT assign cat.ID. Blizzard hands out a numeric id and
		-- OpenSettingsPanel takes an integer; overwriting it with the addon's
		-- name made GetID() return a string and every open threw.
		local cat = Settings.RegisterCanvasLayoutCategory(panel, "DodoSays")
		Settings.RegisterAddOnCategory(cat)
		ns.settingsCategory = cat
	end

	built = panel
	return panel
end
