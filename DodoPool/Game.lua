-- DodoPool - Game
-- 状态机 + 摆球 + 鼠标瞄准蓄力 + WASD 塞点 / QE 抬杆(masse) + 出杆循环 + HUD + 进战暂停。
-- 严格 9 球规则:必须先碰最小号球、碰球后须有球到库或进球,否则犯规;犯规罚 1 杆 + 自由球;
-- 合法把 9 号打进即胜,犯规进 9 号则重摆;存读档(1 档)+ 最佳杆数记录。

local DP = _G.DodoPool or {}
_G.DodoPool = DP

local G = {}
DP.Game = G
G.held = {}

local geo, Physics, Render

-- 操控参数(可调)
local MAX_PULL    = 230
local MIN_PULL    = 14
local STICK_LEN   = 150
local STRIKE_RATE = 1.6
local MISCUE_SAFE = 0.82
local ELEV_RATE   = 55
local MAX_ELEV    = 45
local STRIKE_RAD  = 28
local DASH_LEN, DASH_GAP, DASH_SPEED = 11, 8, 42

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function Print(msg)
    if _G.Dodo and _G.Dodo.Print then _G.Dodo.Print("Pool", msg) else print("DodoPool: " .. tostring(msg)) end
end

local function Clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi end return x end

local function MouseFelt()
    local pa = DP.playArea
    local scale = pa:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    mx, my = mx / scale, my / scale
    return mx - pa:GetLeft(), my - pa:GetBottom()
end

local function MakeCircle(host, size, layer, r, g, b, a)
    local t = host:CreateTexture(nil, layer or "ARTWORK")
    t:SetSize(size, size)
    t:SetPoint("CENTER", host, "CENTER", 0, 0)
    t:SetColorTexture(r, g, b, a or 1)
    local m = host:CreateMaskTexture()
    m:SetAllPoints(t)
    m:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    t:AddMaskTexture(m)
    return t
end

