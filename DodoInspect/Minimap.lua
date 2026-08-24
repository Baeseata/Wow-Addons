-- DodoInspect - Minimap.lua
-- The button on the minimap ring. Left-click opens the loot browser
-- (LootPanel.lua), right-click opens this addon's settings, drag moves
-- it around the ring.
--
-- Hand-rolled rather than LibDBIcon: one button and one angle on disk,
-- with no library to ship or keep in step. DodoInspect goes to
-- CurseForge on its own and deliberately does not depend on the Dodo
-- parent package, so "just use the shared one" is not available here.
--
-- !! The geometry and the scale handling below are copied VERBATIM from
-- DodoSays/Minimap.lua, including the parts that look paranoid. Copying
-- a precedent that has already been proven is only safe if you can say
-- which parts MUST differ, so here they are -- and nothing else changed:
--   1. The icon is this addon's OWN art with a measured crop, not a game
--      icon with LibDBIcon's border crop. See Config.LOOT_MINIMAP_ICON.
--   2. The angle is persisted in DodoInspectDB, which is this addon's
--      only saved-variables table -- there is no ns.db here.
--   3. The default angle is 295, not 200 (see Config).
--   4. No panel is built in this file; LootPanel.lua owns the window.
--   5. Right-click opens the settings page instead of a second panel.
--   6. Tooltip lines come from ns.L -- this addon ships four languages.
--   7. The button can be switched off in the options, so there is an
--      Apply function; DodoSays' button is unconditional.

local _, ns = ...

local button

-- Derived from the minimap rather than written down: addons and UI scale
-- both resize it, and a constant that is right on this machine is
-- exactly the kind of thing that puts the button in the wrong place on
-- another one.
local function ring()
    local w = Minimap and Minimap:GetWidth() or nil
    if type(w) ~= "number" or w <= 0 then return 80 end
    return w / 2 + 10
end

local function SavedAngle()
    local db = DodoInspectDB
    local a = db and tonumber(db.lootMinimapAngle)
    return a or ns.Config.LOOT_MINIMAP_ANGLE
end

local function place(angle)
    if not button or not Minimap then return end
    local rad, r = math.rad(angle or ns.Config.LOOT_MINIMAP_ANGLE), ring()
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER",
                    math.cos(rad) * r, math.sin(rad) * r)
end

-- 🔴 The scale here must be the MINIMAP's, not UIParent's.
--
-- GetCenter() answers in the frame's own coordinate space, while
-- GetCursorPosition() answers in raw screen pixels. Dividing the cursor
-- by UIParent's scale lands it in UIParent's space -- a different space
-- whenever anything has resized the minimap, which is most setups. The
-- offset that creates is not small and not stable: in the addon this was
-- copied from, the first frame of a drag threw the button across the
-- screen.
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

    -- 5.1 has math.atan2; later versions fold it into a two-argument
    -- math.atan.
    local atan2 = math.atan2 or math.atan
    return math.deg(atan2(dy, dx))
end

function ns.LootMinimapEnabled()
    if ns.Config.LOOT_FEATURE_ENABLED ~= true then return false end
    return ns.IsEnabled("showLootMinimap")
end

function ns.SetupMinimapButton()
    if button or not Minimap then return button end

    button = CreateFrame("Button", "DodoInspectMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    -- Geometry lifted verbatim from LibDBIcon: 17px at TOPLEFT(7,-6).
    -- Not centred, and that is the point -- the ring artwork is not
    -- centred either, so anything placed by arithmetic ends up sitting
    -- visibly high and left. Hundreds of addons use these exact numbers.
    --
    -- The TEXCOORD is ours, not theirs: LibDBIcon's 0.07/0.93 exists to
    -- cut the border baked into Blizzard's icons, and Media/Dodo.tga has
    -- no border -- it has a transparent margin instead. See
    -- Config.LOOT_MINIMAP_CROP for how that number was measured.
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(ns.Config.LOOT_MINIMAP_ICON)
    local crop = ns.Config.LOOT_MINIMAP_CROP
    icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
    -- Checked rather than assumed: SetTexture fails SILENTLY on a bad
    -- path and leaves a blank button, which reads as "the addon is
    -- broken". A question mark is wrong but visible, and visible is the
    -- failure mode worth having.
    if icon:GetTexture() == nil then
        -- Same fallback DodoGuanzhu already runs in production on this
        -- machine, so the path is known to resolve. A file id would be a
        -- second unverified constant in the branch whose whole job is to
        -- rescue a first one that failed.
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end

    local ringTex = button:CreateTexture(nil, "OVERLAY")
    ringTex:SetSize(53, 53)
    ringTex:SetPoint("TOPLEFT")
    ringTex:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetHighlightTexture(
        "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnDragStart", function(self) self.dragging = true end)
    button:SetScript("OnDragStop", function(self) self.dragging = false end)
    button:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        local a = angleFromCursor()
        if not a then return end
        if DodoInspectDB then DodoInspectDB.lootMinimapAngle = a end
        place(a)
    end)

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            if Settings and Settings.OpenToCategory and ns.OptionsCategory then
                Settings.OpenToCategory(ns.OptionsCategory)
            end
            return
        end
        ns.ToggleLootPanel()
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("DodoInspect", 1, 1, 1)
        GameTooltip:AddLine((ns.L and ns.L.lootMiniClick) or "", 0.8, 0.8, 0.8)
        GameTooltip:AddLine((ns.L and ns.L.lootMiniRight) or "", 0.8, 0.8, 0.8)
        GameTooltip:AddLine((ns.L and ns.L.lootMiniDrag) or "", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    place(SavedAngle())
    return button
end

-- Options hook. Creating the button lazily on first enable keeps a user
-- who never wants it from paying for a frame at all; hiding rather than
-- destroying keeps the saved angle meaningful if they turn it back on.
--
-- The window is deliberately NOT closed here, and switching the button
-- off does not strand it: Escape closes it (UISpecialFrames) and
-- `/dins loot` opens it again. A hidden minimap button that also made
-- the feature unreachable would be a much bigger switch than its label
-- claims.
--
-- Defaults ON, like every other display toggle in this addon (owner
-- decision 2026-08-14). It is the only VISIBLE way in, so defaulting it
-- off would ship the feature switched off without saying so.
function ns.ApplyLootMinimapEnabled()
    if not ns.LootMinimapEnabled() then
        if button then button:Hide() end
        return
    end
    ns.SetupMinimapButton()
    if button then
        place(SavedAngle())
        button:Show()
    end
end
