-- DodoInspect - Data/StatPriority.lua
-- Current Patch 12.1 PvE secondary-stat guidance, keyed by specID.
--
-- DATA ONLY, ASCII ONLY. Only entries with current=true are visible.
-- provisional=true marks a best-effort source-of-record where current
-- authors still disagree. There is no fallback to retained Season 1
-- research. The primary stat is intentionally omitted.
--
-- Matrix compression:
--   raid       : Raid / single-target order
--   mythic     : M+ / AoE order; omit when identical to raid
--   builds[id] : hero-tree row; omit builds when both trees are identical
--   goalBuilds[id] : hero-specific rough targets without changing the order
--
-- Order elements are stat keys or nested tie groups. Example:
--   { "mastery", { "crit", "haste" }, "versatility" }
-- Orders are deliberately static. Optional goals/contentGoals are rough
-- reference targets only; they never change an order. Threshold/after-order
-- rules are intentionally unsupported.

local _, ns = ...

ns.StatPriority = {

    ------------------------------------------------------------------
    -- Death Knight
    ------------------------------------------------------------------
    [250] = { -- Blood; survival baseline
        current = true,
        provisional = true,
        source = "Wowhead (Mandl) / Kyrasis",
        date = "2026-08-13",
        builds = {
            [31] = { -- San'layn
                raid = { "haste", { "mastery", "crit", "versatility" } },
                mythic = { "versatility", "haste", "mastery", "crit" },
            },
            [33] = { -- Deathbringer
                raid = { "crit", { "mastery", "versatility" }, "haste" },
                mythic = { "versatility", "mastery", { "crit", "haste" } },
            },
        },
    },
    [251] = { -- Frost
        current = true,
        raid = { "crit", "mastery", "haste", "versatility" },
        source = "Wowhead (khazakdk)",
        date = "2026-08-13",
    },
    [252] = { -- Unholy
        current = true,
        provisional = true,
        raid = { "mastery", "crit", "haste", "versatility" },
        source = "Wowhead (Taeznak)",
        date = "2026-08-13",
    },

    ------------------------------------------------------------------
    -- Demon Hunter
    ------------------------------------------------------------------
    [577] = { -- Havoc
        current = true,
        raid = { "crit", "mastery", "haste", "versatility" },
        source = "Wowhead / Icy Veins / Method",
        date = "2026-08-13",
    },
    [581] = { -- Vengeance; survival baseline
        current = true,
        raid = { "haste", { "crit", "versatility" }, "mastery" },
        source = "Wowhead (Itamae)",
        date = "2026-08-13",
    },
    [1480] = { -- Devourer
        current = true,
        source = "Icy Veins / Wowhead",
        date = "2026-08-13",
        builds = {
            [124] = { -- Annihilator
                raid = { "haste", "mastery", "crit", "versatility" },
                mythic = { "mastery", "haste", "crit", "versatility" },
            },
            [126] = { -- Void-Scarred
                raid = { "haste", "crit", "mastery", "versatility" },
                mythic = { "haste", "mastery", "crit", "versatility" },
            },
        },
    },

    ------------------------------------------------------------------
    -- Druid
    ------------------------------------------------------------------
    [102] = { -- Balance
        current = true,
        source = "Wowhead (gamz)",
        date = "2026-08-13",
        builds = {
            [23] = { -- Keeper of the Grove
                raid = { "mastery", { "haste", "crit" }, "versatility" },
            },
            [24] = { -- Elune's Chosen
                raid = { "mastery", "haste", "crit", "versatility" },
            },
        },
    },
    [103] = { -- Feral
        current = true,
        source = "Wowhead (Guiltyas)",
        date = "2026-08-13",
        builds = {
            [21] = { -- Druid of the Claw
                raid = { "mastery", "haste", "crit", "versatility" },
            },
            [22] = { -- Wildstalker
                raid = { "mastery", "crit", "haste", "versatility" },
            },
        },
    },
    [104] = { -- Guardian; survival baseline
        current = true,
        raid = { "haste", "versatility", "crit", "mastery" },
        source = "Wowhead (Pumps)",
        date = "2026-08-13",
    },
    [105] = { -- Restoration; healing baseline
        current = true,
        raid = { "haste", "mastery", "versatility", "crit" },
        source = "Wowhead (Voulk)",
        date = "2026-08-13",
    },

    ------------------------------------------------------------------
    -- Evoker
    ------------------------------------------------------------------
    [1467] = { -- Devastation
        current = true,
        provisional = true,
        raid = { "crit", "mastery", "haste", "versatility" },
        source = "Wowhead (Preheat)",
        date = "2026-08-13",
    },
    [1468] = { -- Preservation; healing baseline
        current = true,
        source = "Wowhead / Spiritbloom.Pro / Method",
        date = "2026-08-13",
        builds = {
            [37] = { -- Flameshaper
                raid = { "mastery", "crit", "haste", "versatility" },
            },
            [38] = { -- Chronowarden
                raid = { "mastery", "crit", "haste", "versatility" },
                mythic = { "mastery", "haste", "crit", "versatility" },
            },
        },
    },
    [1473] = { -- Augmentation
        current = true,
        source = "Icy Veins / Wowhead",
        date = "2026-08-13",
        builds = {
            [38] = { -- Chronowarden
                raid = { "mastery", "crit", "haste", "versatility" },
            },
            [36] = { -- Scalecommander
                raid = { "mastery", { "crit", "haste" }, "versatility" },
            },
        },
    },

    ------------------------------------------------------------------
    -- Hunter
    ------------------------------------------------------------------
    [253] = { -- Beast Mastery
        current = true,
        source = "Wowhead / Method",
        date = "2026-08-13",
        builds = {
            [43] = { -- Pack Leader
                raid = { "mastery", { "crit", "haste" }, "versatility" },
                mythic = { "mastery", "crit", { "haste", "versatility" } },
            },
            [44] = { -- Dark Ranger
                raid = { "crit", "mastery", "haste", "versatility" },
                mythic = { "mastery", "crit", "haste", "versatility" },
            },
        },
    },
    [254] = { -- Marksmanship
        current = true,
        raid = { "crit", "mastery", "versatility", "haste" },
        source = "Wowhead / Method",
        date = "2026-08-13",
    },
    [255] = { -- Survival
        current = true,
        raid = { "mastery", { "crit", "haste" }, "versatility" },
        source = "Wowhead / Icy Veins / Method",
        date = "2026-08-13",
    },

    ------------------------------------------------------------------
    -- Mage
    ------------------------------------------------------------------
    [62] = { -- Arcane
        current = true,
        provisional = true,
        source = "Wowhead (Porom)",
        date = "2026-08-13",
        builds = {
            [40] = { -- Spellslinger
                raid = { "haste", "mastery", "crit", "versatility" },
            },
            [39] = { -- Sunfury
                raid = { "haste", "versatility", "crit", "mastery" },
            },
        },
    },
    [63] = { -- Fire
        current = true,
        raid = { "haste", "mastery", "versatility", "crit" },
        source = "Wowhead / Icy Veins",
        date = "2026-08-13",
    },
    [64] = { -- Frost
        current = true,
        raid = { "mastery", "crit", "haste", "versatility" },
        source = "Wowhead / Icy Veins",
        date = "2026-08-13",
    },

    ------------------------------------------------------------------
    -- Monk
    ------------------------------------------------------------------
    [268] = { -- Brewmaster; Raid survival, M+ combined damage baseline
        current = true,
        raid = { { "crit", "versatility", "mastery" }, "haste" },
        mythic = { "crit", { "versatility", "mastery" }, "haste" },
        source = "Wowhead / Method",
        date = "2026-08-13",
    },
    [269] = { -- Windwalker
        current = true,
        raid = { { "haste", "crit", "mastery" }, "versatility" },
        source = "Peak of Serenity / Wowhead",
        date = "2026-08-13",
    },
    [270] = { -- Mistweaver; healing throughput baseline
        current = true,
        provisional = true,
        raid = { "haste", "crit", "versatility", "mastery" },
        mythic = { "haste", "mastery", "crit", "versatility" },
        source = "Wowhead (Swirl)",
        date = "2026-08-13",
    },

    ------------------------------------------------------------------
    -- Paladin
    ------------------------------------------------------------------
    [65] = { -- Holy; healing throughput baseline
        current = true,
        source = "Icy Veins / Method / WingsIsUp",
        date = "2026-08-13",
        builds = {
            [50] = { -- Herald of the Sun
                raid = { "mastery", "haste", "crit", "versatility" },
            },
            [49] = { -- Lightsmith
                raid = { "mastery", "crit", "haste", "versatility" },
                mythic = { "mastery", "haste", "crit", "versatility" },
            },
        },
    },
    [66] = { -- Protection; survival baseline
        current = true,
        provisional = true,
        raid = { "haste", "mastery", "crit", "versatility" },
        source = "Wowhead (Pumps)",
        date = "2026-08-13",
    },
    [70] = { -- Retribution
        current = true,
        raid = { "mastery", "haste", "crit", "versatility" },
        source = "Wowhead / Method",
        date = "2026-08-13",
    },

    ------------------------------------------------------------------
    -- Priest
    ------------------------------------------------------------------
    [256] = { -- Discipline; healing baseline
        current = true,
        raid = { "haste", "mastery", "crit", "versatility" },
        source = "Icy Veins / Wowhead",
        date = "2026-08-13",
        goalBuilds = {
            [18] = { -- Voidweaver
                goals = {
                    { stat = "haste", value = 1800, unit = "rating" },
                },
            },
            [20] = {}, -- Oracle; no specific target
        },
    },
    [257] = { -- Holy; healing throughput baseline
        current = true,
        provisional = true,
        raid = { "crit", "mastery", "versatility", "haste" },
        mythic = { "crit", "versatility", "haste", "mastery" },
        source = "Icy Veins (Niphyr)",
        date = "2026-08-13",
    },
    [258] = { -- Shadow
        current = true,
        raid = { "haste", "mastery", "crit", "versatility" },
        source = "Warcraft Priests",
        date = "2026-08-13",
        goalBuilds = {
            [19] = { -- Archon
                contentGoals = {
                    raid = {
                        { stat = "crit", min = 800, max = 1200 },
                        { stat = "haste", min = 1400, max = 1600 },
                        { stat = "mastery", min = 1200, max = 1400 },
                        { stat = "versatility", max = 400 },
                    },
                    mythic = {
                        { stat = "crit", min = 800, max = 1200 },
                        { stat = "haste", min = 1600, max = 1800 },
                        { stat = "mastery", min = 1000, max = 1200 },
                        { stat = "versatility", max = 400 },
                    },
                },
            },
            [18] = { -- Voidweaver
                contentGoals = {
                    raid = {
                        { stat = "crit", min = 800, max = 1200 },
                        { stat = "haste", min = 1400, max = 1800 },
                        { stat = "mastery", min = 1200, max = 1400 },
                        { stat = "versatility", max = 400 },
                    },
                    mythic = {
                        { stat = "crit", min = 800, max = 1200 },
                        { stat = "haste", min = 1600, max = 1800 },
                        { stat = "mastery", min = 1000, max = 1200 },
                        { stat = "versatility", max = 400 },
                    },
                },
            },
        },
    },

    ------------------------------------------------------------------
    -- Rogue
    ------------------------------------------------------------------
    [259] = { -- Assassination
        current = true,
        raid = { "crit", "haste", "mastery", "versatility" },
        source = "Wowhead / Icy Veins",
        date = "2026-08-13",
    },
    [260] = { -- Outlaw
        current = true,
        provisional = true,
        raid = { "haste", "crit", "versatility", "mastery" },
        goals = {
            { stat = "haste", value = 23, unit = "percent" },
        },
        source = "Wowhead (JustGuy)",
        date = "2026-08-13",
    },
    [261] = { -- Subtlety
        current = true,
        provisional = true,
        raid = { "mastery", "haste", "crit", "versatility" },
        contentGoals = {
            raid = {
                { stat = "haste", value = 1100, unit = "rating" },
            },
            mythic = {
                { stat = "haste", min = 650, max = 700, unit = "rating" },
            },
        },
        source = "Wowhead (fuu1)",
        date = "2026-08-13",
    },

    ------------------------------------------------------------------
    -- Shaman
    ------------------------------------------------------------------
    [262] = { -- Elemental
        current = true,
        raid = { "mastery", { "haste", "crit" }, "versatility" },
        goals = {
            { stat = "mastery", value = 1200, percent = 72, unit = "rating" },
        },
        source = "Wowhead / Icy Veins",
        date = "2026-08-13",
    },
    [263] = { -- Enhancement
        current = true,
        raid = { { "mastery", "haste" }, "crit", "versatility" },
        source = "Wowhead / Icy Veins (Wordup)",
        date = "2026-08-13",
    },
    [264] = { -- Restoration; healing throughput baseline
        current = true,
        provisional = true,
        raid = { "crit", "haste", "versatility", "mastery" },
        source = "Wowhead (Harreks)",
        date = "2026-08-13",
    },

    ------------------------------------------------------------------
    -- Warlock
    ------------------------------------------------------------------
    [265] = { -- Affliction
        current = true,
        provisional = true,
        raid = { "haste", "crit", "versatility", "mastery" },
        source = "Wowhead (Kalamazi)",
        date = "2026-08-13",
    },
    [266] = { -- Demonology
        current = true,
        provisional = true,
        raid = { { "haste", "crit" }, "mastery", "versatility" },
        source = "Wowhead (NotWarlock)",
        date = "2026-08-13",
    },
    [267] = { -- Destruction
        current = true,
        provisional = true,
        raid = { "haste", { "mastery", "crit" }, "versatility" },
        source = "Wowhead (Loozy)",
        date = "2026-08-13",
    },

    ------------------------------------------------------------------
    -- Warrior
    ------------------------------------------------------------------
    [71] = { -- Arms
        current = true,
        raid = { { "crit", "haste" }, "mastery", "versatility" },
        source = "Wowhead / Icy Veins (Archimtiros)",
        date = "2026-08-13",
    },
    [72] = { -- Fury
        current = true,
        provisional = true,
        raid = { "haste", "mastery", "crit", "versatility" },
        source = "Wowhead (Archimtiros)",
        date = "2026-08-13",
    },
    [73] = { -- Protection; general survival baseline
        current = true,
        raid = { "haste", { "crit", "versatility" }, "mastery" },
        mythic = { "haste", "crit", "versatility", "mastery" },
        source = "Wowhead / Icy Veins",
        date = "2026-08-13",
    },
}
