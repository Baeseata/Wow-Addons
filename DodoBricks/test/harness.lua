-- DodoBricks headless smoke test: mock WoW API + drive the real game loop for 110 levels.
-- Run: luajit harness.lua <addon_dir>
local DIR = arg and arg[1] or "."

math.randomseed(42)  -- deterministic run

-- ------------------------------------------------------------------
-- Mock WoW API
-- ------------------------------------------------------------------
local mockTime = 0
function GetTime() mockTime = mockTime + 0.0005 return mockTime end

MOCK_MOUSE = { x = 224, y = 400 }
MOCK_LMB = false
function GetCursorPosition() return MOCK_MOUSE.x, MOCK_MOUSE.y end
function IsMouseButtonDown(btn)
    if btn == "LeftButton" then return MOCK_LMB end
    return false
end
function IsShiftKeyDown() return false end
function PlaySound() end
function GameTooltip_Hide() end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UISpecialFrames = {}
SlashCmdList = {}
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert

local allFrames = {}

local function NewRegion()
    local o = { __scripts = {} }
    setmetatable(o, { __index = function(t, k)
        if k == "TitleText" then return nil end   -- template-injected field, absent in the mock
        local fn
        if k == "CreateTexture" or k == "CreateMaskTexture" or k == "CreateLine" or k == "CreateFontString" then
            fn = function() return NewRegion() end
        elseif k == "GetFrameLevel" then fn = function() return 0 end
        elseif k == "GetEffectiveScale" then fn = function() return 1 end
        elseif k == "GetLeft" or k == "GetBottom" then fn = function() return 0 end
        elseif k == "GetWidth" then fn = function() return 100 end
        elseif k == "GetCenter" then fn = function() return 50, 50 end
        elseif k == "IsShown" then fn = function(self) return self.__shown end
        elseif k == "Show" then fn = function(self) self.__shown = true end
        elseif k == "Hide" then fn = function(self) self.__shown = false end
        elseif k == "GetChecked" then fn = function() return false end
        elseif k == "SetScript" then fn = function(self, ev, h) self.__scripts[ev] = h end
        elseif k == "GetScript" then fn = function(self, ev) return self.__scripts[ev] end
        elseif k == "GetPoint" then fn = function() return "CENTER", nil, "CENTER", 0, 0 end
        else fn = function() end end
        rawset(t, k, fn)
        return fn
    end })
    return o
end

