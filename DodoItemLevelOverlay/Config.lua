-- DodoItemLevelOverlay - Config.lua
-- All user-tweakable settings live here. Edit, save, then /reload in game.

local _, ns = ...

ns.Config = {

    ------------------------------------------------------------------
    -- Item level color gradient window
    ------------------------------------------------------------------
    -- Item levels are mapped onto a Raider.IO style score color ramp
    -- (see Gradient.lua). Anything at or below MIN renders white,
    -- anything at or above MAX renders legendary orange, everything
    -- in between blends smoothly through green, blue, purple and
    -- pink. Tune these two numbers once per season.
    GRADIENT_MIN_ILVL = 205,
    GRADIENT_MAX_ILVL = 270,

    ------------------------------------------------------------------
    -- Junk filter
    ------------------------------------------------------------------
    -- When true, equippable items of Poor (gray) or Common (white)
    -- quality get no overlays at all: no item level, no BOE tag, no
    -- slot label. A bare icon reads as "safe to vendor".
    HIDE_JUNK_QUALITY = true,

    ------------------------------------------------------------------
    -- Item level text (top-left corner; bags and character frame)
    ------------------------------------------------------------------
    ILVL_FONT_SIZE  = 12,
    ILVL_FONT_FLAGS = "OUTLINE",
    ILVL_POINT      = "TOPLEFT",
    ILVL_X          = 1,
    ILVL_Y          = -1,

    ------------------------------------------------------------------
    -- BOE tag (bottom-left corner; bags only)
    ------------------------------------------------------------------
    BOE_TEXT       = "BOE",
    BOE_FONT_SIZE  = 14,
    BOE_FONT_FLAGS = "OUTLINE",
    BOE_COLOR      = { 0.30, 1.00, 0.30, 1 },
    BOE_POINT      = "BOTTOMLEFT",
    BOE_X          = 1,
    BOE_Y          = 1,

    ------------------------------------------------------------------
    -- Equipment set name tag (bottom-left corner; bags only)
    ------------------------------------------------------------------
    SET_FONT_SIZE  = 14,
    SET_FONT_FLAGS = "OUTLINE",
    SET_COLOR      = { 1.00, 0.82, 0.00, 1 },
    SET_POINT      = "BOTTOMLEFT",
    SET_X          = 1,
    SET_Y          = 1,

    ------------------------------------------------------------------
    -- Slot label (top-right corner; bags only)
    ------------------------------------------------------------------
    SLOT_FONT_SIZE  = 14,
    SLOT_FONT_FLAGS = "OUTLINE",
    SLOT_COLOR      = { 0.20, 1.00, 0.20, 1 },
    SLOT_POINT      = "TOPRIGHT",
    SLOT_X          = -1,
    SLOT_Y          = -1,
}
