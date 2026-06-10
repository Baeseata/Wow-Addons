-- DodoBricks - Geometry
-- Board geometry constants. Same coordinate system as DodoPool: board local pixels, origin bottom-left, +x right +y up.
-- Grid: COLS columns x ROWS rows. row=1 is the bottom row of bricks (against the launch line), row=ROWS is the top spawn row.
-- The launch strip is at y in [0, FLOOR); the ball's "floor" = FLOOR (a ball center reaching it counts as landed).

local DBR = _G.DodoBricks or {}
_G.DodoBricks = DBR

local geo = {}
DBR.geo = geo

geo.COLS  = 7      -- number of columns (classic Ballz layout)
geo.ROWS  = 9      -- visible brick rows; a brick pushed to row 0 (into the launch strip) = game over
geo.CELL  = 56     -- cell side length (px)
geo.FLOOR = 30     -- launch strip height; the ball flight region's lower bound y = FLOOR

geo.BOARD_W = geo.COLS * geo.CELL                -- 392
geo.BOARD_H = geo.FLOOR + geo.ROWS * geo.CELL    -- 534

geo.BALL_R   = 7    -- ball radius
geo.ITEM_R   = 10   -- pickup radius of the "+1 ball" item (slightly smaller visually)
geo.BRICK_PAD = 3   -- brick visual inset (collision uses the full cell, the gap is only visual; adjacent bricks have no passable seam)

-- cell (col 0..COLS-1, row 1..ROWS) -> collision AABB (full cell)
function geo.CellRect(col, row)
    local x0 = col * geo.CELL
    local y0 = geo.FLOOR + (row - 1) * geo.CELL
    return x0, y0, x0 + geo.CELL, y0 + geo.CELL
end

-- cell center
function geo.CellCenter(col, row)
    local x0, y0 = geo.CellRect(col, row)
    return x0 + geo.CELL / 2, y0 + geo.CELL / 2
end

-- which cell does ball center (x,y) land in (row may be <1 or >ROWS, the caller checks bounds itself)
function geo.CellAt(x, y)
    local col = math.floor(x / geo.CELL)
    local row = math.floor((y - geo.FLOOR) / geo.CELL) + 1
    return col, row
end
