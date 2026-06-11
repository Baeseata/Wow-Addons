-- DodoRush - Sound
-- Sound effects reusing WoW's built-in SoundKit. Same approach as DodoPool/DodoBricks:
-- kit table KITS + per-kind minimum-gap throttle GAP + mute checkbox + volume slider
-- (volume = same-frame repeat plays).
-- Kinds: start run start / gate_good buff gate / gate_bad debuff gate / clash engage
--        / tick combat drain (high frequency, keep it light) / win wall ground down
--        / boss boss wall broken / dodge skirmish avoided / over crowd wiped / best new record.

local DR = _G.DodoRush or {}
_G.DodoRush = DR

local S = {}
DR.Sound = S

local SK = _G.SOUNDKIT or {}
local KITS = {
    start     = SK.IG_MAINMENU_OPTION_CHECKBOX_ON or 856,   -- run start: light click
    gate_good = SK.LOOT_WINDOW_COIN_SOUND or 120,           -- buff gate: coin jingle (same as Bricks pickup, loudness verified)
    gate_bad  = SK.AUCTION_WINDOW_CLOSE or 5275,            -- debuff gate: muffled gavel
    clash     = SK.AUCTION_WINDOW_OPEN or 5274,             -- engage: heavy gavel thud
    tick      = SK.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857,  -- combat drain: light click (highest frequency, keep light)
    win       = SK.MAP_PING or 3175,                        -- wall ground down: minimap ping
    boss      = SK.IG_QUEST_LIST_COMPLETE or 875,           -- boss broken: quest-complete chime
    dodge     = SK.IG_MAINMENU_OPTION_CHECKBOX_ON or 856,   -- skirmish dodged: light click
    over      = SK.IG_QUEST_FAILED or 846,                  -- crowd wiped: failure sting
    best      = SK.IG_QUEST_LIST_COMPLETE or 875,           -- new record: chime
}

-- Per-kind minimum gap (seconds). GetTime is constant within a frame, so
-- same-frame event bursts naturally collapse into a single play.
local GAP = { tick = 0.07, gate_good = 0.12, gate_bad = 0.12, clash = 0.18,
              win = 0.2, dodge = 0.25, over = 0.3, best = 0.5, start = 0.3 }
local last = {}

function S.Enabled()
    local db = DR.db
    return not (db and db.sound == false)
end

-- Volume steps 1~10 = number of same-frame repeat plays
function S.Volume()
    local db = DR.db
    local v = (db and tonumber(db.soundVolume)) or 3
    if v < 1 then v = 1 elseif v > 10 then v = 10 end
    return math.floor(v + 0.5)
end

local function Emit(kit)
    -- forceNoDuplicates must be an explicit false: it would otherwise refuse to play
    -- while the previous instance is still playing, and stacked loudness relies on
    -- repeating the sound within the same frame
    for _ = 1, S.Volume() do
        PlaySound(kit, "Master", false)
    end
end

function S.Play(kind)
    if not S.Enabled() then return end
    local kit = KITS[kind]
    if not kit then return end
    local gap = GAP[kind]
    if gap then
        local now = GetTime()
        if last[kind] and (now - last[kind]) < gap then return end
        last[kind] = now
    end
    Emit(kit)
end

-- ------------------------------------------------------------
-- Mute checkbox (one on the start screen + one in the HUD, states kept in sync)
-- ------------------------------------------------------------
local toggles = {}
local volSliders = {}

function S.SyncToggles()
    local on = S.Enabled()
    for _, cb in ipairs(toggles) do cb:SetChecked(on) end
    for _, sl in ipairs(volSliders) do sl:Refresh() end
end

function S.CreateToggle(parent, compact)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(24, 24)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    if not compact then
        cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 1, 0)
        cb.label:SetText("Sound")
    end
    cb:SetScript("OnShow", function(self) self:SetChecked(S.Enabled()) end)
    cb:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if DR.db then DR.db.sound = on end
        S.SyncToggles()
        if on then Emit(KITS.win) end   -- audible feedback when enabling, stay silent when muting
    end)
    cb:SetScript("OnEnter", function(self)
        if not compact then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Toggle sound", 1, 1, 1)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    toggles[#toggles + 1] = cb
    return cb
end

-- ------------------------------------------------------------
-- Volume slider (steps 1~10, used on the start screen)
-- ------------------------------------------------------------
function S.CreateVolumeSlider(parent)
    local sl = CreateFrame("Slider", nil, parent)
    sl:SetOrientation("HORIZONTAL")
    sl:SetSize(160, 16)
    sl:SetMinMaxValues(1, 10)
    sl:SetValueStep(1)
    sl:SetObeyStepOnDrag(true)
    sl:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")

    local rail = sl:CreateTexture(nil, "BACKGROUND")
    rail:SetPoint("LEFT", 2, 0); rail:SetPoint("RIGHT", -2, 0)
    rail:SetHeight(5)
    rail:SetColorTexture(0, 0, 0, 0.55)

    sl.caption = sl:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sl.caption:SetPoint("RIGHT", sl, "LEFT", -8, 0)
    sl.caption:SetText("Volume")
    sl.valText = sl:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sl.valText:SetPoint("LEFT", sl, "RIGHT", 8, 0)
    sl.valText:SetText("3")

    function sl.Refresh(self)
        self._noPreview = true
        self:SetValue(S.Volume())
        self._noPreview = false
        self._lastVal = S.Volume()
        self.valText:SetText(tostring(S.Volume()))
        local on = S.Enabled()
        self:SetAlpha(on and 1 or 0.45)
        if on then self:Enable() else self:Disable() end
    end

    sl:SetScript("OnShow", sl.Refresh)
    sl:SetScript("OnValueChanged", function(self, value)
        local v = math.floor(value + 0.5)
        if v == self._lastVal then return end
        self._lastVal = v
        if DR.db then DR.db.soundVolume = v end
        self.valText:SetText(tostring(v))
        if not self._noPreview then Emit(KITS.win) end   -- preview the new volume while dragging
    end)

    volSliders[#volSliders + 1] = sl
    sl:Refresh()
    return sl
end
