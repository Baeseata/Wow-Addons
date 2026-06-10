-- DodoBricks - Game
-- State machine + round loop + input + HUD + save/load + combat pause.
-- States: AIM (aim by holding left-click and dragging, release to launch, right-click to cancel) -> FLY (the ball stream flies: launched in sequence, landing collected,
--       first ball's landing spot = next launch point) -> DESCEND (bricks drop one row + a new top spawn row, animated) -> back to AIM.
--       A brick pushed past the bottom row = OVER, game over. Level = rows spawned so far, new brick HP = current level (small chance of double).
-- Save: round-based, autosaves on each return to AIM (1 slot); game over clears the save; the highest level is recorded in DodoBricksDB.bestLevel.

local DBR = _G.DodoBricks or {}
_G.DodoBricks = DBR

local G = {}
DBR.Game = G

local geo, Physics, Render

-- Tunable parameters
local LAUNCH_GAP   = 0.07   -- ball launch interval (seconds)
local MIN_AIM_DIST = 16     -- if the mouse is closer than this to the launch point = invalid aim (release won't launch)
local MIN_ANGLE    = 8      -- minimum launch elevation (degrees, prevents grazing flat shots)
local AIM_MAX_LEN  = 900    -- max length of the aim's first segment (px)
local STUB_LEN     = 70     -- length of the bounce-hint stub after the first segment's collision
local DOT_GAP      = 18     -- spacing between aim dots
local DOT_SPEED    = 60     -- aim dot travel speed (px/s)
local DESCEND_T    = 0.28   -- descend animation duration (seconds)
local SLIDE_SPEED  = 1500   -- speed at which landed balls slide to the gather point (px/s)
local BRICK_CHANCE  = 0.45  -- per-cell brick spawn chance in a new row (item cell excluded; if none spawn, guarantee 1)
local TRI_CHANCE    = 0.20  -- chance a new brick is a triangle
local DOUBLE_CHANCE = 0.12  -- chance a new brick has double HP ("hard brick")
local ORIENTS = { "BL", "BR", "TL", "TR" }
local SPREAD_DEG    = 3     -- multi-ball spread: from the 2nd ball on, randomly offset +-SPREAD_DEG/2 degrees (the first follows the aim line strictly, so the dashes are honest)
local SPECIAL_CHANCE = 0.22 -- chance a new row spawns a special item (laser/bomb) (placed in an empty cell; +1 ball still guaranteed every row)
local SPECIAL_KINDS = { "laserH", "laserV", "bomb" }
local CLEAR_BONUS   = 2     -- clear-all bonus balls (clearing the whole board in one round)
local TRAIL_MAX     = 3     -- max comet-trail segments (each segment = an afterimage of a previous frame's position)
local TRAIL_BUDGET  = 240   -- total trail-segment budget across the board: auto-shortens when there are many balls (<=80 balls 3 seg, <=120 balls 2 seg, more = 1 seg)

-- Ball speed ramp (0.2.2): the base ball speed climbs slightly with the level, and a long single round smoothly fast-forwards, so later rounds don't drag.
-- The implementation is pure "time fast-forward" (uniformly scaling FLY's dt): trajectory and landing are identical to 1x speed, only the playback is faster.
local LV_SPEED_GAIN  = 0.02 -- +2% base speed per level (level 1 = x1.0)
local LV_SPEED_MAX   = 1.6  -- level speed-up cap (with this default, caps around level 31)
local RAMP_START     = 4    -- how many seconds into a round's flight before fast-forward begins (short rounds feel nothing)
local RAMP_FULL      = 12   -- how many seconds until fast-forward is maxed (smoothstep in between)
local RAMP_MAX       = 2.0  -- in-round fast-forward cap (multiplied on top of the level speed-up)
local SPEED_MULT_CAP = 2.6  -- total speed-multiplier cap (LV_SPEED_GAIN=0 + RAMP_MAX=1 disables the ramp entirely)

local function Print(msg)
    if _G.Dodo and _G.Dodo.Print then _G.Dodo.Print("Bricks", msg) else print("|cff33ff99DodoBricks:|r " .. tostring(msg)) end
end

local function Clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi end return x end

local function Snd(kind) if DBR.Sound then DBR.Sound.Play(kind) end end

local function MouseBoard()
    local pa = DBR.playArea
    local scale = pa:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    mx, my = mx / scale, my / scale
    return mx - pa:GetLeft(), my - pa:GetBottom()
end

-- ------------------------------------------------------------
-- Build pieces (once): bricks / items / balls / aim dots each get an object pool
-- ------------------------------------------------------------
local function EnsureSetup()
    if G.ready then return end
    G.ready = true
    geo, Physics, Render = DBR.geo, DBR.Physics, DBR.Render
    local pa = DBR.playArea

    -- bricks/items hang on gridLayer; the descend animation only moves this layer's anchor offset
    local gl = CreateFrame("Frame", nil, pa)
    gl:SetSize(geo.BOARD_W, geo.BOARD_H)
    gl:SetPoint("BOTTOMLEFT", pa, "BOTTOMLEFT", 0, 0)
    gl:SetFrameLevel((pa:GetFrameLevel() or 0) + 2)
    G.gridLayer = gl

    G.bricks = {}            -- set: brick -> true
    G.grid = {}              -- grid[row][col] = brick
    for r = 1, geo.ROWS do G.grid[r] = {} end
    G.items = {}             -- array: { col, row, kind, frame } (kind: ball/laserH/laserV/bomb)
    G.balls = {}             -- ball struct pool (grows with ballTotal)
    G.brickPool = {}         -- recycle pool: key("sq"/"tri_BL"...) -> {frame...}
    G.itemPool = {}          -- item recycle pool: kind -> {frame...}
    G.dots = {}
    G.effects = {}           -- active effects: { key, frame, t, dur, grow }
    G.effectPool = {}        -- effect recycle pool: key -> {frame...}

    -- launcher: white ball + remaining-count text + next-round landing ghost
    G.launcher = Render.NewBall(pa)
    G.countText = pa:CreateFontString(nil, "OVERLAY")
    G.countText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    G.countText:SetTextColor(1, 1, 1, 0.95)
    G.marker = Render.NewBall(pa)
    G.marker:SetAlpha(0.35)
    G.marker:Hide()

    -- combat pause prompt
    local pause = pa:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    pause:SetPoint("CENTER", pa, "CENTER", 0, 40)
    pause:SetTextColor(1, 0.4, 0.4)
    pause:SetText("Paused in combat")
    pause:Hide()
    G.pauseText = pause

    -- "+1" floating-text pool
    G.floats = {}
    for i = 1, 4 do
        local fs = pa:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
        fs:SetTextColor(0.4, 1, 0.5)
        fs:Hide()
        G.floats[i] = { fs = fs, t = nil, x = 0, y = 0 }
    end

    -- big floating announcement (clear-all bonus etc., board center)
    G.bigFs = pa:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    G.bigFs:SetTextColor(1, 0.85, 0.2)
    G.bigFs:Hide()
    G.bigT = nil

    -- physics context (table is persistent, fields reference shared objects)
    G.ctx = {
        balls = G.balls,
        grid = G.grid,
        items = G.items,
        OnBrickHit = function(brick) G.HitBrick(brick) end,
        OnItemHit = function(item, idx, ball) G.HitItem(item, idx, ball) end,
        OnBallLand = function(ball) G.BallLanded(ball) end,
    }

    G.EnsureHUD()
    G.EnsureOverPanel()

    -- input + driver
    pa:EnableMouse(true)
    pa:SetScript("OnMouseDown", function(_, button)
        if G.state ~= "AIM" or G.paused then return end
        if button == "LeftButton" then
            G.lmbDown = true
        elseif button == "RightButton" then
            G.lmbDown = false
            G.HideDots()
        end
    end)
    pa:SetScript("OnUpdate", function(_, elapsed) G.Driver(elapsed) end)
end

-- ------------------------------------------------------------
-- Brick / item pools
-- ------------------------------------------------------------
local function BrickKey(shape, orient) return shape == "tri" and ("tri_" .. orient) or "sq" end

local function GetBrickFrame(shape, orient)
    local key = BrickKey(shape, orient)
    local pool = G.brickPool[key]
    local fr = pool and table.remove(pool)
    if not fr then fr = Render.NewBrick(G.gridLayer, shape, orient) end
    fr:Show()
    return fr
end

local function FreeBrickFrame(brick)
    brick.frame:Hide()
    local key = BrickKey(brick.shape, brick.orient)
    G.brickPool[key] = G.brickPool[key] or {}
    table.insert(G.brickPool[key], brick.frame)
    brick.frame = nil
end

local function PlaceItem(it)
    local x, y = geo.CellCenter(it.col, it.row)
    Render.PlaceAt(G.gridLayer, it.frame, x, y)
end

local function GetItemFrame(kind)
    kind = kind or "ball"
    local pool = G.itemPool[kind]
    local fr = pool and table.remove(pool)
    if not fr then fr = Render.NewItem(G.gridLayer, kind) end
    fr:Show()
    return fr
end

local function FreeItemFrame(it)
    it.frame:Hide()
    local kind = it.kind or "ball"
    G.itemPool[kind] = G.itemPool[kind] or {}
    table.insert(G.itemPool[kind], it.frame)
    it.frame = nil
end

-- ------------------------------------------------------------
-- Effect pool (brick flash / laser beam / explosion ring): ADD glow, grown + faded out then recycled.
-- Structure = anchor placeholder frame (positions, doesn't scale) + visual subframe (zero offset, centered, scaled):
-- WoW's SetScale scales the anchor offset too, so directly scaling a frame with a large offset would drift.
-- ------------------------------------------------------------
local function SpawnEffect(key, build, x, y, dur, grow)
    local pool = G.effectPool[key]
    local fr = pool and table.remove(pool)
    if not fr then
        fr = CreateFrame("Frame", nil, DBR.playArea)
        fr:SetSize(2, 2)
        fr:SetFrameLevel((DBR.playArea:GetFrameLevel() or 0) + 7)
        local vis = build(fr)
        vis:ClearAllPoints()
        vis:SetPoint("CENTER", fr, "CENTER", 0, 0)
        fr.vis = vis
    end
    fr:ClearAllPoints()
    fr:SetPoint("CENTER", DBR.playArea, "BOTTOMLEFT", x, y)
    fr.vis:SetScale(1)
    fr:SetAlpha(1)
    fr:Show()
    table.insert(G.effects, { key = key, frame = fr, t = 0, dur = dur, grow = grow or 0 })
end

local function UpdateEffects(dt)
    for i = #G.effects, 1, -1 do
        local e = G.effects[i]
        e.t = e.t + dt
        local p = e.t / e.dur
        if p >= 1 then
            e.frame:Hide()
            e.frame.vis:SetScale(1)
            G.effectPool[e.key] = G.effectPool[e.key] or {}
            table.insert(G.effectPool[e.key], e.frame)
            table.remove(G.effects, i)
        else
            e.frame:SetAlpha(1 - p)
            if e.grow > 0 then e.frame.vis:SetScale(1 + e.grow * p) end
        end
    end
end

local function BrickFlash(brick)
    local key = "fx_" .. BrickKey(brick.shape, brick.orient)
    local shape, orient = brick.shape, brick.orient
    local cx, cy = geo.CellCenter(brick.col, brick.row)
    SpawnEffect(key, function(p) return Render.NewBrickFlash(p, shape, orient) end,
        cx, cy, 0.22, 0.35)
end

local function FireBeamH(row)
    local _, cy = geo.CellCenter(0, row)
    SpawnEffect("beamH", function(p) return Render.NewBeam(p, true) end,
        geo.BOARD_W / 2, cy, 0.2, 0)
end

local function FireBeamV(col)
    local cx = geo.CellCenter(col, 1)
    SpawnEffect("beamV", function(p) return Render.NewBeam(p, false) end,
        cx, geo.FLOOR + geo.ROWS * geo.CELL / 2, 0.2, 0)
end

local function FireBoom(col, row)
    local cx, cy = geo.CellCenter(col, row)
    SpawnEffect("boom", function(p) return Render.NewBoom(p) end,
        cx, cy, 0.3, 0.6)
end

local function ClearBoard()
    for brick in pairs(G.bricks) do FreeBrickFrame(brick) end
    wipe(G.bricks)
    for r = 1, geo.ROWS do wipe(G.grid[r]) end
    for i = #G.items, 1, -1 do FreeItemFrame(G.items[i]); table.remove(G.items, i) end
    for _, b in ipairs(G.balls) do
        b.flying, b.sliding, b.itemTouch = false, false, nil
        b.frame:Hide()
        if b.ghosts then for k = 1, #b.ghosts do b.ghosts[k]:Hide() end end
    end
    for _, fl in ipairs(G.floats) do fl.t = nil; fl.fs:Hide() end
    for i = #G.effects, 1, -1 do
        local e = G.effects[i]
        e.frame:Hide(); e.frame.vis:SetScale(1)
        G.effectPool[e.key] = G.effectPool[e.key] or {}
        table.insert(G.effectPool[e.key], e.frame)
        table.remove(G.effects, i)
    end
    G.bigT = nil
    G.bigFs:Hide()
    G.marker:Hide()
    G.HideDots()
end

-- Grow the ball struct pool to n (hx/hy = ring of previous-frame positions, used to draw the trail; ghosts lazily built)
local function EnsureBalls(n)
    for i = #G.balls + 1, n do
        G.balls[i] = { x = 0, y = 0, vx = 0, vy = 0, flying = false, sliding = false,
                       flatT = 0, kick = false, hx = { 0, 0, 0 }, hy = { 0, 0, 0 },
                       frame = Render.NewBall(DBR.playArea) }
        G.balls[i].frame:Hide()
    end
end

-- ------------------------------------------------------------
-- HUD (main window top bar): level / ball count / sound / back to start
-- ------------------------------------------------------------
function G.EnsureHUD()
    if G.hud then return end
    local f = DBR.frame
    local hud = {}
    G.hud = hud

    hud.level = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hud.level:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -30)
    hud.level:SetText("Level 1")

    hud.balls = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hud.balls:SetPoint("LEFT", hud.level, "RIGHT", 18, 0)
    hud.balls:SetTextColor(0.95, 0.95, 0.95)
    hud.balls:SetText("Balls x1")

    -- current ball-speed multiplier (ball speed ramp, shown from x1.1 up)
    hud.speed = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hud.speed:SetPoint("LEFT", hud.balls, "RIGHT", 14, 0)
    hud.speed:SetTextColor(0.5, 0.85, 1)
    hud.speed:Hide()

    local menuBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    menuBtn:SetSize(76, 21)
    menuBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -29)
    menuBtn:SetText("Menu")
    menuBtn:SetScript("OnClick", function() G.ReturnToMenu() end)

    if DBR.Sound and DBR.Sound.CreateToggle then
        local cb = DBR.Sound.CreateToggle(f, true)   -- compact version: no label, with tooltip
        cb:SetPoint("RIGHT", menuBtn, "LEFT", -4, 0)
    end
end

local function UpdateHUD()
    if not G.hud then return end
    G.hud.level:SetText("Level " .. (G.round or 1))
    G.hud.balls:SetText("Balls x" .. (G.ballTotal or 1))
end

-- launcher and remaining-count text
local function PlaceLauncher()
    Render.PlaceAt(DBR.playArea, G.launcher, G.launchX, geo.FLOOR)
    G.countText:ClearAllPoints()
    G.countText:SetPoint("BOTTOM", DBR.playArea, "BOTTOMLEFT", G.launchX, geo.FLOOR + geo.BALL_R + 3)
end

local function SetCountText(n)
    if n and n > 0 then
        G.countText:SetText("x" .. n)
        G.countText:Show()
    else
        G.countText:Hide()
    end
end

-- ------------------------------------------------------------
-- Game over panel
-- ------------------------------------------------------------
function G.EnsureOverPanel()
    if G.overPanel then return end
    local pa = DBR.playArea
    local p = CreateFrame("Frame", nil, pa)
    p:SetAllPoints(pa)
    p:SetFrameLevel((pa:GetFrameLevel() or 0) + 30)
    p:EnableMouse(true)   -- eat clicks
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.82)

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    p.title:SetPoint("CENTER", p, "CENTER", 0, 90)
    p.title:SetTextColor(1, 0.35, 0.3)
    p.title:SetText("Game Over")

    p.line1 = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.line1:SetPoint("TOP", p.title, "BOTTOM", 0, -16)
    p.line2 = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.line2:SetPoint("TOP", p.line1, "BOTTOM", 0, -10)

    local againBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    againBtn:SetSize(140, 30)
    againBtn:SetPoint("TOP", p.line2, "BOTTOM", 0, -28)
    againBtn:SetText("Play Again")
    againBtn:SetScript("OnClick", function() G.New() end)

    local menuBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    menuBtn:SetSize(140, 30)
    menuBtn:SetPoint("TOP", againBtn, "BOTTOM", 0, -10)
    menuBtn:SetText("Menu")
    menuBtn:SetScript("OnClick", function() G.ReturnToMenu() end)

    p:Hide()
    G.overPanel = p
end

-- ------------------------------------------------------------
-- Aim dashes
-- ------------------------------------------------------------
local function GetDot(i)
    local d = G.dots[i]
    if not d then
        d = Render.NewDot(DBR.playArea)
        G.dots[i] = d
    end
    return d
end

function G.HideDots(from)
    for k = from or 1, #G.dots do G.dots[k]:Hide() end
end

-- lay travelling aim dots along [launch point -> collision point] (+ a bounce stub)
local function DrawAimDots(sx, sy, ux, uy)
    local hx, hy, rdx, rdy = Physics.Raycast(G.ctx, sx, sy, ux, uy, AIM_MAX_LEN)
    local len1 = math.sqrt((hx - sx) ^ 2 + (hy - sy) ^ 2)
    local len2 = rdx and STUB_LEN or 0
    local total = len1 + len2
    local phase = (GetTime() * DOT_SPEED) % DOT_GAP
    local di = 0
    local s = phase
    while s < total and di < 70 do
        di = di + 1
        local d = GetDot(di)
        local x, y
        if s <= len1 then
            x, y = sx + ux * s, sy + uy * s
        else
            local t2 = s - len1
            x, y = hx + rdx * t2, hy + rdy * t2
            d:SetAlpha(0.45)   -- bounce segment a bit fainter
        end
        if s <= len1 then d:SetAlpha(0.9) end
        Render.PlaceAt(DBR.playArea, d, x, y)
        d:Show()
        s = s + DOT_GAP
    end
    G.HideDots(di + 1)
end

-- ------------------------------------------------------------
-- Aim / launch
-- ------------------------------------------------------------
local function Fire()
    EnsureBalls(G.ballTotal)
    for i = 1, G.ballTotal do
        local b = G.balls[i]
        b.flying, b.sliding, b.flatT, b.kick = false, false, 0, false
        b.itemTouch = nil
        b.frame:Hide()
    end
    G.ballsInPlay = G.ballTotal
    G.toLaunch = G.ballTotal
    G.launchTimer = 0
    G.flyT = 0               -- this round's flight timer (for the ball speed ramp, real seconds)
    G.nextX = nil
    G.turnHadBricks = next(G.bricks) ~= nil
    -- trail segment count: shared from the board-wide budget, auto-shortens when there are many balls for performance
    G.trailN = math.min(TRAIL_MAX, math.floor(TRAIL_BUDGET / math.max(1, G.ballTotal)))
    G.marker:Hide()
    G.HideDots()
    G.state = "FLY"
end

local function UpdateAim()
    if not G.lmbDown then return end
    if IsMouseButtonDown("RightButton") then
        G.lmbDown = false
        G.aimValid = false
        G.HideDots()
        return
    end

    local mx, my = MouseBoard()
    local dx, dy = mx - G.launchX, my - geo.FLOOR
    local dist = math.sqrt(dx * dx + dy * dy)
    local minUp = math.sin(math.rad(MIN_ANGLE))
    local valid = dist >= MIN_AIM_DIST and dy > 0 and (dy / dist) >= minUp

    if not IsMouseButtonDown("LeftButton") then
        -- release: launch if valid
        G.lmbDown = false
        if valid then
            G.aimDirX, G.aimDirY = dx / dist, dy / dist
            Fire()
            Snd("launch")
        else
            G.HideDots()
        end
        return
    end

    G.aimValid = valid
    if valid then
        DrawAimDots(G.launchX, geo.FLOOR, dx / dist, dy / dist)
    else
        G.HideDots()
    end
end

-- ------------------------------------------------------------
-- Physics callbacks
-- ------------------------------------------------------------
function G.HitBrick(brick)
    if not G.bricks[brick] then return end   -- already broken this frame by a laser/bomb chain
    brick.hp = brick.hp - 1
    if brick.hp <= 0 then
        BrickFlash(brick)
        G.grid[brick.row][brick.col] = nil
        G.bricks[brick] = nil
        FreeBrickFrame(brick)
        Snd("brk")
    else
        brick.frame:SetHP(brick.hp)
        Snd("hit")
    end
end

local function AddFloat(x, y, text)
    for _, fl in ipairs(G.floats) do
        if not fl.t then
            fl.t, fl.x, fl.y = 0, x, y
            fl.fs:SetText(text)
            fl.fs:Show()
            return
        end
    end
end

-- board-center big float (clear-all bonus)
local function BigFloat(text)
    G.bigFs:SetText(text)
    G.bigT = 0
    G.bigFs:Show()
end

function G.HitItem(item, idx, ball)
    local kind = item.kind or "ball"
    -- gridLayer may carry a descend offset, but items are only triggered in FLY (offset 0), so use cell coords directly
    if kind == "ball" then
        table.remove(G.items, idx)
        local x, y = geo.CellCenter(item.col, item.row)
        FreeItemFrame(item)
        G.ballTotal = G.ballTotal + 1
        AddFloat(x, y, "+1")
        Snd("item")
        UpdateHUD()
        return
    end

    -- laser/bomb: persist the whole round, each ball triggers once, disappears at round end (after being triggered)
    if ball then
        ball.itemTouch = ball.itemTouch or {}
        if ball.itemTouch[item] then return end
        ball.itemTouch[item] = true
    end
    item.used = true

    local targets = {}
    if kind == "laserH" then
        FireBeamH(item.row)
        Snd("laser")
        local line = G.grid[item.row]
        for c = 0, geo.COLS - 1 do
            if line[c] then targets[#targets + 1] = line[c] end
        end
    elseif kind == "laserV" then
        FireBeamV(item.col)
        Snd("laser")
        for r = 1, geo.ROWS do
            local br = G.grid[r][item.col]
            if br then targets[#targets + 1] = br end
        end
    elseif kind == "bomb" then
        FireBoom(item.col, item.row)
        Snd("boom")
        for r = item.row - 1, item.row + 1 do
            local line = G.grid[r]
            if line then
                for c = item.col - 1, item.col + 1 do
                    if line[c] then targets[#targets + 1] = line[c] end
                end
            end
        end
    end
    for _, br in ipairs(targets) do G.HitBrick(br) end
end

function G.BallLanded(b)
    if not G.nextX then
        G.nextX = Clamp(b.x, geo.BALL_R + 4, geo.BOARD_W - geo.BALL_R - 4)
        Render.PlaceAt(DBR.playArea, G.marker, G.nextX, geo.FLOOR)
        G.marker:Show()
        Snd("land")
    end
    b.sliding = true
end

-- ------------------------------------------------------------
-- Spawn row / descend / game over
-- ------------------------------------------------------------
local function AddBrick(col, shape, orient, hp)
    local brick = { col = col, row = geo.ROWS, hp = hp, shape = shape, orient = orient }
    brick.frame = GetBrickFrame(shape, orient)
    brick.frame:SetHP(hp)
    Render.PlaceBrick(G.gridLayer, brick.frame, col, geo.ROWS)
    G.bricks[brick] = true
    G.grid[geo.ROWS][col] = brick
end

local function AddItem(col, kind)
    local it = { col = col, row = geo.ROWS, kind = kind, frame = GetItemFrame(kind) }
    PlaceItem(it)
    table.insert(G.items, it)
end

local function SpawnRow()
    local occupied = {}
    local itemCol = math.random(0, geo.COLS - 1)
    occupied[itemCol] = true

    local spawned = 0
    for col = 0, geo.COLS - 1 do
        if not occupied[col] and math.random() < BRICK_CHANCE then
            local shape = (math.random() < TRI_CHANCE) and "tri" or "sq"
            local orient = shape == "tri" and ORIENTS[math.random(4)] or nil
            local hp = G.round * ((math.random() < DOUBLE_CHANCE) and 2 or 1)
            AddBrick(col, shape, orient, hp)
            occupied[col] = true
            spawned = spawned + 1
        end
    end
    if spawned == 0 then
        -- guarantee one brick, the row can't be empty
        local empties = {}
        for col = 0, geo.COLS - 1 do
            if not occupied[col] then empties[#empties + 1] = col end
        end
        if #empties > 0 then
            local col = empties[math.random(#empties)]
            AddBrick(col, "sq", nil, G.round)
            occupied[col] = true
        end
    end

    AddItem(itemCol, "ball")

    -- special item (laser/bomb): spawned with some chance in a remaining empty cell
    if math.random() < SPECIAL_CHANCE then
        local empties = {}
        for col = 0, geo.COLS - 1 do
            if not occupied[col] then empties[#empties + 1] = col end
        end
        if #empties > 0 then
            AddItem(empties[math.random(#empties)], SPECIAL_KINDS[math.random(#SPECIAL_KINDS)])
        end
    end
end

local function GameOver()
    G.state = "OVER"
    if DodoBricksDB then DodoBricksDB.save = nil end
    local newBest = (G.round or 1) > (G.startBest or 0)
    local p = G.overPanel
    p.line1:SetText("Reached Level " .. (G.round or 1))
    if newBest then
        p.line2:SetText("|cffffd200New record!|r")
        Snd("best")
    else
        p.line2:SetText("Best: Level " .. (DodoBricksDB and DodoBricksDB.bestLevel or G.round or 1))
        Snd("over")
    end
    p:Show()
    Print("Game over, reached level " .. (G.round or 1) .. ".")
end

local function AutoSave()
    if not DodoBricksDB then return end
    local sv = { round = G.round, ballTotal = G.ballTotal, launchX = G.launchX, bricks = {}, items = {} }
    for brick in pairs(G.bricks) do
        sv.bricks[#sv.bricks + 1] = { col = brick.col, row = brick.row, hp = brick.hp,
                                      shape = brick.shape, orient = brick.orient }
    end
    for _, it in ipairs(G.items) do
        sv.items[#sv.items + 1] = { col = it.col, row = it.row, kind = it.kind or "ball" }
    end
    DodoBricksDB.save = sv
end

local function StartDescend()
    -- move the launcher to the first ball's landing spot
    if G.nextX then G.launchX = G.nextX end
    G.marker:Hide()
    PlaceLauncher()

    -- clear-all bonus: this round started with bricks, now none remain
    if G.turnHadBricks and next(G.bricks) == nil then
        G.ballTotal = G.ballTotal + CLEAR_BONUS
        BigFloat("Clear!  +" .. CLEAR_BONUS .. " balls")
        Snd("clear")
    end
    G.turnHadBricks = false
    SetCountText(G.ballTotal)

    -- triggered lasers/bombs: disappear at round end
    for i = #G.items, 1, -1 do
        local it = G.items[i]
        if it.used then
            table.remove(G.items, i)
            FreeItemFrame(it)
        end
    end

    -- still bricks in the bottom row => pushing again enters the launch strip, game over
    for brick in pairs(G.bricks) do
        if brick.row <= 1 then GameOver(); return end
    end

    -- bottom-row items: +1 ball is auto-collected before being pushed down, laser/bomb just disappear
    for i = #G.items, 1, -1 do
        local it = G.items[i]
        if it.row <= 1 then
            local x, y = geo.CellCenter(it.col, it.row)
            local kind = it.kind or "ball"
            table.remove(G.items, i)
            FreeItemFrame(it)
            if kind == "ball" then
                G.ballTotal = G.ballTotal + 1
                AddFloat(x, y - geo.CELL, "+1")
                Snd("item")
            end
        end
    end

    -- shift everything down one row (logic first, the animation slides the gridLayer offset from +CELL to 0)
    for brick in pairs(G.bricks) do
        brick.row = brick.row - 1
        Render.PlaceBrick(G.gridLayer, brick.frame, brick.col, brick.row)
    end
    for r = 1, geo.ROWS do wipe(G.grid[r]) end
    for brick in pairs(G.bricks) do G.grid[brick.row][brick.col] = brick end
    for _, it in ipairs(G.items) do
        it.row = it.row - 1
        PlaceItem(it)
    end

    -- new level
    G.round = (G.round or 0) + 1
    if DodoBricksDB and G.round > (DodoBricksDB.bestLevel or 0) then
        DodoBricksDB.bestLevel = G.round
    end
    SpawnRow()
    UpdateHUD()
    Snd("descend")

    G.descendT = 0
    G.gridLayer:ClearAllPoints()
    G.gridLayer:SetPoint("BOTTOMLEFT", DBR.playArea, "BOTTOMLEFT", 0, geo.CELL)
    G.state = "DESCEND"
end

local function UpdateDescend(dt)
    G.descendT = G.descendT + dt
    local p = G.descendT / DESCEND_T
    if p > 1 then p = 1 end
    local e = p * p * (3 - 2 * p)   -- smoothstep
    G.gridLayer:ClearAllPoints()
    G.gridLayer:SetPoint("BOTTOMLEFT", DBR.playArea, "BOTTOMLEFT", 0, geo.CELL * (1 - e))
    if p >= 1 then
        G.state = "AIM"
        AutoSave()
    end
end

-- ------------------------------------------------------------
-- Ball speed ramp: level base multiplier x in-round fast-forward (see the parameter comments at the top)
-- ------------------------------------------------------------
local function LevelMult()
    local m = 1 + LV_SPEED_GAIN * ((G.round or 1) - 1)
    return m < LV_SPEED_MAX and m or LV_SPEED_MAX
end

local function SpeedMult()
    local m = LevelMult()
    local t = G.flyT or 0
    if t > RAMP_START then
        local p = Clamp((t - RAMP_START) / (RAMP_FULL - RAMP_START), 0, 1)
        p = p * p * (3 - 2 * p)   -- smoothstep, smooth ramp with no jump
        m = m * (1 + (RAMP_MAX - 1) * p)
    end
    return m < SPEED_MULT_CAP and m or SPEED_MULT_CAP
end

-- HUD multiplier indicator: shown from x1.1 up, don't touch the text if the value (rounded to 0.1) hasn't changed
local function UpdateSpeedHUD(m)
    local shown = math.floor(m * 10 + 0.5) / 10
    if shown < 1.1 then shown = nil end
    if shown == G.speedShown then return end
    G.speedShown = shown
    if shown then
        G.hud.speed:SetFormattedText("Speed x%.1f", shown)
        G.hud.speed:Show()
    else
        G.hud.speed:Hide()
    end
end

-- ------------------------------------------------------------
-- Flight driver
-- ------------------------------------------------------------
local function UpdateLaunch(dt)
    if G.toLaunch <= 0 then return end
    G.launchTimer = G.launchTimer - dt
    while G.launchTimer <= 0 and G.toLaunch > 0 do
        local idx = G.ballsInPlay - G.toLaunch + 1
        local b = G.balls[idx]
        b.x, b.y = G.launchX, geo.FLOOR
        -- multi-ball spread: the first ball follows the aim line strictly (honest dashes), from the 2nd on randomly offset +-SPREAD_DEG/2 degrees
        local dx, dy = G.aimDirX, G.aimDirY
        if idx > 1 and SPREAD_DEG > 0 then
            local a = math.atan2(dy, dx) + (math.random() - 0.5) * math.rad(SPREAD_DEG)
            local lo, hi = math.rad(MIN_ANGLE), math.rad(180 - MIN_ANGLE)
            if a < lo then a = lo elseif a > hi then a = hi end
            dx, dy = math.cos(a), math.sin(a)
        end
        b.vx, b.vy = dx * Physics.SPEED, dy * Physics.SPEED
        b.flying, b.sliding, b.flatT, b.kick = true, false, 0, false
        b.itemTouch = nil
        for k = 1, TRAIL_MAX do b.hx[k], b.hy[k] = b.x, b.y end   -- trail unfurls from the muzzle point
        b.frame:Show()
        G.toLaunch = G.toLaunch - 1
        G.launchTimer = G.launchTimer + LAUNCH_GAP
        Snd("launch")
    end
    SetCountText(G.toLaunch)
end

local function UpdateSliding(dt)
    for i = 1, G.ballsInPlay do
        local b = G.balls[i]
        if b.sliding then
            local target = G.nextX or b.x
            local step = SLIDE_SPEED * dt
            local d = target - b.x
            if math.abs(d) <= step then
                b.sliding = false
                b.frame:Hide()
            else
                b.x = b.x + (d > 0 and step or -step)
            end
        end
    end
end

local function EnsureTrail(b, n)
    b.ghosts = b.ghosts or {}
    for k = #b.ghosts + 1, n do
        b.ghosts[k] = Render.NewGhost(DBR.playArea, k)
    end
end

local function SyncBalls()
    local pa = DBR.playArea
    local trailN = G.trailN or 0
    for i = 1, G.ballsInPlay do
        local b = G.balls[i]
        if b.flying or b.sliding then
            Render.MoveAt(pa, b.frame, b.x, b.y)
            b.frame:Show()
        else
            b.frame:Hide()
        end
        -- comet trail: drawn at the previous few frames' positions (only for balls in flight; landed sliding has no trail)
        local n = b.flying and trailN or 0
        if n > 0 then
            EnsureTrail(b, n)
            local hx, hy = b.hx, b.hy
            for k = 1, n do
                local g = b.ghosts[k]
                Render.MoveAt(pa, g, hx[k], hy[k])
                g:Show()
            end
            for k = n + 1, #b.ghosts do b.ghosts[k]:Hide() end
            -- shift history back one slot, record this frame's position (the next frame's "previous frame")
            for k = TRAIL_MAX, 2, -1 do hx[k], hy[k] = hx[k - 1], hy[k - 1] end
            hx[1], hy[1] = b.x, b.y
        elseif b.ghosts then
            for k = 1, #b.ghosts do b.ghosts[k]:Hide() end
        end
    end
end

local function CheckTurnEnd()
    if G.toLaunch > 0 then return end
    for i = 1, G.ballsInPlay do
        local b = G.balls[i]
        if b.flying or b.sliding then return end
    end
    StartDescend()
end

-- "+1" float + board-center big text
local function UpdateFloats(dt)
    for _, fl in ipairs(G.floats) do
        if fl.t then
            fl.t = fl.t + dt
            if fl.t >= 0.8 then
                fl.t = nil
                fl.fs:Hide()
            else
                local p = fl.t / 0.8
                fl.fs:ClearAllPoints()
                fl.fs:SetPoint("CENTER", DBR.playArea, "BOTTOMLEFT", fl.x, fl.y + 26 * p)
                fl.fs:SetAlpha(1 - p * p)
            end
        end
    end
    if G.bigT then
        G.bigT = G.bigT + dt
        if G.bigT >= 1.4 then
            G.bigT = nil
            G.bigFs:Hide()
        else
            local p = G.bigT / 1.4
            G.bigFs:ClearAllPoints()
            G.bigFs:SetPoint("CENTER", DBR.playArea, "CENTER", 0, 20 + 36 * p)
            G.bigFs:SetAlpha(1 - p * p)
        end
    end
end

-- item breathing pulse
local function PulseItems()
    local a = 0.55 + 0.35 * (0.5 + 0.5 * math.sin(GetTime() * 4))
    for _, it in ipairs(G.items) do
        if it.frame then it.frame.ring:SetAlpha(a) end
    end
end

function G.Driver(elapsed)
    if G.paused then return end
    UpdateFloats(elapsed)
    UpdateEffects(elapsed)
    if G.state == "AIM" then
        PulseItems()
        UpdateSpeedHUD(LevelMult())
        UpdateAim()
    elseif G.state == "FLY" then
        PulseItems()
        -- ball speed ramp = uniform fast-forward: launch interval / physics / landing slide use the same scaled dt, trajectory matches 1x
        G.flyT = (G.flyT or 0) + elapsed
        local m = SpeedMult()
        UpdateSpeedHUD(m)
        local dt = elapsed * m
        UpdateLaunch(dt)
        Physics.Step(G.ctx, dt)
        UpdateSliding(dt)
        SyncBalls()
        CheckTurnEnd()
    elseif G.state == "DESCEND" then
        UpdateSpeedHUD(LevelMult())
        UpdateDescend(elapsed)
    end
end

-- ------------------------------------------------------------
-- Combat pause / window hidden / back to menu
-- ------------------------------------------------------------
local function OnCombat(inCombat)
    if not G.ready then return end
    if inCombat then
        if DBR.frame and DBR.frame:IsShown() then
            G.paused = true
            G.lmbDown = false
            G.HideDots()
            G.pauseText:Show()
        end
    else
        if DBR.frame and DBR.frame:IsShown() then
            G.paused = false
            G.pauseText:Hide()
        end
    end
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function(_, event)
    OnCombat(event == "PLAYER_REGEN_DISABLED")
end)

function G.OnWindowHidden()
    G.paused = false
    G.lmbDown = false
    if G.ready then
        G.HideDots()
        G.pauseText:Hide()
    end
end

function G.ReturnToMenu()
    G.lmbDown = false
    if G.ready then
        G.HideDots()
        G.overPanel:Hide()
        G.pauseText:Hide()
    end
    if DBR.ShowStartScreen then DBR.ShowStartScreen() end
end

-- ------------------------------------------------------------
-- New game / save-load
-- ------------------------------------------------------------
function G.New()
    EnsureSetup()
    ClearBoard()
    G.overPanel:Hide()
    G.pauseText:Hide()
    G.paused, G.lmbDown = false, false
    G.round = 0
    G.ballTotal = 1
    G.ballsInPlay = 0
    G.toLaunch = 0
    G.launchX = geo.BOARD_W / 2
    G.nextX = nil
    G.turnHadBricks = false
    G.startBest = (DodoBricksDB and DodoBricksDB.bestLevel) or 0
    PlaceLauncher()
    G.launcher:Show()
    SetCountText(G.ballTotal)
    UpdateHUD()
    StartDescend()   -- the first row slides in, round becomes 1
end

function G.HasSave() return (DodoBricksDB and DodoBricksDB.save) ~= nil end

function G.Load()
    EnsureSetup()
    local sv = DodoBricksDB and DodoBricksDB.save
    if not sv then return false end
    ClearBoard()
    G.overPanel:Hide()
    G.pauseText:Hide()
    G.paused, G.lmbDown = false, false

    G.round = sv.round or 1
    G.ballTotal = sv.ballTotal or 1
    G.ballsInPlay = 0
    G.toLaunch = 0
    G.launchX = Clamp(sv.launchX or geo.BOARD_W / 2, geo.BALL_R + 4, geo.BOARD_W - geo.BALL_R - 4)
    G.nextX = nil
    G.startBest = (DodoBricksDB and DodoBricksDB.bestLevel) or 0

    G.gridLayer:ClearAllPoints()
    G.gridLayer:SetPoint("BOTTOMLEFT", DBR.playArea, "BOTTOMLEFT", 0, 0)

    for _, d in ipairs(sv.bricks or {}) do
        local row = d.row
        if row and row >= 1 and row <= geo.ROWS and d.col and d.col >= 0 and d.col < geo.COLS then
            local brick = { col = d.col, row = row, hp = d.hp or 1, shape = d.shape or "sq", orient = d.orient }
            brick.frame = GetBrickFrame(brick.shape, brick.orient)
            brick.frame:SetHP(brick.hp)
            Render.PlaceBrick(G.gridLayer, brick.frame, brick.col, brick.row)
            G.bricks[brick] = true
            G.grid[row][d.col] = brick
        end
    end
    for _, d in ipairs(sv.items or {}) do
        if d.row and d.row >= 1 and d.row <= geo.ROWS and d.col and d.col >= 0 and d.col < geo.COLS then
            local kind = d.kind or "ball"
            local it = { col = d.col, row = d.row, kind = kind, frame = GetItemFrame(kind) }
            PlaceItem(it)
            table.insert(G.items, it)
        end
    end

    PlaceLauncher()
    G.launcher:Show()
    SetCountText(G.ballTotal)
    UpdateHUD()
    G.state = "AIM"
    Print("Progress loaded: level " .. G.round .. ", balls x" .. G.ballTotal .. ".")
    return true
end
