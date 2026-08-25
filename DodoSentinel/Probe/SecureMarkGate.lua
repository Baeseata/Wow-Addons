local ADDON_NAME, ns = ...

local Probe = ns.Probe or {}
ns.Probe = Probe

local Gate = {}
ns.SecureMarkGate = Gate

local PANEL_WIDTH = 380
local PANEL_HEIGHT = 364
local PANEL_X = -260
local PANEL_Y = 150
local ROW_HEIGHT = 28
local ROW_GAP = 6
local ROW_TOP = -58

local CELL_WRAP = [[
if not UnitExists(self:GetAttribute("unit")) then
    return false
end
if button == "LeftButton" then
    local n = (control:GetAttribute("n") or 0) % 5 + 1
    control:SetAttribute("n", n)
    control:SetAttribute("next", n % 5 + 1)
    self:SetAttribute("marker", n)
    return nil, 1
end
if button == "RightButton" then
    return nil, 2
end
return false
]]

local CELL_POST_WRAP = [[
local sequence = (control:GetAttribute("evidence-seq") or 0) + 1
control:SetAttribute("evidence-action", message)
control:SetAttribute("evidence-seq", sequence)
]]

local RESET_WRAP = [[
control:SetAttribute("n", 0)
control:SetAttribute("next", 1)
local sequence = (control:GetAttribute("evidence-seq") or 0) + 1
control:SetAttribute("evidence-action", 3)
control:SetAttribute("evidence-seq", sequence)
return false
]]

local BACK_WRAP = [[
local n = (control:GetAttribute("n") or 0) % 5
n = (n + 4) % 5
control:SetAttribute("n", n)
control:SetAttribute("next", n % 5 + 1)
local sequence = (control:GetAttribute("evidence-seq") or 0) + 1
control:SetAttribute("evidence-action", 4)
control:SetAttribute("evidence-seq", sequence)
return false
]]

local SET_NEXT_WRAP = [[
local marker = self:GetAttribute("next-marker") or 1
control:SetAttribute("n", (marker + 4) % 5)
control:SetAttribute("next", marker)
local sequence = (control:GetAttribute("evidence-seq") or 0) + 1
control:SetAttribute("evidence-action", 5)
control:SetAttribute("evidence-seq", sequence)
return false
]]

local function ApplyBackdrop(frame, red, green, blue, alpha)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 1,
	})
	frame:SetBackdropColor(red, green, blue, alpha)
	frame:SetBackdropBorderColor(0.27, 0.31, 0.38, 0.95)
end

-- SavedVariables evidence is deliberately narrower than the on-screen probe.
-- Chat payloads, player identity, and arbitrary tables never belong here.
local LOG_MAX = 600
local SECRET_OMITTED = "[SECRET OMITTED]"
local copyFrame

local function IsSecretValue(value)
	if type(issecretvalue) ~= "function" then
		return false
	end
	local ok, secret = pcall(issecretvalue, value)
	return ok and secret == true
end

local function IsSecretTable(value)
	if type(issecrettable) ~= "function" then
		return false
	end
	local ok, secret = pcall(issecrettable, value)
	return ok and secret == true
end

local function PlainField(value)
	-- This must be the first operation on every caller-provided value.
	if IsSecretValue(value) then
		return SECRET_OMITTED
	end
	if value == nil then
		return "nil"
	end

	local valueType = type(value)
	if valueType == "table" then
		if IsSecretTable(value) then
			return SECRET_OMITTED
		end
		return "[TABLE OMITTED]"
	elseif valueType == "string" then
		return value
		:gsub("|c%x%x%x%x%x%x%x%x", "")
		:gsub("|r", "")
		:gsub("[\r\n]+", " ")
	elseif valueType == "number" or valueType == "boolean" then
		return tostring(value)
	end
	return "[UNSUPPORTED OMITTED]"
end

local function GetPlainLog()
	if type(DodoSentinelProbeDB) ~= "table" then
		DodoSentinelProbeDB = {}
	end
	if type(DodoSentinelProbeDB.log) ~= "table" then
		DodoSentinelProbeDB.log = {}
	end
	return DodoSentinelProbeDB.log
end

