-- DodoInspect - LootPanel.lua
-- The standalone "what drops where" browser, opened from the minimap
-- button (Minimap.lua) or with /dins loot.
--
-- Left column: a mode switch (Mythic+ / Raid) over a list of source
-- cards -- this season's eight dungeons, or its nine raid bosses.
-- Right column: the drops for whichever card is selected.
--
-- WHY IT IS NOT DOCKED TO THE MYTHIC+ UI: the original design hung this
-- off ChallengesFrame's right edge. RaiderIO already puts its own panel
-- there, and two addons fighting over one anchor is a bug report waiting
-- to happen. Owner's call 2026-08-24: free-floating window, minimap
-- button, remembers where you left it.
--
-- The card list itself is DERIVED, not written here -- see
-- ns.LootCardList in LootSource.lua. This file only draws it.
--
-- SECRET VALUES: nothing in this file reads unit data. The spec filter
-- (step 5) will read the PLAYER's own spec, which is never secret out of
-- combat, and there is no inspect path into this window at all.

local _, ns = ...

local panel
-- Mode and selection are persisted; position is too. All three are
-- read through accessors rather than touched directly, because
-- DodoInspectDB does not exist until ADDON_LOADED and this file's
-- functions can be reached from a slash command before then.
local RETRY_LIMIT = 6
local retries = 0

function ns.LootPanelMode()
    local db = DodoInspectDB
    if db and db.lootPanelMode == "raid" then return "raid" end
    return "mythic"
end

function ns.SetLootPanelMode(mode)
    mode = (mode == "raid") and "raid" or "mythic"
    if DodoInspectDB then DodoInspectDB.lootPanelMode = mode end
    retries = 0
    ns.RefreshLootPanel()
end

-- Selection is stored PER MODE. One shared slot would mean switching to
-- Raid and back landed you on whatever card happened to share the index,
-- which reads as the window forgetting where you were.
local function SelectedKey(mode)
    local db = DodoInspectDB
    return db and db.lootPanelPick and db.lootPanelPick[mode] or nil
end

function ns.LootPanelSelection()
    local mode = ns.LootPanelMode()
    local list = ns.LootCardList and ns.LootCardList(mode)
    if not list or #list == 0 then return nil end
    local want = SelectedKey(mode)
    for _, card in ipairs(list) do
        if card.key == want then return card end
    end
    -- Nothing stored, or the stored key is from a season that has moved
    -- on. Fall back to the first card rather than showing an empty right
    -- column: a browser that opens on nothing looks broken.
    return list[1]
end

function ns.SelectLootCard(card)
    if not card or not card.key then return end
    if DodoInspectDB then
        DodoInspectDB.lootPanelPick = DodoInspectDB.lootPanelPick or {}
        DodoInspectDB.lootPanelPick[ns.LootPanelMode()] = card.key
    end
    ns.RefreshLootPanel()
end

--------------------------------------------------------------------
-- Geometry
--------------------------------------------------------------------

-- Derived from the side panel's font size, like GearPanel: one slider in
-- the options moves every panel this addon draws, and a third
-- independent size control would be one more thing to explain.
-- Recomputed on every refresh, because that slider can move while this
-- window is open.
local PAD = 10
local HEADER_H = 26
local FS, ICON, CARD_H, GROUP_H, LEFT_W, RIGHT_W, TAB_H, BODY_H

local function Layout()
    FS       = ns.SidePanelFontSize()
    ICON     = math.floor(FS * 1.7)
    CARD_H   = ICON + 4
    GROUP_H  = math.floor(FS * 1.5)
    TAB_H    = math.floor(FS * 1.9)
    -- Wide enough for a boss name, not just a four-letter dungeon tag.
    -- Anything longer still clips on one line and the tooltip carries
    -- the full name; a wrapping card would make the rows different
    -- heights, and then the list stops scanning as a list.
    LEFT_W   = math.floor(FS * 11)
    RIGHT_W  = math.floor(FS * 26)

    -- Height is the TALLER of the two modes, always. Sizing to the
    -- current mode would make the window jump every time the switch is
    -- clicked, and a window that resizes under the cursor is the kind of
    -- thing people report as flicker.
    local tallest = 0
    for _, mode in ipairs({ "mythic", "raid" }) do
        local list = ns.LootCardList and ns.LootCardList(mode)
        local h = 0
        for _, card in ipairs(list or {}) do
            h = h + CARD_H + (card.groupFirst and GROUP_H or 0)
        end
        if h > tallest then tallest = h end
    end
    BODY_H = math.max(tallest, math.floor(FS * 14))
end

--------------------------------------------------------------------
-- Card icons and labels
--------------------------------------------------------------------

