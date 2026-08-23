-- DodoGrid :: Dispel.lua
-- Click-to-dispel: a configurable modifier+button click on each cell casts the player's dispel spell
-- on that unit, pairing with the "③ 可驱散" school-colored border (Auras.lua). 12.0 Secret-Values safe:
-- the cast is a secure /cast [@<token>] macro (the game picks the debuff to remove); we never READ aura
-- data. All SetAttribute writes happen OUT OF COMBAT (build-time + PLAYER_REGEN_ENABLED flush).
--
-- Spell is AUTO-DETECTED per class via IsSpellKnown over a candidate list (broadest healer dispel first),
-- re-resolved on spec / talent / spellbook change. Warlock's Singe Magic is a PET spell (special-cased).
-- ns.db.auras.dispelClick.spellOverride (non-empty) wins over auto-detect.

local ADDON, ns = ...

-- Per-class friendly-dispel candidates (verified WoW 12.0 IDs; "Improved" talents augment the base ID in
-- place, so only the base IDs are listed). Pick the first the player KNOWS. Warlock handled below.
local DISPEL_CANDIDATES = {
	PRIEST  = { 527, 32375, 213634 },   -- Purify(Disc/Holy) > Mass Dispel > Purify Disease(Shadow)
	PALADIN = { 4987, 213644 },         -- Cleanse(Holy) > Cleanse Toxins(Prot/Ret)
	DRUID   = { 88423, 2782 },          -- Nature's Cure(Resto) > Remove Corruption(others)
	SHAMAN  = { 77130, 51886 },         -- Purify Spirit(Resto) > Cleanse Spirit(Ele/Enh)
	MONK    = { 115450, 218164 },       -- Detox(Mistweaver) > Detox(Brew/WW) -- distinct IDs
	EVOKER  = { 360823, 374251 },       -- Naturalize(Pres) > Cauterizing Flame(talent)
	MAGE    = { 475 },                  -- Remove Curse(talent)
}
local WARLOCK_SINGE = 89808            -- Singe Magic: Imp PET ability (IsSpellKnown(id, true) + Imp active)

-- ── API posture for this file (keep both shims below to the SAME rule) ────────────────────────
-- 1. If a `C_*` namespaced version exists, that is the call we make.
-- 2. A legacy-global fallback is allowed ONLY when it is type-guarded AND its return SHAPE is
--    known not to have changed. Never call a legacy global bare — the failure of a nil-call here
--    is "the dispel macro body has no spell name in it", which looks EXACTLY like "this spec has
--    no dispel". Both shims end with an explicit safe value so a missing API degrades, not throws.
-- (`GetSpellInfo` was the one bare legacy global left in the whole monorepo; it is gone now — see
--  the note in spellName() for why it did NOT get a guarded fallback.)

local function spellKnown(id, isPet)
	if C_SpellBook and type(C_SpellBook.IsSpellKnown) == "function" then
		-- 2nd arg is a SpellBookSpellBank enum (Player/Pet), NOT a boolean — passing a bool errors.
		local bank = isPet and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
		return C_SpellBook.IsSpellKnown(id, bank) and true or false
	end
	-- Legacy fallback kept: the global form's 2nd arg IS the boolean isPet (deprecated 11.2.0), and
	-- its return shape (a single truthy/falsey) is unambiguous, so normalising it is safe.
	if type(IsSpellKnown) == "function" then return IsSpellKnown(id, isPet) and true or false end
	return false
end

local function spellName(id)
	if C_Spell and type(C_Spell.GetSpellName) == "function" then return C_Spell.GetSpellName(id) end
	-- Deliberately NO `GetSpellInfo` fallback. The modern global returns a different shape than the
	-- old `name, rank, icon, …` tuple, and we cannot verify which shape this client ships — a wrong
	-- shape here silently concatenates garbage into the macro body instead of failing loudly.
	-- Returning nil makes Resolve() report "no dispel spell", which Apply() already handles.
	return nil
end

-- Returns the dispel spell NAME (string) for the macro, or nil if this spec has none.
local function Resolve()
	local d = ns.db and ns.db.auras and ns.db.auras.dispelClick
	if d and d.spellOverride and d.spellOverride ~= "" then return d.spellOverride end
	local _, class = UnitClass("player")
	if class == "WARLOCK" then
		return spellKnown(WARLOCK_SINGE, true) and spellName(WARLOCK_SINGE) or nil
	end
	local cands = DISPEL_CANDIDATES[class]
	if not cands then return nil end
	for _, id in ipairs(cands) do
		if spellKnown(id, false) then return spellName(id) end
	end
	return nil
end

local currentSpell                    -- cached resolved name; refreshed on Refresh()

-- Secure attribute base for the configured bind, e.g. "shift-type1" (modifier-prefixed overrides the
-- "*type1" wildcard target/menu only for that modifier+button; everything else falls through).
local function bindKey(d)
	local mod = d.modifier or "shift"
	local btn = d.button or 1
	local prefix = (mod ~= "" and mod ~= "none") and (mod .. "-") or ""
	return prefix .. "type" .. btn
end

-- Apply (or clear) the dispel bind on one secure button. OOC only (callers gate / build-time).
local function Apply(b)
	local prev = b._dgDispelKey
	if prev then                       -- clear the previously-applied slot so a rebind never leaves a stale cast
		b:SetAttribute(prev, nil)
		b:SetAttribute((prev:gsub("type", "macrotext")), nil)
		b._dgDispelKey = nil
	end
	local d = ns.db and ns.db.auras and ns.db.auras.dispelClick
	if not d or d.enabled == false then return end
	local u = b:GetAttribute("unit")
	if not currentSpell or not u then return end
	local key = bindKey(d)
	b:SetAttribute(key, "macro")
	b:SetAttribute((key:gsub("type", "macrotext")),
		"/cast [@" .. u .. "] " .. currentSpell .. "\n/stopspelltarget")
	b._dgDispelKey = key
end

local dispelDirty = false
local function ApplyAll()
	if InCombatLockdown() then dispelDirty = true; return end   -- secure SetAttribute is OOC-only
	dispelDirty = false
	if ns.ForEachButton then ns.ForEachButton(Apply) end
end

-- Re-resolve the spell then re-apply to every cell. The entry point for events + Options.
local function Refresh()
	if not ns.db then return end
	currentSpell = Resolve()
	ApplyAll()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")        -- first real apply (after Core built the buttons)
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:RegisterEvent("TRAIT_CONFIG_UPDATED")          -- talent swap
f:RegisterEvent("UNIT_PET")                      -- warlock Imp in/out
f:RegisterEvent("PLAYER_REGEN_ENABLED")          -- flush a combat-deferred apply
f:SetScript("OnEvent", function(_, event, arg1)
	if event == "UNIT_PET" then
		if arg1 == "player" then Refresh() end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if dispelDirty then ApplyAll() end
	else
		Refresh()
	end
end)

ns.Dispel = { Resolve = Resolve, Current = function() return currentSpell end, Apply = Apply }
function ns.ApplyDispel() Refresh() end          -- called by Options after a config change
