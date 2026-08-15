-- DodoInspect - Locales.lua
-- Translations for slot labels and item type tags.
--
-- This is the only file in the addon that contains non-ASCII
-- characters: the Chinese strings themselves (French and Spanish
-- labels are deliberately accent-free so they render in any client
-- font). Everything else (code, comments, docs) stays pure ASCII.
-- HARD RULE: tags are 4 characters max (2 CJK chars max) -- that is
-- all a bag icon row fits (size 9 Latin, 13 for CJK; see sizeBump).
--
-- "font" is an optional font override for languages the default
-- client font cannot render (Chinese glyphs are missing from the
-- Latin client font). When the override fails to load, the code
-- falls back to the client default font.
--
-- "sizeBump" is an optional adjustment to the bag slot label and
-- type tag font sizes (base 11px). CJK glyphs are denser and ask for
-- a couple points more (cn +2 -> 13); the wider Latin tags drop a
-- couple to keep four characters inside the icon (-2 -> 9).

local _, ns = ...

ns.DEFAULT_LOCALE = "en"

ns.Locales = {

    en = {
        name = "English",
        durability = "Durability",
        font = nil, -- client default
        sizeBump = -2, -- Latin tags run wider; shrink to fit the icon
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
        statNames = {
            versatility = "Versatility",
            haste       = "Haste",
            mastery     = "Mastery",
            crit        = "Critical Strike",
        },
        -- tertiary stats, 2 letters max (1 CJK char)
        terts = {
            speed     = "SP",
            leech     = "LE",
            avoidance = "AV",
        },
        enchant = "EN",
        -- stat priority (top of the gear side panel)
        priTitle   = "Stat Priority",
        priRaid    = "Raid",
        priMythic  = "M+",
        priSame    = "Raid and M+ priority is identical",
        priGoalRating = "%s target ~%d",
        priGoalPercent = "%s target ~%d%%",
        priGoalRatingPercent = "%s target ~%d (~%d%%)",
        priGoalRange = "%s target %d-%d",
        priGoalMax = "%s target at most ~%d",
        priSource  = "Sources: %s | Reviewed: %s",
        priProvisional = "Provisional: current sources disagree; this is a best-effort baseline.",
        priDisclaimer = "General gearing reference only. Item level and primary stat usually come first; tank priorities assume survival and healer priorities assume healing. Sim your character for final choices.",
        gearSubtitle = "Ranked by stat fit -- not a best-in-slot list",
        gearEquipped = "(equipped)",
        gearNoStats = "no stat data",
        gearCrafted = "A crafted piece usually wins this slot",
        gearProvisional = "Provisional data",
        gearNoCandidates = "Nothing drops for this slot this season",
        gearNoSpec = "Specialization unknown",
        gearNoTrinketSim = "No simulation data for this spec",
        gearTwoHand = "Two-hand",
        gearOneHand = "One-hand",
        gearNoOffHandSpec = "This specialization does not use an off hand",
        gearNoOffHandTwo = "A two-handed weapon leaves this slot empty",
        priBuild      = "Build: %s",
    },

    cn = {
        name = "中文",
        durability = "耐久度",
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
        statNames = {
            versatility = "全能",
            haste       = "急速",
            mastery     = "精通",
            crit        = "暴击",
        },
        terts = {
            speed     = "速",
            leech     = "吸",
            avoidance = "避",
        },
        enchant = "附",
        priTitle   = "属性优先级",
        priRaid    = "团",
        priMythic  = "米",
        priSame    = "团本与大米优先顺序相同",
        priGoalRating = "%s目标约%d",
        priGoalPercent = "%s目标约%d%%",
        priGoalRatingPercent = "%s目标约%d（约%d%%）",
        priGoalRange = "%s目标约%d-%d",
        priGoalMax = "%s目标不高于约%d",
        priSource  = "来源: %s｜复核: %s",
        priProvisional = "暂定建议：当前资料存在分歧，本条采用最佳可用的通用基线。",
        priDisclaimer = "仅供通用配装参考。通常先看装等和主属性；坦克按生存、治疗按治疗量排序，最终请模拟自己的角色。",
        gearSubtitle = "按属性契合度排序，不是 BIS 列表",
        gearEquipped = "(当前)",
        gearNoStats = "无属性数据",
        gearCrafted = "这个部位通常用制造装备",
        gearProvisional = "数据暂定",
        gearNoCandidates = "本赛季该部位无掉落",
        gearNoSpec = "专精未知",
        gearNoTrinketSim = "本专精暂无模拟数据",
        gearTwoHand = "双手",
        gearOneHand = "单手",
        gearNoOffHandSpec = "该专精不使用副手",
        gearNoOffHandTwo = "使用双手武器时该栏空置",
        priBuild      = "构建: %s",
    },

    fr = {
        name = "Français",
        durability = "Durabilite",
        font = nil,
        sizeBump = -2,
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
        statNames = {
            versatility = "Polyvalence",
            haste       = "Hate",
            mastery     = "Maitrise",
            crit        = "Coup critique",
        },
        terts = {
            speed     = "VI", -- vitesse
            leech     = "PO", -- ponction
            avoidance = "EV", -- evitement
        },
        enchant = "EN", -- enchantement
        priTitle   = "Priorite des stats",
        priRaid    = "Raid",
        priMythic  = "M+",
        priSame    = "Priorite identique en Raid et M+",
        priGoalRating = "Objectif %s : ~%d",
        priGoalPercent = "Objectif %s : ~%d%%",
        priGoalRatingPercent = "Objectif %s : ~%d (~%d%%)",
        priGoalRange = "Objectif %s : %d-%d",
        priGoalMax = "Objectif %s : au plus ~%d",
        priSource  = "Sources : %s | Verifie : %s",
        priProvisional = "Provisoire : les sources actuelles divergent; cette ligne est une base indicative.",
        priDisclaimer = "Reference generale uniquement. Le niveau d'objet et la statistique principale priment souvent; tanks = survie, soigneurs = soins. Simulez votre personnage.",
        gearSubtitle = "Classe par affinite de stats -- pas une liste BiS",
        gearEquipped = "(equipe)",
        gearNoStats = "pas de stats",
        gearCrafted = "Un objet fabrique gagne souvent cet emplacement",
        gearProvisional = "Donnees provisoires",
        gearNoCandidates = "Rien pour cet emplacement cette saison",
        gearNoSpec = "Specialisation inconnue",
        gearNoTrinketSim = "Pas de donnees de simulation pour cette spe",
        gearTwoHand = "Deux mains",
        gearOneHand = "Une main",
        gearNoOffHandSpec = "Cette specialisation n'utilise pas de main gauche",
        gearNoOffHandTwo = "Une arme a deux mains laisse cet emplacement vide",
        priBuild      = "Build : %s",
    },

    es = {
        name = "Español",
        durability = "Durabilidad",
        font = nil,
        sizeBump = -2,
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
        statNames = {
            versatility = "Versatilidad",
            haste       = "Celeridad",
            mastery     = "Maestria",
            crit        = "Golpe critico",
        },
        terts = {
            speed     = "VE", -- velocidad
            leech     = "SU", -- sustraccion de vida
            avoidance = "EV", -- evasion
        },
        enchant = "EN", -- encantamiento
        priTitle   = "Prioridad de stats",
        priRaid    = "Banda",
        priMythic  = "M+",
        priSame    = "Prioridad identica en Banda y M+",
        priGoalRating = "Objetivo de %s: ~%d",
        priGoalPercent = "Objetivo de %s: ~%d%%",
        priGoalRatingPercent = "Objetivo de %s: ~%d (~%d%%)",
        priGoalRange = "Objetivo de %s: %d-%d",
        priGoalMax = "Objetivo de %s: como maximo ~%d",
        priSource  = "Fuentes: %s | Revisado: %s",
        priProvisional = "Provisional: las fuentes actuales difieren; esta linea es una referencia aproximada.",
        priDisclaimer = "Solo referencia general. El nivel de objeto y la estadistica principal suelen primar; tanques = supervivencia, sanadores = sanacion. Simula tu personaje.",
        gearSubtitle = "Ordenado por afinidad de stats -- no es una lista BiS",
        gearEquipped = "(equipado)",
        gearNoStats = "sin datos de stats",
        gearCrafted = "Aqui suele ganar un objeto fabricado",
        gearProvisional = "Datos provisionales",
        gearNoCandidates = "Nada para esta ranura esta temporada",
        gearNoSpec = "Especializacion desconocida",
        gearNoTrinketSim = "Sin datos de simulacion para esta espec",
        gearTwoHand = "Dos manos",
        gearOneHand = "Una mano",
        gearNoOffHandSpec = "Esta especializacion no usa mano izquierda",
        gearNoOffHandTwo = "Un arma a dos manos deja esta ranura vacia",
        priBuild      = "Build: %s",
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
