-- DodoInspect - tools/test_lootpanel.lua
-- Offline smoke test for the loot browser's DRAW path. Run from the
-- addon folder:
--
--     lua tools/test_lootpanel.lua
--
-- Not shipped (the packaging step excludes tools/).
--
-- WHY THIS EXISTS, separately from test_gearrank.lua: that file stops at
-- the DATA. It proves ns.LootCardList derives the right cards in the
-- right order, and then nothing at all executes Layout, SetupLootPanel or
-- RefreshLootPanel -- the seam between "the list is right" and "the list
-- gets drawn" had no assertion on either side of it. This walks it.
--
-- WHAT IT DOES NOT PROVE: that anything LOOKS right. A stub frame will
-- happily accept a card placed off the bottom of the window. Geometry and
-- legibility are still a real-client job.
--
-- A/B verified 2026-08-24: a typo'd field name in the draw loop reports
-- six failing steps naming the field, and removing the stale-selection
-- fallback reports the two steps that depend on it.
--
-- The stub models a real frame: an UNSET FIELD IS NIL, only method-shaped
-- names (UpperCamelCase, the WoW convention) answer with a function. A
-- catch-all __index that answers every name makes `x.cards = x.cards or {}`
-- keep the function it just handed back, and then you spend an evening
-- reading a bug that only exists inside the harness.
local ns = {}
local NUMERIC = {
  GetWidth = 200, GetHeight = 400, GetFrameLevel = 3, GetStringWidth = 40,
  GetEffectiveScale = 1, GetScale = 1,
}
local stubFrame
function stubFrame()
  local f = {}
  return setmetatable(f, { __index = function(_, key)
    if type(key) ~= "string" or not key:match("^%u") then return nil end
    local n = NUMERIC[key]
    if n then return function() return n end end
    if key == "GetTexture" then return function() return "tex" end end
    if key == "IsShown" then return function() return f.__shown == true end end
    if key == "Show" then return function() f.__shown = true end end
    if key == "Hide" then return function() f.__shown = false end end
    if key == "GetPoint" then
      return function() return "CENTER", nil, "CENTER", 0, 0 end
    end
    -- SetText / GetText round-trip for real. The catch-all below would
    -- hand GetText back the FRAME, and `frame .. " "` throws -- which is
    -- a harness artefact, not a bug in the addon.
    if key == "SetText" then return function(_, v) f.__text = v end end
    if key == "GetText" then return function() return f.__text end end
    -- Handlers are STORED, so a test can fire them. Without this the
    -- catch-all swallows SetScript and every OnEnter / OnDragStop in the
    -- addon is unreachable from here -- which is how a handler that
    -- calls a nil global (a local declared further down the file) can
    -- sit in the tree with luac perfectly happy about it.
    -- SetShown is a real setter, not a no-op: the catch-all would hand
    -- back the frame and leave __shown alone, so a control that was
    -- never shown and one that was hidden on purpose would read the
    -- same -- which is the state the "hidden dropdowns" check is about.
    if key == "SetShown" then
      return function(_, v) f.__shown = (v == true) end
    end
    -- Recorded so "shown and mouse-enabled move together" is checkable.
    if key == "EnableMouse" then
      return function(_, v) f.__mouse = (v == true) end
    end
    if key == "SetScript" then
      return function(_, name, fn) f.__scripts = f.__scripts or {}
                                   f.__scripts[name] = fn end
    end
    if key == "GetScript" then
      return function(_, name) return f.__scripts and f.__scripts[name] end
    end
    if key == "GetCenter" then return function() return 100, 100 end end
    -- Region factories must hand back a NEW object. Returning self made
    -- panel.empty, panel.title and panel.divider all ALIAS the panel, so
    -- `panel.empty:Hide()` hid the window and the harness reported that
    -- Show() had not worked. The bug was entirely in here.
    if key:match("^Create") then return function() return stubFrame() end end
    return function() return f end
  end })
