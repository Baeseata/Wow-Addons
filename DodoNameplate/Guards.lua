-- DodoNameplate :: Guards.lua
-- Secret Values guard toolkit. See GOTCHAS.md S1.
-- THE rule of this codebase: never do Lua-side ops (arith / compare / bool-test / table-key /
-- index / call) on a value that may be a Secret. Guard with issecretvalue() first, or pass the
-- value straight into a Blizzard widget sink.

local ADDON, ns = ...

-- canaccessvalue may not exist off-Midnight; shim so the addon still loads.
-- On Midnight it is real: Plater force-falses any secret bool (Plater.lua ~8032/8048).
local canaccessvalue = canaccessvalue or function() return true  end

-- ============================================================================
-- isSecret -- a DELIBERATE COPY. Do NOT replace this with `Dodo.IsSecret`.
--
-- DodoNameplate is distributed standalone on CurseForge and deliberately declares no
-- `## OptionalDeps: Dodo` and no `## Group: Dodo` (see CLAUDE.md). `Dodo/` is never in
-- this addon's package, so `_G.Dodo` is simply absent for most of its users. Every addon
-- that publishes independently must carry its own copy -- that is the cost of the choice,
-- not an oversight.
--
-- KEY: do not hard-code the count -- it starts rotting the day you write it.
--      Re-derive: git grep -n 'pcall(issecretvalue' -- '*.lua'
--      2026-08-22: 5 wrapped copies (DodoNameplate/Guards, DodoSays/Util, DodoUnholy/Rotation,
--      DodoGuanzhu/Macro, DodoGrid/Core), all aligned to type-probe + pcall + `== true`.
--      NOTE DodoCombatHUD has 2 further INLINE uses (~795 / ~1501) outside these 5.
-- ⚠ FOUR copies of this function exist in this repo and they must keep the SAME SHAPE
-- (type probe -> pcall -> normalise to a plain boolean). Change one, change all four:
--     DodoNameplate/Guards.lua   (this file)
--     DodoSays/Util.lua
--     DodoGuanzhu/Macro.lua
--     DodoUnholy/Rotation.lua
-- Re-derive that list with `git grep -n issecretvalue -- '*.lua'` -- line numbers rot,
-- the shape does not. Four hand-written copies of one invariant is a silent-divergence
-- generator; keeping them literally identical is what makes a diff meaningful.
--
-- Why each piece, so nobody "simplifies" one of them back out:
--   type probe -- `issecretvalue` does not exist off-Midnight. No API means nothing is secret.
--   pcall      -- the call itself can throw on some builds. A guard that can crash is not a guard.
--   == true    -- the caller boolean-tests the answer, so the answer must already be a PLAIN
--                 boolean. Handing back a secret (or nil) is the exact taint error this file
--                 exists to prevent; DodoSays lost a whole encounter to `nil` folding to false.
-- ============================================================================
local function isSecret(v)
	if type(issecretvalue) ~= "function" then return false end
	local ok, secret = pcall(issecretvalue, v)
	return ok and secret == true
end

local Guards = {}
ns.Guards = Guards

Guards.IsSecret  = isSecret
Guards.CanAccess = canaccessvalue

-- Turn a maybe-secret / maybe-nil boolean into a plain boolean.
-- Secret -> false (mirrors Plater's "if issecretvalue(x) then x = false end" pattern).
-- Goes through isSecret, not through the raw global: a second code path here would be a
-- fifth divergent copy inside the one file that is supposed to own this rule.
function Guards.Bool(v)
	if isSecret(v) or v == nil then
		return false
	end
	return v and true or false
end

-- UnitIsUnit wrapper. Self / target / focus identity is Secret on Midnight in restricted
-- content, so a raw boolean test can taint-error. Returns plain false when the result is secret.
function Guards.UnitIsUnit(a, b)
	return Guards.Bool(UnitIsUnit(a, b))
end