function ns.LogPlain(tag, ...)
	local fields = {}
	for index = 1, select("#", ...) do
		fields[index] = PlainField(select(index, ...))
	end

	local entry = date("%m-%d %H:%M:%S") .. "  [" .. PlainField(tag) .. "]"
	if #fields > 0 then
		entry = entry .. "  " .. table.concat(fields, " ")
	end

	local log = GetPlainLog()
	log[#log + 1] = entry
	while #log > LOG_MAX do
		table.remove(log, 1)
	end
	return entry
end

function ns.GetPlainLogCount()
	return #GetPlainLog()
end

function ns.ClearPlainLog()
	if type(DodoSentinelProbeDB) ~= "table" then
		DodoSentinelProbeDB = {}
	end
	DodoSentinelProbeDB.log = {}
end

function ns.ShowLogCopy()
	if not copyFrame then
		local frame = CreateFrame("Frame", "DodoSentinelProbeCopyFrame", UIParent, "BackdropTemplate")
		frame:SetSize(720, 480)
		frame:SetPoint("CENTER")
		frame:SetFrameStrata("FULLSCREEN_DIALOG")
		frame:SetFrameLevel(500)
		frame:SetClampedToScreen(true)
		frame:SetMovable(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", frame.StartMoving)
		frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
		frame:SetScript("OnShow", function(self)
			self:EnableMouse(true)
		end)
		frame:SetScript("OnHide", function(self)
			self:EnableMouse(false)
		end)
		ApplyBackdrop(frame, 0.015, 0.02, 0.03, 0.97)

		local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		heading:SetPoint("TOPLEFT", 12, -10)
		heading:SetText("DodoSentinel 明文探针日志（Ctrl+A / Ctrl+C）")

		local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -2, -2)

		local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 12, -38)
		scroll:SetPoint("BOTTOMRIGHT", -32, 12)

		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetFontObject(ChatFontNormal)
		edit:SetWidth(660)
		edit:SetAutoFocus(false)
		edit:SetScript("OnEscapePressed", function()
			frame:Hide()
		end)
		scroll:SetScrollChild(edit)

		frame.edit = edit
		copyFrame = frame
		frame:Hide()
	end

	local safeLines = {}
	for index, entry in ipairs(GetPlainLog()) do
		safeLines[index] = PlainField(entry)
	end
	if #safeLines == 0 then
		safeLines[1] = "[no plain evidence logged]"
	end

	copyFrame.edit:SetText(table.concat(safeLines, "\n"))
	copyFrame:Show()
	copyFrame.edit:SetFocus()
	copyFrame.edit:HighlightText()
end

-- The visual surface and protected click surface are siblings. Neither is parented
-- nor anchored to the other, so combat protection does not propagate into status UI.
local visualPanel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
visualPanel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
visualPanel:SetPoint("CENTER", UIParent, "CENTER", PANEL_X, PANEL_Y)
visualPanel:SetFrameStrata("HIGH")
ApplyBackdrop(visualPanel, 0.025, 0.035, 0.055, 0.96)

local title = visualPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 12, -11)
title:SetText("DodoSentinel P0 — 安全标记闸")

local instructions = visualPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
instructions:SetPoint("TOPLEFT", 12, -33)
instructions:SetText("左键：按共享序列设 1→5　　右键：清该单位")

local visualRows = {}
local rowLabels = {}
for index = 1, 5 do
	local row = CreateFrame("Frame", nil, visualPanel, "BackdropTemplate")
	row:SetSize(PANEL_WIDTH - 24, ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 12, ROW_TOP - (index - 1) * (ROW_HEIGHT + ROW_GAP))
	ApplyBackdrop(row, 0.08, 0.095, 0.125, 0.98)

	local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", 9, 0)
	label:SetPoint("RIGHT", -9, 0)
	label:SetJustifyH("LEFT")
	label:SetText("raid" .. index .. "  ·  <空>")

	visualRows[index] = row
	rowLabels[index] = label
end

local rosterStatus = visualPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
rosterStatus:SetPoint("TOPLEFT", 12, -232)
rosterStatus:SetPoint("RIGHT", -12, 0)
rosterStatus:SetJustifyH("LEFT")

local counterStatus = visualPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
counterStatus:SetPoint("TOPLEFT", 12, -252)
counterStatus:SetPoint("RIGHT", -12, 0)
counterStatus:SetJustifyH("LEFT")

local correctionTitle = visualPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
correctionTitle:SetPoint("TOPLEFT", 12, -271)
correctionTitle:SetText("战斗内纠偏：")

