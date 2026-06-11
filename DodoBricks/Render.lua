-- DodoBricks - Render
-- Visuals for the board / bricks / balls / items. All elements are positioned relative to the host frame's bottom-left corner (board coords used directly as pixel offsets).
-- Triangle bricks: a solid-color texture is folded with SetVertexOffset, collapsing one corner onto an adjacent one to render a solid right triangle,
--             with no custom textures needed; the four orientations = folding different corners (BL/BR/TL/TR = the corner holding the right angle).
-- Brick colors: reuse DodoPool's class color palette, cycling by HP ((hp-1)%9+1), changing color each time a hit is taken = damage feedback.

local DBR = _G.DodoBricks or {}
_G.DodoBricks = DBR

local Render = {}
DBR.Render = Render

local geo = DBR.geo

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- HP -> class token (reads RAID_CLASS_COLORS for color, same source as DodoPool's ball colors)
local TIER_CLASS = {
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

-- Palette rotation (0.3.0): Game sets colorShift = floor((level-1)/10), so every 10 levels the
-- hp->color mapping rotates one slot = a visible "new season" as you push deeper. Existing bricks
-- recolor lazily on their next hit (SetHP), which blends the transition naturally.
Render.colorShift = 0

function Render.TierColor(hp)
    local i = ((math.max(1, hp) - 1 + (Render.colorShift or 0)) % 9) + 1
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[TIER_CLASS[i]]
    if c then return c.r, c.g, c.b end
    local f = TIER_FALLBACK[i]
    return f[1], f[2], f[3]
end

-- Fixed colors for special bricks (not part of the hp color cycle)
local KIND_COLOR = {
    healer = { 0.16, 0.72, 0.32 },   -- green: "the medic" - kill it first or it heals its neighbors
    chest  = { 0.95, 0.76, 0.20 },   -- gold: treasure, breaking it drops an item ring
}

-- Apply a circle mask to a texture (same as DodoPool; the texture must be SetPoint or it won't render)
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
-- Triangle texture: a square of size S folded into a right triangle
-- orient = the corner holding the right angle: "BL" | "BR" | "TL" | "TR"
-- SetVertexOffset vertex indices: 1=top-left 2=bottom-left 3=top-right 4=bottom-right; +y is up.
-- After folding, one of the two rendered triangles degenerates to zero area, leaving exactly the target triangle (holds under both internal triangulations).
-- ------------------------------------------------------------
local function CollapseToTriangle(tex, S, orient)
    -- zero all four corners first (a rebuild via SetHP may change the size)
    for i = 1, 4 do tex:SetVertexOffset(i, 0, 0) end
    if orient == "BL" then
        tex:SetVertexOffset(3, -S, 0)   -- fold the top-right corner onto top-left => leaves (0,0)(S,0)(0,S)
    elseif orient == "BR" then
        tex:SetVertexOffset(1, 0, -S)   -- fold the top-left corner onto bottom-left => leaves (0,0)(S,0)(S,S)
    elseif orient == "TL" then
        tex:SetVertexOffset(4, -S, 0)   -- fold the bottom-right corner onto bottom-left => leaves (0,0)(S,S)(0,S)
    elseif orient == "TR" then
        tex:SetVertexOffset(2, S, 0)    -- fold the bottom-left corner onto bottom-right => leaves (S,0)(S,S)(0,S)
    end
end

-- anchor name of the right-angle corner (the inner triangle insets toward the right angle)
local ANCHOR_OF = { BL = "BOTTOMLEFT", BR = "BOTTOMRIGHT", TL = "TOPLEFT", TR = "TOPRIGHT" }
-- sign of the number's offset toward the right-angle corner
local NUMOFF = { BL = { -1, -1 }, BR = { 1, -1 }, TL = { -1, 1 }, TR = { 1, 1 } }

-- ------------------------------------------------------------
-- Brick: shape = "sq" | "tri"; tri carries orient. Returns a frame (with :SetHP(hp)).
-- Visual size = CELL - 2*BRICK_PAD (leaves a seam), collision still uses the full cell (handled by Physics).
-- ------------------------------------------------------------
local hasGrad = (CreateColor ~= nil)

function Render.NewBrick(parent, shape, orient, kind)
    local S = geo.CELL - 2 * geo.BRICK_PAD
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(S, S)
    b.shape, b.orient, b.kind = shape, orient, kind

    -- outer = border color (dark), inner = main color gradient (dark at bottom, bright at top)
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
        inner:SetPoint(a, b, a, -sx * 2, -sy * 2)   -- inset 2px into the triangle
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

    -- healer: a small white cross glyph in the top-left corner ("the medic"), hp number stays centered
    if kind == "healer" then
        local cv = b:CreateTexture(nil, "OVERLAY")
        cv:SetSize(3, 11)
        cv:SetPoint("TOPLEFT", b, "TOPLEFT", 9, -5)
        cv:SetColorTexture(1, 1, 1, 0.95)
        local ch = b:CreateTexture(nil, "OVERLAY")
        ch:SetSize(11, 3)
        ch:SetPoint("CENTER", cv, "CENTER", 0, 0)
        ch:SetColorTexture(1, 1, 1, 0.95)
    end

    function b.SetHP(self, hp)
        local fc = KIND_COLOR[self.kind]
        local r, g, bl
        if fc then r, g, bl = fc[1], fc[2], fc[3] else r, g, bl = Render.TierColor(hp) end
        self.outer:SetColorTexture(r * 0.35, g * 0.35, bl * 0.35, 1)
        if hasGrad and self.inner.SetGradient then
            self.inner:SetColorTexture(1, 1, 1, 1)
            self.inner:SetGradient("VERTICAL",
                CreateColor(r * 0.62, g * 0.62, bl * 0.62, 1),
                CreateColor(math.min(1, r * 1.12), math.min(1, g * 1.12), math.min(1, bl * 1.12), 1))
        else
            self.inner:SetColorTexture(r, g, bl, 1)
        end
        -- chest shows "?" instead of an hp number (mystery loot reads better than "2")
        if self.kind == "chest" then
            self.num:SetText("?")
        else
            self.num:SetText(tostring(hp))
        end
    end

    return b
end

-- ------------------------------------------------------------
-- Boss brick (0.3.0): a 3x3-cell mega brick, fixed dark red, big centered hp number.
-- Same .SetHP interface as a normal brick; collision is the full 3x3 AABB (Physics reads brick.w/h).
-- ------------------------------------------------------------
function Render.NewBossBrick(parent)
    local S = 3 * geo.CELL - 2 * geo.BRICK_PAD
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(S, S)
    b.shape, b.kind = "sq", "boss"

    local outer = b:CreateTexture(nil, "BORDER")
    outer:SetAllPoints()
    outer:SetColorTexture(0.16, 0.03, 0.05, 1)
    local inner = b:CreateTexture(nil, "ARTWORK")
    inner:SetPoint("TOPLEFT", 3, -3)
    inner:SetPoint("BOTTOMRIGHT", -3, 3)
    b.outer, b.inner = outer, inner

    local r, g, bl = 0.72, 0.10, 0.18
    if hasGrad and inner.SetGradient then
        inner:SetColorTexture(1, 1, 1, 1)
        inner:SetGradient("VERTICAL",
            CreateColor(r * 0.55, g * 0.55, bl * 0.55, 1),
            CreateColor(math.min(1, r * 1.25), math.min(1, g * 1.25), math.min(1, bl * 1.25), 1))
    else
        inner:SetColorTexture(r, g, bl, 1)
    end

    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 26, "OUTLINE")
    fs:SetPoint("CENTER")
    fs:SetTextColor(1, 0.92, 0.85, 1)
    b.num = fs

    function b.SetHP(self, hp)
        self.num:SetText(tostring(hp))
    end

    return b
end

-- Place a brick at cell (col,row), with a visual downward offset dy (used by the descend animation; 0 = in place)
function Render.PlaceBrick(parent, brick, col, row, dy)
    local x0, y0 = geo.CellRect(col, row)
    brick:ClearAllPoints()
    brick:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x0 + geo.BRICK_PAD, y0 + geo.BRICK_PAD + (dy or 0))
end

-- ------------------------------------------------------------
-- Ball (white, small highlight). Returns a frame.
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

-- Hot-path move (ball + trail, hundreds of times per frame): replace the same CENTER anchor directly, skipping ClearAllPoints.
-- Only usable on frames that "only ever use the CENTER anchor" (ball / trail / aim dots).
function Render.MoveAt(parent, fr, x, y)
    fr:SetPoint("CENTER", parent, "BOTTOMLEFT", x, y)
end

-- ------------------------------------------------------------
-- Comet trail afterimage: segment k (1 near, 3 far), smaller and fainter the farther out, ADD glow
-- ------------------------------------------------------------
local GHOST_SIZE  = { 0.78, 0.58, 0.38 }   -- size ratio relative to the ball's diameter
local GHOST_ALPHA = { 0.30, 0.16, 0.07 }

function Render.NewGhost(parent, k)
    local r = geo.BALL_R * (GHOST_SIZE[k] or 0.3)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(2 * r, 2 * r)
    f:SetFrameLevel((parent:GetFrameLevel() or 0) + 5)   -- below the ball (+6), above the bricks
    local t = MakeCircle(f, 2 * r, "ARTWORK", 1, 1, 1, GHOST_ALPHA[k] or 0.05)
    t:SetBlendMode("ADD")
    f:Hide()
    return f
end

-- ------------------------------------------------------------
-- Item: outer ring (color by kind) + a glyph that is a MINIATURE PREVIEW of the effect (0.3.0 design:
-- no text anywhere - the glyph hints the effect, the trigger VFX teaches it for real on first contact).
-- kinds: ball "+1 ball" (white ring + dot) / laserH / laserV (red ring + bar poking past the ring = "pierces the whole line")
--        / laserD1 "/" diagonal / laserD2 "\" diagonal (the glyph slant = the actual sweep direction, honest preview)
--        / laserX cross laser (gold ring + plus, rare) / bomb (orange ring + core with x-shaped spikes)
--        / split (violet ring + two side-by-side dots = "each ball doubles")
-- ------------------------------------------------------------
local ITEM_RING = {
    ball    = { 0.95, 0.95, 0.95 },
    laserH  = { 1.00, 0.38, 0.32 },
    laserV  = { 1.00, 0.38, 0.32 },
    laserD1 = { 1.00, 0.38, 0.32 },
    laserD2 = { 1.00, 0.38, 0.32 },
    laserX  = { 1.00, 0.82, 0.20 },
    bomb    = { 1.00, 0.62, 0.15 },
    split   = { 0.72, 0.52, 0.95 },
}

function Render.NewItem(parent, kind)
    kind = kind or "ball"
    local R = geo.ITEM_R
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(2 * R + 8, 2 * R + 8)
    f:SetFrameLevel((parent:GetFrameLevel() or 0) + 4)
    local rc = ITEM_RING[kind] or ITEM_RING.ball
    local ring = MakeCircle(f, 2 * R, "ARTWORK", rc[1], rc[2], rc[3], 0.9)
    local hole = MakeCircle(f, 2 * R - 6, "ARTWORK", 0.045, 0.045, 0.085, 1)  -- same as the board background, punches out the ring

    local function glyphLine(x1, y1, x2, y2, w, r, g, b)
        local L = f:CreateLine(nil, "OVERLAY")
        L:SetStartPoint("CENTER", f, x1, y1)
        L:SetEndPoint("CENTER", f, x2, y2)
        L:SetThickness(w or 3)
        L:SetColorTexture(r or 1, g or 0.5, b or 0.45, 1)
        return L
    end

    if kind == "laserH" then
        glyphLine(-(R + 2), 0, R + 2, 0)                 -- pokes 2px past the ring: "goes through"
    elseif kind == "laserV" then
        glyphLine(0, -(R + 2), 0, R + 2)
    elseif kind == "laserD1" then                        -- "/" = sweeps the up-right diagonal
        local d = (R + 2) * 0.71
        glyphLine(-d, -d, d, d)
    elseif kind == "laserD2" then                        -- "\" = sweeps the down-right diagonal
        local d = (R + 2) * 0.71
        glyphLine(-d, d, d, -d)
    elseif kind == "laserX" then
        glyphLine(-(R - 1), 0, R - 1, 0, 3, 1, 0.85, 0.35)
        glyphLine(0, -(R - 1), 0, R - 1, 3, 1, 0.85, 0.35)
    elseif kind == "bomb" then
        MakeCircle(f, 8, "OVERLAY", 1, 0.62, 0.15, 1)
        local d1, d2 = 4, R - 1                          -- four diagonal spikes (x-shape, distinct from laserX's +)
        glyphLine(d1, d1, d2, d2, 2, 1, 0.62, 0.15)
        glyphLine(-d1, d1, -d2, d2, 2, 1, 0.62, 0.15)
        glyphLine(d1, -d1, d2, -d2, 2, 1, 0.62, 0.15)
        glyphLine(-d1, -d1, -d2, -d2, 2, 1, 0.62, 0.15)
    elseif kind == "split" then
        MakeCircle(f, 7, "OVERLAY", 0.95, 0.92, 1, 1):SetPoint("CENTER", f, "CENTER", -5, 0)
        MakeCircle(f, 7, "OVERLAY", 0.95, 0.92, 1, 1):SetPoint("CENTER", f, "CENTER", 5, 0)
    else
        MakeCircle(f, 8, "OVERLAY", 0.96, 0.96, 0.94, 1)
    end
    f.ring, f.hole = ring, hole
    return f
end

-- ------------------------------------------------------------
-- Effect pieces (used by Game's effect pool): brick flash / laser beam / explosion ring, all ADD-blended glow
-- ------------------------------------------------------------

-- Brick flash: a white ADD texture in the same shape as the brick (triangle folded the same way)
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

-- Laser beam: a glowing bar spanning a full row / full column
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

-- Explosion ring: an orange glowing circle, grown + faded out in Game
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

-- Diagonal laser beam (0.3.0): a long glowing line at 45 degrees through the trigger point.
-- ne=true is the "/" direction (up-right), false is "\". Long enough to cross the whole board; playArea clips the overhang.
function Render.NewBeamD(parent, ne)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(2, 2)
    f:SetFrameLevel((parent:GetFrameLevel() or 0) + 7)
    local L = (geo.BOARD_W + geo.BOARD_H) * 0.75
    local s = ne and 1 or -1
    local t = f:CreateLine(nil, "OVERLAY")
    t:SetStartPoint("CENTER", f, -L, -s * L)
    t:SetEndPoint("CENTER", f, L, s * L)
    t:SetThickness(10)
    t:SetColorTexture(1, 0.45, 0.4, 1)
    t:SetBlendMode("ADD")
    local core = f:CreateLine(nil, "OVERLAY", nil, 1)
    core:SetStartPoint("CENTER", f, -L, -s * L)
    core:SetEndPoint("CENTER", f, L, s * L)
    core:SetThickness(3)
    core:SetColorTexture(1, 0.9, 0.85, 1)
    core:SetBlendMode("ADD")
    return f
end

-- Colored pulse ring (0.3.0): small ADD circle, used by the healer pulse (green) and the split pop (violet)
function Render.NewPop(parent, r, g, b)
    local f = CreateFrame("Frame", nil, parent)
    local D = geo.CELL * 1.25
    f:SetSize(D, D)
    f:SetFrameLevel((parent:GetFrameLevel() or 0) + 7)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetSize(D, D)
    t:SetPoint("CENTER")
    t:SetColorTexture(r, g, b, 0.85)
    t:SetBlendMode("ADD")
    ApplyCircleMask(f, t)
    return f
end

-- Boss hit/death flash: a 3x3-cell white ADD block
function Render.NewBossFlash(parent)
    local S = 3 * geo.CELL - 2 * geo.BRICK_PAD
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(S, S)
    f:SetFrameLevel((parent:GetFrameLevel() or 0) + 7)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetColorTexture(1, 1, 1, 1)
    t:SetBlendMode("ADD")
    return f
end

-- ------------------------------------------------------------
-- Aim dot (small white dot)
-- ------------------------------------------------------------
function Render.NewDot(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(6, 6)
    f:SetFrameLevel((parent:GetFrameLevel() or 0) + 8)
    MakeCircle(f, 6, "OVERLAY", 1, 1, 1, 0.8)
    return f
end

-- ------------------------------------------------------------
-- Static parts of the board: dark base + thin left/right/top walls + launch strip + floor line. Built once.
-- ------------------------------------------------------------
function Render.BuildBoard(parent)
    if parent._built then return end
    parent._built = true

    local W, H, FLOOR = geo.BOARD_W, geo.BOARD_H, geo.FLOOR

    -- Clip overflow: during the descend animation the top spawn row slides in from outside the board, must not draw outside it
    parent:SetClipsChildren(true)

    -- dark base
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.045, 0.045, 0.085, 1)

    -- launch strip (bottom, slightly brighter)
    local strip = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    strip:SetPoint("BOTTOMLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", parent, "BOTTOMLEFT", W, FLOOR)
    strip:SetColorTexture(0.08, 0.08, 0.13, 1)

    -- floor line (a ball falling back / a brick pushed to this line = game over)
    local floorLine = parent:CreateTexture(nil, "BORDER")
    floorLine:SetPoint("BOTTOMLEFT", 0, FLOOR - 1)
    floorLine:SetPoint("TOPRIGHT", parent, "BOTTOMLEFT", W, FLOOR)
    floorLine:SetColorTexture(0.75, 0.3, 0.3, 0.35)

    -- left / right / top thin walls (visual hint for the bounce boundaries)
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
