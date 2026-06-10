-- DodoPool - Sound
-- 音效:复用魔兽自带 SoundKit(无自定义音频文件)。
-- 种类:cue 出杆 / clack 球碰球(脆) / soft 轻碰、滑杆、放球 / rail 撞库 / pocket 进袋 / win 胜利 / foul 犯规。
-- 同类音带最小间隔节流(子步进一帧多次碰撞只响一下);开关存 DodoPoolDB.sound,开始界面与 HUD 各一个勾选框。
-- 音量:WoW 的 PlaySound 没有音量参数 => 同帧把同一音效叠播 N 次(振幅叠加变响),
--       N = DodoPoolDB.soundVolume(1~10 档,开始界面滑条,默认 3)。叠播只能加响,
--       真正决定底子的是选音:音源本身轻(如 UI 点击声),叠几档都轻。

local DP = _G.DodoPool or {}
_G.DodoPool = DP

local S = {}
DP.Sound = S

-- 选音:经 SOUNDKIT 常量表取条目,名字不存在则数字兜底;两者都没有就静默跳过该音
local SK = _G.SOUNDKIT or {}
local KITS = {
    cue    = SK.IG_ABILITY_ICON_DROP or 838,                -- 出杆:闷击
    clack  = SK.AUCTION_WINDOW_OPEN or 5274,                -- 球碰球(重):拍卖行木槌,响且是木头撞击声
    soft   = SK.MAP_PING or 3175,                           -- 轻碰 / 滑杆 / 放自由球:小地图 ping 轻"咚"
    rail   = SK.AUCTION_WINDOW_CLOSE or 5275,               -- 撞库:木槌闷敲
    -- 选音变迁:碰撞三件套最初用 UI 点击声(856/1115/857)太轻 -> MAP_PING 仍轻 -> 木槌。
    -- 还嫌轻的下一步是往 media/ 塞自己的台球 ogg 走 PlaySoundFile(插件内文件路径仍支持)。
    pocket = SK.LOOT_WINDOW_COIN_SOUND or 120,              -- 进袋:金币叮当
    win    = SK.IG_QUEST_LIST_COMPLETE or 875,              -- 胜利:任务完成钟声
    foul   = SK.IG_QUEST_FAILED or 846,                     -- 犯规:失败短音
}

-- 同类最小间隔(秒)。GetTime 一帧内不变 => 同帧子步进里的连环碰撞天然只响第一下
local GAP = { clack = 0.07, soft = 0.07, rail = 0.09, pocket = 0.15 }
local ALIAS = { soft = "clack" }   -- soft 与 clack 都是球碰球,共用节流桶
local last = {}

function S.Enabled()
    local db = DP.db
    return not (db and db.sound == false)
end

-- 音量档 1~10 = 同帧叠播次数
function S.Volume()
    local db = DP.db
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

function S.CreateToggle(parent)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(24, 24)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 1, 0)
    cb.label:SetText("音效")
    cb:SetScript("OnShow", function(self) self:SetChecked(S.Enabled()) end)
    cb:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if DP.db then DP.db.sound = on end
        S.SyncToggles()
        if on then Emit(KITS.clack) end   -- 开启给声反馈,关闭保持安静
    end)
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
        if DP.db then DP.db.soundVolume = v end
        self.valText:SetText(tostring(v))
        if not self._noPreview then Emit(KITS.clack) end   -- 拖动即试听新音量
    end)

    volSliders[#volSliders + 1] = sl
    sl:Refresh()
    return sl
end
