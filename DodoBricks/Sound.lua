-- DodoBricks - Sound
-- 音效:复用魔兽自带 SoundKit(无自定义音频文件)。套路同 DodoPool/Sound.lua:
-- 选音表 KITS + 同类最小间隔节流 GAP + 静音勾选框 + 音量滑条(同帧叠播 N 次加响度)。
-- 种类:launch 发球 / hit 球碰砖(高频轻响) / brk 砖碎 / item 吃 +1 球 / land 首球落地
--       / descend 砖下压一行 / over 游戏结束 / best 新纪录。
-- 注:撞墙故意不配音(每秒太多次,只会吵)。

local DBR = _G.DodoBricks or {}
_G.DodoBricks = DBR

local S = {}
DBR.Sound = S

-- 选音:经 SOUNDKIT 常量表取条目,名字不存在则数字兜底;两者都没有就静默跳过该音。
-- 砖块游戏的碰撞声每秒几十次,故 hit/launch 选"轻"的 UI click(台球那边嫌轻,这里轻正合适);
-- 低频事件(碎砖/道具/下压/结束)才用响的。选音不满意参考 DodoPool 的迭代路径换 KITS 即可。
local SK = _G.SOUNDKIT or {}
local KITS = {
    launch  = SK.IG_MAINMENU_OPTION_CHECKBOX_ON or 856,   -- 发球:极轻嗒(高频,要轻)
    hit     = SK.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857,  -- 球碰砖:轻嗒(最高频,要轻)
    brk     = SK.MAP_PING or 3175,                        -- 砖碎:小地图 ping 轻"咚"
    item    = SK.LOOT_WINDOW_COIN_SOUND or 120,           -- 吃 +1 球:金币叮当(台球进袋同款,实测响度 OK)
    land    = SK.IG_MAINMENU_OPTION_CHECKBOX_ON or 856,   -- 首球落地(标记下回合发射点):极轻
    descend = SK.AUCTION_WINDOW_CLOSE or 5275,            -- 砖下压:木槌闷敲(每回合一次)
    over    = SK.IG_QUEST_FAILED or 846,                  -- 游戏结束:失败短音
    best    = SK.IG_QUEST_LIST_COMPLETE or 875,           -- 新纪录:任务完成钟声
}

-- 同类最小间隔(秒)。GetTime 一帧内不变 => 同帧子步进里的连环碰撞天然只响一下
local GAP = { hit = 0.06, launch = 0.09, brk = 0.09, item = 0.12, land = 0.2 }
local ALIAS = { land = "launch" }   -- 落地与发球同为极轻嗒,共用节流桶
local last = {}

function S.Enabled()
    local db = DBR.db
    return not (db and db.sound == false)
end

-- 音量档 1~10 = 同帧叠播次数
function S.Volume()
    local db = DBR.db
    local v = (db and tonumber(db.soundVolume)) or 3
    if v < 1 then v = 1 elseif v > 10 then v = 10 end
    return math.floor(v + 0.5)
end

local function Emit(kit)
    -- forceNoDuplicates 必须显式 false:一是上一声没播完会拒播吞掉连续碰撞声,
    -- 二是"叠播加响度"全靠同帧重复播同一音效
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
-- 静音勾选框(开始界面 + HUD 各一个,状态互相同步)
-- 贴图手搓,不依赖 UICheckButtonTemplate 之类可能变动的模板
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
        if DBR.db then DBR.db.sound = on end
        S.SyncToggles()
        if on then Emit(KITS.brk) end   -- 开启给声反馈,关闭保持安静
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
-- 音量滑条(1~10 档,开始界面用)。Slider 手搓贴图,不依赖模板
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

    -- 程序化刷新(进面板 / 别处改了开关时):同步值 + 可用态,不触发试听
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
        if not self._noPreview then Emit(KITS.brk) end   -- 拖动即试听新音量
    end)

    volSliders[#volSliders + 1] = sl
    sl:Refresh()
    return sl
end
