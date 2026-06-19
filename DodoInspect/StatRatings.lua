-- DodoInspect - StatRatings.lua
-- Reworks the character stats pane:
--   * Enhancement rows become three aligned columns -- label |
--     percentage | rating -- by sliding Blizzard's percentage left and
--     drawing the rating in its own right-aligned column, colored to
--     match the side panel stat colors;
--   * percentages are shown to one decimal place;
--   * the Item Level number is recolored with the addon gradient and
--     shown to one decimal place.
-- Primary attributes (Strength, Stamina, Armor, ...) are deliberately
-- left untouched -- only the specific Blizzard setters below are hooked.
--
-- FRAME REUSE: the stats pane pools its rows, so a frame that shows
-- Haste in one refresh can show Stamina in the next. Anything we add to
-- a frame would "leak" onto whatever stat it shows later. Guarded by a
-- per-refresh sweep: after each batch of setter calls, every row we
-- touched that was NOT refreshed as an enhancement this pass is restored
-- to Blizzard's layout. The sweep is scheduled with C_Timer (next frame)
-- so it runs after the whole refresh without needing to know the name of
-- the function that drives it.
--
-- SECRET VALUES (12.0): combat-rating / percentage APIs (and the raw
-- numericValue derived from them) are *secret* numbers WHILE IN COMBAT;
-- tainted code may not compare, math, tostring or concatenate them.
-- The player's own values are only secret in combat, so we bail before
-- touching anything in combat, issecretvalue-guard every read, and run
-- the rebuild under pcall. In combat the rows freeze (the percentage
-- still updates live -- Blizzard owns it); after combat the pane is
-- refreshed.

local _, ns = ...

-- One entry per Enhancement row. fns: candidate Blizzard setter names
-- (crit has been spelled both ways); cr: CR_* constant name; color:
-- key into Config.STAT_COLORS / Config.TERT_COLORS.
local STAT_RATINGS = {
    { fns = { "PaperDollFrame_SetCritChance",
              "PaperDollFrame_SetCriticalChance" },
      cr = "CR_CRIT_SPELL",              color = "crit" },
    { fns = { "PaperDollFrame_SetHaste" },
      cr = "CR_HASTE_SPELL",             color = "haste" },
    { fns = { "PaperDollFrame_SetMastery" },
      cr = "CR_MASTERY",                 color = "mastery" },
    { fns = { "PaperDollFrame_SetVersatility" },
      cr = "CR_VERSATILITY_DAMAGE_DONE", color = "versatility" },
    { fns = { "PaperDollFrame_SetLifesteal" },
      cr = "CR_LIFESTEAL",               color = "leech" },
    { fns = { "PaperDollFrame_SetAvoidance" },
      cr = "CR_AVOIDANCE",               color = "avoidance" },
    { fns = { "PaperDollFrame_SetSpeed" },
      cr = "CR_SPEED",                   color = "speed" },
}

local function InCombat()
    return InCombatLockdown() or UnitAffectingCombat("player")
end

-- v if it is a plain, non-secret number; nil otherwise.
local function PlainNumber(v)
    if issecretvalue(v) then return nil end
    if type(v) ~= "number" then return nil end
    return v
end

