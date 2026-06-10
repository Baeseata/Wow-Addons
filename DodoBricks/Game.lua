-- DodoBricks - Game
-- 状态机 + 回合循环 + 输入 + HUD + 存读档 + 进战暂停。
-- 状态:AIM 瞄准(按住左键拖,松开发射,右键取消)-> FLY 球群飞行(依次发射、落地回收、
--       首球落点 = 下回合发射点)-> DESCEND 砖整体下压一行 + 顶部刷新行(动画)-> 回 AIM。
--       砖被压到最底行再下压 = OVER 游戏结束。关数 = 已刷行数,新砖血量 = 当前关数(小概率双倍)。
-- 存档:回合制,每次回到 AIM 自动存(1 档);游戏结束清档;最高关卡记 DodoBricksDB.bestLevel。

local DBR = _G.DodoBricks or {}
_G.DodoBricks = DBR

local G = {}
DBR.Game = G

local geo, Physics, Render

-- 可调参数
local LAUNCH_GAP   = 0.07   -- 发球间隔(秒)
local MIN_AIM_DIST = 16     -- 鼠标离发射点近于此 = 无效瞄准(松开不发射)
local MIN_ANGLE    = 8      -- 最低发射仰角(度,防贴地平射)
local AIM_MAX_LEN  = 900    -- 瞄准首段最大长度(px)
local STUB_LEN     = 70     -- 首段碰撞后的反弹提示短段长度
local DOT_GAP      = 18     -- 瞄准虚线点间距
local DOT_SPEED    = 60     -- 虚线行进速度(px/s)
local DESCEND_T    = 0.28   -- 下压动画时长(秒)
local SLIDE_SPEED  = 1500   -- 落地球滑向集合点的速度(px/s)
local BRICK_CHANCE  = 0.45  -- 刷新行每格出砖概率(道具格除外;一块不出则保底 1 块)
local TRI_CHANCE    = 0.20  -- 新砖为三角形概率
local DOUBLE_CHANCE = 0.12  -- 新砖双倍血概率("硬砖")
local ORIENTS = { "BL", "BR", "TL", "TR" }
local SPREAD_DEG    = 3     -- 多球散布:第 2 颗起随机偏 ±SPREAD_DEG/2 度(首颗严格按瞄准线,虚线才诚实)
local SPECIAL_CHANCE = 0.22 -- 刷新行出特殊道具(激光/炸弹)概率(放在空格里,+1 球照旧每行必有)
local SPECIAL_KINDS = { "laserH", "laserV", "bomb" }
local CLEAR_BONUS   = 2     -- 全清奖励球数(一回合打空全场)

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
-- 构件(只建一次):砖/道具/球/虚线点各自带对象池
-- ------------------------------------------------------------
local function EnsureSetup()
    if G.ready then return end
    G.ready = true
    geo, Physics, Render = DBR.geo, DBR.Physics, DBR.Render
    local pa = DBR.playArea

    -- 砖/道具挂在 gridLayer 上;下压动画只动这一层的锚点偏移
    local gl = CreateFrame("Frame", nil, pa)
    gl:SetSize(geo.BOARD_W, geo.BOARD_H)
    gl:SetPoint("BOTTOMLEFT", pa, "BOTTOMLEFT", 0, 0)
    gl:SetFrameLevel((pa:GetFrameLevel() or 0) + 2)
    G.gridLayer = gl

    G.bricks = {}            -- set:brick -> true
    G.grid = {}              -- grid[row][col] = brick
    for r = 1, geo.ROWS do G.grid[r] = {} end
    G.items = {}             -- array:{ col, row, kind, frame }(kind: ball/laserH/laserV/bomb)
    G.balls = {}             -- 球结构池(随 ballTotal 增长)
    G.brickPool = {}         -- 回收池:key("sq"/"tri_BL"...) -> {frame...}
    G.itemPool = {}          -- 道具回收池:kind -> {frame...}
    G.dots = {}
    G.effects = {}           -- 活动特效:{ key, frame, t, dur, grow }
    G.effectPool = {}        -- 特效回收池:key -> {frame...}

    -- 发射台:白球 + 余量文字 + 下回合落点虚影
    G.launcher = Render.NewBall(pa)
    G.countText = pa:CreateFontString(nil, "OVERLAY")
    G.countText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    G.countText:SetTextColor(1, 1, 1, 0.95)
    G.marker = Render.NewBall(pa)
    G.marker:SetAlpha(0.35)
    G.marker:Hide()

    -- 战斗暂停提示
    local pause = pa:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    pause:SetPoint("CENTER", pa, "CENTER", 0, 40)
    pause:SetTextColor(1, 0.4, 0.4)
    pause:SetText("战斗中已暂停")
    pause:Hide()
    G.pauseText = pause

    -- "+1" 飘字池
    G.floats = {}
    for i = 1, 4 do
        local fs = pa:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
        fs:SetTextColor(0.4, 1, 0.5)
        fs:Hide()
        G.floats[i] = { fs = fs, t = nil, x = 0, y = 0 }
    end

    -- 大字飘报(全清奖励等,板中央)
    G.bigFs = pa:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    G.bigFs:SetTextColor(1, 0.85, 0.2)
    G.bigFs:Hide()
    G.bigT = nil

    -- 物理上下文(表常驻,字段引用共享)
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

    -- 输入 + 驱动
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
-- 砖 / 道具池
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
-- 特效池(碎砖闪光 / 激光束 / 爆炸圈):ADD 发光,放大+淡出后回收。
-- 结构 = 锚点占位帧(定位,不缩放)+ 视觉子帧(零偏移居中,缩放它):
-- WoW 的 SetScale 会连锚点偏移一起缩放,直接缩放带大偏移的帧会漂移。
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
    for _, b in ipairs(G.balls) do b.flying, b.sliding, b.itemTouch = false, false, nil; b.frame:Hide() end
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

