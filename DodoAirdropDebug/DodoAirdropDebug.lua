local addonName, ns = ...

local ADDON_PREFIX = "|cff00ff98DodoAirdropDebug|r"
local MAX_LOGS = 100

DodoAirdropDebugDB = DodoAirdropDebugDB or {}

local frame = CreateFrame("Frame")
local enabled = true
local overlayEnabled = true
local printAll = true

local function nowTime()
    return date("%H:%M:%S")
end

local function safeToString(v)
    if v == nil then
        return "nil"
    end
    local t = type(v)
    if t == "string" then
        return v
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "table" then
        local ok, result = pcall(function() return tostring(v) end)
        return ok and result or "<table>"
    else
        return tostring(v)
    end
end

local function chat(msg)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("%s %s", ADDON_PREFIX, msg))
end

local overlay = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
overlay:SetSize(900, 150)
overlay:SetPoint("TOP", 0, -120)
overlay:SetFrameStrata("FULLSCREEN_DIALOG")
overlay:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
overlay:SetBackdropColor(0, 0, 0, 0.75)
overlay:Hide()

local overlayText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
overlayText:SetPoint("TOPLEFT", 14, -14)
overlayText:SetPoint("BOTTOMRIGHT", -14, 14)
overlayText:SetJustifyH("LEFT")
overlayText:SetJustifyV("TOP")
overlayText:SetText("")

local function showOverlay(lines)
    if not overlayEnabled then
        return
    end
    overlayText:SetText(table.concat(lines, "\n"))
    overlay:Show()
    C_Timer.After(8, function()
        if overlay and overlay:IsShown() then
            overlay:Hide()
        end
    end)
end

local function ensureDB()
    DodoAirdropDebugDB = DodoAirdropDebugDB or {}
    DodoAirdropDebugDB.logs = DodoAirdropDebugDB.logs or {}
end

local function getMapInfo()
    local mapID = C_Map.GetBestMapForUnit("player")
    local mapName = "unknown"
    if mapID then
        local info = C_Map.GetMapInfo(mapID)
        if info and info.name then
            mapName = info.name
        end
    end
    local zoneText = GetZoneText() or ""
    local subZoneText = GetSubZoneText() or ""
    return mapID, mapName, zoneText, subZoneText
end

local function addLog(event, payload)
    ensureDB()
    local mapID, mapName, zoneText, subZoneText = getMapInfo()
    local entry = {
        ts = time(),
        clock = nowTime(),
        event = event,
        mapID = mapID,
        mapName = mapName,
        zoneText = zoneText,
        subZoneText = subZoneText,
        payload = payload,
    }
    table.insert(DodoAirdropDebugDB.logs, 1, entry)
    while #DodoAirdropDebugDB.logs > MAX_LOGS do
        table.remove(DodoAirdropDebugDB.logs)
    end
    return entry
end

local function emit(entry)
    local lines = {
        string.format("[%s] %s", entry.clock, entry.event),
        string.format("Map: %s (%s)", safeToString(entry.mapName), safeToString(entry.mapID)),
        string.format("Zone: %s | SubZone: %s", safeToString(entry.zoneText), safeToString(entry.subZoneText)),
    }

    for i = 1, math.min(#entry.payload, 8) do
        lines[#lines + 1] = string.format("arg%d: %s", i, safeToString(entry.payload[i]))
    end

    if printAll then
        chat(string.format("[%s] event=%s map=%s (%s)", entry.clock, entry.event, safeToString(entry.mapName), safeToString(entry.mapID)))
        for i = 1, math.min(#entry.payload, 8) do
            chat(string.format("arg%d=%s", i, safeToString(entry.payload[i])))
        end
    else
        chat(string.format("[%s] %s", entry.clock, entry.event))
    end

    PlaySound(SOUNDKIT.READY_CHECK, "Master")
    showOverlay(lines)
end

local function record(event, ...)
    if not enabled then
        return
    end

    local payload = {}
    for i = 1, select("#", ...) do
        payload[i] = safeToString(select(i, ...))
    end

    local entry = addLog(event, payload)
    emit(entry)
end

local watchedEvents = {
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
    "TALKINGHEAD_REQUESTED",
    "CHAT_MSG_MONSTER_SAY",
    "CHAT_MSG_MONSTER_YELL",
    "CHAT_MSG_MONSTER_EMOTE",
    "CHAT_MSG_RAID_BOSS_EMOTE",
    "CHAT_MSG_RAID_BOSS_WHISPER",
    "UI_ERROR_MESSAGE",
}

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        ensureDB()
        chat("loaded. Any talking-head style announcement or watched world-message event will dump debug info.")
        return
    end

    record(event, ...)
end)

for _, event in ipairs(watchedEvents) do
    frame:RegisterEvent(event)
end

if TalkingHeadFrame then
    hooksecurefunc(TalkingHeadFrame, "PlayCurrent", function(self)
        if not self or not self.TextFrame then
            return
        end
        local text = self.TextFrame.Text and self.TextFrame.Text:GetText() or nil
        local name = self.NameFrame and self.NameFrame.Name and self.NameFrame.Name:GetText() or nil
        record("HOOK_TALKINGHEAD_PLAYCURRENT", name, text)
    end)
end

SLASH_DODOAIRDROPDEBUG1 = "/dadbg"
SLASH_DODOAIRDROPDEBUG2 = "/dodoairdropdebug"
SlashCmdList["DODOAIRDROPDEBUG"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "off" then
        enabled = false
        chat("debug capture disabled.")
    elseif msg == "on" then
        enabled = true
        chat("debug capture enabled.")
    elseif msg == "overlay off" then
        overlayEnabled = false
        overlay:Hide()
        chat("overlay disabled.")
    elseif msg == "overlay on" then
        overlayEnabled = true
        chat("overlay enabled.")
    elseif msg == "brief" then
        printAll = false
        chat("brief chat output enabled.")
    elseif msg == "full" then
        printAll = true
        chat("full chat output enabled.")
    elseif msg == "last" then
        ensureDB()
        local entry = DodoAirdropDebugDB.logs[1]
        if not entry then
            chat("no logs yet.")
            return
        end
        chat(string.format("last event: [%s] %s | map=%s (%s)", entry.clock, entry.event, safeToString(entry.mapName), safeToString(entry.mapID)))
        for i = 1, math.min(#entry.payload, 12) do
            chat(string.format("arg%d=%s", i, safeToString(entry.payload[i])))
        end
    elseif msg == "clear" then
        ensureDB()
        DodoAirdropDebugDB.logs = {}
        chat("logs cleared.")
    else
        chat("commands: /dadbg on | off | overlay on | overlay off | brief | full | last | clear")
    end
end
