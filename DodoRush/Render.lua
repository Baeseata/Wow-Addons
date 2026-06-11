-- DodoRush - Render
-- Road / units / count pills / gate panels / effect parts. Everything is positioned
-- relative to the host frame's bottom-left corner (track coordinates map straight to pixel offsets).
-- A unit = circle-masked solid disc (body) + small glint; blue = friendly, red = enemy.
-- Phase-2 "face swap" hook: stack a circle-masked portrait texture (class icon / monster
-- head) on top of the body without touching any logic.

local DR = _G.DodoRush or {}
_G.DodoRush = DR

local Render = {}
DR.Render = Render

local geo = DR.geo

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Apply a circular mask to a texture (same as DodoPool; the texture MUST be
-- SetPoint-anchored or it will not render)
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

function Render.PlaceAt(parent, fr, x, y)
    fr:ClearAllPoints()
    fr:SetPoint("CENTER", parent, "BOTTOMLEFT", x, y)
end

-- Hot-path move (units / enemy packs / dashes, hundreds of calls per frame):
-- re-setting the same CENTER anchor replaces it in place, skipping ClearAllPoints.
-- Only safe on frames that have never used any anchor other than CENTER.
function Render.MoveAt(parent, fr, x, y)
    fr:SetPoint("CENTER", parent, "BOTTOMLEFT", x, y)
end

-- ------------------------------------------------------------
-- Road: dark asphalt + curbs. The dashed center line scrolls with the road
-- and is managed by Game (NewDash).
-- ------------------------------------------------------------
function Render.BuildRoad(parent)
    if parent._built then return end
    parent._built = true

    -- Clip out-of-bounds: elements spawn above the top edge and slide in,
    -- they must not draw outside the road
    parent:SetClipsChildren(true)

    local W, H, CURB = geo.ROAD_W, geo.ROAD_H, geo.CURB

    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.115, 0.12, 0.15, 1)

    local function curb(x1, x2)
        local t = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
        t:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x1, 0)
        t:SetPoint("TOPRIGHT", parent, "BOTTOMLEFT", x2, H)
        t:SetColorTexture(0.30, 0.32, 0.40, 1)
        local edge = parent:CreateTexture(nil, "BACKGROUND", nil, 2)
        edge:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", (x1 == 0) and (x2 - 1) or x1, 0)
        edge:SetPoint("TOPRIGHT", parent, "BOTTOMLEFT", (x1 == 0) and x2 or (x1 + 1), H)
        edge:SetColorTexture(0.55, 0.58, 0.7, 0.6)
    end
    curb(0, CURB)
    curb(W - CURB, W)
end

