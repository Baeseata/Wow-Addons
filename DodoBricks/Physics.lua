-- DodoBricks - Physics
-- Ball flight: constant speed, no gravity, no friction, perfectly elastic bounce; balls don't collide with each other (genre convention, also saves performance).
-- Collisions use a uniform "closest-point method": find the closest point from the ball center to the shape (square = AABB clamp, triangle = closest point on the three edges),
--   distance < radius means a hit, normal = ball center - closest point, velocity mirror-reflected along the normal + position pushed out. Corners come out correct naturally.
-- Bricks are on a grid => each sub-step only checks the 3x3 neighborhood of the ball's cell, O(1), hundreds of balls stay smooth.
-- Sub-stepping: each step's displacement <= SUBSTEP_LEN (< ball radius), prevents tunneling (same idea as DodoPool).
-- Coordinates: board local pixels, origin bottom-left.

local DBR = _G.DodoBricks or {}
_G.DodoBricks = DBR

local Physics = {}
DBR.Physics = Physics

local geo = DBR.geo

-- Tunable constants
Physics.SPEED   = 900       -- ball speed (px/s, constant)
local SUBSTEP_LEN = 6       -- max displacement per sub-step (px, needs to be < BALL_R)
local MAX_DT      = 0.05    -- max advance per frame (prevents tunneling in one go on a frame drop)

-- Anti horizontal stall: when |vy| stays below FLAT_VY for FLAT_T seconds, keep nudging the ball toward its current vertical direction (downward if near zero),
-- until |vy| exceeds FLAT_EXIT. Fixes "the last ball bounces sideways forever and won't come down".
local FLAT_VY   = 35
local FLAT_T    = 3.5
local FLAT_EXIT = 140
local FLAT_KICK = 220       -- vy correction rate (px/s per second)

-- ------------------------------------------------------------
-- Closest point on a shape
-- ------------------------------------------------------------
local function ClosestOnSegment(px, py, ax, ay, bx, by)
    local abx, aby = bx - ax, by - ay
    local len2 = abx * abx + aby * aby
    if len2 <= 0 then return ax, ay end
    local t = ((px - ax) * abx + (py - ay) * aby) / len2
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return ax + abx * t, ay + aby * t
end

-- The triangle's three vertices (the right angle is at the orient corner; collision uses the full cell, the seam is only visual)
local function TriVerts(x0, y0, x1, y1, orient)
    if orient == "BL" then return x0, y0, x1, y0, x0, y1
    elseif orient == "BR" then return x0, y0, x1, y0, x1, y1
    elseif orient == "TL" then return x0, y0, x1, y1, x0, y1
    else return x1, y0, x1, y1, x0, y1 end   -- TR
end

-- Is the ball center P inside the triangle? (inside the AABB + on the solid side of the hypotenuse)
local function InsideTri(px, py, x0, y0, x1, y1, orient)
    if px < x0 or px > x1 or py < y0 or py > y1 then return false end
    local u, v, C = px - x0, py - y0, x1 - x0
    if orient == "BL" then return u + v <= C
    elseif orient == "BR" then return u >= v
    elseif orient == "TL" then return u <= v
    else return u + v >= C end   -- TR
end

-- Closest point from the ball center to a brick. Returns cpx, cpy, inside
-- Multi-cell bricks (boss, w/h > 1): the AABB spans from the bottom-left cell to the top-right cell.
local function ClosestOnBrick(brick, px, py)
    local x0, y0, x1, y1 = geo.CellRect(brick.col, brick.row)
    if brick.w and brick.w > 1 then
        local _, _, xx, yy = geo.CellRect(brick.col + brick.w - 1, brick.row + (brick.h or 1) - 1)
        x1, y1 = xx, yy
    end
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
-- Single sub-step: advance one ball. ctx = { grid, items, OnBrickHit, OnItemHit, OnBallLand }
-- ------------------------------------------------------------
local function StepBall(ctx, b, h)
    local r = geo.BALL_R
    local W, H, FLOOR = geo.BOARD_W, geo.BOARD_H, geo.FLOOR

    b.x = b.x + b.vx * h
    b.y = b.y + b.vy * h

    -- walls (left/right/top)
    if b.x < r then b.x = r; b.vx = math.abs(b.vx)
    elseif b.x > W - r then b.x = W - r; b.vx = -math.abs(b.vx) end
    if b.y > H - r then b.y = H - r; b.vy = -math.abs(b.vy) end

    -- landing (ball center reaches FLOOR while moving down) => this ball is done for the round
    if b.y <= FLOOR and b.vy < 0 then
        b.y = FLOOR
        b.flying = false
        if ctx.OnBallLand then ctx.OnBallLand(b) end
        return
    end

    -- bricks: in the 3x3 neighborhood, resolve the one with the deepest penetration (the next sub-step naturally handles an adjacent second brick)
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
            -- ball center is touching / inside the brick (in theory a small enough sub-step prevents this): back out along the incoming direction
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
        if ctx.OnBrickHit then ctx.OnBrickHit(best, b) end
    end

    -- items (triggered on pass-through, no bounce; +1 ball is consumed and removed, laser/bomb persist the whole round, deduped by Game)
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

    -- anti horizontal stall
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
-- Advance all balls in flight
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
-- Aim ray: advance from (x,y) along the unit vector (ux,uy) (with the ball radius),
-- stop at a wall/brick. Returns hx, hy (ball-center contact position), rdx, rdy (bounce direction); if it runs the full maxLen, returns the end point with no bounce direction.
-- Items don't block the aim line.
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
