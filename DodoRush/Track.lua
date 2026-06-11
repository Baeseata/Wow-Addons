-- DodoRush - Track
-- Stage generation + numeric balance (design locked with the user, 2026-06-11):
--   Par curve P(i) = crowd size of a player who picks the best gate every stage; everything
--   anchors to it (enemies anchor to PAR, not the player's actual count, so mistakes
--   compound into a lasting disadvantage).
--   Pressure alpha(i): wall size = alpha x post-gate par, climbing 0.38 -> 0.86;
--   target net growth rho(i): 1.28 easing down to 0.90; late-game rho < 1 plus the
--   multiplier-gate cap = guaranteed eventual death, record the furthest stage.
--   Stage structure: gates (pick one of two) -> [skirmish blob (dodgeable, 10~18% of par)] -> wall (must fight).
--   Boss wall every 5 stages (alpha x1.18); the stage right after a boss grants a x3 / x2 bonus gate pair.
--   Gate pairs are designed near the add/multiply crossover ("+N is better when small,
--   xK is better when big"); traps and lose-lose pairs mix in later.

local DR = _G.DodoRush or {}
_G.DodoRush = DR

local Track = {}
DR.Track = Track

-- Tunables (numeric balance lives here)
-- 0.1.1 tuning notes (2026-06-11; playtest died at stage 6 vs the stage 20~30 target):
--   The old curve ALPHA0=0.50/GAIN=0.016 left only half headroom from stage 1; the stage-5
--   boss fought at an effective alpha of 0.72 (gates only compensate the plain alpha), so
--   even par lost 21% crossing it, and BOTHBAD gates unlocked right after at stage 6 --
--   dying at stage 6 was structural. Worse, need broke 3.3 at stage 11, turning every gate
--   multiplicative and removing the additive-gate catch-up path: any player 40% behind was
--   mathematically dead from stage 8 on.
--   The new curve pushes the death zone from stages 5~8 to ~28+: additive gates survive
--   to ~stage 28 and a boss stage is roughly par-neutral.
local START_PAR    = 10     -- starting crowd (par curve origin; Game starts with the same count)
local ALPHA0       = 0.38   -- stage-1 pressure (was 0.50)
local ALPHA_GAIN   = 0.012  -- per-stage increase (was 0.016; stage 21 = 0.62, stage 31 = 0.74)
local ALPHA_CAP    = 0.86   -- pressure cap (at alpha 0.86, need = 6.4 > MULT_CAP forces decay; second safety)
local RHO0         = 1.28   -- stage-1 target net growth
local RHO_DECAY    = 0.012  -- per-stage decrease
local RHO_MIN      = 0.90   -- net-growth floor (< 1 = the late game always declines)
local MULT_CAP     = 6      -- multiplier-gate cap (late-game required gain exceeds it => natural decay)
local TRAP_CHANCE     = 0.15   -- chance the off-gate is a trap (divide-by-2 / -N) (was 0.18)
local BOTHBAD_CHANCE  = 0.10   -- chance both gates are negative ("lose-lose") (was 0.12)
local SKIRM_CHANCE    = 0.60   -- chance a skirmish blob spawns
local TRAP_MIN_STAGE    = 4    -- first stage traps may appear (was 3)
local BOTHBAD_MIN_STAGE = 8    -- first stage lose-lose may appear (was 6 -- collided with the boss aftermath)
local SKIRM_MIN_STAGE   = 2    -- first stage skirmishes may appear
local SKIRM_FRAC_LO, SKIRM_FRAC_HI = 0.10, 0.18   -- skirmish = 10~18% of par (was 12~22)
local BOSS_EVERY      = 5
local BOSS_ALPHA_MULT = 1.18   -- (was 1.28 -- gates only compensate plain alpha, so 1.28 cost par 21% per boss)
local BOSS_ALPHA_CAP  = 0.90

-- Element spacing (px; gapAfter = scroll distance between this element and the next)
local GAP_GATE_SKIRM = 210   -- gates -> skirmish
local GAP_SKIRM_WALL = 230   -- skirmish -> wall
local GAP_GATE_WALL  = 360   -- gates -> wall (no skirmish)
local GAP_WALL_GATE  = 340   -- wall -> next stage's gates (enough room even for a max 2 s grind)

Track.START_PAR = START_PAR

local state = { stage = 0, par = START_PAR, queue = {} }

local function AlphaAt(i)
    local a = ALPHA0 + ALPHA_GAIN * (i - 1)
    if a > ALPHA_CAP then a = ALPHA_CAP end
    return a
end

local function RhoAt(i)
    local r = RHO0 - RHO_DECAY * (i - 1)
    if r < RHO_MIN then r = RHO_MIN end
    return r
end

-- Round to a "nice" number: >=100 to tens, >=30 to fives, minimum 1
local function NiceNum(n)
    n = math.floor(n + 0.5)
    if n >= 100 then n = math.floor(n / 10 + 0.5) * 10
    elseif n >= 30 then n = math.floor(n / 5 + 0.5) * 5 end
    if n < 1 then n = 1 end
    return n
end

-- Apply a gate to a crowd count (Game settles with this too, so display == settlement)
-- Division uses ceil: a divide gate can never reach 0 directly (only minus gates or
-- combat can finish a crowd)
function Track.ApplyOp(C, g)
    if g.op == "+" then C = C + g.v
    elseif g.op == "-" then C = C - g.v
    elseif g.op == "×" then C = math.floor(C * g.v)
    else C = math.ceil(C / g.v) end
    if C < 0 then C = 0 end
    if C > 9999 then C = 9999 end
    return C
end

function Track.GateText(g)
    if g.op == "×" then return "×" .. g.v end
    if g.op == "÷" then return "÷" .. g.v end
    if g.op == "+" then return "+" .. g.v end
    return "-" .. g.v
end

-- Generate a gate pair: best = the designed optimal pick, other = suboptimal / trap
local function MakeGatePair(i, P)
    -- Stage right after a boss: fixed bonus corridor x3 / x2
    if i > 1 and ((i - 1) % BOSS_EVERY == 0) then
        return { op = "×", v = 3 }, { op = "×", v = 2 }
    end

    local need = RhoAt(i) / (1 - AlphaAt(i))   -- optimal gain multiplier required this stage
    local best
    if need <= 3.3 and math.random() < 0.5 then
        best = { op = "+", v = NiceNum((need - 1) * P) }
    else
        local k = math.floor(need + 0.5)
        if k < 2 then k = 2 elseif k > MULT_CAP then k = MULT_CAP end
        best = { op = "×", v = k }
    end

    local other
    local r = math.random()
    if i >= BOTHBAD_MIN_STAGE and r < BOTHBAD_CHANCE then
        -- Lose-lose: no growth this stage, pick the smaller loss
        best = { op = "-", v = NiceNum(P * 0.18) }
        if math.random() < 0.5 then
            other = { op = "÷", v = 2 }
        else
            other = { op = "-", v = NiceNum(P * 0.5) }
        end
    elseif i >= TRAP_MIN_STAGE and r < BOTHBAD_CHANCE + TRAP_CHANCE then
        -- Trap gate: picking wrong hurts
        if math.random() < 0.5 then
            other = { op = "÷", v = 2 }
        else
            other = { op = "-", v = NiceNum(P * (0.3 + math.random() * 0.3)) }
        end
    else
        -- Suboptimal gate: 60~85% of the optimal growth, preferring the other form
        -- (teaches the add/multiply crossover)
        local f = 0.60 + math.random() * 0.25
        local bc = Track.ApplyOp(P, best)
        local target = P + (bc - P) * f
        if best.op == "×" then
            other = { op = "+", v = NiceNum(math.max(1, target - P)) }
        elseif P * 2 <= target * 1.15 then
            other = { op = "×", v = 2 }
        else
            other = { op = "+", v = NiceNum(math.max(1, (target - P) * 0.8)) }
        end
    end
    return best, other
end

-- Generate all elements of stage i into the queue
local function GenStage()
    state.stage = state.stage + 1
    local i = state.stage
    local P = state.par

    local best, other = MakeGatePair(i, P)
    local L, R
    if math.random() < 0.5 then L, R = best, other else L, R = other, best end

    -- Post-gate par = the better of the two gates (perfect player)
    local Pb = math.max(Track.ApplyOp(P, best), Track.ApplyOp(P, other), 1)

    local isBoss = (i % BOSS_EVERY == 0)
    local a = AlphaAt(i)
    if isBoss then
        a = a * BOSS_ALPHA_MULT
        if a > BOSS_ALPHA_CAP then a = BOSS_ALPHA_CAP end
    end
    local E = math.max(3, math.floor(Pb * a + 0.5))

    local hasSkirm = (i >= SKIRM_MIN_STAGE) and (math.random() < SKIRM_CHANCE)
    local S = 0
    if hasSkirm then
        S = math.max(2, NiceNum(Pb * (SKIRM_FRAC_LO + math.random() * (SKIRM_FRAC_HI - SKIRM_FRAC_LO))))
    end

    local q = state.queue
    q[#q + 1] = { type = "gates", stage = i, L = L, R = R,
                  gapAfter = (S > 0) and GAP_GATE_SKIRM or GAP_GATE_WALL }
    if S > 0 then
        q[#q + 1] = { type = "enemy", kind = "blob", count = S,
                      xfrac = (math.random() < 0.5) and 0.27 or 0.73,
                      gapAfter = GAP_SKIRM_WALL }
    end
    q[#q + 1] = { type = "enemy", kind = isBoss and "boss" or "wall", count = E,
                  gapAfter = GAP_WALL_GATE }

    state.par = math.max(1, Pb - E)
end

function Track.Reset()
    state.stage = 0
    state.par = START_PAR
    wipe(state.queue)
end

-- Pop the next element to spawn (generates the next stage when the queue runs dry)
function Track.Next()
    if #state.queue == 0 then GenStage() end
    return table.remove(state.queue, 1)
end
