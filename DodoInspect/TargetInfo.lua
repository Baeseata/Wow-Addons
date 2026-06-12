-- DodoInspect - TargetInfo.lua
-- One-line player summary above the default target frame: item level
-- (gradient colored), race, class and spec (class colored) and hero
-- talent. Friendly players within inspect range (~28 yards) fill the
-- whole line through the inspect pipeline (NotifyInspect followed by
-- INSPECT_READY).
--
-- Hostile players cannot be inspected, that is a hard Blizzard API
-- rule (CanInspect returns false), so the line renders in layers and
-- shows what the game does expose: race and class everywhere, plus
-- the spec from the scoreboard in battlegrounds and from the opponent
-- spec API in arenas. Item levels and hero talents of hostile players
-- are not available to any addon.
--
-- Every visible word (race, class, spec, hero talent) comes from the
-- game's own localization in the client language, so this works in
-- any locale without addon-side translations.

local _, ns = ...

local HERO_COLOR = "ffd200" -- gold, matches the hero talent theme
local WHITE = "ffffff"

local function IsPlayerTarget()
    return UnitExists("target") and UnitIsPlayer("target")
end

------------------------------------------------------------------
-- Display frame
------------------------------------------------------------------

local display = CreateFrame("Frame", "DodoInspectTargetInfo", UIParent)
display:SetFrameStrata("HIGH")
display:SetSize(620, 30)
display:Hide()

local text = display:CreateFontString(nil, "OVERLAY")
text:SetPoint("CENTER", display, "CENTER", 0, 0)
text:SetJustifyH("CENTER")
-- set a font right away: HideDisplay can SetText("") before the first
-- Render, and SetText on a font-less FontString is an error
ns.SetOverlayFont(text, ns.Config.TARGET_FONT_SIZE, "OUTLINE")

local function AnchorDisplay()
    local cfg = ns.Config
    display:ClearAllPoints()
    if TargetFrame then
        display:SetPoint("BOTTOM", TargetFrame, "TOP",
            cfg.TARGET_OFFSET_X, cfg.TARGET_OFFSET_Y)
    else
        -- target frame replaced by a UI overhaul addon: park the
        -- line at the top of the screen instead
        display:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

local function HideDisplay()
    text:SetText("")
    display:Hide()
end

------------------------------------------------------------------
-- Spec helpers (prefer C_SpecializationInfo, fall back to the
-- deprecated globals still present in 12.0)
------------------------------------------------------------------

local function GetInspectSpecID(unit)
    if C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization then
        return C_SpecializationInfo.GetInspectSpecialization(unit)
    end
    if GetInspectSpecialization then return GetInspectSpecialization(unit) end
    return nil
end

local function SpecNameByID(specID)
    if not specID or specID <= 0 then return nil end
    local name
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoByID then
        name = select(2, C_SpecializationInfo.GetSpecializationInfoByID(specID))
    elseif GetSpecializationInfoByID then
        name = select(2, GetSpecializationInfoByID(specID))
    end
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

------------------------------------------------------------------
-- PvP spec fallback. Inspect is friendly-only, but battleground
-- scoreboards and arena opponent specs cover hostile players too.
------------------------------------------------------------------

local lastScoreRequestAt = 0

-- Ask the server for fresh scoreboard data while in a battleground;
-- the reply fires UPDATE_BATTLEFIELD_SCORE which re-renders.
local function RequestScoreboard()
    local _, instanceType = IsInInstance()
    if instanceType ~= "pvp" then return end
    local now = GetTime()
    if now - lastScoreRequestAt < 3 then return end
    lastScoreRequestAt = now
    if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
end

local function GetPvPSpecName()
    local _, instanceType = IsInInstance()

    -- arena: opponent specs are published before the gates open
    if instanceType == "arena" then
        local n = (GetNumArenaOpponentSpecs and GetNumArenaOpponentSpecs()) or 0
        for i = 1, n do
            if UnitIsUnit("target", "arena" .. i) then
                local specID = GetArenaOpponentSpec and GetArenaOpponentSpec(i)
                return SpecNameByID(specID)
            end
        end
        return nil
    end

    -- battleground: the scoreboard lists both factions, match by GUID
    if instanceType == "pvp" and C_PvP and C_PvP.GetScoreInfo then
        local guid = UnitGUID("target")
        if not guid then return nil end
        local n = (GetNumBattlefieldScores and GetNumBattlefieldScores()) or 0
        for i = 1, n do
            local info = C_PvP.GetScoreInfo(i)
            if info and info.guid == guid then
                local spec = info.talentSpec
                if type(spec) == "string" and spec ~= "" then return spec end
                return nil
            end
        end
    end

    return nil
end

------------------------------------------------------------------
-- Hero talent from the inspect traits config
------------------------------------------------------------------

