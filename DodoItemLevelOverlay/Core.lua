-- DodoItemLevelOverlay - Core.lua
-- SavedVariables, event wiring and refresh entry points.

local ADDON_NAME, ns = ...

-- Everything anchored to the character frame: the equipment slot
-- overlays and the gear summary side panel.
function ns.UpdateCharacterViews()
    ns.UpdateEquipment()
    ns.UpdateSidePanel()
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
    DodoItemLevelOverlayDB = DodoItemLevelOverlayDB or {}
    ns.SetLocale(DodoItemLevelOverlayDB.locale or ns.DEFAULT_LOCALE)
    ns.RegisterOptions()
end

local function OnLogin()
    ns.HookBagFrames()
    ns.SetupSidePanel()

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
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
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
    ns.UpdateAllVisible()
end)
