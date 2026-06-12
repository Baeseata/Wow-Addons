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
local DESCEND_T    = 0.28   -- descend animation duration (seconds, 1 row)
local DESCEND_T2   = 0.40   -- descend animation duration for a double-descend event (2 rows)
local SLIDE_SPEED  = 1500   -- speed at which landed balls slide to the gather point (px/s)
local BRICK_CHANCE  = 0.45  -- per-cell brick spawn chance in a new row at level 1 (ramps up, see CHANCE_GAIN)
local TRI_CHANCE    = 0.20  -- chance a new brick is a triangle
local DOUBLE_CHANCE = 0.12  -- chance a new brick has double HP at level 1 (ramps up, see DBL_GAIN)
local ORIENTS = { "BL", "BR", "TL", "TR" }
local SPREAD_DEG    = 3     -- multi-ball spread: from the 2nd ball on, randomly offset +-SPREAD_DEG/2 degrees (the first follows the aim line strictly, so the dashes are honest)
local SPECIAL_CHANCE = 0.22 -- chance a new row spawns a special item (placed in an empty cell; +1 ball still guaranteed every row)
local CLEAR_BONUS   = 2     -- clear-all bonus balls (clearing the whole board in one round)

-- Difficulty curve (0.3.0): the old fixed numbers made output (balls x hits) outgrow supply (rows x hp)
-- ~3x past level ~50 = an unlosable autopilot. Supply now ramps superlinearly to keep tension alive.
local CHANCE_GAIN, CHANCE_CAP = 0.0045, 0.68   -- brick chance: 0.45 + gain*(lv-1), capped (hits cap ~lv 52)
local DBL_GAIN, DBL_CAP       = 0.0032, 0.28   -- double-hp chance: 0.12 + gain*(lv-1), capped (~lv 51)
local TRIPLE_FROM, TRIPLE_GAIN, TRIPLE_CAP = 35, 0.005, 0.15  -- triple-hp bricks fade in from lv 35 (~lv 65 cap)

-- Special items (0.3.0): weighted pool. laserD1 "/" and laserD2 "\" sweep one diagonal (direction shown by
-- the glyph - honest preview); laserX is the rare horizontal+vertical cross; split makes each ball that touches
-- it spawn ONE temp clone (this round only, never counts into ballTotal - hard rule, else ball count explodes).
local SPECIAL_W = { laserH = 22, laserV = 22, bomb = 20, laserD1 = 9, laserD2 = 9, split = 12, laserX = 4 }
local CHEST_DROP = { ball = 40, laserH = 12, laserV = 12, bomb = 12, laserD1 = 6, laserD2 = 6, split = 9, laserX = 3 }
local SPLIT_CAP = 140       -- max simultaneous active balls (real + temp), protects the frame rate

-- Special bricks (0.3.0)
local CHEST_FROM, CHEST_CHANCE, CHEST_HP, CHEST_BONUS = 8, 0.06, 2, 25   -- gold "?" brick: breaks into an item ring + bonus points
local HEALER_FROM, HEALER_CHANCE = 30, 0.08   -- green medic brick: at round end heals all 8 neighbors +1 hp - kill it first

-- Events (0.3.0): scheduled one round AHEAD with a flashing top-row warning (no surprise deaths).
-- Pool currently = double-descend only; the frame is built to take more kinds later.
local EVENT_FROM, EVENT_CHANCE, EVENT_CD = 30, 0.18, 4   -- from lv 30, ~18%/round, >=4 rounds between events

-- Boss (0.3.0): every 25 levels a 3x3 mega brick spawns instead of the normal row, swallowing whatever
-- it lands on (their hp folds into it). Drops 3 item rings + big score on death. From lv 75 its aura
-- heals ALL normal bricks +1/round ("the exam" - earlier bosses are just loot festivals).
-- 0.4.0 rebalance (playtest: boss 1 was a grind, boss 2 a wall): hp = BASE + (lv-25)*GAIN + eaten*EAT_RATE.
-- The old lv*35 + full eaten compounded twice - late bricks are fat, so "eaten" alone exploded.
local BOSS_EVERY, BOSS_AURA_FROM = 25, 75
local BOSS_BASE, BOSS_HP_GAIN, BOSS_EAT_RATE = 500, 14, 0.5

-- Bedrock (0.4.0): unbreakable grey filler brick. Balls bounce off (no damage, no score), lasers/bombs
-- ignore it, it rides the descend like any brick, and past the floor it simply leaves the board (never
-- a loss). Max 1 per row and never the same column as the previous row's one - a sealed pocket would
-- need 2 in one row, so the board can always be shot through.
local BEDROCK_FROM, BEDROCK_CHANCE, BEDROCK_GAIN, BEDROCK_CAP = 12, 0.10, 0.004, 0.32

