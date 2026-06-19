-- DodoInspect - Equipment.lua
-- Gear overlays on the character frame equipment slots (the player's
-- own gear), mirroring the inspect window (Inspect.lua):
--   top-left:     item level (gradient colored)
--   bottom-left:  enchant tag (green ok / red missing)
--   bottom-right: gem icons
-- Slot labels and type tags stay a bag-only concept. The player's own
-- gear is never a secret value, so the link helpers need no guards.

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
    -- when the toggle is off, the loop still runs with nil data, which
    -- hides anything drawn before the toggle flipped
    local enabled = ns.IsEnabled("showEquipmentIlvl")
    for _, name in ipairs(EQUIP_BUTTONS) do
        local button = _G[name]
        if button then
            local slotID = button:GetID()
            local ok = enabled and type(slotID) == "number" and slotID > 0

            -- top-left: item level (hidden for junk-quality gear)
            local ilvl
            if ok then
                local itemLoc = ItemLocation:CreateFromEquipmentSlot(slotID)
                ilvl = ns.GetItemLevel(itemLoc)
                if ilvl and ns.Config.HIDE_JUNK_QUALITY
                    and ns.IsJunkQuality(ns.GetQuality(itemLoc)) then
                    ilvl = nil
                end
            end
            ns.SetItemLevelText(button, ilvl)

            -- bottom-left: enchant, bottom-right: gems
            local link = ok and GetInventoryItemLink("player", slotID) or nil
            ns.SetEnchantAndGems(button, slotID, link)
        end
    end
end