function CreateFrame(ftype, name, parent, template)
    local f = NewRegion()
    f.__type = ftype
    allFrames[#allFrames + 1] = f
    return f
end

GameTooltip = NewRegion()
Minimap = NewRegion()
UIParent = NewRegion()
DodoBricksDB = nil

-- ------------------------------------------------------------------
-- Load the addon files in toc order
-- ------------------------------------------------------------------
for _, f in ipairs({ "Geometry.lua", "Sound.lua", "Render.lua", "Physics.lua", "Game.lua", "Core.lua" }) do
    dofile(DIR .. "/" .. f)
end

local DBR = _G.DodoBricks
assert(DBR and DBR.geo and DBR.Game and DBR.Render and DBR.Physics, "modules missing")
assert(DBR.geo.COLS == 8 and DBR.geo.ROWS == 12, "grid should be 8x12")

-- fire PLAYER_LOGIN at every frame with an OnEvent handler (Initialize lives there)
for _, f in ipairs(allFrames) do
    local h = f.__scripts and f.__scripts.OnEvent
    if h then h(f, "PLAYER_LOGIN") end
end
assert(DBR.db, "Initialize did not run")
assert(DodoBricksDB, "saved variables missing")

local G, geo = DBR.Game, DBR.geo

-- ------------------------------------------------------------------
-- Helpers to drive the real loop
-- ------------------------------------------------------------------
local function gridConsistent()
    for brick in pairs(G.bricks) do
        for r = brick.row, brick.row + (brick.h or 1) - 1 do
            for c = brick.col, brick.col + (brick.w or 1) - 1 do
                if not G.grid[r] or G.grid[r][c] ~= brick then
                    return false, string.format("brick at (%d,%d) not registered on cell (%d,%d)", brick.col, brick.row, c, r)
                end
            end
        end
    end
    for r = 1, geo.ROWS do
        for c = 0, geo.COLS - 1 do
            local b = G.grid[r][c]
            if b and not G.bricks[b] then
                return false, string.format("grid cell (%d,%d) points to a dead brick", c, r)
            end
        end
    end
    return true
end

local stats = { boss = 0, healer = 0, chest = 0, doubles = 0, splits = 0, maxBalls = 0, maxScore = 0 }

local function launch()
    -- aim at a random upward direction and release
    MOCK_MOUSE.x = 40 + math.random() * (geo.BOARD_W - 80)
    MOCK_MOUSE.y = 350 + math.random() * 250
    MOCK_LMB = false
    G.lmbDown = true
    G.Driver(0.016)   -- AIM branch: UpdateAim sees the release => Fire
    assert(G.state == "FLY", "launch failed, state = " .. tostring(G.state))
end

local function playRound(leaveOne)
    local wasPending = G.pendingDouble and true or false
    launch()
    local frames = 0
    local cheated = false
    while G.state == "FLY" or G.state == "DESCEND" do
        frames = frames + 1
        if frames > 6000 then error("round stuck after 6000 frames at level " .. tostring(G.round)) end
        G.Driver(0.05)
        if G.state == "FLY" and frames == 20 and not cheated then
            cheated = true
            -- play like a god: chip every brick down (optionally leave one to break the clear chain)
            local skip = leaveOne
            for brick in pairs(G.bricks) do
                if skip then skip = false
                else
                    local guard = 0
                    while G.bricks[brick] do
                        G.HitBrick(brick)
                        guard = guard + 1
                        if guard > 20000 then error("brick will not die") end
                    end
                end
            end
        end
    end
    assert(G.state == "AIM" or G.state == "OVER", "unexpected state " .. tostring(G.state))
    if wasPending then stats.doubles = stats.doubles + 1 end
    for brick in pairs(G.bricks) do
        if brick.kind == "boss" then stats.boss = stats.boss + 1 end
        if brick.kind == "healer" then stats.healer = stats.healer + 1 end
        if brick.kind == "chest" then stats.chest = stats.chest + 1 end
    end
    stats.maxBalls = math.max(stats.maxBalls, G.ballTotal + (G.tempCount or 0))
    stats.maxScore = math.max(stats.maxScore, G.score or 0)
    local ok, why = gridConsistent()
    assert(ok, "grid inconsistent after level " .. tostring(G.round) .. ": " .. tostring(why))
end

-- ------------------------------------------------------------------
-- Phase A: new game
-- ------------------------------------------------------------------
G.New()
-- the first descend animation runs via Driver
while G.state == "DESCEND" do G.Driver(0.05) end
assert(G.state == "AIM" and G.round == 1, "New() should land on AIM at level 1")
print("Phase A  OK: new game, level 1, state AIM")

-- ------------------------------------------------------------------
-- Phase B: 110 levels with a god hand (covers chest/healer/triple/events/boss/aura/palette)
-- ------------------------------------------------------------------
local lastScore = 0
while G.round < 110 and G.state ~= "OVER" do
    playRound(G.round % 7 == 3)   -- every 7th-ish round leave a brick: clear chain must break
    assert((G.score or 0) >= lastScore, "score went backwards")
    lastScore = G.score or 0
end
assert(G.state ~= "OVER", "god hand should not die")
assert(stats.boss > 0, "no boss ever seen")
assert(stats.doubles > 0, "no double-descend event ever executed")
assert((G.mult or 1) >= 1, "mult broken")
print(string.format("Phase B  OK: reached level %d, score %d, mult x%d, bosses seen %d, healers %d, chests %d, doubles %d, max balls %d",
    G.round, G.score, G.mult, stats.boss, stats.healer, stats.chest, stats.doubles, stats.maxBalls))

-- ------------------------------------------------------------------
-- Phase C: save -> load roundtrip
-- ------------------------------------------------------------------
local savedRound, savedScore, savedMult, savedBalls = G.round, G.score, G.mult, G.ballTotal
assert(DodoBricksDB.save, "autosave missing")
assert(G.Load(), "load failed")
assert(G.round == savedRound and G.score == savedScore and G.mult == savedMult and G.ballTotal == savedBalls,
    "save/load mismatch")
local ok, why = gridConsistent()
assert(ok, "grid inconsistent after load: " .. tostring(why))
for _ = 1, 5 do playRound(false) end
print(string.format("Phase C  OK: save/load roundtrip at level %d, then 5 more rounds to level %d", savedRound, G.round))

-- ------------------------------------------------------------------
-- Phase D: forced death + play again
-- ------------------------------------------------------------------
local victim
for b in pairs(G.bricks) do victim = b break end
if not victim then error("no brick to push to the floor") end
victim.row = 1
launch()
local frames = 0
while G.state == "FLY" or G.state == "DESCEND" do
    frames = frames + 1
    if frames > 6000 then error("death round stuck") end
    G.Driver(0.05)
    if frames == 20 then
        for brick in pairs(G.bricks) do
            if brick ~= victim then
                while G.bricks[brick] do G.HitBrick(brick) end
            end
        end
    end
end
assert(G.state == "OVER", "expected game over, got " .. tostring(G.state))
assert(DodoBricksDB.save == nil, "save should be cleared on death")
assert((DodoBricksDB.bestScore or 0) > 0, "bestScore never recorded")
assert((DodoBricksDB.bestLevel or 0) >= 100, "bestLevel not recorded")
G.New()
while G.state == "DESCEND" do G.Driver(0.05) end
assert(G.state == "AIM" and G.round == 1 and G.score == 0 and G.mult == 1, "play-again reset broken")
print("Phase D  OK: forced death -> Game Over -> Play Again reset clean")

-- ------------------------------------------------------------------
-- Phase E: legacy 0.2.x save compatibility (no score/kind fields, 7x9 coords)
-- ------------------------------------------------------------------
DodoBricksDB.save = {
    round = 12, ballTotal = 14, launchX = 196,
    bricks = { { col = 2, row = 5, hp = 9, shape = "sq" }, { col = 6, row = 9, hp = 24, shape = "tri", orient = "BL" } },
    items  = { { col = 3, row = 7, kind = "ball" }, { col = 1, row = 6, kind = "laserH" } },
}
assert(G.Load(), "legacy load failed")
assert(G.round == 12 and G.score == 0 and G.mult == 1, "legacy defaults wrong")
local ok2, why2 = gridConsistent()
assert(ok2, "grid inconsistent after legacy load: " .. tostring(why2))
for _ = 1, 3 do playRound(false) end
print(string.format("Phase E  OK: legacy 0.2.x save loads, 3 rounds played to level %d", G.round))

print("ALL PASS")
