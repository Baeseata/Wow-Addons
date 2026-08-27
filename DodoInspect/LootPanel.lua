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
-- reads the PLAYER's own spec and hero tree, which are never secret,
-- and every other spec it offers is a plain number out of ns.SpecGear.
-- There is no inspect path into this window at all.

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
-- Which specialization the right column answers for
--------------------------------------------------------------------

-- Stored as an OVERRIDE, never as "the current spec".
--
-- An absent key means "whoever is logged in", so a fresh character is
-- shown its own drops without anyone touching the dropdowns. Persisting
-- the spec itself would mean logging in on an alt and being handed the
-- last character's list -- with the window looking completely normal,
-- because the code would be doing exactly what it was told. That is the
-- failure where the code is right and the STATE is wrong, and the cure
-- is to store the departure from the default rather than the default.
--
-- Second return value: is this the player's own spec? Only then can the
-- hero tree be read, and only then does it describe the spec on screen.
function ns.LootPanelSpec()
    local own = ns.PlayerSpecID and ns.PlayerSpecID() or nil
    local db = DodoInspectDB
    local stored = db and db.lootPanelSpec
    if stored then
        -- Validated against the index, not trusted: a saved-variables
        -- file can outlive a spec being removed from ns.SpecGear, and
        -- an unknown id would show an empty column forever.
        local index = ns.LootSpecIndex and ns.LootSpecIndex()
        if index and index.byID[stored] then return stored, stored == own end
    end
    return own, own ~= nil
end

-- Picking your OWN spec clears the override instead of storing it, so a
-- later respec is followed rather than frozen. The stored key then only
-- ever means one thing: "I am looking at somebody else's spec".
function ns.SetLootPanelSpec(specID)
    if DodoInspectDB then
        local own = ns.PlayerSpecID and ns.PlayerSpecID() or nil
        if specID == nil or specID == own then
            DodoInspectDB.lootPanelSpec = nil
        else
            DodoInspectDB.lootPanelSpec = specID
        end
    end
    retries = 0
    ns.RefreshLootPanel()
end

function ns.LootPanelClass()
    local specID = ns.LootPanelSpec()
    if not specID then return nil end
    local index = ns.LootSpecIndex and ns.LootSpecIndex()
    return index and index.classOf[specID] or nil
end

-- Changing class has to land on SOME spec, and which one is a real
-- choice. Landing on your own spec when you pick your own class is the
-- one that matches intent -- that click means "back to me" far more
-- often than it means "show me Arms". Everything else takes the class's
-- first spec.
function ns.SelectLootClass(classID)
    local index = ns.LootSpecIndex and ns.LootSpecIndex()
    local entry = index and index.byClass[classID]
    if not entry then return end
    if ns.LootPanelClass() == classID then return end
    local own = ns.PlayerSpecID and ns.PlayerSpecID() or nil
    if own and index.classOf[own] == classID then
        ns.SetLootPanelSpec(own)
    elseif entry.specs[1] then
        ns.SetLootPanelSpec(entry.specs[1].id)
    end
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
local ROW_H, DETAIL_HEAD_H, DROP_H, DROP_W
-- The dropdown template draws a fixed-height frame and a caret; below
-- roughly this it stops looking like a control you can open. The tab
-- row is the only thing that has to clear it, so the floor lives there.
local DROP_MIN_H = 20
-- Forward-declared: the drop rows are built well above the position
-- helpers, and a row's OnDragStop needs to save where the window landed.
-- Without this the closure would capture a GLOBAL of that name -- which
-- is nil -- and every drag by the right column would throw. luac cannot
-- see that; it is a perfectly legal call to a nil global.
local SavePosition

-- Headroom for the right column, in rows. NOT a measurement: the season
-- with the most drops for one source currently needs 14 (measured across
-- all 40 specs and all 17 cards), and the card list alone is about that
-- tall already, so this changes the window by roughly nothing today. It
-- is here so a bigger season grows the window instead of silently losing
-- its last rows -- and when it does overflow, the N/M count says so.
local MIN_DETAIL_ROWS = 16

