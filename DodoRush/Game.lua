-- DodoRush - Game
-- 主循环 + 输入 + 对撞结算 + HUD + 进战暂停。
-- 状态:RUN 跑动中 -> OVER 全军覆没。菜单 = playArea 隐藏(Core 管)。
-- 世界向下滚动,人群固定在 CROWD_Y:门滑过人群线按左右半路结算;
-- 敌军接战 = 二元全额对账(双方各扣 min(我,敌)),磨的过程摊在 0.5~2 秒里按帧扣,
-- 接战的敌人被"钉住"(只随推进缓慢后退),全程不停下,只轻微减速 —— 边跑边磨。
-- 不做局中存档(单局 3~5 分钟,死了重开);只记最高关数/距离。

local DR = _G.DodoRush or {}
_G.DodoRush = DR

local G = {}
DR.Game = G

local geo, Render, Track

-- 可调参数(手感/平衡看这里;数值生成在 Track.lua 顶部)
local SCROLL            = 240    -- 基础滚动速度(px/s)
local SCROLL_STAGE_GAIN = 0.015  -- 每关提速 +1.5%
local SCROLL_STAGE_MAX  = 1.35   -- 提速封顶
local GRIND_SLOW        = 0.55   -- 接战时滚动减速系数(边跑边磨,不停下)
local PUSH_FRAC         = 0.12   -- 接战敌人被"推着走"的速度比例
local STRAFE            = 320    -- 横移速度(px/s)
local CROWD_VIS         = 48     -- 我方可见小人上限(数字是真,人堆是代表)
local KILL_PER_DUR      = 55     -- 对撞节奏:时长 = clamp(总消耗/此值, MIN, MAX)
local KILL_DUR_MIN      = 0.5
local KILL_DUR_MAX      = 2.0
local GRACE_T           = 0.8    -- 开跑/脱战恢复的缓起秒数(滚动 smoothstep 从 0 拉满)
local INITIAL_RUNWAY    = 430    -- 开局跑道留白(px,第一道门出现前)
local DIST_PER_M        = 40     -- 多少 px 算 1 米
local DASH_N, DASH_GAP  = 8, 80  -- 中线虚线节数与间距
local DASH_SPAN         = DASH_N * DASH_GAP

local function Print(msg)
    if _G.Dodo and _G.Dodo.Print then _G.Dodo.Print("Rush", msg) else print("|cff33ff99DodoRush:|r " .. tostring(msg)) end
end

local function Clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi end return x end

local function Snd(kind) if DR.Sound then DR.Sound.Play(kind) end end

-- ------------------------------------------------------------
-- 特效池(过门闪光 / 阵亡 poof):ADD 发光,放大+淡出后回收。
-- 结构 = 锚点占位帧 + 缩放视觉子帧(SetScale 会连锚点偏移一起缩放,直接缩放会漂移)。
-- ------------------------------------------------------------
local function SpawnEffect(key, build, x, y, dur, grow)
    local pool = G.effectPool[key]
    local fr = pool and table.remove(pool)
    if not fr then
        fr = CreateFrame("Frame", nil, DR.playArea)
        fr:SetSize(2, 2)
        fr:SetFrameLevel((DR.playArea:GetFrameLevel() or 0) + 8)
        local vis = build(fr)
        vis:ClearAllPoints()
        vis:SetPoint("CENTER", fr, "CENTER", 0, 0)
        fr.vis = vis
    end
    fr:ClearAllPoints()
    fr:SetPoint("CENTER", DR.playArea, "BOTTOMLEFT", x, y)
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

-- 小 poof 受预算节流(混战时每秒最多十来个),大 poof(破阵)不限
local function Poof(x, y, big)
    if not big then
        if G.poofBudget < 1 then return end
        G.poofBudget = G.poofBudget - 1
    end
    SpawnEffect(big and "poofB" or "poof",
        function(p) return Render.NewPoof(p, big) end,
        x, y, big and 0.4 or 0.26, big and 0.9 or 0.7)
