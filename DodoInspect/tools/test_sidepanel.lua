-- DodoInspect - tools/test_sidepanel.lua
-- Offline test for the character side panel's REFRESH: one row that
-- throws must cost that row, not the whole layout. Run from the addon
-- folder:
--
--     lua tools/test_sidepanel.lua
--
-- Not shipped (the packaging step excludes tools/).
--
-- WHY THIS EXISTS (2026-10-17): a player on 12.1.5 running a pre-1.14.0
-- build had the off-hand row die on a removed item global. The off-hand
-- row is the LAST row, and the two steps after the row loop never ran:
-- the slot button faces were never sized to their labels (each drew at
-- the art file's 128px, spilling over the character frame) and the rows
-- were never laid out under the stat priority line (which then sat on
-- top of the head and neck rows). The fault below is planted at that
-- exact spot -- the off-hand enchant check -- and on the FIRST refresh,
-- because that player's refreshes all died the same way.
--
-- WHAT IT DOES NOT PROVE: that anything LOOKS right. A stub will accept a
-- face of any width. What it proves is that the face got a width at all,
-- and that the layout step ran after a row threw.
--
-- The stub follows tools/test_lootpanel.lua (unset field = nil, only
-- method-shaped names answer, Create* returns a NEW object), with three
-- departures that model the client more closely and that this test
-- depends on:
--   * a region is SHOWN until hidden, as a real one is on creation --
--     UpdateSlotButtonStates skips hidden buttons, so a default of
--     "hidden" would make it skip every one and the face checks would
--     pass without a single face being sized;
--   * GetStringWidth answers 0 until there is text, which is the client
--     behaviour FitFace is written around;
--   * width and height round-trip, and an unsized region answers nil --
--     the "never given a width" state is the one being tested for.
local ns = {}

local function stubFrame()
  local f = { __regions = {} }
  return setmetatable(f, { __index = function(_, key)
    if type(key) ~= "string" or not key:match("^%u") then return nil end
    if key == "IsShown" then return function() return f.__shown ~= false end end
    if key == "Show" then return function() f.__shown = true end end
    if key == "Hide" then return function() f.__shown = false end end
    if key == "SetShown" then return function(_, v) f.__shown = (v and true or false) end end
    if key == "SetText" then return function(_, v) f.__text = v end end
    if key == "GetText" then return function() return f.__text end end
    if key == "GetStringWidth" then
      return function()
        local t = f.__text
        return (type(t) == "string" and #t > 0) and #t * 7 or 0
      end
    end
    if key == "SetWidth" then return function(_, w) f.__w = w end end
    if key == "GetWidth" then return function() return f.__w end end
    if key == "SetHeight" then return function(_, h) f.__h = h end end
    if key == "GetHeight" then return function() return f.__h end end
    if key == "SetSize" then return function(_, w, h) f.__w, f.__h = w, h end end
    if key == "SetTexture" then return function(_, t) f.__texture = t end end
    if key == "GetTexture" then return function() return f.__texture end end
    if key == "SetTexCoord" then return function(_, ...) f.__texcoord = { ... } end end
    if key == "ClearAllPoints" then return function() f.__points = {} end end
    if key == "SetPoint" then
      return function(_, ...)
        f.__points = f.__points or {}
        f.__points[#f.__points + 1] = { ... }
      end
    end
    if key == "SetScript" then
      return function(_, name, fn) f.__scripts = f.__scripts or {}
                                   f.__scripts[name] = fn end
    end
    if key == "GetScript" then
      return function(_, name) return f.__scripts and f.__scripts[name] end
    end
    if key == "GetPoint" then
      return function() return "CENTER", nil, "CENTER", 0, 0 end
    end
    if key == "GetFrameLevel" then return function() return 3 end end
    if key == "GetEffectiveScale" or key == "GetScale" then
      return function() return 1 end
    end
    if key == "GetCenter" then return function() return 100, 100 end end
    if key:match("^Create") then
      return function()
        local child = stubFrame()
        f.__regions[#f.__regions + 1] = child
        return child
      end
    end
    return function() return f end
  end })
end

-- A NAMED frame becomes a global, as the real CreateFrame does, and every
-- frame is recorded on its parent -- that is how the steps below reach
-- the panel and its rows without the addon exporting a test-only hook.
_G.CreateFrame = function(_, name, parent)
  local f = stubFrame()
  if type(name) == "string" then _G[name] = f end
  -- The real side panel gets its height from two anchors (top and bottom
  -- of the character frame) the moment it is created, so the setup-time
  -- layout already has a height to work with. Nothing in a stub can
  -- derive that, so it is declared here, for that one frame only.
  if name == "DodoInspectSidePanel" then f.__h = 520 end
  if type(parent) == "table" and parent.__regions then
    parent.__regions[#parent.__regions + 1] = f
  end
  return f
end

-- Errors go where the client sends them: to whatever geterrorhandler()
-- returns. Recording them is what lets "the error was reported, not
-- swallowed" be asserted -- isolation that hid the error would be a
-- different bug, and a worse one.
local reported = {}
_G.geterrorhandler = function()
  return function(err) reported[#reported + 1] = tostring(err) end
end

_G.C_Timer = { After = function() end }
_G.SlashCmdList = {}
_G.UIParent = stubFrame(); _G.Minimap = stubFrame(); _G.GameTooltip = stubFrame()
_G.UISpecialFrames = {}
_G.CharacterFrame = stubFrame()
_G.PaperDollFrame = stubFrame()
_G.issecretvalue = function() return false end
_G.hooksecurefunc = function() end
_G.STANDARD_TEXT_FONT = "font"
_G.tinsert = table.insert
-- WoW global; ParseItemLink splits the link on ":" with it.
_G.strsplit = function(sep, str)
  local out = {}
  for piece in (str .. sep):gmatch("(.-)" .. (sep:gsub("%p", "%%%0"))) do
    out[#out + 1] = piece
  end
  return table.unpack(out)
end
_G.GetCursorPosition = function() return 150, 150 end
_G.DodoInspectDB = {}

-- Fury warrior: its stat priority resolves without a hero tree, so the
-- header line is on screen and has a height the rows must clear.
_G.C_SpecializationInfo = { GetSpecialization = function() return 1 end }
_G.GetSpecializationInfo = function() return 72 end

-- Gear in every slot, the off-hand included -- the off-hand row is the
-- one that died in the report. Item ids are 900000 + slot so a link says
-- which row it belongs to.
local OFFHAND_ID = 900017
local equipped = {}
for _, slot in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }) do
  equipped[slot] = "item:" .. (900000 + slot) .. ":7000::::::::::::"
end
_G.GetInventoryItemLink = function(_, slot) return equipped[slot] end
_G.ItemLocation = {
  CreateFromEquipmentSlot = function(_, slot)
    return { IsValid = function() return true end, slot = slot }
  end,
}
_G.C_Item = {
  GetItemInfoInstant = function(link)
    local id = tonumber(tostring(link):match("item:(%d+)"))
    local loc = (id == OFFHAND_ID) and "INVTYPE_WEAPONOFFHAND" or "INVTYPE_HEAD"
    return id, nil, nil, loc
  end,
  GetItemInventoryType = function() return 1 end,
  GetCurrentItemLevel = function() return 321 end,
  GetItemStats = function()
    return { ITEM_MOD_CRIT_RATING_SHORT = 120, ITEM_MOD_HASTE_RATING_SHORT = 60 }
  end,
  GetItemInfo = function(link) return "Item " .. tostring(link):match("item:(%d+)"), nil, 4 end,
}

local toc = assert(io.open("DodoInspect.toc"))
for line in toc:lines() do
  line = line:gsub("%s+$", ""):gsub("\\", "/")
  if line:match("%.lua$") then assert(loadfile(line))("DodoInspect", ns) end
end
toc:close()

local panel
local function slotRows()
  local out = {}
  for _, r in ipairs(panel.__regions) do
    if r.slotID then out[#out + 1] = r end
  end
  return out
end
local function rowFor(slotID)
  for _, r in ipairs(slotRows()) do
    if r.slotID == slotID then return r end
  end
end
-- The stretched middle of a slot button's face: the one texture sampled
-- from the art's middle band (ART_MID in GearPanel.lua). Its width is the
-- face's width; the caps are fixed.
local function faceMid(row)
  for _, r in ipairs(row.__regions) do
    if r.__texcoord and r.__texcoord[1] == 0.09375 then return r end
  end
end
-- What FitFace draws for a MEASURED label, restated: text plus a little
-- padding, never wider than the cell leaves room for between the caps.
local function expectedFace(row)
  local textW = row.slot:GetStringWidth()
  local widest = (row.slot:GetWidth() or 0) - 24
  local want = textW + 2
  if widest > 8 and want > widest then want = widest end
  return math.max(8, want)
end

-- The fault, at the spot the report died: the off-hand enchant check is
-- the only caller of ns.ItemInfoInstant on this panel, and only for the
-- off-hand row. It counts its own firings so a run where it never fires
-- (and every check below is green for free) cannot pass.
local realInstant = ns.ItemInfoInstant
local fired = 0
local function plantFault()
  ns.ItemInfoInstant = function(item)
    if tostring(item):find(tostring(OFFHAND_ID), 1, true) then
      fired = fired + 1
      error("planted: removed item global")
    end
    return realInstant(item)
  end
end

local steps = {
  { "setup", function()
      plantFault()
      ns.SetupSidePanel()
      panel = DodoInspectSidePanel
      assert(panel, "no side panel was built")
      assert(#slotRows() == 16, "expected 16 slot rows, got " .. #slotRows())
    end },
  { "a throwing row stays inside it", function()
      local ok, err = pcall(ns.UpdateSidePanel)
      assert(ok, "the refresh threw past the row loop: " .. tostring(err))
      assert(fired == 1, "the planted fault fired " .. fired
             .. " times; expected once, on the off-hand row")
    end },
  { "the error was reported", function()
      assert(#reported == 1 and reported[1]:find("planted", 1, true),
             "the row's error was swallowed instead of reaching the "
             .. "error handler (" .. #reported .. " reported)")
    end },
  { "rows sit under the header", function()
      local headerH = panel.dodoPriorityHeight or 0
      assert(headerH > 0, "the priority header is not on screen, so "
             .. "this check would prove nothing")
      local head = rowFor(1)
      local y = head.__points and head.__points[1] and head.__points[1][5]
      assert(y == -headerH, "the head row is at y=" .. tostring(y)
             .. ", not under the header (" .. -headerH .. "): the layout "
             .. "step never ran after the row threw")
    end },
  { "every face fits its label", function()
      for _, row in ipairs(slotRows()) do
        local mid = faceMid(row)
        assert(mid, "slot " .. row.slotID .. " has no button face")
        assert(mid.__w == expectedFace(row), "slot " .. row.slotID
               .. " face is " .. tostring(mid.__w) .. " wide, expected "
               .. expectedFace(row) .. ": it was never fitted to its label")
      end
    end },
  { "only the bad row lost anything", function()
      for _, row in ipairs(slotRows()) do
        assert((row.name.__text or "") ~= "", "slot " .. row.slotID
               .. " lost its item name")
      end
      assert(rowFor(17).ench.__shown == false,
             "the off-hand row drew an enchant tag past its own error")
    end },
  { "a clean refresh adds nothing", function()
      ns.ItemInfoInstant = realInstant
      local before = #reported
      local ok, err = pcall(ns.UpdateSidePanel)
      assert(ok, tostring(err))
      assert(#reported == before, "a clean refresh reported "
             .. (#reported - before) .. " new errors")
      assert(rowFor(17).ench.__shown ~= false,
             "the off-hand enchant tag did not come back once fixed")
    end },
  { "one bad face costs one face", function()
      -- Cleared first: a face the aborted loop never reached would
      -- otherwise still carry its width from the refresh before, and pass.
      for _, row in ipairs(slotRows()) do faceMid(row).__w = nil end
      local head = rowFor(1)
      head.slot.GetStringWidth = function() error("planted: bad face") end
      local before = #reported
      local ok, err = pcall(ns.UpdateSidePanel)
      head.slot.GetStringWidth = nil
      assert(ok, "the refresh threw past the face loop: " .. tostring(err))
      assert(#reported == before + 1, "expected the one planted face "
             .. "error to be reported, got " .. (#reported - before))
      for _, row in ipairs(slotRows()) do
        if row.slotID ~= 1 then
          assert(faceMid(row).__w == expectedFace(row), "slot "
                 .. row.slotID .. " was left unsized behind the head "
                 .. "row's error")
        end
      end
    end },
  { "a new face starts sized", function()
      local row = stubFrame()
      row.slot, row.slotKey, row.slotID = stubFrame(), "INVTYPE_HEAD", 1
      ns.AttachSlotButton(row, panel, "player")
      local mid = faceMid(row)
      assert(mid and mid.__w == 8, "an unmeasured face has width "
             .. tostring(mid and mid.__w) .. "; the client would draw it "
             .. "at the art file's own 128px")
    end },
  { "an unmeasured face fills its cell", function()
      -- Its own row, so a failure in the step above cannot cascade here.
      local row = stubFrame()
      row.slot, row.slotKey, row.slotID = stubFrame(), "INVTYPE_HEAD", 1
      ns.AttachSlotButton(row, panel, "player")
      row.slot:SetWidth(46)
      ns.UpdateSlotButtonStates()
      local mid = faceMid(row)
      assert(mid.__w == 46 - 24, "a face with a cell but no measured "
             .. "label is " .. tostring(mid.__w) .. " wide, expected "
             .. (46 - 24) .. " (the cell between its caps)")
    end },
}
local bad = 0
for _, s in ipairs(steps) do
  local ok, err = pcall(s[2])
  print(string.format("%-34s %s", s[1], ok and "ok" or ("ERROR " .. tostring(err))))
  if not ok then bad = bad + 1 end
end
print(string.format("%d steps, %d failed", #steps, bad))
os.exit(bad == 0 and 0 or 1)