local function Layout()
    FS       = ns.SidePanelFontSize()
    ICON     = math.floor(FS * 1.7)
    CARD_H   = ICON + 4
    GROUP_H  = math.floor(FS * 1.5)
    -- The tab row now also carries the class and spec dropdowns, so it
    -- has a floor: at the smallest font size FS * 1.9 is 15 pixels, and
    -- a 15-pixel dropdown is a sliver. Only the bottom of the slider
    -- range moves -- at the default size this is unchanged.
    TAB_H    = math.max(math.floor(FS * 1.9), DROP_MIN_H + 4)
    -- Wide enough for a boss name, not just a four-letter dungeon tag.
    -- Anything longer still clips on one line and the tooltip carries
    -- the full name; a wrapping card would make the rows different
    -- heights, and then the list stops scanning as a list.
    LEFT_W   = math.floor(FS * 11)
    RIGHT_W  = math.floor(FS * 26)
    -- Same row height as the gear panel: the two lists are read the same
    -- way and a different rhythm on each would look like a mistake.
    ROW_H         = math.floor(FS * 1.35)
    DETAIL_HEAD_H = math.floor(FS * 1.6)
    -- Sized like the mode tabs so the whole row reads as one strip, and
    -- split across the right column because that is what they filter.
    DROP_H = math.max(TAB_H - 4, DROP_MIN_H)
    DROP_W = math.floor((RIGHT_W - PAD) / 2)

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
    BODY_H = math.max(tallest, math.floor(FS * 14),
                      DETAIL_HEAD_H + ROW_H * MIN_DETAIL_ROWS)
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

    -- Anchored on all four corners so the container has a real height:
    -- the rows are capped to what fits inside it, and a frame with no
    -- bottom would report whatever height it was last given.
    panel.detail:ClearAllPoints()
    panel.detail:SetPoint("TOPLEFT", panel.body, "TOPRIGHT", PAD, 0)
    panel.detail:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, PAD)
    ns.SetOverlayFont(panel.detailTitle, FS)
    panel.detailNote:ClearAllPoints()
    panel.detailNote:SetPoint("TOPLEFT", panel.detail, "TOPLEFT", 0,
                              -DETAIL_HEAD_H)

    local tabW = math.floor(LEFT_W / 2) - 1
    panel.tabMythic:SetSize(tabW, TAB_H - 4)
    panel.tabRaid:SetSize(tabW, TAB_H - 4)

    -- The filters live in the tab row above the RIGHT column, not above
    -- the cards: they change what the right column lists, and the strip
    -- over there was empty anyway. Anchored off panel.body's top-right
    -- corner so they share one origin with panel.detail below them --
    -- two independent offsets from the frame would be two chances to
    -- disagree with a height that is recomputed on every refresh.
    if panel.classDrop then
        panel.classDrop:SetSize(DROP_W, DROP_H)
        panel.classDrop:ClearAllPoints()
        panel.classDrop:SetPoint("TOPLEFT", panel.body, "TOPRIGHT",
                                 PAD, TAB_H - 2)
        panel.specDrop:SetSize(DROP_W, DROP_H)
        panel.specDrop:ClearAllPoints()
        panel.specDrop:SetPoint("LEFT", panel.classDrop, "RIGHT", PAD, 0)
    end
end

--------------------------------------------------------------------
-- Right column: what the selected card drops
--------------------------------------------------------------------

-- Which upgrade ceiling this row's tooltip should render at.
--
-- 🔴 THE ONE THING NOT TO COPY FROM GearPanel. Its TooltipLink quotes
-- the Myth track (334 / 344), which is RAID gear. Mythic+ dungeon drops
-- cap at Hero 3/6 = ilvl 311, measured in game 2026-08-22 -- quoting 334
-- at them overstates every dungeon row by an upgrade tier and a half.
--
-- The mirror of that mistake is just as easy from here, and it did not
-- exist when Config.lua's comment was written: this window grew a RAID
-- half on 2026-08-24, and rendering a raid boss's drops at 311 would
-- understate them by 23 to 33 item levels. So the ceiling follows the
-- CARD, not the panel.
--
-- topItemLevel is a boolean ("does this piece reach 344"), not a number.
local function DetailBonusID(card, entryRow)
    if entryRow.offTrack then return nil end
    local cfg = ns.Config
    if card.kind == "dungeon" then return cfg.GEAR_HERO_BONUS_ID end
    return entryRow.topItemLevel and cfg.GEAR_TOP_BONUS_ID
           or cfg.GEAR_MYTH_BONUS_ID