end

local function GateFlashAt(x, y)
    SpawnEffect("gflash", function(p) return Render.NewGateFlash(p) end, x, y, 0.25, 0.10)
end

local function DeathBurst(el)
    local rx = (el.kind == "blob") and el.rE or 70
    local ry = (el.kind == "blob") and el.rE or (el.bandH / 2)
    for _ = 1, 6 do
        Poof(el.x + (math.random() - 0.5) * 2 * rx * 0.8,
             el.y + (math.random() - 0.5) * 2 * ry * 0.8, true)
    end
end

-- ------------------------------------------------------------
-- 飘字
-- ------------------------------------------------------------
local function AddFloat(x, y, text, r, g, b)
    for _, fl in ipairs(G.floats) do
        if not fl.t then
            fl.t, fl.x, fl.y = 0, x, y
            fl.fs:SetText(text)
            fl.fs:SetTextColor(r, g, b)
            fl.fs:Show()
            return
        end
    end
end

local function UpdateFloats(dt)
    for _, fl in ipairs(G.floats) do
        if fl.t then
            fl.t = fl.t + dt
            if fl.t >= 0.9 then
                fl.t = nil
                fl.fs:Hide()
            else
                local p = fl.t / 0.9
                fl.fs:ClearAllPoints()
                fl.fs:SetPoint("CENTER", G.layerF, "BOTTOMLEFT", fl.x, fl.y + 30 * p)
                fl.fs:SetAlpha(1 - p * p)
            end
        end
    end
end

-- ------------------------------------------------------------
-- 我方人群:数字是真,可见小人 = min(count, CROWD_VIS)。
-- 向日葵螺旋排阵;每个小人滞后追自己的阵位(横移拖尾的"活物感")+ 上下小颠。
-- ------------------------------------------------------------
local function EnsureCrowdUnits(n)
    for i = #G.units + 1, n do
        G.units[i] = { f = Render.NewUnit(G.layerC, "friend"),
                       x = G.cx, y = geo.CROWD_Y, tx = 0, ty = 0,
                       phase = math.random() * 6.28, rate = 8 + math.random() * 6 }
        G.units[i].f:Hide()
    end
end

local function RecomputeFormation()
    local vis = G.vis
    if vis <= 0 then G.crowdR = 12; return end
    local R = 12 + 4.0 * math.sqrt(vis)
    if R > 58 then R = 58 end
    G.crowdR = R + 8
    for i = 1, vis do
        local ang = i * 2.39996
        local rad = R * math.sqrt(i / vis)
        local u = G.units[i]
        u.tx = math.cos(ang) * rad
        u.ty = math.sin(ang) * rad * 0.85
    end
end

local function SyncCrowdVis(lossPoof)
    local newVis = Clamp(math.min(G.count, CROWD_VIS), 0, CROWD_VIS)
    if newVis == G.vis then return end
    if newVis > G.vis then
        EnsureCrowdUnits(newVis)
        for i = G.vis + 1, newVis do
            local u = G.units[i]
            u.x, u.y = G.cx, geo.CROWD_Y   -- 新人从队伍中心冒出,流向阵位
            u.f:Show()
        end
    else
        for i = newVis + 1, G.vis do
            local u = G.units[i]
            u.f:Hide()
            if lossPoof then Poof(u.x, u.y, false) end
        end
    end
    G.vis = newVis
    RecomputeFormation()
end

local function SetCrowdCount(lossPoof)
    if G.count < 0 then G.count = 0 end
    G.pill:SetCount(G.count)
    if G.count > G.peak then G.peak = G.count end
    SyncCrowdVis(lossPoof)
end

