-- DodoBricks - Geometry
-- 棋盘几何常量。坐标系与 DodoPool 同款:board 局部像素,原点左下,+x 右 +y 上。
-- 网格:COLS 列 x ROWS 行,row=1 是最底下一行砖(紧贴发射线),row=ROWS 是顶部刷新行。
-- 发射条(launch strip)在 y ∈ [0, FLOOR),球的"地面"= FLOOR(球心到达即算落地)。

local DBR = _G.DodoBricks or {}
_G.DodoBricks = DBR

local geo = {}
DBR.geo = geo

geo.COLS  = 7      -- 列数(经典 Ballz 布局)
geo.ROWS  = 9      -- 可视砖行数;砖被压到 row 0(进发射条)= 游戏结束
geo.CELL  = 56     -- 格子边长(px)
geo.FLOOR = 30     -- 发射条高度;球飞行区下边界 y = FLOOR

geo.BOARD_W = geo.COLS * geo.CELL                -- 392
geo.BOARD_H = geo.FLOOR + geo.ROWS * geo.CELL    -- 534

geo.BALL_R   = 7    -- 弹球半径
geo.ITEM_R   = 10   -- "+1 球"道具的拾取半径(视觉略小)
geo.BRICK_PAD = 3   -- 砖视觉内缩(碰撞用整格,视觉留缝;相邻砖之间不可穿缝)

-- 格子 (col 0..COLS-1, row 1..ROWS) -> 碰撞 AABB(整格)
function geo.CellRect(col, row)
    local x0 = col * geo.CELL
    local y0 = geo.FLOOR + (row - 1) * geo.CELL
    return x0, y0, x0 + geo.CELL, y0 + geo.CELL
end

-- 格子中心
function geo.CellCenter(col, row)
    local x0, y0 = geo.CellRect(col, row)
    return x0 + geo.CELL / 2, y0 + geo.CELL / 2
end

-- 球心 (x,y) 落在哪个格(row 可能 <1 或 >ROWS,调用方自己判界)
function geo.CellAt(x, y)
    local col = math.floor(x / geo.CELL)
    local row = math.floor((y - geo.FLOOR) / geo.CELL) + 1
    return col, row
end
