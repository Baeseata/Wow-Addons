-- DodoInspect - Inspect.lua
-- Gear overlays on the inspect window (another player's equipment):
--   top-left:     item level (gradient colored, like Equipment.lua)
--   bottom-left:  enchant tag (green ok / red missing)
--   bottom-right: gem icons
-- The simplified inspect side panel (InspectPanel.lua) keeps only the
-- slot and the four-stat grid; enchants and gems live here instead.
--
-- Two things differ from the character frame (Equipment.lua):
--   * Blizzard_InspectUI is load-on-demand, so the frame is hooked
--     when that addon loads (or lazily on the first inspect event).
--   * the inspected unit's gear is read by item LINK -- ItemLocation
--     is player-only -- and the data arrives asynchronously, so the
--     overlays refresh on INSPECT_READY and GET_ITEM_INFO_RECEIVED.
--
-- Inspect only works on players you are allowed to inspect (friendly /
-- same faction); their gear is readable and hostile players cannot be
-- inspected at all, so this never reads secret values. The ilvl and
-- quality reads are issecretvalue-guarded anyway, as a cheap habit
-- consistent with TargetInfo.lua.

local _, ns = ...

local INSPECT_BUTTONS = {
    "InspectHeadSlot",
    "InspectNeckSlot",
    "InspectShoulderSlot",
    "InspectBackSlot",
    "InspectChestSlot",
    "InspectWristSlot",
    "InspectHandsSlot",
    "InspectWaistSlot",
    "InspectLegsSlot",
    "InspectFeetSlot",
    "InspectFinger0Slot",
    "InspectFinger1Slot",
    "InspectTrinket0Slot",
    "InspectTrinket1Slot",
    "InspectMainHandSlot",
    "InspectSecondaryHandSlot",
}

-- Item level from an item link (the inspected unit's gear). The
-- player-only ItemLocation path in ItemInfo.lua does not work for
-- other units, so read the effective level off the link instead.
local function GetLinkItemLevel(link)
    if issecretvalue(link) or not link then return nil end
    local lvl
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        lvl = C_Item.GetDetailedItemLevelInfo(link)
    elseif GetDetailedItemLevelInfo then
        lvl = GetDetailedItemLevelInfo(link)
    end
    if not issecretvalue(lvl) and type(lvl) == "number" and lvl > 0 then
        return math.floor(lvl + 0.5)
    end
    return nil
end
ns.GetLinkItemLevel = GetLinkItemLevel -- shared with InspectPanel.lua

-- Quality from an item link (3rd return of GetItemInfo), for the junk
-- filter; nil while the item is still uncached.
local function GetLinkQuality(link)
    if issecretvalue(link) or not link then return nil end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(getInfo) ~= "function" then return nil end
    local q = select(3, getInfo(link))
    if issecretvalue(q) then return nil end
    return q
end

function ns.UpdateInspect()
    if not (InspectFrame and InspectFrame:IsShown()) then return end
    local unit = InspectFrame.unit or "target"
    local enabled = ns.IsEnabled("showInspectIlvl") and UnitExists(unit)
    for _, name in ipairs(INSPECT_BUTTONS) do
        local button = _G[name]
        if button then
            local slotID = button:GetID()
            local link
            if enabled and type(slotID) == "number" and slotID > 0 then
                link = GetInventoryItemLink(unit, slotID)
                if issecretvalue(link) then link = nil end
            end

            -- top-left: item level (hidden for junk-quality gear)
            local ilvl = link and GetLinkItemLevel(link) or nil
            if ilvl and ns.Config.HIDE_JUNK_QUALITY
                and ns.IsJunkQuality(GetLinkQuality(link)) then
                ilvl = nil
            end
            ns.SetItemLevelText(button, ilvl)

            -- bottom-left: enchant (green ok / red missing on an
            -- enchantable slot), bottom-right: gems
            if link then
                local enchantID, gems = ns.ParseItemLink(link)
                local enchState
                if ns.IsEnchantableSlot(slotID, link) then
                    local on = enchantID and enchantID ~= "" and enchantID ~= "0"
                    enchState = on and "ok" or "missing"
                end
                ns.SetEnchantTag(button, enchState)
                local stats = ns.GetStatsTable(link)
                ns.SetGemOverlay(button, gems,
                    math.max(0, ns.CountTemplateSockets(stats) - #gems))
            else
                ns.SetEnchantTag(button, nil)
                ns.SetGemOverlay(button, nil, 0)
            end
        end
    end
end

-- Options checkbox hook: re-render (UpdateInspect checks the toggle and
-- the frame's visibility itself).
function ns.ApplyInspectEnabled()
    ns.UpdateInspect()
end

-- Blizzard_InspectUI is load-on-demand; hook its frame once it exists.
-- Guarded so it happens at most once and only when the frame is present.
local hooked = false
local function HookInspectFrame()
    if hooked or not InspectFrame then return end
    hooked = true
    InspectFrame:HookScript("OnShow", function()
        C_Timer.After(0, ns.UpdateInspect)
    end)
end

local EVT = CreateFrame("Frame")
EVT:RegisterEvent("ADDON_LOADED")
EVT:RegisterEvent("INSPECT_READY")
EVT:RegisterEvent("GET_ITEM_INFO_RECEIVED")
EVT:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_InspectUI" then HookInspectFrame() end
        return
    end
    -- INSPECT_READY / GET_ITEM_INFO_RECEIVED: the inspect data, or a
    -- previously uncached item link, just became available. Also covers
    -- a /reload while the inspect UI was already loaded (lazy hook).
    HookInspectFrame()
    C_Timer.After(0, ns.UpdateInspect)
end)