local correctionVisuals = {}
local function BuildCorrectionVisual(x, width, label)
	local frame = CreateFrame("Frame", nil, visualPanel, "BackdropTemplate")
	frame:SetSize(width, 24)
	frame:SetPoint("TOPLEFT", x, -291)
	ApplyBackdrop(frame, 0.11, 0.125, 0.16, 1)

	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("CENTER")
	text:SetText(label)

	correctionVisuals[#correctionVisuals + 1] = frame
	return frame
end

BuildCorrectionVisual(12, 54, "归零")
BuildCorrectionVisual(71, 54, "退一格")
for marker = 1, 5 do
	BuildCorrectionVisual(130 + (marker - 1) * 43, 38, "下个" .. marker)
end

local errorMeta = visualPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
errorMeta:SetPoint("TOPLEFT", 12, -323)
errorMeta:SetPoint("RIGHT", -12, 0)
errorMeta:SetJustifyH("LEFT")
errorMeta:SetText("UI_ERROR_MESSAGE：尚无")

local errorText = visualPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
errorText:SetPoint("TOPLEFT", 12, -341)
errorText:SetPoint("RIGHT", -12, 0)
errorText:SetJustifyH("LEFT")
errorText:SetTextColor(1, 0.45, 0.35)

local controller = CreateFrame(
	"Frame",
	"DodoSentinelMarkGateController",
	UIParent,
	"SecureHandlerBaseTemplate"
)
controller:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
controller:SetPoint("CENTER", UIParent, "CENTER", PANEL_X, PANEL_Y)
controller:SetFrameStrata("DIALOG")
controller:SetAttribute("n", 0)
controller:SetAttribute("next", 1)
controller:SetAttribute("evidence-action", 0)
controller:SetAttribute("evidence-seq", 0)

local cells = {}
for index = 1, 5 do
	local unit = "raid" .. index
	local cell = CreateFrame(
		"Button",
		"DodoSentinelMarkGateRaid" .. index,
		controller,
		"SecureActionButtonTemplate"
	)
	cell:SetSize(PANEL_WIDTH - 24, ROW_HEIGHT)
	cell:SetPoint("TOPLEFT", 12, ROW_TOP - (index - 1) * (ROW_HEIGHT + ROW_GAP))
	cell:SetAttribute("unit", unit)
	cell:SetAttribute("*type1", "raidtarget")
	cell:SetAttribute("*action1", "set")
	cell:SetAttribute("*type2", "raidtarget")
	cell:SetAttribute("*action2", "clear")
	cell:SetAttribute("marker", 1)
	cell:SetAttribute("useOnKeyDown", true)
	cell:RegisterForClicks("AnyDown")
	SecureHandlerWrapScript(cell, "OnClick", controller, CELL_WRAP, CELL_POST_WRAP)
	cells[index] = cell
end

local function BuildCorrectionButton(name, x, width, wrapBody, marker)
	local button = CreateFrame(
		"Button",
		name,
		controller,
		"SecureActionButtonTemplate"
	)
	button:SetSize(width, 24)
	button:SetPoint("TOPLEFT", x, -291)
	button:SetAttribute("useOnKeyDown", true)
	if marker then
		button:SetAttribute("next-marker", marker)
	end
	button:RegisterForClicks("LeftButtonDown")
	SecureHandlerWrapScript(button, "OnClick", controller, wrapBody)
	return button
end

local correctionButtons = {
	BuildCorrectionButton("DodoSentinelMarkGateReset", 12, 54, RESET_WRAP),
	BuildCorrectionButton("DodoSentinelMarkGateBack", 71, 54, BACK_WRAP),
}
for marker = 1, 5 do
	correctionButtons[#correctionButtons + 1] = BuildCorrectionButton(
		"DodoSentinelMarkGateNext" .. marker,
		130 + (marker - 1) * 43,
		38,
		SET_NEXT_WRAP,
		marker
	)
end

-- Fixed evidence codes: 1=cell-left, 2=cell-right, 3=reset, 4=back,
-- 5=set-next. This is an attempted-action/counter snapshot, never a claim
-- that SetRaidTarget succeeded. No unit, player identity, or marker readback
-- enters this bridge. HookScript preserves the controller's secure handler.
controller:HookScript("OnAttributeChanged", function(_, name, value)
	if IsSecretValue(name) or name ~= "evidence-seq" then
		return
	end
	ns.LogPlain(
		"secure-transition",
		"sequence",
		value,
		"action-code",
		controller:GetAttribute("evidence-action"),
		"counter",
		controller:GetAttribute("n"),
		"next",
		controller:GetAttribute("next")
	)
end)

-- A normal sibling above the secure layer is the combat fail-closed gate. It can
-- legally appear after GROUP_ROSTER_UPDATE and consumes every click until combat ends.
local staleBlocker = CreateFrame(
	"Frame",
	"DodoSentinelMarkGateBlocker",
	UIParent,
	"BackdropTemplate"
)
staleBlocker:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
staleBlocker:SetPoint("CENTER", UIParent, "CENTER", PANEL_X, PANEL_Y)
staleBlocker:SetFrameStrata("FULLSCREEN_DIALOG")
staleBlocker:SetFrameLevel(200)
ApplyBackdrop(staleBlocker, 0.24, 0.015, 0.015, 0.92)

local function ShowBlocker()
	staleBlocker:EnableMouse(true)
	staleBlocker:Show()
end

local function HideBlocker()
	staleBlocker:Hide()
	staleBlocker:EnableMouse(false)
end

local staleTitle = staleBlocker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
staleTitle:SetPoint("CENTER", 0, 12)
staleTitle:SetText("团队结构已变化 — 点击已封锁")

local staleHelp = staleBlocker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
staleHelp:SetPoint("TOP", staleTitle, "BOTTOM", 0, -8)
staleHelp:SetText("本轮 fail-closed；离开战斗后自动刷新 raid1–raid5 快照")
HideBlocker()

local function ShowStaleBlocker()
	staleTitle:SetText("团队结构已变化 — 点击已封锁")
	staleHelp:SetText("本轮 fail-closed；离开战斗后自动刷新 raid1–raid5 快照")
	ShowBlocker()
end

local function ShowPendingHideBlocker()
	staleTitle:SetText("正在等待离开战斗后隐藏")
	staleHelp:SetText("受保护点击层仍在原位，因此先用普通遮罩封锁全部点击")
	ShowBlocker()
end

local requestedVisible = true
local pendingVisibility
local rosterReady = false
local permissionReady = false
local stale = false
local errorCount = 0

local function RefreshStatus()
	if stale then
		rosterStatus:SetText("|cffff5c5cSTALE：团队结构在战斗中发生变化，本轮禁止继续点击。|r")
	elseif not rosterReady then
		rosterStatus:SetText("|cffffc45c需要转换为团队，并保证 raid1–raid5 均存在。|r")
	elseif not permissionReady then
		rosterStatus:SetText("|cffffc45c当前不是团长/助理；标记动作预计无权限。|r")
	elseif InCombatLockdown() then
		rosterStatus:SetText("|cff67e480战斗锁定中：只允许真实点击与受保护纠偏。|r")
	else
		rosterStatus:SetText("|cff67e480快照就绪：请让团长快速左键点五个不同单位。|r")
	end
end

local function RefreshRoster()
	if InCombatLockdown() then
		return false
	end

	rosterReady = IsInRaid() and GetNumGroupMembers() >= 5
	permissionReady = UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")

	for index = 1, 5 do
		local unit = "raid" .. index
		local name = UnitName(unit)
		if name then
			rowLabels[index]:SetFormattedText("%s  ·  %s", unit, name)
		else
			rowLabels[index]:SetFormattedText("%s  ·  <空>", unit)
		end
	end

	RefreshStatus()
	return true
end

local function ApplyVisibility(shown)
	requestedVisible = shown
	for _, cell in ipairs(cells) do
		cell:EnableMouse(shown)
	end
	for _, button in ipairs(correctionButtons) do
		button:EnableMouse(shown)
	end
	if shown then
		visualPanel:Show()
		controller:Show()
		if stale then
			ShowBlocker()
		else
			HideBlocker()
		end
	else
		HideBlocker()
		controller:Hide()
		visualPanel:Hide()
	end
end

local function ResetCounterOutOfCombat()
	if InCombatLockdown() then
		return false
	end
	controller:SetAttribute("n", 0)
	controller:SetAttribute("next", 1)
	return true
end

local function SetNextOutOfCombat(marker)
	if InCombatLockdown()
		or IsSecretValue(marker)
		or type(marker) ~= "number"
		or marker % 1 ~= 0
		or marker < 1
		or marker > 5
	then
		return false
	end
	controller:SetAttribute("n", (marker + 4) % 5)
	controller:SetAttribute("next", marker)
	return true
end

local function BackOutOfCombat()
	if InCombatLockdown() then
		return false
	end
	local n = (controller:GetAttribute("n") or 0) % 5
	n = (n + 4) % 5
	controller:SetAttribute("n", n)
	controller:SetAttribute("next", n % 5 + 1)
	return true
end

function Gate:Show()
	if InCombatLockdown() then
		requestedVisible = true
		pendingVisibility = true
		if stale then
			ShowStaleBlocker()
		else
			HideBlocker()
		end
		return false
	end
	pendingVisibility = nil
	ApplyVisibility(true)
	return true
end

function Gate:Hide()
	if InCombatLockdown() then
		requestedVisible = false
		pendingVisibility = false
		if controller:IsShown() then
			ShowPendingHideBlocker()
		end
		return false
	end
	pendingVisibility = nil
	ApplyVisibility(false)
	return true
end

function Gate:Reset()
	return ResetCounterOutOfCombat()
end

function Gate:SetNext(marker)
	return SetNextOutOfCombat(marker)
end

function Gate:Back()
	return BackOutOfCombat()
end

function Gate:Clear()
	errorCount = 0
	errorMeta:ClearText()
	errorMeta:SetText("UI_ERROR_MESSAGE：尚无")
	errorText:ClearText()
	return ResetCounterOutOfCombat()
end

function Gate:GetStatus()
	return {
		requestedVisible = requestedVisible,
		appliedVisible = controller:IsShown(),
		stale = stale,
		rosterReady = rosterReady,
		permissionReady = permissionReady,
		errorCount = errorCount,
		counter = controller:GetAttribute("n"),
		nextMarker = controller:GetAttribute("next"),
	}
end

function Gate:GetController()
	return controller
end

function Gate:GetCells()
	return cells
end

local pollElapsed = 0
visualPanel:SetScript("OnUpdate", function(_, elapsed)
	pollElapsed = pollElapsed + elapsed
	if pollElapsed < 0.1 then
		return
	end
	pollElapsed = 0
	counterStatus:SetFormattedText(
		"共享计数器：上次 %s　/　下一枚 %s",
		controller:GetAttribute("n"),
		controller:GetAttribute("next")
	)
end)

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("UI_ERROR_MESSAGE")
events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		local addonName = ...
		if addonName == ADDON_NAME then
			ns.LogPlain("boot", "addon-loaded", ADDON_NAME)
			events:UnregisterEvent("ADDON_LOADED")
		end
		return
	end

	if event == "UI_ERROR_MESSAGE" then
		local errorType, message = ...
		errorCount = errorCount + 1
		errorMeta:SetFormattedText("UI_ERROR_MESSAGE #%d（code %s）", errorCount, errorType)
		-- Message is escaped in C, sent to a widget sink, and never persisted.
		errorText:SetText(C_StringUtil.EscapeQuotedCodes(message))
		ns.LogPlain("ui-error", "sequence", errorCount, "code", errorType)
		return
	end

	if event == "GROUP_ROSTER_UPDATE" and InCombatLockdown() then
		stale = true
		if controller:IsShown() then
			ShowStaleBlocker()
		end
		ns.LogPlain("roster", "combat-change", "blocked", true)
		RefreshStatus()
		return
	end

	if event == "PLAYER_REGEN_ENABLED" then
		stale = false
		HideBlocker()
		if pendingVisibility ~= nil then
			local shown = pendingVisibility
			pendingVisibility = nil
			ApplyVisibility(shown)
		end
		RefreshRoster()
		return
	end

	if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
		RefreshRoster()
	else
		RefreshStatus()
	end
end)

