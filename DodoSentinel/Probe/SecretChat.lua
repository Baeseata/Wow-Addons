local _, ns = ...

-- P0 probe for encounter-chat secrecy.  The incoming message and sender are
-- never stored.  Each value is escaped, then passed immediately to a FontString
-- sink; the raw message is also passed to TextureRoute, whose implementation is
-- constrained to secret-safe C API sinks.

local SecretChat = {}
ns.SecretChat = SecretChat

local MAX_ROWS = 20
local ROW_HEIGHT = 18
local rows = {}
local enabled = false
local arrivalCount = 0

local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
frame:SetSize(610, 58 + MAX_ROWS * ROW_HEIGHT)
-- Keep the chat sink below the secure marking panel; both probes can be shown
-- together on a 1920x1080 test client without covering click targets.
frame:SetPoint("CENTER", UIParent, "CENTER", -285, -250)
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
title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -11)
title:SetText("DodoSentinel · SecretChat")

local stateText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
stateText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -13)
stateText:SetText("监听：关")

local sequenceHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
sequenceHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -36)
sequenceHeader:SetText("#")

local channelHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
channelHeader:SetPoint("LEFT", sequenceHeader, "LEFT", 34, 0)
channelHeader:SetText("频道")

local senderHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
senderHeader:SetPoint("LEFT", sequenceHeader, "LEFT", 82, 0)
senderHeader:SetText("发送者（仅渲染）")

local messageHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
messageHeader:SetPoint("LEFT", sequenceHeader, "LEFT", 258, 0)
messageHeader:SetText("内容（仅渲染）")

for index = 1, MAX_ROWS do
	local row = CreateFrame("Frame", nil, frame)
	row:SetSize(586, ROW_HEIGHT)
	row:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -48 - (index - 1) * ROW_HEIGHT)
	row:SetClipsChildren(true)

	if index % 2 == 0 then
		local stripe = row:CreateTexture(nil, "BACKGROUND")
		stripe:SetAllPoints(row)
		stripe:SetColorTexture(1, 1, 1, 0.025)
	end

	row.sequence = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.sequence:SetSize(28, ROW_HEIGHT)
	row.sequence:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.sequence:SetJustifyH("RIGHT")

	row.channel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.channel:SetSize(40, ROW_HEIGHT)
	row.channel:SetPoint("LEFT", row.sequence, "RIGHT", 6, 0)
	row.channel:SetJustifyH("LEFT")

	row.sender = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.sender:SetSize(168, ROW_HEIGHT)
	row.sender:SetPoint("LEFT", row.channel, "RIGHT", 8, 0)
	row.sender:SetJustifyH("LEFT")
	row.sender:SetWordWrap(false)

	row.message = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.message:SetSize(324, ROW_HEIGHT)
	row.message:SetPoint("LEFT", row.sender, "RIGHT", 8, 0)
	row.message:SetJustifyH("LEFT")
	row.message:SetWordWrap(false)

	row:Hide()
	rows[index] = row
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_RAID")
eventFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
eventFrame:SetScript("OnEvent", function(_, event, message, sender)
	if not enabled then
		return
	end

	arrivalCount = arrivalCount + 1
	local slot = ((arrivalCount - 1) % MAX_ROWS) + 1
	local row = rows[slot]
	if type(ns.LogPlain) == "function" then
		-- event is one of the two fixed registered names; arrivalCount is derived
		-- only from callback order.  Never pass chat payloads into the plain log.
		ns.LogPlain(event, arrivalCount)
	end

	-- ClearText is the official reset for a FontString that has consumed a
	-- secret.  Never return these widgets to a pool.
	row.sender:ClearText()
	row.message:ClearText()
	row.sequence:SetFormattedText("%02d", arrivalCount)
	row.channel:SetText(event == "CHAT_MSG_RAID_LEADER" and "RL" or "R")

	-- EscapeQuotedCodes is mandatory because the text is opaque, untrusted chat
	-- markup.  Its return value goes straight to the secret-safe rendering sink.
	row.sender:SetText(C_StringUtil.EscapeQuotedCodes(sender))
	row.message:SetText(C_StringUtil.EscapeQuotedCodes(message))
	row:Show()
	frame:Show()

	if ns.TextureRoute and ns.TextureRoute.Push then
		ns.TextureRoute:Push(message)
	end
end)

function SecretChat:SetEnabled(value)
	enabled = value == true
	if enabled then
		stateText:SetText("监听：开")
		frame:Show()
	else
		stateText:SetText("监听：关")
		frame:Hide()
	end
end

function SecretChat:IsEnabled()
	return enabled
end

function SecretChat:Clear()
	arrivalCount = 0
	for index = 1, MAX_ROWS do
		local row = rows[index]
		row.sender:ClearText()
		row.message:ClearText()
		row.sequence:ClearText()
		row.channel:ClearText()
		row:Hide()
	end
end

function SecretChat:Show()
	frame:Show()
end

function SecretChat:Hide()
	frame:Hide()
end

function SecretChat:GetArrivalCount()
	return arrivalCount
end

SecretChat.frame = frame
