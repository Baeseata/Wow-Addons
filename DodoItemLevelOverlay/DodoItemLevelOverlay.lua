-- DodoItemLevelOverlay.lua
-- Show item level on item icons for:
-- 1) Character equipment slots (PaperDoll): ilvl only
-- 2) Blizzard default bags (combined or separated): ilvl + one bottom-left tag + one top-right slot label
--
-- Bag item overlays:
-- - TOPLEFT: item level
-- - BOTTOMLEFT: "BOE" (only if truly unbound BOE) OR equipment set name
-- - TOPRIGHT: Chinese one-char slot label (头 / 肩 / 胸 / 主 ...)

-- ========================================================================
-- Config (四类显示内容都集中在这里)
-- ========================================================================

-- [1] 装等（左上角）
local ILVL_FONT_SIZE  = 12
local ILVL_FONT_FLAGS = "OUTLINE"
local ILVL_ANCHOR_POINT = "TOPLEFT"
local ILVL_ANCHOR_X, ILVL_ANCHOR_Y = 1, -1

-- 装等颜色档位（你可以直接改）
local ILVL_WHITE_R,  ILVL_WHITE_G,  ILVL_WHITE_B,  ILVL_WHITE_A  = 1.00, 1.00, 1.00, 1
local ILVL_GREEN_R,  ILVL_GREEN_G,  ILVL_GREEN_B,  ILVL_GREEN_A  = 0.20, 1.00, 0.20, 1
local ILVL_BLUE_R,   ILVL_BLUE_G,   ILVL_BLUE_B,   ILVL_BLUE_A   = 0.25, 0.65, 1.00, 1
local ILVL_PURPLE_R, ILVL_PURPLE_G, ILVL_PURPLE_B, ILVL_PURPLE_A = 0.75, 0.25, 1.00, 1
local ILVL_ORANGE_R, ILVL_ORANGE_G, ILVL_ORANGE_B, ILVL_ORANGE_A = 1.00, 0.55, 0.10, 1
local ILVL_RED_R,    ILVL_RED_G,    ILVL_RED_B,    ILVL_RED_A    = 1.00, 0.10, 0.10, 1

-- [2] BOE（左下角）
local BOE_TEXT = "BOE"
local BOE_FONT_SIZE  = 14
local BOE_FONT_FLAGS = "OUTLINE"
local BOE_TEXT_R, BOE_TEXT_G, BOE_TEXT_B, BOE_TEXT_A = 0.30, 1.00, 0.30, 1
local BOE_ANCHOR_POINT = "BOTTOMLEFT"
local BOE_ANCHOR_X, BOE_ANCHOR_Y = 1, 1

-- [3] 装备方案名（左下角）
local SET_FONT_SIZE   = 14
local SET_FONT_FLAGS  = "OUTLINE"
local SET_TEXT_R, SET_TEXT_G, SET_TEXT_B, SET_TEXT_A = 1.00, 0.82, 0.00, 1
local SET_ANCHOR_POINT = "BOTTOMLEFT"
local SET_ANCHOR_X, SET_ANCHOR_Y = 1, 1

-- [4] 部位（右上角，只显示在背包里的可装备物品上）
local SLOT_FONT_SIZE   = 14
local SLOT_FONT_FLAGS  = "OUTLINE"
local SLOT_TEXT_R, SLOT_TEXT_G, SLOT_TEXT_B, SLOT_TEXT_A = 0.20, 1.00, 0.20, 1
local SLOT_ANCHOR_POINT = "TOPRIGHT"
local SLOT_ANCHOR_X, SLOT_ANCHOR_Y = -1, -1

-- ========================================================================
-- 装等颜色规则
-- 1-219 = white
-- 220-230 = green
-- 231-243 = blue
-- 244-256 = purple
-- 257-269 = orange
-- 270+   = red
-- ========================================================================

