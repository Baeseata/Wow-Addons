-- Loads the REAL Execute.lua with the WoW API stubbed, per canon: stub the external dependency and
-- run the real original, rather than hand-rolling a fixture that can only confirm my own beliefs.
local SPEC = 258
function GetSpecialization() return 1 end
function GetSpecializationInfo() return SPEC end

local pass, fail = 0, 0
local function check(name, got, want)
  if got == want then pass = pass + 1
  else fail = fail + 1; print(("  FAIL %s: got %s want %s"):format(name, tostring(got), tostring(want))) end
end

local function load_module(enabled)
  local ns = {
    Guards = { IsSecret = function() return false end },
    db = { execute = { enabled = enabled } },
  }
  assert(loadfile("Execute.lua"))("DodoNameplate", ns)
  return ns.Execute, ns
end

local E = load_module(true)

-- 1. the one confirmed spec draws
SPEC = 258; check("shadow priest active", E.IsActive(), true)
check("shadow priest pct", (E.Rule()).pct, 0.20)

-- 2. every non-confirmed state must NOT draw
SPEC = 71;  check("warrior (dynamic) silent", E.IsActive(), false)
SPEC = 253; check("hunter (unverified) silent", E.IsActive(), false)
SPEC = 250; check("dk (unverified) silent", E.IsActive(), false)

-- 3. a spec with no execute at all
SPEC = 259; check("rogue has no rule", E.Rule(), nil)
check("rogue silent", E.IsActive(), false)

-- 4. kill switch beats even a confirmed spec
local Eoff = load_module(false)
SPEC = 258; check("kill switch wins", Eoff.IsActive(), false)

-- 5. a secret spec id must never reach the table as an index
local nsSecret = { Guards = { IsSecret = function() return true end }, db = { execute = { enabled = true } } }
assert(loadfile("Execute.lua"))("DodoNameplate", nsSecret)
SPEC = 258; check("secret spec -> no rule", nsSecret.Execute.Rule(), nil)

-- 6. GEOMETRY: the line must anchor to the BAR and sit at width*pct.
-- This is the test that catches the mistake the header warns about (anchoring to the fill).
local HB, FILL = {}, {}
local seen = {}
local f = {
  hb = HB, barWidth = 100,
  execLine = {
    ClearAllPoints = function() end,
    SetWidth = function(_, w) seen.w = w end,
    Show = function() seen.shown = true end,
    Hide = function() seen.shown = false end,
    SetPoint = function(_, _, rel, _, x) seen.rel = rel; seen.x = x end,
  },
}
SPEC = 258
E.Apply(f)
check("line shown for shadow", seen.shown, true)
check("anchored to the BAR not the fill", seen.rel, HB)
check("x = width * 0.20", seen.x, 20)
check("line is 2px", seen.w, 2)

-- 7. a spec that draws nothing must actively hide a line left over from the previous spec
SPEC = 71
E.Apply(f)
check("respec to dynamic hides the line", seen.shown, false)

-- 8. zero width (first frame, before layout) must not park the line at the left edge
SPEC = 258; f.barWidth = 0; seen.shown = nil
E.Apply(f)
check("zero width -> hidden, not x=0", seen.shown, false)

print(("\n%d passed, %d failed"):format(pass, fail))
print("--- Status() strings ---")
f.barWidth = 100
for _, s in ipairs({ 258, 71, 253, 259 }) do
  SPEC = s
  print(("  %-4d %s"):format(s, E.Status()))
end
