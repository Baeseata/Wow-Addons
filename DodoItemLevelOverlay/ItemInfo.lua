-- DodoItemLevelOverlay - ItemInfo.lua
-- Read-only helpers that extract display data from items.

local _, ns = ...

local QUALITY_POOR   = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
local QUALITY_COMMON = (Enum and Enum.ItemQuality and Enum.ItemQuality.Common) or 1

-- Item class and consumable subclass IDs (stable since vanilla).
local CLASS_CONSUMABLE = 0
local CLASS_QUESTITEM  = 12
local SUBCLASS_POTION  = 1
local SUBCLASS_FLASK   = 3 -- flasks and phials
local SUBCLASS_FOOD    = 5 -- food and drink

local function RoundInt(x)
    if type(x) ~= "number" or x <= 0 then return nil end
    return math.floor(x + 0.5)
end

-- True when the location holds an equippable item.
function ns.IsEquippableLocation(itemLoc)
    if not itemLoc or not itemLoc:IsValid() then return false end
    local invType = C_Item.GetItemInventoryType(itemLoc) -- 0 for non-equippable
    return type(invType) == "number" and invType ~= 0
end

-- Rounded current item level for an equippable location, or nil.
function ns.GetItemLevel(itemLoc)
    if not ns.IsEquippableLocation(itemLoc) then return nil end
    return RoundInt(C_Item.GetCurrentItemLevel(itemLoc))
end

-- True for Poor (gray) and Common (white) quality: vendor junk as
-- far as gearing is concerned.
function ns.IsJunkQuality(quality)
    return type(quality) == "number" and quality <= QUALITY_COMMON
end

-- Quality for an item location (works for equipped items too).
function ns.GetQuality(itemLoc)
    if not itemLoc or not itemLoc:IsValid() then return nil end
    if C_Item and type(C_Item.GetItemQuality) == "function" then
        return C_Item.GetItemQuality(itemLoc)
    end
    return nil
end

local function GetBindType(itemLink)
    if not itemLink then return nil end

    -- 14th return value of GetItemInfo is bindType (2 = Bind on Equip)
    local bindType
    if C_Item and type(C_Item.GetItemInfo) == "function" then
        bindType = select(14, C_Item.GetItemInfo(itemLink))
    end
    if not bindType and type(GetItemInfo) == "function" then
        bindType = select(14, GetItemInfo(itemLink))
    end
    return bindType
end

local function IsBOETemplate(itemLink)
    local bindType = GetBindType(itemLink)
    if not bindType then return false end
    return bindType == LE_ITEM_BIND_ON_EQUIP or bindType == 2
end

-- True only when the item template is BOE and this specific instance
-- is still unbound. When in doubt, returns false to avoid false tags.
function ns.IsUnboundBOE(bagID, slot, itemLink)
    if not itemLink or not IsBOETemplate(itemLink) then return false end

    -- preferred: ask the specific item instance whether it is bound
    local itemLoc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
    if itemLoc and itemLoc:IsValid() and C_Item and type(C_Item.IsBound) == "function" then
        local isBound = C_Item.IsBound(itemLoc)
        if isBound == true then return false end
        if isBound == false then return true end
    end

    -- fallback: container slot info carries an isBound flag
    if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if info and info.isBound ~= nil then
            return not info.isBound
        end
    end

    return false
end

-- Equipment set name for a bag slot, or nil.
function ns.GetEquipmentSetName(bagID, slot)
    if not C_Container or type(C_Container.GetContainerItemEquipmentSetInfo) ~= "function" then
        return nil
    end
    local inSet, setList = C_Container.GetContainerItemEquipmentSetInfo(bagID, slot)
    if not inSet or type(setList) ~= "string" or setList == "" then
        return nil
    end
    return setList
end

-- Localized short slot label for an item link, or nil.
function ns.GetSlotLabel(itemLink)
    if not itemLink then return nil end
    local _, _, _, equipLoc = GetItemInfoInstant(itemLink)
    if not equipLoc or equipLoc == "" then return nil end
    return ns.L and ns.L.slots[equipLoc] or nil
end

local function IsQuestItem(bagID, slot, classID)
    if classID == CLASS_QUESTITEM then return true end
    -- also covers quest-starting items that are not class 12
    if C_Container and type(C_Container.GetContainerItemQuestInfo) == "function" then
        local questInfo = C_Container.GetContainerItemQuestInfo(bagID, slot)
        if type(questInfo) == "table" and questInfo.isQuestItem then
            return true
        end
    end
    return false
end

-- Item type tag key for the top-left corner, or nil.
-- Priority: junk beats quest beats consumable.
--   "junk":   Poor quality anything; Common quality gear while the
--             junk filter is on. White non-gear (trade goods) is
--             NOT junk.
--   "quest":  quest items
--   "food" / "flask" / "potion" / "cons": consumables, with the
--             generic "cons" covering everything but those three
function ns.GetTypeTag(bagID, slot, itemLink, quality, isEquippable)
    if not itemLink then return nil end

    if type(quality) == "number" then
        if quality == QUALITY_POOR then return "junk" end
        if ns.Config.HIDE_JUNK_QUALITY and isEquippable and quality == QUALITY_COMMON then
            return "junk"
        end
    end

    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemLink)

    if IsQuestItem(bagID, slot, classID) then return "quest" end

    if classID == CLASS_CONSUMABLE then
        if subclassID == SUBCLASS_FOOD then return "food" end
        if subclassID == SUBCLASS_FLASK then return "flask" end
        if subclassID == SUBCLASS_POTION then return "potion" end
        return "cons"
    end

    return nil
end
