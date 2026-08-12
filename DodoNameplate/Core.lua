-- DodoNameplate :: Core.lua
-- Event hub: track nameplates, classify each, and drive the per-group styling in Plate.lua.
-- Owns SavedVariables (ns.db) + the player's role cache (tank vs dps/healer).

local ADDON, ns = ...

ns.plates = {}   -- [unitToken] = { plate = <frame>, group = <id> }
ns.isTank = false

-- Default settings (merged into DodoNameplateDB at login; surfaced in Options.lua).
-- Per-group blocks keyed by the GROUP ids in Classification.lua. Self (1) = Blizzard personal
-- resource (not styled); enemy player (6) = Phase 2 (PvP), no block yet.
-- Cast-bar settings are PER-GROUP (decoupled): castHeight/castColor/castImportantColor.
-- (Width always follows the healthbar width -- not configurable. Important casts = a clean R->L
-- reverse-fill bar in castImportantColor; no glow/gold-border emphasis.) The hostile group (5) also
-- has importantHpRecolor + importantHpColor (recolor the health bar while the unit casts an important
-- spell -- the friendly equivalent is deferred).
local function castBlock(height) return {
	castHeight = height,
	castTextSize = 8,                                 -- spell name + countdown font size
	castColor = { r = 1, g = 0.78, b = 0 },           -- normal cast (gold)
	castImportantColor = { r = 1, g = 0.30, b = 0 },  -- important cast (orange by default)
} end

local function merge(base, extra)
	for k, v in pairs(extra) do base[k] = v end
	return base
end

ns.defaults = {
	locale      = "enUS",                            -- shipped default = English; "auto" follows client, "zhCN" = 中文 (panel only)
	colorNormal = { r = 0.85, g = 0.15, b = 0.15 },  -- threat-state "normal for your role" (red)
	colorWarn   = { r = 0.15, g = 0.40, b = 0.95 },  -- threat-state "wrong for your role" (blue)
	targetScale = 1.0,                               -- target highlight scale; 1.0 = no enlargement, slider 1.0-1.6
	markSize    = 40,                                -- raid target icon size (global, above the bar)
	overlays    = { dimTapped = true, hideCritter = false },
	-- Shared aura config for enemy plates (hostile mobs + enemy players). WoW 12.1's secure
	-- CustomAuraContainer owns filtering and display; addon Lua never enumerates restricted aura data.
	auras = {
		enabled = true, w = 26, h = 26, max = 4, yOffset = 5, alpha = 0.85, showTimer = true,
		mine = true,        -- personal/nameplate debuffs (left row, black border)
		cc = true,          -- HARMFUL|CROWD_CONTROL    共享控制 (right slot, red border, any caster)
		important = true,   -- priority personal debuffs (left row, gold border)
		buffs = false,      -- HELPFUL                  敌方增益 (buff row below-bar-right, green; sparse on NPCs)
		purge = true,       -- HELPFUL|RAID_PLAYER_DISPELLABLE  可净化增益 (buff row, purple; gated on ns.playerCanPurge)
		defensive = true,   -- HELPFUL|BIG/EXTERNAL_DEFENSIVE   防御性增益 (buff row, white; enemy players only)
		buffMax = 3,        -- max icons in the buff row (below-bar right)
	},
	-- Group defaults below were captured from Jerry's live config (2026-06-24, reload-flushed
	-- SavedVariables) and set as the baseline so a fresh download matches his setup.
	-- Vestigial fields (castGlow/castWidth/a stray group-5 targetScale) were dropped. CopyDefaults
	-- only fills MISSING keys -> existing saves are untouched; this only affects fresh installs.
	groups = {
		-- party / raid
		[2] = merge(castBlock(9),  { enabled = true, width = 75,  height = 20, showName = true, nameSize = 18, levelSize = 18, healthSize = 18, showCast = false }),
		-- other friendly player
		[3] = merge(castBlock(9),  { enabled = true, width = 90,  height = 11, showName = true, nameSize = 12, levelSize = 12, healthSize = 12, showCast = false }),
		-- friendly NPC
		[4] = merge(castBlock(14), { enabled = true, width = 100, height = 14, showName = true, nameSize = 14, levelSize = 14, healthSize = 14, showCast = true, castTextSize = 14 }),
		-- hostile creature
		[5] = merge(castBlock(24), {
			enabled = true, width = 214, height = 24, showName = true, nameSize = 16, levelSize = 16, healthSize = 16, showCast = true, castTextSize = 18,
			castImportantColor = { r = 1, g = 1, b = 1 },                                  -- white
			importantHpRecolor = true, importantHpColor = { r = 0.933, g = 0.565, b = 1 }, -- purple
			castTargetShow = true, castTargetHeight = 18, castTargetWidth = 70, castTargetTextSize = 18,
			castTargetFallbackColor = { r = 0.486, g = 1, b = 0.471 },                      -- green (cast target bar color)
		}),
		-- enemy player (Phase 2 PvP): class-colored bar + cast bar. Color source = ClassColor (guarded;
		-- falls back to reaction red when class is secret, e.g. arena identity-restricted). Works in
		-- war mode / battleground / arena uniformly (Classify is pure reaction-based).
		[6] = merge(castBlock(16), { enabled = true, width = 200, height = 20, showName = true, nameSize = 20, levelSize = 20, healthSize = 20, showCast = true, castTextSize = 16, castImportantColor = { r = 1, g = 1, b = 1 } }),
	},
}

