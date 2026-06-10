-- DodoBricks - Render
-- 棋盘/砖/球/道具的视觉。所有元素相对宿主帧左下角定位(board 坐标直接当像素偏移)。
-- 三角砖画法:纯色 texture 用 SetVertexOffset 把一个角折叠到相邻角上,渲染出实心直角三角形,
--             不需要任何自定义贴图;四个朝向 = 折叠不同的角(BL/BR/TL/TR = 直角所在角)。
-- 砖配色:沿用 DodoPool 的职业色板,按血量循环取色((hp-1)%9+1),每掉一滴血换一次色 = 伤害反馈。

local DBR = _G.DodoBricks or {}
_G.DodoBricks = DBR

local Render = {}
DBR.Render = Render

local geo = DBR.geo

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- 血量 -> 职业 token(读 RAID_CLASS_COLORS 拿色,与 DodoPool 球色同源)
local TIER_CLASS = {
    [1] = "ROGUE",       -- 黄
    [2] = "SHAMAN",      -- 蓝
    [3] = "DEATHKNIGHT", -- 红
    [4] = "WARLOCK",     -- 淡紫
    [5] = "DRUID",       -- 橙
    [6] = "MONK",        -- 玉绿
    [7] = "WARRIOR",     -- 棕
    [8] = "PALADIN",     -- 粉
    [9] = "MAGE",        -- 青
}
local TIER_FALLBACK = {
    [1] = { 0.99, 0.96, 0.41 },
    [2] = { 0.00, 0.44, 0.87 },
    [3] = { 0.77, 0.12, 0.23 },
    [4] = { 0.53, 0.53, 0.93 },
    [5] = { 1.00, 0.49, 0.04 },
    [6] = { 0.00, 1.00, 0.60 },
    [7] = { 0.78, 0.61, 0.43 },
    [8] = { 0.96, 0.55, 0.73 },
    [9] = { 0.25, 0.78, 0.92 },
}

function Render.TierColor(hp)
    local i = ((math.max(1, hp) - 1) % 9) + 1
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[TIER_CLASS[i]]
    if c then return c.r, c.g, c.b end
    local f = TIER_FALLBACK[i]
    return f[1], f[2], f[3]
end

-- 给一个 texture 套圆形遮罩(DodoPool 同款;贴图必须 SetPoint 否则不渲染)
local function ApplyCircleMask(host, tex)
    local m = host:CreateMaskTexture()
    m:SetAllPoints(tex)
    m:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    tex:AddMaskTexture(m)
    return m
end

local function MakeCircle(host, size, layer, r, g, b, a)
    local t = host:CreateTexture(nil, layer or "ARTWORK")
    t:SetSize(size, size)
    t:SetPoint("CENTER", host, "CENTER", 0, 0)
    t:SetColorTexture(r, g, b, a or 1)
    ApplyCircleMask(host, t)
    return t
end
Render.MakeCircle = MakeCircle

-- ------------------------------------------------------------
-- 三角形 texture:尺寸 S 的方块折叠成直角三角形
-- orient = 直角所在角:"BL" | "BR" | "TL" | "TR"
-- SetVertexOffset 顶点序号:1=左上 2=左下 3=右上 4=右下;y 正方向向上。
-- 折叠后两个渲染三角形之一退化为零面积,留下的恰是目标三角形(两种内部三角剖分下都成立)。
-- ------------------------------------------------------------
local function CollapseToTriangle(tex, S, orient)
    -- 先清零四角(SetHP 重建时可能换尺寸)
    for i = 1, 4 do tex:SetVertexOffset(i, 0, 0) end
    if orient == "BL" then
        tex:SetVertexOffset(3, -S, 0)   -- 右上角折到左上 => 剩 (0,0)(S,0)(0,S)
    elseif orient == "BR" then
        tex:SetVertexOffset(1, 0, -S)   -- 左上角折到左下 => 剩 (0,0)(S,0)(S,S)
    elseif orient == "TL" then
        tex:SetVertexOffset(4, -S, 0)   -- 右下角折到左下 => 剩 (0,0)(S,S)(0,S)
    elseif orient == "TR" then
        tex:SetVertexOffset(2, S, 0)    -- 左下角折到右下 => 剩 (S,0)(S,S)(0,S)
    end
end

-- 直角角落的锚点名(内层三角形往直角缩进用)
local ANCHOR_OF = { BL = "BOTTOMLEFT", BR = "BOTTOMRIGHT", TL = "TOPLEFT", TR = "TOPRIGHT" }
-- 数字往直角方向偏移的符号
local NUMOFF = { BL = { -1, -1 }, BR = { 1, -1 }, TL = { -1, 1 }, TR = { 1, 1 } }

-- ------------------------------------------------------------
-- 砖:shape = "sq" | "tri";tri 带 orient。返回 frame(含 :SetHP(hp))。
-- 视觉尺寸 = CELL - 2*BRICK_PAD(留缝),碰撞仍按整格(Physics 管)。
-- ------------------------------------------------------------
local hasGrad = (CreateColor ~= nil)

