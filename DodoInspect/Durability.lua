-- DodoInspect - Durability.lua
-- Average equipment durability readout, shown at the bottom of the
-- character stats pane. One number: the mean of the per-slot durability
-- percentages across every equipped item that has durability (armor
-- and weapons; neck, rings, trinkets, cloak and shirt have none and
-- are skipped automatically). Colored red (low) through yellow to
-- green (full) for an at-a-glance repair check.

local _, ns = ...

-- Inventory slots worth checking. Slots without durability return nil
-- and are skipped, so the list only needs to cover the ones that can
-- have it: 1 head, 3 shoulder, 5 chest, 6 waist, 7 legs, 8 feet,
-- 9 wrist, 10 hands, 16 main hand, 17 off hand.
local DURABILITY_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17 }

local text

local function EnsureText()
    if text then return text end

    -- Anchor to the stats pane (the middle column) so the readout sits
    -- in the empty space below the enhancement stats and hides with the
    -- paper doll tab; fall back if that frame is absent.
    local parent = _G.CharacterStatsPane or PaperDollFrame or CharacterFrame
    if not parent then return nil end

    local cfg = ns.Config
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns.SetOverlayFont(fs, cfg.DURABILITY_FONT_SIZE, cfg.DURABILITY_FONT_FLAGS)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetPoint(cfg.DURABILITY_POINT, parent, cfg.DURABILITY_POINT,
        cfg.DURABILITY_X, cfg.DURABILITY_Y)

    text = fs
    return fs
end

-- Smooth ramp: red at 0%, yellow at 50%, green at 100%.
local function ColorForPct(pct)
    if pct <= 0 then return 1.00, 0.12, 0.12 end
    if pct >= 100 then return 0.30, 1.00, 0.30 end
    if pct < 50 then
        local f = pct / 50
        return 1.00, 0.12 + 0.88 * f, 0.12
    end
    local f = (pct - 50) / 50
    return 1.00 - 0.70 * f, 1.00, 0.12 + 0.18 * f
end

-- Mean of the per-slot durability percentages, or nil when nothing
-- equipped has durability. The pcall is precautionary: a player's own
-- gear is never a secret value, but it keeps any future surprise from
-- erroring the character frame.
local function AverageDurability()
    if type(GetInventoryItemDurability) ~= "function" then return nil end

    local sum, count = 0, 0
    for _, slot in ipairs(DURABILITY_SLOTS) do
        local cur, max = GetInventoryItemDurability(slot)
        if type(cur) == "number" and type(max) == "number" and max > 0 then
            sum = sum + cur / max
            count = count + 1
        end
    end

    if count == 0 then return nil end
    return sum / count * 100
end

function ns.UpdateDurability()
    if not ns.IsEnabled("showDurability") then
        if text then text:Hide() end
        return
    end

    local fs = EnsureText()
    if not fs then return end

    local pct
    local ok, result = pcall(AverageDurability)
    if ok then pct = result end

    if not pct then
        fs:Hide()
        return
    end

    local cfg = ns.Config
    ns.SetOverlayFont(fs, cfg.DURABILITY_FONT_SIZE, cfg.DURABILITY_FONT_FLAGS)
    fs:SetText(((ns.L and ns.L.durability) or "Durability")
        .. " " .. math.floor(pct + 0.5) .. "%")
    fs:SetTextColor(ColorForPct(pct))
    fs:Show()
end
