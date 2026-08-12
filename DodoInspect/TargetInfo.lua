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
--
-- =====================================================================
-- !! 12.0 SECRET VALUES -- read before editing this file.
-- Hostile players in instanced PvP expose unit fields (name, realm,
-- localized className, scoreboard guid/spec) as *secret values*.
-- Tainted addon code may NOT compare, concatenate, do arithmetic on,
-- tostring, take # of, or MEASURE them (a fontstring built from a
-- secret has a secret width) -- any of these throws
-- "attempt to compare ... a secret ... value, while execution tainted".
-- Rules that keep this file safe -- do NOT regress:
--   * issecretvalue(x) FIRST on anything unit-derived (it accepts nil
--     and never throws). C_* are engine C (safe); FrameXML Lua globals
--     like GetUnitName run tainted when WE call them and WILL throw.
--   * class via the readable classToken -> LOCALIZED_CLASS_NAMES_MALE,
--     never UnitClass's secret className.
--   * BG spec via C_PvP.GetScoreInfoByPlayerGuid(readable UnitGUID),
--     never a self-rolled scoreboard match.
--   * every text part goes through AddPart; the wrap/measure block is
--     pcall-netted. Full history: DodoInspect/CLAUDE.md.
-- =====================================================================

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

-- hidden twin of `text`, used to measure candidate lines while wrapping
local measure = display:CreateFontString(nil, "OVERLAY")
measure:Hide()
ns.SetOverlayFont(measure, ns.Config.TARGET_FONT_SIZE, "OUTLINE")

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

-- Delegates to the one shared lookup (StatPriority.lua, loaded earlier
-- per the TOC), which issecretvalue-guards the result and filters out 0.
-- Two parallel copies of this used to exist and only one had the guard.
local function GetInspectSpecID(unit)
    return ns.InspectSpecID and ns.InspectSpecID(unit) or nil
end

local function SpecNameByID(specID)
    if issecretvalue(specID) or not specID or specID <= 0 then return nil end
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

    -- battleground: in 12.0 BOTH the scoreboard's per-row `guid` and
    -- the hostile target's unit name/realm are secret, so neither a
    -- guid compare nor a name match works from addon code -- and
    -- GetUnitName itself throws on the secret realm (the 1.3.1 crash:
    -- GetUnitName is FrameXML *Lua*, so it ran in our tainted context).
    -- Hand the target's readable GUID to the engine lookup instead: a
    -- C_PvP *C* function resolves the row in secure code with no
    -- tainted comparison. talentSpec can still come back secret for a
    -- hostile player, so it is issecretvalue-guarded and the whole
    -- block runs under pcall -- a spec that stays secret shows nothing
    -- instead of erroring, and race/class still render.
    local ScoreByGuid = C_PvP and
        (C_PvP.GetScoreInfoByPlayerGuid or C_PvP.GetScoreInfoByPlayerGUID)
    if instanceType == "pvp" and ScoreByGuid then
        local ok, spec = pcall(function()
            local guid = UnitGUID("target")
            if issecretvalue(guid) or not guid then return end
            local info = ScoreByGuid(guid)
            local s = info and info.talentSpec
            if not issecretvalue(s) and type(s) == "string" and s ~= "" then
                return s
            end
        end)
        if ok and spec then return spec end
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

    -- Already guarded and > 0 (or nil) -- see GetInspectSpecID above.
    -- The old bare "specID <= 0" here was a second copy of the same
    -- secret-value crash, shielded only by the HasValidInspectData check.
    local specID = GetInspectSpecID("target")
    if not specID then return nil end

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