function Render.NewBrick(parent, shape, orient)
    local S = geo.CELL - 2 * geo.BRICK_PAD
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(S, S)
    b.shape, b.orient = shape, orient

    -- 外层 = 边框色(深),内层 = 主色渐变(下深上亮)
    local outer = b:CreateTexture(nil, "BORDER")
    outer:SetAllPoints()
    local inner = b:CreateTexture(nil, "ARTWORK")
    b.outer, b.inner = outer, inner

    if shape == "tri" then
        CollapseToTriangle(outer, S, orient)
        local SI = S - 5
        inner:SetSize(SI, SI)
        local a = ANCHOR_OF[orient]
        local sx, sy = NUMOFF[orient][1], NUMOFF[orient][2]
        inner:SetPoint(a, b, a, -sx * 2, -sy * 2)   -- 往三角内部缩 2px
        CollapseToTriangle(inner, SI, orient)
    else
        inner:SetPoint("TOPLEFT", 2, -2)
        inner:SetPoint("BOTTOMRIGHT", -2, 2)
    end

    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, shape == "tri" and 12 or 14, "OUTLINE")
    if shape == "tri" then
        local sx, sy = NUMOFF[orient][1], NUMOFF[orient][2]
        fs:SetPoint("CENTER", b, "CENTER", sx * (geo.CELL * 0.14), sy * (geo.CELL * 0.14))
    else
        fs:SetPoint("CENTER")
    end
    fs:SetTextColor(1, 1, 1, 1)
    b.num = fs

    function b.SetHP(self, hp)
        local r, g, bl = Render.TierColor(hp)
        self.outer:SetColorTexture(r * 0.35, g * 0.35, bl * 0.35, 1)
        if hasGrad and self.inner.SetGradient then
            self.inner:SetColorTexture(1, 1, 1, 1)
            self.inner:SetGradient("VERTICAL",
                CreateColor(r * 0.62, g * 0.62, bl * 0.62, 1),
                CreateColor(math.min(1, r * 1.12), math.min(1, g * 1.12), math.min(1, bl * 1.12), 1))
        else
            self.inner:SetColorTexture(r, g, bl, 1)
        end
        self.num:SetText(tostring(hp))
    end

    return b
end

-- 砖放到格(col,row),带视觉下移偏移 dy(下压动画用;0 = 到位)
function Render.PlaceBrick(parent, brick, col, row, dy)
    local x0, y0 = geo.CellRect(col, row)
    brick:ClearAllPoints()
    brick:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x0 + geo.BRICK_PAD, y0 + geo.BRICK_PAD + (dy or 0))
end

-- ------------------------------------------------------------
-- 弹球(白,小高光)。返回 frame。
-- ------------------------------------------------------------
function Render.NewBall(parent)
    local r = geo.BALL_R
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(2 * r, 2 * r)
    b:SetFrameLevel((parent:GetFrameLevel() or 0) + 6)
    MakeCircle(b, 2 * r, "ARTWORK", 0.96, 0.96, 0.94, 1)
    local hi = b:CreateTexture(nil, "OVERLAY")
    hi:SetSize(r * 0.7, r * 0.7)
    hi:SetPoint("CENTER", b, "CENTER", -r * 0.3, r * 0.3)
    hi:SetColorTexture(1, 1, 1, 0.55)
    ApplyCircleMask(b, hi)
    return b
end

function Render.PlaceAt(parent, fr, x, y)
    fr:ClearAllPoints()
    fr:SetPoint("CENTER", parent, "BOTTOMLEFT", x, y)
end

-- ------------------------------------------------------------
-- 道具:外环(颜色按种类)+ 中心图形。返回 frame(含 .ring 供脉冲)。
-- kind: "ball" +1球(白环+小球) / "laserH" 横激光(红环+横杠) / "laserV" 竖激光(红环+竖杠)
--       / "bomb" 炸弹(橙环+实心圆)
-- ------------------------------------------------------------
local ITEM_RING = {
    ball   = { 0.95, 0.95, 0.95 },
    laserH = { 1.00, 0.38, 0.32 },
    laserV = { 1.00, 0.38, 0.32 },
    bomb   = { 1.00, 0.62, 0.15 },
}

function Render.NewItem(parent, kind)
    kind = kind or "ball"
    local R = geo.ITEM_R
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(2 * R + 8, 2 * R + 8)
    f:SetFrameLevel((parent:GetFrameLevel() or 0) + 4)
    local rc = ITEM_RING[kind] or ITEM_RING.ball
    local ring = MakeCircle(f, 2 * R, "ARTWORK", rc[1], rc[2], rc[3], 0.9)
    local hole = MakeCircle(f, 2 * R - 6, "ARTWORK", 0.045, 0.045, 0.085, 1)  -- 与棋盘底色一致,抠出环
    if kind == "laserH" or kind == "laserV" then
        local bar = f:CreateTexture(nil, "OVERLAY")
        if kind == "laserH" then bar:SetSize(2 * R - 8, 3) else bar:SetSize(3, 2 * R - 8) end
        bar:SetPoint("CENTER")
        bar:SetColorTexture(1, 0.5, 0.45, 1)
    elseif kind == "bomb" then
        MakeCircle(f, 9, "OVERLAY", 1, 0.62, 0.15, 1)
    else
        MakeCircle(f, 8, "OVERLAY", 0.96, 0.96, 0.94, 1)
    end
    f.ring, f.hole = ring, hole
    return f
