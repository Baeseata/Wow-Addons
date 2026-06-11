-- DodoRush - Sound
-- 音效:复用魔兽自带 SoundKit。套路同 DodoPool/DodoBricks:
-- 选音表 KITS + 同类最小间隔节流 GAP + 静音勾选框 + 音量滑条(同帧叠播 N 次加响度)。
-- 种类:start 开跑 / gate_good 吃增益门 / gate_bad 吃减益门 / clash 接敌 / tick 对撞消耗(高频,要轻)
--       / win 磨穿敌阵 / boss 击破 Boss 墙 / dodge 躲开散兵 / over 全军覆没 / best 新纪录。

local DR = _G.DodoRush or {}
_G.DodoRush = DR

local S = {}
DR.Sound = S

local SK = _G.SOUNDKIT or {}
local KITS = {
    start     = SK.IG_MAINMENU_OPTION_CHECKBOX_ON or 856,   -- 开跑:轻嗒
    gate_good = SK.LOOT_WINDOW_COIN_SOUND or 120,           -- 增益门:金币叮当(Bricks 吃球同款,响度实测 OK)
    gate_bad  = SK.AUCTION_WINDOW_CLOSE or 5275,            -- 减益门:木槌闷敲
    clash     = SK.AUCTION_WINDOW_OPEN or 5274,             -- 接敌:重木槌"砰"
    tick      = SK.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857,  -- 对撞掉人:轻嗒(最高频,要轻)
    win       = SK.MAP_PING or 3175,                        -- 磨穿敌阵:小地图 ping
    boss      = SK.IG_QUEST_LIST_COMPLETE or 875,           -- 击破 Boss:任务完成钟声
    dodge     = SK.IG_MAINMENU_OPTION_CHECKBOX_ON or 856,   -- 躲开散兵:轻嗒
    over      = SK.IG_QUEST_FAILED or 846,                  -- 全军覆没:失败短音
    best      = SK.IG_QUEST_LIST_COMPLETE or 875,           -- 新纪录:钟声
}

-- 同类最小间隔(秒)。GetTime 一帧内不变 => 同帧连环事件天然只响一下
local GAP = { tick = 0.07, gate_good = 0.12, gate_bad = 0.12, clash = 0.18,
              win = 0.2, dodge = 0.25, over = 0.3, best = 0.5, start = 0.3 }
local last = {}

function S.Enabled()
    local db = DR.db
    return not (db and db.sound == false)
end

-- 音量档 1~10 = 同帧叠播次数
function S.Volume()
    local db = DR.db
    local v = (db and tonumber(db.soundVolume)) or 3
    if v < 1 then v = 1 elseif v > 10 then v = 10 end
    return math.floor(v + 0.5)
end

local function Emit(kit)
    -- forceNoDuplicates 必须显式 false:一是上一声没播完会拒播,二是叠播加响度全靠同帧重复播
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
-- 静音勾选框(开始界面 + HUD 各一个,状态互相同步)
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
        cb.label:SetText("音效")
    end
    cb:SetScript("OnShow", function(self) self:SetChecked(S.Enabled()) end)
    cb:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if DR.db then DR.db.sound = on end
        S.SyncToggles()
        if on then Emit(KITS.win) end   -- 开启给声反馈,关闭保持安静
    end)
    cb:SetScript("OnEnter", function(self)
        if not compact then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("音效开关", 1, 1, 1)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    toggles[#toggles + 1] = cb
    return cb
end

-- ------------------------------------------------------------
-- 音量滑条(1~10 档,开始界面用)
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
    sl.caption:SetText("音量")
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
        if not self._noPreview then Emit(KITS.win) end   -- 拖动即试听新音量
    end)

    volSliders[#volSliders + 1] = sl
    sl:Refresh()
    return sl
end