-- ------------------------------------------------------------
-- 球(结构+视觉)只建一次
-- ------------------------------------------------------------
local function EnsureBalls()
    if G.balls then return end
    geo, Physics, Render = DP.geo, DP.Physics, DP.Render
    local pa = DP.playArea
    G.balls, G.struct = {}, {}
    for num = 0, 9 do
        local fr = Render.NewBall(pa, num)
        local s = { num = num, x = 0, y = 0, vx = 0, vy = 0, shotDirX = 0, shotDirY = 0,
                    spinF = 0, spinS = 0, curve = 0, touchedObject = false, active = true, frame = fr }
        G.struct[num] = s
        G.balls[#G.balls + 1] = s
    end
    G.cue = G.struct[0]
    G._out = { pocketed = {}, firstHit = nil, railAfter = false }
end

local function SyncVisuals()
    local pa = DP.playArea
    for _, b in ipairs(G.balls) do
        if b.active then
            b.frame:Show()
            Render.PlaceBall(pa, b.frame, b.x, b.y)
        else
            b.frame:Hide()
        end
    end
end

-- ------------------------------------------------------------
-- 台面视觉:球杆三段 + 动态虚线 + 胜利 / 暂停
-- ------------------------------------------------------------
local function EnsureVisuals()
    if G.cueTip then return end
    local pa = DP.playArea

    G.cueTip = pa:CreateLine(nil, "OVERLAY")
    G.cueTip:SetThickness(4); G.cueTip:SetColorTexture(0.62, 0.85, 1, 1); G.cueTip:Hide()
    G.cueShaft = pa:CreateLine(nil, "OVERLAY")
    G.cueShaft:SetThickness(5); G.cueShaft:SetColorTexture(0.85, 0.68, 0.40, 1); G.cueShaft:Hide()
    G.cueButt = pa:CreateLine(nil, "OVERLAY")
    G.cueButt:SetThickness(7); G.cueButt:SetColorTexture(0.36, 0.22, 0.12, 1); G.cueButt:Hide()

    G.dashes = {}

    local win = pa:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    win:SetPoint("CENTER"); win:SetTextColor(1, 0.85, 0.1); win:Hide()
    G.winText = win

    local pause = pa:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    pause:SetPoint("CENTER"); pause:SetTextColor(1, 0.4, 0.4)
    pause:SetText("战斗中已暂停"); pause:Hide()
    G.pauseText = pause

    local hint = pa:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hint:SetPoint("TOP", pa, "TOP", 0, -10); hint:SetTextColor(1, 0.9, 0.3); hint:Hide()
    G.placeHint = hint
end

local function GetDash(i)
    local d = G.dashes[i]
    if not d then
        d = DP.playArea:CreateLine(nil, "OVERLAY")
        d:SetThickness(3); d:SetColorTexture(1, 1, 1, 0.75)
        G.dashes[i] = d
    end
    return d
end

local function HideDashes(from)
    if not G.dashes then return end
    for k = from or 1, #G.dashes do G.dashes[k]:Hide() end
end

local function DrawAimDashes(pts)
    local n = #pts
    if n < 2 then HideDashes(); return end
    local cum = { 0 }
    for i = 2, n do
        local dx, dy = pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y
        cum[i] = cum[i - 1] + math.sqrt(dx * dx + dy * dy)
    end
    local total = cum[n]
    local function posAt(s)
        if s <= 0 then return pts[1].x, pts[1].y end
        if s >= total then return pts[n].x, pts[n].y end
        local lo = 1
        for i = 2, n do if cum[i] >= s then lo = i - 1; break end end
        local seg = cum[lo + 1] - cum[lo]
        local t = seg > 0 and (s - cum[lo]) / seg or 0
        return pts[lo].x + (pts[lo + 1].x - pts[lo].x) * t,
               pts[lo].y + (pts[lo + 1].y - pts[lo].y) * t
    end
    local period = DASH_LEN + DASH_GAP
    local phase = (GetTime() * DASH_SPEED) % period
    local di, s = 0, phase - period
    while s < total and di < 70 do
        local ds, de = math.max(s, 0), math.min(s + DASH_LEN, total)
        if de > ds then
            di = di + 1
            local d = GetDash(di)
            local x1, y1 = posAt(ds)
            local x2, y2 = posAt(de)
            d:SetStartPoint("BOTTOMLEFT", x1, y1)
            d:SetEndPoint("BOTTOMLEFT", x2, y2)
            d:Show()
        end
        s = s + period
    end
    HideDashes(di + 1)
end

local function HideAimVisuals()
    if G.cueTip then G.cueTip:Hide(); G.cueShaft:Hide(); G.cueButt:Hide() end
    HideDashes()
end

-- ------------------------------------------------------------
-- HUD
-- ------------------------------------------------------------
local function EnsureHUD()
    if G.hud then return end
    local f = DP.frame
    local hud = {}
    G.hud = hud

    if f.hud then f.hud:SetText("|cff9dd6a0鼠标拖动瞄准蓄力·松开击球·右键取消  |  WASD 击球点  QE 抬杆|r") end

    hud.strokes = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hud.strokes:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -52)
    hud.strokes:SetText("杆数: 0")

    hud.balls = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hud.balls:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, -52)
    hud.balls:SetText("剩球: 9")

    -- 蓄力条(CastingBar 材质)
    local pbW, pbH = 300, 20
    local pframe = CreateFrame("Frame", nil, f)
    pframe:SetSize(pbW, pbH)
    pframe:SetPoint("TOP", f, "TOP", 20, -70)
    local pbg = pframe:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints(); pbg:SetTexture("Interface\\CastingBar\\UI-CastingBar-Background")
    local pb = CreateFrame("StatusBar", nil, pframe)
    pb:SetPoint("TOPLEFT", 2, -3); pb:SetPoint("BOTTOMRIGHT", -2, 3)
    pb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    pb:SetStatusBarColor(1, 0.76, 0.10)
    pb:SetMinMaxValues(0, 1); pb:SetValue(0)
    local spark = pb:CreateTexture(nil, "OVERLAY")
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD"); spark:SetSize(18, pbH * 1.9); spark:Hide()
    local pborder = pframe:CreateTexture(nil, "OVERLAY")
    pborder:SetPoint("TOPLEFT", -3, 4); pborder:SetPoint("BOTTOMRIGHT", 3, -4)
    pborder:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border")
    hud.powerBar, hud.powerSpark, hud.powerW = pb, spark, pbW - 4
    local plabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    plabel:SetPoint("RIGHT", pframe, "LEFT", -8, 0); plabel:SetText("蓄力")

    -- 击球点圆盘
    local sw = CreateFrame("Frame", nil, f)
    sw:SetSize(2 * STRIKE_RAD, 2 * STRIKE_RAD)
    sw:SetPoint("TOPLEFT", f, "TOPLEFT", 150, -28)
    MakeCircle(sw, 2 * STRIKE_RAD, "ARTWORK", 0.93, 0.93, 0.9, 1)
    hud.strikeDot = MakeCircle(sw, 12, "OVERLAY", 1, 0.85, 0.1, 1)
    local slabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slabel:SetPoint("TOP", sw, "BOTTOM", 0, -1); slabel:SetText("击球点")

    -- 抬杆侧视球杆(0~45 度)
    local eg = CreateFrame("Frame", nil, f)
    eg:SetSize(72, 64)
    eg:SetPoint("LEFT", sw, "RIGHT", 18, 0)
    local baseLine = eg:CreateLine(nil, "ARTWORK")
    baseLine:SetThickness(2); baseLine:SetColorTexture(0.45, 0.45, 0.45, 0.8)
    baseLine:SetStartPoint("BOTTOMLEFT", 8, 12); baseLine:SetEndPoint("BOTTOMLEFT", 64, 12)
    local gball = MakeCircle(eg, 13, "ARTWORK", 0.93, 0.93, 0.9, 1)
    gball:ClearAllPoints(); gball:SetPoint("CENTER", eg, "BOTTOMLEFT", 58, 18)
    local cueL = eg:CreateLine(nil, "OVERLAY")
    cueL:SetThickness(4); cueL:SetColorTexture(0.86, 0.70, 0.40, 1)
    hud.elevCue = cueL
    hud.elevText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hud.elevText:SetPoint("TOP", eg, "BOTTOM", 0, -1); hud.elevText:SetText("抬杆 0\194\176")

    -- 保存按钮
    local saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    saveBtn:SetSize(64, 22)
    saveBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, -78)
    saveBtn:SetText("保存")
    saveBtn:SetScript("OnClick", function() G.Save() end)
