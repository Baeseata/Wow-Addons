-- DodoInspect - Overlay.lua
-- FontString management on item buttons. Each button gets up to
-- four overlay texts, created lazily and reused across refreshes:
--   top-left:     item level on gear, OR the item type tag
--                 (junk / quest / consumable) on everything else
--   center:       slot label
--   bottom-left:  tag (BOE or equipment set name)

local _, ns = ...

local function EnsureText(button, key, justifyH)
    local fs = button[key]
    if fs then
        fs:SetJustifyH(justifyH)
        return fs
    end

    fs = button:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    fs:SetJustifyH(justifyH)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:Hide()

    button[key] = fs
    return fs
end

-- Apply the active locale font (e.g. a CJK font for Chinese) with a
-- fallback to the client default when the override fails to load.
-- Shared with the character side panel.
function ns.SetOverlayFont(fs, size, flags)
    local font = (ns.L and ns.L.font) or STANDARD_TEXT_FONT
    if not fs:SetFont(font, size, flags) then
        fs:SetFont(STANDARD_TEXT_FONT, size, flags)
    end
end

-- The engine can only draw black outlines, so the white rim is four
-- white copies of the text offset by one pixel each way; their own
-- black outlines and shadows provide the dark edge and the drop
-- shadow, and the colored original renders on top of them.
local RIM_OFFSETS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function EnsureRim(fs)
    if fs.DodoRim then return fs.DodoRim end
    local rim = {}
    for i = 1, #RIM_OFFSETS do
        local copy = fs:GetParent():CreateFontString(nil, "OVERLAY")
        copy:SetDrawLayer("OVERLAY", 1)
        copy:SetTextColor(1, 1, 1, 1)
        copy:SetShadowOffset(1, -1)
        copy:SetShadowColor(0, 0, 0, 1)
        copy:Hide()
        rim[i] = copy
    end
    fs:SetDrawLayer("OVERLAY", 2)
    fs.DodoRim = rim
    return rim
end

local function HideOverlay(fs)
    if not fs then return end
    fs:Hide()
    if fs.DodoRim then
        for _, copy in ipairs(fs.DodoRim) do copy:Hide() end
    end
end

local function ApplyText(fs, text, size, flags, r, g, b, a, point, x, y)
    local parent = fs:GetParent()
    local white = ns.Config.WHITE_OUTLINE

    -- in white rim mode the copies supply outline and shadow, the
    -- original is pure colored fill
    ns.SetOverlayFont(fs, size, white and "" or flags)
    fs:SetShadowOffset(white and 0 or 1, white and 0 or -1)
    fs:ClearAllPoints()
    fs:SetPoint(point, parent, point, x, y)
    fs:SetTextColor(r, g, b, a)
    fs:SetText(text)
    fs:Show()

    if white then
        local rim = EnsureRim(fs)
        for i, off in ipairs(RIM_OFFSETS) do
            local copy = rim[i]
            ns.SetOverlayFont(copy, size, "OUTLINE")
            copy:SetJustifyH(fs:GetJustifyH())
            copy:ClearAllPoints()
            copy:SetPoint(point, parent, point, x + off[1], y + off[2])
            if fs.DodoClampW then
                copy:SetWidth(fs.DodoClampW)
                if copy.SetWordWrap then copy:SetWordWrap(false) end
                if copy.SetMaxLines then copy:SetMaxLines(1) end
            end
            copy:SetText(text)
            copy:Show()
        end
    elseif fs.DodoRim then
        for _, copy in ipairs(fs.DodoRim) do copy:Hide() end
    end
end

-- Constrain a font string to the button width so long texts clip on
-- a single line instead of spilling over the neighbor buttons.
local function ClampToButtonWidth(fs, button)
    local w = (button.GetWidth and button:GetWidth()) or 0
    if type(w) == "number" and w > 4 then
        fs:SetWidth(w - 2)
        fs.DodoClampW = w - 2
    end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetMaxLines then fs:SetMaxLines(1) end
end

