-- DodoInspect - Equipment.lua
-- Item level overlays on the character frame equipment slots.
-- Only the item level is shown here; tags and slot labels are a
-- bag-only concept.

local _, ns = ...

local EQUIP_BUTTONS = {
    "CharacterHeadSlot",
    "CharacterNeckSlot",
    "CharacterShoulderSlot",
    "CharacterBackSlot",
    "CharacterChestSlot",
    "CharacterWristSlot",
    "CharacterHandsSlot",
    "CharacterWaistSlot",
    "CharacterLegsSlot",
    "CharacterFeetSlot",
    "CharacterFinger0Slot",
    "CharacterFinger1Slot",
    "CharacterTrinket0Slot",
    "CharacterTrinket1Slot",
    "CharacterMainHandSlot",
    "CharacterSecondaryHandSlot",
}

function ns.UpdateEquipment()
    -- when the toggle is off, the loop still runs with a nil item
    -- level, which hides any text drawn before the toggle flipped
    local enabled = ns.IsEnabled("showEquipmentIlvl")
    for _, name in ipairs(EQUIP_BUTTONS) do
        local button = _G[name]
        if button then
            local ilvl
            local slotID = button:GetID()
            if enabled and type(slotID) == "number" and slotID > 0 then
                local itemLoc = ItemLocation:CreateFromEquipmentSlot(slotID)
                ilvl = ns.GetItemLevel(itemLoc)
                if ilvl and ns.Config.HIDE_JUNK_QUALITY
                    and ns.IsJunkQuality(ns.GetQuality(itemLoc)) then
                    ilvl = nil
                end
            end
            ns.SetItemLevelText(button, ilvl)
        end
    end
end