end

local function NewDetailCell(row, justify)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- Four columns: name, the two stat cells, and where you already have it.
-- Widths are derived from the font size like everything else here, and
-- re-applied on every refresh because the slider can move underneath.
local function LayoutDetailRow(row, index)
    local statW  = math.floor(FS * 3.4)
    local ownedW = math.floor(FS * 6)
    -- The slot column carries the two-glyph abbreviation out of
    -- ns.L.slots (TR / RG / 1H ...), which is already translated in all
    -- four locales -- the CJK ones are one glyph wide, the Latin ones
    -- two, so this is sized for the wider of them.
    local slotW  = math.floor(FS * 2.4)
    local nameW  = RIGHT_W - slotW - statW * (ns.GEAR_STAT_COLS or 2)
                   - ownedW - 8

    row:SetSize(RIGHT_W, ROW_H)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel.detail, "TOPLEFT", 0,
                 -(DETAIL_HEAD_H + (index - 1) * ROW_H))

    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetWidth(nameW)
    ns.SetOverlayFont(row.name, FS)

    -- CENTER-anchored at the column's midpoint and deliberately NOT
    -- given a width. ns.SetStatCells draws the dominant-stat underline
    -- by anchoring it to this FontString's own BOTTOMLEFT/BOTTOMRIGHT,
    -- trimmed by a couple of pixels of side bearing -- so a FontString
    -- stretched to the full column width would underline the whole
    -- column instead of the two or three glyphs in it. Both other
    -- callers (the side panel and the gear panel) leave it natural for
    -- exactly this reason.
    row.slot:ClearAllPoints()
    row.slot:SetPoint("CENTER", row, "LEFT", nameW + slotW / 2, 0)
    ns.SetOverlayFont(row.slot, FS)

    for i = 1, #row.stats do
        row.stats[i]:ClearAllPoints()
        row.stats[i]:SetPoint("CENTER", row, "LEFT",
                              nameW + slotW + (i - 0.5) * statW, 0)
        ns.SetOverlayFont(row.stats[i], FS)
    end

    row.owned:ClearAllPoints()
    row.owned:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.owned:SetWidth(ownedW)
    ns.SetOverlayFont(row.owned, FS)
end

local function CreateDetailRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row.name = NewDetailCell(row, "LEFT")
    row.slot = NewDetailCell(row, "CENTER")
    row.stats, row.statLines = {}, {}
    for i = 1, (ns.GEAR_STAT_COLS or 2) do
        row.stats[i] = NewDetailCell(row, "CENTER")
        local line = row:CreateTexture(nil, "OVERLAY")
        line:SetHeight(1)
        line:Hide()
        row.statLines[i] = line
    end
    row.owned = NewDetailCell(row, "RIGHT")
    LayoutDetailRow(row, index)

    -- The real item tooltip is where item level, sockets and on-item
    -- effects live; the two stat cells deliberately do not fold those in.
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local link = self.bonusID and ns.GearTooltipLink
                     and ns.GearTooltipLink(self.itemID, self.bonusID)
        if link then
            GameTooltip:SetHyperlink(link)
        else
            GameTooltip:SetItemByID(self.itemID)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- The window has no title bar -- it is dragged by grabbing the frame
    -- itself. Up to sixteen mouse-enabled rows cover the whole right
    -- half, and a mouse-enabled child swallows the button rather than
    -- passing it up, so without this the right half stops moving the
    -- window. Forwarded rather than disabled: the mouse is what puts the
    -- item tooltip on screen.
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function()
        if panel and panel.StartMoving then panel:StartMoving() end
    end)
    row:SetScript("OnDragStop", function()
        if not panel then return end
        panel:StopMovingOrSizing()
        SavePosition()
    end)
    return row