local function CopyDefaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

local function GetPlate(unit)
	-- Normal plate only. Do NOT fall back to the forbidden form GetNamePlateForUnit(unit, true):
	-- friendly party/raid plates inside PvE instances are forbidden/protected frames (GOTCHAS.md S2),
	-- and CreateFrame/SetAlpha on them taints. nil here -> OnAdded skips -> clean Blizzard default.
	return C_NamePlate.GetNamePlateForUnit(unit)
end

local function RefreshRole()
	local GetSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
	local GetRole = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationRole) or GetSpecializationRole
	local spec = GetSpec and GetSpec()
	ns.isTank = (spec and GetRole and GetRole(spec) == "TANK") or false
end

-- Offensive purge / dispel-magic spells per class (remove enemy BUFFS). Gates the "purgeable buffs"
-- aura category so it only shows when the player can actually act on it. Warlock excluded (pet-based
-- purge -- Jerry, 2026-06-24). Local-player spellbook check only (non-secret); the per-aura match is
-- the HELPFUL|RAID_PLAYER_DISPELLABLE filter in Auras.lua.
local PURGE_SPELL = {
	SHAMAN = 370,    -- Purge
	MAGE   = 30449,  -- Spellsteal
	PRIEST = 528,    -- Dispel Magic (offensive)
	DRUID  = 2908,   -- Soothe
	HUNTER = 19801,  -- Tranquilizing Shot
}
local function SpellKnown(id)
	if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(id) end
	if IsSpellKnown then return IsSpellKnown(id) end
	return false
end
local function RefreshPurge()
	local _, class = UnitClass("player")
	local id = class and PURGE_SPELL[class]
	ns.playerCanPurge = (id and SpellKnown(id)) or false
end

local function OnAdded(unit)
	local plate = GetPlate(unit)
	if not plate then return end
	local group = ns.Classify(unit)
	ns.plates[unit] = { plate = plate, group = group }
	ns.Style.Apply(plate, unit, group)
end

local function OnRemoved(unit)
	local entry = ns.plates[unit]
	if entry then
		ns.Style.Clear(entry.plate)
		ns.plates[unit] = nil
	end
end

-- Reaction / hostility can flip live (mind control, war mode, sanctuary). UNIT_FACTION / UNIT_FLAGS
-- fire for many units, so filter cheaply on ns.plates before doing any work.
local function OnFlip(unit)
	local entry = unit and ns.plates[unit]
	if entry then
		entry.group = ns.Classify(unit)
		ns.Style.Apply(entry.plate, unit, entry.group)
	end
end

local function OnHealth(unit)
	local entry = unit and ns.plates[unit]
	if entry then ns.Style.Health(entry.plate, unit) end
end

local function OnName(unit)
	local entry = unit and ns.plates[unit]
	if entry then ns.Style.UpdateName(entry.plate, unit) end
end

local function OnLevel(unit)
	local entry = unit and ns.plates[unit]
	if entry then ns.Style.UpdateLevel(entry.plate, unit) end
end

local function OnThreat(unit)
	local entry = unit and ns.plates[unit]
	if entry then ns.Style.Recolor(entry.plate, unit) end
end

local function RecolorAll()
	for unit, entry in pairs(ns.plates) do
		ns.Style.Recolor(entry.plate, unit)
	end
end

local function RefreshAllAuras()
	for unit, entry in pairs(ns.plates) do
		ns.Style.Auras(entry.plate, unit)
	end
end

-- PLAYER_TARGET_CHANGED carries no unit; find the target's plate by frame and flag all tracked.
local function OnTargetChanged()
	local tp = C_NamePlate.GetNamePlateForUnit("target")
	for _, entry in pairs(ns.plates) do
		ns.Style.SetTarget(entry.plate, entry.plate == tp)
	end
end

local function OnFocusChanged()
	local fp = C_NamePlate.GetNamePlateForUnit("focus")
	for _, entry in pairs(ns.plates) do
		ns.Style.SetFocus(entry.plate, entry.plate == fp)
	end
end

local function OnRaidMarkers()
	for unit, entry in pairs(ns.plates) do
		ns.Style.Mark(entry.plate, unit)
	end
end

local function OnCastStart(unit, channeled)
	local e = unit and ns.plates[unit]
	if e then ns.Style.CastStart(e.plate, unit, channeled) end
end

local function OnCastStop(unit)
	local e = unit and ns.plates[unit]
	if e then ns.Style.CastStop(e.plate) end
end

local function OnCastShield(unit, notInterruptible)
	local e = unit and ns.plates[unit]
	if e then ns.Style.Shield(e.plate, notInterruptible) end
