-- DodoInspect - Overlay.lua
-- FontString management on item buttons. Each button gets up to
-- four overlay texts, created lazily and reused across refreshes:
--   top-left:     item level (gear only)
--   top-right:    item type tag (junk / quest / consumable),
--                 shown on everything that is not gear
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
    -- locale-table text: CJK locales ask for a slightly larger size
    local size = cfg.SLOT_FONT_SIZE + ((ns.L and ns.L.sizeBump) or 0)
    ApplyText(fs, text, size, cfg.SLOT_FONT_FLAGS,
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

-- Localized item type tag, top-right aligned and right-justified so
-- it hugs the right edge (the item level holds the opposite top-left
-- corner; the two never show on the same item). Pass nil to hide.
function ns.SetTypeText(button, tagKey)
    if not button then return end
    local text = tagKey and ns.L and ns.L.tags[tagKey]
    if type(text) ~= "string" or text == "" then
        if button.DodoTypeText then button.DodoTypeText:Hide() end
        return
    end

    local cfg = ns.Config
    local fs = EnsureText(button, "DodoTypeText", "RIGHT")
    ClampToButtonWidth(fs, button)
    local c = cfg.TYPE_COLORS[tagKey] or cfg.TYPE_COLORS.cons
    -- locale-table text: CJK locales ask for a slightly larger size
    local size = cfg.TYPE_FONT_SIZE + ((ns.L and ns.L.sizeBump) or 0)
    ApplyText(fs, text, size, cfg.TYPE_FONT_FLAGS,
        c[1], c[2], c[3], c[4], cfg.TYPE_POINT, cfg.TYPE_X, cfg.TYPE_Y)
end

-- Bottom-left enchant tag for a gear slot button (inspect window):
-- green when enchanted, red when an enchantable slot is missing its
-- enchant. state is "ok", "missing", or nil to hide.
function ns.SetEnchantTag(button, state)
    if not button then return end
    if state ~= "ok" and state ~= "missing" then
        if button.DodoEnchTag then button.DodoEnchTag:Hide() end
        return
    end

    local cfg = ns.Config
    local fs = EnsureText(button, "DodoEnchTag", "LEFT")
    local c = (state == "ok") and cfg.ENCHANT_OK_COLOR or cfg.ENCHANT_MISSING_COLOR
    ApplyText(fs, (ns.L and ns.L.enchant) or "EN",
        cfg.ENCH_OVL_FONT_SIZE, cfg.ENCH_OVL_FONT_FLAGS,
        c[1], c[2], c[3], c[4], cfg.ENCH_OVL_POINT, cfg.ENCH_OVL_X, cfg.ENCH_OVL_Y)
end

-- Bottom-right gem icons for a gear slot button, growing left: filled
-- gems (their icons) first, then empty sockets. gems is an array of
-- gem item IDs, emptyCount the empty sockets after them. The pooled
-- textures are reused across refreshes; extras are hidden.
local GEM_CAP = 3 -- a gear slot only has room for a few
function ns.SetGemOverlay(button, gems, emptyCount)
    if not button then return end
    local cfg = ns.Config
    button.DodoGems = button.DodoGems or {}
    local pool = button.DodoGems

    local shown = 0
    local function add(texture)
        if shown >= GEM_CAP then return end
        shown = shown + 1
        local tex = pool[shown]
        if not tex then
            tex = button:CreateTexture(nil, "OVERLAY")
            pool[shown] = tex
        end
        tex:SetSize(cfg.GEM_OVL_SIZE, cfg.GEM_OVL_SIZE)
        tex:ClearAllPoints()
        tex:SetPoint(cfg.GEM_OVL_POINT, button, cfg.GEM_OVL_POINT,
            cfg.GEM_OVL_X - (shown - 1) * cfg.GEM_OVL_STEP, cfg.GEM_OVL_Y)
        tex:SetTexture(texture)
        tex:Show()
    end

    for _, gemID in ipairs(gems or {}) do
        local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(gemID)
        add(icon or ns.EMPTY_SOCKET_TEXTURE)
    end
    for _ = 1, (emptyCount or 0) do
        add(ns.EMPTY_SOCKET_TEXTURE)
    end

    for i = shown + 1, #pool do pool[i]:Hide() end
end

-- Apply the enchant tag (bottom-left) and gem icons (bottom-right) to a
-- gear button from its item link and inventory slot; pass link=nil to
-- clear both. Shared by the character frame (Equipment.lua) and the
-- inspect window (Inspect.lua). The caller passes a safe link (nil when
-- secret); the player's own gear is never secret.
function ns.SetEnchantAndGems(button, slotID, link)
    if not link then
        ns.SetEnchantTag(button, nil)
        ns.SetGemOverlay(button, nil, 0)
        return
    end
    local enchantID, gems = ns.ParseItemLink(link)
    local enchState
    if ns.IsEnchantableSlot(slotID, link) then
        local on = enchantID and enchantID ~= "" and enchantID ~= "0"
        enchState = on and "ok" or "missing"
    end
    ns.SetEnchantTag(button, enchState)
    local stats = ns.GetStatsTable(link)
    ns.SetGemOverlay(button, gems,
        math.max(0, ns.CountTemplateSockets(stats) - #gems))
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
