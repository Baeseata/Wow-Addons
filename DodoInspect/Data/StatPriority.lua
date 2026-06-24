-- DodoInspect - Data/StatPriority.lua
-- Per-spec PvE secondary-stat priority for the current season.
-- Keyed by specID (GetSpecializationInfo / GetInspectSpecialization).
--
-- DATA ONLY, ASCII ONLY -- no localized prose here (the renderer pulls
-- the stat labels from ns.L and the full names from the game globals,
-- so all four locales come for free). Update every season.
--
--   raid    : single-target / raid order
--   mythic  : AoE / Mythic+ order (omit when identical to raid; the
--             renderer collapses to a single line when they match)
--   softcap : optional { stat = percent } soft caps, shown in the
--             tooltip via a localized template ("Haste soft cap ~20%")
--
-- An order is an array whose elements are either a stat key
-- ("versatility" / "haste" / "mastery" / "crit" -- the same keys the
-- side panel stat grid uses) or a nested array = a tie group, rendered
-- with "=" instead of ">". The primary stat (Strength / Agility /
-- Intellect) is always best and is intentionally left out, mirroring
-- the secondary-only stat grid below it.
--
-- Sourced from Icy Veins (cross-checked vs Method.gg) for Midnight
-- patch 12.0.7, Season 1, June 2026. Several specs are build- or
-- hero-talent-dependent; where a source splits, the more common /
-- default build is used and noted in a comment. Tank specs use the
-- defensive (survival) ordering as the raid line.

local _, ns = ...

-- Where the orders came from + when, shown on the tooltip's last line.
ns.STAT_PRIORITY_SOURCE = "Icy Veins / Method"
ns.STAT_PRIORITY_DATE   = "2026-06"