end

local f = CreateFrame("Frame", "DodoNameplateEventFrame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
f:RegisterEvent("NAME_PLATE_CREATED")
f:RegisterEvent("UNIT_FACTION")
f:RegisterEvent("UNIT_FLAGS")
f:RegisterEvent("UNIT_HEALTH")
f:RegisterEvent("UNIT_MAXHEALTH")
f:RegisterEvent("UNIT_NAME_UPDATE")
f:RegisterEvent("UNIT_LEVEL")
f:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
f:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("PLAYER_FOCUS_CHANGED")
f:RegisterEvent("RAID_TARGET_UPDATE")
f:RegisterEvent("UNIT_SPELLCAST_START")
f:RegisterEvent("UNIT_SPELLCAST_STOP")
f:RegisterEvent("UNIT_SPELLCAST_DELAYED")
f:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
f:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
f:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
f:RegisterEvent("UNIT_SPELLCAST_FAILED")
f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
f:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")

f:SetScript("OnEvent", function(self, event, arg1)
	if event == "NAME_PLATE_UNIT_ADDED" then
		OnAdded(arg1)
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		OnRemoved(arg1)
	elseif event == "NAME_PLATE_CREATED" then
		-- arg1 = base nameplate frame. Reserved for pre-building widgets (later).
	elseif event == "UNIT_FACTION" or event == "UNIT_FLAGS" then
		OnFlip(arg1)
	elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
		OnHealth(arg1)
	elseif event == "UNIT_NAME_UPDATE" then
		OnName(arg1)
	elseif event == "UNIT_LEVEL" then
		OnLevel(arg1)
	elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
		OnThreat(arg1)
	elseif event == "PLAYER_TARGET_CHANGED" then
		OnTargetChanged()
	elseif event == "PLAYER_FOCUS_CHANGED" then
		OnFocusChanged()
	elseif event == "RAID_TARGET_UPDATE" then
		OnRaidMarkers()
	elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
		OnCastStart(arg1, false)
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
		OnCastStart(arg1, true)
	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
		or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
		OnCastStop(arg1)
	elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
		OnCastShield(arg1, false)
	elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
		OnCastShield(arg1, true)
	elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
		RefreshRole()
		RefreshPurge()
		RecolorAll()
		RefreshAllAuras()
	elseif event == "SPELLS_CHANGED" then
		RefreshPurge()
		RefreshAllAuras()
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- Appearance changes deferred while AuraButtons were restricted can be applied now.
		RefreshAllAuras()
	elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
		-- Map/encounter restrictions can change independently of combat. RestyleRecord re-defers
		-- safely when auras are still secret, so every transition may request a refresh.
		RefreshAllAuras()
	elseif event == "PLAYER_LOGIN" then
		DodoNameplateDB = DodoNameplateDB or {}
		ns.db = DodoNameplateDB
		-- migrate the v0.2.0 single 'hostile' block into groups[5]
		if ns.db.hostile and not ns.db.groups then
			ns.db.groups = { [5] = ns.db.hostile }
			if ns.db.hostile.targetScale then ns.db.targetScale = ns.db.hostile.targetScale end
			ns.db.hostile = nil
		end
		-- migrate the <=v0.6.2 GLOBAL cast settings into each per-group block (now decoupled)
		if ns.db.groups then
			for _, g in pairs(ns.db.groups) do
				if g.castHeight == nil and ns.db.castHeight ~= nil then g.castHeight = ns.db.castHeight end
				if g.castImportantColor == nil and ns.db.castImportantColor ~= nil then g.castImportantColor = ns.db.castImportantColor end
			end
		end
		ns.db.castHeight, ns.db.castImportantColor, ns.db.castGlow = nil, nil, nil
		-- one-time (v0.8.0): the shipped target scale default dropped 1.18 -> 1.0; reset existing saves
		-- to 1.0 once (Jerry's old baseline was 1.18). Marker guards it so a later manual change sticks.
		if not ns.db.tscaleReset10 then
			ns.db.targetScale = 1.0
			ns.db.tscaleReset10 = true
		end
		-- aura config moved from per-group to a shared ns.db.auras (v0.8.0); drop the old per-group copies.
		if ns.db.groups then for _, g in pairs(ns.db.groups) do g.auras = nil end end
		CopyDefaults(ns.db, ns.defaults)
		RefreshRole()
		RefreshPurge()
		-- xpcall, not a bare call: an error inside Initialize used to unwind this whole handler,
		-- taking ApplyLocale, InitOptions (so /dnp died silently), RefreshAllAuras and the
		-- version print with it. geterrorhandler keeps the full traceback going to BugSack.
		if ns.Auras then xpcall(ns.Auras.Initialize, geterrorhandler()) end
		if ns.ApplyLocale then ns.ApplyLocale() end
		if ns.InitOptions then ns.InitOptions() end
		RefreshAllAuras()
		local ver = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"
		print("|cff66ccffDodoNameplate|r v" .. ver .. " loaded. /dnp for options.")
	end
end)
