-- DodoCombatHUD - AuraSets.lua
-- 三排 aura 的**内置 spellID 表** + 几个纯函数。一个框体都不建、一点状态都不存
-- ⇒ 算法那一半能被离线测试够得着(tools/test_aura.lua)。别把逻辑挪回主文件。
--
-- 🔑 三排的语义不一样,分桶方式也就不一样:
--   · DoT   = 我打在**目标**身上的      → 跟专精走 ⇒ 按 specID 分桶
--   · 大招  = 我开在**自己**身上的      → 跟专精走 ⇒ 按 specID 分桶
--   · 团队增益 = **别人给我的**          → 跟我什么专精**无关** ⇒ 全职业一张表
--
-- 🔴 填的必须是**光环那个 ID**,不是技能那个 ID —— 两者常常不同。
--    实例:冷却管理器 Essential 里那条「虚空形态」是 228260(施法),而挂在你身上的
--    光环是 194249(同名不同 ID)。填错**不报错**,只是那一格永远空着 ——
--    跟「ID 没填」「这专精没有」三者分不开。⇒ 用 /dch cd 列出来核名字。
--
-- 📌 ID 来源(2026-08-15):
--    · DoT   —— rgd87/NugRunning config.lua(2024-08,11.0 时代)当候选池,
--                名字用 wago.tools SpellName.db2 @ build 12.1.0.69299 逐个核过
--    · 大招  —— 暴雪冷却管理器自己的 DB2(CooldownSet / CooldownSetSpell)同一个 build,
--                取 Essential 分类 ∩「施加光环的效果目标是友方」∩ 有持续时间
--    · 团队增益 —— 同上的 GroupBuff 分类(只有治疗 / 辅助专精才有)
--    ⚠ 唤魔师的 DoT 那份候选池里**根本没有**(NugRunning 没有 Evoker 段)⇒ 留空,别当"它没有"。

local ADDON, ns = ...
ns = ns or {}

-- specID 取自 ChrSpecialization.db2。写成常量而不是裸数字:下面四张表全靠它对齐,
-- 写错一个数字的症状是「换到那个专精整排空」——跟 ID 填错分不开。
local SPEC = {
    WAR_ARMS = 71,  WAR_FURY = 72,  WAR_PROT = 73,
    PAL_HOLY = 65,  PAL_PROT = 66,  PAL_RET  = 70,
    HUN_BM   = 253, HUN_MM   = 254, HUN_SV   = 255,
    ROG_ASSA = 259, ROG_OUT  = 260, ROG_SUB  = 261,
    PRI_DISC = 256, PRI_HOLY = 257, PRI_SHAD = 258,
    DK_BLOOD = 250, DK_FROST = 251, DK_UNH   = 252,
    SHA_ELE  = 262, SHA_ENH  = 263, SHA_RES  = 264,
    MAG_ARC  = 62,  MAG_FIRE = 63,  MAG_FROST= 64,
    WLK_AFF  = 265, WLK_DEMO = 266, WLK_DEST = 267,
    MNK_BRM  = 268, MNK_WW   = 269, MNK_MW   = 270,
    DRU_BAL  = 102, DRU_FER  = 103, DRU_GUA  = 104, DRU_RES = 105,
    DH_HAVOC = 577, DH_VENG  = 581, DH_DEV   = 1480,
    EVO_DEV  = 1467, EVO_PRE = 1468, EVO_AUG  = 1473,
}
ns.SPEC = SPEC

-- ── ① 目标 DoT(敌方 debuff,我自己上的)────────────────────────────
-- ⚠ 这一排是**固定格位**(掉了哪个就空哪一格,后面的不左移)⇒ 表的长度 = 那个专精占几格。
--    容器数按 ns.DOT_SLOTS 预建,超出的格子 SetEnabled(false),**换专精不重建框体**
--    (战斗中建受保护框体大概率被拒)。所以每条不许超过 DOT_SLOTS。
ns.DOT_SLOTS = 4