local function GetInspectHeroTalentName()
    if not C_Traits or not C_ClassTalents then return nil end
    if not C_Traits.HasValidInspectData or not C_Traits.HasValidInspectData() then
        return nil
    end

    local specID = GetInspectSpecID("target")
    if not specID or specID <= 0 then return nil end

    local treeID = C_ClassTalents.GetTraitTreeForSpec
        and C_ClassTalents.GetTraitTreeForSpec(specID)
    if not treeID then return nil end

    local nodeIDs = C_Traits.GetTreeNodes and C_Traits.GetTreeNodes(treeID)
    if type(nodeIDs) ~= "table" then return nil end

    local configID = -1 -- the shared inspect config
    for _, nodeID in ipairs(nodeIDs) do
        local nodeInfo = C_Traits.GetNodeInfo and C_Traits.GetNodeInfo(configID, nodeID)
        if nodeInfo and type(nodeInfo.entryIDs) == "table" then
            local activeEntryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID
            for _, entryID in ipairs(nodeInfo.entryIDs) do
                local entryInfo = C_Traits.GetEntryInfo
                    and C_Traits.GetEntryInfo(configID, entryID)
                if entryInfo and entryInfo.subTreeID and activeEntryID == entryID then
                    local subTreeInfo = C_Traits.GetSubTreeInfo
                        and C_Traits.GetSubTreeInfo(configID, entryInfo.subTreeID)
                    if subTreeInfo and subTreeInfo.name then
                        return subTreeInfo.name
                    end
                end
            end
        end
    end

    return nil
end

------------------------------------------------------------------
-- Compose and render. Layered: race and class render for any player
-- target right away; item level, spec and hero talent join the line
-- when the inspect data (or a PvP fallback) provides them.
------------------------------------------------------------------

local function ColorWrap(hex, s)
    return "|cff" .. hex .. s .. "|r"
end

local function Render()
    if not ns.IsEnabled("showTargetInfo") or not IsPlayerTarget() then
        HideDisplay()
        return
    end

    local parts = {}

    -- item level: inspect only, same gradient as everywhere else
    if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
        local ilvl = C_PaperDollInfo.GetInspectItemLevel("target")
        ilvl = (type(ilvl) == "number") and math.floor(ilvl + 0.5) or nil
        if ilvl and ilvl > 0 then
            local r, g, b = ns.ColorForItemLevel(ilvl)
            parts[#parts + 1] = string.format("|cff%02x%02x%02x%d|r",
                math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
                math.floor(b * 255 + 0.5), ilvl)
        end
    end

    -- race: visible on any player target, friendly or hostile
    local race = UnitRace("target")
    if race then parts[#parts + 1] = ColorWrap(WHITE, race) end

    -- class: visible on any player target, class colored
    local className, classToken = UnitClass("target")
    local classColor = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    local classHex = (classColor and classColor.colorStr)
        and classColor.colorStr:sub(3) or WHITE
    if className then parts[#parts + 1] = ColorWrap(classHex, className) end

    -- spec: inspect first, PvP scoreboard or arena opponents second
    local spec = SpecNameByID(GetInspectSpecID("target")) or GetPvPSpecName()
    if spec then parts[#parts + 1] = ColorWrap(classHex, spec) end

    -- hero talent: inspect only
    local hero = GetInspectHeroTalentName()
    if hero then parts[#parts + 1] = ColorWrap(HERO_COLOR, hero) end

    if #parts == 0 then
        HideDisplay()
        return
    end

    AnchorDisplay()
    ns.SetOverlayFont(text, ns.Config.TARGET_FONT_SIZE, "OUTLINE")
    text:SetText(table.concat(parts, "  "))
    display:SetWidth(math.max(100, text:GetStringWidth() + 20))
    display:Show()
end

------------------------------------------------------------------
-- Inspect request flow
------------------------------------------------------------------

local inspectPendingGUID
local lastInspectRequestAt = 0

local function RequestInspect()
    if not IsPlayerTarget() then return end
    -- hard Blizzard rule: friendly players within ~28 yards only
    if not (CanInspect and CanInspect("target")) then return end

    local now = GetTime()
    if now - lastInspectRequestAt < 0.6 then return end
    lastInspectRequestAt = now

    inspectPendingGUID = UnitGUID("target")
    NotifyInspect("target")
end

------------------------------------------------------------------
-- Toggle hook (options checkbox) and events
------------------------------------------------------------------

function ns.ApplyTargetInfoEnabled()
    if ns.IsEnabled("showTargetInfo") then
        Render()
        RequestInspect()
    else
        HideDisplay()
    end
end

local EVT = CreateFrame("Frame")
EVT:RegisterEvent("PLAYER_ENTERING_WORLD")
EVT:RegisterEvent("PLAYER_TARGET_CHANGED")
EVT:RegisterEvent("INSPECT_READY")
EVT:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
EVT:RegisterEvent("ARENA_OPPONENT_UPDATE")

EVT:SetScript("OnEvent", function(_, event, ...)
    if not ns.IsEnabled("showTargetInfo") then
        HideDisplay()
        return
    end

    if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        inspectPendingGUID = nil
        if IsPlayerTarget() then
            Render() -- race and class show right away
            RequestInspect()
            RequestScoreboard()
            -- inspect and traits data can land a beat later
            C_Timer.After(0.25, Render)
            C_Timer.After(0.65, Render)
        else
            HideDisplay()
        end
        return
    end

    if event == "INSPECT_READY" then
        local guid = ...
        if inspectPendingGUID and guid and guid ~= inspectPendingGUID then return end
        Render()
        C_Timer.After(0, Render) -- traits may lag one frame behind
        return
    end

    -- UPDATE_BATTLEFIELD_SCORE / ARENA_OPPONENT_UPDATE: fresh PvP
    -- spec data may have arrived for the current target
    Render()
end)
