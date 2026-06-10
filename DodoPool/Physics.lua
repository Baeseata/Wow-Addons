-- DodoPool - Physics
-- 2D motion physics + spin (effect-separated):
--   * Base: sub-step integration, ball-on-ball elastic collision, cushion bounce, rolling friction, pocketing, stop detection
--   * Spin (cue ball only): spinF follow/draw, spinS english, curve masse; each an independent tunable
-- Coordinates: felt local pixels, origin bottom-left, +x right +y up.

local DP = _G.DodoPool or {}
_G.DodoPool = DP

local Physics = {}
DP.Physics = Physics

local geo = DP.geo

-- Base constants (pixels / second)
local ROLL_DECEL = 135      -- rolling-friction deceleration
local STOP_V     = 5        -- below this speed counts as stopped
local WALL_REST  = 0.72     -- cushion restitution
local BALL_REST  = 0.96     -- ball-on-ball restitution
Physics.MAX_SPEED = 1500    -- full-power ball speed

-- Spin effect coefficients (tunable; sign/strength to be flipped/adjusted per feel feedback)
local THROW_K    = 0.05     -- throw: deflection angle english imparts to the object ball (radians, full english)
local ENGLISH_K  = 160      -- english off the cushion: tangential speed added along the cushion after a rail hit
local CURVE_ACCEL = 2600    -- masse: lateral acceleration of the curve (full curve)
local CURVE_DECAY = 1.0     -- curve decay (per second)
local SPIN_DECAY  = 0.7     -- english (spinS) decay while travelling (per second)
local SPINF_ACCEL = 480     -- follow/draw: force along the shot direction (a strong draw makes the cue ball roll back)
local SPINF_DECAY = 0.5     -- follow/draw decay (slow, so it lasts and still has draw left after the ball stops)

-- Pocket "throat" pull (acceleration): once a ball slips past the cushion line into the railless pocket region it is pulled toward the pocket center and drops,
-- fixing the dead-zone bug where "the cue ball stops in the pocket jaws / outside the cushion and gets stuck". Must be > friction to draw a stopped ball into the pocket.
local POCKET_PULL = 1400

-- Sound trigger thresholds (px/s; sound choice and throttle live in Sound.lua)
local SND_BALL_HARD = 260   -- ball-on-ball: relative normal speed above this uses the sharp clack, below uses the soft tap
local SND_BALL_MIN  = 40    -- ball-on-ball: below this is silent
local SND_RAIL_MIN  = 60    -- rail hit: silent if post-bounce speed is below this

-- Pocketing
local function InPocket(b)
    local PR = geo.POCKET_R
    for _, p in ipairs(geo.Pockets()) do
        local dx, dy = b.x - p.x, b.y - p.y
        if dx * dx + dy * dy <= PR * PR then return true end
    end
    return false
end

