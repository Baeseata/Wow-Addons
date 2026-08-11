-- DodoLura: air-horn alert when YOU are targeted by Starsplinter (spell 1282441)
-- on the L'ura / Midnight Falls encounter (encounterID 3183). Zero settings.
-- Targeting is a private aura (1279512/1285510) - addons cannot read the aura;
-- the sanctioned channel is C_UnitAuras.AddAuraSound (12.1+) or its 12.0.x
-- predecessor, C_UnitAuras.AddPrivateAuraAppliedSound. Both hand the sound to
-- the game engine per spellID: no polling or addon-side alert layers.
-- Adding aura sounds is restricted during encounters, so we pre-register while
-- the player is inside March on Quel'Danas and remove them on leaving the zone.
-- AirHorn.ogg by Mike Koenig, CC-BY 3.0 (same file DBM ships); bundled so we
-- do not depend on DBM's file path.

local INSTANCE_ID = 2913 -- March on Quel'Danas
local PRIVATE_AURAS = { 1279512, 1285510 } -- Starsplinter target PAs, both variants
local SOUND = "Interface\\AddOns\\DodoLura\\AirHorn.ogg"

local AddAuraSound = C_UnitAuras.AddAuraSound
local AddLegacyAuraSound = C_UnitAuras.AddPrivateAuraAppliedSound
local RemoveAuraSound = C_UnitAuras.RemoveAuraSound
    or C_UnitAuras.RemovePrivateAuraAppliedSound
local InChatMessagingLockdown = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    or function() return false end
local AURA_ADDED = Enum and Enum.UnitAuraSoundTrigger
    and Enum.UnitAuraSoundTrigger.Added or 0
local CHAT_RESTRICTION = Enum and Enum.AddOnRestrictionType
    and Enum.AddOnRestrictionType.Chat or 5
local RESTRICTION_INACTIVE = Enum and Enum.AddOnRestrictionState
    and Enum.AddOnRestrictionState.Inactive or 0

local zh = GetLocale():find("^zh") ~= nil
local L_READY = zh and "已就位:被星辰裂片点名会吹喇叭"
    or "armed: the air horn sounds when Starsplinter targets you"
local L_TEST = zh and "试音:点名时就是这个声"
    or "sound check: this is what you will hear"

local f = CreateFrame("Frame")
local soundHandles = {} -- keyed by spellID so a partial registration can be retried
local announced = false

local function IsFullyRegistered()
    for _, spellID in ipairs(PRIVATE_AURAS) do
        if not soundHandles[spellID] then
            return false
        end
    end
    return true
end

local function Register()
    if IsFullyRegistered() then return end
    if InChatMessagingLockdown() then
        -- A /reload during a pull cannot add sounds immediately. Retry as soon
        -- as Blizzard lifts the chat/encounter restriction, ready for next pull.
        f:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
        return
    end

    for _, spellID in ipairs(PRIVATE_AURAS) do
        if not soundHandles[spellID] then
            local soundInfo = {
                unitToken = "player",
                spellID = spellID,
                soundFileName = SOUND,
                outputChannel = "Master",
            }
            local handle
            if AddAuraSound then
                handle = AddAuraSound(AURA_ADDED, soundInfo)
            elseif AddLegacyAuraSound then
                handle = AddLegacyAuraSound(soundInfo)
            end
            if handle then
                soundHandles[spellID] = handle
            end
        end
    end

    if IsFullyRegistered() then
        f:UnregisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
        if not announced then
            announced = true
            print("|cFF33FF99DodoLura|r " .. L_READY)
        end
    end
end

local function Unregister()
    for spellID, handle in pairs(soundHandles) do
        if RemoveAuraSound then
            RemoveAuraSound(handle)
        end
        soundHandles[spellID] = nil
    end
    announced = false
end

local function UpdateZone()
    local instanceID = select(8, GetInstanceInfo())
    if instanceID == INSTANCE_ID then
        Register()
    else
        f:UnregisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
        Unregister()
    end
end

f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:SetScript("OnEvent", function(_, event, restrictionType, state)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        if restrictionType == CHAT_RESTRICTION and state == RESTRICTION_INACTIVE then
            f:UnregisterEvent(event)
            UpdateZone()
        end
    else
        UpdateZone()
    end
end)

-- /dodolura plays the horn once (volume/file sanity check, not a settings UI)
SLASH_DODOLURA1 = "/dodolura"
SlashCmdList.DODOLURA = function()
    PlaySoundFile(SOUND, "Master")
    print("|cFF33FF99DodoLura|r " .. L_TEST)
end