ns.SPEC_DOTS = {
    -- 战士:破甲是唯一手动维持的;致死打击那个是被动,留着当"我在输出"的信号
    [SPEC.WAR_ARMS]  = { 772, 262115 },              -- Rend / Deep Wounds
    [SPEC.WAR_FURY]  = { 262115 },
    [SPEC.WAR_PROT]  = { 772, 262115 },
    -- 骑士:三系都没有真正的周期伤害 debuff(判决那种是"累计伤害",不是 DoT)
    [SPEC.PAL_HOLY]  = {},
    [SPEC.PAL_PROT]  = {},
    [SPEC.PAL_RET]   = {},
    -- 猎人:三系各自一个,ID 都不一样
    [SPEC.HUN_BM]    = { 217200 },                   -- Barbed Shot
    [SPEC.HUN_MM]    = { 271788 },                   -- Serpent Sting(射击版)
    [SPEC.HUN_SV]    = { 259491 },                   -- Serpent Sting(生存版)
    -- 潜行者
    [SPEC.ROG_ASSA]  = { 703, 1943, 121411 },        -- Garrote / Rupture / Crimson Tempest
    [SPEC.ROG_OUT]   = {},
    [SPEC.ROG_SUB]   = { 1943 },
    -- 牧师:暗牧那三个是 0.9.x 一路验过来的原班人马
    [SPEC.PRI_DISC]  = { 204213, 589 },              -- Purge the Wicked / SW:Pain(按天赋二选一)
    [SPEC.PRI_HOLY]  = { 589 },
    [SPEC.PRI_SHAD]  = { 34914, 589, 335467 },       -- VT / SW:Pain / SW:Madness
    -- DK:疾病。邪 DK 三个一起挂
    [SPEC.DK_BLOOD]  = { 55078 },                    -- Blood Plague
    [SPEC.DK_FROST]  = { 55095 },                    -- Frost Fever
    [SPEC.DK_UNH]    = { 191587, 55078, 55095 },     -- Virulent Plague / Blood Plague / Frost Fever
    -- 萨满:全职业就这一个
    [SPEC.SHA_ELE]   = { 188389 },                   -- Flame Shock
    [SPEC.SHA_ENH]   = { 188389 },
    [SPEC.SHA_RES]   = { 188389 },
    -- 法师:冰法没有 DoT;火法那个 Ignite 是被动,不是你按出来的
    [SPEC.MAG_ARC]   = { 114923 },                   -- Nether Tempest
    [SPEC.MAG_FIRE]  = { 12654 },                    -- Ignite(被动)
    [SPEC.MAG_FROST] = {},
    -- 术士:痛苦那四格里 Corruption 和 Wither 是**按英雄天赋二选一**
    -- ⇒ 空一格是正常的,那正是"该在的不在"要表达的东西
    [SPEC.WLK_AFF]   = { 980, 146739, 445474, 63106 }, -- Agony / Corruption / Wither / Siphon Life
    [SPEC.WLK_DEMO]  = { 603 },                      -- Doom
    [SPEC.WLK_DEST]  = { 157736 },                   -- Immolate
    -- 武僧:三系都没有周期伤害 debuff
    [SPEC.MNK_BRM]   = {},
    [SPEC.MNK_WW]    = {},
    [SPEC.MNK_MW]    = {},
    -- 德鲁伊
    [SPEC.DRU_BAL]   = { 164812, 164815, 202347 },   -- Moonfire / Sunfire / Stellar Flare
    [SPEC.DRU_FER]   = { 155722, 1079, 192090, 164812 }, -- Rake / Rip / Thrash / Moonfire
    [SPEC.DRU_GUA]   = { 192090, 164812 },
    [SPEC.DRU_RES]   = { 164812, 164815 },
    -- 恶魔猎手
    [SPEC.DH_HAVOC]  = { 204598 },                   -- Sigil of Flame
    [SPEC.DH_VENG]   = { 204598, 247456 },           -- Sigil of Flame / Frailty
    [SPEC.DH_DEV]    = {},                           -- 新专精,候选池里没有
    -- ⚠ 唤魔师:候选池(NugRunning)**根本没有 Evoker 段** ⇒ 这是"没调研",不是"它没有"
    [SPEC.EVO_DEV]   = {},
    [SPEC.EVO_PRE]   = {},
    [SPEC.EVO_AUG]   = {},
}