local function UpdateCrowd(dt)
    local bobAmp = G.anyEng and 3.4 or 1.8
    local now = GetTime()
    local lc = G.layerC
    for i = 1, G.vis do
        local u = G.units[i]
        local k = dt * u.rate
        if k > 1 then k = 1 end
        u.x = u.x + (G.cx + u.tx - u.x) * k
        u.y = u.y + (geo.CROWD_Y + u.ty - u.y) * k
        Render.MoveAt(lc, u.f, u.x, u.y + math.sin(now * 7 + u.phase) * bobAmp)
    end
end

-- ------------------------------------------------------------
-- 敌阵容器:wall/boss = 横排方阵(占满路宽,必打),blob = 圆阵散兵(可绕)。
-- 容器整体移动 + 整体小颠;掉人 = 从前排/外圈隐藏小人 + poof。按 kind 池化复用。
-- ------------------------------------------------------------
local ENEMY_CAP = { wall = 36, boss = 30, blob = 24 }

local function EnsureEnemyUnits(c, n)
    for i = #c.units + 1, n do
        c.units[i] = Render.NewUnit(c, (c.kind == "boss") and "boss" or "foe")
    end
end

-- 排阵;返回 bandH(墙)/rE(散兵)
local function LayoutEnemy(c, count)
    local kind = c.kind
    local vis = math.min(count, ENEMY_CAP[kind])
    local bandH, rE
    EnsureEnemyUnits(c, vis)
    if kind == "blob" then
        local R = 12 + 4.0 * math.sqrt(vis)
        rE = R + 9
        for i = 1, vis do
            local ang = i * 2.39996
            local rad = R * math.sqrt(i / vis)
            local ox, oy = math.cos(ang) * rad, math.sin(ang) * rad * 0.85
            c.units[i]:SetPoint("CENTER", c, "CENTER", ox, oy)
            c.units[i]:Show()
            c.offs[i] = c.offs[i] or {}
            c.offs[i][1], c.offs[i][2] = ox, oy
        end
    else
        local cols = (kind == "boss") and 10 or 12
        local sp   = (kind == "boss") and 34 or 30
        local rh   = (kind == "boss") and 30 or 26
        local rows = math.ceil(vis / cols)
        -- 行序从上到下 => 序号大的在底排(贴近我方),掉人先掉前排
        for i = 1, vis do
            local r0 = math.floor((i - 1) / cols)
            local rowCount = math.min(cols, vis - r0 * cols)
            local colIdx = (i - 1) % cols
            local ox = (colIdx - (rowCount - 1) / 2) * sp
            local oy = ((rows - 1) / 2 - r0) * rh
            c.units[i]:SetPoint("CENTER", c, "CENTER", ox, oy)
            c.units[i]:Show()
            c.offs[i] = c.offs[i] or {}
            c.offs[i][1], c.offs[i][2] = ox, oy
        end
        bandH = rows * rh + 24
    end
    for i = vis + 1, #c.units do c.units[i]:Hide() end
    c.visN = vis
    local py = (kind == "blob") and (rE + 16) or (bandH / 2 + 16)
    c.pill:SetPoint("CENTER", c, "CENTER", 0, py)
    c.pill:SetCount(count)
    return bandH, rE
end

local function GetEnemy(kind)
    local pool = G.enemyPool[kind]
    local c = pool and table.remove(pool)
    if not c then
        c = CreateFrame("Frame", nil, G.layerE)
        c:SetSize(2, 2)
        c:SetFrameLevel((G.layerE:GetFrameLevel() or 0) + 2)
        c.units, c.offs, c.kind = {}, {}, kind
        c.pill = Render.NewPill(c, true)
        if kind == "boss" then
            local tag = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            tag:SetPoint("BOTTOM", c.pill, "TOP", 0, 2)
            tag:SetTextColor(1, 0.25, 0.25)
            tag:SetText("BOSS")
        end
    end
    c:Show()
    return c
end

local function FreeEnemy(el)
    el.c:Hide()
    table.insert(G.enemyPool[el.kind], el.c)
    el.c = nil
end

