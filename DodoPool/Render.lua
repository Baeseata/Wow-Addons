-- DodoPool - Render
-- 把球桌/球画到一个 playArea 帧上。playArea 尺寸 = felt(FELT_W x FELT_H)，
-- 所有元素相对 playArea 左下角定位 (felt 坐标直接当像素偏移)。

local DP = _G.DodoPool or {}
_G.DodoPool = DP

local Render = {}
DP.Render = Render

local geo = DP.geo

-- 圆形遮罩(暴雪自带头像圆形 alpha mask，把方块裁成圆)
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- 球号 -> 职业 token(读 RAID_CLASS_COLORS 拿色，保证跟客户端一致)
local BALL_CLASS = {
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

-- 读不到职业色表时的兜底硬编码(近似职业色)
local BALL_FALLBACK = {
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

function Render.BallColor(n)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[BALL_CLASS[n]]
    if c then return c.r, c.g, c.b end
    local f = BALL_FALLBACK[n] or { 1, 1, 1 }
    return f[1], f[2], f[3]
end

-- 给一个 texture 套圆形遮罩
local function ApplyCircleMask(host, tex)
    local m = host:CreateMaskTexture()
    m:SetAllPoints(tex)
    m:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    tex:AddMaskTexture(m)
    return m
end

-- 建一颗球。num=0 表示母球(白、无号)。返回 ball 帧(含 .tex/.num/.glow)。
function Render.NewBall(parent, num)
    local r = geo.BALL_R
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(2 * r, 2 * r)
    b:SetFrameLevel((parent:GetFrameLevel() or 0) + 5)

    -- 底色
    local tex = b:CreateTexture(nil, "BORDER")
    tex:SetAllPoints()
    if num == 0 then
        tex:SetColorTexture(0.95, 0.95, 0.93, 1) -- 母球白
    else
        tex:SetColorTexture(Render.BallColor(num))
    end
    ApplyCircleMask(b, tex)
    b.tex = tex

    -- 球面阴影:下暗上微亮(假球体),圆形遮罩
    local shade = b:CreateTexture(nil, "ARTWORK")
    shade:SetAllPoints()
    if shade.SetGradient and CreateColor then
        shade:SetColorTexture(1, 1, 1, 1)
        shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.5), CreateColor(1, 1, 1, 0.12))
        ApplyCircleMask(b, shade)
    else
        shade:Hide()
    end

    -- 高光(左上),让球面有反光点
    local hi = b:CreateTexture(nil, "OVERLAY")
    hi:SetSize(r * 0.8, r * 0.8)
    hi:SetPoint("CENTER", b, "CENTER", -r * 0.34, r * 0.36)
    hi:SetColorTexture(1, 1, 1, 0.5)
    ApplyCircleMask(b, hi)
    b.hi = hi

    -- 目标高亮(只在"该打的球"上脉冲显示),叠在球面、号码之下
    local tgt = b:CreateTexture(nil, "OVERLAY")
    tgt:SetAllPoints()
    tgt:SetColorTexture(1, 0.95, 0.4, 1)
    tgt:SetBlendMode("ADD")
    ApplyCircleMask(b, tgt)
    tgt:Hide()
    b.target = tgt

    if num and num > 0 then
        local fs = b:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
        fs:SetPoint("CENTER")
        fs:SetText(tostring(num))
        fs:SetTextColor(1, 1, 1, 1)
        b.num = fs
    end

    return b
end

-- 把球放到 felt 坐标 (x,y)
function Render.PlaceBall(parent, ball, x, y)
    ball:ClearAllPoints()
    ball:SetPoint("CENTER", parent, "BOTTOMLEFT", x, y)
end

-- 建球桌静态部分:木框 + 绿绒 + 球带 + 6 个袋 + 标记。只建一次。
function Render.BuildTable(parent)
    if parent._built then return end
    parent._built = true

    local W, H, RAIL = geo.FELT_W, geo.FELT_H, geo.RAIL
    local hasGrad = (CreateColor ~= nil)

    -- 木框(四周外扩 RAIL)+ 竖向渐变 bevel(上亮下暗)
    local rail = parent:CreateTexture(nil, "BACKGROUND")
    rail:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -RAIL, -RAIL)
    rail:SetPoint("TOPRIGHT", parent, "BOTTOMLEFT", W + RAIL, H + RAIL)
    rail:SetColorTexture(0.30, 0.17, 0.08, 1)
    if hasGrad and rail.SetGradient then
        rail:SetColorTexture(1, 1, 1, 1)
        rail:SetGradient("VERTICAL", CreateColor(0.20, 0.11, 0.05, 1), CreateColor(0.45, 0.27, 0.13, 1))
    end

    -- 绿绒台面 + 竖向微渐变(假光照)
    local felt = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    felt:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    felt:SetSize(W, H)
    felt:SetColorTexture(0.11, 0.44, 0.25, 1)
    if hasGrad and felt.SetGradient then
        felt:SetColorTexture(1, 1, 1, 1)
        felt:SetGradient("VERTICAL", CreateColor(0.07, 0.33, 0.18, 1), CreateColor(0.14, 0.50, 0.29, 1))
    end

    -- 球带(cushion):四条深绿带贴内边(袋会盖在上面,形成缺口)
    local cw = 11
    local function strip(x1, y1, x2, y2)
        local t = parent:CreateTexture(nil, "BORDER")
        t:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x1, y1)
        t:SetPoint("TOPRIGHT", parent, "BOTTOMLEFT", x2, y2)
        t:SetColorTexture(0.05, 0.27, 0.15, 1)
    end
    strip(0, 0, W, cw)
    strip(0, H - cw, W, H)
    strip(0, 0, cw, H)
    strip(W - cw, 0, W, H)

    -- 袋(黑圆,画在球带之上)
    for _, p in ipairs(geo.Pockets()) do
        local pk = parent:CreateTexture(nil, "ARTWORK")
        pk:SetSize(2 * geo.POCKET_R, 2 * geo.POCKET_R)
        pk:SetPoint("CENTER", parent, "BOTTOMLEFT", p.x, p.y)
        pk:SetColorTexture(0.02, 0.04, 0.02, 1)
        ApplyCircleMask(parent, pk)
    end

    -- 标记:开球线 + 置球点
    local head = parent:CreateTexture(nil, "BORDER")
    head:SetSize(2, H - 2 * cw)
    head:SetPoint("CENTER", parent, "BOTTOMLEFT", geo.HEAD_X, H / 2)
    head:SetColorTexture(1, 1, 1, 0.10)
    local spot = parent:CreateTexture(nil, "BORDER")
    spot:SetSize(6, 6)
    spot:SetPoint("CENTER", parent, "BOTTOMLEFT", geo.FOOT_X, H / 2)
    spot:SetColorTexture(1, 1, 1, 0.18)
    ApplyCircleMask(parent, spot)
end