end

-- ------------------------------------------------------------
-- 特效构件(Game 的特效池用):碎砖闪光 / 激光束 / 爆炸圈,都是 ADD 叠加发光
-- ------------------------------------------------------------

-- 碎砖闪光:与砖同形状的白色 ADD 贴图(三角同向折叠)
function Render.NewBrickFlash(parent, shape, orient)
    local S = geo.CELL - 2 * geo.BRICK_PAD
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(S, S)
    f:SetFrameLevel((parent:GetFrameLevel() or 0) + 7)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetColorTexture(1, 1, 1, 1)
    t:SetBlendMode("ADD")
    if shape == "tri" then CollapseToTriangle(t, S, orient) end
    return f
end

-- 激光束:横贯整行 / 纵贯整列的发光条
function Render.NewBeam(parent, horiz)
    local f = CreateFrame("Frame", nil, parent)
    if horiz then f:SetSize(geo.BOARD_W, 10) else f:SetSize(10, geo.ROWS * geo.CELL) end
    f:SetFrameLevel((parent:GetFrameLevel() or 0) + 7)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetColorTexture(1, 0.45, 0.4, 1)
    t:SetBlendMode("ADD")
    local core = f:CreateTexture(nil, "OVERLAY", nil, 1)
    if horiz then
        core:SetPoint("LEFT"); core:SetPoint("RIGHT"); core:SetHeight(3)
    else
        core:SetPoint("TOP"); core:SetPoint("BOTTOM"); core:SetWidth(3)
    end
    core:SetColorTexture(1, 0.9, 0.85, 1)
    core:SetBlendMode("ADD")
    return f
end

-- 爆炸圈:橙色发光圆,Game 里放大+淡出
function Render.NewBoom(parent)
    local f = CreateFrame("Frame", nil, parent)
    local D = geo.CELL * 2.2
    f:SetSize(D, D)
    f:SetFrameLevel((parent:GetFrameLevel() or 0) + 7)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetSize(D, D)
    t:SetPoint("CENTER")
    t:SetColorTexture(1, 0.55, 0.18, 0.9)
    t:SetBlendMode("ADD")
    ApplyCircleMask(f, t)
    local core = f:CreateTexture(nil, "OVERLAY", nil, 1)
    core:SetSize(D * 0.45, D * 0.45)
    core:SetPoint("CENTER")
    core:SetColorTexture(1, 0.9, 0.6, 0.9)
    core:SetBlendMode("ADD")
    ApplyCircleMask(f, core)
    return f
end

-- ------------------------------------------------------------
-- 瞄准虚线点(小白点)
-- ------------------------------------------------------------
function Render.NewDot(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(6, 6)
    f:SetFrameLevel((parent:GetFrameLevel() or 0) + 8)
    MakeCircle(f, 6, "OVERLAY", 1, 1, 1, 0.8)
    return f
end

-- ------------------------------------------------------------
-- 棋盘静态部分:深底 + 左右上细壁 + 发射条 + 地线。只建一次。
-- ------------------------------------------------------------
function Render.BuildBoard(parent)
    if parent._built then return end
    parent._built = true

    local W, H, FLOOR = geo.BOARD_W, geo.BOARD_H, geo.FLOOR

    -- 越界裁剪:下压动画时顶部刷新行从板外滑入,不能画出棋盘外
    parent:SetClipsChildren(true)

    -- 深色底
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.045, 0.045, 0.085, 1)

    -- 发射条(底部,略亮一点)
    local strip = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    strip:SetPoint("BOTTOMLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", parent, "BOTTOMLEFT", W, FLOOR)
    strip:SetColorTexture(0.08, 0.08, 0.13, 1)

    -- 地线(球落回 / 砖压到这条线就完了)
    local floorLine = parent:CreateTexture(nil, "BORDER")
    floorLine:SetPoint("BOTTOMLEFT", 0, FLOOR - 1)
    floorLine:SetPoint("TOPRIGHT", parent, "BOTTOMLEFT", W, FLOOR)
    floorLine:SetColorTexture(0.75, 0.3, 0.3, 0.35)

    -- 左 / 右 / 顶细壁(反弹边界的视觉提示)
    local function wall(x1, y1, x2, y2)
        local t = parent:CreateTexture(nil, "BORDER")
        t:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x1, y1)
        t:SetPoint("TOPRIGHT", parent, "BOTTOMLEFT", x2, y2)
        t:SetColorTexture(0.45, 0.5, 0.65, 0.4)
    end
    wall(0, 0, 2, H)
    wall(W - 2, 0, W, H)
    wall(0, H - 2, W, H)
end