-- 战斗掉人:隐藏超出可见数的小人(前排/外圈先掉)+ poof
local function SyncEnemyVis(el)
    local c = el.c
    local newVis = math.min(el.count, ENEMY_CAP[el.kind])
    if newVis >= c.visN then return end
    for i = newVis + 1, c.visN do
        c.units[i]:Hide()
        local o = c.offs[i]
        if o then Poof(el.x + o[1], el.y + o[2], false) end
    end
    c.visN = newVis
end

-- ------------------------------------------------------------
-- 门板池
-- ------------------------------------------------------------
local function GetGatePanel()
    local f = table.remove(G.gatePool)
    if not f then f = Render.NewGatePanel(G.layerE) end
    f:SetAlpha(1)
    f:Show()
    return f
end

local function FreeGate(el)
    el.fL:Hide(); table.insert(G.gatePool, el.fL); el.fL = nil
    el.fR:Hide(); table.insert(G.gatePool, el.fR); el.fR = nil
end

-- ------------------------------------------------------------
-- 生成:按滚动距离从 Track 队列里取下一个元素放到跑道顶上
-- ------------------------------------------------------------
local function SpawnNext()
    local el = Track.Next()
    el.y = geo.ROAD_H + 80
    if el.type == "gates" then
        el.fL = GetGatePanel(); el.fL:SetGate(el.L.op, el.L.v)
        el.fR = GetGatePanel(); el.fR:SetGate(el.R.op, el.R.v)
        Render.PlaceAt(G.layerE, el.fL, geo.GATE_XL, el.y)
        Render.PlaceAt(G.layerE, el.fR, geo.GATE_XR, el.y)
    else
        el.c = GetEnemy(el.kind)
        local bandH, rE = LayoutEnemy(el.c, el.count)
        el.bandH, el.rE = bandH, rE
        el.x = (el.kind == "blob") and (geo.ROAD_W * el.xfrac) or (geo.ROAD_W / 2)
        el.bobPhase = math.random() * 6.28
        Render.PlaceAt(G.layerE, el.c, el.x, el.y)
    end
    table.insert(G.elements, el)
    G.spawnDist = G.spawnDist + el.gapAfter
end

-- ------------------------------------------------------------
-- 过门 / 接敌 / 对撞
-- ------------------------------------------------------------
local function GameOver(reason)
    if G.state ~= "RUN" then return end
    G.state = "OVER"
    G.SetKeyboard(false)
    local db = DodoRushDB
    local stage = G.stage or 1
    local meters = math.floor((G.dist or 0) / DIST_PER_M)
    local prevBest = (db and db.bestStage) or 0
    local newBest = stage > prevBest
    if db then
        if stage > (db.bestStage or 0) then db.bestStage = stage end
        if meters > (db.bestDist or 0) then db.bestDist = meters end
    end
    local p = G.overPanel
    p.reason:SetText(reason or "")
    p.line1:SetText("到达 第 " .. stage .. " 关 · " .. meters .. " 米")
    p.line2:SetText("本局峰值 " .. (G.peak or 0) .. " 人")
    if newBest then
        p.line3:SetText("|cffffd200新纪录!|r")
        Snd("best")
    else
        p.line3:SetText("最高纪录: 第 " .. prevBest .. " 关")
        Snd("over")
    end
    p:Show()
    Print("全军覆没,到达第 " .. stage .. " 关(" .. meters .. " 米)。")
end

local function ApplyGate(el)
    el.applied = true
    local side = (G.cx < geo.ROAD_W / 2) and "L" or "R"
    local g = el[side]
    local otherF = (side == "L") and el.fR or el.fL
    local old = G.count
    G.count = Track.ApplyOp(G.count, g)
    local good = G.count >= old
    Snd(good and "gate_good" or "gate_bad")
    GateFlashAt((side == "L") and geo.GATE_XL or geo.GATE_XR, el.y)
    otherF:SetDim()
    local txt = Track.GateText(g)
    if good then
        AddFloat(G.cx, geo.CROWD_Y + G.crowdR + 34, txt, 0.45, 1, 0.55)
    else
        AddFloat(G.cx, geo.CROWD_Y + G.crowdR + 34, txt, 1, 0.42, 0.38)
    end
    G.stage = el.stage
    SetCrowdCount(not good)
    G.UpdateHUD()
    if G.count <= 0 then
        GameOver("被 " .. txt .. " 的门减到了 0 人……")
    end
