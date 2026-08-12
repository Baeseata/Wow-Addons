-- DodoInspect - StatPriority.lua
-- Renders the current spec's PvE stat priority as a compact colored
-- line docked at the top of a gear panel (the character side panel and
-- the inspect side panel). The data lives in Data/StatPriority.lua.
--
-- The line reuses the exact stat abbreviations (ns.L.stats) and colors
-- (Config.STAT_COLORS) the panel's stat grid uses, so the top line and
-- the per-row dominant-stat highlight read as the same language. Raid
-- and M+ collapse to one unlabeled line when identical, otherwise show
-- two labeled lines. Soft caps and the source live in the hover tooltip
-- (structured, template-translated -- no per-spec prose to localize).
--
-- This file stays ASCII: the separators are plain ">" and "=", the
-- labels come from ns.L (Locales.lua) and the tooltip full names come
-- from the game's own localized STAT_* globals.

local _, ns = ...

------------------------------------------------------------------
-- Spec detection (own character + inspected unit)
------------------------------------------------------------------

-- The player's current specID, or nil. C_SpecializationInfo is the
-- 12.0 path; the globals are the deprecated-but-working fallback.
local function PlayerSpecID()
    local idx
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        idx = C_SpecializationInfo.GetSpecialization()
    elseif type(GetSpecialization) == "function" then
        idx = GetSpecialization()
    end
    if type(idx) ~= "number" then return nil end
    if type(GetSpecializationInfo) == "function" then
        return (GetSpecializationInfo(idx))
    end
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
        return (C_SpecializationInfo.GetSpecializationInfo(idx))
    end
    return nil
end
ns.PlayerSpecID = PlayerSpecID

-- The inspected unit's specID, or nil (0 = not yet known, secret = nil).
-- This is the ONE spec lookup for non-player units -- TargetInfo calls
-- it too, so the secret guard below can never go missing on one side.
--
-- !! The issecretvalue check MUST come first. A hostile player's spec is
-- a secret value, and type() still reports "number" for one: the throw
-- happens on the id > 0 compare, not on the type check. issecretvalue
-- accepts anything (nil included) and never throws, so it leads.
function ns.InspectSpecID(unit)
    if not unit then return nil end
    local id
    if C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization then
        id = C_SpecializationInfo.GetInspectSpecialization(unit)
    elseif type(GetInspectSpecialization) == "function" then
        id = GetInspectSpecialization(unit)
    end
    if not issecretvalue(id) and type(id) == "number" and id > 0 then return id end
    return nil
end

-- The player's active hero-talent sub-tree ID + its localized name, or
-- nil before a hero spec is unlocked / selected. C_ClassTalents and
-- C_Traits are AllowedWhenUntainted, so this is safe from the addon.
function ns.PlayerHeroSubTree()
    if not (C_ClassTalents and C_ClassTalents.GetActiveHeroTalentSpec) then return nil end
    local subID = C_ClassTalents.GetActiveHeroTalentSpec()
    if not subID then return nil end
    local name
    local cfg = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    if cfg and C_Traits and C_Traits.GetSubTreeInfo then
        local info = C_Traits.GetSubTreeInfo(cfg, subID)
        name = info and info.name
    end
    return subID, name
end

-- The inspected unit's active hero-talent sub-tree ID + name. The
-- inspect config is C_Traits id -1 (valid after INSPECT_READY, which
-- the inspect panel already waits for): walk the tree nodes for the
-- SubTreeSelection node whose chosen sub-tree is active. Inspectable
-- (friendly) units only -- trait config data is never a secret value.
function ns.InspectHeroSubTree()
    if not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes
        and C_Traits.GetNodeInfo) then
        return nil
    end
    local INSPECT = -1
    local cfg = C_Traits.GetConfigInfo(INSPECT)
    if not cfg or not cfg.treeIDs then return nil end
    for _, treeID in ipairs(cfg.treeIDs) do
        local nodes = C_Traits.GetTreeNodes(treeID)
        if nodes then
            for _, nodeID in ipairs(nodes) do
                local ni = C_Traits.GetNodeInfo(INSPECT, nodeID)
                if ni and ni.subTreeID and ni.subTreeActive then
                    local sub = C_Traits.GetSubTreeInfo
                        and C_Traits.GetSubTreeInfo(INSPECT, ni.subTreeID)
                    return ni.subTreeID, sub and sub.name
                end
            end
        end
    end
    return nil
end

------------------------------------------------------------------
-- Order -> colored string
------------------------------------------------------------------