local function ColorForILvl(ilvl)
  if not ilvl or ilvl <= 0 then
    return ILVL_WHITE_R, ILVL_WHITE_G, ILVL_WHITE_B, ILVL_WHITE_A
  end

  if ilvl >= 270 then
    return ILVL_RED_R, ILVL_RED_G, ILVL_RED_B, ILVL_RED_A
  elseif ilvl >= 257 then
    return ILVL_ORANGE_R, ILVL_ORANGE_G, ILVL_ORANGE_B, ILVL_ORANGE_A
  elseif ilvl >= 244 then
    return ILVL_PURPLE_R, ILVL_PURPLE_G, ILVL_PURPLE_B, ILVL_PURPLE_A
  elseif ilvl >= 231 then
    return ILVL_BLUE_R, ILVL_BLUE_G, ILVL_BLUE_B, ILVL_BLUE_A
  elseif ilvl >= 220 then
    return ILVL_GREEN_R, ILVL_GREEN_G, ILVL_GREEN_B, ILVL_GREEN_A
  else
    return ILVL_WHITE_R, ILVL_WHITE_G, ILVL_WHITE_B, ILVL_WHITE_A
  end
end

-- ========================================================================
-- 部位映射（背包里的装备右上角）
-- 基于 equipLoc 字符串
-- ========================================================================

local EQUIP_LOC_LABELS = {
  INVTYPE_HEAD         = "头",
  INVTYPE_NECK         = "颈",
  INVTYPE_SHOULDER     = "肩",
  INVTYPE_CLOAK        = "背",
  INVTYPE_CHEST        = "胸",
  INVTYPE_ROBE         = "胸",
  INVTYPE_BODY         = "衬", -- 衬衣
  INVTYPE_WRIST        = "腕",
  INVTYPE_HAND         = "手",
  INVTYPE_WAIST        = "腰",
  INVTYPE_LEGS         = "腿",
  INVTYPE_FEET         = "脚",
  INVTYPE_FINGER       = "戒",
  INVTYPE_TRINKET      = "饰",
  INVTYPE_WEAPON       = "武",
  INVTYPE_2HWEAPON     = "双",
  INVTYPE_WEAPONMAINHAND = "主",
  INVTYPE_WEAPONOFFHAND  = "副",
  INVTYPE_SHIELD       = "盾",
  INVTYPE_HOLDABLE     = "副",
  INVTYPE_RANGED       = "远",
  INVTYPE_RANGEDRIGHT  = "远",
  INVTYPE_THROWN       = "远",
  INVTYPE_RELIC        = "圣",
  INVTYPE_TABARD       = "袍",
}

-- ========================================================================
-- Utilities
-- ========================================================================

local function RoundInt(x)
  if type(x) ~= "number" or x <= 0 then return nil end
  return math.floor(x + 0.5)
end

-- 左上角装等
local function EnsureIlvlText(button)
  if not button or button.DodoIlvlText then return end

  local fs = button:CreateFontString(nil, "OVERLAY")
  fs:SetFont(STANDARD_TEXT_FONT, ILVL_FONT_SIZE, ILVL_FONT_FLAGS)
  fs:SetPoint(ILVL_ANCHOR_POINT, button, ILVL_ANCHOR_POINT, ILVL_ANCHOR_X, ILVL_ANCHOR_Y)
  fs:SetJustifyH("LEFT")
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 1)
  fs:Hide()

  button.DodoIlvlText = fs
end

-- 左下角 BOE / 装备方案（共用）
local function EnsureTagText(button)
  if not button or button.DodoTagText then return end

  local fs = button:CreateFontString(nil, "OVERLAY")
  fs:SetFont(STANDARD_TEXT_FONT, SET_FONT_SIZE, SET_FONT_FLAGS)
  fs:SetPoint(SET_ANCHOR_POINT, button, SET_ANCHOR_POINT, SET_ANCHOR_X, SET_ANCHOR_Y)
  fs:SetJustifyH("LEFT")
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 1)

  local w = (button.GetWidth and button:GetWidth()) or 0
  if type(w) == "number" and w > 4 and fs.SetWidth then
    fs:SetWidth(w - 2)
  end
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  if fs.SetMaxLines then fs:SetMaxLines(1) end

  fs:Hide()
  button.DodoTagText = fs
end

