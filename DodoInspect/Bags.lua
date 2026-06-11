-- DodoInspect - Bags.lua
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

    if not itemLink then
        ns.ClearAllOverlays(itemButton)
        return
    end

    local info = C_Container.GetContainerItemInfo(bagID, slot)
    local quality = info and info.quality
    local isEquippable = IsEquippableItem(itemLink) and true or false

    -- the top-left corner shows exactly one thing: the item level on
    -- gear worth wearing, or the type tag on everything else
    local junkGear = ns.Config.HIDE_JUNK_QUALITY and ns.IsJunkQuality(quality)
    if not isEquippable or junkGear then
        ns.ClearGearOverlays(itemButton)
        ns.SetTypeText(itemButton, ns.GetTypeTag(bagID, slot, itemLink, quality, isEquippable))
        return
    end

    ns.SetTypeText(itemButton, nil)

    local itemLoc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
    ns.SetItemLevelText(itemButton, ns.GetItemLevel(itemLoc))

    ns.SetSlotText(itemButton, ns.GetSlotLabel(itemLink))

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
