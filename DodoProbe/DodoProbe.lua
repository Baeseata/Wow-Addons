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
        if P.armed then
            P.armed = false
            C_Timer.After(3, function() P:Run("COMBAT") end)
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
