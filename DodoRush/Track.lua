-- DodoRush - Track
-- 关卡生成 + 数值平衡(设计讨论定稿,2026-06-11):
--   基准曲线 P(i) = "每关都选最优门"的人数,所有数值锚定它(敌人锚基准而非玩家实际,
--   这样失误才会累积成劣势)。
--   压力系数 α(i):敌墙人数 = α × 过门后基准,从 0.50 爬到 0.86;
--   目标净增长 ρ(i):从 1.28 缓降到 0.90,后期 ρ < 1 + 乘法门封顶 => 必死,记最高关数。
--   每关结构:门(二选一) -> [散兵(可绕开,占基准 12~22%)] -> 敌墙(必打)。
--   每 5 关一个 Boss 墙(α×1.28),Boss 后一关送 ×3/×2 奖励门。
--   门设计在加/乘交叉点附近("人少 +N 香,人多 ×k 香"),后期混入陷阱与"两害相权"。

local DR = _G.DodoRush or {}
_G.DodoRush = DR

local Track = {}
DR.Track = Track

-- 可调参数(数值平衡看这里)
local START_PAR    = 10     -- 开局人数(基准曲线起点,Game 的起始人数与此一致)
local ALPHA0       = 0.50   -- 第 1 关压力系数
local ALPHA_GAIN   = 0.016  -- 每关 +
local ALPHA_CAP    = 0.86   -- 压力封顶
local RHO0         = 1.28   -- 第 1 关目标净增长
local RHO_DECAY    = 0.012  -- 每关 -
local RHO_MIN      = 0.90   -- 净增长下限(<1 = 后期必然走下坡)
local MULT_CAP     = 6      -- 乘法门封顶(后期 g 需求超过它 => 自然衰减)
local TRAP_CHANCE     = 0.18   -- 次门是陷阱(÷2 / -N)的概率
local BOTHBAD_CHANCE  = 0.12   -- 两个门都是负的("两害相权")概率
local SKIRM_CHANCE    = 0.60   -- 出散兵概率
local TRAP_MIN_STAGE    = 3    -- 第几关起允许陷阱
local BOTHBAD_MIN_STAGE = 6    -- 第几关起允许两害相权
local SKIRM_MIN_STAGE   = 2    -- 第几关起出散兵
local SKIRM_FRAC_LO, SKIRM_FRAC_HI = 0.12, 0.22   -- 散兵 = 基准的 12~22%
local BOSS_EVERY      = 5
local BOSS_ALPHA_MULT = 1.28
local BOSS_ALPHA_CAP  = 0.92

-- 元素间距(px,gapAfter = 此元素与下一元素的滚动距离)
local GAP_GATE_SKIRM = 210   -- 门 -> 散兵
local GAP_SKIRM_WALL = 230   -- 散兵 -> 敌墙
local GAP_GATE_WALL  = 360   -- 门 -> 敌墙(无散兵时)
local GAP_WALL_GATE  = 340   -- 敌墙 -> 下一关门(磨墙最长 2 秒也来得及)

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

-- 圆整成"好看的数":>=100 取整十,>=30 取整五,最小 1
local function NiceNum(n)
    n = math.floor(n + 0.5)
    if n >= 100 then n = math.floor(n / 10 + 0.5) * 10
    elseif n >= 30 then n = math.floor(n / 5 + 0.5) * 5 end
    if n < 1 then n = 1 end
    return n
end

-- 门作用于人数(Game 结算也用这个,保证显示与结算一致)
-- ÷ 用 ceil:除法不会直接除到 0(0 只能死于 -门 或战斗)
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

-- 生成一对门:best = 设计上的最优选,other = 次优/陷阱
local function MakeGatePair(i, P)
    -- Boss 后一关:固定奖励走廊 ×3 / ×2
    if i > 1 and ((i - 1) % BOSS_EVERY == 0) then
        return { op = "×", v = 3 }, { op = "×", v = 2 }
    end

    local need = RhoAt(i) / (1 - AlphaAt(i))   -- 本关需要的最优增益倍率
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
        -- 两害相权:本关没有增长,选损失小的
        best = { op = "-", v = NiceNum(P * 0.18) }
        if math.random() < 0.5 then
            other = { op = "÷", v = 2 }
        else
            other = { op = "-", v = NiceNum(P * 0.5) }
        end
    elseif i >= TRAP_MIN_STAGE and r < BOTHBAD_CHANCE + TRAP_CHANCE then
        -- 陷阱门:选错很疼
        if math.random() < 0.5 then
            other = { op = "÷", v = 2 }
        else
            other = { op = "-", v = NiceNum(P * (0.3 + math.random() * 0.3)) }
        end
    else
        -- 次优门:增长是最优的 60~85%,尽量用另一种形态(教学加/乘交叉点)
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

-- 生成第 i 关的全部元素进队列
local function GenStage()
    state.stage = state.stage + 1
    local i = state.stage
    local P = state.par

    local best, other = MakeGatePair(i, P)
    local L, R
    if math.random() < 0.5 then L, R = best, other else L, R = other, best end

    -- 过门后的基准 = 两门里较好的那个(完美玩家)
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

-- 取下一个待生成元素(队列空了就生成下一关)
function Track.Next()
    if #state.queue == 0 then GenStage() end
    return table.remove(state.queue, 1)
end