end

local function Engage(el)
    el.engaged = true
    el.kills = math.min(G.count, el.count)   -- 二元全额对账:碰上就打满
    local dur = Clamp(el.kills / KILL_PER_DUR, KILL_DUR_MIN, KILL_DUR_MAX)
    el.rate = el.kills / dur
    el.acc = 0
    Snd("clash")
end

local function CheckEngage(el)
    if el.kind == "blob" then
        local dx, dy = el.x - G.cx, el.y - geo.CROWD_Y
        local rr = el.rE + G.crowdR - 6
        if dx * dx + dy * dy <= rr * rr then Engage(el) end
    else
        if el.y - el.bandH / 2 <= geo.CROWD_Y + G.crowdR * 0.6 then Engage(el) end
    end
end

local function DrainFight(el, dt)
    el.acc = el.acc + el.rate * dt
    local n = math.floor(el.acc)
    if n <= 0 then return end
    el.acc = el.acc - n
    if n > el.count then n = el.count end
    if n > G.count then n = G.count end
    if n <= 0 then return end
    el.count = el.count - n
    G.count = G.count - n
    el.c.pill:SetCount(el.count)
    SyncEnemyVis(el)
    SetCrowdCount(true)
    Snd("tick")
    if el.count <= 0 then
        el.dead = true
        DeathBurst(el)
        Snd((el.kind == "boss") and "boss" or "win")
        AddFloat(G.cx, geo.CROWD_Y + G.crowdR + 34, "-" .. el.kills, 1, 0.5, 0.45)
    end
    if G.count <= 0 then
        GameOver("队伍在敌阵里拼光了……")
    end
end

-- ------------------------------------------------------------
-- 世界更新
-- ------------------------------------------------------------
local function UpdateDashes(scrollD)
    local pa = DR.playArea
    for i = 1, #G.dashes do
        local d = G.dashes[i]
        d.y = d.y - scrollD
        if d.y < -26 then d.y = d.y + DASH_SPAN end
        Render.MoveAt(pa, d.f, geo.ROAD_W / 2, d.y)
    end
end

local function UpdateElements(dt, scroll)
    local anyEng = false
    local now = GetTime()
    local le = G.layerE
    local i = #G.elements
    while i >= 1 do
        local el = G.elements[i]
        if el.type == "gates" then
            el.y = el.y - scroll * dt
            Render.MoveAt(le, el.fL, geo.GATE_XL, el.y)
            Render.MoveAt(le, el.fR, geo.GATE_XR, el.y)
            if (not el.applied) and el.y <= geo.CROWD_Y then ApplyGate(el) end
            if el.y < -80 then
                FreeGate(el)
                table.remove(G.elements, i)
            end
        else
            if el.engaged and not el.dead then
                el.y = el.y - scroll * dt * PUSH_FRAC   -- 被钉住,只被推着缓退
                DrainFight(el, dt)
                if not el.dead then anyEng = true end
            elseif not el.dead then
                el.y = el.y - scroll * dt
                CheckEngage(el)
                if el.engaged then
                    anyEng = true
                elseif el.kind == "blob" and (not el.dodged)
                    and el.y < geo.CROWD_Y - (el.rE + G.crowdR) - 6 then
                    el.dodged = true
                    AddFloat(G.cx, geo.CROWD_Y + G.crowdR + 34, "躲开 " .. el.count .. " 人", 0.7, 0.92, 0.7)
                    Snd("dodge")
                end
            end
            if el.dead then
                FreeEnemy(el)
                table.remove(G.elements, i)
            else
                Render.MoveAt(le, el.c, el.x, el.y + math.sin(now * 5 + el.bobPhase) * 1.6)
                if el.y < -70 then
                    FreeEnemy(el)
                    table.remove(G.elements, i)
                end
            end
        end
        if G.state ~= "RUN" then break end
        i = i - 1
    end
    G.anyEng = anyEng
