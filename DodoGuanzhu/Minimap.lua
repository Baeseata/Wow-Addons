-- DodoGuanzhu :: Minimap.lua
-- 小地图环上的按钮。左键开设置面板,右键开关预览浮标,拖动沿环移动。
--
-- 手搓,不用 LibDBIcon:一个按钮 + 一个存盘的角度,不用带一个库、也不用跟着它升级。
-- ⚠ **这份文件的几何和 scale 处理逐字抄自 `DodoSays/Minimap.lua`**,包括那些看着像偏执的部分 ——
--    canon:抄久经考验的先例时,真正的工作量是列出「哪几处必须不一样」,而不是重写它聪明的地方。
--    必须不一样的只有三处:① 图标用能量灌注自己的 ② **不自建面板**(Options.lua 已经有了)
--    ③ 右键给浮标开关。其余一个字都别动。

local ADDON, ns = ...

local Mini = {}
ns.Mini = Mini

-- 🔴 半径**从小地图实时算**,别写死常量。
-- 别的插件和 UI 缩放都会改小地图大小 —— 一个"在这台机器上正确"的常量,
-- 正是那种换台机器就把按钮放到错地方的东西。
local function ring()
    local w = Minimap and Minimap:GetWidth() or nil
    if type(w) ~= "number" or w <= 0 then return 80 end
    return w / 2 + 10
end

-- ⚠ 图标路径错了的话,**客户端画一片空白而且一声不吭** ⇒ 按钮变白先查这儿。
-- 用能量灌注自己的图标(比鱼人头贴切);早期加载拿不到就先挂问号,SPELLS_CHANGED 再补。
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local function iconPath()
    local ok, tex = pcall(C_Spell.GetSpellTexture, ns.PI_SPELL_ID)
    if ok and tex then return tex end
    return FALLBACK_ICON
end

local button

local function place(angle)
    if not button or not Minimap then return end
    local rad, r = math.rad(angle or 200), ring()
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
end
Mini.Place = place

-- 🔴 这里的 scale 必须是**小地图的**,不是 UIParent 的。
--
-- `GetCenter()` 答的是框体**自己**的坐标系,而 `GetCursorPosition()` 答的是**屏幕原始像素**。
-- 拿 UIParent 的 scale 去除光标,结果落在 UIParent 的空间里 —— 只要有任何东西改过小地图大小
-- (多数配置都改过),那就是**另一个空间**。它造成的偏移既不小也不稳定:
-- 先例里的原话是「拖动的第一帧就把按钮甩出了屏幕」。
local function angleFromCursor()
    if not Minimap or type(GetCursorPosition) ~= "function" then return nil end

    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    if type(mx) ~= "number" or type(px) ~= "number"
        or type(scale) ~= "number" or scale == 0 then
        return nil
    end

    local dx, dy = px / scale - mx, py / scale - my
    if dx == 0 and dy == 0 then return nil end

    -- 5.1 有 math.atan2;之后的版本把它折进了两参数的 math.atan。
    local atan2 = math.atan2 or math.atan
    return math.deg(atan2(dy, dx))
end

function Mini.Build()
    if button or not Minimap then return button end

    button = CreateFrame("Button", "DodoGuanzhuMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    -- 🔴 几何**逐字抄自 LibDBIcon**:图标 17px 放在 TOPLEFT(7,-6),用 texcoord 把图标自带的
    -- 边框裁掉。它**不居中,而这正是重点** —— 环的美术本身就不居中,任何"算出来"的位置
    -- 都会明显偏高偏左。几百个插件用的就是这组数字,别自己算。
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(iconPath())
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.icon = icon

    local ringTex = button:CreateTexture(nil, "OVERLAY")
    ringTex:SetSize(53, 53)
    ringTex:SetPoint("TOPLEFT")
    ringTex:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnDragStart", function(self) self.dragging = true end)
    button:SetScript("OnDragStop", function(self) self.dragging = false end)
    button:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        local a = angleFromCursor()
        if not a then return end
        if ns.db then ns.db.minimapAngle = a end
        place(a)
    end)

    button:SetScript("OnClick", function(_, mouseBtn)
        if mouseBtn == "RightButton" then
            if ns.Preview and ns.Preview.Toggle then pcall(ns.Preview.Toggle) end
        else
            -- 🔴 pcall 要看返回值。第一版写的是裸 `pcall(ns.Options.Open)`,
            -- 于是 Open 里抛的任何错都被完整吞掉 ⇒ 真机症状是"左键点了毫无反应",
            -- 而右键(走 Preview.Toggle)正常 —— 一个"A 能用 B 不能用"的假象,
            -- 真相是两条路调的函数不同、坏的那条把自己的死因藏起来了。
            if not (ns.Options and ns.Options.Open) then
                ns.Print("设置面板(Options.lua)没加载。"); return
            end
            local ok, err = pcall(ns.Options.Open)
            if not ok then ns.Print("打开设置面板出错:" .. tostring(err)) end
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("DodoGuanzhu", 1, 1, 1)
        GameTooltip:AddLine("左键:打开设置", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("右键:开关预览浮标", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("拖动:沿环移动", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    place(ns.db and ns.db.minimapAngle or 200)
    return button
end

function Mini.Refresh()
    if button and button.icon then button.icon:SetTexture(iconPath()) end
end

-- ⚠ 建在 PLAYER_LOGIN 而不是 ADDON_LOADED:那会儿 Minimap 不保证在,
-- 而 ring() 要读它的宽度 —— 读不到就会回落到那个 80 的兜底常量,
-- 正好是本文件开头骂的那种"在这台机器上碰巧对"的值。
-- SPELLS_CHANGED 补一次图标:登录早期 GetSpellTexture 可能还没数据,那时挂的是问号。
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("SPELLS_CHANGED")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then Mini.Build() else Mini.Refresh() end
end)