-- 右上角部位（只给背包按钮用）
local function EnsureBagSlotText(button)
  if not button or button.DodoBagSlotText then return end

  local fs = button:CreateFontString(nil, "OVERLAY")
  fs:SetFont(STANDARD_TEXT_FONT, SLOT_FONT_SIZE, SLOT_FONT_FLAGS)
  fs:SetPoint(SLOT_ANCHOR_POINT, button, SLOT_ANCHOR_POINT, SLOT_ANCHOR_X, SLOT_ANCHOR_Y)
  fs:SetJustifyH("RIGHT")
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 1)
  fs:Hide()

  button.DodoBagSlotText = fs
end

local function SetILvl(button, ilvlInt)
  if not button or not button.DodoIlvlText then return end
  if not ilvlInt or ilvlInt <= 0 then
    button.DodoIlvlText:Hide()
    return
  end

  local r, g, b, a = ColorForILvl(ilvlInt)
  button.DodoIlvlText:SetFont(STANDARD_TEXT_FONT, ILVL_FONT_SIZE, ILVL_FONT_FLAGS)
  button.DodoIlvlText:ClearAllPoints()
  button.DodoIlvlText:SetPoint(ILVL_ANCHOR_POINT, button, ILVL_ANCHOR_POINT, ILVL_ANCHOR_X, ILVL_ANCHOR_Y)
  button.DodoIlvlText:SetTextColor(r, g, b, a)
  button.DodoIlvlText:SetText(tostring(ilvlInt))
  button.DodoIlvlText:Show()
end

local function ClearBagTag(button)
  if not button or not button.DodoTagText then return end
  button.DodoTagText:Hide()
end

local function SetBagTag(button, text, fontSize, fontFlags, r, g, b, a, point, x, y)
  if not button or not button.DodoTagText then return end
  if type(text) ~= "string" or text == "" then
    button.DodoTagText:Hide()
    return
  end

  button.DodoTagText:SetFont(STANDARD_TEXT_FONT, fontSize, fontFlags)
  button.DodoTagText:ClearAllPoints()
  button.DodoTagText:SetPoint(point, button, point, x, y)
  button.DodoTagText:SetTextColor(r, g, b, a)
  button.DodoTagText:SetText(text)
  button.DodoTagText:Show()
end

local function ClearBagSlotLabel(button)
  if not button or not button.DodoBagSlotText then return end
  button.DodoBagSlotText:Hide()
end

local function SetBagSlotLabel(button, text)
  if not button or not button.DodoBagSlotText then return end
  if type(text) ~= "string" or text == "" then
    button.DodoBagSlotText:Hide()
    return
  end

  button.DodoBagSlotText:SetFont(STANDARD_TEXT_FONT, SLOT_FONT_SIZE, SLOT_FONT_FLAGS)
  button.DodoBagSlotText:ClearAllPoints()
  button.DodoBagSlotText:SetPoint(SLOT_ANCHOR_POINT, button, SLOT_ANCHOR_POINT, SLOT_ANCHOR_X, SLOT_ANCHOR_Y)
  button.DodoBagSlotText:SetTextColor(SLOT_TEXT_R, SLOT_TEXT_G, SLOT_TEXT_B, SLOT_TEXT_A)
  button.DodoBagSlotText:SetText(text)
  button.DodoBagSlotText:Show()
end

local function IsEquipItemByLocation(itemLoc)
  if not itemLoc or not itemLoc:IsValid() then return false end
  local invType = C_Item.GetItemInventoryType(itemLoc) -- 0 for non-equippable
  return type(invType) == "number" and invType ~= 0
end

local function GetIlvlFromLocation(itemLoc)
  if not itemLoc or not itemLoc:IsValid() then return nil end
  if not IsEquipItemByLocation(itemLoc) then return nil end

  local ilvl = C_Item.GetCurrentItemLevel(itemLoc)
  return RoundInt(ilvl)
end