end

-- ------------------------------------------------------------
-- HUD / 结算面板
-- ------------------------------------------------------------
function G.EnsureHUD()
    if G.hud then return end
    local f = DR.frame
    local hud = {}
    G.hud = hud

    hud.stage = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hud.stage:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -30)
    hud.stage:SetText("第 1 关")

    hud.dist = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hud.dist:SetPoint("LEFT", hud.stage, "RIGHT", 18, 0)
    hud.dist:SetTextColor(0.95, 0.95, 0.95)
    hud.dist:SetText("0 米")

    local menuBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    menuBtn:SetSize(76, 21)
    menuBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -29)
    menuBtn:SetText("返回开始")
    menuBtn:SetScript("OnClick", function() G.ReturnToMenu() end)

    if DR.Sound and DR.Sound.CreateToggle then
        local cb = DR.Sound.CreateToggle(f, true)
        cb:SetPoint("RIGHT", menuBtn, "LEFT", -4, 0)
    end
end

function G.UpdateHUD()
    if not G.hud then return end
    G.hud.stage:SetText("第 " .. (G.stage or 1) .. " 关")
    G.hud.dist:SetText(math.floor((G.dist or 0) / DIST_PER_M) .. " 米")
end

function G.EnsureOverPanel()
    if G.overPanel then return end
    local pa = DR.playArea
    local p = CreateFrame("Frame", nil, pa)
    p:SetAllPoints(pa)
    p:SetFrameLevel((pa:GetFrameLevel() or 0) + 30)
    p:EnableMouse(true)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.84)

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    p.title:SetPoint("CENTER", p, "CENTER", 0, 110)
    p.title:SetTextColor(1, 0.35, 0.3)
    p.title:SetText("全军覆没")

    p.reason = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.reason:SetPoint("TOP", p.title, "BOTTOM", 0, -10)
    p.reason:SetTextColor(0.8, 0.8, 0.8)

    p.line1 = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.line1:SetPoint("TOP", p.reason, "BOTTOM", 0, -18)
    p.line2 = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.line2:SetPoint("TOP", p.line1, "BOTTOM", 0, -8)
    p.line3 = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.line3:SetPoint("TOP", p.line2, "BOTTOM", 0, -8)

    local againBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    againBtn:SetSize(140, 30)
    againBtn:SetPoint("TOP", p.line3, "BOTTOM", 0, -24)
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
-- 键盘(DodoPool 验证过的套路):吞掉按键,ESC 放行关窗;
-- 进战必须整个 EnableKeyboard(false)(战斗中插件不能调 SetPropagateKeyboardInput)。
-- ------------------------------------------------------------
local function OnKeyDown(self, key)
    if key == "ESCAPE" then self:SetPropagateKeyboardInput(true); return end
    self:SetPropagateKeyboardInput(false)
    if key == "A" or key == "D" or key == "LEFT" or key == "RIGHT" then
        G.held[key] = true
    end
end

local function OnKeyUp(_, key) G.held[key] = nil end

function G.SetKeyboard(on)
    local pa = DR.playArea
    if not pa then return end
    if on then
        pa:EnableKeyboard(true)
        pa:SetScript("OnKeyDown", OnKeyDown)
        pa:SetScript("OnKeyUp", OnKeyUp)
    else
        pa:SetScript("OnKeyDown", nil)
        pa:SetScript("OnKeyUp", nil)
        pa:EnableKeyboard(false)
        if G.held then wipe(G.held) end
    end
end