-- Append a colored part only when the source string is readable.
-- Hostile unit fields (className, and others) are secret values in
-- instanced PvP on 12.0; a secret in the line would poison the width
-- measurement used for wrapping. issecretvalue is checked first so
-- nothing downstream ever compares or concatenates a secret.
local function AddPart(parts, hex, s)
    if not issecretvalue(s) and type(s) == "string" and s ~= "" then
        parts[#parts + 1] = ColorWrap(hex, s)
    end
end

local function Render()
    if not ns.IsEnabled("showTargetInfo") or not IsPlayerTarget() then
        HideDisplay()
        return
    end

    local parts = {}

    -- item level: inspect only, same gradient as everywhere else.
    -- issecretvalue-guarded like the text fields below (math.floor and
    -- the > 0 compare would throw on a secret number).
    if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
        local ilvl = C_PaperDollInfo.GetInspectItemLevel("target")
        if not issecretvalue(ilvl) and type(ilvl) == "number" then
            ilvl = math.floor(ilvl + 0.5)
            if ilvl > 0 then
                local r, g, b = ns.ColorForItemLevel(ilvl)
                parts[#parts + 1] = string.format("|cff%02x%02x%02x%d|r",
                    math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
                    math.floor(b * 255 + 0.5), ilvl)
            end
        end
    end

    -- race: visible on any player target, friendly or hostile
    AddPart(parts, WHITE, UnitRace("target"))

    -- class: localize from the class TOKEN, not UnitClass's localized
    -- name. The token ("PRIEST") stays readable for everyone, while the
    -- localized className is a secret value for hostile players in
    -- instanced PvP (12.0) and would poison the width measurement.
    local _, classToken = UnitClass("target")
    local classHex = WHITE
    local classDisplay
    if not issecretvalue(classToken) and type(classToken) == "string" then
        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
        if cc and cc.colorStr then classHex = cc.colorStr:sub(3) end
        classDisplay = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classToken]
    end
    AddPart(parts, classHex, classDisplay)

    -- spec: inspect first, PvP scoreboard or arena opponents second
    AddPart(parts, classHex,
        SpecNameByID(GetInspectSpecID("target")) or GetPvPSpecName())

    -- hero talent: inspect only
    AddPart(parts, HERO_COLOR, GetInspectHeroTalentName())

    if #parts == 0 then
        HideDisplay()
        return
    end

    AnchorDisplay()
    ns.SetOverlayFont(text, ns.Config.TARGET_FONT_SIZE, "OUTLINE")
    ns.SetOverlayFont(measure, ns.Config.TARGET_FONT_SIZE, "OUTLINE")

    -- Long locales (German, French, Russian...) can push the one-line
    -- form past half a screen. Wrap between parts onto up to 3 lines;
    -- a break never lands inside a name. Compact locales (CJK) stay
    -- under the cap and keep a single line. Every part above is already
    -- issecretvalue-guarded, so the width measurement is safe; the pcall
    -- is a last-ditch guard so any unforeseen secret hides the line
    -- instead of throwing on the width compare.
    local ok = pcall(function()
        local maxW = ns.Config.TARGET_MAX_WIDTH
        local lines, current = {}, nil
        for _, part in ipairs(parts) do
            local candidate = current and (current .. "  " .. part) or part
            measure:SetText(candidate)
            if current and #lines < 2 and measure:GetStringWidth() > maxW then
                lines[#lines + 1] = current
                current = part
            else
                current = candidate
            end
        end
        lines[#lines + 1] = current

        local widest = 0
        for _, line in ipairs(lines) do
            measure:SetText(line)
            widest = math.max(widest, measure:GetStringWidth())
        end

        text:SetText(table.concat(lines, "\n"))
        display:SetSize(math.max(100, widest + 20),
            math.max(30, text:GetStringHeight() + 10))
    end)

    if not ok then
        HideDisplay()
        return
    end
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
        -- inspect is friendly-only so both GUIDs are readable; guard the
        -- event arg anyway so no future secret GUID can throw the compare
        if not issecretvalue(guid) and inspectPendingGUID
            and guid and guid ~= inspectPendingGUID then return end
        Render()
        C_Timer.After(0, Render) -- traits may lag one frame behind
        return
    end

    -- UPDATE_BATTLEFIELD_SCORE / ARENA_OPPONENT_UPDATE: fresh PvP
    -- spec data may have arrived for the current target
    Render()
end)
