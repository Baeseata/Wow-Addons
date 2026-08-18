-- DodoGrid :: HideBlizzard.lua
-- Hide Blizzard's default party/raid frames, taint-free (the Cell / ElvUI shipping pattern):
--   * reparent each Compact* frame to a permanently-hidden holder + UnregisterAllEvents, so the
--     frame can't re-enter its own secure show logic on a roster change;
--   * MANDATORY KeepHidden post-hooks (Edit Mode calls Show()/SetShown() directly, bypassing the
--     unregistered events) -- hooksecurefunc runs in a secure-inserted slot, so it does NOT taint;
--   * the sanctioned CompactRaidFrameManager_SetSetting("IsShown","0") BEFORE the reparent.
-- Combat-gated: SetParent on a protected frame errors in combat, so defer to PLAYER_REGEN_ENABLED.
-- Toggling OFF requires /reload -- there is no taint-safe live un-hide (matches Cell/ElvUI).

local ADDON, ns = ...

local hiddenHolder = CreateFrame("Frame", "DodoGridHiddenHolder", UIParent)
hiddenHolder:Hide()

local function HideFrame(frame)
	if not frame then return end
	frame:UnregisterAllEvents()
	frame:SetParent(hiddenHolder)
	frame:Hide()
end

local hooked = {}
local function KeepHidden(frame)   -- mandatory: defeats Edit Mode's direct Show()/SetShown()
	if not frame or hooked[frame] then return end
	hooked[frame] = true
	hooksecurefunc(frame, "Show", frame.Hide)                                  -- on Show() -> Hide(), no taint
	hooksecurefunc(frame, "SetShown", function(self, shown) if shown then self:Hide() end end)
end

local function HideBlizzardRaid()
	UIParent:UnregisterEvent("GROUP_ROSTER_UPDATE")
	if CompactRaidFrameContainer then HideFrame(CompactRaidFrameContainer); KeepHidden(CompactRaidFrameContainer) end
	if CompactRaidFrameManager_SetSetting then CompactRaidFrameManager_SetSetting("IsShown", "0") end  -- before reparent
	if CompactRaidFrameManager then HideFrame(CompactRaidFrameManager); KeepHidden(CompactRaidFrameManager) end
	if CompactRaidGroup_InitializeForGroup then
		hooksecurefunc("CompactRaidGroup_InitializeForGroup", function(self)
			if self and self.UnregisterAllEvents then self:UnregisterAllEvents() end
		end)
	end
end

local function HideBlizzardParty()
	UIParent:UnregisterEvent("GROUP_ROSTER_UPDATE")
	if CompactPartyFrame then HideFrame(CompactPartyFrame); KeepHidden(CompactPartyFrame) end
	if PartyFrame then                                          -- 12.0 container + pooled member frames
		PartyFrame:UnregisterAllEvents()
		PartyFrame:SetScript("OnShow", nil)
		if PartyFrame.PartyMemberFramePool then
			for f in PartyFrame.PartyMemberFramePool:EnumerateActive() do HideFrame(f) end
		end
		HideFrame(PartyFrame)
	else
		for i = 1, 4 do
			HideFrame(_G["PartyMemberFrame" .. i])
			HideFrame(_G["CompactPartyFrameMember" .. i])
		end
	end
end

local applyFrame = CreateFrame("Frame")
local function ApplyHideBlizzard()
	if InCombatLockdown() then
		applyFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- SetParent on a protected frame errors in combat
		return
	end
	applyFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
	local db = ns.db
	if not db then return end
	if db.hideBlizzardRaid  ~= false then HideBlizzardRaid()  end
	if db.hideBlizzardParty ~= false then HideBlizzardParty() end
end
applyFrame:SetScript("OnEvent", ApplyHideBlizzard)
ns.ApplyHideBlizzard = ApplyHideBlizzard

StaticPopupDialogs["DODOGRID_RELOAD"] = {
	text = "DodoGrid: 需要重载界面以应用更改。现在重载?",
	button1 = OKAY, button2 = CANCEL,
	OnAccept = ReloadUI, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
function ns.PromptReload() StaticPopup_Show("DODOGRID_RELOAD") end