-- ------------------------------------------------------------
-- 驱动
-- ------------------------------------------------------------
function G.Driver(elapsed)
    if G.paused then return end
    local dt = elapsed
    if dt > 0.05 then dt = 0.05 end

    if G.state == "RUN" then
        -- 缓起(开跑 / 脱战恢复都从 0 平滑拉满,不突然糊脸)
        G.grace = G.grace + dt
        local gm = 1
        if G.grace < GRACE_T then
            local p = G.grace / GRACE_T
            gm = p * p * (3 - 2 * p)
        end

        -- 横移
        local dir = 0
        if G.held.A or G.held.LEFT then dir = dir - 1 end
        if G.held.D or G.held.RIGHT then dir = dir + 1 end
        if dir ~= 0 then
            G.cx = Clamp(G.cx + dir * STRAFE * dt, geo.EDGE, geo.ROAD_W - geo.EDGE)
        end

        -- 滚动速度:基础 × 关数小提速 × 缓起 × 接战减速
        local lvl = 1 + SCROLL_STAGE_GAIN * ((G.stage or 1) - 1)
        if lvl > SCROLL_STAGE_MAX then lvl = SCROLL_STAGE_MAX end
        local scroll = SCROLL * lvl * gm
        if G.anyEng then scroll = scroll * GRIND_SLOW end
        G.dist = G.dist + scroll * dt

        G.poofBudget = math.min(4, G.poofBudget + dt * 14)

        UpdateDashes(scroll * dt)

        G.spawnDist = G.spawnDist - scroll * dt
        while G.spawnDist <= 0 and G.state == "RUN" do SpawnNext() end

        UpdateElements(dt, scroll)

        if G.state == "RUN" then
            UpdateCrowd(dt)
            Render.MoveAt(G.layerF, G.pill, G.cx, geo.CROWD_Y + G.crowdR + 18)
            G.hudT = (G.hudT or 0) + dt
            if G.hudT > 0.15 then
                G.hudT = 0
                G.UpdateHUD()
            end
        end
    end

    UpdateEffects(dt)
    UpdateFloats(dt)
end

-- ------------------------------------------------------------
-- 构件(只建一次)
-- ------------------------------------------------------------
local function EnsureSetup()
    if G.ready then return end
    G.ready = true
    geo, Render, Track = DR.geo, DR.Render, DR.Track
    local pa = DR.playArea

    Render.BuildRoad(pa)
    local lv = pa:GetFrameLevel() or 0

    local le = CreateFrame("Frame", nil, pa)   -- 实体层:门/敌阵
    le:SetAllPoints()
    le:SetFrameLevel(lv + 2)
    G.layerE = le

    local lc = CreateFrame("Frame", nil, pa)   -- 人群层(盖在门板上,人从门里穿过)
    lc:SetAllPoints()
    lc:SetFrameLevel(lv + 6)
    G.layerC = lc

    local lf = CreateFrame("Frame", nil, pa)   -- 飘字/数字牌/暂停提示层
    lf:SetAllPoints()
    lf:SetFrameLevel(lv + 12)
    G.layerF = lf

    -- 中线虚线(左右半路的分界,选门看它)
    G.dashes = {}
    for i = 1, DASH_N do
        local f = Render.NewDash(pa)
        G.dashes[i] = { f = f, y = (i - 1) * DASH_GAP + 40 }
        Render.PlaceAt(pa, f, geo.ROAD_W / 2, G.dashes[i].y)
    end

    G.units = {}
    G.vis = 0
    G.crowdR = 20
    G.cx = geo.ROAD_W / 2
    G.pill = Render.NewPill(lf, false)

    G.elements = {}
    G.gatePool = {}
    G.enemyPool = { wall = {}, blob = {}, boss = {} }
    G.effects = {}
    G.effectPool = {}

    G.floats = {}
    for i = 1, 6 do
        local fs = lf:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
        fs:Hide()
        G.floats[i] = { fs = fs }
    end

    G.pauseText = lf:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    G.pauseText:SetPoint("CENTER", pa, "CENTER", 0, 60)
    G.pauseText:SetTextColor(1, 0.4, 0.4)
    G.pauseText:SetText("战斗中已暂停")
    G.pauseText:Hide()
    G.pauseSub = lf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    G.pauseSub:SetPoint("TOP", G.pauseText, "BOTTOM", 0, -8)
    G.pauseSub:SetText("脱战后自动继续")
    G.pauseSub:Hide()

    G.held = {}

    G.EnsureHUD()
    G.EnsureOverPanel()

    pa:SetScript("OnUpdate", function(_, e) G.Driver(e) end)