end

local function UpdateHUD()
    if not G.hud then return end
    G.hud.strokes:SetText("杆数: " .. (G.strokes or 0))
    G.hud.balls:SetText("剩球: " .. (G.ballsLeft or 0))
end

local function SetPowerBar(frac)
    if not G.hud or not G.hud.powerBar then return end
    frac = Clamp(frac or 0, 0, 1)
    G.hud.powerBar:SetValue(frac)
    local sp = G.hud.powerSpark
    if sp then
        if frac > 0.02 then
            sp:ClearAllPoints()
            sp:SetPoint("CENTER", G.hud.powerBar, "LEFT", frac * G.hud.powerW, 0)
            sp:Show()
        else
            sp:Hide()
        end
    end
end

local function UpdateStrikeHUD()
    if not G.hud then return end
    local ox, oy = G.ox or 0, G.oy or 0
    local sw = G.hud.strikeDot:GetParent()
    G.hud.strikeDot:ClearAllPoints()
    G.hud.strikeDot:SetPoint("CENTER", sw, "CENTER", ox * STRIKE_RAD, oy * STRIKE_RAD)
    local mag = math.sqrt(ox * ox + oy * oy)
    if mag > MISCUE_SAFE then
        G.hud.strikeDot:SetColorTexture(1, 0.25, 0.2, 1)
    else
        G.hud.strikeDot:SetColorTexture(1, 0.85, 0.1, 1)
    end
    local rad = math.rad(G.elevDeg or 0)
    local px, py, L = 56, 18, 48
    G.hud.elevCue:SetStartPoint("BOTTOMLEFT", px, py)
    G.hud.elevCue:SetEndPoint("BOTTOMLEFT", px - L * math.cos(rad), py + L * math.sin(rad))
    G.hud.elevText:SetText(string.format("抬杆 %d\194\176", math.floor((G.elevDeg or 0) + 0.5)))
end

-- ------------------------------------------------------------
-- 键盘捕获
-- ------------------------------------------------------------
local function OnKeyDown(self, key)
    if key == "ESCAPE" then self:SetPropagateKeyboardInput(true); return end
    self:SetPropagateKeyboardInput(false)
    if key == "W" or key == "S" or key == "A" or key == "D" or key == "Q" or key == "E" then
        G.held[key] = true
    end
