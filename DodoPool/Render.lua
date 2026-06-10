-- DodoPool - Render
-- Draws the table/balls onto a playArea frame. playArea size = felt (FELT_W x FELT_H),
-- all elements positioned relative to playArea's bottom-left corner (felt coords used directly as pixel offsets).

local DP = _G.DodoPool or {}
_G.DodoPool = DP

local Render = {}
DP.Render = Render

local geo = DP.geo

-- Circle mask (Blizzard's built-in portrait circular alpha mask, crops a square into a circle)
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Ball number -> class token (reads RAID_CLASS_COLORS for color, to stay consistent with the client)
local BALL_CLASS = {
    [1] = "ROGUE",       -- yellow
    [2] = "SHAMAN",      -- blue
    [3] = "DEATHKNIGHT", -- red
    [4] = "WARLOCK",     -- light purple
    [5] = "DRUID",       -- orange
    [6] = "MONK",        -- jade green
    [7] = "WARRIOR",     -- brown
    [8] = "PALADIN",     -- pink
    [9] = "MAGE",        -- cyan
}

-- Hardcoded fallback when the class color table can't be read (approximate class colors)
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

-- Apply a circle mask to a texture
local function ApplyCircleMask(host, tex)
    local m = host:CreateMaskTexture()
    m:SetAllPoints(tex)
    m:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    tex:AddMaskTexture(m)
    return m
end

-- Create a ball. num=0 means the cue ball (white, no number). Returns the ball frame (with .tex/.num/.glow).
function Render.NewBall(parent, num)
    local r = geo.BALL_R
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(2 * r, 2 * r)
    b:SetFrameLevel((parent:GetFrameLevel() or 0) + 5)

    -- base color
    local tex = b:CreateTexture(nil, "BORDER")
    tex:SetAllPoints()
    if num == 0 then
        tex:SetColorTexture(0.95, 0.95, 0.93, 1) -- cue ball white
    else
        tex:SetColorTexture(Render.BallColor(num))
    end
    ApplyCircleMask(b, tex)
    b.tex = tex

    -- Ball surface shading: dark at the bottom, faintly bright at the top (fake sphere), circle mask
    local shade = b:CreateTexture(nil, "ARTWORK")
    shade:SetAllPoints()
    if shade.SetGradient and CreateColor then
        shade:SetColorTexture(1, 1, 1, 1)
        shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.5), CreateColor(1, 1, 1, 0.12))
        ApplyCircleMask(b, shade)
    else
        shade:Hide()
    end

    -- Highlight (top-left), gives the ball surface a reflection point
    local hi = b:CreateTexture(nil, "OVERLAY")
    hi:SetSize(r * 0.8, r * 0.8)
    hi:SetPoint("CENTER", b, "CENTER", -r * 0.34, r * 0.36)
    hi:SetColorTexture(1, 1, 1, 0.5)
    ApplyCircleMask(b, hi)
    b.hi = hi

    -- Target highlight (only pulses on "the ball to hit"), layered below the surface shade and the number
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

-- Place a ball at felt coordinate (x,y)
function Render.PlaceBall(parent, ball, x, y)
    ball:ClearAllPoints()
    ball:SetPoint("CENTER", parent, "BOTTOMLEFT", x, y)
end

-- Build the static parts of the table: wooden frame + felt + cushions + 6 pockets + markings. Built once.
function Render.BuildTable(parent)
    if parent._built then return end
    parent._built = true

    local W, H, RAIL = geo.FELT_W, geo.FELT_H, geo.RAIL
    local hasGrad = (CreateColor ~= nil)

    -- Wooden frame (expanded outward by RAIL on all sides) + vertical gradient bevel (bright top, dark bottom)
    local rail = parent:CreateTexture(nil, "BACKGROUND")
    rail:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -RAIL, -RAIL)
    rail:SetPoint("TOPRIGHT", parent, "BOTTOMLEFT", W + RAIL, H + RAIL)
    rail:SetColorTexture(0.30, 0.17, 0.08, 1)
    if hasGrad and rail.SetGradient then
        rail:SetColorTexture(1, 1, 1, 1)
        rail:SetGradient("VERTICAL", CreateColor(0.20, 0.11, 0.05, 1), CreateColor(0.45, 0.27, 0.13, 1))
    end

    -- Green felt surface + slight vertical gradient (fake lighting)
    local felt = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    felt:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    felt:SetSize(W, H)
    felt:SetColorTexture(0.11, 0.44, 0.25, 1)
    if hasGrad and felt.SetGradient then
        felt:SetColorTexture(1, 1, 1, 1)
        felt:SetGradient("VERTICAL", CreateColor(0.07, 0.33, 0.18, 1), CreateColor(0.14, 0.50, 0.29, 1))
    end

    -- Cushions: four dark-green strips along the inner edge (pockets layer over them, forming gaps)
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

    -- Pockets (black circles, drawn over the cushions)
    for _, p in ipairs(geo.Pockets()) do
        local pk = parent:CreateTexture(nil, "ARTWORK")
        pk:SetSize(2 * geo.POCKET_R, 2 * geo.POCKET_R)
        pk:SetPoint("CENTER", parent, "BOTTOMLEFT", p.x, p.y)
        pk:SetColorTexture(0.02, 0.04, 0.02, 1)
        ApplyCircleMask(parent, pk)
    end

    -- Markings: break line + foot spot
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