-- ── ② 大招存续(自己身上的 buff)────────────────────────────────────
-- ⚠ 这一排是**流式**(有几个画几个,没挂就不占位)⇒ 表可以随便长,不受格数限制。
--    代价:它放弃了"该在的不在一眼看出来" —— 但大招没挂是**你自己没按**,你本来就知道;
--    这一排的监控价值在"还剩几秒",不在"在不在"。
-- ⚠ 能量灌注(10060)**故意不在这儿** —— 它进了下面的团队增益表。牧师自己开也从那儿显示,
--    两边都放会在同一屏上画两个一模一样的图标。
ns.SPEC_CDS = {
    [SPEC.WAR_ARMS]  = { 107574, 260708, 227847 },        -- Avatar / Sweeping Strikes / Bladestorm
    [SPEC.WAR_FURY]  = { 107574, 1719, 227847 },          -- Avatar / Recklessness / Bladestorm
    [SPEC.WAR_PROT]  = { 107574, 871, 190456, 23920 },    -- Avatar / Shield Wall / Ignore Pain / Spell Reflection
    [SPEC.PAL_HOLY]  = { 31884, 31821, 642 },             -- Avenging Wrath / Aura Mastery / Divine Shield
    [SPEC.PAL_PROT]  = { 31884, 31850, 86659, 642 },      -- + Ardent Defender / Guardian of Ancient Kings
    [SPEC.PAL_RET]   = { 31884, 403876, 642 },            -- Avenging Wrath / Divine Protection / Divine Shield
    [SPEC.HUN_BM]    = { 19574, 186265 },                 -- Bestial Wrath / Aspect of the Turtle
    [SPEC.HUN_MM]    = { 288613, 186265 },                -- Trueshot / Turtle
    [SPEC.HUN_SV]    = { 186289, 186265 },                -- Aspect of the Eagle / Turtle
    [SPEC.ROG_ASSA]  = { 315496, 5277, 31224 },           -- Slice and Dice / Evasion / Cloak of Shadows
    [SPEC.ROG_OUT]   = { 13750, 13877, 1214909, 315496 }, -- Adrenaline Rush / Blade Flurry / Roll the Bones / SnD
    [SPEC.ROG_SUB]   = { 121471, 185313 },                -- Shadow Blades / Shadow Dance
    [SPEC.PRI_DISC]  = { 421453, 19236 },                 -- Ultimate Penitence / Desperate Prayer
    [SPEC.PRI_HOLY]  = { 200183, 64843 },                 -- Apotheosis / Divine Hymn
    -- 🔴 熵能裂隙:叫这个名字的 spellID 有**五个**,只有 450193 是挂在你身上那个 8 秒 buff。
    --    447444 = 隐藏被动(天赋本体,Apply Aura: Dummy,无持续时间)
    --    447445 = 20 秒的地面 Area Trigger(裂隙那个物体本身,不在任何单位身上)
    --    447448 = 一次性的暗影伤害事件(无持续时间)
    --    459314 = 同为 8 秒,但带 **"No Aura Icon"** 标志 ⇒ 结构上不产生图标,筛到也画不出来
    --    450193 = 8 秒 + Summon(Entropic Rift)+ 移速 ⇒ 就是它            ← 用这个
    --    ⚠ 这是文件头那条「填光环 ID 不是技能 ID」的第二个实例,而且这次**名字完全不能当判据**
    --      (五个全叫「熵能裂隙」)⇒ /dch cd 列出来名字对,只证明 ID 存在,不证明选对了那一个。
    [SPEC.PRI_SHAD]  = { 194249, 47585, 15286, 450193 },  -- Voidform(光环 ID!)/ Dispersion / Vampiric Embrace / 熵能裂隙
    -- 血 DK:骨盾常驻 + 血裔精华 + 四个保命大招。沸点(15+3)不在这儿 ——
    -- 它要变色 / 换图 / 优先级,那三样容器给不了,走 Boiling.lua 钉死的那一格。
    [SPEC.DK_BLOOD]  = { 195181, 433925, 55233, 49028, 48792, 48707 },
    -- 骨盾 / 鲜血女王的精华 / 吸血鬼之血 / 舞动符文武器 / 冰封之韧 / 反魔法护罩
    [SPEC.DK_FROST]  = { 51271, 48792, 48707 },           -- Pillar of Frost / Icebound / AMS
    [SPEC.DK_UNH]    = { 1233448, 42650, 48792, 48707 },  -- Dark Transformation / Army of the Dead / …
    [SPEC.SHA_ELE]   = { 191634, 108271 },                -- Stormkeeper / Astral Shift
    [SPEC.SHA_ENH]   = { 108271 },                        -- ⚠ 机器表里 Enhancement 的 Essential 一条都没命中
    [SPEC.SHA_RES]   = { 114052, 108271 },                -- Ascendance / Astral Shift
    [SPEC.MAG_ARC]   = { 12051, 45438, 66 },              -- Evocation / Ice Block / Invisibility
    [SPEC.MAG_FIRE]  = { 190319, 45438 },                 -- Combustion / Ice Block
    [SPEC.MAG_FROST] = { 11426, 45438 },                  -- Ice Barrier / Ice Block
    [SPEC.WLK_AFF]   = { 205180, 442726, 104773 },        -- Summon Darkglare / Malevolence / Unending Resolve
    [SPEC.WLK_DEMO]  = { 265187, 104773 },                -- Summon Demonic Tyrant / Unending Resolve
    [SPEC.WLK_DEST]  = { 442726, 104773, 108416 },        -- Malevolence / Unending Resolve / Dark Pact
    [SPEC.MNK_BRM]   = { 322507, 132578 },                -- Celestial Brew / Invoke Niuzao
    [SPEC.MNK_WW]    = { 123904, 1249625, 122470 },       -- Invoke Xuen / Zenith / Touch of Karma
    [SPEC.MNK_MW]    = { 116680, 322118, 325197 },        -- Thunder Focus Tea / Yu'lon / Chi-Ji
    [SPEC.DRU_BAL]   = { 194223, 22812 },                 -- Celestial Alignment / Barkskin
    [SPEC.DRU_FER]   = { 106951, 5217, 61336 },           -- Berserk / Tiger's Fury / Survival Instincts
    [SPEC.DRU_GUA]   = { 50334, 22812, 61336, 155835 },   -- Berserk / Barkskin / SI / Bristling Fur
    [SPEC.DRU_RES]   = { 740, 22812 },                    -- Tranquility / Barkskin(铁木在团队增益表里)
    [SPEC.DH_HAVOC]  = { 258920, 196718 },                -- Immolation Aura / Darkness
    [SPEC.DH_VENG]   = { 187827, 258920, 196718 },        -- Metamorphosis / Immolation Aura / Darkness
    [SPEC.DH_DEV]    = {},
    [SPEC.EVO_DEV]   = { 375087, 363916 },                -- Dragonrage / Obsidian Scales
    [SPEC.EVO_PRE]   = { 370960, 363916 },                -- Emerald Communion / Obsidian Scales
    [SPEC.EVO_AUG]   = { 363916 },                        -- Obsidian Scales(增强给别人的都在团队增益表)
}