end

local function Colored(text, color)
    if not color then return text end
    return string.format("|cff%02x%02x%02x%s|r", math.floor(color[1] * 255),
                         math.floor(color[2] * 255), math.floor(color[3] * 255),
                         text)
end

-- "Bags 305". The word and the number are kept apart rather than run
-- through one format string, because the item level can legitimately be
-- missing (an uncached link answers nothing) and a format string would
-- then print the word with a hole in it.
local function OwnedText(owned)
    if not owned then return "" end
    local L = ns.L or {}
    local word = (owned.where == "equipped" and L.lootOwnedEquipped)
              or (owned.where == "bank" and L.lootOwnedBank)
              or L.lootOwnedBags
    if not word then return "" end
    if owned.ilvl then return word .. " " .. owned.ilvl end
    return word
end

-- The item level every row in this list is being rendered at, READ BACK
-- off the very link the tooltips use rather than stated as a constant.
-- Config carries the bonus id; the item level that id produces is the
-- client's business, and writing "311" here as well would be the same
-- fact in two hand-written places, free to drift at the season roll.
--
-- Dungeons only: every M+ row shares one ceiling, so one number is
-- honest. A raid boss's drops do NOT -- armor from the last two
-- Venomous Abyss bosses reaches 344 while its rings and necks stay at
-- 334 -- so there is no single number to print and this says nothing.
local function DetailCeiling(card, list)
    if card.kind ~= "dungeon" then return nil end
    if not (C_Item and type(C_Item.GetDetailedItemLevelInfo) == "function") then
        return nil
    end
    for _, entryRow in ipairs(list) do
        local bonusID = DetailBonusID(card, entryRow)
        local link = bonusID and ns.GearTooltipLink
                     and ns.GearTooltipLink(entryRow.id, bonusID)
        if link then
            local ok, level = pcall(C_Item.GetDetailedItemLevelInfo, link)
            if ok and type(level) == "number" and level > 0 then return level end
        end
    end
    return nil
end

