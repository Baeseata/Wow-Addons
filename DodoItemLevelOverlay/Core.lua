-- DodoItemLevelOverlay - Core.lua
-- Event wiring and refresh entry points.

local _, ns = ...

function ns.UpdateAllVisible()
    if CharacterFrame and CharacterFrame:IsShown() then
        ns.UpdateEquipment()
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

local function OnLogin()
    ns.HookBagFrames()

    -- refresh equipment overlays when the character frame opens
    if CharacterFrame and CharacterFrame.HookScript then
        CharacterFrame:HookScript("OnShow", function()
            C_Timer.After(0, ns.UpdateEquipment)
        end)
    end
    if PaperDollFrame and PaperDollFrame.HookScript then
        PaperDollFrame:HookScript("OnShow", function()
            C_Timer.After(0, ns.UpdateEquipment)
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
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED") -- uncached item info arriving

frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        OnLogin()
        return
    end
    ns.UpdateAllVisible()
end)
