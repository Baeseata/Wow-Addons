-- DodoBricks - Sound
-- Sound effects: reuse WoW's built-in SoundKit (no custom audio files). Same approach as DodoPool/Sound.lua:
-- sound table KITS + per-kind minimum-interval throttle GAP + mute checkbox + volume slider (same-frame stacking for loudness).
-- Kinds: launch (fire a ball) / hit (ball hits a brick, high-frequency soft) / brk (brick breaks) / item (collect a +1 ball) / land (first ball lands)
--       / descend (bricks drop one row) / over (game over) / best (new record).
-- Note: wall hits are deliberately silent (too many per second, would only be noise).

local DBR = _G.DodoBricks or {}
_G.DodoBricks = DBR

local S = {}
DBR.Sound = S

-- Sound choice: look entries up in the SOUNDKIT constant table; if the name is missing fall back to the number; if neither exists, silently skip that sound.
-- A brick game's collision sound fires dozens of times per second, so hit/launch use a "light" UI click (the pool game found these too quiet, but light is just right here);
-- only the low-frequency events (brick break / item / descend / over) use loud ones. If unhappy with a choice, swap KITS following DodoPool's iteration path.
local SK = _G.SOUNDKIT or {}
local KITS = {
    launch  = SK.IG_MAINMENU_OPTION_CHECKBOX_ON or 856,   -- fire a ball: very light tick (high-frequency, must be light)
    hit     = SK.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857,  -- ball hits a brick: light tick (highest frequency, must be light)
    brk     = SK.MAP_PING or 3175,                        -- brick breaks: minimap ping, a soft "tock"
    item    = SK.LOOT_WINDOW_COIN_SOUND or 120,           -- collect a +1 ball: coin jingle (same as pocketing in pool, loudness tested OK)
    land    = SK.IG_MAINMENU_OPTION_CHECKBOX_ON or 856,   -- first ball lands (marks the next launch point): very light
    descend = SK.AUCTION_WINDOW_CLOSE or 5275,            -- bricks drop: muffled mallet knock (once per round)
    over    = SK.IG_QUEST_FAILED or 846,                  -- game over: short failure tone
    best    = SK.IG_QUEST_LIST_COMPLETE or 875,           -- new record: quest-complete chime
    laser   = SK.IG_ABILITY_ICON_DROP or 838,             -- laser trigger: muffled knock (same as the pool cue strike, sound choice to be iterated in-game)
    boom    = SK.AUCTION_WINDOW_OPEN or 5274,             -- bomb: heavy mallet "bang"
    clear   = SK.IG_QUEST_LIST_COMPLETE or 875,           -- clear-all bonus: chime (shares the sound with best, different occasion)
}

-- Minimum interval per kind (seconds). GetTime is constant within a frame => chained collisions in the same sub-step naturally only sound once
local GAP = { hit = 0.06, launch = 0.09, brk = 0.09, item = 0.12, land = 0.2,
              laser = 0.1, boom = 0.15, clear = 0.5 }
local ALIAS = { land = "launch" }   -- landing and firing are both very light ticks, share one throttle bucket
local last = {}

function S.Enabled()
    local db = DBR.db
    return not (db and db.sound == false)
end

-- Volume level 1~10 = number of same-frame stacked plays
function S.Volume()
    local db = DBR.db
    local v = (db and tonumber(db.soundVolume)) or 3
    if v < 1 then v = 1 elseif v > 10 then v = 10 end
    return math.floor(v + 0.5)
end

local function Emit(kit)
    -- forceNoDuplicates must be explicitly false: one, if the previous sound hasn't finished it would refuse to play and swallow consecutive collision sounds;
    -- two, "stacking for loudness" relies entirely on replaying the same sound in the same frame
    for _ = 1, S.Volume() do
        PlaySound(kit, "Master", false)
    end
end

function S.Play(kind)
    if not S.Enabled() then return end
    local kit = KITS[kind]
    if not kit then return end
    local bucket = ALIAS[kind] or kind
    local gap = GAP[bucket]
    if gap then
        local now = GetTime()
        if last[bucket] and (now - last[bucket]) < gap then return end
        last[bucket] = now
    end
    Emit(kit)
end

-- ------------------------------------------------------------
-- Mute checkbox (one on the start screen + one on the HUD, states sync with each other)
-- Textures handcrafted, not relying on UICheckButtonTemplate or other templates that may change
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
        if DBR.db then DBR.db.sound = on end
        S.SyncToggles()
        if on then Emit(KITS.brk) end   -- audible feedback when turning on, stay silent when turning off
    end)
    cb:SetScript("OnEnter", function(self)
        if not compact then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Sound toggle", 1, 1, 1)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    toggles[#toggles + 1] = cb
    return cb
end

-- ------------------------------------------------------------
-- Volume slider (levels 1~10, used on the start screen). Slider textures handcrafted, no template
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

    -- Programmatic refresh (on entering the panel / when the toggle was changed elsewhere): sync value + enabled state, without triggering a preview
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
        if DBR.db then DBR.db.soundVolume = v end
        self.valText:SetText(tostring(v))
        if not self._noPreview then Emit(KITS.brk) end   -- dragging previews the new volume
    end)

    volSliders[#volSliders + 1] = sl
    sl:Refresh()
    return sl
end
