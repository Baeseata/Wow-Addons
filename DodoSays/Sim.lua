local ADDON, ns = ...

-- ===========================================================================
-- Sim.lua  ·  rehearse without the boss.
--
-- The real thing happens three times per pull, in a delve you have to walk
-- back into. That is a terrible loop to develop or practise against, so this
-- drives the exact same seam Detector drives -- same events, same board, same
-- announcements -- with nothing registered and no encounter anywhere.
--
-- It is not a mock of the display. It IS the display; only the source of the
-- events differs. Anything that works here works in the fight, and anything
-- broken here is broken there.
-- ===========================================================================

local Sim = {}
ns.Sim = Sim

local running, ticker

function Sim.Stop()
	if ticker then ticker:Cancel(); ticker = nil end
	running = false
end

-- --------------------------------------------------------------------------
-- Open a showing half of `waves` waves. The player taps as many quarters as
-- they like; `/ds go` (or the timeout) locks it and plays the run back on the
-- difficulty's real cadence.
-- --------------------------------------------------------------------------
function Sim.Round(waves, difficulty)
	Sim.Stop()
	difficulty = difficulty or (ns.Detector and ns.Detector.state.difficulty) or "normal"
	waves = tonumber(waves) or (ns.Detector and ns.Detector.WavesFor(difficulty, 1)) or 3

	running = true
	ns.Emit("reset")
	ns.Emit("round", waves)
	print(("|cff88ccffDodoSays|r sim: tap %d quarter(s), then |cffffd100/ds go|r."):format(waves))
end

-- --------------------------------------------------------------------------
-- Lock what is on the board and call it back on the clock. Real cadence, so
-- the rehearsal is honest about how little time there is between waves.
-- --------------------------------------------------------------------------
function Sim.Go(difficulty)
	local seq = ns.Board.Sequence()
	local n = #seq
	if n == 0 then
		print("|cff88ccffDodoSays|r sim: nothing tapped yet.")
		return
	end

	-- Echo cadence, NOT the sermon's. Measured 2026-08-15 on ?: waves land
	-- 3.25-3.27s apart -- a 3.00s cast plus a quarter-second breath -- while the
	-- sermon's own slot is 3.50. Rehearsing on 3.50 would be 8% kinder than the
	-- fight, and a practice mode that is easier than the real thing teaches the
	-- wrong reflex.
	difficulty = difficulty or (ns.Detector and ns.Detector.state.difficulty) or "normal"
	local cast = (ns.Detector and ns.Detector.CastLength()) or 3.00
	local gap = cast + 0.25

	ns.Emit("lock", n)

	local step = 0
	ticker = C_Timer.NewTicker(gap, function()
		step = step + 1
		if step > n then
			Sim.Stop()
			ns.Emit("finish")
			return
		end
		ns.Emit("call", step, seq[step])
	end, n + 1)
end

function Sim.IsRunning() return running == true end
