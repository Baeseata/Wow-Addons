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
    -- Midnight 12.1 Season 2 raises rewards by 46 item levels. Keep
    -- the 12.0 color semantics by shifting the whole window by 46:
    -- Season 2 starts at 266 (Adventurer 1), regular Myth tops at 334
    -- (Myth 6) and the track's real ceiling is 344 (Myth 9).
    --
    -- Read out of the client data 2026-08-14, not from a guide: the Myth
    -- ladder for this season is 318/321/324/328/331/334/337/340/344
    -- (bonus list group 618). Re-derive with the recipe in CLAUDE.md,
    -- "12.1 upgrade tracks" -- it is a table lookup, not a measurement.
    --
    -- An earlier version of this comment claimed Ascendant Venomstones
    -- reach 341. There is no item level 341 anywhere in the 12.1 data,
    -- and the "Venomcursed" bonus grants an effect, no item level at
    -- all. It came from the same pre-season set as the crafted number
    -- below. MAX = 344 is the one number here that was measured in game.
    -- Tune the three numbers per season, each moves independently.
    GRADIENT_MIN_ILVL    = 262,
    GRADIENT_ORANGE_ILVL = 326,
    GRADIENT_MAX_ILVL    = 344,

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
    -- Average durability readout (merged into the item-level row)
    ------------------------------------------------------------------
    -- Mean durability across equipped items that have it (armor and
    -- weapons). Blizzard's separate item level number is hidden and
    -- replaced by one centered line on the same row, "286.1 | 88%", so
    -- the item level and the durability share a single size. The item
    -- level is gold; the durability percent is colored red (low) ->
    -- yellow -> green (full). The line auto-shrinks (down to
    -- _MIN_FONT_SIZE) only if it would ever exceed the row width.
    DURABILITY_FONT_SIZE      = 16,
    DURABILITY_MIN_FONT_SIZE  = 9,
    DURABILITY_FONT_FLAGS     = "OUTLINE",
    DURABILITY_MAX_WIDTH      = 110, -- fallback width if the row can't be measured
    DURABILITY_X              = 0,   -- horizontal nudge from center
    DURABILITY_Y              = 0,   -- vertical nudge
    -- Separator between the item level and the durability percent. Kept
    -- as a byte-escape so this file stays ASCII-only (raw non-ASCII lives
    -- only in Locales.lua). Current = U+FF5C fullwidth vertical, which is
    -- centered, unlike a plain "|" pipe which renders low. Other options:
    -- U+2502 light "\226\148\130", U+2503 heavy "\226\148\131",
    -- U+2016 double "\226\128\150".
    DURABILITY_SEPARATOR      = "\239\189\156",

    ------------------------------------------------------------------
    -- Secondary stat ratings (extra column in the stats pane)
    ------------------------------------------------------------------
    -- Width reserved for the rating column to the right of the
    -- percentage. Raise it if very large ratings touch the percent,
    -- lower it to pull the two columns closer together.
    STAT_RATING_COL_W = 50,

    ------------------------------------------------------------------
    -- Character side panel (gear list right of the character frame)
    ------------------------------------------------------------------
    -- The panel height always matches the character frame. Rows are
    -- packed tight (row height follows the font size) and centered
    -- vertically. All columns are fixed so enchant tags and gems
    -- align across rows; column widths scale with the font size,
    -- and the panel width derives from the column layout.
    PANEL_ENABLED    = true,
    -- Default font size for both gear panels (character side panel and
    -- inspect side panel). Players can override each one independently
    -- under Esc > Options > AddOns > DodoInspect; the override is stored
    -- in SavedVariables and falls back to this default when unset. The
    -- min / max bound the option sliders.
    PANEL_FONT_SIZE  = 18,
    PANEL_FONT_MIN   = 8,
    PANEL_FONT_MAX   = 36,
    -- Width of the item name column; names longer than this clip
    -- (the mouseover tooltip always has the full name).
    PANEL_NAME_WIDTH = 150,

    -- Global renderer / option gate. Data freshness is enforced per spec
    -- in Data/StatPriority.lua: only entries marked current=true resolve,
    -- so current specs can ship independently; provisional rows label
    -- disagreements explicitly instead of exposing stale Season 1 data.
    STAT_PRIORITY_FEATURE_ENABLED = true,

    -- Loot source and gear panel. Data/Loot.lua carries a build and date
    -- stamp; both features are opt-in because the data is season-scoped.
    LOOT_FEATURE_ENABLED = true,
    LOOT_SOURCE_COLOR = { 0.25, 0.85, 0.85, 1 }, -- matches the slot column
    GEAR_EFFECT_COLOR = { 1.00, 0.70, 0.20, 1 }, -- on-item effect marker
    GEAR_MUTED_COLOR  = { 0.55, 0.55, 0.55, 1 }, -- unrankable rows
    GEAR_ILVL_COLOR      = { 0.80, 0.80, 0.85, 1 },
    -- The two ceiling numbers (334 / 344) that used to live here went away
    -- with the gear panel's item level column, 2026-08-14. Nothing read
    -- them once the tooltip started rendering from bonus ids, and a config
    -- value nobody reads gets maintained forever by whoever assumes it is
    -- live. The numbers themselves are recorded with the ids below --
    -- which is also where they have to be kept in sync anyway.
    -- Bonus ids for this season's Myth upgrade track (group 618). Used to
    -- render tooltips at the level a piece actually reaches instead of its
    -- base form. Measured in game 2026-08-14 on item 250243:
    --   12854 -> ilvl 334, quality 4  (sequence 6 = Myth 6/6)
    --   13848 -> ilvl 344, quality 4  (sequence 9 = Myth 9/6)
    -- SEASONAL, like the two numbers above -- and these have to be looked
    -- up rather than guessed: the 9/6 id does NOT continue the numbering
    -- of the first eight (12849-12856), it was added mid-season.
    -- To re-derive: print an equipped item's link, take its bonus id, find
    -- it in ItemBonusListGroupEntry on wago.tools to get the group, then
    -- read that group's SequenceValue rows.
    GEAR_MYTH_BONUS_ID = 12854,
    GEAR_TOP_BONUS_ID  = 13848,
    -- Ceiling for gear that DROPS INSIDE a Mythic+ dungeon: Hero 3 of 6,
    -- bonus list 12843, item level 311. Used by the Mythic+ loot panel,
    -- which lists only dungeon drops -- so it must NOT reuse the two ids
    -- above. Those are the Myth track, which is raid gear; rendering a
    -- dungeon drop at 334 would overstate every row in that panel by an
    -- upgrade tier and a half.
    --
    -- Provenance, stated apart because these are not equally strong:
    --   MEASURED in game: 12841 -> 305, which is sequence 1 of the same
    --     group 617 that 12843 sits in at sequence 3.
    --   MEASURED in game 2026-08-22 on HOME: 12843 renders item 250243 at
    --     ilvl 311, quality 4. The three derivations below predicted it and
    --     are kept because re-deriving is how the next season starts, not
    --     because the number still needs them.
    --   DERIVED (2026-08-22, three independent routes, before the measurement):
    --     a. ItemBonus(12843) Type=49 -> ItemScalingConfig 316 -> 311.
    --        The same chain reproduces all five in-game measurements on
    --        record (285/292/305/334/344) exactly, and reading Value_0
    --        as the item level directly fails all five -- so the chain
    --        discriminates rather than agreeing with anything.
    --     b. Group 617's ladder is 305 308 311 315 318 321 324 328,
    --        anchored on the measured 305 at sequence 1.
    --     c. MythicPlusSeasonRewardLevels, season 120 tier 256 (the M+
    --        tier) walks 305 305 308 308 311 315 315 315 318 for keys
    --        +2..+10, i.e. 311 is a level this season really hands out.
    -- Kept as a rule even though this one is now measured: three
    -- derivations agreeing is not a measurement, and this project has
    -- been burned by exactly that before. Next season, re-derive AND
    -- re-measure -- the recipe is in CLAUDE.md ("tooltip rendered at
    -- 6/6 / 9/6"), one /run.
    --
    -- "3 of 6" is settled, and not by counting rows: group 617 has eight
    -- entries, but only five carry an ItemExtendedCostID -- five paid
    -- upgrade steps, so six ranks -- and the last two are zero-cost
    -- overflow. All five of this season's tracks have that same 5-paid
    -- shape, including 618, whose 337/340/344 are likewise unbuyable
    -- (they drop, they are not upgraded to). Counting rows instead gives
    -- "3/8" and "Myth 6/9", both wrong.
    --
    -- Still open, and the same /run answers it: whether the tooltip
    -- actually names the track "Hero". No DB2 table carries a track
    -- name at all -- "Hero" is read off the track's position in the
    -- chain, so it is a label, not a string we found.
    --
    -- SEASONAL, like the two above: re-derive all three together.
    GEAR_HERO_BONUS_ID = 12843,
    -- Ceiling for max-quality crafted gear, shown on the wrist and back
    -- rows. Wrist and back cannot be pushed further: Ascendant Venomstones
    -- only apply to weapons, trinkets and necklaces. (^ Unverified, and
    -- from the same source set as the number below -- the client data has
    -- no "Venomstone" in it at all, only a "Venomcursed" bonus that grants
    -- an effect and no item level.)
    --
    -- Owner's call 2026-08-14: use 331, knowing it was never verified --
    -- every source quoting 331 also quoted the Myth ceiling as 337, and
    -- 344 was observed in game the same day.
    --
    -- Dug into the client data 2026-08-14, and the number looks worse
    -- than "unverified":
    --   * Exactly ONE bonus list in the whole build sets an absolute
    --     item level of 331: 12853, which is Myth 5 of 9. No upgrade
    --     track ends at 331.
    --   * 337 is Myth 7 of 9. So those sources were reading real ladder
    --     values off the wrong rank, not inventing numbers.
    --   * Crafted gear is not on an upgrade track at all this season:
    --     zero bonus tree nodes with the TradeSkill item context (13)
    --     reach groups 607/614-618. They reach crafting-QUALITY groups
    --     instead (591 = +0/+3/+6/+9/+13 item levels over the base).
    -- SCOPE, so nobody over-reads this: the search covered the two
    -- mechanisms the tracks use to SET an item level. Item levels can
    -- also be reached as a delta off a base item (ItemBonus type 1),
    -- which cannot be resolved without naming the base item -- so this
    -- is "the data does not support 331", not "331 is impossible".
    -- What the real crafted ceiling is, the data did not say either.
    --
    -- Owner reviewed all of the above 2026-08-14 and kept 331 anyway.
    -- Recording that as a decision, not an oversight: do not "fix" this
    -- to nil on the strength of the comment above, it has been read.
    -- (nil IS supported here -- the panel then prints the note with no
    -- figure -- so switching costs one word if he ever changes his mind.)
    GEAR_CRAFTED_ITEM_LEVEL = 331,

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
