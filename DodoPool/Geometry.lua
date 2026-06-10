-- DodoPool - Geometry
-- Table geometry + coordinate constants. Everything uses "felt local pixel coordinates":
-- origin = bottom-left corner of the felt, +x to the right (long axis), +y up. Render and physics share this system.

local DP = _G.DodoPool or {}
_G.DodoPool = DP

local geo = {}
DP.geo = geo

-- ============================================================
-- Size constants (pixels). A 9-ball table has a 2:1 aspect ratio.
-- ============================================================
geo.FELT_W   = 860      -- felt length (long axis)
geo.FELT_H   = 430      -- felt width
geo.RAIL     = 32       -- rail (wooden frame) thickness
geo.BALL_R   = 13       -- ball radius
geo.POCKET_R = 22       -- pocket radius (visual + pocketing test)

-- Key positions (felt local coordinates)
geo.CENTER_Y = geo.FELT_H / 2
geo.FOOT_X   = geo.FELT_W * 0.72   -- rack apex (1-ball) x, toward the right
geo.HEAD_X   = geo.FELT_W * 0.22   -- break line (cue ball) x, toward the left

-- ============================================================
-- 6 pockets: 4 corners + 2 long-side midpoints
-- ============================================================
function geo.Pockets()
    local W, H = geo.FELT_W, geo.FELT_H
    return {
        { x = 0,     y = 0 },   -- bottom-left
        { x = W / 2, y = 0 },   -- bottom-middle
        { x = W,     y = 0 },   -- bottom-right
        { x = 0,     y = H },   -- top-left
        { x = W / 2, y = H },   -- top-middle
        { x = W,     y = H },   -- top-right
    }
end

-- ============================================================
-- 9-ball diamond rack: the apex (1-ball) faces left toward the cue ball, the 9-ball sits dead center.
-- Columns of 1,2,3,2,1 = 9 positions total. Returns a list of {x,y} (felt coordinates).
-- Convention: pos[1] = apex (holds the 1-ball), pos[5] = diamond center (holds the 9-ball).
-- ============================================================
function geo.RackPositions()
    local r  = geo.BALL_R
    local d  = 2 * r            -- center-to-center distance when balls touch
    local dx = d * 0.866        -- horizontal column step for a tight triangle rack (cos30)
    local cx, cy = geo.FOOT_X, geo.CENTER_Y

    -- per-column y offset relative to the center line (unit = d)
    local cols = {
        { 0 },               -- col0 apex
        { -0.5, 0.5 },       -- col1
        { -1, 0, 1 },        -- col2 (the middle one = diamond center)
        { -0.5, 0.5 },       -- col3
        { 0 },               -- col4 tail
    }

    local pos = {}
    for ci, ys in ipairs(cols) do
        local x = cx + (ci - 1) * dx
        for _, yo in ipairs(ys) do
            pos[#pos + 1] = { x = x, y = cy + yo * d }
        end
    end
    return pos   -- pos[1]=apex, pos[5]=center (9-ball)
end

-- Numeric clamp (prefer the shared library's; fall back to local if absent)
function geo.Clamp(x, lo, hi)
    if _G.Dodo and _G.Dodo.Clamp then return _G.Dodo.Clamp(x, lo, hi) end
    x = tonumber(x) or lo
    if x < lo then return lo elseif x > hi then return hi end
    return x
end
