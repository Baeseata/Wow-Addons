-- DodoPool - Physics
-- 2D 运动物理 + 旋转(效果分离式):
--   * 基础:子步进积分、球-球弹性碰撞、库边反弹、滚动摩擦、落袋、停止判定
--   * 旋转(只母球带):spinF 跟杆/缩杆、spinS 侧塞、curve masse 弧线;各为独立可调项
-- 坐标:felt 局部像素，原点左下，+x 右 +y 上。

local DP = _G.DodoPool or {}
_G.DodoPool = DP

local Physics = {}
DP.Physics = Physics

local geo = DP.geo

-- 基础常量(像素 / 秒)
local ROLL_DECEL = 135      -- 滚动摩擦减速度
local STOP_V     = 5        -- 低于此速判停
local WALL_REST  = 0.72     -- 库边反弹系数
local BALL_REST  = 0.96     -- 球-球反弹系数
Physics.MAX_SPEED = 1500    -- 满力球速

-- 旋转效果系数(可调;符号/强度按手感反馈再翻/调)
local THROW_K    = 0.05     -- throw:侧塞给目标球的偏转角(弧度,满塞)
local ENGLISH_K  = 160      -- 侧塞吃库:撞库后沿库面加的切向速度
local CURVE_ACCEL = 2600    -- masse:弧线侧向加速度(满 curve)
local CURVE_DECAY = 1.0     -- curve 衰减(每秒)
local SPIN_DECAY  = 0.7     -- 侧塞(spinS)行进中衰减(每秒)
local SPINF_ACCEL = 480     -- 跟杆/缩杆:沿出杆方向施力(缩杆够劲母球会回滚)
local SPINF_DECAY = 0.5     -- 跟杆/缩杆衰减(慢些,撑到停球后还有劲回滚)

-- 落袋
local function InPocket(b)
    local PR = geo.POCKET_R
    for _, p in ipairs(geo.Pockets()) do
        local dx, dy = b.x - p.x, b.y - p.y
        if dx * dx + dy * dy <= PR * PR then return true end
    end
    return false
end

-- 靠近袋口(靠近时不撞库)
local function NearPocket(b)
    local R = geo.POCKET_R * 1.5
    for _, p in ipairs(geo.Pockets()) do
        local dx, dy = b.x - p.x, b.y - p.y
        if dx * dx + dy * dy <= R * R then return true end
    end
    return false
end

function Physics.AnyMoving(balls)
    for _, b in ipairs(balls) do
        if b.active and (b.vx * b.vx + b.vy * b.vy) > STOP_V * STOP_V then
            return true
        end
    end
    return false
end

-- 这一杆是否仍在进行:有球在动,或母球残余跟/缩杆仍足以推动静止的它(否则就该结束)。
function Physics.ShotActive(balls)
    if Physics.AnyMoving(balls) then return true end
    for _, b in ipairs(balls) do
        if b.active and b.num == 0 then
            local eff = math.abs(b.spinF or 0) * SPINF_ACCEL
            if (b.spinF or 0) > 0 then eff = eff * 0.5 end
            if eff > ROLL_DECEL * 1.1 then return true end
        end
    end
    return false
end

-- 出杆(带旋转)。dir 单位向量, frac 力度[0,1], ox/oy 击球点[-1,1], curveAmt = ox*sin(抬杆)
function Physics.ShootSpin(cue, dirx, diry, frac, ox, oy, curveAmt)
    local s = Physics.MAX_SPEED * frac
    cue.vx, cue.vy = dirx * s, diry * s
    cue.shotDirX, cue.shotDirY = dirx, diry   -- 跟杆/缩杆沿此固定方向施力
    cue.touchedObject = false    -- 本杆母球是否碰到目标球(判空杆犯规)
    cue.spinF = oy or 0          -- 上塞跟杆(+) / 下塞缩杆(-)
    cue.spinS = ox or 0          -- 左右侧塞
    cue.curve = curveAmt or 0    -- masse 弧线量(侧塞 * 抬杆)
end

-- 预测母球轨迹(动态瞄准虚线用):含 masse 弧线 + 摩擦,遇库边/目标球/停下即止。
-- 返回 felt 坐标点列表。不含跟杆/缩杆(那是落点后行为,瞄准线只示路径与弧线)。
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

-- 推进一帧。out.pocketed 收集本帧落袋(调用方 wipe)。
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
        -- 位移 + masse 弧线 + 摩擦 + 旋转衰减
        for _, b in ipairs(balls) do
            if b.active then
                b.x = b.x + b.vx * h
                b.y = b.y + b.vy * h

                local sp = math.sqrt(b.vx * b.vx + b.vy * b.vy)

                -- masse 弧线:垂直速度方向施加侧向加速度
                if b.curve ~= 0 and sp > 1 then
                    local lx, ly = -b.vy / sp, b.vx / sp     -- 左法线
                    local ca = b.curve * CURVE_ACCEL * h
                    b.vx = b.vx + lx * ca
                    b.vy = b.vy + ly * ca
                    b.curve = b.curve * (1 - math.min(1, CURVE_DECAY * h))
                    if math.abs(b.curve) < 0.001 then b.curve = 0 end
                end

                -- 跟杆/缩杆:沿出杆方向施力(缩杆够强母球会先前进再回滚)
                if b.spinF ~= 0 then
                    local acc = b.spinF * SPINF_ACCEL
                    if b.spinF > 0 then acc = acc * 0.5 end   -- 跟杆温和、缩杆够劲
                    b.vx = b.vx + (b.shotDirX or 0) * acc * h
                    b.vy = b.vy + (b.shotDirY or 0) * acc * h
                end

                -- 滚动摩擦(用施力后的实时速度,否则缩杆反向那一下会被旧速度错误抹掉)
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

                -- spinF / spinS 行进中缓慢衰减
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

        -- 落袋
        for _, b in ipairs(balls) do
            if b.active and InPocket(b) then
                b.active = false
                b.vx, b.vy = 0, 0
                if out then out.pocketed[#out.pocketed + 1] = b end
            end
        end

        -- 库边反弹(+ 侧塞吃库)
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
                end
            end
        end

        -- 球-球碰撞(等质量弹性 + 母球旋转传递)
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

                                -- 母球侧塞 throw:把目标球出球方向偏一点
                                -- (跟杆/缩杆由自由滚动施力处理,碰撞处不清 spinF,母球带塞继续前进/回滚)
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