end
-- A DropdownButton really does carry menu methods a plain Frame does
-- not, so it gets its own shape here. SetupMenu STORES the generator and
-- GenerateMenu RUNS it -- if the catch-all swallowed those two, the
-- whole menu-building closure would sit in the file unexecuted while the
-- suite reported green, which is the one thing this file exists to stop.
local function stubDropdown()
  local f = stubFrame()
  f.SetupMenu = function(self, generator) self.__generator = generator end
  f.SetDefaultText = function(self, text) self.__defaultText = text end
  f.GenerateMenu = function(self)
    local radios = {}
    local root = {}
    -- Returns the entry, as the real menu API returns an element
    -- description; callers may chain off it.
    function root:CreateRadio(text, isSelected, setSelected)
      radios[#radios + 1] = {
        text = text, isSelected = isSelected, setSelected = setSelected,
      }
      return radios[#radios]
    end
    if self.__generator then self.__generator(self, root) end
    self.__radios = radios
  end
  return f
end

-- A NAMED frame becomes a global, exactly as the real CreateFrame does.
-- That is how the tests below reach the panel without the addon having
-- to export a hook that exists only for them.
_G.CreateFrame = function(frameType, name)
  local f = (frameType == "DropdownButton") and stubDropdown() or stubFrame()
  if type(name) == "string" then _G[name] = f end
  return f
end
_G.C_Timer = { After = function() end }
_G.SlashCmdList = {}
_G.UIParent = stubFrame(); _G.Minimap = stubFrame(); _G.GameTooltip = stubFrame()
_G.UISpecialFrames = {}

-- The client data the right column needs. WITHOUT these the draw path
-- still runs and still reports "ok" -- it just draws nothing, because
-- GearRank's ItemShape fails closed when GetItemInfoInstant is missing
-- and PlayerSpecID answers nil when the specialization API is. Verified
-- 2026-08-25 by removing this block: the three right-column steps go red
-- ("the right column drew no rows at all"), which is what makes them
-- worth having. A silent empty list is the failure this harness exists
-- to catch.
local shapes = assert(loadfile("tools/fixture_itemshape.lua"))()
_G.GetItemInfoInstant = function(itemID)
  local shape = shapes[itemID]
  if not shape then return nil end
  return itemID, nil, nil, shape[1], nil, shape[2], shape[3]
end
_G.C_Item = {
  -- Distinct names on purpose: one shared name would make DedupeByName
  -- collapse the whole list to a single row and the row assertions would
  -- be measuring the deduper instead of the draw.
  GetItemInfo = function(itemID) return "Item " .. tostring(itemID) end,
  -- Answers a DIFFERENT number for a link marked LOW, so "keep the
  -- better copy" is a question the harness can actually pose. A
  -- constant here would make that assertion pass no matter which copy
  -- the scan kept.
  GetDetailedItemLevelInfo = function(link)
    if type(link) == "string" and link:find("LOW", 1, true) then return 285 end
    return 311
  end,
}

-- Fury warrior: plate, Strength, and its stat priority resolves without
-- a hero tree (eight of the forty specs do not -- see SourceCandidates).
local TEST_SPEC = 72
_G.GetSpecialization = function() return 1 end
_G.GetSpecializationInfo = function() return TEST_SPEC end

-- The class / spec tree the filter dropdowns are built from.
--
-- The GROUPING is not invented here: it is lifted from the class
-- sections of Data/StatPriority.lua, which files every one of these
-- forty spec ids under a class heading. The CLASS IDS are ordinals
-- assigned right here and are deliberately not the game's -- nothing
-- under test reads their value, only that they are distinct and stable,
-- and claiming to know Blizzard's numbering would be an assertion this
-- harness cannot back up.
--
-- The coverage check below is what keeps this from rotting: add a spec
-- to ns.SpecGear without adding it here and the suite says so, rather
-- than quietly dropping it out of a dropdown nobody is looking at.
local CLASS_SPECS = {
  { "Death Knight", { 250, 251, 252 } },
  { "Demon Hunter", { 577, 581, 1480 } },
  { "Druid",        { 102, 103, 104, 105 } },
  { "Evoker",       { 1467, 1468, 1473 } },
  { "Hunter",       { 253, 254, 255 } },
  { "Mage",         { 62, 63, 64 } },
  { "Monk",         { 268, 269, 270 } },
  { "Paladin",      { 65, 66, 70 } },
  { "Priest",       { 256, 257, 258 } },
  { "Rogue",        { 259, 260, 261 } },
  { "Shaman",       { 262, 263, 264 } },
  { "Warlock",      { 265, 266, 267 } },
  { "Warrior",      { 71, 72, 73 } },
}
-- Two ids that are NOT in ns.SpecGear, filed under a real class and
-- under a class of their own. Without them "the dropdown only offers
-- servable specs" would be asserted against a client that never offered
-- anything else -- the filter would be untested and the check free.
local ALIEN_SPEC, ALIEN_CLASS_SPEC = 9001, 9002
table.insert(CLASS_SPECS[13][2], ALIEN_SPEC)
CLASS_SPECS[#CLASS_SPECS + 1] = { "Tinker", { ALIEN_CLASS_SPEC } }

local classOfSpec, classNames, specNames = {}, {}, {}
for classID, row in ipairs(CLASS_SPECS) do
  classNames[classID] = row[1]
  for _, specID in ipairs(row[2]) do
    classOfSpec[specID] = classID
    specNames[specID] = row[1] .. " " .. specID
  end
end

_G.C_SpecializationInfo = {
  GetClassIDFromSpecID = function(specID) return classOfSpec[specID] end,
}
_G.C_CreatureInfo = {
  GetClassInfo = function(classID)
    local name = classNames[classID]
    if not name then return nil end
    return { className = name, classFile = name:upper(), classID = classID }
  end,
}
_G.GetSpecializationInfoByID = function(specID)
  local name = specNames[specID]
  if not name then return nil end
  return specID, name, "desc", 12345, "DAMAGER"
end
_G.C_ClassColor = {
  GetClassColor = function() return { r = 0.5, g = 0.6, b = 0.7 } end,
}

-- A hero tree that is really there, so "passed for my own spec, withheld
-- for anybody else's" is a difference the harness can see. With this
-- unstubbed both sides answer nil and the check passes for free.
_G.C_ClassTalents = {
  GetActiveHeroTalentSpec = function() return 31 end,
  GetActiveConfigID = function() return 1 end,
}
_G.C_Traits = {
  GetSubTreeInfo = function() return { name = "Test Tree" } end,
}

-- Planted inventory. Both tables are filled by the steps below, so the
-- ownership column is asserted against items the test chose rather than
-- against whatever happens to be in the season data.
local equippedLinks, bagLinks = {}, {}
_G.GetInventoryItemLink = function(_, slotID) return equippedLinks[slotID] end
-- ns.LootOwnedIndex derives its container list from Enum.BagIndex, so
-- without this the harness silently took the pre-Enum fallback path and
-- never exercised the one the live client uses. Only the fields that
-- function reads are modelled; a name it asks for and does not find is
-- meant to be skipped, and leaving some out is how that gets tested.
_G.Enum = { BagIndex = {
  Backpack = 0, ReagentBag = 5, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4,
  Bank = -1, Reagentbank = -3,
  CharacterBankTab_1 = 6, CharacterBankTab_2 = 7,
  AccountBankTab_1 = 13, AccountBankTab_2 = 14,
} }

-- bag 0 is carried, container 6 is a character bank tab and 14 is a
-- WARBAND tab -- the one a hand-written 6..12 range used to miss while
-- accidentally scanning its neighbour. Everything else answers 0 slots,
-- which is also how the client reports a bank nobody has opened.
local BANK_TAB, WARBAND_TAB = 6, 14
local bankLinks, warbandLinks = {}, {}
local function containerFor(bag)
  if bag == 0 then return bagLinks end
  if bag == BANK_TAB then return bankLinks end
  if bag == WARBAND_TAB then return warbandLinks end
  return nil
end
_G.C_Container = {
  GetContainerNumSlots = function(bag) return containerFor(bag) and 4 or 0 end,
  GetContainerItemLink = function(bag, slot)
    local t = containerFor(bag)
    return t and t[slot] or nil
  end,
}
_G.issecretvalue = function() return false end
_G.hooksecurefunc = function() end
_G.STANDARD_TEXT_FONT = "font"
_G.tinsert = table.insert
_G.GetCursorPosition = function() return 150, 150 end
_G.DodoInspectDB = {}

local toc = assert(io.open("DodoInspect.toc"))
for line in toc:lines() do
  line = line:gsub("%s+$", ""):gsub("\\", "/")
  if line:match("%.lua$") then assert(loadfile(line))("DodoInspect", ns) end
end
toc:close()

-- Fire a menu entry the way a click does, so the radio's own callback
-- is what moves the selection. Calling ns.SelectLootClass directly would
-- leave the closure in the generator untested.
local function pickRadio(drop, needle)
  for _, radio in ipairs(drop.__radios or {}) do
    if radio.text:find(needle, 1, true) then radio.setSelected() return end
  end
  error("no menu entry matching " .. needle)
end

local steps = {
  { "setup", function() ns.SetupLootPanel() end },
  { "refresh mythic", function() ns.RefreshLootPanel() end },
  { "switch to raid", function() ns.SetLootPanelMode("raid") end },
  { "select 2nd raid card", function()
      ns.SelectLootCard(ns.LootCardList("raid")[2])
      assert(ns.LootPanelSelection().key == ns.LootCardList("raid")[2].key,
             "the selection did not stick")
    end },
  { "switch back to mythic", function()
      ns.SetLootPanelMode("mythic")
      assert(ns.LootPanelSelection().kind == "dungeon",
             "mode switch must not carry the raid selection across")
    end },
  { "stale saved pick", function()
      DodoInspectDB.lootPanelPick.mythic = "d999999"
      ns.RefreshLootPanel()
      assert(ns.LootPanelSelection().key == "d1030",
             "a stale key must fall back to the first card")
    end },
  { "right column draws rows", function()
      ns.SetLootPanelMode("mythic")
      ns.SelectLootCard(ns.LootCardList("mythic")[1])
      local rows = DodoInspectLootPanel.detailRows or {}
      local shown = 0
      for _, row in ipairs(rows) do
        if row.__shown then shown = shown + 1 end
      end
      assert(shown > 0, "the right column drew no rows at all")
      assert(type(rows[1].name.__text) == "string" and rows[1].name.__text ~= "",
             "row 1 has no name text")
      assert(rows[1].itemID, "row 1 carries no itemID for its tooltip")
    end },
  { "ceiling follows the card", function()
      local rows = DodoInspectLootPanel.detailRows
      ns.SetLootPanelMode("mythic")
      ns.SelectLootCard(ns.LootCardList("mythic")[1])
      local dungeon = rows[1].bonusID
      ns.SetLootPanelMode("raid")
      ns.SelectLootCard(ns.LootCardList("raid")[1])
      local raid = rows[1].bonusID
      -- Raid card [1] happens to carry no 344 rows, so asserting only on
      -- it left the GEAR_TOP_BONUS_ID half of DetailBonusID unexecuted.
      -- Find a card that really does reach 344 and check both halves on
      -- the SAME card, which is also the only place the difference is
      -- visible to a player.
      local sawTop, sawMyth = false, false
      for _, card in ipairs(ns.LootCardList("raid")) do
        ns.SelectLootCard(card)
        for _, row in ipairs(rows) do
          if row.__shown then
            if row.bonusID == ns.Config.GEAR_TOP_BONUS_ID then sawTop = true end
            if row.bonusID == ns.Config.GEAR_MYTH_BONUS_ID then sawMyth = true end
          end
        end
      end
      assert(sawTop, "no raid row anywhere quoted the 344 ceiling -- the "
             .. "GEAR_TOP_BONUS_ID branch is never executed")
      assert(sawMyth, "no raid row quoted the 334 ceiling either")
      -- The whole point of DetailBonusID. A dungeon row rendered on the
      -- Myth track overstates it by an upgrade tier and a half; a raid
      -- row rendered on the dungeon track understates it by 23 or more.
      assert(dungeon == ns.Config.GEAR_HERO_BONUS_ID,
             "a dungeon row must quote the Hero ceiling")
      assert(raid == ns.Config.GEAR_MYTH_BONUS_ID
             or raid == ns.Config.GEAR_TOP_BONUS_ID,
             "a raid row must quote the Myth track")
      assert(dungeon ~= raid, "both modes quoted the same ceiling")
    end },
  { "owned column", function()
      ns.SetLootPanelMode("mythic")
      ns.SelectLootCard(ns.LootCardList("mythic")[1])
      local rows = DodoInspectLootPanel.detailRows
      local worn, carried = rows[1].itemID, rows[2].itemID
      assert(worn and carried and worn ~= carried,
             "need two distinct rows to plant into")

      -- Plant one on the character and one in a bag, then read the
      -- column back. Both branches of the scan run, and the two wordings
      -- have to differ -- a column that says the same thing wherever the
      -- item is answers a question nobody asked.
      equippedLinks[1] = "item:" .. worn
      bagLinks[1]      = "item:" .. carried
      ns.RefreshLootPanel()
      assert((rows[1].owned.__text or "") ~= "",
             "the equipped item is not reported as owned")
      assert((rows[2].owned.__text or "") ~= "",
             "the bagged item is not reported as owned")
      assert(rows[1].owned.__text ~= rows[2].owned.__text,
             "equipped and bagged must not read the same")

      -- The negative half: everything NOT planted must stay blank.
      -- Without this the assertions above would also pass if the column
      -- simply labelled every row.
      local strays = 0
      for i = 3, #rows do
        if rows[i].__shown and (rows[i].owned.__text or "") ~= "" then
          strays = strays + 1
        end
      end
      assert(strays == 0,
             "rows the player does not own must leave the column empty")

      equippedLinks[1], bagLinks[1] = nil, nil
      ns.RefreshLootPanel()
      assert((rows[1].owned.__text or "") == "",
             "the column still claims ownership after the item is gone")
    end },
  { "bank and warband are both found", function()
      ns.SetLootPanelMode("mythic")
      ns.SelectLootCard(ns.LootCardList("mythic")[1])
      local rows = DodoInspectLootPanel.detailRows
      local a, b, c = rows[1].itemID, rows[2].itemID, rows[3].itemID
      bankLinks[1]    = "item:" .. a
      warbandLinks[1] = "item:" .. b
      bagLinks[1]     = "item:" .. c
      ns.RefreshLootPanel()
      local bankWord = rows[1].owned.__text
      assert((bankWord or "") ~= "", "a character bank tab was not scanned")
      -- The warband tab is the one a hand-written container range used to
      -- miss, and missing it looks exactly like not owning the item.
      assert((rows[2].owned.__text or "") ~= "",
             "a warband bank tab was not scanned -- whether the column "
             .. "finds your item must not depend on which tab it is in")
      assert(rows[2].owned.__text == bankWord,
             "both bank kinds must read the same -- one of them saying "
             .. "nothing is the bug this guards")
      assert(rows[3].owned.__text ~= bankWord, "a bag must not read as a bank")

      -- Precedence: the same item in a bag AND the bank reads as the bag.
      bankLinks[2] = "item:" .. c
      ns.RefreshLootPanel()
      assert(rows[3].owned.__text ~= bankWord,
             "a bag copy must outrank a bank copy")

      -- Best copy within one place, not the first slot scanned.
      bagLinks[1] = "item:" .. c .. ":LOW"
      bagLinks[2] = "item:" .. c .. ":HIGH"
      ns.RefreshLootPanel()
      assert((rows[3].owned.__text or ""):find("311", 1, true),
             "the higher item level of two copies must be the one shown")

      bagLinks[1], bagLinks[2] = nil, nil
      bankLinks[1], bankLinks[2], warbandLinks[1] = nil, nil, nil
      ns.RefreshLootPanel()
    end },
  { "slot column", function()
      ns.SetLootPanelMode("mythic")
      ns.SelectLootCard(ns.LootCardList("mythic")[1])
      local rows = DodoInspectLootPanel.detailRows
      local drawn, labelled, distinct = 0, 0, {}
      local n = 0
      for _, row in ipairs(rows) do
        if row.__shown then
          drawn = drawn + 1
          local text = row.slot.__text or ""
          if text ~= "" then
            labelled = labelled + 1
            if not distinct[text] then distinct[text] = true; n = n + 1 end
          end
        end
      end
      assert(drawn > 0, "no rows were drawn")
      assert(labelled == drawn, string.format(
             "%d of %d rows have no slot label", drawn - labelled, drawn))
      -- More than one distinct value, or a hard-coded constant would
      -- satisfy the check above just as well.
      assert(n > 1, "every row shows the SAME slot label (" .. n .. ")")
      -- Trinkets lead, so row 1 must carry the trinket abbreviation --
      -- which also proves the column is keyed off the item and not the
      -- row index.
      assert(rows[1].slot.__text == ns.L.slots.INVTYPE_TRINKET,
             "row 1 is not a trinket, or the slot column is wrong: got "
             .. tostring(rows[1].slot.__text))
    end },
  { "nothing truncates this season", function()
      -- MIN_DETAIL_ROWS is headroom, not a measurement, and the only
      -- thing that says whether it is still enough is this. If a season
      -- grows past it the window starts hiding rows behind an "N/M" that
      -- nobody asked for -- which is honest, but worth being told about
      -- while it is still a one-constant fix.
      local seen = 0
      for _, mode in ipairs({ "mythic", "raid" }) do
        ns.SetLootPanelMode(mode)
        for _, card in ipairs(ns.LootCardList(mode)) do
          ns.SelectLootCard(card)
          seen = seen + 1
          -- Counted, not read off the "N/M" label. Reading the label
          -- would make this guard depend on the label existing: drop
          -- that one string and the check goes green while the window
          -- silently hides rows. Verified by doing exactly that.
          local drawn = 0
          for _, row in ipairs(DodoInspectLootPanel.detailRows or {}) do
            if row.__shown then drawn = drawn + 1 end
          end
          local want = ns.DedupeByName(ns.SourceCandidates(
              card, TEST_SPEC, nil,
              card.kind == "dungeon" and "mythic" or "raid"))
          assert(drawn == #want, string.format(
                 "card %s has %d drops but only %d rows fit -- raise "
                 .. "MIN_DETAIL_ROWS in LootPanel.lua", card.key, #want, drawn))
        end
      end
      assert(seen >= 17, "every card was actually visited (got " .. seen .. ")")
      ns.SetLootPanelMode("mythic")
    end },
  { "row handlers actually run", function()
      ns.SetLootPanelMode("mythic")
      ns.SelectLootCard(ns.LootCardList("mythic")[1])
      local row = DodoInspectLootPanel.detailRows[1]
      -- Fired for real, not just inspected. Every one of these reaches
      -- code that luac cannot check: an upvalue captured before it was
      -- declared reads as a nil global and only throws when the handler
      -- runs.
      for _, name in ipairs({ "OnEnter", "OnLeave", "OnDragStart", "OnDragStop" }) do
        local fn = row:GetScript(name)
        assert(fn, "row has no " .. name .. " handler")
        fn(row)
      end
      -- And the same on a row whose tooltip has no bonus id to quote,
      -- which takes the other branch of OnEnter.
      local saved = row.bonusID
      row.bonusID = nil
      row:GetScript("OnEnter")(row)
      row.bonusID = saved
    end },
  { "spec index is servable-only", function()
      local index, complete = ns.LootSpecIndex()
      assert(complete, "the index reported itself incomplete with every "
             .. "client lookup stubbed -- nothing would ever stop retrying")
      -- Reverse assertion first: every loop below walks these, and an
      -- empty index would let the whole step pass proving nothing.
      assert(#index.classes == 13, "expected 13 classes with servable "
             .. "specs, got " .. #index.classes)

      local n = 0
      for specID in pairs(ns.SpecGear) do
        n = n + 1
        assert(index.byID[specID], "ns.SpecGear carries spec " .. specID
               .. " but the filter does not offer it -- either the index "
               .. "dropped it or CLASS_SPECS in this file is stale")
      end
      assert(n == 40, "expected 40 servable specs, got " .. n)

      -- The filter half. ALIEN_SPEC sits inside a real class, so it
      -- tests per-spec filtering; ALIEN_CLASS_SPEC is a whole class of
      -- its own, so it tests that a class with nothing servable does not
      -- get an empty row. Offering either would mean a dropdown entry
      -- whose only feedback is an empty right column.
      assert(not index.byID[ALIEN_SPEC],
             "a spec absent from ns.SpecGear was offered anyway")
      assert(not index.byID[ALIEN_CLASS_SPEC], "same, for the lone spec "
             .. "of a class with nothing servable")
      for _, entry in ipairs(index.classes) do
        assert(entry.name ~= "Tinker",
               "a class with no servable spec still got a dropdown row")
        assert(#entry.specs > 0, "class " .. entry.name .. " has an empty "
               .. "spec list")
      end

      -- Total order. pairs() is unordered, and a filter that reshuffles
      -- between two openings is a bug nobody can reproduce on demand.
      --
      -- Checked as a PROPERTY of the one list, not by calling twice and
      -- comparing: the index caches itself once complete, so a second
      -- call hands back the very same table and would compare it to
      -- itself. Sorted-by-name plus the id tie-break fully determines
      -- the order for a given set, so monotonicity says the same thing
      -- and actually looks at something.
      for i = 2, #index.classes do
        local prev, this = index.classes[i - 1], index.classes[i]
        assert(prev.name < this.name
               or (prev.name == this.name and prev.classID < this.classID),
               "class order is not sorted by the name the player reads: "
               .. prev.name .. " came before " .. this.name)
      end
      assert(index.classes[1].name == "Death Knight",
             "classes are not sorted by the name the player reads (got "
             .. tostring(index.classes[1].name) .. ")")
    end },
  { "dropdowns offer the current class", function()
      DodoInspectDB.lootPanelSpec = nil
      ns.SetLootPanelMode("mythic")
      ns.SelectLootCard(ns.LootCardList("mythic")[1])
      local panel = DodoInspectLootPanel
      local classDrop, specDrop = panel.classDrop, panel.specDrop
      assert(classDrop and specDrop, "the dropdowns were never built")
      -- Shown and mouse-enabled move together; half of that pair going
      -- missing leaves an invisible control still taking clicks.
      assert(classDrop.__shown and classDrop.__mouse,
             "the class dropdown is not both shown and mouse-enabled")
      assert(specDrop.__shown and specDrop.__mouse,
             "the spec dropdown is not both shown and mouse-enabled")

      assert(#(classDrop.__radios or {}) == 13,
             "the class menu built " .. #(classDrop.__radios or {})
             .. " entries, expected 13 -- the generator never ran if 0")
      -- Exactly one checked, in each menu. Zero means the radio cannot
      -- show you where you are; two means it is checking on the wrong
      -- thing entirely.
      local function checked(drop)
        local hits = 0
        for _, radio in ipairs(drop.__radios or {}) do
          if radio.isSelected() then hits = hits + 1 end
        end
        return hits
      end
      assert(checked(classDrop) == 1,
             "class menu has " .. checked(classDrop) .. " checked entries")
      -- The player is a Fury warrior, so the spec menu must be the
      -- warrior's three -- NOT all forty, and not another class's.
      assert(#(specDrop.__radios or {}) == 3,
             "the spec menu listed " .. #(specDrop.__radios or {})
             .. " specs, expected the current class's 3")
      assert(checked(specDrop) == 1,
             "spec menu has " .. checked(specDrop) .. " checked entries")
    end },
  { "picking another class redraws the column", function()
      DodoInspectDB.lootPanelSpec = nil
      ns.SetLootPanelMode("mythic")
      ns.SelectLootCard(ns.LootCardList("mythic")[1])
      local panel = DodoInspectLootPanel
      local rows = panel.detailRows

      local before = {}
      for _, row in ipairs(rows) do
        if row.__shown then before[#before + 1] = row.itemID end
      end
      assert(#before > 0, "nothing was drawn to compare against")
      -- The player is plate/Strength; arcane mage is cloth/Intellect, so
      -- an unchanged list would mean the spec never reached the query.
      pickRadio(panel.classDrop, "Mage")

      local specID, isOwn = ns.LootPanelSpec()
      assert(specID == 62, "picking Mage did not land on its first spec "
             .. "(got " .. tostring(specID) .. ")")
      assert(not isOwn, "somebody else's spec is reported as your own")
      assert(DodoInspectDB.lootPanelSpec == 62,
             "the override was not persisted")

      local after, same = {}, 0
      for _, row in ipairs(rows) do
        if row.__shown then after[#after + 1] = row.itemID end
      end
      assert(#after > 0, "the right column went empty for another spec -- "
             .. "SourceCandidates must LIST for a spec it cannot rank")
      for _, id in ipairs(after) do
        for _, old in ipairs(before) do
          if id == old then same = same + 1 end
        end
      end
      assert(same < #after, "a cloth caster was shown the plate list -- "
             .. "the filter never reached the query")
    end },
  { "unranked says so, ranked does not", function()
      local panel = DodoInspectLootPanel
      -- 62 is one of the eight specs whose priority splits by hero tree,
      -- and it is not the player's, so no tree can be read for it.
      ns.SetLootPanelSpec(62)
      local unranked = ns.L.lootUnranked
      assert(unranked and unranked ~= "", "the locale has no lootUnranked")
      assert((panel.detailTitle.__text or ""):find(unranked, 1, true),
             "a list that could not be ranked did not say so")
      assert(not (panel.detailRows[1].name.__text or ""):match("^1%. "),
             "rows are numbered while nothing ranked them -- numbering "
             .. "asserts an order that is not there")

      -- The other half. Without this the marker could be permanently on
      -- and every check above would still pass.
      ns.SetLootPanelSpec(63)
      assert(not (panel.detailTitle.__text or ""):find(unranked, 1, true),
             "a spec that ranks fine was still labelled unranked")
      assert((panel.detailRows[1].name.__text or ""):match("^1%. "),
             "a ranked list lost its numbering")
    end },
  { "hero tree only for your own spec", function()
      local seen = {}
      local real = ns.SourceCandidates
      ns.SourceCandidates = function(card, specID, subTree, content)
        seen[#seen + 1] = { spec = specID, tree = subTree }
        return real(card, specID, subTree, content)
      end

      DodoInspectDB.lootPanelSpec = nil
      ns.RefreshLootPanel()
      ns.SetLootPanelSpec(62)
      ns.SourceCandidates = real

      assert(#seen >= 2, "the query ran " .. #seen .. " times, need both")
      local own, other = seen[1], seen[#seen]
      assert(own.spec == TEST_SPEC and other.spec == 62,
             "the two probes did not land on the specs expected")
      -- Reverse assertion: with C_ClassTalents unstubbed BOTH sides
      -- answer nil and the real check below passes for free.
      assert(own.tree == 31, "no hero tree reached your own spec (got "
             .. tostring(own.tree) .. ") -- the check below proves nothing")
      assert(other.tree == nil, "your hero tree was handed to somebody "
             .. "else's spec, which would rank their drops against your "
             .. "talents and never look wrong")
    end },
  { "your own class snaps back to you", function()
      ns.SetLootPanelSpec(62)
      assert(DodoInspectDB.lootPanelSpec == 62, "setup did not take")
      local panel = DodoInspectLootPanel
      pickRadio(panel.classDrop, "Warrior")
      local specID, isOwn = ns.LootPanelSpec()
      assert(specID == TEST_SPEC, "picking your own class landed on "
             .. tostring(specID) .. " instead of the spec you are in")
      assert(isOwn, "your own spec is not reported as your own")
      -- The whole point of storing the departure rather than the state:
      -- with nothing stored, a respec is followed instead of frozen.
      assert(DodoInspectDB.lootPanelSpec == nil,
             "picking your own spec stored an override, so a later "
             .. "respec would leave the window on the old spec")
    end },
  { "a stale stored spec falls back to you", function()
      DodoInspectDB.lootPanelSpec = 999999
      local specID, isOwn = ns.LootPanelSpec()
      assert(specID == TEST_SPEC and isOwn,
             "an id no longer in ns.SpecGear was used anyway, which "
             .. "shows an empty column forever (got "
             .. tostring(specID) .. ")")
      DodoInspectDB.lootPanelSpec = nil
      ns.RefreshLootPanel()
    end },
  { "the window works without dropdowns", function()
      -- The degraded path taken when the Blizzard template cannot be
      -- created. It has to behave exactly like the panel did before this
      -- step: follow the player's own spec and keep drawing.
      local panel = DodoInspectLootPanel
      local savedClass, savedSpec = panel.classDrop, panel.specDrop
      panel.classDrop, panel.specDrop = nil, nil
      ns.SetLootPanelMode("mythic")
      ns.SelectLootCard(ns.LootCardList("mythic")[1])
      local drawn = 0
      for _, row in ipairs(panel.detailRows) do
        if row.__shown then drawn = drawn + 1 end
      end
      assert(drawn > 0, "losing the dropdowns took the drop list with it")
      panel.classDrop, panel.specDrop = savedClass, savedSpec
      ns.RefreshLootPanel()
    end },
  { "show / hide / toggle", function()
      ns.ShowLootPanel(); assert(ns.LootPanelShown(), "show did not show")
      ns.ToggleLootPanel(); assert(not ns.LootPanelShown(), "toggle did not hide")
    end },
  { "minimap button", function()
      ns.ApplyLootMinimapEnabled()
      assert(ns.SetupMinimapButton() ~= nil, "no button was built")
    end },
  { "minimap off", function()
      DodoInspectDB.showLootMinimap = false
      assert(ns.LootMinimapEnabled() == false, "the toggle did not take")
      ns.ApplyLootMinimapEnabled()
      DodoInspectDB.showLootMinimap = nil
    end },
  { "slash /dins loot", function() SlashCmdList["DODOINSPECT"]("loot") end },
}
local bad = 0
for _, s in ipairs(steps) do
  local ok, err = pcall(s[2])
  print(string.format("%-26s %s", s[1], ok and "ok" or ("ERROR " .. tostring(err))))
  if not ok then bad = bad + 1 end
end
print(string.format("%d steps, %d failed", #steps, bad))
os.exit(bad == 0 and 0 or 1)