end

local function ClearAll()
    for i = #G.elements, 1, -1 do
        local el = G.elements[i]
        if el.type == "gates" then FreeGate(el) else FreeEnemy(el) end
        table.remove(G.elements, i)
    end
    for _, fl in ipairs(G.floats) do fl.t = nil; fl.fs:Hide() end
    for i = #G.effects, 1, -1 do
        local e = G.effects[i]
        e.frame:Hide()
        e.frame.vis:SetScale(1)
        G.effectPool[e.key] = G.effectPool[e.key] or {}
        table.insert(G.effectPool[e.key], e.frame)
        table.remove(G.effects, i)
    end
    for i = 1, #G.units do G.units[i].f:Hide() end
    G.vis = 0
    wipe(G.held)
end

-- ------------------------------------------------------------
-- 进战暂停 / 窗口隐藏 / 返回菜单
-- ------------------------------------------------------------
local function SetPauseShown(shown)
    if not G.ready then return end
    if shown then G.pauseText:Show(); G.pauseSub:Show()
    else G.pauseText:Hide(); G.pauseSub:Hide() end
end

local function OnCombat(inCombat)
    if not G.ready then return end
    if inCombat then
        if DR.frame and DR.frame:IsShown() and G.state == "RUN" then
            G.paused = true
            G.SetKeyboard(false)
            SetPauseShown(true)
        end
    else
        if DR.frame and DR.frame:IsShown() and DR.playArea and DR.playArea:IsShown()
            and G.state == "RUN" and G.paused then
            G.paused = false
            G.grace = 0   -- 缓起,不突然糊脸
            G.SetKeyboard(true)
            SetPauseShown(false)
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
    G.SetKeyboard(false)
    G.paused = false
    SetPauseShown(false)
end

function G.ReturnToMenu()
    G.SetKeyboard(false)
    if G.ready then
        G.overPanel:Hide()
        SetPauseShown(false)
    end
    if DR.ShowStartScreen then DR.ShowStartScreen() end
end

-- ------------------------------------------------------------
-- 开新局 / 继续(本局在内存里,无落盘存档)
-- ------------------------------------------------------------
function G.CanResume()
    return G.state == "RUN"
end

function G.New()
    EnsureSetup()
    ClearAll()
    Track.Reset()
    G.count = Track.START_PAR
    G.stage = 1
    G.dist = 0
    G.peak = G.count
    G.cx = geo.ROAD_W / 2
    G.grace = 0
    G.anyEng = false
    G.poofBudget = 0
    G.spawnDist = INITIAL_RUNWAY
    G.hudT = 0
    G.overPanel:Hide()
    G.paused = false
    SetPauseShown(false)
    G.state = "RUN"
    SetCrowdCount(false)
    G.pill:Show()
    Render.MoveAt(G.layerF, G.pill, G.cx, geo.CROWD_Y + G.crowdR + 18)
    G.UpdateHUD()
    if InCombatLockdown() then
        G.paused = true
        SetPauseShown(true)
    else
        G.SetKeyboard(true)
    end
    Snd("start")
end

function G.Resume()
    EnsureSetup()
    if G.state ~= "RUN" then return end
    G.paused = false
    G.grace = 0
    SetPauseShown(false)
    if InCombatLockdown() then
        G.paused = true
        SetPauseShown(true)
    else
        G.SetKeyboard(true)
    end
end