-- Near a pocket (don't bounce off the cushion when close)
local function NearPocket(b)
    local R = geo.POCKET_R * 1.5
    for _, p in ipairs(geo.Pockets()) do
        local dx, dy = b.x - p.x, b.y - p.y
        if dx * dx + dy * dy <= R * R then return true end
    end
    return false
end

-- Nearest pocket within the pocket region: returns pocket-center px,py + distance squared; nil if not in any pocket region.
-- Used by "pocket throat suction": a ball that slips into the pocket region (cushion already off) is pulled toward the nearest pocket center.
local function MouthPocket(b)
    local R2 = (geo.POCKET_R * 1.5) ^ 2
    local best, bx, by
    for _, p in ipairs(geo.Pockets()) do
        local dx, dy = p.x - b.x, p.y - b.y
        local d2 = dx * dx + dy * dy
        if d2 <= R2 and (not best or d2 < best) then best, bx, by = d2, p.x, p.y end
    end
    return bx, by, best
end

function Physics.AnyMoving(balls)
    for _, b in ipairs(balls) do
        if b.active and (b.vx * b.vx + b.vy * b.vy) > STOP_V * STOP_V then
            return true
        end
    end
    return false
end

-- Whether this shot is still going: a ball is moving, or the cue ball's leftover follow/draw is still enough to push it from rest (otherwise it should end).
function Physics.ShotActive(balls)
    if Physics.AnyMoving(balls) then return true end
    for _, b in ipairs(balls) do
        if b.active and b.num == 0 then
            local eff = math.abs(b.spinF or 0) * SPINF_ACCEL
            if (b.spinF or 0) > 0 then eff = eff * 0.5 end
            if eff > ROLL_DECEL * 1.1 then return true end
        end
    end
    -- A ball slipped past the cushion line (stuck in a pocket throat): keep simulating so the pocket pull draws it in, don't let the shot end here
    local W, H, R = geo.FELT_W, geo.FELT_H, geo.BALL_R
    for _, b in ipairs(balls) do
        if b.active and (b.x < R or b.x > W - R or b.y < R or b.y > H - R) then return true end
    end
    return false
end

-- Shoot (with spin). dir unit vector, frac power [0,1], ox/oy strike point [-1,1], curveAmt = ox*sin(elevation)
function Physics.ShootSpin(cue, dirx, diry, frac, ox, oy, curveAmt)
    local s = Physics.MAX_SPEED * frac
    cue.vx, cue.vy = dirx * s, diry * s
    cue.shotDirX, cue.shotDirY = dirx, diry   -- follow/draw applies force along this fixed direction
    cue.touchedObject = false    -- whether the cue ball touched an object ball this shot (for the no-contact foul)
    cue.spinF = oy or 0          -- top english = follow (+) / bottom english = draw (-)
    cue.spinS = ox or 0          -- left/right english
    cue.curve = curveAmt or 0    -- masse curve amount (english * elevation)
end

-- Predict the cue ball path (for the dynamic aim dashes): includes masse curve + friction, stops at a cushion/object ball/standstill.
-- Returns a list of felt-coordinate points. Excludes follow/draw (that is post-landing behavior; the aim line only shows the path and the curve).
function Physics.PredictCuePath(sx, sy, dirx, diry, speed, curveAmt, balls)
    local R, W, H = geo.BALL_R, geo.FELT_W, geo.FELT_H
    local x, y = sx, sy
    local vx, vy = dirx * speed, diry * speed
    local curve = curveAmt or 0
    local dt = 0.012
    local pts = { { x = x, y = y } }
    for _ = 2, 90 do
        local sp = math.sqrt(vx * vx + vy * vy)
        if sp < 25 then break end
        if curve ~= 0 then
            local lx, ly = -vy / sp, vx / sp
            local ca = curve * CURVE_ACCEL * dt
            vx, vy = vx + lx * ca, vy + ly * ca
            curve = curve * (1 - math.min(1, CURVE_DECAY * dt))
        end
        local dec = ROLL_DECEL * dt
        if dec < sp then local f = (sp - dec) / sp; vx, vy = vx * f, vy * f end
        x, y = x + vx * dt, y + vy * dt
        pts[#pts + 1] = { x = x, y = y }
        if x < R or x > W - R or y < R or y > H - R then break end
        local stop = false
        for _, b in ipairs(balls) do
            if b.active and b.num ~= 0 then
                local ddx, ddy = x - b.x, y - b.y
                if ddx * ddx + ddy * ddy <= (2 * R) * (2 * R) then stop = true; break end
            end
        end
        if stop then break end
    end
    return pts
end

-- Advance one frame. out.pocketed collects balls pocketed this frame (caller wipes it).
function Physics.Step(balls, dt, out)
    local W, H, R = geo.FELT_W, geo.FELT_H, geo.BALL_R
    local n = #balls

    local maxv2 = 0
    for _, b in ipairs(balls) do
        if b.active then
            local s = b.vx * b.vx + b.vy * b.vy
            if s > maxv2 then maxv2 = s end
        end
    end
    local maxv = math.sqrt(maxv2)
    local sub = 1
    if maxv > 0 then
        sub = math.ceil(maxv * dt / (R * 0.4))
        if sub < 1 then sub = 1 elseif sub > 16 then sub = 16 end
    end
    local h = dt / sub

    for _ = 1, sub do
        -- displacement + masse curve + friction + spin decay
        for _, b in ipairs(balls) do
            if b.active then
                b.x = b.x + b.vx * h
                b.y = b.y + b.vy * h

                local sp = math.sqrt(b.vx * b.vx + b.vy * b.vy)

                -- masse curve: apply lateral acceleration perpendicular to the velocity
                if b.curve ~= 0 and sp > 1 then
                    local lx, ly = -b.vy / sp, b.vx / sp     -- left normal
                    local ca = b.curve * CURVE_ACCEL * h
                    b.vx = b.vx + lx * ca
                    b.vy = b.vy + ly * ca
                    b.curve = b.curve * (1 - math.min(1, CURVE_DECAY * h))
                    if math.abs(b.curve) < 0.001 then b.curve = 0 end
                end

                -- follow/draw: apply force along the shot direction (a strong-enough draw makes the cue ball move forward first then roll back)
                if b.spinF ~= 0 then
                    local acc = b.spinF * SPINF_ACCEL
                    if b.spinF > 0 then acc = acc * 0.5 end   -- gentle follow, punchy draw
                    b.vx = b.vx + (b.shotDirX or 0) * acc * h
                    b.vy = b.vy + (b.shotDirY or 0) * acc * h
                end

                -- pocket throat suction: a ball has slipped past the cushion line (into the railless pocket region) -> pull it toward the nearest pocket center and drop it,
                -- eliminating the dead zone of getting stuck in the pocket jaws / outside the cushion (the cushion is off in the pocket region, so it won't bounce it back)
                if b.x < R or b.x > W - R or b.y < R or b.y > H - R then
                    local mpx, mpy, md2 = MouthPocket(b)
                    if mpx and md2 and md2 > 0.0001 then
                        local d = math.sqrt(md2)
                        b.vx = b.vx + (mpx - b.x) / d * POCKET_PULL * h
                        b.vy = b.vy + (mpy - b.y) / d * POCKET_PULL * h
                    end
                end

                -- rolling friction (use the post-force live speed, otherwise the draw's reverse step gets wrongly cancelled by the old speed)
                local fsp = math.sqrt(b.vx * b.vx + b.vy * b.vy)
                if fsp > 0 then
                    local dec = ROLL_DECEL * h
                    if dec >= fsp then
                        b.vx, b.vy = 0, 0
                    else
                        local f = (fsp - dec) / fsp
                        b.vx, b.vy = b.vx * f, b.vy * f
                    end
                end

                -- spinF / spinS slowly decay while travelling
                if b.spinF ~= 0 then
                    b.spinF = b.spinF * (1 - math.min(1, SPINF_DECAY * h))
                    if math.abs(b.spinF) < 0.001 then b.spinF = 0 end
                end
                if b.spinS ~= 0 then
                    b.spinS = b.spinS * (1 - math.min(1, SPIN_DECAY * h))
                    if math.abs(b.spinS) < 0.001 then b.spinS = 0 end
                end
            end
        end

        -- pocketing
        for _, b in ipairs(balls) do
            if b.active and InPocket(b) then
                b.active = false
                b.vx, b.vy = 0, 0
                if out then out.pocketed[#out.pocketed + 1] = b end
            end
        end

        -- cushion bounce (+ english off the cushion)
        for _, b in ipairs(balls) do
            if b.active and not NearPocket(b) then
                local hit = false
                if b.x < R then
                    b.x = R; b.vx = -b.vx * WALL_REST; hit = true
                    if b.spinS ~= 0 then b.vy = b.vy + b.spinS * ENGLISH_K; b.spinS = b.spinS * -0.4 end
                elseif b.x > W - R then
                    b.x = W - R; b.vx = -b.vx * WALL_REST; hit = true
                    if b.spinS ~= 0 then b.vy = b.vy - b.spinS * ENGLISH_K; b.spinS = b.spinS * -0.4 end
                end
                if b.y < R then
                    b.y = R; b.vy = -b.vy * WALL_REST; hit = true
                    if b.spinS ~= 0 then b.vx = b.vx - b.spinS * ENGLISH_K; b.spinS = b.spinS * -0.4 end
                elseif b.y > H - R then
                    b.y = H - R; b.vy = -b.vy * WALL_REST; hit = true
                    if b.spinS ~= 0 then b.vx = b.vx + b.spinS * ENGLISH_K; b.spinS = b.spinS * -0.4 end
                end
                if hit then
                    if b.spinF ~= 0 then b.spinF = b.spinF * 0.5 end
                    if out and out.firstHit then out.railAfter = true end
                    if DP.Sound and (b.vx * b.vx + b.vy * b.vy) > SND_RAIL_MIN * SND_RAIL_MIN then
                        DP.Sound.Play("rail")
                    end
                end
            end
        end

        -- ball-on-ball collision (equal-mass elastic + cue spin transfer)
        for i = 1, n do
            local a = balls[i]
            if a.active then
                for j = i + 1, n do
                    local c = balls[j]
                    if c.active then
                        local dx, dy = c.x - a.x, c.y - a.y
                        local d2 = dx * dx + dy * dy
                        local md = 2 * R
                        if d2 > 0.0001 and d2 < md * md then
                            local d = math.sqrt(d2)
                            local nx, ny = dx / d, dy / d
                            local ov = (md - d) / 2
                            a.x, a.y = a.x - nx * ov, a.y - ny * ov
                            c.x, c.y = c.x + nx * ov, c.y + ny * ov
                            local vn = (c.vx - a.vx) * nx + (c.vy - a.vy) * ny
                            if vn < 0 then
                                local imp = -(1 + BALL_REST) * vn / 2
                                a.vx, a.vy = a.vx - imp * nx, a.vy - imp * ny
                                c.vx, c.vy = c.vx + imp * nx, c.vy + imp * ny

                                -- collision sound: split light/heavy by relative normal speed (chained same-frame collisions throttled by Sound)
                                if DP.Sound then
                                    local hv = -vn
                                    if hv >= SND_BALL_HARD then DP.Sound.Play("clack")
                                    elseif hv >= SND_BALL_MIN then DP.Sound.Play("soft") end
                                end

                                -- cue ball english throw: deflect the object ball's outgoing direction a bit
                                -- (follow/draw is handled by the free-rolling force step; don't clear spinF at collision, the cue ball keeps moving/rolling back with english)
                                local cue, obj
                                if a.num == 0 then cue, obj = a, c
                                elseif c.num == 0 then cue, obj = c, a end
                                if cue then
                                    cue.touchedObject = true
                                    if out and not out.firstHit then out.firstHit = obj.num end
                                end
                                if cue and cue.spinS ~= 0 then
                                    local phi = cue.spinS * THROW_K
                                    local cs, sn = math.cos(phi), math.sin(phi)
                                    local ovx, ovy = obj.vx, obj.vy
                                    obj.vx = ovx * cs - ovy * sn
                                    obj.vy = ovx * sn + ovy * cs
                                    cue.spinS = cue.spinS * 0.6
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end
