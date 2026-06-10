-- DodoPool - Sound
-- 音效:复用魔兽自带 SoundKit(无自定义音频文件)。
-- 种类:cue 出杆 / clack 球碰球(脆) / soft 轻碰、滑杆、放球 / rail 撞库 / pocket 进袋 / win 胜利 / foul 犯规。
-- 同类音带最小间隔节流(子步进一帧多次碰撞只响一下);开关存 DodoPoolDB.sound,开始界面与 HUD 各一个勾选框。

local DP = _G.DodoPool or {}
_G.DodoPool = DP

local S = {}
DP.Sound = S

-- 选音:经 SOUNDKIT 常量表取条目,名字不存在则数字兜底;两者都没有就静默跳过该音
local SK = _G.SOUNDKIT or {}
local KITS = {
    cue    = SK.IG_ABILITY_ICON_DROP or 838,                -- 出杆:闷击
    clack  = SK.IG_MAINMENU_OPTION_CHECKBOX_ON or 856,      -- 球碰球:脆响
    soft   = SK.U_CHAT_SCROLL_BUTTON or 1115,               -- 轻碰 / 滑杆 / 放自由球:轻嗒
    rail   = SK.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857,     -- 撞库:闷嗒
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
    -- forceNoDuplicates 必须显式 false:否则上一声没播完会拒播,连续碰撞声被吞
    PlaySound(kit, "Master", false)
end

-- ------------------------------------------------------------
-- 静音勾选框(开始界面 + HUD 各一个,状态互相同步)
-- 贴图手搓,不依赖 UICheckButtonTemplate 之类可能变动的模板
-- ------------------------------------------------------------
local toggles = {}

function S.SyncToggles()
    local on = S.Enabled()
    for _, cb in ipairs(toggles) do cb:SetChecked(on) end
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
        if on then PlaySound(KITS.clack, "Master", false) end   -- 开启给声反馈,关闭保持安静
    end)
    toggles[#toggles + 1] = cb
    return cb
end