-- Scoring (0.3.0): 1 hp chipped = 1 point; bricks on the bottom 2 rows pay DOUBLE (danger pay);
-- everything is multiplied by the clear-chain multiplier (consecutive full clears: x1 -> x2 -> ... x10, broken = back to x1).
local DANGER_ROWS, DANGER_MULT = 2, 2
local MULT_CAP = 10
local COMBO_WINDOW = 0.30   -- one ball hitting bricks faster than this chains an in-groove combo (sound ladder)
local SLOWMO_RATE = 0.25    -- slow-motion playback rate (last-brick clear / first-time item triggers / boss kill)
local TRAIL_MAX     = 3     -- max comet-trail segments (each segment = an afterimage of a previous frame's position)
local TRAIL_BUDGET  = 240   -- total trail-segment budget across the board: auto-shortens when there are many balls (<=80 balls 3 seg, <=120 balls 2 seg, more = 1 seg)

-- Ball speed ramp (0.2.3): a pure function of how long this round's balls have been in flight --
-- the longer they bounce, the faster the playback, from base speed up to RAMP_MAX x base.
-- No level scaling and no HUD indicator. Pure "time fast-forward" (uniformly scaling FLY's dt):
-- trajectory and landing are identical to 1x speed, only the playback is faster.
local RAMP_START = 3    -- seconds of flight before the ramp begins (short rounds feel nothing)
local RAMP_FULL  = 15   -- seconds of flight at which the ramp tops out (smoothstep in between)
local RAMP_MAX   = 3.0  -- top multiplier = 300% of base speed (set 1 to disable the ramp)

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

    -- floating-text pool ("+1" ball pickups, gold score pops; pool-limited - when all 10 are busy
    -- extra requests are silently dropped, the points still count, only the text is skipped)
    G.floats = {}
    for i = 1, 10 do
        local fs = pa:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
        fs:SetTextColor(0.4, 1, 0.5)
        fs:Hide()
        G.floats[i] = { fs = fs, t = nil, x = 0, y = 0 }
    end

    -- double-descend warning: the top row breathes red while an event is pending (the only telegraph - no text)
    local warn = CreateFrame("Frame", nil, pa)
    warn:SetPoint("BOTTOMLEFT", pa, "BOTTOMLEFT", 0, geo.FLOOR + (geo.ROWS - 1) * geo.CELL)
    warn:SetSize(geo.BOARD_W, geo.CELL)
    warn:SetFrameLevel((pa:GetFrameLevel() or 0) + 3)
    local warnTex = warn:CreateTexture(nil, "OVERLAY")
    warnTex:SetAllPoints()
    warnTex:SetColorTexture(1, 0.22, 0.18, 1)
    warnTex:SetBlendMode("ADD")
    warn:SetAlpha(0)
    warn:Hide()
    G.warnBar = warn

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
local function BrickKey(shape, orient, kind)
    if kind then return kind end                 -- healer / chest / boss have dedicated frames
    return shape == "tri" and ("tri_" .. orient) or "sq"
end

local function GetBrickFrame(shape, orient, kind)
    local key = BrickKey(shape, orient, kind)
    local pool = G.brickPool[key]
    local fr = pool and table.remove(pool)
    if not fr then
        if kind == "boss" then fr = Render.NewBossBrick(G.gridLayer)
        else fr = Render.NewBrick(G.gridLayer, shape, orient, kind) end
    end
    fr:Show()
    return fr
end

local function FreeBrickFrame(brick)
    brick.frame:Hide()
    local key = BrickKey(brick.shape, brick.orient, brick.kind)
    G.brickPool[key] = G.brickPool[key] or {}
    table.insert(G.brickPool[key], brick.frame)
    brick.frame = nil
end

-- grid registration for 1x1 and multi-cell (boss) bricks alike
local function GridSet(brick, on)
    for r = brick.row, brick.row + (brick.h or 1) - 1 do
        local line = G.grid[r]
        if line then
            for c = brick.col, brick.col + (brick.w or 1) - 1 do
                line[c] = on and brick or nil
            end
        end
    end
end

-- "any brick left that can actually be broken?" - bedrock is permanent scenery, so every
-- clear-all check (bonus balls / chain multiplier / last-brick slow-mo) must use this, not
-- next(G.bricks). Defined up here in the utility block: Fire / HitBrick / StartDescend all
-- call it and Lua locals resolve in lexical order.
local function AnyBreakableBrick()
    for brick in pairs(G.bricks) do
        if brick.kind ~= "bedrock" then return true end
    end
    return false
end

-- weighted random pick from a {key=weight} table
local function WeightedPick(tbl)
    local sum = 0
    for _, w in pairs(tbl) do sum = sum + w end
    local r = math.random() * sum
    for k, w in pairs(tbl) do
        r = r - w
        if r <= 0 then return k end
    end
    for k in pairs(tbl) do return k end
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

-- center of a brick (multi-cell aware: boss center = middle cell)
local function BrickCenter(brick)
    if brick.w and brick.w > 1 then
        local x0, y0 = geo.CellRect(brick.col, brick.row)
        return x0 + brick.w * geo.CELL / 2, y0 + (brick.h or brick.w) * geo.CELL / 2
    end
    return geo.CellCenter(brick.col, brick.row)
end

local function BrickFlash(brick)
    local cx, cy = BrickCenter(brick)
    if brick.kind == "boss" then
        SpawnEffect("fx_boss", function(p) return Render.NewBossFlash(p) end, cx, cy, 0.30, 0.18)
        return
    end
    local key = "fx_" .. BrickKey(brick.shape, brick.orient)
    local shape, orient = brick.shape, brick.orient
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

local function FireBeamD(col, row, ne)
    local cx, cy = geo.CellCenter(col, row)
    SpawnEffect(ne and "beamD1" or "beamD2", function(p) return Render.NewBeamD(p, ne) end,
        cx, cy, 0.2, 0)
end

-- colored pulse ring: healer pulse (green) / split pop (violet)
local function FirePop(key, x, y, r, g, b)
    SpawnEffect(key, function(p) return Render.NewPop(p, r, g, b) end, x, y, 0.35, 0.5)
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
    G.tempCount = 0
    G.slowmoT = 0
    if G.warnBar then G.warnBar:Hide() end
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

    local menuBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    menuBtn:SetSize(76, 21)
    menuBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -29)
    menuBtn:SetText("Menu")
    menuBtn:SetScript("OnClick", function() G.ReturnToMenu() end)

    local anchor = menuBtn
    if DBR.Sound and DBR.Sound.CreateToggle then
        local cb = DBR.Sound.CreateToggle(f, true)   -- compact version: no label, with tooltip
        cb:SetPoint("RIGHT", menuBtn, "LEFT", -4, 0)
        anchor = cb
    end

    -- score (gold), right-aligned next to the sound toggle; " xN" suffix shows the clear-chain multiplier
    hud.score = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hud.score:SetPoint("RIGHT", anchor, "LEFT", -10, 0)
    hud.score:SetTextColor(1, 0.85, 0.2)
    hud.score:SetText("0")
end

local function UpdateHUD()
    if not G.hud then return end
    G.hud.level:SetText("Level " .. (G.round or 1))
    G.hud.balls:SetText("Balls x" .. (G.ballTotal or 1))
    local s = tostring(G.score or 0)
    if (G.mult or 1) >= 2 then s = s .. " |cffff7f1ax" .. G.mult .. "|r" end
    G.hud.score:SetText(s)
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
    for i = 1, #G.balls do   -- reset the WHOLE pool: higher slots may carry stale temp clones from last round
        local b = G.balls[i]
        b.flying, b.sliding, b.flatT, b.kick, b.temp = false, false, 0, false, nil
        b.itemTouch = nil
        b.comboN, b.lastHitT = nil, nil
        b.frame:Hide()
    end
    G.tempCount = 0
    G.ballsInPlay = G.ballTotal
    G.toLaunch = G.ballTotal
    G.launchTimer = 0
    G.flyT = 0               -- this round's flight timer (for the ball speed ramp, real seconds)
    G.slowmoT = 0
    G.nextX = nil
    G.turnHadBricks = AnyBreakableBrick()   -- a bedrock-only board must not count as a clearable turn
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
local function AddFloat(x, y, text, r, g, b)
    for _, fl in ipairs(G.floats) do
        if not fl.t then
            fl.t, fl.x, fl.y = 0, x, y
            fl.fs:SetText(text)
            fl.fs:SetTextColor(r or 0.4, g or 1, b or 0.5)
            fl.fs:Show()
            return
        end
    end
end

-- board-center big float (clear-all bonus / boss down)
local function BigFloat(text)
    G.bigFs:SetText(text)
    G.bigT = 0
    G.bigFs:Show()
end

-- first-ever trigger of an item kind: 0.45s slow motion = the wordless tutorial moment (per-account, DodoBricksDB.seen)
local function MarkSeen(kind)
    local db = DodoBricksDB
    if not db then return end
    db.seen = db.seen or {}
    if not db.seen[kind] then
        db.seen[kind] = true
        G.slowmoT = math.max(G.slowmoT or 0, 0.45)
    end
end

-- brick / item factories (placed before HitBrick: chest breaks spawn item rings mid-flight)
local function AddBrick(col, row, shape, orient, hp, kind, extra)
    local brick = { col = col, row = row, hp = hp, shape = shape, orient = orient, kind = kind }
    if extra then for k, v in pairs(extra) do brick[k] = v end end
    brick.frame = GetBrickFrame(shape, orient, kind)
    brick.frame:SetHP(hp)
    Render.PlaceBrick(G.gridLayer, brick.frame, col, row)
    G.bricks[brick] = true
    GridSet(brick, true)
    return brick
end

local function AddItem(col, kind, row)
    local it = { col = col, row = row or geo.ROWS, kind = kind, frame = GetItemFrame(kind) }
    PlaceItem(it)
    table.insert(G.items, it)
end

-- split item: the touching REAL ball spawns one temp clone (same speed, angle nudged 18-36 degrees).
-- Temp balls live this round only: they never count into ballTotal, vanish on landing, and cannot
-- trigger items themselves (both rules are hard - they keep the ball economy from exploding).
local function SpawnTempBall(src)
    local active = G.ballsInPlay + (G.tempCount or 0)
    if active >= SPLIT_CAP then return end
    G.tempCount = (G.tempCount or 0) + 1
    local idx = G.ballsInPlay + G.tempCount
    EnsureBalls(idx)
    local b = G.balls[idx]
    b.temp = true
    b.x, b.y = src.x, src.y
    local ang = math.atan2(src.vy, src.vx)
        + ((math.random() < 0.5) and -1 or 1) * math.rad(18 + math.random() * 18)
    b.vx, b.vy = math.cos(ang) * Physics.SPEED, math.sin(ang) * Physics.SPEED
    b.flying, b.sliding, b.flatT, b.kick = true, false, 0, false
    b.itemTouch = nil
    for k = 1, TRAIL_MAX do b.hx[k], b.hy[k] = b.x, b.y end
    b.frame:Show()
    -- re-share the trail budget across the grown ball count
    G.trailN = math.min(TRAIL_MAX, math.floor(TRAIL_BUDGET / math.max(1, G.ballsInPlay + G.tempCount)))
end

function G.HitBrick(brick, ball)
    if not G.bricks[brick] then return end   -- already broken this frame by a laser/bomb chain
    if brick.kind == "bedrock" then
        -- unbreakable: the ball already bounced in Physics; just flash as feedback. No damage,
        -- no score, no combo bookkeeping (it neither extends nor breaks a ball's hit chain).
        BrickFlash(brick)
        Snd("hit")
        return
    end
    brick.hp = brick.hp - 1

    -- scoring: 1 point per hp chipped, doubled in the danger rows, times the clear-chain multiplier
    local gain = ((brick.row <= DANGER_ROWS) and DANGER_MULT or 1) * (G.mult or 1)
    G.score = (G.score or 0) + gain
    brick.scoreGiven = (brick.scoreGiven or 0) + gain

    -- in-groove combo (per ball): hits faster than COMBO_WINDOW chain up, sound ladder from tier 4
    local comboTier
    if ball then
        local now = GetTime()
        if now - (ball.lastHitT or -10) < COMBO_WINDOW then
            ball.comboN = (ball.comboN or 0) + 1
        else
            ball.comboN = 1
        end
        ball.lastHitT = now
        if ball.comboN >= 4 then comboTier = math.min(ball.comboN - 3, 5) end
    end

    if brick.hp <= 0 then
        BrickFlash(brick)
        GridSet(brick, nil)
        G.bricks[brick] = nil
        local cx, cy = BrickCenter(brick)
        if brick.kind == "chest" then
            local bonus = CHEST_BONUS * (G.mult or 1)
            G.score = G.score + bonus
            AddItem(brick.col, WeightedPick(CHEST_DROP), brick.row)   -- the drop ring appears in place, ready to be triggered
            AddFloat(cx, cy, "+" .. bonus, 1, 0.85, 0.2)
            Snd("item")
        elseif brick.kind == "boss" then
            local bonus = brick.maxHp or 0
            G.score = G.score + bonus
            for c = brick.col, brick.col + (brick.w or 3) - 1 do
                AddItem(c, WeightedPick(CHEST_DROP), brick.row + 1)
            end
            BigFloat("BOSS DOWN!  +" .. bonus)
            FireBoom(brick.col + 1, brick.row + 1)
            G.slowmoT = math.max(G.slowmoT or 0, 0.6)
            Snd("best")
        else
            AddFloat(cx, cy, "+" .. brick.scoreGiven, 1, 0.85, 0.2)
        end
        FreeBrickFrame(brick)
        Snd("brk")
        -- last brick of a full clear: brief slow-mo as the board empties (the ritual moment)
        if G.turnHadBricks and not AnyBreakableBrick() and G.state == "FLY" then
            G.slowmoT = math.max(G.slowmoT or 0, 0.35)
        end
    else
        if brick.kind then BrickFlash(brick) end   -- fixed-color bricks flash instead of recoloring
        brick.frame:SetHP(brick.hp)
        if comboTier then
            if DBR.Sound then DBR.Sound.PlayCombo(comboTier) end
        else
            Snd("hit")
        end
    end
    G.hudDirty = true   -- score changes hundreds of times/s at 100 balls; the Driver repaints once per frame
end

-- collect bricks along one diagonal ray from (col,row); a multi-cell boss crossed on several
-- cells is collected several times = takes several hits from one sweep (big target eats full AOE, intended)
local function DiagTargets(col, row, dc, dr, out)
    local c, r = col + dc, row + dr
    while c >= 0 and c < geo.COLS and r >= 1 and r <= geo.ROWS do
        local br = G.grid[r][c]
        if br then out[#out + 1] = br end
        c, r = c + dc, r + dr
    end
end

function G.HitItem(item, idx, ball)
    if ball and ball.temp then return end   -- temp balls only break bricks, never trigger items (no chain reactions)
    local kind = item.kind or "ball"
    -- gridLayer may carry a descend offset, but items are only triggered in FLY (offset 0), so use cell coords directly
    if kind == "ball" then
        table.remove(G.items, idx)
        local x, y = geo.CellCenter(item.col, item.row)
        FreeItemFrame(item)
        G.ballTotal = G.ballTotal + 1
        AddFloat(x, y, "+1")
        Snd("item")
        G.hudDirty = true
        return
    end

    -- special items: persist the whole round, each ball triggers once, disappear at round end (after being triggered)
    if ball then
        ball.itemTouch = ball.itemTouch or {}
        if ball.itemTouch[item] then return end
        ball.itemTouch[item] = true
    end
    item.used = true
    MarkSeen(kind)   -- first-ever trigger of this kind = brief slow-mo, the wordless tutorial

    if kind == "split" then
        local x, y = geo.CellCenter(item.col, item.row)
        FirePop("popSplit", x, y, 0.72, 0.52, 0.95)
        Snd("split")
        if ball then SpawnTempBall(ball) end
        return
    end

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
    elseif kind == "laserD1" then            -- "/" sweep: up-right + down-left
        FireBeamD(item.col, item.row, true)
        Snd("laser")
        DiagTargets(item.col, item.row, 1, 1, targets)
        DiagTargets(item.col, item.row, -1, -1, targets)
    elseif kind == "laserD2" then            -- "\" sweep: up-left + down-right
        FireBeamD(item.col, item.row, false)
        Snd("laser")
        DiagTargets(item.col, item.row, -1, 1, targets)
        DiagTargets(item.col, item.row, 1, -1, targets)
    elseif kind == "laserX" then             -- rare cross: full row + full column at once
        FireBeamH(item.row)
        FireBeamV(item.col)
        Snd("laser")
        local line = G.grid[item.row]
        for c = 0, geo.COLS - 1 do
            if line[c] then targets[#targets + 1] = line[c] end
        end
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
    if b.temp then
        -- temp clones evaporate on landing: no gather slide, never set the next launch point
        b.frame:Hide()
        if b.ghosts then for k = 1, #b.ghosts do b.ghosts[k]:Hide() end end
        return
    end
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
local function PickEmpty(occupied)
    local empties = {}
    for col = 0, geo.COLS - 1 do
        if not occupied[col] then empties[#empties + 1] = col end
    end
    if #empties == 0 then return nil end
    return empties[math.random(#empties)]
end

-- Spawn one fresh row at targetRow (ROWS normally; a double-descend also fills ROWS-1).
-- All spawn chances follow the difficulty curve (see the constants block up top).
local function SpawnRow(targetRow)
    local N = G.round
    local brickChance = math.min(CHANCE_CAP, BRICK_CHANCE + CHANCE_GAIN * (N - 1))
    local dblChance   = math.min(DBL_CAP, DOUBLE_CHANCE + DBL_GAIN * (N - 1))
    local triChance   = (N >= TRIPLE_FROM) and math.min(TRIPLE_CAP, TRIPLE_GAIN * (N - TRIPLE_FROM)) or 0

    local occupied = {}
    local itemCol = math.random(0, geo.COLS - 1)
    occupied[itemCol] = true

    local spawned = 0
    for col = 0, geo.COLS - 1 do
        if not occupied[col] and math.random() < brickChance then
            local shape = (math.random() < TRI_CHANCE) and "tri" or "sq"
            local orient = shape == "tri" and ORIENTS[math.random(4)] or nil
            local mul, r = 1, math.random()
            if r < triChance then mul = 3
            elseif r < triChance + dblChance then mul = 2 end
            AddBrick(col, targetRow, shape, orient, N * mul)
            occupied[col] = true
            spawned = spawned + 1
        end
    end
    if spawned == 0 then
        -- guarantee one brick, the row can't be empty
        local col = PickEmpty(occupied)
        if col then
            AddBrick(col, targetRow, "sq", nil, N)
            occupied[col] = true
        end
    end

    AddItem(itemCol, "ball", targetRow)

    -- healer brick ("the medic"): low hp, heals its 8 neighbors +1 at every round end - a priority target
    if N >= HEALER_FROM and math.random() < HEALER_CHANCE then
        local col = PickEmpty(occupied)
        if col then
            AddBrick(col, targetRow, "sq", nil, math.max(1, math.ceil(N / 5)), "healer")
            occupied[col] = true
        end
    end

    -- chest brick: 2 hp, breaks into an item ring + bonus points - a juicy aim target
    if N >= CHEST_FROM and math.random() < CHEST_CHANCE then
        local col = PickEmpty(occupied)
        if col then
            AddBrick(col, targetRow, "sq", nil, CHEST_HP, "chest")
            occupied[col] = true
        end
    end

    -- bedrock: at most 1 per row, never in the same column as the previous row's one (no vertical
    -- pillars, and a sealed pocket would need 2 in one row - so the board can always be shot through).
    -- hp 1 is a dummy: HitBrick returns before any damage. Runs after the guaranteed brick on purpose.
    local prevBedCol = G.lastBedrockCol
    G.lastBedrockCol = nil
    if N >= BEDROCK_FROM then
        local bedChance = math.min(BEDROCK_CAP, BEDROCK_CHANCE + BEDROCK_GAIN * (N - BEDROCK_FROM))
        if math.random() < bedChance then
            local col = PickEmpty(occupied)
            if col and col ~= prevBedCol then
                AddBrick(col, targetRow, "sq", nil, 1, "bedrock")
                occupied[col] = true
                G.lastBedrockCol = col
            end
        end
    end

    -- special item: weighted pick from the pool, placed in a remaining empty cell
    if math.random() < SPECIAL_CHANCE then
        local col = PickEmpty(occupied)
        if col then
            AddItem(col, WeightedPick(SPECIAL_W), targetRow)
        end
    end
end

-- Boss spawn (every BOSS_EVERY levels, replaces the normal row): a 3x3 mega brick drops onto the top
-- three rows, swallowing whatever bricks/items it lands on (their hp folds into the boss - dramatic and simple).
local function SpawnBoss()
    local N = G.round
    local col = math.random(0, geo.COLS - 3)
    local row = geo.ROWS - 2
    local eaten = 0
    for r = row, row + 2 do
        for c = col, col + 2 do
            local br = G.grid[r] and G.grid[r][c]
            if br and G.bricks[br] then
                eaten = eaten + math.max(0, br.hp)
                GridSet(br, nil)
                G.bricks[br] = nil
                FreeBrickFrame(br)
            end
        end
    end
    for i = #G.items, 1, -1 do
        local it = G.items[i]
        if it.row >= row and it.col >= col and it.col <= col + 2 then
            table.remove(G.items, i)
            FreeItemFrame(it)
        end
    end
    -- 0.4.0: flat base + gentle per-level growth + only half the eaten hp (late-game bricks are so
    -- fat that full folding alone made boss 2 unkillable in playtests)
    local hp = BOSS_BASE + (N - BOSS_EVERY) * BOSS_HP_GAIN + math.floor(eaten * BOSS_EAT_RATE)
    AddBrick(col, row, "sq", nil, hp, "boss", { w = 3, h = 3, maxHp = hp, spawnLevel = N })
    Snd("boom")
end

local function GameOver()
    G.state = "OVER"
    if DodoBricksDB then DodoBricksDB.save = nil end
    if G.warnBar then G.warnBar:Hide() end
    local lv, sc = G.round or 1, G.score or 0
    local newLv = lv > (G.startBest or 0)
    local newSc = sc > (G.startBestScore or 0)
    local p = G.overPanel
    p.line1:SetText("Level " .. lv .. "  -  Score " .. sc)
    if newLv or newSc then
        p.line2:SetText("|cffffd200New record!|r")
        Snd("best")
    else
        local db = DodoBricksDB
        p.line2:SetText("Best: Level " .. ((db and db.bestLevel) or lv)
            .. "  -  Score " .. ((db and db.bestScore) or sc))
        Snd("over")
    end
    p:Show()
    Print("Game over: level " .. lv .. ", score " .. sc .. ".")
end

local function AutoSave()
    if not DodoBricksDB then return end
    local sv = { round = G.round, ballTotal = G.ballTotal, launchX = G.launchX,
                 score = G.score, mult = G.mult, pendingDouble = G.pendingDouble or nil,
                 eventCd = G.eventCd, bricks = {}, items = {} }
    for brick in pairs(G.bricks) do
        sv.bricks[#sv.bricks + 1] = { col = brick.col, row = brick.row, hp = brick.hp,
                                      shape = brick.shape, orient = brick.orient,
                                      kind = brick.kind, w = brick.w, h = brick.h,
                                      maxHp = brick.maxHp, spawnLevel = brick.spawnLevel }
    end
    for _, it in ipairs(G.items) do
        sv.items[#sv.items + 1] = { col = it.col, row = it.row, kind = it.kind or "ball" }
    end
    DodoBricksDB.save = sv
end

-- Round-end heals: every healer brick gives its 8 neighbors +1 hp (normal bricks only - healers
-- don't stack-heal each other, chests/bosses are excluded); a lv75+ boss aura heals ALL normal bricks.
local function HealerPulse()
    local healed = false
    for brick in pairs(G.bricks) do
        if brick.kind == "healer" then
            local cx, cy = BrickCenter(brick)
            FirePop("popHeal", cx, cy, 0.3, 1, 0.45)
            healed = true
            for r = brick.row - 1, brick.row + 1 do
                local line = G.grid[r]
                if line then
                    for c = brick.col - 1, brick.col + 1 do
                        local t = line[c]
                        if t and t ~= brick and not t.kind then
                            t.hp = t.hp + 1
                            t.frame:SetHP(t.hp)
                        end
                    end
                end
            end
        elseif brick.kind == "boss" and (brick.spawnLevel or 0) >= BOSS_AURA_FROM then
            local cx, cy = BrickCenter(brick)
            FirePop("popHeal", cx, cy, 0.3, 1, 0.45)
            healed = true
            for t in pairs(G.bricks) do
                if not t.kind then
                    t.hp = t.hp + 1
                    t.frame:SetHP(t.hp)
                end
            end
        end
    end
    if healed then Snd("heal") end
end

local function BossAlive()
    for brick in pairs(G.bricks) do
        if brick.kind == "boss" then return true end
    end
    return false
end

local function StartDescend()
    -- move the launcher to the first ball's landing spot
    if G.nextX then G.launchX = G.nextX end
    G.marker:Hide()
    PlaceLauncher()

    -- clear-all: bonus balls + the clear-chain multiplier climbs; surviving bricks break the chain
    -- (surviving bedrock doesn't - it can't be broken, so it neither blocks nor grants a clear)
    if G.turnHadBricks then
        if not AnyBreakableBrick() then
            G.ballTotal = G.ballTotal + CLEAR_BONUS
            G.mult = math.min((G.mult or 1) + 1, MULT_CAP)
            if G.mult >= 2 then
                BigFloat("Clear!  +" .. CLEAR_BONUS .. " balls  x" .. G.mult)
            else
                BigFloat("Clear!  +" .. CLEAR_BONUS .. " balls")
            end
            Snd("clear")
        else
            G.mult = 1
        end
    end
    G.turnHadBricks = false
    SetCountText(G.ballTotal)

    -- triggered specials: disappear at round end
    for i = #G.items, 1, -1 do
        local it = G.items[i]
        if it.used then
            table.remove(G.items, i)
            FreeItemFrame(it)
        end
    end

    -- healer bricks / boss aura do their round-end healing before the board moves
    HealerPulse()

    -- double-descend event: scheduled last round (top row was flashing), executes now - 2 rows at once
    local rows = G.pendingDouble and 2 or 1
    G.pendingDouble = nil
    if G.warnBar then G.warnBar:Hide() end

    -- bricks within `rows` of the strip => this push shoves them past the floor, game over.
    -- Bedrock is the exception: it just slides off the board (removing during pairs() is fine
    -- in Lua as long as we only delete the current key).
    for brick in pairs(G.bricks) do
        if brick.row <= rows then
            if brick.kind == "bedrock" then
                GridSet(brick, nil)
                G.bricks[brick] = nil
                FreeBrickFrame(brick)
            else
                GameOver(); return
            end
        end
    end

    -- low items: +1 ball is auto-collected before being pushed out, others just disappear
    for i = #G.items, 1, -1 do
        local it = G.items[i]
        if it.row <= rows then
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

    -- shift everything down (logic first, the animation slides the gridLayer offset from +rows*CELL to 0)
    for brick in pairs(G.bricks) do
        brick.row = brick.row - rows
        Render.PlaceBrick(G.gridLayer, brick.frame, brick.col, brick.row)
    end
    for r = 1, geo.ROWS do wipe(G.grid[r]) end
    for brick in pairs(G.bricks) do GridSet(brick, true) end
    for _, it in ipairs(G.items) do
        it.row = it.row - rows
        PlaceItem(it)
    end

    -- new level
    G.round = (G.round or 0) + 1
    local db = DodoBricksDB
    if db then
        if G.round > (db.bestLevel or 0) then db.bestLevel = G.round end
        if (G.score or 0) > (db.bestScore or 0) then db.bestScore = G.score end
    end
    Render.colorShift = math.floor((G.round - 1) / 10)   -- palette rotates every 10 levels ("new season")

    -- spawn: boss level = the boss IS the row; otherwise normal row(s)
    if (G.round % BOSS_EVERY) == 0 and not BossAlive() then
        SpawnBoss()
    else
        SpawnRow(geo.ROWS)
        if rows == 2 then SpawnRow(geo.ROWS - 1) end
    end
    UpdateHUD()
    Snd("descend")

    -- schedule the next event (one round ahead, telegraphed by the flashing top row; never on a boss
    -- level, never while a boss lives - its 3x3 body would overlap the second spawned row)
    G.eventCd = math.max(0, (G.eventCd or 0) - 1)
    local nxt = G.round + 1
    if nxt >= EVENT_FROM and G.eventCd <= 0 and (nxt % BOSS_EVERY) ~= 0
        and not BossAlive() and math.random() < EVENT_CHANCE then
        G.pendingDouble = true
        G.eventCd = EVENT_CD
        if G.warnBar then G.warnBar:Show() end
    end

    G.descendRows = rows
    G.descendT = 0
    G.gridLayer:ClearAllPoints()
    G.gridLayer:SetPoint("BOTTOMLEFT", DBR.playArea, "BOTTOMLEFT", 0, geo.CELL * rows)
    G.state = "DESCEND"
end

local function UpdateDescend(dt)
    G.descendT = G.descendT + dt
    local rows = G.descendRows or 1
    local p = G.descendT / (rows == 2 and DESCEND_T2 or DESCEND_T)
    if p > 1 then p = 1 end
    local e = p * p * (3 - 2 * p)   -- smoothstep
    G.gridLayer:ClearAllPoints()
    G.gridLayer:SetPoint("BOTTOMLEFT", DBR.playArea, "BOTTOMLEFT", 0, geo.CELL * rows * (1 - e))
    if p >= 1 then
        G.state = "AIM"
        AutoSave()
    end
end

-- ------------------------------------------------------------
-- Ball speed ramp: a pure function of this round's flight time (see the parameter comments at the top)
-- ------------------------------------------------------------
local function SpeedMult()
    local t = G.flyT or 0
    if t <= RAMP_START then return 1 end
    local p = Clamp((t - RAMP_START) / (RAMP_FULL - RAMP_START), 0, 1)
    p = p * p * (3 - 2 * p)   -- smoothstep, smooth ramp with no jump
    return 1 + (RAMP_MAX - 1) * p
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
    for i = 1, G.ballsInPlay do   -- temp clones never slide, real balls only
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
    for i = 1, G.ballsInPlay + (G.tempCount or 0) do   -- temp clones render exactly like real balls
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
    for i = 1, G.ballsInPlay + (G.tempCount or 0) do   -- a flying temp clone also holds the round open
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

    -- double-descend telegraph: the top row breathes red while the event is pending
    if G.pendingDouble and G.warnBar then
        G.warnBar:SetAlpha(0.10 + 0.13 * (0.5 + 0.5 * math.sin(GetTime() * 5)))
    end

    if G.state == "AIM" then
        PulseItems()
        UpdateAim()
    elseif G.state == "FLY" then
        PulseItems()
        -- ball speed ramp = uniform fast-forward: launch interval / physics / landing slide use the same scaled dt, trajectory matches 1x
        -- slow motion (last-brick clear / first item trigger / boss kill) overrides the ramp while it lasts
        G.flyT = (G.flyT or 0) + elapsed
        local mult = SpeedMult()
        if (G.slowmoT or 0) > 0 then
            G.slowmoT = G.slowmoT - elapsed
            mult = SLOWMO_RATE
        end
        local dt = elapsed * mult
        UpdateLaunch(dt)
        Physics.Step(G.ctx, dt)
        UpdateSliding(dt)
        SyncBalls()
        CheckTurnEnd()
    elseif G.state == "DESCEND" then
        UpdateDescend(elapsed)
    end

    if G.hudDirty then
        G.hudDirty = nil
        UpdateHUD()
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
    G.score = 0
    G.mult = 1
    G.pendingDouble = nil
    G.eventCd = 0
    G.lastBedrockCol = nil
    G.startBest = (DodoBricksDB and DodoBricksDB.bestLevel) or 0
    G.startBestScore = (DodoBricksDB and DodoBricksDB.bestScore) or 0
    Render.colorShift = 0
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
    G.score = sv.score or 0          -- 0.2.x saves carry no score: start counting from here
    G.mult = sv.mult or 1
    G.pendingDouble = sv.pendingDouble or nil
    G.eventCd = sv.eventCd or 0
    G.lastBedrockCol = nil   -- not saved; worst case one adjacent-column bedrock after a load
    G.startBest = (DodoBricksDB and DodoBricksDB.bestLevel) or 0
    G.startBestScore = (DodoBricksDB and DodoBricksDB.bestScore) or 0
    Render.colorShift = math.floor((G.round - 1) / 10)
    if G.warnBar then
        if G.pendingDouble then G.warnBar:Show() else G.warnBar:Hide() end
    end

    G.gridLayer:ClearAllPoints()
    G.gridLayer:SetPoint("BOTTOMLEFT", DBR.playArea, "BOTTOMLEFT", 0, 0)

    for _, d in ipairs(sv.bricks or {}) do
        local row = d.row
        if row and row >= 1 and row <= geo.ROWS and d.col and d.col >= 0 and d.col < geo.COLS then
            local brick = { col = d.col, row = row, hp = d.hp or 1, shape = d.shape or "sq", orient = d.orient,
                            kind = d.kind, w = d.w, h = d.h, maxHp = d.maxHp, spawnLevel = d.spawnLevel }
            brick.frame = GetBrickFrame(brick.shape, brick.orient, brick.kind)
            brick.frame:SetHP(brick.hp)
            Render.PlaceBrick(G.gridLayer, brick.frame, brick.col, brick.row)
            G.bricks[brick] = true
            GridSet(brick, true)
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