end

local function OnKeyUp(_, key) G.held[key] = nil end

function G.SetKeyboard(on)
    local pa = DP.playArea
    if not pa then return end
    if on then
        pa:EnableKeyboard(true)
        pa:SetScript("OnKeyDown", OnKeyDown)
        pa:SetScript("OnKeyUp", OnKeyUp)
    else
        pa:SetScript("OnKeyDown", nil)
        pa:SetScript("OnKeyUp", nil)
        pa:EnableKeyboard(false)
        wipe(G.held)
    end
end

local function ApplyHeldKeys(dt)
    local ox, oy = G.ox or 0, G.oy or 0
    if G.held.A then ox = ox - STRIKE_RATE * dt end
    if G.held.D then ox = ox + STRIKE_RATE * dt end
    if G.held.W then oy = oy + STRIKE_RATE * dt end
    if G.held.S then oy = oy - STRIKE_RATE * dt end
    local mag = math.sqrt(ox * ox + oy * oy)
    if mag > 1 then ox, oy = ox / mag, oy / mag end
    G.ox, G.oy = ox, oy
    local e = G.elevDeg or 0
    if G.held.E then e = e + ELEV_RATE * dt end
    if G.held.Q then e = e - ELEV_RATE * dt end
    G.elevDeg = Clamp(e, 0, MAX_ELEV)
end

-- ------------------------------------------------------------
-- 瞄准 / 出杆
-- ------------------------------------------------------------
local Fire

local function UpdateAim(dt)
    local cue = G.cue
    if not cue.active then return end

    if G.lmbDown then
        if IsMouseButtonDown("RightButton") then
            G.lmbDown = false; SetPowerBar(0)
        elseif not IsMouseButtonDown("LeftButton") then
            G.lmbDown = false; Fire(); return
        end
    end

    ApplyHeldKeys(dt or 0)
    UpdateStrikeHUD()

    local cx, cy = cue.x, cue.y
    local mfx, mfy = MouseFelt()
    local dx, dy = mfx - cx, mfy - cy
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then HideAimVisuals(); return end

    local ux, uy = dx / dist, dy / dist
    local fdx, fdy = -ux, -uy

    local pull = G.lmbDown and math.min(dist, MAX_PULL) or 0
    local frac = pull / MAX_PULL
    G.fireX, G.fireY, G.power = fdx, fdy, frac

    local previewFrac = (frac > 0.05) and frac or 0.5
    local curveAmt = (G.ox or 0) * math.sin(math.rad(G.elevDeg or 0))
    local pts = Physics.PredictCuePath(cx, cy, fdx, fdy, previewFrac * Physics.MAX_SPEED, curveAmt, G.balls)
    DrawAimDashes(pts)

    local base = geo.BALL_R + 6 + pull
    local function seg(line, da, db)
        line:SetStartPoint("BOTTOMLEFT", cx + ux * da, cy + uy * da)
        line:SetEndPoint("BOTTOMLEFT", cx + ux * db, cy + uy * db)
        line:Show()
    end
    seg(G.cueTip, base, base + 14)
    seg(G.cueShaft, base + 14, base + STICK_LEN - 34)
    seg(G.cueButt, base + STICK_LEN - 34, base + STICK_LEN)

    SetPowerBar(frac)
end

function Fire()
    if (G.power or 0) < (MIN_PULL / MAX_PULL) then SetPowerBar(0); return end

    local frac = G.power
    local ox, oy = G.ox or 0, G.oy or 0
    local fx, fy = G.fireX, G.fireY

    local mag = math.sqrt(ox * ox + oy * oy)
    if mag > MISCUE_SAFE then
        local chance = (mag - MISCUE_SAFE) / (1 - MISCUE_SAFE) * 0.5
        if math.random() < chance then
            frac = frac * 0.3
            local jit = (math.random() - 0.5) * 0.25
            local cs, sn = math.cos(jit), math.sin(jit)
            fx, fy = fx * cs - fy * sn, fx * sn + fy * cs
            ox, oy = 0, 0
            Print("滑杆!")
        end
    end

    -- 本杆"必须先碰"的最小号球 + 重置裁定标志
    G.requiredBall = nil
    for n = 1, 9 do if G.struct[n].active then G.requiredBall = n; break end end
    G._out.firstHit = nil
    G._out.railAfter = false
    G.ninePotted = false
    G.pottedThisShot = false

    local curveAmt = ox * math.sin(math.rad(G.elevDeg or 0))
    Physics.ShootSpin(G.cue, fx, fy, frac, ox, oy, curveAmt)

    G.strokes = (G.strokes or 0) + 1
    UpdateHUD()
    HideAimVisuals()
    SetPowerBar(0)
    G.state = "SHOOT"
