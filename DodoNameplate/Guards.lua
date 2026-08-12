-- DodoNameplate :: Guards.lua
-- Secret Values guard toolkit. See GOTCHAS.md S1.
-- THE rule of this codebase: never do Lua-side ops (arith / compare / bool-test / table-key /
-- index / call) on a value that may be a Secret. Guard with issecretvalue() first, or pass the
-- value straight into a Blizzard widget sink.

local ADDON, ns = ...

-- issecretvalue / canaccessvalue may not exist off-Midnight; shim so the addon still loads.
-- On Midnight they are real: Plater force-falses any secret bool (Plater.lua ~8032/8048).
local issecretvalue  = issecretvalue  or function() return false end
local canaccessvalue = canaccessvalue or function() return true  end

local Guards = {}
ns.Guards = Guards

Guards.IsSecret  = issecretvalue
Guards.CanAccess = canaccessvalue

-- Turn a maybe-secret / maybe-nil boolean into a plain boolean.
-- Secret -> false (mirrors Plater's "if issecretvalue(x) then x = false end" pattern).
function Guards.Bool(v)
	if issecretvalue(v) or v == nil then
		return false
	end
	return v and true or false
end

-- UnitIsUnit wrapper. Self / target / focus identity is Secret on Midnight in restricted
-- content, so a raw boolean test can taint-error. Returns plain false when the result is secret.
function Guards.UnitIsUnit(a, b)
	return Guards.Bool(UnitIsUnit(a, b))
end
