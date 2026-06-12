-- DodoInspect - Locales.lua
-- Translations for slot labels and item type tags.
--
-- This is the only file in the addon that contains non-ASCII
-- characters: the Chinese strings themselves (French and Spanish
-- labels are deliberately accent-free so they render in any client
-- font). Everything else (code, comments, docs) stays pure ASCII.
-- HARD RULE: tags are 4 characters max (2 CJK chars max) -- that is
-- all a bag icon row fits (size 11 Latin, 13 for CJK via sizeBump).
--
-- "font" is an optional font override for languages the default
-- client font cannot render (Chinese glyphs are missing from the
-- Latin client font). When the override fails to load, the code
-- falls back to the client default font.
--
-- "sizeBump" is an optional addition to the bag slot label and type
-- tag font sizes: CJK glyphs are denser than Latin and need a point
-- or two more than the default 11px to stay readable.

local _, ns = ...

ns.DEFAULT_LOCALE = "en"

ns.Locales = {

    en = {
        name = "English",
        font = nil, -- client default
        slots = {
            INVTYPE_HEAD           = "HD",
            INVTYPE_NECK           = "NK",
            INVTYPE_SHOULDER       = "SH",
            INVTYPE_CLOAK          = "CL",
            INVTYPE_CHEST          = "CH",
            INVTYPE_ROBE           = "CH",
            INVTYPE_BODY           = "ST", -- shirt
            INVTYPE_WRIST          = "WR",
            INVTYPE_HAND           = "GL", -- gloves
            INVTYPE_WAIST          = "BT", -- belt
            INVTYPE_LEGS           = "LG",
            INVTYPE_FEET           = "FT",
            INVTYPE_FINGER         = "RG", -- ring
            INVTYPE_TRINKET        = "TR",
            INVTYPE_WEAPON         = "1H",
            INVTYPE_2HWEAPON       = "2H",
            INVTYPE_WEAPONMAINHAND = "MH",
            INVTYPE_WEAPONOFFHAND  = "OH",
            INVTYPE_SHIELD         = "SD",
            INVTYPE_HOLDABLE       = "OH",
            INVTYPE_RANGED         = "RN",
            INVTYPE_RANGEDRIGHT    = "RN",
            INVTYPE_THROWN         = "TH",
            INVTYPE_RELIC          = "RL",
            INVTYPE_TABARD         = "TB",
        },
        tags = {
            junk   = "JUNK",
            quest  = "QST",
            food   = "FOOD",
            flask  = "FLSK",
            potion = "POT",
            cons   = "CONS",
        },
        -- secondary stats, 2 letters max (1 CJK char)
        stats = {
            versatility = "VS",
            haste       = "HA",
            mastery     = "MA",
            crit        = "CR",
        },
        enchant = "EN",
    },

    cn = {
        name = "中文",
        font = "Fonts\\ARKai_T.ttf", -- simplified Chinese client font
        sizeBump = 2,
        slots = {
            INVTYPE_HEAD           = "头",
            INVTYPE_NECK           = "颈",
            INVTYPE_SHOULDER       = "肩",
            INVTYPE_CLOAK          = "背",
            INVTYPE_CHEST          = "胸",
            INVTYPE_ROBE           = "胸",
            INVTYPE_BODY           = "衬",
            INVTYPE_WRIST          = "腕",
            INVTYPE_HAND           = "手",
            INVTYPE_WAIST          = "腰",
            INVTYPE_LEGS           = "腿",
            INVTYPE_FEET           = "脚",
            INVTYPE_FINGER         = "戒",
            INVTYPE_TRINKET        = "饰",
            INVTYPE_WEAPON         = "武",
            INVTYPE_2HWEAPON       = "双",
            INVTYPE_WEAPONMAINHAND = "主",
            INVTYPE_WEAPONOFFHAND  = "副",
            INVTYPE_SHIELD         = "盾",
            INVTYPE_HOLDABLE       = "副",
            INVTYPE_RANGED         = "远",
            INVTYPE_RANGEDRIGHT    = "远",
            INVTYPE_THROWN         = "远",
            INVTYPE_RELIC          = "圣",
            INVTYPE_TABARD         = "袍",
        },
        tags = {
            junk   = "垃圾",
            quest  = "任务",
            food   = "食物",
            flask  = "合剂",
            potion = "药水",
            cons   = "消耗",
        },
        stats = {
            versatility = "全",
            haste       = "急",
            mastery     = "精",
            crit        = "爆",
        },
        enchant = "附",
    },

    fr = {
        name = "Français",
        font = nil,
        slots = {
            INVTYPE_HEAD           = "TE", -- tete
            INVTYPE_NECK           = "CO", -- cou
            INVTYPE_SHOULDER       = "EP", -- epaule
            INVTYPE_CLOAK          = "DO", -- dos
            INVTYPE_CHEST          = "TO", -- torse
            INVTYPE_ROBE           = "TO",
            INVTYPE_BODY           = "CH", -- chemise
            INVTYPE_WRIST          = "PG", -- poignets
            INVTYPE_HAND           = "MA", -- mains
            INVTYPE_WAIST          = "TA", -- taille
            INVTYPE_LEGS           = "JA", -- jambes
            INVTYPE_FEET           = "PI", -- pieds
            INVTYPE_FINGER         = "AN", -- anneau
            INVTYPE_TRINKET        = "BI", -- bijou
            INVTYPE_WEAPON         = "1M", -- une main
            INVTYPE_2HWEAPON       = "2M", -- deux mains
            INVTYPE_WEAPONMAINHAND = "MD", -- main droite
            INVTYPE_WEAPONOFFHAND  = "MG", -- main gauche
            INVTYPE_SHIELD         = "BO", -- bouclier
            INVTYPE_HOLDABLE       = "MG",
            INVTYPE_RANGED         = "DI", -- a distance
            INVTYPE_RANGEDRIGHT    = "DI",
            INVTYPE_THROWN         = "LA", -- lance
            INVTYPE_RELIC          = "RE", -- relique
            INVTYPE_TABARD         = "TB", -- tabard
        },
        tags = {
            junk   = "NUL",   -- worthless
            quest  = "QTE",   -- quete
            food   = "BOUF",  -- bouffe
            flask  = "FIOL",  -- fiole (phial)
            potion = "POT",
            cons   = "CONS",  -- consommable
        },
        stats = {
            versatility = "PO", -- polyvalence
            haste       = "HA", -- hate
            mastery     = "MA", -- maitrise
            crit        = "CR", -- critique
        },
        enchant = "EN", -- enchantement
    },

    es = {
        name = "Español",
        font = nil,
        slots = {
            INVTYPE_HEAD           = "CA", -- cabeza
            INVTYPE_NECK           = "CU", -- cuello
            INVTYPE_SHOULDER       = "HO", -- hombro
            INVTYPE_CLOAK          = "ES", -- espalda
            INVTYPE_CHEST          = "PE", -- pecho
            INVTYPE_ROBE           = "PE",
            INVTYPE_BODY           = "CM", -- camisa
            INVTYPE_WRIST          = "MU", -- munecas
            INVTYPE_HAND           = "MA", -- manos
            INVTYPE_WAIST          = "CI", -- cintura
            INVTYPE_LEGS           = "PR", -- piernas
            INVTYPE_FEET           = "PI", -- pies
            INVTYPE_FINGER         = "AN", -- anillo
            INVTYPE_TRINKET        = "AB", -- abalorio
            INVTYPE_WEAPON         = "1M", -- una mano
            INVTYPE_2HWEAPON       = "2M", -- dos manos
            INVTYPE_WEAPONMAINHAND = "MD", -- mano derecha
            INVTYPE_WEAPONOFFHAND  = "MI", -- mano izquierda
            INVTYPE_SHIELD         = "EC", -- escudo
            INVTYPE_HOLDABLE       = "MI",
            INVTYPE_RANGED         = "DI", -- a distancia
            INVTYPE_RANGEDRIGHT    = "DI",
            INVTYPE_THROWN         = "AR", -- arrojadiza
            INVTYPE_RELIC          = "RE", -- reliquia
            INVTYPE_TABARD         = "TB", -- tabardo
        },
        tags = {
            junk   = "MALO",  -- worthless
            quest  = "MIS",   -- mision
            food   = "COMI",  -- comida
            flask  = "VIAL",  -- phial
            potion = "POCI",  -- pocion
            cons   = "CONS",  -- consumible
        },
        stats = {
            versatility = "VE", -- versatilidad
            haste       = "CE", -- celeridad
            mastery     = "MA", -- maestria
            crit        = "CR", -- critico
        },
        enchant = "EN", -- encantamiento
    },
}

-- Stable order for the options dropdown.
ns.LocaleOrder = { "en", "cn", "fr", "es" }

-- Switch the active locale (falls back to the default for unknown
-- keys) and persist the choice when SavedVariables are available.
function ns.SetLocale(key)
    if not ns.Locales[key] then key = ns.DEFAULT_LOCALE end
    ns.ActiveLocaleKey = key
    ns.L = ns.Locales[key]
    if DodoInspectDB then
        DodoInspectDB.locale = key
    end
end

-- Bootstrap with the default so every file can read ns.L right away;
-- the saved choice is applied on ADDON_LOADED (see Core.lua).
ns.SetLocale(ns.DEFAULT_LOCALE)