-- Item level text, colored by the gradient. Pass nil to hide.
function ns.SetItemLevelText(button, ilvl)
    if not button then return end
    if not ilvl or ilvl <= 0 then
        HideOverlay(button.DodoIlvlText)
        return
    end

    local cfg = ns.Config
    local fs = EnsureText(button, "DodoIlvlText", "LEFT")
    local r, g, b, a = ns.ColorForItemLevel(ilvl)
    ApplyText(fs, tostring(ilvl), cfg.ILVL_FONT_SIZE, cfg.ILVL_FONT_FLAGS,
        r, g, b, a, cfg.ILVL_POINT, cfg.ILVL_X, cfg.ILVL_Y)
end

-- Centered slot label. Pass nil to hide.
function ns.SetSlotText(button, text)
    if not button then return end
    if type(text) ~= "string" or text == "" then
        HideOverlay(button.DodoSlotText)
        return
    end

    local cfg = ns.Config
    local fs = EnsureText(button, "DodoSlotText", "CENTER")
    local c = cfg.SLOT_COLOR
    ApplyText(fs, text, cfg.SLOT_FONT_SIZE, cfg.SLOT_FONT_FLAGS,
        c[1], c[2], c[3], c[4], cfg.SLOT_POINT, cfg.SLOT_X, cfg.SLOT_Y)
end

-- Bottom-left tag. kind is "boe" or "set" (text required for "set").
-- Pass nil kind to hide.
function ns.SetTagText(button, kind, text)
    if not button then return end
    if kind ~= "boe" and not (kind == "set" and type(text) == "string" and text ~= "") then
        HideOverlay(button.DodoTagText)
        return
    end

    local cfg = ns.Config
    local fs = EnsureText(button, "DodoTagText", "LEFT")
    ClampToButtonWidth(fs, button)

    if kind == "boe" then
        local c = cfg.BOE_COLOR
        ApplyText(fs, cfg.BOE_TEXT, cfg.BOE_FONT_SIZE, cfg.BOE_FONT_FLAGS,
            c[1], c[2], c[3], c[4], cfg.BOE_POINT, cfg.BOE_X, cfg.BOE_Y)
    else
        local c = cfg.SET_COLOR
        ApplyText(fs, text, cfg.SET_FONT_SIZE, cfg.SET_FONT_FLAGS,
            c[1], c[2], c[3], c[4], cfg.SET_POINT, cfg.SET_X, cfg.SET_Y)
    end
end

-- Localized item type tag, top-left aligned (it takes the spot the
-- item level uses on real gear; the two never show together).
-- Pass nil to hide.
function ns.SetTypeText(button, tagKey)
    if not button then return end
    local text = tagKey and ns.L and ns.L.tags[tagKey]
    if type(text) ~= "string" or text == "" then
        HideOverlay(button.DodoTypeText)
        return
    end

    local cfg = ns.Config
    local fs = EnsureText(button, "DodoTypeText", "LEFT")
    ClampToButtonWidth(fs, button)
    local c = cfg.TYPE_COLORS[tagKey] or cfg.TYPE_COLORS.cons
    ApplyText(fs, text, cfg.TYPE_FONT_SIZE, cfg.TYPE_FONT_FLAGS,
        c[1], c[2], c[3], c[4], cfg.TYPE_POINT, cfg.TYPE_X, cfg.TYPE_Y)
end

-- Hide every overlay this addon owns on a button.
function ns.ClearAllOverlays(button)
    if not button then return end
    HideOverlay(button.DodoIlvlText)
    HideOverlay(button.DodoSlotText)
    HideOverlay(button.DodoTagText)
    HideOverlay(button.DodoTypeText)
end

-- Hide just the gear overlays (item level, slot label, BOE/set tag),
-- leaving the type tag alone.
function ns.ClearGearOverlays(button)
    if not button then return end
    HideOverlay(button.DodoIlvlText)
    HideOverlay(button.DodoSlotText)
    HideOverlay(button.DodoTagText)
end