-- Both lookups are allowed to answer nothing, and both are wrapped:
-- GetMapUIInfo is declared MayReturnNothing, and EJ_GetCreatureInfo
-- needs the Encounter Journal loaded, which it is not on a cold login.
-- A nil answer hides the icon and leaves the label alone rather than
-- drawing a placeholder -- see the retry below, which is what actually
-- fixes it a moment later.
local function CardIcon(card)
    if card.kind == "dungeon" then
        if not (card.mapID and C_ChallengeMode
                and C_ChallengeMode.GetMapUIInfo) then return nil end
        local ok, _, _, _, texture = pcall(C_ChallengeMode.GetMapUIInfo,
                                           card.mapID)
        if ok and texture then return texture end
        return nil
    end
    local api = _G.EJ_GetCreatureInfo
    if type(api) ~= "function" then return nil end
    local ok, _, _, _, _, iconImage = pcall(api, 1, card.encounterID)
    if ok and iconImage then return iconImage end
    return nil
end

-- The card's short label. Dungeons get the hand-written acronym (the one
-- thing in this feature that is not resolved from game data); bosses get
-- their own localized name, which needs no shortening scheme because the
-- client already ships it in every language.
local function CardLabel(card)
    if card.kind == "dungeon" then
        local perLocale = ns.L and ns.L.dungeonShort
        return (perLocale and perLocale[card.instanceID])
               or (ns.DungeonShort and ns.DungeonShort[card.instanceID])
               or tostring(card.instanceID)
    end
    return (ns.LootBossName and ns.LootBossName(card.encounterID)) or nil
end

-- Full name for the hover tooltip: the localized instance name, plus the
-- boss's position in the raid so "#3" matches what the loot-source line
-- on an item tooltip already says.
local function CardTooltip(card)
    local instance = ns.LootInstanceName and ns.LootInstanceName(card.instanceID)
    if card.kind == "dungeon" then return instance end
    local boss = ns.LootBossName and ns.LootBossName(card.encounterID)
    if not (instance and boss) then return instance or boss end
    return string.format("%s  #%d %s", instance, card.position or 0, boss)
end

--------------------------------------------------------------------
-- Card widgets
--------------------------------------------------------------------

-- The key of the card the right column is currently showing. Cached on
-- refresh rather than re-derived per card: ApplyCardLook also runs on
-- every mouse enter and leave, and LootPanelSelection walks the list.
local selectedKey

local function ApplyCardLook(button)
    local cfg = ns.Config
    local selected = button.cardKey ~= nil and button.cardKey == selectedKey
    local color = selected and cfg.LOOT_CARD_SELECTED_COLOR
                  or (button.hovered and cfg.LOOT_CARD_HOVER_COLOR
                                     or cfg.LOOT_CARD_IDLE_COLOR)
    button.label:SetTextColor(color[1], color[2], color[3], color[4])
    -- The selected card keeps its backing lit; hover only brightens it.
    -- A card list where nothing is visibly current reads as "click did
    -- not register", which is the whole reason the right column looks
    -- like it did not update.
    button.bg:SetShown(selected or button.hovered)
    button.bg:SetColorTexture(color[1], color[2], color[3],
                              selected and 0.22 or 0.10)
end

local function CreateCard(parent)
    local button = CreateFrame("Button", nil, parent)
    button:RegisterForClicks("LeftButtonUp")

    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.bg:Hide()

    button.icon = button:CreateTexture(nil, "ARTWORK")
    -- Blizzard's dungeon and boss art carries its own border. Same crop
    -- every icon in this addon uses, so the cards match the bag overlay.
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    button.label = button:CreateFontString(nil, "OVERLAY")
    -- A FontString with no font template throws on SetText. This addon
    -- has shipped that bug twice (1.1.1 TargetInfo, then GearPanel.NewCell)
    -- -- house rule: CreateFontString without a template is always
    -- followed by ns.SetOverlayFont.
    ns.SetOverlayFont(button.label, FS)
    button.label:SetWordWrap(false)
    button.label:SetJustifyH("LEFT")

    button:SetScript("OnEnter", function(self)
        self.hovered = true
        ApplyCardLook(self)
        local text = self.card and CardTooltip(self.card)
        if not text then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        self.hovered = false
        ApplyCardLook(self)
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function(self)
        if self.card then ns.SelectLootCard(self.card) end
    end)
    return button
end