local function CallOptional(module, method, ...)
	if module and type(module[method]) == "function" then
		return module[method](module, ...)
	end
end

function Probe:Show()
	local changed = Gate:Show()
	CallOptional(ns.SecretChat, "Show")
	CallOptional(ns.TextureRoute, "Show")
	return changed
end

function Probe:Hide()
	local changed = Gate:Hide()
	CallOptional(ns.SecretChat, "Hide")
	CallOptional(ns.TextureRoute, "Hide")
	return changed
end

function Probe:Reset()
	local changed = Gate:Reset()
	CallOptional(ns.SecretChat, "Clear")
	CallOptional(ns.TextureRoute, "Clear")
	return changed
end

function Probe:Clear()
	local changed = Gate:Clear()
	CallOptional(ns.SecretChat, "Clear")
	CallOptional(ns.TextureRoute, "Clear")
	return changed
end

function Probe:Status()
	return Gate:GetStatus()
end

local function PrintHelp()
	DEFAULT_CHAT_FRAME:AddMessage("|cff65d9ffDodoSentinel P0|r  /dsprobe show|hide|status|reset|clear")
	DEFAULT_CHAT_FRAME:AddMessage("/dsprobe next 1-5 | back（仅战斗外；战斗内用面板纠偏键）")
	DEFAULT_CHAT_FRAME:AddMessage("/dsprobe chat on|off | texture <坐标> | copy | log | logclear")