-- 球结构池扩容到 n
local function EnsureBalls(n)
    for i = #G.balls + 1, n do
        G.balls[i] = { x = 0, y = 0, vx = 0, vy = 0, flying = false, sliding = false,
                       flatT = 0, kick = false, frame = Render.NewBall(DBR.playArea) }
        G.balls[i].frame:Hide()
    end
end

-- ------------------------------------------------------------
-- HUD(主窗口顶条):关数 / 球数 / 音效 / 返回开始
-- ------------------------------------------------------------
function G.EnsureHUD()
    if G.hud then return end
    local f = DBR.frame
    local hud = {}
    G.hud = hud

    hud.level = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hud.level:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -30)
    hud.level:SetText("第 1 关")

    hud.balls = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hud.balls:SetPoint("LEFT", hud.level, "RIGHT", 18, 0)
    hud.balls:SetTextColor(0.95, 0.95, 0.95)
    hud.balls:SetText("球 ×1")

    local menuBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    menuBtn:SetSize(76, 21)
    menuBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -29)
    menuBtn:SetText("返回开始")
    menuBtn:SetScript("OnClick", function() G.ReturnToMenu() end)

    if DBR.Sound and DBR.Sound.CreateToggle then
        local cb = DBR.Sound.CreateToggle(f, true)   -- 紧凑版:无文字,带 tooltip
        cb:SetPoint("RIGHT", menuBtn, "LEFT", -4, 0)
    end
end

local function UpdateHUD()
    if not G.hud then return end
    G.hud.level:SetText("第 " .. (G.round or 1) .. " 关")
    G.hud.balls:SetText("球 ×" .. (G.ballTotal or 1))
end

-- 发射台与余量文字
local function PlaceLauncher()
    Render.PlaceAt(DBR.playArea, G.launcher, G.launchX, geo.FLOOR)
    G.countText:ClearAllPoints()
    G.countText:SetPoint("BOTTOM", DBR.playArea, "BOTTOMLEFT", G.launchX, geo.FLOOR + geo.BALL_R + 3)
end

local function SetCountText(n)
    if n and n > 0 then
        G.countText:SetText("×" .. n)
        G.countText:Show()
    else
        G.countText:Hide()
    end
end

-- ------------------------------------------------------------
-- 游戏结束面板
-- ------------------------------------------------------------
function G.EnsureOverPanel()
    if G.overPanel then return end
    local pa = DBR.playArea
    local p = CreateFrame("Frame", nil, pa)
    p:SetAllPoints(pa)
    p:SetFrameLevel((pa:GetFrameLevel() or 0) + 30)
    p:EnableMouse(true)   -- 吃掉点击
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.82)

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    p.title:SetPoint("CENTER", p, "CENTER", 0, 90)
    p.title:SetTextColor(1, 0.35, 0.3)
    p.title:SetText("游戏结束")

    p.line1 = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.line1:SetPoint("TOP", p.title, "BOTTOM", 0, -16)
    p.line2 = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.line2:SetPoint("TOP", p.line1, "BOTTOM", 0, -10)

    local againBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    againBtn:SetSize(140, 30)
    againBtn:SetPoint("TOP", p.line2, "BOTTOM", 0, -28)
    againBtn:SetText("再来一局")
    againBtn:SetScript("OnClick", function() G.New() end)

    local menuBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    menuBtn:SetSize(140, 30)
    menuBtn:SetPoint("TOP", againBtn, "BOTTOM", 0, -10)
    menuBtn:SetText("返回开始")
    menuBtn:SetScript("OnClick", function() G.ReturnToMenu() end)

    p:Hide()
    G.overPanel = p
end

-- ------------------------------------------------------------
-- 瞄准虚线
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