local function CreateGroupLabel(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns.SetOverlayFont(fs, FS)
    fs:SetWordWrap(false)
    fs:SetJustifyH("LEFT")
    return fs
end

--------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------

-- Names and icons arrive late: the Encounter Journal is load-on-demand
-- and its data is cold for a moment after it loads. Rather than draw
-- placeholders, draw what we have and come back.
--
-- BOUNDED on purpose. An unbounded "retry until everything resolves"
-- becomes a permanent half-second timer on any client where one of these
-- lookups never answers, and nothing on screen would ever say so.
local function ScheduleRetry()
    if retries >= RETRY_LIMIT then return end
    retries = retries + 1
    C_Timer.After(0.4, function()
        if panel and panel:IsShown() then ns.RefreshLootPanel() end
    end)
end

-- Everything whose position or size is DERIVED from the font size, in
-- one place. Called from the refresh rather than only at build time: the
-- options slider can move while this window is open, and an anchor set
-- once then quietly disagrees with a height that is recomputed every
-- refresh -- which shows up as the card list creeping over the tabs
-- rather than as an error.
--
-- Deliberately not duplicated in SetupLootPanel. Two hand-written copies
-- of the same layout is a silent-divergence generator; every path that
-- shows this window refreshes it, so one copy is enough.
local function ApplyChrome()
    panel.body:ClearAllPoints()
    panel.body:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(HEADER_H + TAB_H))
    panel.body:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, PAD)
    panel.body:SetWidth(LEFT_W)

    panel.detail:ClearAllPoints()
    panel.detail:SetPoint("TOPLEFT", panel.body, "TOPRIGHT", PAD, 0)
    panel.detail:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -(HEADER_H + TAB_H))

    local tabW = math.floor(LEFT_W / 2) - 1
    panel.tabMythic:SetSize(tabW, TAB_H - 4)
    panel.tabRaid:SetSize(tabW, TAB_H - 4)
end

function ns.RefreshLootPanel()
    if not panel then return end
    Layout()

    local mode = ns.LootPanelMode()
    local list = (ns.LootCardList and ns.LootCardList(mode)) or {}
    local selection = ns.LootPanelSelection()
    selectedKey = selection and selection.key or nil

    panel:SetWidth(PAD * 2 + LEFT_W + PAD + RIGHT_W)
    panel:SetHeight(HEADER_H + TAB_H + BODY_H + PAD * 2)

    ApplyChrome()

    panel.title:SetText((ns.L and ns.L.lootTitle) or "")
    panel.tabMythic:SetText((ns.L and ns.L.lootTabMythic) or "M+")
    panel.tabRaid:SetText((ns.L and ns.L.lootTabRaid) or "Raid")
    -- The switch says which mode you are IN, so the button for the mode
    -- you are already in is the disabled one. Both stay visible: their
    -- pair is what tells you the other mode exists at all.
    panel.tabMythic:SetEnabled(mode ~= "mythic")
    panel.tabRaid:SetEnabled(mode ~= "raid")

    if #list == 0 then
        panel.empty:SetText((ns.L and ns.L.lootNoData) or "")
        panel.empty:Show()
    else
        panel.empty:Hide()
    end

    panel.cards = panel.cards or {}
    panel.groups = panel.groups or {}

    local cold = false
    local y, usedCards, usedGroups = 0, 0, 0
    for _, card in ipairs(list) do
        if card.groupFirst then
            usedGroups = usedGroups + 1
            local fs = panel.groups[usedGroups]
            if not fs then
                fs = CreateGroupLabel(panel.body)
                panel.groups[usedGroups] = fs
            end
            ns.SetOverlayFont(fs, FS)
            local name = ns.LootInstanceName and ns.LootInstanceName(card.instanceID)
            if not name then cold = true end
            fs:SetText(name or "")
            fs:SetWidth(LEFT_W)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 0, -y)
            local c = ns.Config.LOOT_GROUP_COLOR
            fs:SetTextColor(c[1], c[2], c[3], c[4])
            fs:Show()
            y = y + GROUP_H
        end

        usedCards = usedCards + 1
        local button = panel.cards[usedCards]
        if not button then
            button = CreateCard(panel.body)
            panel.cards[usedCards] = button
        end
        button.card = card
        button.cardKey = card.key
        button:SetSize(LEFT_W, CARD_H)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 0, -y)

        local texture = CardIcon(card)
        if texture then
            button.icon:SetTexture(texture)
            button.icon:SetSize(ICON, ICON)
            button.icon:ClearAllPoints()
            button.icon:SetPoint("LEFT", button, "LEFT", 2, 0)
            button.icon:Show()
        else
            cold = true
            button.icon:Hide()
        end

        ns.SetOverlayFont(button.label, FS)
        local label = CardLabel(card)
        if not label then cold = true end
        button.label:SetText(label or "")
        button.label:ClearAllPoints()
        -- The label starts after the icon's slot whether or not the icon
        -- resolved, so a cold card does not shift left and then jump
        -- right when its art arrives.
        button.label:SetPoint("LEFT", button, "LEFT", ICON + 6, 0)
        button.label:SetWidth(LEFT_W - ICON - 8)
        ApplyCardLook(button)
        button:Show()
        y = y + CARD_H
    end

    for i = usedCards + 1, #panel.cards do panel.cards[i]:Hide() end
    for i = usedGroups + 1, #panel.groups do panel.groups[i]:Hide() end

    -- Right column is step 4. Until then it says what it is waiting for
    -- rather than sitting blank, which reads as a broken window.
    ns.SetOverlayFont(panel.detail, FS)
    panel.detail:SetText((ns.L and ns.L.lootPickSource) or "")

    if cold then ScheduleRetry() end
