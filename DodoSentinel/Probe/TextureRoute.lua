local _, ns = ...

-- P0 probe: hand an opaque chat payload to C_StringUtil.WrapString, then let
-- Texture:SetTexture perform the only "does this coordinate exist?" lookup.
-- Nothing in this file compares, indexes with, concatenates, or branches on
-- the payload.  Keep the texture slots preallocated: a texture that has seen a
-- secret value must never enter a reusable object pool.

local TextureRoute = {}
ns.TextureRoute = TextureRoute

local GROUP_COUNT = 4
local POSITION_COUNT = 5
local MAX_LAYERS = 20
local CELL_WIDTH = 60
local CELL_HEIGHT = 44
local GRID_WIDTH = POSITION_COUNT * CELL_WIDTH
local GRID_HEIGHT = GROUP_COUNT * CELL_HEIGHT
local TEXTURE_PREFIX = "Interface\\AddOns\\DodoSentinel\\Probe\\Media\\hl\\"
local ASSET_U_MAX = 125 / 128

local arrivalCount = 0
local layers = {}

local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
frame:SetSize(GRID_WIDTH + 32, GRID_HEIGHT + 78)
frame:SetPoint("CENTER", UIParent, "CENTER", 290, 45)
frame:SetFrameStrata("DIALOG")
frame:SetBackdrop({
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Buttons\\WHITE8X8",
	edgeSize = 1,
})
frame:SetBackdropColor(0.025, 0.03, 0.04, 0.94)
frame:SetBackdropBorderColor(0.28, 0.34, 0.42, 1)
frame:Hide()

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -12)
title:SetText("DodoSentinel · TextureRoute")

local counter = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
counter:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -14)
counter:SetFormattedText("到达：%d", arrivalCount)

local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
hint:SetText("有效路径只亮对应格；无效路径必须完全不显示")

local grid = CreateFrame("Frame", nil, frame)
grid:SetSize(GRID_WIDTH, GRID_HEIGHT)
grid:SetPoint("BOTTOM", frame, "BOTTOM", 0, 16)
grid:SetClipsChildren(true)

for group = 1, GROUP_COUNT do
	for position = 1, POSITION_COUNT do
		local cell = CreateFrame("Frame", nil, grid)
		cell:SetSize(CELL_WIDTH, CELL_HEIGHT)
		cell:SetPoint(
			"TOPLEFT",
			grid,
			"TOPLEFT",
			(position - 1) * CELL_WIDTH,
			-(group - 1) * CELL_HEIGHT
		)

		local background = cell:CreateTexture(nil, "BACKGROUND")
		background:SetAllPoints(cell)
		background:SetColorTexture(0.07, 0.085, 0.11, 0.92)

		local border = cell:CreateTexture(nil, "BORDER")
		border:SetPoint("TOPLEFT", cell, "TOPLEFT", 1, -1)
		border:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)
		border:SetColorTexture(0.18, 0.22, 0.28, 0.5)

		local inset = cell:CreateTexture(nil, "BACKGROUND", nil, 1)
		inset:SetPoint("TOPLEFT", cell, "TOPLEFT", 2, -2)
		inset:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -2, 2)
		inset:SetColorTexture(0.035, 0.04, 0.055, 1)

		local label = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("CENTER")
		label:SetFormattedText("%d-%d", group, position)
	end
end

for index = 1, MAX_LAYERS do
	local layer = grid:CreateTexture(nil, "ARTWORK")
	layer:SetAllPoints(grid)
	-- Probe TGAs are power-of-two (128x64); their 5-column grid occupies the
	-- first 125 pixels so the final three transparent pixels are cropped out.
	layer:SetTexCoord(0, ASSET_U_MAX, 0, 1)
	layer:SetBlendMode("ADD")
	layer:SetAlpha(0)
	layers[index] = layer
end

-- payload may be secret.  Do not add guards, logging, validation, or return
-- values here: all of those invite an accidental observation of the payload.
function TextureRoute:Push(payload)
	arrivalCount = arrivalCount + 1
	local slot = ((arrivalCount - 1) % MAX_LAYERS) + 1
	local path = C_StringUtil.WrapString(payload, TEXTURE_PREFIX, ".tga")

	-- SetTexture's success result may carry secrecy from path.  Feed it directly
	-- into the dedicated boolean sink so a missing texture cannot show Blizzard's
	-- placeholder and produce a confident false positive.
	layers[slot]:SetAlphaFromBoolean(layers[slot]:SetTexture(path), 1, 0)

	counter:SetFormattedText("到达：%d", arrivalCount)
	frame:Show()
end

function TextureRoute:Clear()
	arrivalCount = 0
	for index = 1, MAX_LAYERS do
		layers[index]:SetTexture(nil)
		layers[index]:SetAlpha(0)
	end
	counter:SetFormattedText("到达：%d", arrivalCount)
end

-- Manual is only for ordinary slash-command input.  It deliberately shares
-- the exact Push path used by restricted chat events.
function TextureRoute:Manual(code)
	if code == nil or code == "" then
		code = "1-1"
	end
	self:Push(code)
end

function TextureRoute:Show()
	frame:Show()
end

function TextureRoute:Hide()
	frame:Hide()
end

function TextureRoute:GetArrivalCount()
	return arrivalCount
end

TextureRoute.frame = frame