local function GetItemBindType(itemLink)
  if not itemLink then return nil end

  -- 第14个返回值 = bindType
  -- 2 = Bind on Equip
  local bindType

  if C_Item and type(C_Item.GetItemInfo) == "function" then
    bindType = select(14, C_Item.GetItemInfo(itemLink))
  end

  if not bindType then
    bindType = select(14, GetItemInfo(itemLink))
  end

  return bindType
end

local function IsBOEItem(itemLink)
  local bindType = GetItemBindType(itemLink)
  if not bindType then
    return false
  end

  if bindType == LE_ITEM_BIND_ON_EQUIP or bindType == 2 then
    return true
  end

  return false
end

-- 只有“物品模板是 BOE”且“这件具体物品当前未绑定”时，才显示 BOE
local function IsActualUnboundBOEItem(bagID, slot, itemLink)
  if not itemLink or not IsBOEItem(itemLink) then
    return false
  end

  local itemLoc = ItemLocation:CreateFromBagAndSlot(bagID, slot)

  -- 优先：判断具体物品实例是否已绑定
  if itemLoc and itemLoc:IsValid() and C_Item and type(C_Item.IsBound) == "function" then
    local isBound = C_Item.IsBound(itemLoc)
    if isBound == true then
      return false
    elseif isBound == false then
      return true
    end
  end

  -- 兜底：背包槽位信息里的 isBound
  if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
    local info = C_Container.GetContainerItemInfo(bagID, slot)
    if info and info.isBound ~= nil then
      return not info.isBound
    end
  end

  -- 无法确认时，宁可不显示 BOE，避免误报
  return false
end

local function GetEquipSetNameFromBagSlot(bagID, slot)
  if not C_Container or type(C_Container.GetContainerItemEquipmentSetInfo) ~= "function" then
    return nil
  end

  local inSet, setList = C_Container.GetContainerItemEquipmentSetInfo(bagID, slot)
  if not inSet or type(setList) ~= "string" or setList == "" then
    return nil
  end

  return setList
end

local function GetBagSlotLabelFromItem(itemLink)
  if not itemLink then return nil end

  local _, _, _, equipLoc = GetItemInfoInstant(itemLink)
  if not equipLoc or equipLoc == "" then
    return nil
  end

  return EQUIP_LOC_LABELS[equipLoc]
end

-- 返回背包左下角要显示的标签（只显示一个）
-- 优先级：未绑定 BOE > 装备方案名
local function GetBagTagData(bagID, slot, itemLink)
  if not itemLink then
    return nil
  end

  if IsActualUnboundBOEItem(bagID, slot, itemLink) then
    return BOE_TEXT,
           BOE_FONT_SIZE, BOE_FONT_FLAGS,
           BOE_TEXT_R, BOE_TEXT_G, BOE_TEXT_B, BOE_TEXT_A,
           BOE_ANCHOR_POINT, BOE_ANCHOR_X, BOE_ANCHOR_Y
  end

  local setName = GetEquipSetNameFromBagSlot(bagID, slot)
  if setName and setName ~= "" then
    return setName,
           SET_FONT_SIZE, SET_FONT_FLAGS,
           SET_TEXT_R, SET_TEXT_G, SET_TEXT_B, SET_TEXT_A,
           SET_ANCHOR_POINT, SET_ANCHOR_X, SET_ANCHOR_Y
  end

  return nil
end

-- ========================================================================
-- Equipment (PaperDoll) - 只显示装等，不显示部位
-- ========================================================================

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

local function UpdateEquipmentOverlays()
  for _, name in ipairs(EQUIP_BUTTONS) do
    local btn = _G[name]
    if btn then
      EnsureIlvlText(btn)

      local slotID = btn:GetID()
      if type(slotID) == "number" and slotID > 0 then
        local itemLoc = ItemLocation:CreateFromEquipmentSlot(slotID)
        SetILvl(btn, GetIlvlFromLocation(itemLoc))
      else
        SetILvl(btn, nil)
      end
    end
  end
end

-- ========================================================================
-- Bags (Combined/Separated Blizzard Bags)
-- ========================================================================