local GRAY   = "|cff808080"
local CYAN   = "|cff40d9d9"           -- matches the slot abbreviation color
local SEP_GT = GRAY .. " > " .. "|r"  -- strictly better
local SEP_EQ = GRAY .. " = " .. "|r"  -- roughly equal (sources' ">=")

-- Game globals for the full localized stat names (tooltip only).
local STAT_FULL = {
    crit        = "STAT_CRITICAL_STRIKE",
    haste       = "STAT_HASTE",
    mastery     = "STAT_MASTERY",
    versatility = "STAT_VERSATILITY",
}

local function AbbrevLabel(statKey)
    return (ns.L and ns.L.stats and ns.L.stats[statKey]) or statKey
end

local function FullLabel(statKey)
    local g = _G[STAT_FULL[statKey] or ""]
    if type(g) == "string" and g ~= "" then return g end
    return AbbrevLabel(statKey)
end

local function ColorStat(statKey, labelFn)
    local label = labelFn(statKey)
    local c = ns.Config.STAT_COLORS[statKey]
    if not c then return label end
    return string.format("|cff%02x%02x%02x%s|r",
        math.floor(c[1] * 255 + 0.5),
        math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5), label)
end

-- Build one colored line from an order array (elements are stat keys or
-- tie-group sub-arrays). labelFn picks abbreviations or full names.
local function BuildOrder(order, labelFn)
    local parts = {}
    for _, elem in ipairs(order) do
        if type(elem) == "table" then
            local sub = {}
            for _, sk in ipairs(elem) do
                sub[#sub + 1] = ColorStat(sk, labelFn)
            end
            parts[#parts + 1] = table.concat(sub, SEP_EQ)
        else
            parts[#parts + 1] = ColorStat(elem, labelFn)
        end
    end
    return table.concat(parts, SEP_GT)
end

local function ElemEqual(x, y)
    if type(x) ~= type(y) then return false end
    if type(x) == "table" then
        if #x ~= #y then return false end
        for i = 1, #x do if x[i] ~= y[i] then return false end end
        return true
    end
    return x == y
end

local function OrdersEqual(a, b)
    if not a or not b then return false end
    if #a ~= #b then return false end
    for i = 1, #a do
        if not ElemEqual(a[i], b[i]) then return false end
    end
    return true
end

-- Resolve the effective priority for a spec given the active hero
-- talent sub-tree. A build-specific override (data.builds[subTreeID])
-- wins; otherwise the spec default. Each entry is self-contained
-- (raid + optional mythic + optional softcap), so a matched build is
-- returned as-is and never inherits the default's mythic / softcap.
local function Resolve(specID, subTreeID)
    if ns.Config.STAT_PRIORITY_DATA_CURRENT ~= true then return nil end
    local data = specID and ns.StatPriority and ns.StatPriority[specID]
    if not data then return nil end
    if subTreeID and data.builds and data.builds[subTreeID] then
        return data.builds[subTreeID]
    end
    return data
end

-- True when the header can show anything at all: the data-freshness
-- gate plus the user toggle.
--
-- Callers must check this BEFORE looking a spec up. The gate inside
-- Resolve is too late to protect the lookups: UpdateStatPriorityHeader's
-- arguments are evaluated before the call, so ns.InspectSpecID(unit) runs
-- (and could throw on a secret) even with the feature fully switched off.
-- Callers still call UpdateStatPriorityHeader with a nil specID when this
-- is false -- that is what zeroes dodoPriorityHeight and re-flows the rows.
function ns.StatPriorityActive()
    if ns.Config.STAT_PRIORITY_DATA_CURRENT ~= true then return false end
    return ns.IsEnabled("showStatPriority") and true or false
end

------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------

local function OnHeaderEnter(self)
    local data = Resolve(self.specID, self.subTreeID)
    if not data then return end
    local L = ns.L or {}

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.priTitle or "Stat Priority", 1, 0.82, 0)

    -- which hero talent build these numbers are for (when detected)
    if self.heroName then
        GameTooltip:AddLine(string.format(L.priBuild or "Build: %s", self.heroName),
            0.55, 0.80, 1.00)
    end

    local mythic = data.mythic or data.raid
    if OrdersEqual(data.raid, mythic) then
        GameTooltip:AddLine(BuildOrder(data.raid, FullLabel), 1, 1, 1, true)
        GameTooltip:AddLine(L.priSame or "Raid = M+", 0.6, 0.6, 0.6)
    else
        GameTooltip:AddDoubleLine(L.priRaid or "Raid",
            BuildOrder(data.raid, FullLabel))
        GameTooltip:AddDoubleLine(L.priMythic or "M+",
            BuildOrder(mythic, FullLabel))
    end

    if data.softcap then
        for _, sk in ipairs({ "crit", "haste", "mastery", "versatility" }) do
            local v = data.softcap[sk]
            if v then
                GameTooltip:AddLine(
                    string.format(L.priSoftcap or "%s soft cap ~%d%%",
                        FullLabel(sk), v), 0.8, 0.8, 0.8)
            end
        end
    end

    if ns.STAT_PRIORITY_SOURCE then
        GameTooltip:AddLine(string.format(L.priSource or "Source: %s, %s",
            ns.STAT_PRIORITY_SOURCE, ns.STAT_PRIORITY_DATE or "?"),
            0.5, 0.5, 0.5)
    end

    -- disclaimer: aggregated public data, reference only (wraps)
    if L.priDisclaimer then
        GameTooltip:AddLine(L.priDisclaimer, 0.45, 0.45, 0.45, true)
    end
    GameTooltip:Show()
end

local function OnHeaderLeave()
    GameTooltip:Hide()
end

------------------------------------------------------------------
-- Header region (one per panel)
------------------------------------------------------------------

-- Build the header child once. It owns its own vertical footprint; the
-- panel's LayoutRows reads panel.dodoPriorityHeight to know how much
-- top space to leave for it.
function ns.SetupStatPriorityHeader(panel)
    if panel.dodoPri then return panel.dodoPri end

    local h = CreateFrame("Frame", nil, panel)
    h:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -6)

    local function NewFS()
        local fs = h:CreateFontString(nil, "OVERLAY")
        fs:SetJustifyH("LEFT")
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        return fs
    end

    h.line1 = NewFS()
    h.line2 = NewFS()
    h.divider = h:CreateTexture(nil, "OVERLAY")
    h.divider:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    h.divider:SetHeight(1)

    h:SetScript("OnEnter", OnHeaderEnter)
    h:SetScript("OnLeave", OnHeaderLeave)
    h:EnableMouse(true)

    panel.dodoPri = h
    return h
end

-- Populate / size the header for the given spec and font size, and
-- record the vertical space it needs in panel.dodoPriorityHeight (0 when
-- disabled, no panel header, or no data for the spec). Returns that
-- height so callers can use it directly too.
function ns.UpdateStatPriorityHeader(panel, specID, subTreeID, heroName, fontSize, panelW)
    local h = panel and panel.dodoPri
    if not h then
        if panel then panel.dodoPriorityHeight = 0 end
        return 0
    end

    local data = (specID and ns.IsEnabled("showStatPriority"))
        and Resolve(specID, subTreeID) or nil
    if not data then
        h:Hide()
        panel.dodoPriorityHeight = 0
        return 0
    end

    h.specID = specID
    h.subTreeID = subTreeID
    h.heroName = heroName
    local width = (panelW or panel:GetWidth() or 200) - 12
    local fs1, fs2, div = h.line1, h.line2, h.divider

    ns.SetOverlayFont(fs1, fontSize, "OUTLINE")
    ns.SetOverlayFont(fs2, fontSize, "OUTLINE")
    fs1:ClearAllPoints()
    fs1:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)

    local mythic = data.mythic or data.raid
    local raidLine = BuildOrder(data.raid, AbbrevLabel)
    local lines, lastFS = 1, fs1

    if OrdersEqual(data.raid, mythic) then
        fs1:SetText(raidLine)
        fs2:Hide()
    else
        fs1:SetText(CYAN .. (ns.L.priRaid or "R") .. "|r " .. raidLine)
        fs2:ClearAllPoints()
        fs2:SetPoint("TOPLEFT", fs1, "BOTTOMLEFT", 0, -2)
        fs2:SetText(CYAN .. (ns.L.priMythic or "M") .. "|r "
            .. BuildOrder(mythic, AbbrevLabel))
        fs2:Show()
        lines, lastFS = 2, fs2
    end

    local lineH = fontSize + 2
    local textBlockH = lines * lineH + (lines == 2 and 2 or 0)
    local divGap, botPad, topInset = 3, 2, 6

    h:SetSize(width, textBlockH)
    div:ClearAllPoints()
    div:SetWidth(width)
    div:SetPoint("TOPLEFT", lastFS, "BOTTOMLEFT", 0, -divGap)
    div:Show()
    h:Show()

    local reserved = topInset + textBlockH + divGap + 1 + botPad
    panel.dodoPriorityHeight = reserved
    return reserved
end

-- Toggle handler: refresh both panels in place (the update reclaims or
-- yields the top space and re-flows the rows).
function ns.ApplyStatPriorityEnabled()
    if ns.UpdateSidePanel then ns.UpdateSidePanel() end
    if ns.UpdateInspectPanel then ns.UpdateInspectPanel() end
end
