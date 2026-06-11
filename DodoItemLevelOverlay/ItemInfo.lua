-- DodoItemLevelOverlay - ItemInfo.lua
-- Read-only helpers that extract display data from items.

local _, ns = ...

local QUALITY_COMMON = (Enum and Enum.ItemQuality and Enum.ItemQuality.Common) or 1

-- Short English slot labels keyed by inventory type token.
local SLOT_LABELS = {
    INVTYPE_HEAD           = "HD",
    INVTYPE_NECK           = "NK",
    INVTYPE_SHOULDER       = "SH",
    INVTYPE_CLOAK          = "CL",
    INVTYPE_CHEST          = "CH",
    INVTYPE_ROBE           = "CH",
    INVTYPE_BODY           = "ST", -- shirt
    INVTYPE_WRIST          = "WR",
    INVTYPE_HAND           = "GL", -- gloves
    INVTYPE_WAIST          = "BT", -- belt
    INVTYPE_LEGS           = "LG",
    INVTYPE_FEET           = "FT",
    INVTYPE_FINGER         = "RG", -- ring
    INVTYPE_TRINKET        = "TR",
    INVTYPE_WEAPON         = "1H",
    INVTYPE_2HWEAPON       = "2H",
    INVTYPE_WEAPONMAINHAND = "MH",
    INVTYPE_WEAPONOFFHAND  = "OH",
    INVTYPE_SHIELD         = "SD",
    INVTYPE_HOLDABLE       = "OH",
    INVTYPE_RANGED         = "RN",
    INVTYPE_RANGEDRIGHT    = "RN",
    INVTYPE_THROWN         = "TH",
    INVTYPE_RELIC          = "RL",
    INVTYPE_TABARD         = "TB",
}

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

-- Short slot label for an item link, or nil.
function ns.GetSlotLabel(itemLink)
    if not itemLink then return nil end
    local _, _, _, equipLoc = GetItemInfoInstant(itemLink)
    if not equipLoc or equipLoc == "" then return nil end
    return SLOT_LABELS[equipLoc]
end