-- 沿 [发射点 -> 碰撞点](+ 反弹短段)铺行进虚线点
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
            d:SetAlpha(0.45)   -- 反弹段淡一点
        end
        if s <= len1 then d:SetAlpha(0.9) end
        Render.PlaceAt(DBR.playArea, d, x, y)
        d:Show()
        s = s + DOT_GAP
    end
    G.HideDots(di + 1)
end

-- ------------------------------------------------------------
-- 瞄准 / 发射
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
    G.nextX = nil
    G.turnHadBricks = next(G.bricks) ~= nil
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
        -- 松开:有效就发射
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
-- 物理回调
-- ------------------------------------------------------------
function G.HitBrick(brick)
    if not G.bricks[brick] then return end   -- 已被同帧的激光/炸弹链碎掉
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

-- 板中央大字飘报(全清奖励)
local function BigFloat(text)
    G.bigFs:SetText(text)
    G.bigT = 0
    G.bigFs:Show()
end

function G.HitItem(item, idx, ball)
    local kind = item.kind or "ball"
    -- gridLayer 可能带着下压偏移,但道具只在 FLY(偏移 0)被触发,直接用格坐标
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

    -- 激光/炸弹:整回合常驻,每颗球各触发一次,回合结束(被触发过)才消失
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
-- 刷新行 / 下压 / 游戏结束
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
        -- 保底一块,不能空行
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

    -- 特殊道具(激光/炸弹):概率刷在剩余空格里
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
    p.line1:SetText("到达 第 " .. (G.round or 1) .. " 关")
    if newBest then
        p.line2:SetText("|cffffd200新纪录!|r")
        Snd("best")
    else
        p.line2:SetText("最高纪录: 第 " .. (DodoBricksDB and DodoBricksDB.bestLevel or G.round or 1) .. " 关")
        Snd("over")
    end
    p:Show()
    Print("游戏结束,到达第 " .. (G.round or 1) .. " 关。")
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
    -- 发射台移到首球落点
    if G.nextX then G.launchX = G.nextX end
    G.marker:Hide()
    PlaceLauncher()

    -- 全清奖励:这回合开打时有砖、现在一块不剩
    if G.turnHadBricks and next(G.bricks) == nil then
        G.ballTotal = G.ballTotal + CLEAR_BONUS
        BigFloat("全清!  +" .. CLEAR_BONUS .. " 球")
        Snd("clear")
    end
    G.turnHadBricks = false
    SetCountText(G.ballTotal)

    -- 被触发过的激光/炸弹:回合结束消失
    for i = #G.items, 1, -1 do
        local it = G.items[i]
        if it.used then
            table.remove(G.items, i)
            FreeItemFrame(it)
        end
    end

    -- 最底行还有砖 => 再压就进发射条,游戏结束
    for brick in pairs(G.bricks) do
        if brick.row <= 1 then GameOver(); return end
    end

    -- 最底行道具:+1 球压下去前自动吃掉,激光/炸弹直接消失
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

    -- 整体下移一行(逻辑先到位,动画用 gridLayer 偏移从 +CELL 滑到 0)
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

    -- 新一关
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
-- 飞行驱动
-- ------------------------------------------------------------
local function UpdateLaunch(dt)
    if G.toLaunch <= 0 then return end
    G.launchTimer = G.launchTimer - dt
    while G.launchTimer <= 0 and G.toLaunch > 0 do
        local idx = G.ballsInPlay - G.toLaunch + 1
        local b = G.balls[idx]
        b.x, b.y = G.launchX, geo.FLOOR
        -- 多球散布:首颗严格按瞄准线(虚线诚实),第 2 颗起随机偏 ±SPREAD_DEG/2 度
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

local function SyncBalls()
    local pa = DBR.playArea
    for i = 1, G.ballsInPlay do
        local b = G.balls[i]
        if b.flying or b.sliding then
            Render.PlaceAt(pa, b.frame, b.x, b.y)
            b.frame:Show()
        else
            b.frame:Hide()
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

-- "+1" 飘字 + 板中央大字
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

-- 道具呼吸脉冲
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
        UpdateAim()
    elseif G.state == "FLY" then
        PulseItems()
        UpdateLaunch(elapsed)
        Physics.Step(G.ctx, elapsed)
        UpdateSliding(elapsed)
        SyncBalls()
        CheckTurnEnd()
    elseif G.state == "DESCEND" then
        UpdateDescend(elapsed)
    end
end

-- ------------------------------------------------------------
-- 进战暂停 / 窗口隐藏 / 返回菜单
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
-- 开新局 / 存读档
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
    StartDescend()   -- 第一行滑入,round 变 1
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
    Print("已读取进度:第 " .. G.round .. " 关,球 ×" .. G.ballTotal .. "。")
    return true
end
