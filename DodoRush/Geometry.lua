-- DodoRush - Geometry
-- Track constants. Coordinate system: origin = bottom-left of the road, +x right, +y up (Dodo series convention).
-- Pure 2D top-down: the world scrolls downward, the crowd stays at CROWD_Y and can only strafe.

local DR = _G.DodoRush or {}
_G.DodoRush = DR

local geo = {}
DR.geo = geo

geo.ROAD_W  = 392    -- road width (same as the DodoBricks board, window 436x624)
geo.ROAD_H  = 534    -- road height
geo.CROWD_Y = 120    -- fixed crowd-center height (from the bottom edge)
geo.EDGE    = 40     -- horizontal reach of the crowd center: [EDGE, ROAD_W-EDGE]
geo.CURB    = 6      -- left/right curb width

-- Gates: one row of two panels, the center seam splits left/right
geo.GATE_GAP = 8                                       -- margin and center seam
geo.GATE_W   = (geo.ROAD_W - 3 * geo.GATE_GAP) / 2     -- = 184
geo.GATE_H   = 64
geo.GATE_XL  = geo.GATE_GAP + geo.GATE_W / 2           -- left gate center x = 100
geo.GATE_XR  = geo.ROAD_W - geo.GATE_GAP - geo.GATE_W / 2  -- right gate center x = 292
