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
        -- 2026-08-22: author flipped Crit ahead of Mastery on 08-17
        -- ("Crit tends to be slightly better than Mastery on average").
        -- Both hero trees (San'layn / Rider) list the same order.
        current = true,
        provisional = true,
        raid = { "crit", "mastery", "haste", "versatility" },
        source = "Wowhead (Taeznak)",
        date = "2026-08-22",
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
        -- 2026-08-25 15:00: the author ADDED a chart (H > C > V > M) and in
        -- the same breath wrote that "all secondary stats are roughly
        -- equal, closer to the difference between .95 and 1 in value rather
        -- than .1 and 1", that Versatility "is equally as good as Critical
        -- Strike", and that Mastery "is also equal ... slightly better than
        -- Crit outside of Meta and slightly worse during it". The prose did
        -- not change; only the chart is new. Shipping the chart literally
        -- would assert a precision the author explicitly disclaims, so the
        -- three near-equal stats stay tied and only Haste leads.
        -- Icy Veins (dated 08-26) ranks them H > M > V > C for damage and
        -- says item level dominates defensively. Two sources of record that
        -- put Mastery second and last respectively => provisional.
        current = true,
        provisional = true,
        raid = { "haste", { "crit", "versatility", "mastery" } },
        source = "Wowhead (Itamae) / Icy Veins",
        date = "2026-08-25",
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
        -- 2026-08-22: the previous hero-tree split was a misreading. The two
        -- side-by-side boxes on the source page are titled "Raid" and
        -- "Mythic+", not Flameshaper / Chronowarden; that page carries no
        -- hero-tree markers at all, and Method (08-20) is also tree-agnostic.
        -- Raid agrees across both sources. For M+ the sources split by intent:
        -- Method separates healing-output (M > C > H > V) from damage-leaning
        -- (C > H > M > V) and Wowhead lists only the damage-leaning one. House
        -- rule is healers default to healing output, which equals the raid
        -- order, so this collapses to 1x1. provisional: M+ sources disagree.
        current = true,
        provisional = true,
        raid = { "mastery", "crit", "haste", "versatility" },
        source = "Wowhead / Method (Cryve)",
        date = "2026-08-22",
    },
    [1473] = { -- Augmentation
        -- 2026-08-28: Wowhead ships one identical list for both hero trees
        -- (M > C > H > V), so its page cannot be the origin of the asymmetry
        -- below -- and its own prose says the two trees "may differ", which
        -- its two identical boxes then do not. The asymmetry is transcribed
        -- from Icy Veins (upd. 08-10, Saeldur), sentence by sentence:
        --   "As a Chronowarden Crit is very slightly better than Haste but
        --   they are extremely close."   -> 38: M > C > H > V
        --   "As a Scalecommander they are equivalent."  -> 36: M > C=H > V
        -- Corroboration that this row was read and not invented: the
        -- threshold that used to sit here (mastery 1840, after which
        -- mastery/crit/haste collapse together) is the same page's "until
        -- you get close to the Second Stat DR around 1840 Mastery. At that
        -- point it is approximately equal to Haste and Critical Strike
        -- Chance." The number was dropped by the fully-static rewrite; the
        -- order it came with is still correct. Method (upd. 08-25, Daylea)
        -- independently writes "Mastery > Haste = Critical Strike > Vers".
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
        -- 2026-08-28: the Pack Leader raid row used to tie Crit and Haste.
        -- No source says that. Unlike 73 and 1473 -- where the tie is what
        -- the guides actually state -- this one has no origin we can find:
        --   Wowhead (Tarlo) writes the two as separate list items, and its
        --   prose asserts a real gap: "Pack Leader wants Weapon Damage,
        --   followed by Agility, then Mastery, Critical Strike, Haste and
        --   finally Versatility, in every situation" plus "the gap between
        --   your two highest secondary stats and Haste is much larger on AoE
        --   than on single-target". Negative control: on the SURVIVAL page
        --   the same author writes the same hero tree's tie as one item,
        --   "[li]Critical Strike and Haste[/li]" -- so the split here is a
        --   real reading, not a parser blind spot.
        --   Icy Veins never ties them either: "we recommend Crit > Haste as
        --   a rule of thumb for general, all-content play" (changelog
        --   16 Jul. 2026: "Clarified the Crit vs Haste rule of thumb").
        --   The repo never recorded a reason: 253 appears only in the "not
        --   done yet" lists of both research docs, then went straight into
        --   the release matrix.
        -- Likely mechanism (a hypothesis, not established): Method/Qenjua's
        -- single-target line reads "Mastery > Haste => Crit > Versatility"
        -- -- a stray "=>" where every other tie on that site is a plain "=".
        -- Read as a tie it yields exactly the row we shipped, and the mythic
        -- row matches that page's AoE line ("Crit > Vers = Haste") word for
        -- word, so the transcription clearly went ST->raid, AoE->mythic.
        -- Cannot be proven: that page's Last Updated is 08-23, after we
        -- transcribed on 08-13.
        -- Raid now follows Wowhead's Pack Leader list. Mythic is unchanged
        -- (it is sourced -- only the AoE = M+ mapping is ours). provisional
        -- because the three sources genuinely disagree on the order itself:
        -- Wowhead M>C>H>V, Method ST M>H>C>V, Icy Veins ST M>H>C>V.
        current = true,
        provisional = true,
        source = "Wowhead / Method",
        date = "2026-08-28",
        builds = {
            [43] = { -- Pack Leader
                raid = { "mastery", "crit", "haste", "versatility" },
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
        -- 2026-08-28: tie group rewritten in the source's own order
        -- (Wowhead: "Versatility, Critical Strike, Mastery"). Tiers are
        -- unchanged, so weights and the raid/mythic collapse are unchanged
        -- too -- this only stops the scanner reporting tie-order forever.
        current = true,
        raid = { { "versatility", "crit", "mastery" }, "haste" },
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
        -- 2026-08-28: the raid rows below are Icy Veins verbatim and stay.
        -- The M+ bucket is the part that was wrong: it resolved to
        -- mastery-first for BOTH trees (tree 49 from Icy Veins' own "Mythic+"
        -- widget, tree 50 by falling back to its raid row for want of a
        -- mythic one), and two of the three sources we cite contradict that
        -- specific claim. Method (upd. 08-27): "Since Mastery does not
        -- contribute any damage, the value is decreased significantly in
        -- Mythic+" and "Versatility takes precedence over mastery in M+".
        -- WingsIsUp's Meta Mythic+ build opens on Haste (~25% floor) and
        -- trails "Vers / Crit / Mastery" as a group. Icy Veins is the lone
        -- mastery-first holdout for M+, so it loses 2-to-1 on that point.
        -- Both trees now carry an explicit mythic row -- neither may fall
        -- back to raid, because the fallback is what hid this.
        current = true,
        provisional = true,
        source = "Method / WingsIsUp (M+) / Icy Veins (raid)",
        date = "2026-08-28",
        builds = {
            [50] = { -- Herald of the Sun
                raid = { "mastery", "haste", "crit", "versatility" },
                mythic = { "haste", "versatility", { "crit", "mastery" } },
            },
            [49] = { -- Lightsmith
                raid = { "mastery", "crit", "haste", "versatility" },
                mythic = { "haste", "versatility", { "crit", "mastery" } },
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
        -- 2026-08-28: the order was haste-first, attributed to "Warcraft
        -- Priests" -- but that site is a links hub whose own inline stat text
        -- is a stale Wrath-era leftover (it still names Idol of Yogg-Saron),
        -- i.e. it never sourced this row. Icy Veins (upd. 08-10) and Method
        -- (upd. 08-27) both lead with Mastery for single-target, on both hero
        -- trees. Decisive detail: the goalBuilds rating bands below already
        -- matched Icy Veins EXACTLY, per tree and per content -- the numbers
        -- had been transcribed and only the order string was left behind.
        -- Orders now come from the same source as the goals, so the two can
        -- no longer silently disagree. (Haste carries a higher rating target
        -- than Mastery while ranking below it; a target is not a ranking.)
        current = true,
        source = "Icy Veins / Method",
        date = "2026-08-28",
        builds = {
            [19] = { -- Archon
                raid = { "mastery", "crit", "haste", "versatility" },
                mythic = { "mastery", "haste", "crit", "versatility" },
            },
            [18] = { -- Voidweaver
                raid = { "mastery", "haste", "crit", "versatility" },
                mythic = { "haste", "mastery", "crit", "versatility" },
            },
        },
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
        -- 2026-08-28: two live sources disagree and have since before this
        -- row was first written. Wowhead (JustGuy, upd. 08-12) leads with
        -- Haste; Icy Veins (Seliathan, upd. 08-10) leads with Critical
        -- Strike -- "Item Level, Critical Strike to 40%, Haste to 25%,
        -- Versatility, Mastery" -- and states it applies to both raid and
        -- M+. Taking Icy Veins for the order. Stays provisional: this is a
        -- source conflict that has not resolved, not a settled answer.
        -- NOTE the haste goal below is still Wowhead's 23%; Icy Veins says
        -- 25% (M+) / 30% (raid). Goals never change an order, so it is left
        -- alone here rather than half-migrated -- revisit as its own call.
        current = true,
        provisional = true,
        raid = { "crit", "haste", "versatility", "mastery" },
        goals = {
            { stat = "haste", value = 23, unit = "percent" },
        },
        source = "Icy Veins (Seliathan) / Wowhead (JustGuy)",
        date = "2026-08-28",
    },
    [261] = { -- Subtlety
        -- 2026-08-22: page was rewritten 08-19 into a 2x2 grid (Deathstalker /
        -- Trickster x Single Target / Mythic+). All four cells are identical,
        -- so this stays 1x1. Versatility moved ahead of Crit, and the split
        -- Haste targets (raid 1100 / M+ 650-700) collapsed into a flat ~700.
        current = true,
        provisional = true,
        raid = { "mastery", "haste", "versatility", "crit" },
        goals = {
            { stat = "haste", value = 700, unit = "rating" },
        },
        source = "Wowhead (fuu1)",
        date = "2026-08-22",
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
        -- 2026-08-22 23:48: the author split the trees. Season-start crit
        -- gear lost its stats, so Stormbringer moved onto Crit and off
        -- Haste; Totemic did not move and still matches what shipped as
        -- the single row. Single-target and AoE stay identical, so this is
        -- 2 trees x 1 content, not 2x2.
        -- Icy Veins (same author, page dated 08-23) agrees on the split and
        -- on the top two of each tree but writes them strictly rather than
        -- tied: Stormbringer M > C > H > V, Totemic M > H > C > V. Same
        -- author on both sites means that is not independent confirmation,
        -- so the tie form -- the weaker claim both pages support -- ships.
        current = true,
        source = "Wowhead (Wordup)",
        date = "2026-08-22",
        builds = {
            [54] = { -- Totemic
                raid = { { "mastery", "haste" }, "crit", "versatility" },
            },
            [55] = { -- Stormbringer
                raid = { { "crit", "mastery" }, "haste", "versatility" },
            },
        },
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
        -- 2026-08-28: Wowhead's Survivability list splits Crit and Vers
        -- (H > C > V > M), which is what our mythic row already says. We
        -- keep the raid tie because the other two sources state it outright,
        -- and because Wowhead's own prose does not match its own list -- it
        -- groups 2+2 ("Defensively, Protection prefers Haste and Crit with a
        -- good balance of Vers and Mastery"), not 1-1-1-1.
        --   Icy Veins (upd. 08-10, Mwahi): "Versatility is roughly equal to
        --   Critical Strike." Its widget draws a literal equals icon between
        --   the two, arrows everywhere else.
        --   Method (upd. 08-11, Nate): "Strength >> Haste > Crit = Vers >
        --   Mastery for all situations."
        -- The raid/M+ split is Icy Veins too: "Critical Strike increases in
        -- value for Mythic+." Wowhead has no M+ box for this spec at all,
        -- which is why the mythic row shows up under UNVERIFIED -- no source
        -- contradicts it, one source simply never speaks to it.
        current = true,
        raid = { "haste", { "crit", "versatility" }, "mastery" },
        mythic = { "haste", "crit", "versatility", "mastery" },
        source = "Wowhead / Icy Veins",
        date = "2026-08-13",
    },
}
