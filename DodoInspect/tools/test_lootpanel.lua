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
    if key == "GetCenter" then return function() return 100, 100 end end
    -- Region factories must hand back a NEW object. Returning self made
    -- panel.empty, panel.title and panel.divider all ALIAS the panel, so
    -- `panel.empty:Hide()` hid the window and the harness reported that
    -- Show() had not worked. The bug was entirely in here.
    if key:match("^Create") then return function() return stubFrame() end end
    return function() return f end
  end })
end
_G.CreateFrame = function() return stubFrame() end
_G.C_Timer = { After = function() end }
_G.SlashCmdList = {}
_G.UIParent = stubFrame(); _G.Minimap = stubFrame(); _G.GameTooltip = stubFrame()
_G.UISpecialFrames = {}; _G.C_Item = {}
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
