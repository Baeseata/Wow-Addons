-- DodoPool - Sound
-- Sound effects: reuse WoW's built-in SoundKit (no custom audio files).
-- Kinds: cue (cue strike) / clack (ball-on-ball, sharp) / soft (light tap, miscue slide, ball placement) / rail (cushion hit) / pocket (pocketed) / win (victory) / foul.
-- Minimum-interval throttle per kind (so a multi-collision sub-step within one frame only sounds once); the toggle is stored in DodoPoolDB.sound, with one checkbox on the start screen and one on the HUD.
-- Volume: WoW's PlaySound has no volume parameter => play the same sound N times in the same frame (amplitude stacks, gets louder),
--       N = DodoPoolDB.soundVolume (levels 1~10, start-screen slider, default 3). Stacking can only add loudness;
--       what really sets the baseline is the sound choice: if the source is quiet (e.g. a UI click), it stays quiet at any level.

local DP = _G.DodoPool or {}
_G.DodoPool = DP

local S = {}
DP.Sound = S

-- Sound choice: look entries up in the SOUNDKIT constant table; if the name is missing fall back to the number; if neither exists, silently skip that sound
local SK = _G.SOUNDKIT or {}
local KITS = {
    cue    = SK.IG_ABILITY_ICON_DROP or 838,                -- cue strike: muffled knock
    clack  = SK.AUCTION_WINDOW_OPEN or 5274,                -- ball-on-ball (hard): auction-house mallet, loud and wood-on-wood
    soft   = SK.MAP_PING or 3175,                           -- light tap / miscue slide / placing ball-in-hand: minimap ping, a soft "tock"
    rail   = SK.AUCTION_WINDOW_CLOSE or 5275,               -- cushion hit: muffled mallet
    -- Sound-choice history: the collision trio first used UI click sounds (856/1115/857), too quiet -> MAP_PING still quiet -> mallet.
    -- The next step if still too quiet is to drop our own pool ogg into media/ and use PlaySoundFile (in-addon file paths are still supported).
    pocket = SK.LOOT_WINDOW_COIN_SOUND or 120,              -- pocketed: coin jingle
    win    = SK.IG_QUEST_LIST_COMPLETE or 875,              -- victory: quest-complete chime
    foul   = SK.IG_QUEST_FAILED or 846,                     -- foul: short failure tone
}

-- Minimum interval per kind (seconds). GetTime is constant within a frame => chained collisions in the same sub-step naturally only sound on the first
local GAP = { clack = 0.07, soft = 0.07, rail = 0.09, pocket = 0.15 }
local ALIAS = { soft = "clack" }   -- soft and clack are both ball-on-ball, share one throttle bucket
local last = {}

function S.Enabled()
    local db = DP.db
    return not (db and db.sound == false)
end

-- Volume level 1~10 = number of same-frame stacked plays
function S.Volume()
    local db = DP.db
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

function S.CreateToggle(parent)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(24, 24)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 1, 0)
    cb.label:SetText("Sound")
    cb:SetScript("OnShow", function(self) self:SetChecked(S.Enabled()) end)
    cb:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if DP.db then DP.db.sound = on end
        S.SyncToggles()
        if on then Emit(KITS.clack) end   -- audible feedback when turning on, stay silent when turning off
    end)
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
        if DP.db then DP.db.soundVolume = v end
        self.valText:SetText(tostring(v))
        if not self._noPreview then Emit(KITS.clack) end   -- dragging previews the new volume
    end)

    volSliders[#volSliders + 1] = sl
    sl:Refresh()
    return sl
end