end

local function ProcessPockets()
    local out = G._out
    if #out.pocketed == 0 then return end
    for _, b in ipairs(out.pocketed) do
        b.frame:Hide()
        if b.num == 0 then
            G.scratched = true
        else
            G.ballsLeft = (G.ballsLeft or 9) - 1
            G.pottedThisShot = true
            if b.num == 9 then G.ninePotted = true end
        end
    end
    UpdateHUD()
end

local function ResetCueSpin()
    local c = G.cue
    c.spinF, c.spinS, c.curve, c.shotDirX, c.shotDirY = 0, 0, 0, 0, 0
end

-- 9 号非法进袋 -> 重摆到置球点(被占就沿长轴顺延)
local function RespotNine()
    local s = G.struct[9]
    local r = geo.BALL_R
    local x, y = geo.FOOT_X, geo.CENTER_Y
    local function occupied(px, py)
        for n = 0, 9 do
            local o = G.struct[n]
            if o ~= s and o.active then
                local dx, dy = px - o.x, py - o.y
                if dx * dx + dy * dy < (2 * r) * (2 * r) then return true end
            end
        end
        return false
    end
    local tries = 0
    while occupied(x, y) and tries < 60 do
        x = x + r
        if x > geo.FELT_W - r then x = geo.FOOT_X; y = y + r end
        if y > geo.FELT_H - r then y = geo.CENTER_Y end
        tries = tries + 1
    end
    s.active, s.x, s.y, s.vx, s.vy = true, x, y, 0, 0
    s.frame:Show()
    G.ballsLeft = (G.ballsLeft or 0) + 1
end

-- 进入自由球放置模式
local function EnterPlace()
    G.cue.active = true
    G.cue.vx, G.cue.vy = 0, 0
    ResetCueSpin()
    HideAimVisuals()
    if G.placeHint then G.placeHint:SetText("自由球:移动鼠标放置母球,左键确认"); G.placeHint:Show() end
    G.state = "PLACE"
end

local function EndShot()
    local scratched = G.scratched
    local firstHit = G._out.firstHit

    -- 犯规裁定(优先级:进袋 > 空杆 > 未先碰最小号 > 碰球后无球到库且未进球)
    local foul, reason = false, nil
    if scratched then foul, reason = true, "母球进袋"
    elseif firstHit == nil then foul, reason = true, "空杆未碰到球"
    elseif firstHit ~= G.requiredBall then
        foul, reason = true, ("未先碰最小号球(应碰 " .. tostring(G.requiredBall) .. ",实先碰 " .. tostring(firstHit) .. ")")
    elseif not (G._out.railAfter or G.pottedThisShot) then
        foul, reason = true, "碰球后无球到库且未进球"
    end

    -- 9 号:合法进袋胜;犯规进袋重摆
    local win = false
    if G.ninePotted then
        if not foul then win = true else RespotNine() end
        G.ninePotted = false
    end

    if scratched then
        G.scratched = false
        G.cue.active = true
        ResetCueSpin()
    end

    if foul then
        G.strokes = (G.strokes or 0) + 1   -- 击球已计 1 杆,犯规再罚 1 杆
        Print("犯规(" .. reason .. "),罚 1 杆,自由球。")
    end

    G.ox, G.oy, G.elevDeg = 0, 0, 0
    ResetCueSpin()
    UpdateStrikeHUD()
    UpdateHUD()

    if win then
        G.state = "OVER"
        local best = DodoPoolDB and DodoPoolDB.bestStrokes
        if not best or G.strokes < best then
            if DodoPoolDB then DodoPoolDB.bestStrokes = G.strokes end
            G.winText:SetText("你赢了! 杆数 " .. (G.strokes or 0) .. "  新纪录!")
        else
            G.winText:SetText("你赢了! 杆数 " .. (G.strokes or 0))
        end
        G.winText:Show()
        G.SetKeyboard(false)
        Print("制胜! 杆数 " .. (G.strokes or 0) .. "。再点小地图或 /pool 开新局。")
        return
    end

    if foul then EnterPlace(); return end
    G.state = "AIM"
