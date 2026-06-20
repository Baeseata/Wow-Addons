-- DodoInspect - Bags.lua
-- Overlays on the default Blizzard bags (combined and separated).

local _, ns = ...

-- Draw (or clear) every overlay on a single container item button from
-- its resolved bag/slot. Shared by the Blizzard bags and the player
-- bank (the new bank tabs are ordinary C_Container containers, so the
-- whole bag treatment -- item level, slot label, BOE/set and type tags
-- -- applies unchanged). The guild bank is link-only and uses its own
-- path in Bank.lua.
function ns.ApplyItemOverlay(itemButton, bagID, slot)
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

    -- gear worth wearing shows its item level (top-left corner);
    -- everything else shows a type tag (top-right) instead
    local junkGear = ns.Config.HIDE_JUNK_QUALITY and ns.IsJunkQuality(quality)
    if not isEquippable or junkGear then
        ns.ClearGearOverlays(itemButton)
        ns.SetTypeText(itemButton, ns.GetTypeTag(bagID, slot, itemLink, quality, isEquippable))
        return
    end

    ns.SetTypeText(itemButton, nil)

    local itemLoc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
    local ilvl = ns.GetItemLevel(itemLoc)
    -- bags and the character bank resolve through ItemLocation; some
    -- account (warband) bank containers do not, so fall back to the
    -- link's effective level there. Never triggers for the bags.
    if not ilvl and ns.GetLinkItemLevel then
        ilvl = ns.GetLinkItemLevel(itemLink)
    end
    ns.SetItemLevelText(itemButton, ilvl)

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

local function UpdateItemButton(itemButton, frame)
    local bagID = (itemButton.GetBagID and itemButton:GetBagID())
        or (frame.GetID and frame:GetID())
    local slot = (itemButton.GetID and itemButton:GetID()) or nil
    ns.ApplyItemOverlay(itemButton, bagID, slot)
end

function ns.UpdateBagFrame(frame)
    if not frame or not frame.IsShown or not frame:IsShown() then return end
    if type(frame.EnumerateValidItems) ~= "function" then return end

    -- when the toggle is off, clear instead of skip: the hooks keep
    -- firing and texts drawn before the toggle flipped must go away
    local enabled = ns.IsEnabled("showBagOverlays")
    for _, itemButton in frame:EnumerateValidItems() do
        if itemButton then
            if enabled then
                UpdateItemButton(itemButton, frame)
            else
                ns.ClearAllOverlays(itemButton)
            end
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
