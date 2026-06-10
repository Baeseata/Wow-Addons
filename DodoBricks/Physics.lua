-- DodoBricks - Physics
-- 弹球飞行:匀速、无重力、无摩擦、完全弹性反弹;球与球不互撞(本类游戏惯例,也省性能)。
-- 碰撞统一用"最近点法":求球心到形状(方=AABB clamp,三角=三条边最近点)的最近点,
--   距离 < 半径即碰,法线 = 球心-最近点,速度沿法线镜像反射 + 位置推出。角点自然正确。
-- 砖在网格上 => 每子步只查球所在格 3x3 邻域,O(1),球上百颗不卡。
-- 子步进:每步位移 ≤ SUBSTEP_LEN(< 球半径),防穿模(DodoPool 同思路)。
-- 坐标:board 局部像素,原点左下。

local DBR = _G.DodoBricks or {}
_G.DodoBricks = DBR

local Physics = {}
DBR.Physics = Physics

local geo = DBR.geo

-- 可调常量
Physics.SPEED   = 900       -- 球速(px/s,恒定)
local SUBSTEP_LEN = 6       -- 每子步最大位移(px,需 < BALL_R)
local MAX_DT      = 0.05    -- 单帧最大推进(防掉帧时一口气穿模)

-- 防水平死弹:|vy| 低于 FLAT_VY 累计 FLAT_T 秒后,持续把球往当前纵向(近零则向下)拐,
-- 直到 |vy| 超过 FLAT_EXIT 才停手。治"最后一颗球横着弹半天不下来"。
local FLAT_VY   = 35
local FLAT_T    = 3.5
local FLAT_EXIT = 140
local FLAT_KICK = 220       -- vy 修正速率(px/s 每秒)

-- ------------------------------------------------------------
-- 形状最近点
-- ------------------------------------------------------------
local function ClosestOnSegment(px, py, ax, ay, bx, by)
    local abx, aby = bx - ax, by - ay
    local len2 = abx * abx + aby * aby
    if len2 <= 0 then return ax, ay end
    local t = ((px - ax) * abx + (py - ay) * aby) / len2
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return ax + abx * t, ay + aby * t
end

-- 三角形三个顶点(直角在 orient 角;整格碰撞,留缝只是视觉)
local function TriVerts(x0, y0, x1, y1, orient)
    if orient == "BL" then return x0, y0, x1, y0, x0, y1
    elseif orient == "BR" then return x0, y0, x1, y0, x1, y1
    elseif orient == "TL" then return x0, y0, x1, y1, x0, y1
    else return x1, y0, x1, y1, x0, y1 end   -- TR
end

-- 球心 P 在三角形内?(AABB 内 + 斜边实心侧)
local function InsideTri(px, py, x0, y0, x1, y1, orient)
    if px < x0 or px > x1 or py < y0 or py > y1 then return false end
    local u, v, C = px - x0, py - y0, x1 - x0
    if orient == "BL" then return u + v <= C
    elseif orient == "BR" then return u >= v
    elseif orient == "TL" then return u <= v
    else return u + v >= C end   -- TR
end

-- 球心到砖的最近点。返回 cpx, cpy, inside
local function ClosestOnBrick(brick, px, py)
    local x0, y0, x1, y1 = geo.CellRect(brick.col, brick.row)
    if brick.shape ~= "tri" then
        local cx = px < x0 and x0 or (px > x1 and x1 or px)
        local cy = py < y0 and y0 or (py > y1 and y1 or py)
        local inside = (cx == px and cy == py)
        return cx, cy, inside
    end
    if InsideTri(px, py, x0, y0, x1, y1, brick.orient) then
        return px, py, true
    end
    local ax, ay, bx, by, cx, cy = TriVerts(x0, y0, x1, y1, brick.orient)
    local best2, bpx, bpy
    local function edge(ex1, ey1, ex2, ey2)
        local qx, qy = ClosestOnSegment(px, py, ex1, ey1, ex2, ey2)
        local d2 = (px - qx) ^ 2 + (py - qy) ^ 2
        if not best2 or d2 < best2 then best2, bpx, bpy = d2, qx, qy end
    end
    edge(ax, ay, bx, by); edge(bx, by, cx, cy); edge(cx, cy, ax, ay)
    return bpx, bpy, false
end

