-- DodoItemLevelOverlay - Gradient.lua
-- Raider.IO style color ramp applied to item levels.
--
-- The anchors below are sampled from the Raider.IO Mythic+ score
-- gradient: white at the bottom, peak green at the uncommon
-- threshold, rare blue, epic purple, then pink rising into
-- legendary orange at the cap. Positions are normalized 0..1.
-- The item level window from Config.lua is mapped onto that range
-- and colors between anchors are linearly interpolated, so the
-- result is a smooth ramp rather than a handful of fixed tiers.

local _, ns = ...

-- { position, r, g, b }, sorted ascending by position.
local ANCHORS = {
    { 0.000, 1.00, 1.00, 1.00 }, -- white
    { 0.098, 0.90, 1.00, 0.85 },
    { 0.196, 0.79, 1.00, 0.71 },
    { 0.294, 0.67, 1.00, 0.56 },
    { 0.393, 0.52, 1.00, 0.40 },
    { 0.466, 0.37, 1.00, 0.26 },
    { 0.534, 0.18, 1.00, 0.08 }, -- peak green (uncommon tier)
    { 0.563, 0.31, 0.90, 0.33 },
    { 0.599, 0.37, 0.77, 0.50 },
    { 0.633, 0.36, 0.65, 0.64 }, -- teal
    { 0.663, 0.30, 0.55, 0.75 },
    { 0.687, 0.19, 0.48, 0.83 },
    { 0.706, 0.00, 0.44, 0.87 }, -- rare blue
    { 0.729, 0.35, 0.39, 0.89 },
    { 0.758, 0.53, 0.31, 0.91 },
    { 0.785, 0.64, 0.21, 0.93 }, -- epic purple
    { 0.815, 0.74, 0.24, 0.82 },
    { 0.844, 0.81, 0.29, 0.71 },
    { 0.880, 0.87, 0.34, 0.58 }, -- pink
    { 0.909, 0.92, 0.38, 0.46 },
    { 0.939, 0.95, 0.42, 0.35 },
    { 0.968, 0.98, 0.47, 0.21 },
    { 1.000, 1.00, 0.50, 0.00 }, -- legendary orange
}

-- Returns r, g, b, a for the given item level.
function ns.ColorForItemLevel(ilvl)
    if type(ilvl) ~= "number" then
        return 1, 1, 1, 1
    end

    local cfg = ns.Config
    local minIlvl = cfg.GRADIENT_MIN_ILVL
    local span = cfg.GRADIENT_MAX_ILVL - minIlvl

    local t
    if span <= 0 then
        t = (ilvl >= minIlvl) and 1 or 0
    else
        t = (ilvl - minIlvl) / span
    end

    if t <= 0 then
        local a = ANCHORS[1]
        return a[2], a[3], a[4], 1
    end
    if t >= 1 then
        local a = ANCHORS[#ANCHORS]
        return a[2], a[3], a[4], 1
    end

    for i = 2, #ANCHORS do
        local hi = ANCHORS[i]
        if t <= hi[1] then
            local lo = ANCHORS[i - 1]
            local f = (t - lo[1]) / (hi[1] - lo[1])
            return lo[2] + (hi[2] - lo[2]) * f,
                   lo[3] + (hi[3] - lo[3]) * f,
                   lo[4] + (hi[4] - lo[4]) * f,
                   1
        end
    end

    local a = ANCHORS[#ANCHORS]
    return a[2], a[3], a[4], 1
end
