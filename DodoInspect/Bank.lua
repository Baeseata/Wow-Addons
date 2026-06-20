-- DodoInspect - Bank.lua
-- Reuses the bag overlays on the bank windows.
--
-- Player bank (The War Within bank panels: BankPanel / AccountBankPanel)
-- holds ordinary C_Container containers -- each item button reports its
-- bank tab and slot -- so it gets the exact same treatment as the bags
-- through the shared ns.ApplyItemOverlay (item level, slot label,
-- BOE / equipment-set tags, item type tags).
--
-- Guild bank (Blizzard_GuildBankUI, load-on-demand) is link-only: its
-- slots are not C_Container containers, so the overlays are rebuilt from
-- the item link instead -- item level (gradient), slot label and the
-- item type tag. BOE / equipment-set tags need a per-instance bound
-- state that the guild bank does not expose, so they are skipped there.
--
-- All of this is gated by the single "showBankOverlays" toggle, matching
-- how the bags use "showBagOverlays".

local _, ns = ...

------------------------------------------------------------------
-- Player bank (BankPanel / AccountBankPanel)
------------------------------------------------------------------

-- Draw (or clear) the overlays on every valid item button of a bank
-- panel. The panel is passed straight from the hooked Blizzard methods.
function ns.UpdateBankPanel(panel)
    if not panel or type(panel.EnumerateValidItems) ~= "function" then return end

    local enabled = ns.IsEnabled("showBankOverlays")
    for itemButton in panel:EnumerateValidItems() do
        if itemButton then
            if enabled then
                local bagID = (itemButton.GetBankTabID and itemButton:GetBankTabID())
                    or (itemButton.GetBagID and itemButton:GetBagID())
                local slot = (itemButton.GetContainerSlotID and itemButton:GetContainerSlotID())
                    or (itemButton.GetID and itemButton:GetID())
                ns.ApplyItemOverlay(itemButton, bagID, slot)
            else
                ns.ClearAllOverlays(itemButton)
            end
        end
    end
end

local function ForEachBankPanel(fn)
    if _G.BankPanel then fn(_G.BankPanel) end
    if _G.AccountBankPanel then fn(_G.AccountBankPanel) end
end

-- Redraw the currently shown bank panels (used when the toggle flips or
-- the bank first opens; routine refreshes ride the hooks below).
function ns.RefreshPlayerBank()
    ForEachBankPanel(function(panel)
        if panel.IsShown and panel:IsShown() then
            ns.UpdateBankPanel(panel)
        end
    end)
end

-- Hook each bank panel's slot-generation and refresh methods so the
-- overlays follow tab switches and item moves. Idempotent: a panel is
-- only hooked once, and panels that do not exist (or lack the methods)
-- are skipped, so this is safe to call repeatedly as panels appear.
local bankHooked = {}
local function HookBankPanel(panel)
    if not panel or bankHooked[panel] then return end
    local hookedAny = false
    for _, method in ipairs({ "GenerateItemSlotsForSelectedTab", "RefreshAllItemsForSelectedTab" }) do
        if type(panel[method]) == "function" then
            hooksecurefunc(panel, method, function(self)
                ns.UpdateBankPanel(self)
            end)
            hookedAny = true
        end
    end
    if hookedAny then bankHooked[panel] = true end
end

local function TryHookBank()
    ForEachBankPanel(HookBankPanel)
end

------------------------------------------------------------------
-- Guild bank (Blizzard_GuildBankUI, load-on-demand)
------------------------------------------------------------------

-- 7 columns x 14 rows = 98 slots per tab (Blizzard constants).
local GUILDBANK_COLUMNS = 7
local GUILDBANK_ROWS    = 14

-- Overlay a single guild bank button from its item link (link-only --
-- no C_Container location is available for guild bank slots).
local function ApplyGuildBankOverlay(button, link)
    if not link then
        ns.ClearAllOverlays(button)
        return
    end

    local quality = ns.GetLinkQuality(link)
    local isEquippable = IsEquippableItem(link) and true or false

    -- gear shows its item level (top-left); everything else, plus junk
    -- gear when the junk filter is on, shows a type tag (top-right)
    local junkGear = ns.Config.HIDE_JUNK_QUALITY and ns.IsJunkQuality(quality)
    if not isEquippable or junkGear then
        ns.ClearGearOverlays(button)
        ns.SetTypeText(button, ns.GetTypeTag(nil, nil, link, quality, isEquippable))
        return
    end

    ns.SetTypeText(button, nil)
    ns.SetItemLevelText(button, ns.GetLinkItemLevel(link))
    ns.SetSlotText(button, ns.GetSlotLabel(link))
    -- BOE / equipment-set tags need a per-instance bound state the guild
    -- bank does not expose; leave the bottom-left tag clear.
    ns.SetTagText(button, nil)