-- ------------------------------------------------------------
-- 单子步:推进一颗球。ctx = { grid, items, OnBrickHit, OnItemHit, OnBallLand }
-- ------------------------------------------------------------
local function StepBall(ctx, b, h)
    local r = geo.BALL_R
    local W, H, FLOOR = geo.BOARD_W, geo.BOARD_H, geo.FLOOR

    b.x = b.x + b.vx * h
    b.y = b.y + b.vy * h

    -- 墙(左右顶)
    if b.x < r then b.x = r; b.vx = math.abs(b.vx)
    elseif b.x > W - r then b.x = W - r; b.vx = -math.abs(b.vx) end
    if b.y > H - r then b.y = H - r; b.vy = -math.abs(b.vy) end

    -- 落地(球心到 FLOOR 且向下)=> 本回合该球结束
    if b.y <= FLOOR and b.vy < 0 then
        b.y = FLOOR
        b.flying = false
        if ctx.OnBallLand then ctx.OnBallLand(b) end
        return
    end

    -- 砖:3x3 邻域取穿透最深的一块结算(下一子步自然处理相邻第二块)
    local grid = ctx.grid
    local col, row = geo.CellAt(b.x, b.y)
    local best, bcp_x, bcp_y, bdepth
    for rr = row - 1, row + 1 do
        local line = grid[rr]
        if line then
            for cc = col - 1, col + 1 do
                local brick = line[cc]
                if brick then
                    local cpx, cpy, inside = ClosestOnBrick(brick, b.x, b.y)
                    local d2 = (b.x - cpx) ^ 2 + (b.y - cpy) ^ 2
                    if inside or d2 < r * r then
                        local depth = inside and r or (r - math.sqrt(d2))
                        if not best or depth > bdepth then
                            best, bcp_x, bcp_y, bdepth = brick, cpx, cpy, depth
                        end
                    end
                end
            end
        end
    end
    if best then
        local nx, ny
        local dx, dy = b.x - bcp_x, b.y - bcp_y
        local d = math.sqrt(dx * dx + dy * dy)
        if d > 0.001 then
            nx, ny = dx / d, dy / d
        else
            -- 球心贴在/进了砖里(理论上子步够小不会发生):沿来向退出
            local sp = math.sqrt(b.vx * b.vx + b.vy * b.vy)
            if sp > 0 then nx, ny = -b.vx / sp, -b.vy / sp else nx, ny = 0, 1 end
        end
        b.x = bcp_x + nx * (r + 0.5)
        b.y = bcp_y + ny * (r + 0.5)
        local dot = b.vx * nx + b.vy * ny
        if dot < 0 then
            b.vx = b.vx - 2 * dot * nx
            b.vy = b.vy - 2 * dot * ny
        end
        if ctx.OnBrickHit then ctx.OnBrickHit(best) end
    end

    -- 道具(穿过即触发,不反弹;+1 球吃掉即除,激光/炸弹常驻整回合由 Game 去重)
    local items = ctx.items
    if items and #items > 0 then
        local R2 = (r + geo.ITEM_R) ^ 2
        for i = #items, 1, -1 do
            local it = items[i]
            local ix, iy = geo.CellCenter(it.col, it.row)
            if (b.x - ix) ^ 2 + (b.y - iy) ^ 2 <= R2 then
                if ctx.OnItemHit then ctx.OnItemHit(it, i, b) end
            end
        end
    end

    -- 防水平死弹
    local avy = math.abs(b.vy)
    if b.kick then
        local s = (b.vy >= 0) and 1 or -1
        b.vy = b.vy + s * FLAT_KICK * h
        local sp = math.sqrt(b.vx * b.vx + b.vy * b.vy)
        if sp > 0 then
            local k = Physics.SPEED / sp
            b.vx, b.vy = b.vx * k, b.vy * k
        end
        if math.abs(b.vy) >= FLAT_EXIT then b.kick = false; b.flatT = 0 end
    elseif avy < FLAT_VY then
        b.flatT = (b.flatT or 0) + h
        if b.flatT > FLAT_T then b.kick = true end
    else
        b.flatT = 0
    end
end

-- ------------------------------------------------------------
-- 推进所有飞行中的球
-- ------------------------------------------------------------
function Physics.Step(ctx, dt)
    if dt > MAX_DT then dt = MAX_DT end
    local steps = math.ceil(Physics.SPEED * dt / SUBSTEP_LEN)
    if steps < 1 then steps = 1 end
    local h = dt / steps
    for _ = 1, steps do
        for _, b in ipairs(ctx.balls) do
            if b.flying then StepBall(ctx, b, h) end
        end
    end
end

-- ------------------------------------------------------------
-- 瞄准射线:从 (x,y) 沿单位向量 (ux,uy) 推进(带球半径),
-- 撞墙/砖即停。返回 hx, hy(球心接触位), rdx, rdy(反弹方向);走满 maxLen 返回末端且无反弹方向。
-- 道具不挡瞄准线。
-- ------------------------------------------------------------
function Physics.Raycast(ctx, x, y, ux, uy, maxLen)
    local r = geo.BALL_R
    local W, H = geo.BOARD_W, geo.BOARD_H
    local STEP = 3
    local px, py = x, y
    local t = 0
    while t < maxLen do
        local adv = math.min(STEP, maxLen - t)
        px = px + ux * adv
        py = py + uy * adv
        t = t + adv

        local nx, ny
        if px < r then px = r; nx, ny = 1, 0
        elseif px > W - r then px = W - r; nx, ny = -1, 0 end
        if py > H - r then py = H - r; nx, ny = 0, -1 end

        if not nx then
            local col, row = geo.CellAt(px, py)
            local grid = ctx.grid
            for rr = row - 1, row + 1 do
                local line = grid[rr]
                if line then
                    for cc = col - 1, col + 1 do
                        local brick = line[cc]
                        if brick then
                            local cpx, cpy, inside = ClosestOnBrick(brick, px, py)
                            local d2 = (px - cpx) ^ 2 + (py - cpy) ^ 2
                            if inside or d2 < r * r then
                                local d = math.sqrt(d2)
                                if d > 0.001 then nx, ny = (px - cpx) / d, (py - cpy) / d
                                else nx, ny = -ux, -uy end
                                px = cpx + nx * (r + 0.5)
                                py = cpy + ny * (r + 0.5)
                            end
                        end
                        if nx then break end
                    end
                end
                if nx then break end
            end
        end

        if nx then
            local dot = ux * nx + uy * ny
            local rdx, rdy = ux - 2 * dot * nx, uy - 2 * dot * ny
            return px, py, rdx, rdy
        end
    end
    return px, py, nil, nil
end