-- Draws the right column for one card. Returns true when it drew rows,
-- so the caller can tell "there is a list" from "there is a sentence".
-- Returns whether anything is still waiting on the item cache, so the
-- caller can fold it into the same retry the card labels already use.
--
-- C_Item.GetItemInfo answers nil until the client has the item, and for
-- season loot the player has never seen that is the NORMAL state on the
-- first open after login: without a retry the whole column sits on
-- "item:230187" strings, the ceiling label never appears (an uncached
-- link has no detailed item level either) and ns.DedupeByName cannot
-- collapse the returning dungeons' duplicate names, so the legacy twins
-- show up beside the modern ones. None of it repairs itself, because
-- nothing else redraws this panel.
local function RefreshDetail(card)
    panel.detailRows = panel.detailRows or {}
    local rows = panel.detailRows
    local cold = false

    local function Note(text)
        for i = 1, #rows do rows[i]:Hide() end
        panel.detailNote:SetText(text or "")
        panel.detailNote:Show()
        return false, false
    end

    local L = ns.L or {}
    if not card then
        panel.detailTitle:SetText("")
        return Note(L.lootPickSource)
    end

    -- Built as a local and set once at the end. Reading it back off the
    -- FontString later would make the heading depend on what a widget
    -- hands back, which is a round trip through the UI for a string this
    -- function already has.
    local heading = CardTooltip(card) or CardLabel(card) or ""
    panel.detailTitle:SetText(heading)

    -- Whichever spec the filter is on -- the player's own unless they
    -- picked another. Eight of the forty specs split their stat priority
    -- by hero tree, and SourceCandidates lists the drops either way; it
    -- just cannot rank them without one.
    local specID, isOwn = ns.LootPanelSpec()
    if not specID then return Note(L.lootNoSpec) end
    -- Written as a statement, not `isOwn and X and X() or nil`: that
    -- idiom collapses to the last branch the moment the middle term is
    -- falsy, and a hero tree legitimately IS nil before one is picked.
    local subTree
    if isOwn and ns.PlayerHeroSubTree then
        -- Only your own tree is readable, and it only describes your own
        -- spec. Handing it to somebody else's spec would rank their
        -- drops against your talents and never look wrong.
        subTree = ns.PlayerHeroSubTree()
    end
    local content = (card.kind == "dungeon") and "mythic" or "raid"

    local list, _, ranked = ns.SourceCandidates(card, specID, subTree, content)
    -- Two different item ids can carry the same name: the three
    -- returning dungeons still list their legacy pieces beside the
    -- modern namesakes, and one name printed twice reads as a bug.
    if list and ns.DedupeByName then list = ns.DedupeByName(list) end
    if not list or #list == 0 then return Note(L.lootNoDrops) end
    panel.detailNote:Hide()

    -- Capped to what fits, the same way the gear panel caps to its
    -- anchor -- rows drawn past the bottom edge do not error, they are
    -- just not there. Computed from BODY_H rather than asked of
    -- panel.detail: the container is anchored to exactly that height, so
    -- the widget can only ever agree, and asking it adds a way to be
    -- wrong (a frame that has not been laid out yet answers 0, which
    -- would silently cut the list to a single row).
    local cap = math.floor((BODY_H - DETAIL_HEAD_H) / math.max(1, ROW_H))
    if cap < 1 then cap = 1 end
    local shown = math.min(#list, cap)

    local owned = ns.LootOwnedIndex and ns.LootOwnedIndex() or {}

    for i = 1, shown do
        local entryRow = list[i]
        local row = rows[i]
        if not row then
            row = CreateDetailRow(panel.detail, i)
            rows[i] = row
        end
        LayoutDetailRow(row, i)
        row.itemID  = entryRow.id
        row.bonusID = DetailBonusID(card, entryRow)

        local name = C_Item.GetItemInfo(entryRow.id)
        if not name then
            cold = true
            -- Ask for it rather than only waiting: an item nobody has
            -- looked at is not loading on its own.
            if C_Item.RequestLoadItemDataByID then
                pcall(C_Item.RequestLoadItemDataByID, entryRow.id)
            end
        end
        -- Numbered only when there is a ranking behind the order.
        local label = ranked and string.format("%d. %s", i,
                                               name or ("item:" .. entryRow.id))
                      or (name or ("item:" .. entryRow.id))
        if entryRow.effect then
            label = label .. " " .. Colored("*", ns.Config.GEAR_EFFECT_COLOR)
        end
        row.name:SetText(label)

        local have = owned[entryRow.id]
        row.owned:SetText(Colored(OwnedText(have),
                                  have and ns.Config.LOOT_OWNED_COLOR or nil))

        -- Resolved from the client's own equip location, so no new
        -- strings: ns.L.slots already carries every one of these in all
        -- four languages, and the bag overlays have been printing them
        -- for months.
        local slots = ns.L and ns.L.slots
        row.slot:SetText((slots and entryRow.equipLoc
                          and slots[entryRow.equipLoc]) or "")
        local sc = ns.Config.LOOT_GROUP_COLOR
        row.slot:SetTextColor(sc[1], sc[2], sc[3], sc[4])

        ns.SetStatCells(row, entryRow, FS)
        row:Show()
    end
    for i = shown + 1, #rows do rows[i]:Hide() end

    local cap311 = DetailCeiling(card, list)
    if cap311 and L.lootCeiling then
        heading = heading .. "  " ..
                  Colored(string.format(L.lootCeiling, cap311),
                          ns.Config.LOOT_GROUP_COLOR)
    end
    -- Say WHY the rows lost their numbers. Without this, picking a spec
    -- whose priority splits by hero tree silently drops the ranking and
    -- the list still looks like a ranked one -- which reads as the
    -- numbering being broken rather than as an honest "there is no order
    -- to assert here". Eight of the forty specs land on this the moment
    -- you look at somebody else's.
    if not ranked and L.lootUnranked then
        heading = heading .. "  " ..
                  Colored(L.lootUnranked, ns.Config.LOOT_GROUP_COLOR)
    end
    -- Truncation has to be visible: a list quietly cut to fit reads as
    -- "these are all of them", which is the one thing it is not.
    if shown < #list then
        heading = heading .. string.format("  |cff808080%d/%d|r", shown, #list)
    end
    panel.detailTitle:SetText(heading)
    -- The ceiling label is read off a link, which is equally cold.
    if not cap311 and card.kind == "dungeon" then cold = true end
    return true, cold
end

-- Show and mouse-enable together, always. A Hidden frame is not
-- reliably out of the way of the cursor, and half of this pair is
-- exactly the kind of thing that gets forgotten at one of two call
-- sites -- so there is only one call site.
local function ShowDrop(drop, on)
    drop:SetShown(on)
    drop:EnableMouse(on)
end

-- Menu contents are rebuilt here rather than once at construction, the
-- same way DodoGuanzhu's list dropdown does it: the spec menu depends on
-- which class is selected, so "set it up once" would need the generator
-- to close over live state anyway, and the shipped-and-proven sequence
-- is SetupMenu -> SetDefaultText -> GenerateMenu.
--
-- Both radio callbacks read the selection back through the accessors
-- instead of closing over what it was when the menu was built. A menu
-- built before a respec would otherwise keep checking the old row.
local function RefreshDropdowns()
    local classDrop, specDrop = panel.classDrop, panel.specDrop
    -- Absent when the dropdown template could not be created; the rest
    -- of the window works without them and follows the player's spec.
    -- True, not nil: with no dropdowns there is nothing here for the
    -- retry to wait on, and answering "incomplete" would spend the
    -- whole retry budget on a question nobody asked.
    if not (classDrop and specDrop) then return true end

    local index, complete = ns.LootSpecIndex()
    if #index.classes == 0 then
        -- Nothing to choose between. Two empty controls invite clicks
        -- that do nothing, which is worse than no controls at all.
        ShowDrop(classDrop, false)
        ShowDrop(specDrop, false)
        return complete
    end
    ShowDrop(classDrop, true)
    ShowDrop(specDrop, true)

    local L = ns.L or {}
    local specID = ns.LootPanelSpec()
    local classID = ns.LootPanelClass()

    classDrop:SetupMenu(function(_, root)
        for _, entry in ipairs(index.classes) do
            local id = entry.classID
            root:CreateRadio(Colored(entry.name, entry.color),
                function() return ns.LootPanelClass() == id end,
                function() ns.SelectLootClass(id) end)
        end
    end)
    local classEntry = classID and index.byClass[classID]
    classDrop:SetDefaultText(classEntry
        and Colored(classEntry.name, classEntry.color) or L.lootClass or "")
    classDrop:GenerateMenu()

    specDrop:SetupMenu(function(_, root)
        -- Read at OPEN time, not captured: the class can change between
        -- two openings of this menu and the entries have to follow.
        local current = ns.LootPanelClass()
        local entry = current and index.byClass[current]
        for _, spec in ipairs(entry and entry.specs or {}) do
            local id = spec.id
            root:CreateRadio(spec.name,
                function() return (ns.LootPanelSpec()) == id end,
                function() ns.SetLootPanelSpec(id) end)
        end
    end)
    local specEntry = specID and index.byID[specID]
    specDrop:SetDefaultText(specEntry and specEntry.name or L.lootSpec or "")
    specDrop:GenerateMenu()
    return complete
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

    -- Before the detail: the right column asks LootPanelSpec, which
    -- validates a stored override against this same index.
    if not RefreshDropdowns() then cold = true end

    local _, detailCold = RefreshDetail(selection)
    if detailCold then cold = true end

    -- Listen for item data only while something is actually waiting on
    -- it. This event fires for every item the client resolves anywhere,
    -- so leaving it registered would redraw the panel constantly.
    if panel.RegisterEvent then
        if cold then panel:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        else panel:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
    end
    if cold then ScheduleRetry() end
end

--------------------------------------------------------------------
-- Construction, position, visibility
--------------------------------------------------------------------

-- Where the window was left. Stored as the full anchor tuple rather than
-- an offset from centre, so a UI scale or resolution change moves it the
-- same way Blizzard's own frames move.
function SavePosition()
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

    -- Class and specialization filters. Named and templated exactly the
    -- way DodoGuanzhu's shipping dropdown is -- WowStyle1DropdownTemplate
    -- with SetupMenu and CreateRadio, not the deprecated
    -- UIDropDownMenu_* family, which still works and so gives no signal
    -- at all when you write against it by mistake.
    --
    -- pcall'd because this is the one control here built from a Blizzard
    -- template that can be renamed out from under us: CreateFrame throws
    -- on an unknown template, and taking the whole window down over a
    -- filter would trade a missing convenience for a missing feature.
    -- Without them the panel simply follows the player's own spec, which
    -- is what it did before this step.
    local ok, classDrop = pcall(CreateFrame, "DropdownButton",
                                "DodoInspectLootClassDropdown", panel,
                                "WowStyle1DropdownTemplate")
    local okSpec, specDrop = pcall(CreateFrame, "DropdownButton",
                                   "DodoInspectLootSpecDropdown", panel,
                                   "WowStyle1DropdownTemplate")
    if ok and okSpec and classDrop and specDrop then
        panel.classDrop, panel.specDrop = classDrop, specDrop
    end

    -- Card container, so every card anchors to one origin instead of to
    -- the frame plus a running header offset.
    panel.body = CreateFrame("Frame", nil, panel)

    panel.divider = panel:CreateTexture(nil, "ARTWORK")
    panel.divider:SetColorTexture(1, 1, 1, 0.12)
    panel.divider:SetWidth(1)
    panel.divider:SetPoint("TOPLEFT", panel.body, "TOPRIGHT", PAD / 2, 0)
    panel.divider:SetPoint("BOTTOMLEFT", panel.body, "BOTTOMRIGHT", PAD / 2, 0)

    -- A real Frame, because the drop rows are its children. In step 3
    -- this was a FontString holding a "pick something on the left"
    -- placeholder; that line now lives in panel.detailNote.
    panel.detail = CreateFrame("Frame", nil, panel)

    panel.detailTitle = panel.detail:CreateFontString(nil, "OVERLAY")
    panel.detailTitle:SetJustifyH("LEFT")
    -- Anchored on both sides, so it has a fixed width -- and FontStrings
    -- wrap by default. The header reserve is one line tall, so a wrapped
    -- second line would draw straight over the first drop row.
    panel.detailTitle:SetWordWrap(false)
    panel.detailTitle:SetPoint("TOPLEFT", panel.detail, "TOPLEFT", 0, 0)
    panel.detailTitle:SetPoint("TOPRIGHT", panel.detail, "TOPRIGHT", 0, 0)

    -- Every "there is nothing to draw" answer, in one place. Which
    -- sentence it carries is the caller's business; a blank right column
    -- reads as a broken window whichever reason produced it.
    panel.detailNote = panel.detail:CreateFontString(nil, "OVERLAY",
                                                    "GameFontDisableSmall")
    panel.detailNote:SetJustifyH("LEFT")
    panel.detailNote:Hide()

    panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.empty:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 0, 0)
    panel.empty:Hide()

    -- The right column is derived from things that change underneath it
    -- while the window is open: what is in your bags, what you are
    -- wearing, and which spec you are. Without this you equip a piece
    -- out of your bags and the column still reads "Bags 305" -- forever,
    -- because nothing else redraws this panel.
    --
    -- Only ever acts while shown, so a closed browser costs nothing.
    -- GET_ITEM_INFO_RECEIVED is registered on demand instead (see the
    -- refresh): it fires constantly, and it is only interesting for as
    -- long as something in the list is still uncached.
    panel:RegisterEvent("BAG_UPDATE_DELAYED")
    panel:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    panel:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    panel:RegisterEvent("PLAYER_TALENT_UPDATE")
    panel:SetScript("OnEvent", function(self)
        if self:IsShown() then ns.RefreshLootPanel() end
    end)

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
