-- DodoInspect - Gradient.lua
-- Raider.IO style color ramp applied to item levels.
--
-- The body of the ramp is sampled from the Raider.IO Mythic+ score
-- gradient: white at the bottom, peak green at the uncommon
-- threshold, rare blue, epic purple, pink, then legendary orange.
-- On top of that the last ~12 percent of the window rises through
-- gold into hot red, so the final few item levels of a season get
-- their own clearly distinct steps instead of all saturating into
-- the same orange. Positions are normalized 0..1; the item level
-- window from Config.lua is mapped onto that range and colors
-- between anchors are linearly interpolated.

local _, ns = ...

-- { position, r, g, b }, sorted ascending by position.
local ANCHORS = {
    { 0.000, 1.00, 1.00, 1.00 }, -- white
    { 0.086, 0.90, 1.00, 0.85 },
    { 0.172, 0.79, 1.00, 0.71 },
    { 0.259, 0.67, 1.00, 0.56 },
    { 0.346, 0.52, 1.00, 0.40 },
    { 0.410, 0.37, 1.00, 0.26 },
    { 0.470, 0.18, 1.00, 0.08 }, -- peak green (uncommon tier)
    { 0.495, 0.31, 0.90, 0.33 },
    { 0.527, 0.37, 0.77, 0.50 },
    { 0.557, 0.36, 0.65, 0.64 }, -- teal
    { 0.583, 0.30, 0.55, 0.75 },
    { 0.605, 0.19, 0.48, 0.83 },
    { 0.621, 0.00, 0.44, 0.87 }, -- rare blue
    { 0.642, 0.35, 0.39, 0.89 },
    { 0.667, 0.53, 0.31, 0.91 },
    { 0.691, 0.64, 0.21, 0.93 }, -- epic purple
    { 0.717, 0.74, 0.24, 0.82 },
    { 0.743, 0.81, 0.29, 0.71 },
    { 0.774, 0.87, 0.34, 0.58 }, -- pink
    { 0.800, 0.92, 0.38, 0.46 },
    { 0.826, 0.95, 0.42, 0.35 },
    { 0.852, 0.98, 0.47, 0.21 },
    { 0.880, 1.00, 0.50, 0.00 }, -- legendary orange
    { 0.940, 1.00, 0.80, 0.08 }, -- gold
    { 1.000, 1.00, 0.20, 0.12 }, -- hot red (season top end)
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
