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
-- A NAMED frame becomes a global, exactly as the real CreateFrame does.
-- That is how the tests below reach the panel without the addon having
-- to export a hook that exists only for them.
_G.CreateFrame = function(_, name)
  local f = stubFrame()
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
  GetDetailedItemLevelInfo = function() return 311 end,
}

-- Fury warrior: plate, Strength, and its stat priority resolves without
-- a hero tree (eight of the forty specs do not -- see SourceCandidates).
local TEST_SPEC = 72
_G.GetSpecialization = function() return 1 end
_G.GetSpecializationInfo = function() return TEST_SPEC end

-- Planted inventory. Both tables are filled by the steps below, so the
-- ownership column is asserted against items the test chose rather than
-- against whatever happens to be in the season data.
local equippedLinks, bagLinks = {}, {}
_G.GetInventoryItemLink = function(_, slotID) return equippedLinks[slotID] end
_G.C_Container = {
  GetContainerNumSlots = function(bag) return bag == 0 and 4 or 0 end,
  GetContainerItemLink = function(bag, slot)
    if bag ~= 0 then return nil end
    return bagLinks[slot]
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
