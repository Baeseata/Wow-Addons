-- DodoItemLevelOverlay - Bags.lua
-- Overlays on the default Blizzard bags (combined and separated).

local _, ns = ...

local function UpdateItemButton(itemButton, frame)
    local bagID = (itemButton.GetBagID and itemButton:GetBagID())
        or (frame.GetID and frame:GetID())
    local slot = (itemButton.GetID and itemButton:GetID()) or nil

    if type(bagID) ~= "number" or type(slot) ~= "number" or slot <= 0 then
        ns.ClearAllOverlays(itemButton)
        return
    end

    local itemLink
    if C_Container and C_Container.GetContainerItemLink then
        itemLink = C_Container.GetContainerItemLink(bagID, slot)
    end

    -- empty slot or non-equippable item: nothing to show
    if not itemLink or not IsEquippableItem(itemLink) then
        ns.ClearAllOverlays(itemButton)
        return
    end

    -- junk filter: gray and white quality gear gets no overlays at
    -- all, so a bare icon reads as "safe to vendor"
    if ns.Config.HIDE_JUNK_QUALITY then
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if ns.IsJunkQuality(info and info.quality) then
            ns.ClearAllOverlays(itemButton)
            return
        end
    end

    local itemLoc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
    ns.SetItemLevelText(itemButton, ns.GetItemLevel(itemLoc))

    -- bottom-left tag: unbound BOE wins over equipment set name
    if ns.IsUnboundBOE(bagID, slot, itemLink) then
        ns.SetTagText(itemButton, "boe")
    else
        local setName = ns.GetEquipmentSetName(bagID, slot)
        if setName then
            ns.SetTagText(itemButton, "set", setName)
        else
            ns.SetTagText(itemButton, nil)
        end
    end

    ns.SetSlotText(itemButton, ns.GetSlotLabel(itemLink))
end

function ns.UpdateBagFrame(frame)
    if not frame or not frame.IsShown or not frame:IsShown() then return end
    if type(frame.EnumerateValidItems) ~= "function" then return end

    for _, itemButton in frame:EnumerateValidItems() do
        if itemButton then
            UpdateItemButton(itemButton, frame)
        end
    end
end

function ns.HookBagFrames()
    -- combined bag frame
    if _G.ContainerFrameCombinedBags and _G.ContainerFrameCombinedBags.UpdateItems then
        hooksecurefunc(_G.ContainerFrameCombinedBags, "UpdateItems", ns.UpdateBagFrame)
    end

    -- separated bag frames
    local container = _G.ContainerFrameContainer
    if container and container.ContainerFrames then
        for _, frame in ipairs(container.ContainerFrames) do
            if frame and frame.UpdateItems then
                hooksecurefunc(frame, "UpdateItems", ns.UpdateBagFrame)
            end
        end
    end
end