local function UpdateBagFrameItems(frame)
  if not frame or not frame.IsShown or not frame:IsShown() then return end
  if type(frame.EnumerateValidItems) ~= "function" then return end

  for _, itemButton in frame:EnumerateValidItems() do
    if itemButton then
      EnsureIlvlText(itemButton)
      EnsureTagText(itemButton)
      EnsureBagSlotText(itemButton)

      local bagID = (itemButton.GetBagID and itemButton:GetBagID()) or (frame.GetID and frame:GetID())
      local slot  = (itemButton.GetID and itemButton:GetID()) or nil

      if type(bagID) == "number" and type(slot) == "number" and slot > 0 then
        local itemLoc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
        local ilvlInt = GetIlvlFromLocation(itemLoc)

        local itemLink
        if C_Container and C_Container.GetContainerItemLink then
          itemLink = C_Container.GetContainerItemLink(bagID, slot)
        end

        local isEquippable = false
        if itemLink and IsEquippableItem(itemLink) then
          isEquippable = true
        end

        if not isEquippable then
          ilvlInt = nil
          ClearBagTag(itemButton)
          ClearBagSlotLabel(itemButton)
        else
          local text, fontSize, fontFlags, r, g, b, a, point, x, y = GetBagTagData(bagID, slot, itemLink)
          if text then
            SetBagTag(itemButton, text, fontSize, fontFlags, r, g, b, a, point, x, y)
          else
            ClearBagTag(itemButton)
          end

          local slotLabel = GetBagSlotLabelFromItem(itemLink)
          if slotLabel then
            SetBagSlotLabel(itemButton, slotLabel)
          else
            ClearBagSlotLabel(itemButton)
          end
        end

        SetILvl(itemButton, ilvlInt)
      else
        SetILvl(itemButton, nil)
        ClearBagTag(itemButton)
        ClearBagSlotLabel(itemButton)
      end
    end
  end
end

local function HookBagFrames()
  -- Combined bags
  if _G.ContainerFrameCombinedBags and _G.ContainerFrameCombinedBags.UpdateItems then
    hooksecurefunc(_G.ContainerFrameCombinedBags, "UpdateItems", UpdateBagFrameItems)
  end

  -- Separate bags
  local c = _G.ContainerFrameContainer
  if c and c.ContainerFrames then
    for _, frame in ipairs(c.ContainerFrames) do
      if frame and frame.UpdateItems then
        hooksecurefunc(frame, "UpdateItems", UpdateBagFrameItems)
      end
    end
  end
end

local function UpdateIfVisible()
  if CharacterFrame and CharacterFrame:IsShown() then
    UpdateEquipmentOverlays()
  end

  if _G.ContainerFrameCombinedBags and _G.ContainerFrameCombinedBags:IsShown() then
    UpdateBagFrameItems(_G.ContainerFrameCombinedBags)
  end

  local c = _G.ContainerFrameContainer
  if c and c.ContainerFrames then
    for _, frame in ipairs(c.ContainerFrames) do
      if frame and frame:IsShown() then
        UpdateBagFrameItems(frame)
      end
    end
  end
end

-- ========================================================================
-- Events / init
-- ========================================================================

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("EQUIPMENT_SETS_CHANGED")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED") -- 未缓存物品信息到达后自动刷新

f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    HookBagFrames()

    -- Refresh when character frame shows
    if CharacterFrame and CharacterFrame.HookScript then
      CharacterFrame:HookScript("OnShow", function()
        C_Timer.After(0, UpdateEquipmentOverlays)
      end)
    end
    if PaperDollFrame and PaperDollFrame.HookScript then
      PaperDollFrame:HookScript("OnShow", function()
        C_Timer.After(0, UpdateEquipmentOverlays)
      end)
    end

    -- Refresh when bags open
    for _, fn in ipairs({"ToggleBackpack", "OpenBackpack", "ToggleAllBags", "OpenAllBags", "OpenBag", "ToggleBag"}) do
      if type(_G[fn]) == "function" then
        hooksecurefunc(fn, function()
          C_Timer.After(0, UpdateIfVisible)
        end)
      end
    end

    C_Timer.After(0, UpdateIfVisible)
    return
  end

  UpdateIfVisible()
end)