-- ── ③ 嗜血一族(单独一格,不跟任何东西抢位置)──────────────────────
-- 🔑 为什么单开一格而不是丢进下面那张流式表:"嗜血必须得有"如果靠 sortMethod 排对,
--    就成了一个押在**我还没验过的排序行为**上的需求。给它一个专属容器 ⇒ 结构上保证有位置,
--    没嗜血时那格空着,正好是"该在的不在"。(canon:能靠结构保证的别靠算式保证。)
-- ⚠ 同一时刻只可能有一个(疲劳机制保证)⇒ maxFrameCount 照样用实测过的 6,不赌小值。
ns.LUST = { 2825, 32182, 80353, 264667, 390386, 146555, 90355 }
--          嗜血 / 英勇 / 时间扭曲 / 野性狂怒 / 巨龙之怒 / 战鼓 / 远古狂乱(猎人宠物)

-- ⛔ 疲劳一族(Sated 57724 / Exhaustion 57723 / Temporal Displacement 80354 /
--    Fatigued 160455 / Insanity 95809)**做不了**:那是"友方身上的 debuff",
--    正好是 AuraContainerUtil.CanApplyIdentityCandidateFilters 禁的两格之一。
--    想加的话先用 C_Secrets.GetSpellAuraSecrecy 问它是不是 Never(那种无条件豁免)。

-- ── ④ 别人给我的增益(流式,全职业通用)──────────────────────────
-- 来源 = 冷却管理器 DB2 的 GroupBuff 分类(只有治疗 / 辅助专精才有),按"DPS 会想看"筛过。
-- ⚠ 缺口:团队减伤(集结呐喊 / 反魔法领域 / 黑暗)**不在这个分类里** —— 它们挂在各自专精的
--    Utility 下。要的话用 /dch buff add <id> 自己补。
ns.RAID = {
    10060,                                  -- Power Infusion(牧师自己开也从这儿显示)
    395152, 410089, 410263,                 -- Ebon Might / Prescience / Inferno's Blessing(增强唤魔)
    409676, 360827, 412710, 374227, 370889, -- Chrono Ward / Blistering Scales / Timelessness / Zephyr / Twin Guardian
    369459, 357170,                         -- Source of Magic / Time Dilation
    33206, 47788, 81782,                    -- Pain Suppression / Guardian Spirit / Power Word: Barrier
    116849, 443113,                         -- Life Cocoon / Strength of the Black Ox
    102342, 29166,                          -- Ironbark / Innervate
    6940, 1022, 204018, 1044,               -- Blessing of Sacrifice / Protection / Spellwarding / Freedom
    325174,                                 -- Spirit Link Totem
}

