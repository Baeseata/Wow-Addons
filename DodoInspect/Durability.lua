-- DodoInspect - Durability.lua
-- Average equipment durability readout, merged with the item level on
-- the item-level row of the character stats pane. Blizzard's separate
-- item level number is hidden and replaced by one centered line --
-- "286.1 | 88%" -- so the item level and the durability percent share a
-- single font size. The durability is the mean of the per-slot
-- durability percentages across every equipped item that has durability
-- (armor and weapons; neck, rings, trinkets, cloak and shirt have none
-- and are skipped). The item level is gold; the percent is colored red
-- (low) through yellow to green (full) for an at-a-glance repair check.

local _, ns = ...

-- Inventory slots worth checking. Slots without durability return nil
-- and are skipped, so the list only needs to cover the ones that can
-- have it: 1 head, 3 shoulder, 5 chest, 6 waist, 7 legs, 8 feet,
-- 9 wrist, 10 hands, 16 main hand, 17 off hand.
local DURABILITY_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17 }

local text

local function ItemLevelFrame()
    return CharacterStatsPane and CharacterStatsPane.ItemLevelFrame or nil
end

local function EnsureText()
    if text then return text end

    -- Parent to the item level frame so the line shares its row and
    -- hides with the paper doll tab; fall back if absent.
    local parent = ItemLevelFrame() or CharacterStatsPane or PaperDollFrame or CharacterFrame
    if not parent then return nil end

    local cfg = ns.Config
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetJustifyH("CENTER")
    fs:SetTextColor(1, 1, 1, 1) -- the " | " separator (per-part colors are inline)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetMaxLines then fs:SetMaxLines(1) end
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", parent, "CENTER", cfg.DURABILITY_X, cfg.DURABILITY_Y)

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

local function ShowBlizzardValue(show)
    local ilf = ItemLevelFrame()
    if ilf and ilf.Value then
        if show then ilf.Value:Show() else ilf.Value:Hide() end
    end
end

function ns.UpdateDurability()
    -- Disabled, or we cannot read the data we need: leave Blizzard's own
    -- item level number visible and hide our combined line.
    if not ns.IsEnabled("showDurability") then
        if text then text:Hide() end
        ShowBlizzardValue(true)
        return
    end

    local fs = EnsureText()
    if not fs then return end

    local ilf = ItemLevelFrame()
    local ilvlText = ilf and ilf.Value and ilf.Value:GetText()
    local hasIlvl = type(ilvlText) == "string" and ilvlText ~= ""

    local pct
    local ok, result = pcall(AverageDurability)
    if ok then pct = result end

    if not pct or not hasIlvl then
        fs:Hide()
        ShowBlizzardValue(true)
        return
    end

    -- "<ilvl gold> <sep> <pct colored>", a space on each side of the
    -- separator; "%%" is a literal percent sign. The separator is in the
    -- font string's own (white) color since it sits outside the inline
    -- color codes.
    local pctInt = math.floor(pct + 0.5)
    local r, g, b = ColorForPct(pct)
    local durHex = string.format("%02x%02x%02x",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
    local sep = ns.Config.DURABILITY_SEPARATOR or "/"
    local s = string.format("|cffffd200%s|r %s |cff%s%d%%|r", ilvlText, sep, durHex, pctInt)

    local cfg = ns.Config
    local size = cfg.DURABILITY_FONT_SIZE
    ns.SetOverlayFont(fs, size, cfg.DURABILITY_FONT_FLAGS)
    fs:SetText(s)

    -- safety only: the line is short (numbers), but never let it exceed
    -- the row width
    local rowW = (ilf and ilf:GetWidth()) or cfg.DURABILITY_MAX_WIDTH
    if not rowW or rowW < 20 then rowW = cfg.DURABILITY_MAX_WIDTH end
    while size > cfg.DURABILITY_MIN_FONT_SIZE and fs:GetStringWidth() > rowW - 6 do
        size = size - 1
        ns.SetOverlayFont(fs, size, cfg.DURABILITY_FONT_FLAGS)
    end

    -- replace Blizzard's plain item level number with our merged line
    ShowBlizzardValue(false)
    fs:Show()
end

-- Re-merge whenever Blizzard rewrites the item level number (frame open,
-- gear change). Guarded to the player's stats pane so it never touches
-- the inspect window's item level.
if type(PaperDollFrame_SetItemLevel) == "function" then
    hooksecurefunc("PaperDollFrame_SetItemLevel", function(statFrame, unit)
        if statFrame and statFrame ~= ItemLevelFrame() then return end
        if unit and unit ~= "player" then return end
        ns.UpdateDurability()
    end)
end