-- One dashed-center-line segment (scrolls with the world, recycled by Game)
function Render.NewDash(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(5, 26)
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetColorTexture(0.85, 0.88, 0.95, 0.16)
    return f
end

-- ------------------------------------------------------------
-- Units: kind = "friend" | "foe" | "boss"
-- ------------------------------------------------------------
local UNIT_STYLE = {
    friend = { size = 13, body = { 0.25, 0.58, 1.00 }, glint = { 1, 1, 1, 0.55 } },
    foe    = { size = 13, body = { 0.95, 0.30, 0.27 }, glint = { 1, 0.82, 0.78, 0.45 } },
    boss   = { size = 17, body = { 0.80, 0.10, 0.18 }, glint = { 1, 0.62, 0.55, 0.45 } },
}

function Render.NewUnit(parent, kind)
    local st = UNIT_STYLE[kind] or UNIT_STYLE.friend
    local s = st.size
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(s, s)
    f.body = MakeCircle(f, s, "ARTWORK", st.body[1], st.body[2], st.body[3], 1)
    local gl = f:CreateTexture(nil, "OVERLAY")
    gl:SetSize(s * 0.42, s * 0.42)
    gl:SetPoint("CENTER", f, "CENTER", -s * 0.18, s * 0.2)
    gl:SetColorTexture(st.glint[1], st.glint[2], st.glint[3], st.glint[4])
    ApplyCircleMask(f, gl)
    -- Phase-2 face swap: f.face = circle-masked portrait texture over the body
    -- (class icons / monster heads), see CLAUDE.md
    return f
end

-- ------------------------------------------------------------
-- Count pill (above a crowd): foe=true red bg white text, otherwise white bg dark text
-- ------------------------------------------------------------
function Render.NewPill(parent, foe)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(40, 21)
    f:SetFrameLevel((parent:GetFrameLevel() or 0) + 9)
    local bg = f:CreateTexture(nil, "ARTWORK")
    bg:SetAllPoints()
    if foe then
        bg:SetColorTexture(0.72, 0.10, 0.10, 0.92)
    else
        bg:SetColorTexture(0.96, 0.96, 0.96, 0.94)
    end
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 14, "")
    fs:SetPoint("CENTER", 0, 0)
    if foe then fs:SetTextColor(1, 1, 1, 1) else fs:SetTextColor(0.08, 0.08, 0.12, 1) end
    f.fs = fs

    function f.SetCount(self, n)
        if self._n == n then return end
        self._n = n
        self.fs:SetText(tostring(n))
        self:SetWidth(16 + #tostring(n) * 9)
    end
    return f
end

-- ------------------------------------------------------------
-- Gate panel: translucent fill + border + big label. SetGate styles buff green / debuff red.
-- ------------------------------------------------------------
function Render.NewGatePanel(parent)
    local W, H = geo.GATE_W, geo.GATE_H
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(W, H)
    f:SetFrameLevel((parent:GetFrameLevel() or 0) + 1)

    local fill = f:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints()
    f.fill = fill

    f.borders = {}
    local function edge(i)
        local t = f:CreateTexture(nil, "ARTWORK", nil, 1)
        f.borders[i] = t
        return t
    end
    local top = edge(1);    top:SetPoint("TOPLEFT");      top:SetPoint("TOPRIGHT");      top:SetHeight(2)
    local bot = edge(2);    bot:SetPoint("BOTTOMLEFT");   bot:SetPoint("BOTTOMRIGHT");   bot:SetHeight(2)
    local lef = edge(3);    lef:SetPoint("TOPLEFT");      lef:SetPoint("BOTTOMLEFT");    lef:SetWidth(2)
    local rig = edge(4);    rig:SetPoint("TOPRIGHT");     rig:SetPoint("BOTTOMRIGHT");   rig:SetWidth(2)

    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 28, "OUTLINE")
    fs:SetPoint("CENTER", 0, 0)
    fs:SetTextColor(1, 1, 1, 1)
    f.fs = fs

    function f.SetGate(self, op, v)
        local good = (op == "+" or op == "×")
        local text
        if op == "×" then text = "×" .. v
        elseif op == "÷" then text = "÷" .. v
        elseif op == "+" then text = "+" .. v
        else text = "-" .. v end
        self.fs:SetText(text)
        if good then
            self.fill:SetColorTexture(0.10, 0.55, 0.28, 0.40)
            for _, t in ipairs(self.borders) do t:SetColorTexture(0.35, 1, 0.6, 0.85) end
        else
            self.fill:SetColorTexture(0.62, 0.13, 0.11, 0.40)
            for _, t in ipairs(self.borders) do t:SetColorTexture(1, 0.4, 0.35, 0.85) end
        end
        self:SetAlpha(1)
        return text
    end

    function f.SetDim(self)
        self:SetAlpha(0.30)
    end

    return f
end

-- ------------------------------------------------------------
-- Effect parts (used by Game's effect pool, ADD glow)
-- ------------------------------------------------------------

-- Small smoke / death poof: warm-white glowing disc
function Render.NewPoof(parent, big)
    local D = big and 34 or 16
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(D, D)
    local t = MakeCircle(f, D, "OVERLAY", 1, 0.86, 0.62, big and 0.85 or 0.7)
    t:SetBlendMode("ADD")
    return f
end

-- Gate flash: white ADD rectangle, same size as a gate panel
function Render.NewGateFlash(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(geo.GATE_W, geo.GATE_H)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetColorTexture(1, 1, 1, 0.85)
    t:SetBlendMode("ADD")
    return f
end