ns.StatPriority = {

    ------------------------------------------------------------------
    -- Death Knight
    ------------------------------------------------------------------
    -- Blood: hero-talent dependent. San'layn's stacking-haste buff
    -- makes haste top; Deathbringer's burst favors crit/vers. All
    -- secondaries are close (sim to fine-tune). Default = Deathbringer.
    [250] = { -- Blood (tank)
        raid = { "crit", "versatility", "mastery", "haste" },
        builds = {
            [33] = { raid = { "crit", "versatility", "mastery", "haste" } }, -- Deathbringer
            [31] = { raid = { "haste", "crit", "versatility", "mastery" } }, -- San'layn
        },
    },
    [251] = { -- Frost (dps)
        raid = { "mastery", "crit", "haste", "versatility" },
    },
    [252] = { -- Unholy (dps): Mastery and Crit are a synergistic pair
        raid = { { "mastery", "crit" }, "haste", "versatility" },
    },

    ------------------------------------------------------------------
    -- Demon Hunter
    ------------------------------------------------------------------
    [577] = { -- Havoc (dps)
        raid = { "crit", "mastery", { "haste", "versatility" } },
    },
    [581] = { -- Vengeance (tank)
        raid = { "haste", "versatility", "crit", "mastery" },
    },
    -- Devourer (1480): NEW third DH spec added in 12.0 (Void/Cosmic
    -- ranged caster, Intellect-based), hero-talent dependent. Annihilator
    -- (~99% usage) leans haste in ST and flips to mastery in AoE/M+;
    -- Void-Scarred leads mastery in both. Default = Annihilator.
    [1480] = { -- Devourer (dps)
        raid   = { "haste", "mastery", "crit", "versatility" },
        mythic = { "mastery", "haste", "crit", "versatility" },
        builds = {
            [124] = { -- Annihilator
                raid   = { "haste", "mastery", "crit", "versatility" },
                mythic = { "mastery", "haste", "crit", "versatility" },
            },
            [126] = { -- Void-Scarred
                raid = { "mastery", "haste", "crit", "versatility" },
            },
        },
    },

    ------------------------------------------------------------------
    -- Druid
    ------------------------------------------------------------------
    [102] = { -- Balance (dps): crit/mastery/haste relatively equal
        raid = { { "crit", "mastery", "haste" }, "versatility" },
    },
    [103] = { -- Feral (dps)
        raid = { "mastery", { "haste", "crit" }, "versatility" },
    },
    [104] = { -- Guardian (tank): all four extremely close, treat evenly
        raid = { { "haste", "versatility", "mastery", "crit" } },
    },
    [105] = { -- Restoration (healer)
        raid   = { "haste", "mastery", "versatility", "crit" },
        mythic = { "mastery", "haste", "versatility", "crit" },
    },

    ------------------------------------------------------------------
    -- Evoker
    ------------------------------------------------------------------
    [1467] = { -- Devastation (dps)
        raid = { "haste", "crit", "mastery", "versatility" },
    },
    [1468] = { -- Preservation (healer)
        raid = { "mastery", "crit", "haste", "versatility" },
    },
    [1473] = { -- Augmentation (dps / support)
        raid = { { "crit", "haste" }, "mastery", "versatility" },
    },

    ------------------------------------------------------------------
    -- Hunter
    ------------------------------------------------------------------
    [253] = { -- Beast Mastery (dps)
        raid = { "mastery", "crit", "haste", "versatility" },
    },
    [254] = { -- Marksmanship (dps)
        raid = { { "crit", "mastery" }, { "versatility", "haste" } },
    },
    -- Survival: hero-talent dependent. Mastery leads both; Pack Leader
    -- makes crit and haste interchangeable, Sentinel keeps crit ahead.
    [255] = { -- Survival (dps)
        raid = { "mastery", "crit", "haste", "versatility" },
        builds = {
            [42] = { raid = { "mastery", "crit", "haste", "versatility" } },         -- Sentinel
            [43] = { raid = { "mastery", { "crit", "haste" }, "versatility" } },     -- Pack Leader
        },
    },

    ------------------------------------------------------------------
    -- Mage
    ------------------------------------------------------------------
    [62] = { -- Arcane (dps)
        raid = { "mastery", "versatility", "crit", "haste" },
    },
    [63] = { -- Fire (dps)
        raid = { "haste", "mastery", "versatility", "crit" },
    },
    [64] = { -- Frost (dps)
        raid = { "mastery", "crit", "haste", "versatility" },
    },

    ------------------------------------------------------------------
    -- Monk
    ------------------------------------------------------------------
    [268] = { -- Brewmaster (tank): raid = defensive, M+ = offensive
        raid   = { "crit", "versatility", "mastery", "haste" },
        mythic = { "crit", "mastery", "versatility", "haste" },
    },
    [269] = { -- Windwalker (dps)
        raid = { "haste", "crit", "mastery", "versatility" },
    },
    [270] = { -- Mistweaver (healer)
        raid = { "haste", "crit", "versatility", "mastery" },
    },

    ------------------------------------------------------------------
    -- Paladin
    ------------------------------------------------------------------
    -- Holy: hero-talent dependent. Lightsmith pulls crit ahead of haste
    -- (Hammer and Anvil heals on Judgment crits). Default = Herald of
    -- the Sun (the raid/M+ go-to).
    [65] = { -- Holy (healer)
        raid = { "mastery", "haste", "crit", "versatility" },
        builds = {
            [50] = { raid = { "mastery", "haste", "crit", "versatility" } }, -- Herald of the Sun
            [49] = { raid = { "mastery", "crit", "haste", "versatility" } }, -- Lightsmith
        },
    },
    [66] = { -- Protection (tank): defensive order; ~20% haste for SotR
        raid    = { "haste", "versatility", "mastery", "crit" },
        softcap = { haste = 20 },
    },
    [70] = { -- Retribution (dps)
        raid = { "mastery", "crit", "haste", "versatility" },
    },

    ------------------------------------------------------------------
    -- Priest
    ------------------------------------------------------------------
    [256] = { -- Discipline (healer)
        raid = { "haste", "crit", "mastery", "versatility" },
    },
    [257] = { -- Holy (healer)
        raid   = { "crit", "versatility", "mastery", "haste" },
        mythic = { "crit", "versatility", "haste", "mastery" },
    },
    -- Shadow: hero-talent dependent (IV recommends separate gear sets).
    -- Voidweaver favors haste first (soft cap ~30%); Archon leads mastery.
    [258] = { -- Shadow (dps): default = Voidweaver
        raid    = { "haste", "mastery", "crit", "versatility" },
        softcap = { haste = 30 },
        builds = {
            [18] = { raid = { "haste", "mastery", "crit", "versatility" }, softcap = { haste = 30 } }, -- Voidweaver
            [19] = { raid = { "mastery", "crit", "haste", "versatility" } },                           -- Archon
        },
    },

    ------------------------------------------------------------------
    -- Rogue
    ------------------------------------------------------------------
    [259] = { -- Assassination (dps)
        raid = { "crit", "haste", "mastery", "versatility" },
    },
    [260] = { -- Outlaw (dps): ~20-25% haste reaches the GCD breakpoint
        raid    = { "crit", "haste", "versatility", "mastery" },
        softcap = { haste = 25 },
    },
    [261] = { -- Subtlety (dps)
        raid = { "haste", "mastery", "crit", "versatility" },
    },

    ------------------------------------------------------------------
    -- Shaman
    ------------------------------------------------------------------
    [262] = { -- Elemental (dps): mastery soft cap with Elemental Blast
        raid    = { "mastery", "haste", "crit", "versatility" },
        softcap = { mastery = 86 },
    },
    -- Enhancement: hero-talent dependent. Totemic leads mastery,
    -- Stormbringer leads haste (Maelstrom Weapon cycling); top two swap.
    [263] = { -- Enhancement (dps): default = Totemic
        raid = { "mastery", "haste", "crit", "versatility" },
        builds = {
            [54] = { raid = { "mastery", "haste", "crit", "versatility" } }, -- Totemic
            [55] = { raid = { "haste", "mastery", "crit", "versatility" } }, -- Stormbringer
        },
    },
    [264] = { -- Restoration (healer)
        raid = { "crit", "versatility", "haste", "mastery" },
    },

    ------------------------------------------------------------------
    -- Warlock
    ------------------------------------------------------------------
    [265] = { -- Affliction (dps)
        raid = { "haste", "crit", "mastery", "versatility" },
    },
    [266] = { -- Demonology (dps)
        raid = { "crit", "haste", "mastery", "versatility" },
    },
    [267] = { -- Destruction (dps)
        raid = { "crit", "haste", "mastery", "versatility" },
    },

    ------------------------------------------------------------------
    -- Warrior
    ------------------------------------------------------------------
    [71] = { -- Arms (dps): crit and haste are a near-tie
        raid = { { "crit", "haste" }, "mastery", "versatility" },
    },
    [72] = { -- Fury (dps)
        raid = { "mastery", "haste", "versatility", "crit" },
    },
    [73] = { -- Protection (tank): vers/crit tie in raid; crit ahead in M+
        raid   = { "haste", { "versatility", "crit" }, "mastery" },
        mythic = { "haste", "crit", "versatility", "mastery" },
    },

}