end

-- ------------------------------------------------------------
-- 目标球高亮(最小号在台的球,脉冲变亮)
-- ------------------------------------------------------------
local function UpdateTargetHighlight()
    if not G.struct then return end
    local lo
    for n = 1, 9 do
        local s = G.struct[n]
        if s and s.active then lo = n; break end
    end
    local a = 0.12 + 0.22 * (0.5 + 0.5 * math.sin(GetTime() * 5))
    for n = 1, 9 do
        local s = G.struct[n]
        if s and s.frame.target then
            if n == lo then s.frame.target:SetAlpha(a); s.frame.target:Show()
            else s.frame.target:Hide() end
        end
    end
end

-- 自由球放置(每帧)
local function UpdatePlace()
    local cue = G.cue
    local r = geo.BALL_R
    local mfx, mfy = MouseFelt()
    mfx = Clamp(mfx, r + 2, geo.FELT_W - r - 2)
    mfy = Clamp(mfy, r + 2, geo.FELT_H - r - 2)
    cue.x, cue.y, cue.active = mfx, mfy, true
    Render.PlaceBall(DP.playArea, cue.frame, mfx, mfy)
    cue.frame:Show()

    local legal = true
    for n = 1, 9 do
        local s = G.struct[n]
        if s.active then
            local dx, dy = mfx - s.x, mfy - s.y
            if dx * dx + dy * dy < (2 * r) * (2 * r) then legal = false; break end
        end
    end
    if legal then
        for _, p in ipairs(geo.Pockets()) do
            local dx, dy = mfx - p.x, mfy - p.y
            if dx * dx + dy * dy < (geo.POCKET_R + r) * (geo.POCKET_R + r) then legal = false; break end
        end
    end
    G.placeLegal = legal
    cue.frame:SetAlpha(legal and 1 or 0.4)
end

-- ------------------------------------------------------------
-- 驱动(每帧)
-- ------------------------------------------------------------
local function Driver(_, elapsed)
    if G.paused then return end
    UpdateTargetHighlight()
    if G.state == "AIM" then
        UpdateAim(elapsed)
    elseif G.state == "SHOOT" then
        wipe(G._out.pocketed)
        Physics.Step(G.balls, elapsed, G._out)
        SyncVisuals()
        ProcessPockets()
        if not Physics.ShotActive(G.balls) then EndShot() end
    elseif G.state == "PLACE" then
        UpdatePlace()
    end
end

local function OnMouseDown(_, button)
    if G.state == "PLACE" then
        if button == "LeftButton" and G.placeLegal then
            G.cue.frame:SetAlpha(1)
            if G.placeHint then G.placeHint:Hide() end
            G.state = "AIM"
        elseif button == "LeftButton" then
            Print("这里放不下,换个位置。")
        end
        return
    end
    if G.state ~= "AIM" then return end
    if button == "LeftButton" then
        G.lmbDown = true
    elseif button == "RightButton" then
        G.lmbDown = false; SetPowerBar(0)
    end
end

-- ------------------------------------------------------------
-- 进战:暂停 + 放开键盘
-- ------------------------------------------------------------
local function OnCombat(inCombat)
    if not G.balls then return end
    if inCombat then
        if DP.frame and DP.frame:IsShown() then
            G.paused = true
            G.SetKeyboard(false)
            if G.pauseText then G.pauseText:Show() end
        end
    else
        if DP.frame and DP.frame:IsShown() and (G.state == "AIM" or G.state == "SHOOT" or G.state == "PLACE") then
            G.paused = false
            G.SetKeyboard(true)
            if G.pauseText then G.pauseText:Hide() end
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
    G.SetKeyboard(false)
end

-- ------------------------------------------------------------
-- 公共:连线驱动/鼠标(只挂一次)
-- ------------------------------------------------------------
local function WireInput()
    local pa = DP.playArea
    pa:EnableMouse(true)
    if not G._wired then
        G._wired = true
        pa:SetScript("OnUpdate", Driver)
        pa:HookScript("OnMouseDown", OnMouseDown)
    end
    G.SetKeyboard(true)
