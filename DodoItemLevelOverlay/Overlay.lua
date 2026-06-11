-- DodoItemLevelOverlay - Overlay.lua
-- FontString management on item buttons. Each button gets up to
-- three overlay texts, created lazily and reused across refreshes:
--   top-left:     item level (gradient colored)
--   bottom-left:  tag (BOE or equipment set name)
--   top-right:    slot label

local _, ns = ...

local function EnsureText(button, key, justifyH)
    local fs = button[key]
    if fs then return fs end

    fs = button:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    fs:SetJustifyH(justifyH)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:Hide()

    button[key] = fs
    return fs
end

local function ApplyText(fs, text, size, flags, r, g, b, a, point, x, y)
    fs:SetFont(STANDARD_TEXT_FONT, size, flags)
    fs:ClearAllPoints()
    fs:SetPoint(point, fs:GetParent(), point, x, y)
    fs:SetTextColor(r, g, b, a)
    fs:SetText(text)
    fs:Show()
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

    -- keep long set names on a single clipped line
    local w = (button.GetWidth and button:GetWidth()) or 0
    if type(w) == "number" and w > 4 then
        fs:SetWidth(w - 2)
    end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetMaxLines then fs:SetMaxLines(1) end

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

-- Slot label text. Pass nil to hide.
function ns.SetSlotText(button, text)
    if not button then return end
    if type(text) ~= "string" or text == "" then
        if button.DodoSlotText then button.DodoSlotText:Hide() end
        return
    end

    local cfg = ns.Config
    local fs = EnsureText(button, "DodoSlotText", "RIGHT")
    local c = cfg.SLOT_COLOR
    ApplyText(fs, text, cfg.SLOT_FONT_SIZE, cfg.SLOT_FONT_FLAGS,
        c[1], c[2], c[3], c[4], cfg.SLOT_POINT, cfg.SLOT_X, cfg.SLOT_Y)
end

-- Hide all three overlays at once.
function ns.ClearAllOverlays(button)
    if not button then return end
    if button.DodoIlvlText then button.DodoIlvlText:Hide() end
    if button.DodoTagText then button.DodoTagText:Hide() end
    if button.DodoSlotText then button.DodoSlotText:Hide() end
end
