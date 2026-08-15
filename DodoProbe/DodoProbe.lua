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

-- Pull one real rotational spell id so cooldown/aura probes hit something that exists.
local function firstRotationSpell()
    if not C_AssistedCombat or not C_AssistedCombat.GetRotationSpells then return nil end
    local ok, t = pcall(C_AssistedCombat.GetRotationSpells)
    if ok and type(t) == "table" and t[1] then return t[1] end
    return nil
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
    local okR2, rl2 = pcall(C_AssistedCombat.GetRotationSpells)
    if okR2 and type(rl2) == "table" then
        for i = 1, #rl2 do
            tried = tried + 1
            local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, rl2[i])
            if ok and a ~= nil then hit = hit + 1 end
        end
    end
    local byIndex = 0
    for i = 1, 8 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if ok and a ~= nil then byIndex = byIndex + 1 end
    end
    out[#out + 1] = string.format("  %-34s BySpellID %d/%d   ByIndex %d/8",
        "自身 buff 拿到几个", hit, tried, byIndex)

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
                out[#out + 1] = string.format("  %-18s CD=%-24s Aura=%s",
                    (okN2 and nm) or ("#" .. tostring(id)), lv(okCd, cdL), lv(okAu, auL))
            end
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
    probe("EvalColorFromBoolean",     function()
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

    for _, line in ipairs(out) do print(line) end
    say("done. Copy the block above.")
end

-- Silent by default: this addon ships in the monorepo and syncs to every machine,
-- so it must never print anything unless explicitly asked. /dp arm = one-shot combat run.
P:RegisterEvent("PLAYER_ENTERING_WORLD")
P:RegisterEvent("PLAYER_REGEN_DISABLED")
P:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

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
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" and P.watchCast then
            P.watchCast = false
            say("own cast spellID -> " .. tag(true, spellID) .. "   (is my own cast readable?)")
        end
    end
end)

SLASH_DODOPROBE1 = "/dp"
SLASH_DODOPROBE2 = "/dodoprobe"
SlashCmdList.DODOPROBE = function(msg)
    if string.find(string.lower(msg or ""), "arm") then
        P.armed, P.watchCast = true, true
        say("armed. Pull a mob -- runs once 3s into combat, then disarms itself.")
    else
        P.watchCast = true
        P:Run("MANUAL")
    end
end