end

local function ResetSessionState()
    G.strokes, G.ballsLeft = 0, 9
    G.won, G.scratched, G.lmbDown, G.paused = false, false, false, false
    G.ninePotted, G.pottedThisShot = false, false
    G.power, G.ox, G.oy, G.elevDeg = 0, 0, 0, 0
    G.requiredBall = nil
    G._out.firstHit, G._out.railAfter = nil, false
end

-- ------------------------------------------------------------
-- 开新局
-- ------------------------------------------------------------
function G.New()
    EnsureBalls(); EnsureVisuals(); EnsureHUD()

    local pos = geo.RackPositions()
    local order = { [1] = 1, [5] = 9 }
    local fillers = { 2, 3, 4, 5, 6, 7, 8 }
    for i = #fillers, 2, -1 do
        local j = math.random(i)
        fillers[i], fillers[j] = fillers[j], fillers[i]
    end
    local fi = 1
    for i = 1, #pos do if not order[i] then order[i] = fillers[fi]; fi = fi + 1 end end
    for i = 1, #pos do
        local s = G.struct[order[i]]
        s.x, s.y, s.vx, s.vy, s.active = pos[i].x, pos[i].y, 0, 0, true
        s.spinF, s.spinS, s.curve = 0, 0, 0
    end
    local cue = G.cue
    cue.x, cue.y, cue.vx, cue.vy, cue.active = geo.HEAD_X, geo.CENTER_Y, 0, 0, true
    cue.spinF, cue.spinS, cue.curve, cue.shotDirX, cue.shotDirY = 0, 0, 0, 0, 0
    cue.frame:SetAlpha(1)

    ResetSessionState()
    G.ballsLeft = 9
    G.state = "AIM"

    G.winText:Hide(); if G.pauseText then G.pauseText:Hide() end
    if G.placeHint then G.placeHint:Hide() end
    SyncVisuals(); UpdateHUD(); SetPowerBar(0); UpdateStrikeHUD()
    WireInput()
end

-- ------------------------------------------------------------
-- 存 / 读档(1 档)
-- ------------------------------------------------------------
function G.HasSave() return (DodoPoolDB and DodoPoolDB.save) ~= nil end

function G.Save()
    if G.state ~= "AIM" then Print("等球停稳(可瞄准时)再保存。"); return end
    if not DodoPoolDB then return end
    local sv = { cue = { x = G.cue.x, y = G.cue.y }, balls = {}, strokes = G.strokes or 0 }
    for n = 1, 9 do
        local s = G.struct[n]
        sv.balls[n] = { active = s.active, x = s.x, y = s.y }
    end
    DodoPoolDB.save = sv
    Print("进度已保存。")
end

function G.Load()
    EnsureBalls(); EnsureVisuals(); EnsureHUD()
    local sv = DodoPoolDB and DodoPoolDB.save
    if not sv then return false end
    for n = 1, 9 do
        local s, d = G.struct[n], sv.balls[n]
        if d then s.x, s.y, s.active = d.x, d.y, d.active else s.active = false end
        s.vx, s.vy, s.spinF, s.spinS, s.curve = 0, 0, 0, 0, 0
    end
    local cue = G.cue
    cue.x, cue.y, cue.vx, cue.vy, cue.active = sv.cue.x, sv.cue.y, 0, 0, true
    cue.spinF, cue.spinS, cue.curve, cue.shotDirX, cue.shotDirY = 0, 0, 0, 0, 0
    cue.frame:SetAlpha(1)

    ResetSessionState()
    G.strokes = sv.strokes or 0
    G.ballsLeft = 0
    for n = 1, 9 do if G.struct[n].active then G.ballsLeft = G.ballsLeft + 1 end end
    G.state = "AIM"

    G.winText:Hide(); if G.pauseText then G.pauseText:Hide() end
    if G.placeHint then G.placeHint:Hide() end
    SyncVisuals(); UpdateHUD(); SetPowerBar(0); UpdateStrikeHUD()
    WireInput()
    Print("已读取进度,杆数 " .. (G.strokes or 0) .. "。")
    return true
end

function G.SetPaused(p) G.paused = p and true or false end
