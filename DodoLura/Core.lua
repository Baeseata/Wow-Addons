-- DodoLura: air-horn alert when YOU are targeted by Starsplinter (spell 1282441)
-- on the L'ura / Midnight Falls encounter (encounterID 3183). Zero settings.
-- Targeting is a private aura (1279512/1285510) - addons cannot read the aura;
-- the only sanctioned channel is C_UnitAuras.AddPrivateAuraAppliedSound, which
-- hands the sound to the game engine per spellID: no events, no polling, no
-- addon-side option layers in between.
-- AirHorn.ogg by Mike Koenig, CC-BY 3.0 (same file DBM ships); bundled so we
-- do not depend on DBM's file path.

local ENCOUNTER_ID = 3183 -- Midnight Falls / 至暗之夜(鲁拉)
local PRIVATE_AURAS = { 1279512, 1285510 } -- Starsplinter target PAs, both variants
local SOUND = "Interface\\AddOns\\DodoLura\\AirHorn.ogg"

local zh = GetLocale():find("^zh") ~= nil
local L_READY = zh and "已就位:被星辰裂片点名会吹喇叭"
    or "armed: the air horn sounds when Starsplinter targets you"
local L_TEST = zh and "试音:点名时就是这个声"
    or "sound check: this is what you will hear"

local soundHandles = {}

local function Register()
    if #soundHandles > 0 then return end
    for _, spellID in ipairs(PRIVATE_AURAS) do
        local handle = C_UnitAuras.AddPrivateAuraAppliedSound({
            unitToken = "player",
            spellID = spellID,
            soundFileName = SOUND,
            outputChannel = "Master",
        })
        if handle then
            soundHandles[#soundHandles + 1] = handle
        end
    end
end

local function Unregister()
    for i = #soundHandles, 1, -1 do
        C_UnitAuras.RemovePrivateAuraAppliedSound(soundHandles[i])
        soundHandles[i] = nil
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ENCOUNTER_START")
f:RegisterEvent("ENCOUNTER_END")
f:RegisterEvent("PLAYER_ENTERING_WORLD") -- safety cleanup: mid-fight /reload, leaving the instance
f:SetScript("OnEvent", function(_, event, encounterID)
    if event == "ENCOUNTER_START" and encounterID == ENCOUNTER_ID then
        Register()
        print("|cFF33FF99DodoLura|r " .. L_READY)
    elseif event ~= "ENCOUNTER_START" then
        Unregister()
    end
end)

-- /dodolura plays the horn once (volume/file sanity check, not a settings UI)
SLASH_DODOLURA1 = "/dodolura"
SlashCmdList.DODOLURA = function()
    PlaySoundFile(SOUND, "Master")
    print("|cFF33FF99DodoLura|r " .. L_TEST)
end
