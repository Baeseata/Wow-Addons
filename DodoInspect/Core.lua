-- DodoInspect - Core.lua
-- SavedVariables, event wiring and refresh entry points.

local ADDON_NAME, ns = ...

-- Feature toggles stored in SavedVariables. Only an explicit false
-- disables a feature, so fresh installs (and sessions before the DB
-- loads) default to everything on. Keys: showEquipmentIlvl,
-- showBagOverlays, showSidePanel, showDurability, showStatRatings.
function ns.IsEnabled(flag)
    local db = DodoInspectDB
    return not db or db[flag] ~= false
end

-- Per-panel font size, read from SavedVariables with the Config default
-- as the fallback, clamped to the configured bounds. The character side
-- panel (SidePanel) and the inspect side panel (InspectPanel) each have
-- their own override so they can be sized independently from the options
-- panel; both default to Config.PANEL_FONT_SIZE when unset.
local function PanelFontSize(dbKey)
    local cfg = ns.Config
    local db = DodoInspectDB
    local size = (db and tonumber(db[dbKey])) or cfg.PANEL_FONT_SIZE
    if size < cfg.PANEL_FONT_MIN then size = cfg.PANEL_FONT_MIN end
    if size > cfg.PANEL_FONT_MAX then size = cfg.PANEL_FONT_MAX end
    return size
end

function ns.SidePanelFontSize()
    return PanelFontSize("sidePanelFontSize")
end

function ns.InspectPanelFontSize()
    return PanelFontSize("inspectPanelFontSize")
end

-- Everything anchored to the character frame: the equipment slot
-- overlays and the gear summary side panel.
function ns.UpdateCharacterViews()
    ns.UpdateEquipment()
    ns.UpdateSidePanel()
    ns.UpdateDurability()
end

function ns.UpdateAllVisible()
    if CharacterFrame and CharacterFrame:IsShown() then
        ns.UpdateCharacterViews()
    end

    if _G.ContainerFrameCombinedBags and _G.ContainerFrameCombinedBags:IsShown() then
        ns.UpdateBagFrame(_G.ContainerFrameCombinedBags)
    end

    local container = _G.ContainerFrameContainer
    if container and container.ContainerFrames then
        for _, frame in ipairs(container.ContainerFrames) do
            if frame and frame:IsShown() then
                ns.UpdateBagFrame(frame)
            end
        end
    end
end

local function OnAddonLoaded()
    -- SavedVariables are available from this point on
    DodoInspectDB = DodoInspectDB or {}
    ns.SetLocale(DodoInspectDB.locale or ns.DEFAULT_LOCALE)
    ns.RegisterOptions()
end

local function OnLogin()
    ns.HookBagFrames()
    ns.SetupSidePanel()
    ns.SetupStatRatings()
    ns.SetupLootSource()

    -- refresh the character views when the character frame opens
    if CharacterFrame and CharacterFrame.HookScript then
        CharacterFrame:HookScript("OnShow", function()
            C_Timer.After(0, ns.UpdateCharacterViews)
        end)
    end
    if PaperDollFrame and PaperDollFrame.HookScript then
        PaperDollFrame:HookScript("OnShow", function()
            C_Timer.After(0, ns.UpdateCharacterViews)
        end)
    end

    -- refresh when bags open or toggle
    local openers = {
        "ToggleBackpack", "OpenBackpack", "ToggleAllBags",
        "OpenAllBags", "OpenBag", "ToggleBag",
    }
    for _, fn in ipairs(openers) do
        if type(_G[fn]) == "function" then
            hooksecurefunc(fn, function()
                C_Timer.After(0, ns.UpdateAllVisible)
            end)
        end
    end

    C_Timer.After(0, ns.UpdateAllVisible)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
frame:RegisterEvent("PLAYER_REGEN_ENABLED") -- combat end: re-add stat ratings
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED") -- refresh the stat priority line
frame:RegisterEvent("TRAIT_CONFIG_UPDATED") -- hero talent / loadout change: re-pick the build
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED") -- uncached item info arriving
frame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player") -- enchant / gem changes

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            OnAddonLoaded()
            frame:UnregisterEvent("ADDON_LOADED")
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        OnLogin()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        -- defer a frame so combat lockdown has fully cleared before we
        -- read the (now non-secret) ratings
        C_Timer.After(0, ns.RefreshStatRatings)
        return
    end
    if event == "GET_ITEM_INFO_RECEIVED"
        or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "TRAIT_CONFIG_UPDATED"
        or event == "PLAYER_EQUIPMENT_CHANGED" then
        ns.RefreshGearPanelIfShown()
    end
    ns.UpdateAllVisible()
end)
