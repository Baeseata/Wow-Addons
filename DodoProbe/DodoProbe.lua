-- DodoProbe: measures which combat APIs still hand addons real (non-secret) values in 12.1.
-- Temporary diagnostic. Everything is wrapped in pcall so a blocked call reports instead of erroring.

local P = CreateFrame("Frame")
local out = {}

local function say(s) print("|cff33ff99DodoProbe|r " .. s) end

-- Classify one value without ever operating on it unsafely.
local function tag(ok, v)
    if not ok then return "|cffff3333ERROR|r" end
    if v == nil then return "|cff888888nil|r" end
    if issecretvalue and issecretvalue(v) then return "|cffff8800SECRET|r" end
    if type(v) == "table" then
        if issecrettable and issecrettable(v) then return "|cffff8800SECRET-TABLE|r" end
        return "|cff00ff00table(open)|r"
    end
    return "|cff00ff00" .. tostring(v) .. "|r"
end

local function probe(label, fn)
    local ok, v = pcall(fn)
    out[#out + 1] = string.format("  %-34s %s", label, tag(ok, v))
end

local function sname(id)
    if not id then return nil end
    local ok, n = pcall(C_Spell.GetSpellName, id)
    return ok and n or nil
end

-- Two spell ids this probe needs by name, NOT verified at the time of writing -- the probe
-- prints GetSpellName() next to each so a wrong id is obvious on sight instead of quietly
-- producing an empty result that reads like "the feature doesn't work".
-- Override in-game: /dp dot <id>   /dp exec <id>
P.dotID = 34914   -- 吸血鬼之触? (used by probe B's includeSpellIDs filter)
P.execID = 32379  -- 暗言术:灭?  (used by probe C)

-- Pull one real rotational spell id so cooldown/aura probes hit something that exists.
local function firstRotationSpell()
    if not C_AssistedCombat or not C_AssistedCombat.GetRotationSpells then return nil end
    local ok, t = pcall(C_AssistedCombat.GetRotationSpells)
    if ok and type(t) == "table" and t[1] then return t[1] end
    return nil
end

-- 聊天框读不了这么长的输出(而且滚上去截图很痛苦)。这个窗把最后一次结果原样端出来,
-- Ctrl+A / Ctrl+C 一把带走。颜色码要剥掉,否则复制出去全是 |cffff8800 这种噪音。
local function StripColors(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function ShowCopyBox(text)
    if not P.copyFrame then
        local f = CreateFrame("Frame", "DodoProbeCopyFrame", UIParent, "BackdropTemplate")
        f:SetSize(720, 480)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        f:SetBackdropColor(0, 0, 0, 0.92)
        f:SetBackdropBorderColor(1, 0.6, 0, 1)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -8)
        title:SetText("DodoProbe  —  Ctrl+A 全选, Ctrl+C 复制, Esc 关闭 (可拖动)")

        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 12, -30)
        sf:SetPoint("BOTTOMRIGHT", -32, 12)

        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(660)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.eb = eb
        P.copyFrame = f
    end
    P.copyFrame.eb:SetText(text)
    P.copyFrame:Show()
    P.copyFrame.eb:SetFocus()
    P.copyFrame.eb:HighlightText()
end

-- ===== B. CustomAuraContainer 绑 "target" + includeSpellIDs 精确筛 =====
-- 两个问题一次量:① 这个容器能不能绑 unit token "target"(= 完全不经名条)
-- ② candidateFilters.includeSpellIDs 在**敌方目标的 debuff** 上到底生不生效。
-- 源码说生效(AuraContainerUtil.CanApplyIdentityCandidateFilters 只禁「友方身上的 debuff」和
-- 「敌方身上的 buff」,我们这个组合两条都不沾),但那是契约,不是实测。
local function EnsureAuraProbe()
    if P.auraBuilt ~= nil then return P.auraBuilt end
    P.auraBuilt = false
    if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo
            and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate")) then
        P.auraErr = "没有 CustomAuraContainerTemplate"
        return false
    end

    -- bucket 收集本组创建过的按钮,好在报告里数「现在显示着几个」。
    -- ⚠ 数字只是佐证,**判据是屏幕** —— 池子里的按钮什么时候被回收不归我们管。
    local function makeInit(bucket)
        return function(button)
            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(button)
            button:SetIcon(icon)
            -- 倒计时归暴雪画 —— 插件自己的 SetCooldown 吃不下 secret,这正是走这条路的全部理由。
            local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
            cd:SetAllPoints(icon)
            cd:SetReverse(true)
            button:SetDurationCooldown(cd)
            button:SetSize(32, 32)
            bucket[#bucket + 1] = button
        end
    end

    local function mk(suffix, yOff, label, filterStr, filters)
        local c = CreateFrame("AuraContainer", "DodoProbeAura" .. suffix,
            UIParent, "CustomAuraContainerTemplate")
        c.dpButtons = {}
        c:SetSize(240, 34)
        c:SetPoint("TOPLEFT", UIParent, "TOP", -40, yOff)
        c:SetFlowLayoutAnchorPoint("TOPLEFT")
        c:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
        c:SetFlowLayoutMaximumLineSize(math.huge)
        c:SetUnit("target")
        c:AddAuraGroup("g", filterStr, {
            maxFrameCount = 6,
            sortMethod = AuraContainerSortMethod.Expiration,
            sortDirection = AuraContainerSortDirection.Normal,
            candidateFilters = filters,
            initializeFrame = makeInit(c.dpButtons),
            layout = { elementSpacing = 2, elementWidth = 32, elementHeight = 32, layoutIndex = 1 },
        })
        -- 🔴 这个标签**不能**锚到容器上。实测(12.1.0.69299):
        --   FontString:SetPoint(): Anchoring disallowed as dependent object would inherit
        --   forbidden aspects: UntrustedLayoutScriptExecution
        -- CustomAuraContainer 带着 forbidden aspect ⇒ 插件自己的对象往它身上锚 = 直接被拒,
        -- 而它是在 pcall 里抛的,表现成「整个探针建不起来」,看着像容器这条路不通。
        -- 反方向是允许的:容器 SetParent/SetPoint 到插件的框体上(DodoNameplate 一直这么用)。
        local fs = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPRIGHT", UIParent, "TOP", -46, yOff - 9)
        fs:SetText(label)
        c:SetEnabled(true)
        return c
    end

    -- 三行,不是两行。第三行(最宽的 "HARMFUL")专门为了拆开「上行是 0」这个最容易读反的结果:
    -- 三行全 0 = 绑 target 这条路不通;只有这行有 = 是 |PLAYER 或 |INCLUDE_NAME_PLATE_ONLY 出的问题,
    -- 跟容器本身无关。少了它,一个 0 会被当成「这条路死了」直接写进结论。
    local NP = "|INCLUDE_NAME_PLATE_ONLY"
    local ok, err = pcall(function()
        P.auraAny = mk("Any", -100, "任何 harmful >", "HARMFUL" .. NP, nil)
        P.auraAll = mk("All", -140, "我上的全部 >", "HARMFUL|PLAYER" .. NP, nil)
        P.auraOne = mk("One", -180, "只要这一个 >", "HARMFUL|PLAYER" .. NP,
            { includeSpellIDs = { [P.dotID] = true } })
    end)
    if not ok then P.auraErr = tostring(err); return false end
    P.auraBuilt = true
    P.auraShown = true
    return true
end

-- ===== 延迟探针:上了 DoT,名条上的图标慢一拍 =====
-- 🔴 **「图标什么时候出现」这个量测不出来** —— `button:IsShown()` 是 secret(2026-08-15 实测,
-- 一做布尔测试就崩)。所以本探针**不去测它**,改测「UNIT_AURA 事件几点到的」,
-- 再把「事件到了」画成屏幕上闪一下 —— 参照物必须跟图标在**同一个视野**里,
-- 否则「事件的时刻」活在聊天框、「图标的时刻」活在屏幕,两个世界没法比。
--
-- 判据(闪块 vs 你眼睛看到图标出现):
--   闪块和图标几乎同时     ⇒ 事件层没问题,慢的是暴雪容器的渲染/节流
--   闪块先亮、图标晚一拍   ⇒ 同上,而且这一拍被量化了
--   闪块本身就晚           ⇒ 慢在事件层(服务器→客户端),插件这边无能为力
local LAT_WINDOW = 4
-- 只对**真的会上 debuff 的那几个**开始计时。第一版是「arm 后第一个施法就计时」,
-- 结果采到了「触须猛击」——**量的不是他报的那个症状**,而输出看起来完全正常。
-- (canon:我这条验收路径,把那个症状执行到了吗。)
local LAT_SPELLS = { [589] = true, [34914] = true, [335467] = true }  -- 痛 / 吸血鬼之触 / 癫

local function Now()
    return (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()
end

local function LatFlash()
    if not P.latFlash then
        local t = UIParent:CreateTexture(nil, "OVERLAY")
        t:SetSize(56, 56)
        t:SetPoint("CENTER", UIParent, "CENTER", 0, 240)
        t:SetColorTexture(0.2, 1, 0.35, 0.85)
        t:Hide()
        P.latFlash = t
    end
    P.latFlash:Show()
    C_Timer.After(0.3, function() if P.latFlash then P.latFlash:Hide() end end)
end

local function LatReport()
    local L = P.lat
    if not L or not L.t0 then return end
    local rows = { string.format("|cffffff00=== DoT 上身延迟:%s ===|r", tostring(sname(L.spell))) }
    for _, r in ipairs(L.rows) do rows[#rows + 1] = r end

    -- 顺带点一下 DodoNameplate 那三个容器 —— 它们有全局名(Auras.lua 里
    -- "DodoNameplateAura"..suffix..单位号),所以外部探针够得到。
    -- ⚠ 这几个值一律走 tag(),**不许 tostring** —— 万一哪个是 secret,tostring 当场崩。
    if L.plateN then
        for _, kind in ipairs({ "Main", "CC", "Buff" }) do
            local c = _G["DodoNameplateAura" .. kind .. L.plateN]
            if c then
                local okS, shown = pcall(function() return c:IsShown() end)
                local okV, vis   = pcall(function() return c:IsVisible() end)
                local okR, reg   = pcall(function() return c:IsEventRegistered("UNIT_AURA") end)
                rows[#rows + 1] = string.format("  容器 %-5s nameplate%-3s shown=%s visible=%s UNIT_AURA注册=%s",
                    kind, L.plateN, tag(okS, shown), tag(okV, vis), tag(okR, reg))
            end
        end
    else
        rows[#rows + 1] = "  |cffff8800整个窗口里没收到任何 nameplate 的 UNIT_AURA|r"
    end

    rows[#rows + 1] = "  |cff888888对照:闪块 vs 图标,谁先谁后 —— 判据见文件里那段注释|r"
    for _, r in ipairs(rows) do print(r) end
    P.lastOut = StripColors(table.concat(rows, "\n"))
    L.t0, L.spell, L.plateN = nil, nil, nil
    -- 采完一次就**自己收摊**:disarm + 注销 UNIT_AURA。
    -- 这个插件的设计原则是「默认完全静默」,而一个采完样还常驻监听的探针不满足它 ——
    -- 战斗中 UNIT_AURA 每秒几十次,留着纯烧,而且下次谁来读代码会以为它一直在测什么。
    L.armed = false
    P:UnregisterEvent("UNIT_AURA")
    say("延迟样本收完,探针已自动收起(要再采一次就再 /dp lat)。")
end

function P:Run(phase)
    wipe(out)
    local sid = firstRotationSpell()
    local inCombat = InCombatLockdown() and "IN COMBAT" or "out of combat"

    out[#out + 1] = string.format("|cffffff00=== %s (%s) ===|r", phase, inCombat)

    -- 1. Resource / health
    probe("UnitPower(player)",        function() return UnitPower("player") end)
    probe("UnitPowerMax(player)",     function() return UnitPowerMax("player") end)
    probe("UnitHealth(player)",       function() return UnitHealth("player") end)
    probe("UnitHealth(target)",       function() return UnitHealth("target") end)

    -- 2. Cooldowns / charges on a real rotation spell
    if sid then
        out[#out + 1] = "  |cff888888(cooldown probes use spellID " .. sid .. ")|r"
        probe("C_Spell.GetSpellCooldown",  function() return C_Spell.GetSpellCooldown(sid) end)
        probe("C_Spell.GetSpellCharges",   function() return C_Spell.GetSpellCharges(sid) end)
        probe("C_Spell.IsSpellUsable",     function() return C_Spell.IsSpellUsable(sid) end)
        probe("C_UnitAuras.GetPlayerAura", function() return C_UnitAuras.GetPlayerAuraBySpellID(sid) end)
    else
        out[#out + 1] = "  |cffff3333GetRotationSpells returned nothing - cooldown probes skipped|r"
    end

    -- 3. Target auras (DoT tracking)
    probe("GetAuraDataByIndex(target,1)", function()
        return C_UnitAuras.GetAuraDataByIndex("target", 1, "HARMFUL")
    end)

    -- 4. The official rotation channel
    probe("GetNextCastSpell()",       function() return C_AssistedCombat.GetNextCastSpell() end)
    probe("GetNextCastSpell(true)",   function() return C_AssistedCombat.GetNextCastSpell(true) end)
    probe("GetActionSpell()",         function() return C_AssistedCombat.GetActionSpell() end)
    probe("IsAvailable()",            function() return C_AssistedCombat.IsAvailable() end)
    probe("#GetRotationSpells()",     function()
        local t = C_AssistedCombat.GetRotationSpells()
        return t and #t or nil
    end)

    -- 4b. IsAvailable's SECOND return (failureReason) - probe() only keeps the first,
    -- and "false + why" is the whole answer when the rotation channel is dark.
    local okA, avail, why = pcall(C_AssistedCombat.IsAvailable)
    out[#out + 1] = string.format("  %-34s %s  reason=%s",
        "IsAvailable() +reason", tag(okA, avail), tag(okA, why))

    -- 4c. THE build-or-not question: can the suggested spellID drive name + icon?
    -- Contract says GetNextCastSpell returns a plain number and GetSpellName/Texture
    -- carry no secret returns -- verify live before building an addon on it.
    local okN, nxt = pcall(C_AssistedCombat.GetNextCastSpell)
    if okN and type(nxt) == "number" then
        probe("-> GetSpellName(next)",    function() return C_Spell.GetSpellName(nxt) end)
        probe("-> GetSpellTexture(next)", function() return C_Spell.GetSpellTexture(nxt) end)
    else
        out[#out + 1] = "  |cffff3333next cast not a plain number - display chain UNTESTED|r"
    end

    -- 4d. Is the rotation list itself walkable (elements readable, not just #t)?
    local okR, rl = pcall(C_AssistedCombat.GetRotationSpells)
    if okR and type(rl) == "table" then
        local names = {}
        for i = 1, math.min(#rl, 4) do
            local okn, n = pcall(C_Spell.GetSpellName, rl[i])
            names[#names + 1] = (okn and n) and tostring(n) or "?"
        end
        out[#out + 1] = string.format("  %-34s %s", "RotationSpells names[1..4]",
            table.concat(names, ", "))
    end

    -- 6. The four inputs a predictive rotation helper needs: spell CDs / my resource /
    -- my buffs / target DoTs. Each is a separate wall - measure them separately, and do
    -- not settle for the coarse answer the earlier rows give.
    out[#out + 1] = "|cffffff00--- 四件套 ---|r"

    -- Read one field off a possibly-secret table without ever operating on the value.
    local function field(t, k)
        local ok, v = pcall(function() return t[k] end)
        return tag(ok, v)
    end

    -- 6a. CD: rows above say the TABLE is open. That says nothing about its FIELDS -
    -- an open table can hand out secret members.
    if sid then
        local okC, cd = pcall(C_Spell.GetSpellCooldown, sid)
        if okC and type(cd) == "table" then
            out[#out + 1] = string.format("  %-34s start=%s dur=%s on=%s",
                "GetSpellCooldown 里的字段",
                field(cd, "startTime"), field(cd, "duration"), field(cd, "isEnabled"))
        end
    end

    -- 6b. Resource: the predicate reads "secret for power types not explicitly flagged
    -- as never secret" - that wording implies a whitelist exists. Walk the types.
    if Enum and Enum.PowerType then
        local types = { "Mana", "Rage", "Focus", "Energy", "ComboPoints", "Runes",
            "RunicPower", "SoulShards", "HolyPower", "Chi", "Insanity",
            "ArcaneCharges", "Fury", "Pain", "Essence" }
        local open = {}
        for _, n in ipairs(types) do
            local pt = Enum.PowerType[n]
            if pt then
                local ok, v = pcall(UnitPower, "player", pt)
                if ok and v ~= nil and not (issecretvalue and issecretvalue(v)) then
                    open[#open + 1] = n .. "=" .. tostring(v)
                end
            end
        end
        out[#out + 1] = string.format("  %-34s %s", "UnitPower 明文的能量类型",
            #open > 0 and ("|cff00ff00" .. table.concat(open, ", ") .. "|r")
                       or "|cffff8800一个都没有|r")
    end

    -- 6c. Own buffs: RequiresNonSecretAura returns nothing instead of erroring, and the
    -- docs say individual spells can be flagged never-secret. So count hits, don't guess.
    local hit, tried = 0, 0
    local hitNames = {}
    local okR2, rl2 = pcall(C_AssistedCombat.GetRotationSpells)
    if okR2 and type(rl2) == "table" then
        for i = 1, #rl2 do
            tried = tried + 1
            local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, rl2[i])
            if ok and a ~= nil then
                hit = hit + 1
                -- A count answers "how many", and "how many" is useless when 1 of 12 survives
                -- combat -- the whole question is WHICH one. rl2[i] is a plain number (measured),
                -- so it can be named without ever touching the aura table itself.
                local okn, n = pcall(C_Spell.GetSpellName, rl2[i])
                hitNames[#hitNames + 1] = (okn and n) and tostring(n) or ("#" .. tostring(rl2[i]))
            end
        end
    end
    local byIndex = 0
    for i = 1, 8 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if ok and a ~= nil then byIndex = byIndex + 1 end
    end
    out[#out + 1] = string.format("  %-34s BySpellID %d/%d   ByIndex %d/8",
        "自身 buff 拿到几个", hit, tried, byIndex)
    out[#out + 1] = string.format("  %-34s %s", "  -> BySpellID 命中的是",
        #hitNames > 0 and ("|cff00ff00" .. table.concat(hitNames, ", ") .. "|r")
                       or "|cff888888(一个都没有)|r")

    -- 6d. Target DoTs: the index walk already errors. Try the other two shapes before
    -- writing it off - "one call failed" is not "the whole channel is shut".
    if sid then
        probe("目标 GetAuraDataBySpellID", function()
            return C_UnitAuras.GetAuraDataBySpellID("target", sid)
        end)
    end
    probe("目标 ByIndex HARMFUL|PLAYER", function()
        return C_UnitAuras.GetAuraDataByIndex("target", 1, "HARMFUL|PLAYER")
    end)

    -- 7. Stop guessing which things are readable: C_Secrets declares it, per spell and
    -- per power type. NeverSecret is exactly the set a monitoring UI can read real numbers
    -- from. Section 6 measures, this section asks -- when the two disagree, that gap is
    -- itself the finding (GetSpellCooldown already contradicted its own annotation once).
    if C_Secrets then
        local LV = { [0] = "|cff00ff00Never|r", [1] = "|cffff3333Always|r", [2] = "|cffffff00Ctx|r" }
        local function lv(ok, v)
            if not ok then return "|cffff3333ERR|r" end
            return LV[v] or tostring(v)
        end

        out[#out + 1] = "|cffffff00--- C_Secrets 直接问 ---|r"
        local function flag(label, fn)
            local ok, v = pcall(fn)
            out[#out + 1] = string.format("  %-34s %s", label, tag(ok, v))
        end
        flag("HasSecretRestrictions()",   C_Secrets.HasSecretRestrictions)
        flag("ShouldCooldownsBeSecret()", C_Secrets.ShouldCooldownsBeSecret)
        flag("ShouldAurasBeSecret()",     C_Secrets.ShouldAurasBeSecret)

        local okR3, rl3 = pcall(C_AssistedCombat.GetRotationSpells)
        if okR3 and type(rl3) == "table" then
            for i = 1, #rl3 do
                local id = rl3[i]
                local okN2, nm  = pcall(C_Spell.GetSpellName, id)
                local okCd, cdL = pcall(C_Secrets.GetSpellCooldownSecrecy, id)
                local okAu, auL = pcall(C_Secrets.GetSpellAuraSecrecy, id)
                -- U 列:IsSpellUsable 实测是明文布尔(没被封)。它值钱的地方在于——
                -- 如果「暗言术: 灭」这行会随目标血量翻面,那斩杀线就是明文可读的,
                -- 插件能拿它做任何运算。对满血目标和残血目标各跑一次,比这一列。
                local okUs, us = pcall(C_Spell.IsSpellUsable, id)
                out[#out + 1] = string.format("  %-18s CD=%-20s Aura=%-20s U=%s",
                    (okN2 and nm) or ("#" .. tostring(id)),
                    lv(okCd, cdL), lv(okAu, auL), tag(okUs, us))
            end

            -- 施法条整个建在 Cast 上,而上面那张表只打了 CD 和 Aura —— 没打 Cast。
            -- 谓词是按**单位**判的(查 player 不满足条件 ⇒ 明文),但契约末尾留了
            -- 「个别法术可被单独标成永远 secret」的口子。所以不用逐行加一列把表挤爆,
            -- 只列**例外**:理想输出是「一个都没有」。
            local castOdd = {}
            for i = 1, #rl3 do
                local okCa, caL = pcall(C_Secrets.GetSpellCastSecrecy, rl3[i])
                if okCa and caL ~= 0 then
                    local okn, n = pcall(C_Spell.GetSpellName, rl3[i])
                    castOdd[#castOdd + 1] = ((okn and n) or ("#" .. tostring(rl3[i])))
                        .. "=" .. (LV[caL] or tostring(caL))
                elseif not okCa then
                    castOdd[#castOdd + 1] = "#" .. tostring(rl3[i]) .. "=ERR"
                end
            end
            out[#out + 1] = string.format("  %-34s %s", "施法 secrecy 非 Never 的",
                #castOdd > 0 and ("|cffff8800" .. table.concat(castOdd, " ") .. "|r")
                              or "|cff00ff00一个都没有(全 Never)|r")
        end

        if Enum and Enum.PowerType then
            local types = { "Mana", "Rage", "Focus", "Energy", "ComboPoints", "Runes",
                "RunicPower", "SoulShards", "HolyPower", "Chi", "Insanity",
                "ArcaneCharges", "Fury", "Pain", "Essence" }
            local parts = {}
            for _, n in ipairs(types) do
                local pt = Enum.PowerType[n]
                if pt then
                    local ok, l = pcall(C_Secrets.GetPowerTypeSecrecy, pt)
                    if ok and l ~= 1 then parts[#parts + 1] = n .. "=" .. (LV[l] or tostring(l)) end
                end
            end
            out[#out + 1] = string.format("  %-34s %s", "能量类型(非 Always 的)",
                #parts > 0 and table.concat(parts, " ") or "|cffff8800全是 Always|r")
        end
    else
        out[#out + 1] = "  |cffff3333C_Secrets 不存在|r"
    end

    -- 5. Can a secret be turned into a visible colour? (the display escape hatch)
    probe("ColorCurve create",        function() return C_CurveUtil.CreateColorCurve() ~= nil end)
    -- NOTE: this row feeds a PLAINTEXT bool - `hp ~= nil` is a nil check, not a comparison
    -- of the secret, so it never exercised the secret path. Kept as the plaintext control;
    -- the real test lives in section 8 below. (Measuring something immune to the question
    -- you are asking looks exactly like a pass.)
    probe("EvalColorFromBoolean(明文对照)", function()
        local hp = UnitHealth("player")
        local c = C_CurveUtil.EvaluateColorFromBoolean(hp ~= nil,
            CreateColor(1, 0, 0, 1), CreateColor(0, 1, 0, 1))
        return c ~= nil
    end)

    -- 5b. THE key question: can a secret be rendered as visible TEXT / bar width?
    -- If SetText accepts a secret, an external reader can just read the number off the screen
    -- and no colour-encoding scheme is needed at all.
    if not P.fs then
        P.holder = CreateFrame("Frame", nil, UIParent)
        P.holder:SetSize(220, 20)
        P.holder:SetPoint("TOP", UIParent, "TOP", 0, -140)
        P.fs = P.holder:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        P.fs:SetAllPoints()
        P.bar = CreateFrame("StatusBar", nil, P.holder)
        P.bar:SetSize(220, 6)
        P.bar:SetPoint("TOP", P.holder, "BOTTOM", 0, -2)
        P.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        P.bar:SetStatusBarColor(1, 0.5, 0)
        P.bar:SetMinMaxValues(0, 100)

        -- The cooldown swipe is the single most valuable channel for CD monitoring: if it
        -- accepts a secret start/duration, the player gets a real countdown that the addon
        -- itself still cannot read. That is enough for a human-driven rotation.
        P.iconHolder = CreateFrame("Frame", nil, P.holder)
        P.iconHolder:SetSize(48, 48)
        P.iconHolder:SetPoint("TOP", P.bar, "BOTTOM", 0, -8)
        P.iconTex = P.iconHolder:CreateTexture(nil, "ARTWORK")
        P.iconTex:SetAllPoints()
        P.cd = CreateFrame("Cooldown", nil, P.iconHolder, "CooldownFrameTemplate")
        P.cd:SetAllPoints()

        -- 专给「量程能不能是 secret」用的一次性条。不能借用上面那根 P.bar:
        -- 它的量程是创建时写死的明文 0..100,改掉就把资源条那几行的读数弄脏了。
        P.probeBar = CreateFrame("StatusBar", nil, P.holder)
        P.probeBar:SetSize(1, 1)
        P.probeBar:SetPoint("TOPLEFT", P.holder, "TOPLEFT")
        P.probeBar:Hide()

        -- 分段资源条(圣能 / 连击点 / 灵魂碎片)的可行性。
        -- 形状:每段一个 StatusBar,量程各自是 [(i-1)*step, i*step],**五段全喂同一个值**。
        -- 钳制和填充比例都在 C 层算 ⇒ 插件一次比较都不做。这是「逐颗点亮」
        -- (暴雪 ClassPowerBar:TurnOn/TurnOff,需要 `i <= 当前值`)在 secret 下唯一可能的替代。
        -- 🔴 **必须两排**:只画 secret 那排的话没有判据 —— 「全空 / 全满 / 正确」三种结果
        --    在屏幕上长得都像「它本来就这样」。上排喂**明文 65** 当对照,判据就变成
        --    「两排形状一不一样」,一眼读得出。顺带它还验证了我对钳制行为的理解本身对不对。
        local function MakeSegRow(yOff, tint)
            local row = {}
            for i = 1, 5 do
                local b = CreateFrame("StatusBar", nil, P.holder)
                b:SetSize(40, 10)
                b:SetPoint("TOPLEFT", P.holder, "BOTTOMLEFT", (i - 1) * 44, yOff)
                b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                b:SetStatusBarColor(unpack(tint))
                local bg = b:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(0, 0, 0, 0.6)
                -- 量程是**明文**,每段各占全程五分之一(疯狂 0..100 ⇒ 每段 20)
                b:SetMinMaxValues((i - 1) * 20, i * 20)
                row[i] = b
            end
            return row
        end
        P.segPlain  = MakeSegRow(-80, { 0.4, 0.8, 1 })   -- 明文对照(蓝)
        P.segSecret = MakeSegRow(-94, { 1, 0.5, 0 })     -- 待验(橙)
    end
    probe("FontString:SetText(secret HP)", function()
        P.fs:SetText(UnitHealth("player"))
        return "set-ok (look at the text on screen)"
    end)
    probe("FontString:GetText() readback", function() return P.fs:GetText() end)
    probe("StatusBar:SetValue(secret pwr)", function()
        P.bar:SetValue(UnitPower("player"))
        return "set-ok (look at the bar on screen)"
    end)
    probe("StatusBar:GetValue() readback", function() return P.bar:GetValue() end)
    if sid then
        P.iconTex:SetTexture(C_Spell.GetSpellTexture(sid))
        probe("Cooldown:SetCooldown(secret)", function()
            local cd = C_Spell.GetSpellCooldown(sid)
            P.cd:SetCooldown(cd.startTime, cd.duration)
            return "set-ok (看屏幕那个图标转不转圈)"
        end)
    end

    -- 分段资源条。⚠ 结论只能从**屏幕**读:GetValue 回读的是 secret,打印出来永远是 SECRET,
    -- 那一行只证明 SetValue 没报错,不证明它画对了(跟主条那两行同一个道理)。
    probe("段条 上排:明文 65(对照)", function()
        for i = 1, 5 do P.segPlain[i]:SetValue(65) end
        return "set-ok(该看到:前 3 段满 / 第 4 段 1/4 / 第 5 段空)"
    end)
    probe("段条 下排:secret 当前资源", function()
        local v = UnitPower("player")
        for i = 1, 5 do P.segSecret[i]:SetValue(v) end
        return "set-ok(看屏幕:形状该跟上排是同一个套路)"
    end)

    -- 🔴 下排必须**持续刷新**,否则这组探针根本得不出结论:/dp 是一次快照,而
    -- 「下排全空」既可能是「资源真的是 0」(暗牧脱战就是 0)也可能是「钳制坏了」——
    -- **静态一帧里这两个长得一模一样**。唯一能把它们分开的判据是那条老规矩:
    -- 别验「画出来了」,验「它跟着资源涨落而变」。
    -- 60 秒后自停:探针不该留常驻开销(而且到时候该看的已经看完了)。
    P.segUntil = GetTime() + 60
    P.segTicker = P.segTicker or CreateFrame("Frame")
    P.segTicker:SetScript("OnUpdate", function(self)
        if GetTime() > (P.segUntil or 0) then
            self:SetScript("OnUpdate", nil)
            return
        end
        local v = UnitPower("player")
        for i = 1, 5 do P.segSecret[i]:SetValue(v) end
    end)
    out[#out + 1] = "|cff88ff88段条下排会跟着资源实时变 60 秒 —— 打两下看它涨落|r"

    out[#out + 1] = "|cffffff00--- 多职业资源条(主资源 / 次要资源 / 分段) ---|r"

    -- 契约上 UnitPowerType **零 secret 标注** ⇒ 连官方配色都该是明文。
    -- 真是的话:「换专精自动跟上」不用查专精 ID 表,配色也不用自己配二十来种。
    probe("UnitPowerType(player) 主资源", function()
        local pt, token = UnitPowerType("player")
        return string.format("%s (%s)", tostring(pt), tostring(token))
    end)
    probe("-> 官方配色 rgb", function()
        local _, _, r, g, b = UnitPowerType("player")
        return string.format("%s / %s / %s", tostring(r), tostring(g), tostring(b))
    end)
    probe("UnitPower(player,nil,true) 未缩放", function()
        return UnitPower("player", nil, true)
    end)

    -- ⚠ UnitPowerDisplayMod **不吃 unit**(契约里只有一个 powerType 参数)⇒ 在暗牧身上
    -- 也问得出毁灭术碎片的除数。毁灭术「每颗豆带进度」的本质就是:碎片值是 0..50 而不是 0..5,
    -- 这个数就是那个除数。它若明文,分段的量程边界就是**纯明文算术**,一次都不碰 secret。
    for _, n in ipairs({ "SoulShards", "HolyPower", "ComboPoints", "Chi", "ArcaneCharges", "Runes" }) do
        local pt = Enum.PowerType and Enum.PowerType[n]
        if pt then
            probe("DisplayMod(" .. n .. ")", function() return UnitPowerDisplayMod(pt) end)
        end
    end

    -- 遍历 PowerType 全集,**只报这个角色真有的**:Max 对「该单位没有的资源」返明文 0
    -- ⇒ 这一遍同时答出「本专精到底有哪些资源」,不用维护一张专精 ID 表。
    -- 全报的话是三十多行噪音,会把真东西冲掉。
    -- ⚠ mx 自己可能就是 secret ⇒ 比大小**之前**必须先问 issecretvalue,否则探针自己崩;
    --   而且那种情况要如实报一行(「判不了」跟「没有这资源」是两回事)。
    local kinds = {}
    for n, v in pairs(Enum.PowerType or {}) do
        if type(v) == "number" and v >= 0 then kinds[#kinds + 1] = { n, v } end
    end
    table.sort(kinds, function(a, b) return a[2] < b[2] end)
    for _, e in ipairs(kinds) do
        local n, pt = e[1], e[2]
        local okM, mx = pcall(UnitPowerMax, "player", pt)
        if okM and type(mx) == "number" then
            if issecretvalue and issecretvalue(mx) then
                probe("? " .. n .. " max=SECRET(有没有这资源判不了)", function() return mx end)
            elseif mx > 0 then
                probe("有 " .. n .. "  max", function() return mx end)
                probe("   " .. n .. "  cur", function() return UnitPower("player", pt) end)
                probe("   " .. n .. "  cur(未缩放)", function() return UnitPower("player", pt, true) end)
            end
        end
    end

    -- 资源配色。`UnitPowerType` 的 rgb 实测是 nil,所以颜色只能另找路 ——
    -- `PowerBarColor` 是全局表,key 就是 UnitPowerType 给的那个 token。
    -- ⚠ 这一组是**摸清有没有**,不是打算直接拿来用:官方色是给暴雪那种带厚金属边框 +
    -- 不透明底的框体调的,搬到一根裸条上会糊(疯狂条就是这么从官方 atlas 退回
    -- 素图 + 自选亮紫的,理由见 DodoCombatHUD 的 DEFAULTS.powerTexture)。
    if type(PowerBarColor) == "table" then
        local seen = 0
        for _, tk in ipairs({ "MANA", "RAGE", "FOCUS", "ENERGY", "COMBO_POINTS", "RUNES",
                              "RUNIC_POWER", "SOUL_SHARDS", "LUNAR_POWER", "HOLY_POWER",
                              "MAELSTROM", "CHI", "INSANITY", "ARCANE_CHARGES",
                              "FURY", "PAIN", "ESSENCE" }) do
            local c = PowerBarColor[tk]
            seen = seen + 1
            probe("PowerBarColor." .. tk, function()
                if type(c) ~= "table" then return "nil" end
                return string.format("r=%.2f g=%.2f b=%.2f%s",
                    c.r or -1, c.g or -1, c.b or -1,
                    c.atlas and (" atlas=" .. tostring(c.atlas)) or "")
            end)
        end
        -- 反空转:一个都没查等于这组探针没跑,而「没跑」跟「全是 nil」在输出里长得一样
        if seen == 0 then out[#out + 1] = "  |cffff5555(PowerBarColor 一个 token 都没查 = 探针空转)|r" end
    else
        out[#out + 1] = "  |cffff5555PowerBarColor 这张表不存在|r"
    end

    -- 8. Threshold cues for a self-drawn resource bar. Bar LENGTH needs no math
    -- (SetMinMaxValues + SetValue both take secrets), but "go red near overcap" needs a
    -- path from a secret NUMBER to a visual. The generated contract says both curve
    -- Evaluate methods are AllowedWhenUntainted = addons cannot feed them. Contract has
    -- been wrong once already (GetSpellCooldown), so measure it instead of quoting it.
    out[#out + 1] = "|cffffff00--- HUD 阈值提示可行性 ---|r"

    local okCC, curve = pcall(C_CurveUtil.CreateColorCurve)
    if okCC and curve then
        pcall(function()
            curve:AddPoint(0, CreateColor(0.2, 0.6, 1.0, 1))
            curve:AddPoint(100, CreateColor(1.0, 0.2, 0.1, 1))
        end)
        -- Plaintext x first. Without it, a failure on the secret row could just mean
        -- "my curve was built wrong" - which reads identical to "secrets are blocked".
        probe("Curve:Evaluate(明文 50) 负对照", function()
            return curve:Evaluate(50) ~= nil and "ok" or "nil"
        end)
        probe("Curve:Evaluate(secret 资源)", function()
            return curve:Evaluate(UnitPower("player")) ~= nil and "ok" or "nil"
        end)
        probe("curve:HasSecretValues()", function() return curve:HasSecretValues() end)
    end

    -- EvaluateColorFromBoolean IS AllowedWhenTainted - but an addon has to obtain a secret
    -- BOOLEAN first, and comparing a secret number is a hard error. So: which API hands
    -- one out? IsSpellUsable is the candidate that matters (execute-range cue).
    if sid then
        local okU, usable = pcall(C_Spell.IsSpellUsable, sid)
        out[#out + 1] = string.format("  %-34s %s", "IsSpellUsable 给的是不是 secret bool",
            tag(okU, usable))
        probe("EvalColorFromBoolean(那个返回值)", function()
            local u = C_Spell.IsSpellUsable(sid)
            return C_CurveUtil.EvaluateColorFromBoolean(u,
                CreateColor(1, 0, 0, 1), CreateColor(0, 1, 0, 1)) ~= nil and "ok" or "nil"
        end)
    end

    -- 血条的唯一闸门。资源条走通了**不替血条背书**:那次的量程是明文(UnitPowerMax=100),
    -- 而 UnitHealthMax 很可能是 secret ⇒ 血条走的是 SetMinMaxValues(0, secret),没测过。
    -- ⚠ 这几行要**选中一个目标**才有意义;没目标时 UnitHealthMax 返 nil,读起来像被封了。
    probe("UnitHealthMax(target)", function() return UnitHealthMax("target") end)
    probe("UnitHealthMax(player)", function() return UnitHealthMax("player") end)
    if UnitExists("target") then
        probe("SetMinMaxValues(0, secret 血上限)", function()
            P.probeBar:SetMinMaxValues(0, UnitHealthMax("target"))
            return "set-ok"
        end)
        -- 回读:set-ok 只说明「调用没被拒」。最阴的失败是**默默不接受**(当成 0)——
        -- 那样条会恒满或恒空,零报错。回读拿到 SECRET 才说明它真收下了那个值。
        probe("-> GetMinMaxValues() 回读上限", function()
            local _, hi = P.probeBar:GetMinMaxValues()
            return hi
        end)
    else
        out[#out + 1] = "  |cffff8800(没选目标 —— 血条那几行跳过了,选个怪再跑一次)|r"
    end

    -- Two more secret-eating setters off the whitelist. Both clamp to 0..1 and we feed a
    -- 0..100 resource, so the SCREEN tells you nothing here - the only question this row
    -- answers is "does the call go through with a secret at all".
    probe("StatusBar:SetStatusBarDesaturation", function()
        P.bar:SetStatusBarDesaturation(UnitPower("player"))
        return "set-ok"
    end)
    probe("Texture:SetRadialProgressBarPercent", function()
        P.iconTex:SetRadialProgressBarPercent(UnitPower("player"))
        return "set-ok"
    end)

    -- ===== B. 报告(容器本体见文件上方 EnsureAuraProbe)=====
    out[#out + 1] = "|cffffff00--- B. AuraContainer + SetUnit(\"target\") ---|r"
    out[#out + 1] = string.format("  被筛的 DoT id=%d 名字=%s |cff888888(名字不对就 /dp dot <id>)|r",
        P.dotID, tostring(sname(P.dotID)))
    if not EnsureAuraProbe() then
        out[#out + 1] = "  |cffff3333建不起来: " .. tostring(P.auraErr) .. "|r"
    else
        -- 🔴 「数出显示着几个」办不到:`button:IsShown()` 返回 **secret boolean**,一做布尔测试
        -- 就是 "attempt to perform boolean test on a secret boolean value"(2026-08-15 实测,
        -- 第一版就是这么炸的,还把它后面的 A / C 两组一起带没了)。
        -- 合理 —— 可见性本身就泄露「这个光环在不在」。⇒ 本组的判据**只能是眼睛看屏幕**,
        -- 跟「挡的是读了去算,不挡画给人看」是同一件事的两面。
        -- 池大小是明文,但它只说「暴雪替这一组备过几个按钮」,不说现在显示几个。
        pcall(function()
            P.auraAny:UpdateAllAuras(); P.auraAll:UpdateAllAuras(); P.auraOne:UpdateAllAuras()
        end)
        out[#out + 1] = string.format("  1 任何 harmful       按钮池 %d", #P.auraAny.dpButtons)
        out[#out + 1] = string.format("  2 我上的全部         按钮池 %d", #P.auraAll.dpButtons)
        out[#out + 1] = string.format("  3 只要这一个         按钮池 %d", #P.auraOne.dpButtons)
        probe("button:IsShown() 的类型", function()
            local b = P.auraAny.dpButtons[1]
            return b and b:IsShown()
        end)
        out[#out + 1] = "  |cffffff00判据在屏幕上(中上三行图标),不在这几个数字里:|r"
        out[#out + 1] = "  |cffffff00  2 有 3 个、3 只有 1 个(吸血鬼之触) = includeSpellIDs 生效|r"
        out[#out + 1] = "  |cffffff00  三行都空 = 容器绑 \"target\" 不通 / 1 有而 2 空 = 过滤串的问题|r"
        out[#out + 1] = "  |cff888888顺带看图标上转不转圈 —— 那是我们自己画不出来的那样东西|r"
    end

    -- ===== A. C_CooldownViewer 数据集:暴雪自己会不会追「我打在目标身上的光环」 =====
    -- 实现侧证据说会(CooldownViewerItemData.lua:1 `scanUnits = {"player","target"}`;:17
    -- 要求 `auraData.sourceUnit == "player"`;:1094 `return self:GetAuraDataUnit() == "target"`)。
    -- 这里量的是**那两个 DoT 在不在它的数据表里** —— 不在的话上面那条实现证据对我们没用。
    -- ⚠ 每行末尾的「N 项」是口径验证:全 0 = 我枚举方式错了,不是「暴雪没数据」。
    out[#out + 1] = "|cffffff00--- A. C_CooldownViewer 数据集 ---|r"
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet) then
        out[#out + 1] = "  |cffff3333C_CooldownViewer 不存在|r"
    else
        local nonSelf = {}
        for cname, cval in pairs(Enum.CooldownViewerCategory or {}) do
            local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cval, true)
            if not ok or type(ids) ~= "table" then
                out[#out + 1] = string.format("  %-24s |cffff3333查不到|r", cname)
            else
                for _, id in ipairs(ids) do
                    local ok2, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
                    if ok2 and info and info.hasAura and not info.selfAura then
                        -- 分类是这里唯一还缺的那个字段:它决定这几个 DoT 能不能被单独摆位置
                        -- (布局 blob 里没有 x/y,分开摆只能走分类)。
                        nonSelf[#nonSelf + 1] = string.format("    %s  spellID=%s  分类=%s  cdID=%d",
                            tostring(sname(info.spellID) or "?"), tostring(info.spellID), cname, id)
                    end
                end
                -- 只报计数,不再把整个分类的法术名串出来 —— 那一串会把后面的结论挤出聊天框。
                -- 计数仍然是口径验证:全 0 = 我枚举方式错了,不是「暴雪没数据」。
                out[#out + 1] = string.format("  %-26s %d 项", cname, #ids)
            end
        end
        out[#out + 1] = "  |cffffff00hasAura 且 NOT selfAura(= 追的是别人身上的光环):|r"
        if #nonSelf == 0 then
            out[#out + 1] = "    |cff888888一个都没有|r"
        else
            for _, l in ipairs(nonSelf) do out[#out + 1] = l end
        end
    end

    -- ===== C. 斩杀技的 usable 会不会随目标血量翻面 =====
    -- 验法:对**满血**目标跑一次、对**残血**目标再跑一次,只比这一行。翻面 = 斩杀线明文可读,
    -- HUD 那条 20% 线就能从「一根静态刻度」升级成「真的会闪」。
    out[#out + 1] = "|cffffff00--- C. 斩杀技 usable 翻面 ---|r"
    out[#out + 1] = string.format("  斩杀技 id=%d 名字=%s |cff888888(名字不对就 /dp exec <id>)|r",
        P.execID, tostring(sname(P.execID)))
    probe("IsSpellUsable(斩杀技)", function() return C_Spell.IsSpellUsable(P.execID) end)
    probe("目标存在", function() return UnitExists("target") end)

    for _, line in ipairs(out) do print(line) end
    P.lastOut = StripColors(table.concat(out, "\n"))
    say("done.  |cffffff00/dp copy|r 弹出可复制的窗口(聊天框滚不动的话用它)")
end

-- Silent by default: this addon ships in the monorepo and syncs to every machine,
-- so it must never print anything unless explicitly asked. /dp arm = one-shot combat run.
P:RegisterEvent("PLAYER_ENTERING_WORLD")
P:RegisterEvent("PLAYER_REGEN_DISABLED")
P:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
-- The container registers UNIT_AURA for its own unit token but NOT PLAYER_TARGET_CHANGED,
-- so on a target swap it keeps showing the previous target's auras until the new target's
-- next aura event. Blizzard exposes UpdateAllAuras for exactly this ("e.g. target changes"
-- -- AuraContainerSharedMixin). Doing it here also puts that fix under test.
P:RegisterEvent("PLAYER_TARGET_CHANGED")

P:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        say("ready (silent).  /dp = run now   |   /dp arm = run once in next combat")
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Stay armed until a sample actually lands IN combat. A flat 3s timer can fire
        -- after a short fight already ended, which stamps a "COMBAT" header on an
        -- out-of-combat sample: a run that reports success while the condition under
        -- test was never present. Verify at fire time, re-arm otherwise.
        if P.armed then
            C_Timer.After(3, function()
                if not P.armed then return end
                if InCombatLockdown() then
                    P.armed = false
                    P:Run("COMBAT")
                else
                    say("that fight ended before the 3s mark - still armed, pull something tankier.")
                end
            end)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if P.auraBuilt then
            pcall(function()
                P.auraAny:UpdateAllAuras(); P.auraAll:UpdateAllAuras(); P.auraOne:UpdateAllAuras()
            end)
        end
    elseif event == "UNIT_AURA" then
        -- ⚠ 只取 unit,**绝不碰第二个参数**(受限时那个 updateInfo 是 secret)。
        local unit = ...
        local L = P.lat
        if L and L.armed and L.t0 and type(unit) == "string" then
            if unit == "target" or unit:find("^nameplate") then
                local dt = Now() - L.t0
                if dt <= LAT_WINDOW then
                    L.rows[#L.rows + 1] = string.format("  t=%.3f  UNIT_AURA  %s", dt, unit)
                    LatFlash()
                end
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        local L = P.lat
        if unit == "player" and L and L.armed and not L.t0 and LAT_SPELLS[spellID] then
            L.t0, L.spell = Now(), spellID
            -- 目标那个 nameplate 的 token **在这一刻**就取下来。上一版是「记最后一个收到
            -- UNIT_AURA 的 nameplate」,而周围的怪一直在刷事件 ⇒ 最后留下的是隔壁那只,
            -- 于是容器状态那三行查了个不相干的单位,还看着挺像回事。
            local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
                and C_NamePlate.GetNamePlateForUnit("target")
            L.plateN = plate and plate.namePlateUnitToken
                and plate.namePlateUnitToken:match("^nameplate(%d+)") or nil
            L.rows = { string.format("  t=0.000  施法成功  %s (%s)%s",
                tostring(sname(spellID)), tostring(spellID),
                L.plateN and ("   目标 = nameplate" .. L.plateN) or "   |cffff8800目标没有名条|r") }
            C_Timer.After(LAT_WINDOW, LatReport)
        end
        if unit == "player" and P.watchCast then
            P.watchCast = false
            say("own cast spellID -> " .. tag(true, spellID) .. "   (is my own cast readable?)")
        end
    end
end)

SLASH_DODOPROBE1 = "/dp"
SLASH_DODOPROBE2 = "/dodoprobe"
SlashCmdList.DODOPROBE = function(msg)
    local cmd, arg = string.lower(msg or ""):match("^%s*(%a*)%s*(%d*)")
    arg = tonumber(arg)
    if cmd == "lat" then
        P.lat = P.lat or { rows = {} }
        P.lat.armed = not P.lat.armed
        P.lat.t0, P.lat.spell, P.lat.plateN = nil, nil, nil
        if P.lat.armed then
            -- 只在武装时注册:UNIT_AURA 在战斗中极频繁,常驻监听纯属白烧。
            P:RegisterEvent("UNIT_AURA")
            say("延迟探针已武装 —— |cffffff00选中目标,放「痛」/「吸血鬼之触」/「癫」其中一个|r。"
                .. "别的技能不会触发计时(上一版就是这么采到了触须猛击)。")
            say("屏幕上方会在每次 UNIT_AURA 到达时闪一个绿块 —— |cffffff00盯着它和名条图标谁先谁后|r。")
        else
            P:UnregisterEvent("UNIT_AURA")
            say("延迟探针关了。")
        end
    elseif cmd == "copy" then
        if P.lastOut then
            ShowCopyBox(P.lastOut)
        else
            say("nothing captured yet -- run /dp first.")
        end
    elseif cmd == "arm" then
        P.armed, P.watchCast = true, true
        say("armed. Pull a mob -- runs once 3s into combat, then disarms itself.")
    elseif cmd == "dot" and arg then
        P.dotID = arg
        if P.auraBuilt then
            pcall(function()
                P.auraOne:SetAuraGroupCandidateFilters("g", { includeSpellIDs = { [P.dotID] = true } })
            end)
        end
        say("dot id -> " .. P.dotID .. "  (" .. tostring(sname(P.dotID)) .. ")")
    elseif cmd == "exec" and arg then
        P.execID = arg
        say("exec id -> " .. P.execID .. "  (" .. tostring(sname(P.execID)) .. ")")
    elseif cmd == "aura" then
        if P.auraBuilt then
            P.auraShown = not P.auraShown
            pcall(function()
                P.auraAny:SetEnabled(P.auraShown)
                P.auraAll:SetEnabled(P.auraShown)
                P.auraOne:SetEnabled(P.auraShown)
            end)
            say("aura probe rows -> " .. (P.auraShown and "on" or "off"))
        else
            say("aura probe not built yet -- run /dp once out of combat first.")
        end
    else
        P.watchCast = true
        P:Run("MANUAL")
    end
end