end

--------------------------------------------------------------------
-- Construction, position, visibility
--------------------------------------------------------------------

-- Where the window was left. Stored as the full anchor tuple rather than
-- an offset from centre, so a UI scale or resolution change moves it the
-- same way Blizzard's own frames move.
local function SavePosition()
    if not (panel and DodoInspectDB) then return end
    local point, _, relPoint, x, y = panel:GetPoint(1)
    if not point then return end
    DodoInspectDB.lootPanelPoint = { point, relPoint, x, y }
end

local function RestorePosition()
    local saved = DodoInspectDB and DodoInspectDB.lootPanelPoint
    panel:ClearAllPoints()
    if type(saved) == "table" and type(saved[1]) == "string" then
        -- Guarded rather than trusted: a saved-variables file edited by
        -- hand (or written by an older layout) can carry anything, and
        -- SetPoint with a bad anchor throws.
        local ok = pcall(panel.SetPoint, panel, saved[1], UIParent,
                         saved[2] or saved[1], saved[3] or 0, saved[4] or 0)
        if ok then return end
    end
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

function ns.SetupLootPanel()
    if panel then return panel end
    Layout()

    -- Named, because UISpecialFrames takes a global name -- that is what
    -- makes Escape close this window like every other one.
    panel = CreateFrame("Frame", "DodoInspectLootPanel", UIParent,
                        "BackdropTemplate")
    panel:SetFrameStrata("HIGH")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:Hide()

    if type(UISpecialFrames) == "table" then
        tinsert(UISpecialFrames, "DodoInspectLootPanel")
    end

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -8)

    panel.close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    panel.close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
    panel.close:SetScript("OnClick", function() ns.HideLootPanel() end)

    -- Mode switch. Two buttons rather than one that toggles its own
    -- label: with a single button there is no way to tell "press me to
    -- go to Raid" from "you are in Raid", and this addon has already
    -- been bitten by a control whose label was also its state.
    panel.tabMythic = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.tabMythic:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -HEADER_H)
    panel.tabMythic:SetScript("OnClick", function()
        ns.SetLootPanelMode("mythic")
    end)

    panel.tabRaid = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.tabRaid:SetPoint("LEFT", panel.tabMythic, "RIGHT", 2, 0)
    panel.tabRaid:SetScript("OnClick", function()
        ns.SetLootPanelMode("raid")
    end)

    -- Card container, so every card anchors to one origin instead of to
    -- the frame plus a running header offset.
    panel.body = CreateFrame("Frame", nil, panel)

    panel.divider = panel:CreateTexture(nil, "ARTWORK")
    panel.divider:SetColorTexture(1, 1, 1, 0.12)
    panel.divider:SetWidth(1)
    panel.divider:SetPoint("TOPLEFT", panel.body, "TOPRIGHT", PAD / 2, 0)
    panel.divider:SetPoint("BOTTOMLEFT", panel.body, "BOTTOMRIGHT", PAD / 2, 0)

    panel.detail = panel:CreateFontString(nil, "OVERLAY")
    ns.SetOverlayFont(panel.detail, FS)
    panel.detail:SetJustifyH("LEFT")

    panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.empty:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 0, 0)
    panel.empty:Hide()

    RestorePosition()
    return panel
end

function ns.ShowLootPanel()
    if ns.Config.LOOT_FEATURE_ENABLED ~= true then return end
    ns.SetupLootPanel()
    -- Ask for the Encounter Journal before the first draw: boss names and
    -- boss art both come from it, and asking here means the usual case is
    -- one draw rather than a draw plus a retry.
    if ns.EnsureEncounterJournal then ns.EnsureEncounterJournal() end
    retries = 0
    panel:Show()
    ns.RefreshLootPanel()
end

function ns.HideLootPanel()
    if panel then panel:Hide() end
end

function ns.ToggleLootPanel()
    if panel and panel:IsShown() then
        ns.HideLootPanel()
    else
        ns.ShowLootPanel()
    end
end

function ns.LootPanelShown()
    return panel ~= nil and panel:IsShown()
end