end

SLASH_DODOSENTINELPROBE1 = "/dsprobe"
-- Slash evidence uses only fixed labels below. Never persist `message` or
-- `argument`; texture/manual input may intentionally be arbitrary probe data.
SlashCmdList.DODOSENTINELPROBE = function(message)
	local command, argument = string.match(message or "", "^%s*(%S*)%s*(.-)%s*$")
	command = string.lower(command)

	if command == "show" then
		ns.LogPlain("command", "show")
		if not Probe:Show() then
			DEFAULT_CHAT_FRAME:AddMessage("DodoSentinel：战斗中不能切换受保护面板，已排队到离战。")
		end
	elseif command == "hide" then
		ns.LogPlain("command", "hide")
		if not Probe:Hide() then
			DEFAULT_CHAT_FRAME:AddMessage("DodoSentinel：战斗中不能切换受保护面板，已排队到离战。")
		end
	elseif command == "reset" then
		ns.LogPlain("command", "reset")
		if not Probe:Reset() then
			DEFAULT_CHAT_FRAME:AddMessage("DodoSentinel：战斗中请点面板上的受保护纠偏键。")
		end
	elseif command == "clear" then
		ns.LogPlain("command", "clear")
		if not Probe:Clear() then
			DEFAULT_CHAT_FRAME:AddMessage("DodoSentinel：显示已清；共享计数器战斗中未改。")
		end
	elseif command == "status" then
		ns.LogPlain("command", "status")
		RefreshStatus()
		DEFAULT_CHAT_FRAME:AddMessage("DodoSentinel：状态已刷新，请看 P0 面板。")
	elseif command == "copy" then
		ns.LogPlain("command", "copy")
		ns.ShowLogCopy()
	elseif command == "log" then
		ns.LogPlain("command", "log")
		DEFAULT_CHAT_FRAME:AddMessage(
			("DodoSentinel：明文日志 %d 条；还需 /reload 才写入 SavedVariables 文件。"):format(
				ns.GetPlainLogCount()
			)
		)
	elseif command == "logclear" then
		ns.ClearPlainLog()
		ns.LogPlain("command", "logclear")
		DEFAULT_CHAT_FRAME:AddMessage("DodoSentinel：旧日志已清并留下本次清理记录；还需 /reload 才写盘。")
	elseif command == "next" then
		local marker = tonumber(argument)
		if not marker or not Gate:SetNext(marker) then
			DEFAULT_CHAT_FRAME:AddMessage("DodoSentinel：next 只接受 1–5，且只能战斗外执行。")
		else
			ns.LogPlain("command", "next", "value", marker)
		end
	elseif command == "back" then
		if not Gate:Back() then
			DEFAULT_CHAT_FRAME:AddMessage("DodoSentinel：战斗中请点面板上的“退一格”。")
		else
			ns.LogPlain("command", "back")
		end
	elseif command == "chat" then
		local mode = string.lower(argument)
		if not ns.SecretChat or not ns.SecretChat.SetEnabled then
			DEFAULT_CHAT_FRAME:AddMessage("DodoSentinel：SecretChat 探针尚未加载。")
		elseif mode == "on" then
			ns.SecretChat:SetEnabled(true)
			ns.LogPlain("command", "chat-on")
		elseif mode == "off" then
			ns.SecretChat:SetEnabled(false)
			ns.LogPlain("command", "chat-off")
		else
			DEFAULT_CHAT_FRAME:AddMessage("DodoSentinel：用法 /dsprobe chat on|off；当前状态未改变。")
		end
	elseif command == "texture" then
		if ns.TextureRoute and ns.TextureRoute.Manual then
			ns.TextureRoute:Manual(argument)
			ns.LogPlain("command", "texture-manual")
		else
			DEFAULT_CHAT_FRAME:AddMessage("DodoSentinel：TextureRoute 探针尚未加载。")
		end
	else
		if command == "" then
			ns.LogPlain("command", "help")
		end
		PrintHelp()
	end
end

RefreshRoster()
