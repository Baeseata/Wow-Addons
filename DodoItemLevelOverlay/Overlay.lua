-- DodoItemLevelOverlay - Overlay.lua
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

local function ApplyText(fs, text, size, flags, r, g, b, a, point, x, y)
    ns.SetOverlayFont(fs, size, flags)
    fs:ClearAllPoints()
    fs:SetPoint(point, fs:GetParent(), point, x, y)
    fs:SetTextColor(r, g, b, a)
    fs:SetText(text)
    fs:Show()
end

-- Constrain a font string to the button width so long texts clip on
-- a single line instead of spilling over the neighbor buttons.
local function ClampToButtonWidth(fs, button)
    local w = (button.GetWidth and button:GetWidth()) or 0
    if type(w) == "number" and w > 4 then
        fs:SetWidth(w - 2)
    end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetMaxLines then fs:SetMaxLines(1) end
end

-- Item level text, colored by the gradient. Pass nil to hide.
function ns.SetItemLevelText(button, ilvl)
    if not button then return end
    if not ilvl or ilvl <= 0 then
        if button.DodoIlvlText then button.DodoIlvlText:Hide() end
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
        if button.DodoSlotText then button.DodoSlotText:Hide() end
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
        if button.DodoTagText then button.DodoTagText:Hide() end
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
        if button.DodoTypeText then button.DodoTypeText:Hide() end
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
    if button.DodoIlvlText then button.DodoIlvlText:Hide() end
    if button.DodoSlotText then button.DodoSlotText:Hide() end
    if button.DodoTagText then button.DodoTagText:Hide() end
    if button.DodoTypeText then button.DodoTypeText:Hide() end
end

-- Hide just the gear overlays (item level, slot label, BOE/set tag),
-- leaving the type tag alone.
function ns.ClearGearOverlays(button)
    if not button then return end
    if button.DodoIlvlText then button.DodoIlvlText:Hide() end
    if button.DodoSlotText then button.DodoSlotText:Hide() end
    if button.DodoTagText then button.DodoTagText:Hide() end
end