-- ── 纯函数 ────────────────────────────────────────────────────────
-- 哪些排按专精分桶、哪些排全局一张表。**这张表是唯一的分界声明** ——
-- 别在调用处各判一次,那就是 canon 说的"同一不变式两份手写实现"。
ns.PER_SPEC   = { dots = "SPEC_DOTS", cds = "SPEC_CDS" }
ns.GLOBAL_SET = { lust = "LUST",      raid = "RAID"    }
ns.AURA_KINDS = { "dots", "cds", "lust", "raid" }

local function copy(t)
    local out = {}
    for i = 1, #(t or {}) do out[i] = t[i] end
    return out
end
ns.CopyList = copy

-- 取某一排现在该用哪份 ID 列表。返回 (list, custom)
--   custom = true  ⇒ 这是玩家自己配过的(存档里有那个桶)
--   custom = false ⇒ 内置表
-- 🔴 判据是"存档里那个桶**存不存在**",不是"它空不空" —— 玩家把一排删空是个合法状态,
--    按"空就回落内置"会让他删完下次登录又长回来,而那种「设置自己会变」最难查。
function ns.AuraList(saved, kind, specID)
    local perSpec = ns.PER_SPEC[kind]
    if perSpec then
        local bucket = saved and saved[kind] and saved[kind][specID]
        if type(bucket) == "table" then return copy(bucket), true end
        return copy(ns[perSpec][specID]), false
    end
    local g = ns.GLOBAL_SET[kind]
    if not g then return {}, false end
    local bucket = saved and saved[kind]
    if type(bucket) == "table" and rawget(bucket, "__set") then return copy(bucket), true end
    return copy(ns[g]), false
end

-- 把一份列表写回存档(玩家改过 ⇒ 从此这一排归他管,内置表不再覆盖它)。返回成没成。
-- 🔴 按专精那两排在 specID 为 nil 时**必须早退**:`t[nil] = v` 在 Lua 里是硬错误
--    (`table index is nil`),而它会从 slash 命令里冒出来 —— 玩家看到的是一串红字堆栈,
--    根本读不出"是因为问不出专精"。返回 false 让调用方说人话。
function ns.SetAuraList(saved, kind, specID, list)
    if not saved then return false end
    if ns.PER_SPEC[kind] then
        if specID == nil then return false end
        saved[kind] = type(saved[kind]) == "table" and saved[kind] or {}
        saved[kind][specID] = copy(list)
        return true
    elseif ns.GLOBAL_SET[kind] then
        local t = copy(list)
        t.__set = true            -- 标记"这桶是玩家的",空列表才区分得出"删空了"和"没配过"
        saved[kind] = t
        return true
    end
    return false
end

-- 回退到内置表:**删掉那个桶**,不是写一份内置值的拷贝进去 ——
-- 拷贝会在下次改内置表时静默过期,而它读起来完全像"我自己配的"。
function ns.ResetAuraList(saved, kind, specID)
    if not saved then return false end
    if ns.PER_SPEC[kind] then
        if specID == nil then return false end          -- 同上,别拿 nil 当键
        if type(saved[kind]) == "table" then saved[kind][specID] = nil end
        return true
    elseif ns.GLOBAL_SET[kind] then
        saved[kind] = nil
        return true
    end
    return false
end

function ns.ListAdd(list, id)
    for i = 1, #list do if list[i] == id then return false end end
    list[#list + 1] = id
    return true
end

function ns.ListRemove(list, id)
    for i = 1, #list do
        if list[i] == id then table.remove(list, i) return true end
    end
    return false
end

-- v0.9.2 → v0.10:`dots` 从**扁平数组**变成**按专精分桶**。
-- 🔴 不迁的后果不是"丢设置",是更阴的一种:暗牧存下的三个 ID 会原样带到骑士身上,
--    而症状是那排**永远空着** —— 跟"ID 填错""这专精没有"三者分不开,而且自愈不了
--    (存档里有值,内置表永远填不进去)。
-- 判据用"老形状还在不在"(第 1 个下标有没有值),自证且幂等,不另记 uiPassXXX 标记。
-- specID 拿不到时**直接丢掉**老列表:它等于内置的暗牧那三个,回落内置零损失。
function ns.MigrateDotsToBuckets(saved, specID)
    if type(saved) ~= "table" or type(saved.dots) ~= "table" then return false end
    if rawget(saved.dots, 1) == nil then return false end       -- 已经是分桶形状
    local old = copy(saved.dots)
    saved.dots = {}
    if specID then saved.dots[specID] = old end
    return true
end