end

-- Visit every guild bank item button. Prefers the modern frame layout
-- (GuildBankFrame.Columns[c].Buttons[r]) and falls back to the legacy
-- global button names, so it keeps working across UI revisions.
local function ForEachGuildBankButton(frame, fn)
    local columns = frame.Columns
    if type(columns) == "table" then
        for _, column in ipairs(columns) do
            local buttons = column and column.Buttons
            if type(buttons) == "table" then
                for _, button in ipairs(buttons) do
                    if button then fn(button) end
                end
            end
        end
        return
    end

    for c = 1, GUILDBANK_COLUMNS do
        for r = 1, GUILDBANK_ROWS do
            local button = _G["GuildBankColumn" .. c .. "Button" .. r]
            if button then fn(button) end
        end
    end
end

function ns.UpdateGuildBank()
    local frame = _G.GuildBankFrame
    if not frame or not frame.IsShown or not frame:IsShown() then return end
    -- only the item tabs carry slot buttons; the money log tab does not
    if frame.mode ~= nil and frame.mode ~= "bank" then return end

    local enabled = ns.IsEnabled("showBankOverlays")
    local tab = type(GetCurrentGuildBankTab) == "function" and GetCurrentGuildBankTab() or nil
    local getLink = (type(GetGuildBankItemLink) == "function") and GetGuildBankItemLink or nil

    ForEachGuildBankButton(frame, function(button)
        if not enabled or not tab or not getLink then
            ns.ClearAllOverlays(button)
            return
        end
        -- each button's ID is the 1..98 slot index used by the API
        local index = button.GetID and button:GetID()
        local link = (type(index) == "number" and index > 0) and getLink(tab, index) or nil
        ApplyGuildBankOverlay(button, link)
    end)
end

local guildBankHooked = false
local function TryHookGuildBank()
    if guildBankHooked or not _G.GuildBankFrame then return end
    -- current retail: GuildBankFrameMixin:Update() drives the refresh
    if type(_G.GuildBankFrame.Update) == "function" then
        hooksecurefunc(_G.GuildBankFrame, "Update", function()
            ns.UpdateGuildBank()
        end)
        guildBankHooked = true
    elseif type(_G.GuildBankFrame_Update) == "function" then
        -- legacy global wrapper, kept as a fallback
        hooksecurefunc("GuildBankFrame_Update", function()
            ns.UpdateGuildBank()
        end)
        guildBankHooked = true
    end
end

------------------------------------------------------------------
-- Toggle handler + event wiring
------------------------------------------------------------------

-- Options checkbox hook: redraw whatever bank window is open (the update
-- functions clear instead of draw when the toggle is off).
function ns.ApplyBankEnabled()
    ns.RefreshPlayerBank()
    ns.UpdateGuildBank()
end

local EVT = CreateFrame("Frame")
EVT:RegisterEvent("PLAYER_LOGIN")
EVT:RegisterEvent("ADDON_LOADED")
EVT:RegisterEvent("BANKFRAME_OPENED")
EVT:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
EVT:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        -- the player bank panels exist up front in retail; hook now (the
        -- BANKFRAME_OPENED path below covers a load-on-demand bank too)
        TryHookBank()
        TryHookGuildBank()
        return
    end
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_GuildBankUI" then
            TryHookGuildBank()
        end
        return
    end
    if event == "BANKFRAME_OPENED" then
        TryHookBank()
        C_Timer.After(0, ns.RefreshPlayerBank)
        return
    end
    if event == "GUILDBANKBAGSLOTS_CHANGED" then
        -- guild bank contents (or a freshly queried tab) changed
        C_Timer.After(0, ns.UpdateGuildBank)
        return
    end
end)