-- "ffRRGGBB" escape for a stat color, white if the key is unknown.
local function ColorCode(key)
    local cfg = ns.Config
    local c = (cfg.STAT_COLORS and cfg.STAT_COLORS[key])
        or (cfg.TERT_COLORS and cfg.TERT_COLORS[key])
    if not c then return "ffffffff" end
    return string.format("ff%02x%02x%02x",
        math.floor(c[1] * 255 + 0.5),
        math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

-- The leading integer of a FontString's text, color escapes stripped.
local function ShownInt(fs)
    local s = fs:GetText()
    if type(s) ~= "string" then return nil end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return tonumber(s:match("(%d+)"))
end

-- Remember the percentage FontString's original anchor(s) once, so we
-- can shift them and put them back. false marks a value we leave alone.
local function CaptureOrig(statFrame)
    if statFrame.dodoOrig ~= nil then return statFrame.dodoOrig end
    local n = statFrame.Value:GetNumPoints()
    if not n or n == 0 then
        statFrame.dodoOrig = false
        return false
    end
    local pts = {}
    for i = 1, n do
        pts[i] = { statFrame.Value:GetPoint(i) }
    end
    statFrame.dodoOrig = pts
    return pts
end

-- Re-anchor a region to captured points, every x shifted by dx.
local function AnchorPoints(region, pts, dx)
    region:ClearAllPoints()
    local parent = region:GetParent()
    for _, p in ipairs(pts) do
        region:SetPoint(p[1], p[2] or parent, p[3], (p[4] or 0) + dx, p[5] or 0)
    end
end

-- Rows we have given a rating column, for the reuse sweep.
local touched = {}
local gen = 0
local function Track(f)
    if not f.dodoTracked then
        f.dodoTracked = true
        touched[#touched + 1] = f
    end
end

-- Undo our enhancement layout: hide the rating, put the percentage back.
-- (The reformatted percentage text and the recolored item level both
-- self-heal -- Blizzard rewrites them on the next refresh.)
local function RestoreFrame(f)
    if f.dodoRating then f.dodoRating:Hide() end
    if f.dodoOrig and f.dodoOrig ~= false and f.Value then
        AnchorPoints(f.Value, f.dodoOrig, 0)
    end
    f.dodoStamp = nil
end

-- Restore any tracked row not refreshed as an enhancement this batch
-- (its frame now shows another stat). Scheduled once per frame.
local sweepScheduled = false
local function Sweep()
    sweepScheduled = false
    for _, f in ipairs(touched) do
        if f.dodoStamp ~= gen then
            RestoreFrame(f)
        end
    end
    gen = gen + 1
end
local function ScheduleSweep()
    if sweepScheduled then return end
    sweepScheduled = true
    C_Timer.After(0, Sweep)
end

-- Lay out one enhancement row. Caller guarantees we are out of combat.
local function ApplyColumns(statFrame, crIndex, color)
    local orig = CaptureOrig(statFrame)
    if not orig then return end

    local rating = PlainNumber(GetCombatRating(crIndex))
    if rating == nil or rating < 0 then
        RestoreFrame(statFrame) -- nothing valid; keep Blizzard's layout
        return
    end

    -- percentage to one decimal, but ONLY when Blizzard's raw value
    -- matches the integer it just displayed -- otherwise leave the text
    -- alone, so an unexpected numericValue can never show a wrong number
    local shown = ShownInt(statFrame.Value)
    local pct = PlainNumber(statFrame.numericValue)
    if pct and shown and math.abs(math.floor(pct + 0.5) - shown) <= 1 then
        statFrame.Value:SetText(string.format("%.1f%%", pct))
    end

    -- the rating text -- the only line that touches the rating number,
    -- so nothing below runs if it ever threw
    local text = "|c" .. ColorCode(color) .. "(" .. rating .. ")|r"

    local fs = statFrame.dodoRating
    if not fs then
        fs = statFrame:CreateFontString(nil, "OVERLAY")
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
        statFrame.dodoRating = fs
    end
    local fo = statFrame.Value:GetFontObject()
    if fo then
        fs:SetFontObject(fo)
    else
        local font, size, flags = statFrame.Value:GetFont()
        if font then fs:SetFont(font, size, flags) end
    end
    fs:SetJustifyH("RIGHT")
    fs:SetText(text)

    -- two columns: percentage slides left, rating sits at the value's
    -- original right edge
    local colW = ns.Config.STAT_RATING_COL_W or 50
    AnchorPoints(statFrame.Value, orig, -colW)
    AnchorPoints(fs, orig, 0)
    fs:Show()

    statFrame.dodoStamp = gen
    Track(statFrame)
end

-- Recolor + decimal the Item Level value. No column shift, and the color
-- is embedded in the text (see below) rather than set with SetTextColor,
-- so a reused pooled row self-heals when Blizzard rewrites it. Hence this
-- never needs the sweep.
local function ApplyItemLevel(statFrame)
    if type(GetAverageItemLevel) ~= "function" then return end
    local shown = ShownInt(statFrame.Value)

    local overall, equipped = GetAverageItemLevel()
    overall, equipped = PlainNumber(overall), PlainNumber(equipped)

    -- pick the precise value matching the integer Blizzard displayed
    local ilvl
    if shown and equipped and math.abs(math.floor(equipped + 0.5) - shown) <= 1 then
        ilvl = equipped
    elseif shown and overall and math.abs(math.floor(overall + 0.5) - shown) <= 1 then
        ilvl = overall
    else
        ilvl = equipped or overall
    end
    if not ilvl then return end

    -- embed the gradient color in the text (not SetTextColor) so that if
    -- this pooled row is later reused for another stat, Blizzard's text
    -- rewrite wipes our color with it -- nothing to leak, nothing to undo
    local r, g, b = ns.ColorForItemLevel(math.floor(ilvl + 0.5))
    local code = string.format("ff%02x%02x%02x",
        math.floor((r or 1) * 255 + 0.5),
        math.floor((g or 1) * 255 + 0.5),
        math.floor((b or 1) * 255 + 0.5))
    statFrame.Value:SetText("|c" .. code .. string.format("%.1f", ilvl) .. "|r")
end

local function OnStatSet(crIndex, color, statFrame, unit)
    if unit and unit ~= "player" then return end
    if not statFrame or not statFrame.Value then return end
    if InCombat() then return end -- freeze; never read a secret rating
    ScheduleSweep()               -- a refresh happened; clean reused rows after
    if not ns.IsEnabled("showStatRatings") then
        RestoreFrame(statFrame)
        return
    end
    if type(GetCombatRating) ~= "function" then return end
    pcall(ApplyColumns, statFrame, crIndex, color)
end

local function OnItemLevel(statFrame, unit)
    if unit and unit ~= "player" then return end
    if not statFrame or not statFrame.Value then return end
    if InCombat() then return end
    ScheduleSweep()
    if not ns.IsEnabled("showStatRatings") then return end -- Blizzard redraw restores it
    pcall(ApplyItemLevel, statFrame)
end

local hooked = false
function ns.SetupStatRatings()
    if hooked then return end
    hooked = true

    for _, entry in ipairs(STAT_RATINGS) do
        local crIndex = _G[entry.cr]
        if type(crIndex) == "number" then
            for _, fnName in ipairs(entry.fns) do
                if type(_G[fnName]) == "function" then
                    local color = entry.color
                    hooksecurefunc(fnName, function(statFrame, unit)
                        OnStatSet(crIndex, color, statFrame, unit)
                    end)
                    break -- only the first existing candidate
                end
            end
        end
    end

    if type(_G.PaperDollFrame_SetItemLevel) == "function" then
        hooksecurefunc("PaperDollFrame_SetItemLevel", OnItemLevel)
    end
end

-- Redraw the pane (out of combat) so everything updates after combat
-- ends or the toggle flips. Safe no-op if the function or the character
-- frame is missing, or if still in combat.
function ns.RefreshStatRatings()
    if InCombat() then return end
    if not (CharacterFrame and CharacterFrame:IsShown()) then return end
    if type(PaperDollFrame_UpdateStats) == "function" then
        pcall(PaperDollFrame_UpdateStats)
    end
end
