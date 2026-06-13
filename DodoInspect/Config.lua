-- DodoInspect - Config.lua
-- All user-tweakable settings live here. Edit, save, then /reload in
-- game. The language is not set here: use the dropdown under
-- Esc > Options > AddOns > DodoInspect, or /dins <en|cn|fr|es>.

local _, ns = ...

ns.Config = {

    ------------------------------------------------------------------
    -- Item level color gradient window
    ------------------------------------------------------------------
    -- Item levels are mapped onto a Raider.IO style score color ramp
    -- (see Gradient.lua) pinned by three thresholds:
    --   MIN     at or below renders white
    --   ORANGE  this item level is exactly legendary orange; the
    --           cool body (green, blue, purple, pink) runs between
    --           MIN and here
    --   MAX     the season ceiling, hot red; between ORANGE and MAX
    --           the ramp climbs through amber and gold
    -- Tune the three numbers per season, each moves independently.
    GRADIENT_MIN_ILVL    = 216,
    GRADIENT_ORANGE_ILVL = 280,
    GRADIENT_MAX_ILVL    = 298,

    ------------------------------------------------------------------
    -- Junk filter
    ------------------------------------------------------------------
    -- When true, equippable items of Poor (gray) or Common (white)
    -- quality lose their gear overlays (item level, BOE, slot label)
    -- and get the junk type tag in the top-right corner instead.
    -- Poor quality items are always tagged as junk regardless.
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
    -- Slot label (dead center of the icon; bags only)
    ------------------------------------------------------------------
    SLOT_FONT_SIZE  = 11,
    SLOT_FONT_FLAGS = "OUTLINE",
    SLOT_COLOR      = { 0.20, 1.00, 0.20, 1 },
    SLOT_POINT      = "CENTER",
    SLOT_X          = 0,
    SLOT_Y          = -1,

    ------------------------------------------------------------------
    -- BOE tag (bottom-left corner; bags only)
    ------------------------------------------------------------------
    -- Same font size as the slot label so the center and bottom
    -- rows split the space below the item level without overlap.
    BOE_TEXT       = "BOE",
    BOE_FONT_SIZE  = 11,
    BOE_FONT_FLAGS = "OUTLINE",
    BOE_COLOR      = { 0.30, 1.00, 0.30, 1 },
    BOE_POINT      = "BOTTOMLEFT",
    BOE_X          = 1,
    BOE_Y          = 1,

    ------------------------------------------------------------------
    -- Equipment set name tag (bottom-left corner; bags only)
    ------------------------------------------------------------------
    SET_FONT_SIZE  = 11,
    SET_FONT_FLAGS = "OUTLINE",
    SET_COLOR      = { 1.00, 0.82, 0.00, 1 },
    SET_POINT      = "BOTTOMLEFT",
    SET_X          = 1,
    SET_Y          = 1,

    ------------------------------------------------------------------
    -- Item type tag (top-right corner; bags only)
    ------------------------------------------------------------------
    -- Localized tag for vendor junk, quest items and consumables
    -- (food, flask, potion, generic consumable). Top-right corner,
    -- opposite the item level's top-left: gear shows an item level,
    -- other items show a type tag, never both. Right-justified (see
    -- Overlay.lua) so the tag hugs the right edge, clear of the
    -- bottom-right stack count number.
    TYPE_FONT_SIZE  = 11,
    TYPE_FONT_FLAGS = "OUTLINE",
    TYPE_POINT      = "TOPRIGHT",
    TYPE_X          = -1,
    TYPE_Y          = -1,

    TYPE_COLORS = {
        junk   = { 0.62, 0.62, 0.62, 1 }, -- gray
        quest  = { 1.00, 0.82, 0.00, 1 }, -- gold
        food   = { 1.00, 0.65, 0.25, 1 }, -- warm orange (cooking)
        flask  = { 0.30, 0.90, 0.90, 1 }, -- teal (phials)
        potion = { 1.00, 0.40, 0.40, 1 }, -- red (potion bottle)
        cons   = { 0.60, 0.80, 1.00, 1 }, -- light blue (misc)
    },

    ------------------------------------------------------------------
    -- Inspect gear overlays (on the inspect window equipment slots)
    ------------------------------------------------------------------
    -- The item level reuses the top-left ILVL_* settings above; the
    -- enchant tag sits bottom-left (green when enchanted, red when an
    -- enchantable slot is empty, same colors as the side panel) and
    -- the gem icons sit bottom-right, growing left.
    ENCH_OVL_FONT_SIZE  = 13,
    ENCH_OVL_FONT_FLAGS = "OUTLINE",
    ENCH_OVL_POINT      = "BOTTOMLEFT",
    ENCH_OVL_X          = 1,
    ENCH_OVL_Y          = 1,
    GEM_OVL_SIZE        = 12,
    GEM_OVL_POINT       = "BOTTOMRIGHT",
    GEM_OVL_X           = -1,
    GEM_OVL_Y           = 1,
    GEM_OVL_STEP        = 13, -- spacing between gem icons (grows left)

    ------------------------------------------------------------------
    -- Character side panel (gear list right of the character frame)
    ------------------------------------------------------------------
    -- The panel height always matches the character frame. Rows are
    -- packed tight (row height follows the font size) and centered
    -- vertically. All columns are fixed so enchant tags and gems
    -- align across rows; column widths scale with the font size,
    -- and the panel width derives from the column layout.
    PANEL_ENABLED    = true,
    PANEL_FONT_SIZE  = 18,
    -- Width of the item name column; names longer than this clip
    -- (the mouseover tooltip always has the full name).
    PANEL_NAME_WIDTH = 150,

    -- secondary stat grid colors (fixed column order: vers, haste,
    -- mastery, crit)
    STAT_COLORS = {
        versatility = { 0.35, 0.65, 1.00, 1 }, -- blue
        haste       = { 1.00, 0.85, 0.25, 1 }, -- yellow
        mastery     = { 0.35, 0.95, 0.45, 1 }, -- green
        crit        = { 1.00, 0.45, 0.35, 1 }, -- red-ish
    },

    ENCHANT_OK_COLOR      = { 0.30, 1.00, 0.30, 1 }, -- enchant present
    ENCHANT_MISSING_COLOR = { 1.00, 0.25, 0.25, 1 }, -- enchantable but empty

    -- Tertiary stat tags (speed / leech / avoidance), shown right
    -- before the enchant tag at the panel font size.
    TERT_COLORS = {
        speed     = { 0.45, 0.95, 0.95, 1 }, -- cyan (movement speed)
        leech     = { 1.00, 0.50, 0.80, 1 }, -- pink (life steal)
        avoidance = { 0.80, 0.70, 1.00, 1 }, -- lavender (aoe damage reduction)
    },

    ------------------------------------------------------------------
    -- Target info (one line above the default target frame)
    ------------------------------------------------------------------
    -- Item level, race, class, spec and hero talent of the targeted
    -- player. The offset is relative to the top of the target frame.
    TARGET_FONT_SIZE = 20,
    TARGET_OFFSET_X  = 0,
    TARGET_OFFSET_Y  = -16,
    -- Wrap the line between words once it would render wider than
    -- this, onto up to 3 lines (long locales: German, French,
    -- Russian...). A break never lands inside a race / spec / talent
    -- name. Compact locales (CJK) never reach the cap and keep one line.
    TARGET_MAX_WIDTH = 420,

    ------------------------------------------------------------------
    -- Season data: which slots take enchants and sockets
    ------------------------------------------------------------------
    -- Midnight (12.0) season 1, verified 2026-06-11:
    --   enchants on helm, shoulder, chest, boots, both rings and
    --   weapons (cloak and bracer enchants were removed this
    --   expansion); legs keep their spellthread / armor kit, which
    --   occupies the same enhancement slot, so they count too.
    --   Death Knight runeforges fill the weapon enchant slot and are
    --   detected the same way.
    -- Update these tables when a new season or expansion changes the
    -- rules. Inventory slot IDs: 1 head, 3 shoulder, 5 chest,
    -- 6 waist, 7 legs, 8 feet, 9 wrist, 11/12 rings, 16/17 weapons.
    ENCHANTABLE_SLOTS = {
        [1]  = true, -- head
        [3]  = true, -- shoulder
        [5]  = true, -- chest
        [7]  = true, -- legs (spellthread / armor kit)
        [8]  = true, -- feet
        [11] = true, -- ring 1
        [12] = true, -- ring 2
        [16] = true, -- main hand
        -- off hand (17) is handled in code: weapons yes,
        -- shields and held-in-off-hand items no
    },
}
