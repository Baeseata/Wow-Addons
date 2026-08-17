-- DodoNameplate :: Plate.lua
-- Replace the Blizzard plate with our own healthbar + name + raid marker + cast bar for any
-- ENABLED group (ns.db.groups[g]). Color per group: hostile = role-aware threat (DESIGN S2),
-- players = class color, friendly NPC = reaction. Border encodes state with priority
-- target (white) > focus (cyan) > elite/boss (gold) / rare (silver) > normal (black).
-- Overlays: dim tapped, hide critters.
--
-- Midnight specifics (ThreatPlates / Plater): hide Blizzard UnitFrame via SetAlpha(0) + keep-hidden
-- hooksecurefunc w/ recursion lock; color via GetStatusBarTexture():SetVertexColor; SetValue accepts
-- secret health; UnitThreatSituation guarded; cast via UnitCastingDuration/UnitChannelDuration ->
-- SetTimerDuration + shield via SetAlphaFromBoolean; class token via UnitClassBase (localized name
-- is secret). Target/focus detected by C_NamePlate frame compare, NOT secret UnitIsUnit.

local ADDON, ns = ...
local Guards = ns.Guards
local PARTY, FRIENDLY, FRIENDLY_NPC, HOSTILE, ENEMY_PLAYER =
	ns.GROUP.PARTY, ns.GROUP.FRIENDLY, ns.GROUP.FRIENDLY_NPC, ns.GROUP.HOSTILE, ns.GROUP.ENEMY_PLAYER
-- name-in-bar + aura row apply to both enemy groups (hostile creature + enemy player).
local function IsEnemyPlate(g) return g == HOSTILE or g == ENEMY_PLAYER end

local HEALTHBAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"  -- flat solid fill (vertex-colored)
local STRIPE = "Interface\\AddOns\\DodoNameplate\\Media\\stripe"  -- diagonal-stripe tile (uninterruptible cast)
local ARROW  = "Interface\\AddOns\\DodoNameplate\\Media\\arrow"   -- white up-arrow (current-target indicator, tintable)
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"  -- locale-correct default (renders CJK)

local COLOR_NORMAL = { r = 0.85, g = 0.15, b = 0.15 }
local COLOR_WARN   = { r = 0.15, g = 0.40, b = 0.95 }
local DEF_TSCALE   = 1.18
local NEUTRAL_YELLOW = { r = 1, g = 0.85, b = 0.1 }
local CAST_COLOR_NORMAL    = { r = 1, g = 0.78, b = 0 }   -- normal cast (gold)
local CAST_COLOR_IMPORTANT = { r = 1, g = 0.30, b = 0 }   -- fallback if ns.db not ready

-- Border state colors
local B_NORMAL = { 0, 0, 0 }
local B_TARGET = { 1, 1, 1 }
local B_FOCUS  = { 0.2, 0.9, 0.9 }
local B_ELITE  = { 1, 0.82, 0 }
local B_RARE   = { 0.85, 0.85, 0.9 }

-- Frame levels above the health bar, as offsets from f.hb:GetFrameLevel(). Everything painted over
-- the bar has to agree on one stack, because two of the three painters are not ours to order:
--
--   +1                 hb's own border ring (child of hb, auto level)
--   +LEVEL_TINT        Tint.lua's per-token proxy -> its aura containers -> their buttons -> nested
--                      containers -> their buttons ... each AND-link costs two more levels, so a
--                      chain of N spells reaches LEVEL_TINT + 2N. LEVEL_IMPORTANT caps N at 11.
--   +LEVEL_IMPORTANT   important-cast recolour (f.impTint), above every DoT tint
--   +LEVEL_TEXT        name / health % / elite icon, above everything so they stay readable
--
-- Aura buttons report a SECRET frame strata and refuse SetFrameLevel while auras are secret, so
-- their level can only be set by choosing their ancestor's -- never by touching them (GOTCHAS S5).
ns.LEVEL_TINT      = 2
ns.LEVEL_IMPORTANT = 24
ns.LEVEL_TEXT      = 25

-- Enemy-player bars carry two channels: the DoT tint takes everything except a thin strip along the
-- TOP, which is reserved for the class colour. Both stay fully saturated, which alpha-blending them
-- could not do -- a half-transparent orange over a blue Shaman is a third colour, so the DoT signal
-- would look different on every class and neither channel would be readable.
--
-- A fixed pixel reserve, not a fraction: it is the minimum needed to still register the class hue, so
-- it should not grow with the bar. Nothing here is conditional on whether a DoT is actually up -- it
-- cannot be, since only Blizzard knows that. Nothing painted means the whole bar shows the class
-- colour; a DoT painting the lower region leaves exactly this strip behind.
--
-- Hostile creatures are NOT split: they have no class-colour channel, so it would only cost tint area.
-- Shared with Tint.lua, which anchors its texture proxy to the region below the strip.
ns.TINT_CLASS_STRIP = 4

local CAST_INTERP  = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local CAST_DIR     = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime
local CHANNEL_DIR  = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime

-- A secret counts as present, but must be detected before any nil/boolean comparison.
local function HasValue(v) return Guards.IsSecret(v) or v ~= nil end

-- Health-percent curve: maps the (secret) health fraction to a plain 0-100 number we CAN format
-- (the sanctioned way to read enemy health % under Secret Values). Blizzard ships CurveConstants.ScaleTo100.
-- Integer 0-100 STEP curve: maps the (secret) health fraction to a whole-number percent. We build
-- our own (Blizzard's CurveConstants.ScaleTo100 is linear -> fractional) so the result renders with
-- NO decimals even when it comes back secret on 12.1 (shown via the SetText sink).
local SCALE100
if C_CurveUtil and C_CurveUtil.CreateCurve then
	local c = C_CurveUtil.CreateCurve()
	if c then
		if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
			c:SetType(Enum.LuaCurveType.Step)
		end
		for i = 0, 100 do c:AddPoint(i / 100, i) end
		SCALE100 = c
	end
end

local function CN() return (ns.db and ns.db.colorNormal) or COLOR_NORMAL end
local function CW() return (ns.db and ns.db.colorWarn)   or COLOR_WARN   end

local Style = {}
ns.Style = Style

---------------------------------------------------------------------------------------------------
-- Blizzard plate hiding
---------------------------------------------------------------------------------------------------
local function HookUnitFrame(uf)
	if uf.dnpHooked or uf:IsForbidden() then return end
	uf.dnpHooked = true
	local locked = false
	hooksecurefunc(uf, "SetAlpha", function(self)
		if locked or self:IsForbidden() then return end
		if self.dnpHide then
			locked = true
			self:SetAlpha(0)
			locked = false
		end
	end)
	uf:HookScript("OnShow", function(self)
		if self.dnpHide then self:SetAlpha(0) end
	end)
end

---------------------------------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------------------------------
-- Mob (hostile) name sits INSIDE the bar, right after the elite icon (or flush-left when none),
-- clamped before the % text. Other groups keep the name above the bar. Called from LayoutPlate and
-- again from UpdateClassification (elite visibility decides the left anchor).
local function AnchorName(f)
	f.name:ClearAllPoints()
	f.name:SetJustifyH("LEFT")
	if IsEnemyPlate(f.group) then
		if f.elite:IsShown() then
			f.name:SetPoint("LEFT", f.elite, "RIGHT", 2, 0)
		else
			f.name:SetPoint("LEFT", f.hb, "LEFT", 3, 0)
		end
		f.name:SetPoint("RIGHT", f.hpPct, "LEFT", -2, 0)
	else
		f.name:SetPoint("BOTTOMLEFT", f.hb, "TOPLEFT", 1, 3)
	end
end

local function LayoutPlate(f, cfg)
	local w = cfg.width or 120
	f:SetSize(w, cfg.height or 12)
	-- hostile mob name auto-sizes to fill the bar height (no per-group nameSize); others use nameSize.
	local nameSize = IsEnemyPlate(f.group) and math.max(8, (cfg.height or 12) - 6) or (cfg.nameSize or 9)
	f.name:SetFont(FONT, nameSize, "OUTLINE")
	f.name:SetShown(cfg.showName ~= false)
	AnchorName(f)
	f.level:SetFont(FONT, cfg.levelSize or 8, "OUTLINE")
	f.hpPct:SetFont(FONT, cfg.healthSize or 8, "OUTLINE")
	f.hpPctSign:SetFont(FONT, cfg.healthSize or 8, "OUTLINE")
	local ch = cfg.castHeight or 9
	f.castbar:SetSize(w, ch)   -- cast bar width always follows the healthbar width
	f.castbar.icon:SetSize(ch, ch)   -- spell icon matches the cast bar height
	f.castbar.text:SetFont(FONT, cfg.castTextSize or 8, "OUTLINE")
	f.castbar.time:SetFont(FONT, cfg.castTextSize or 8, "OUTLINE")
	f.castbar.noInterrupt:SetTexCoord(0, w / 32, 0, ch / 32)   -- tile the stripe undistorted
	f.castTarget:SetSize(cfg.castTargetWidth or w, cfg.castTargetHeight or 9)
	f.castTarget.text:SetFont(FONT, cfg.castTargetTextSize or 8, "OUTLINE")
	local eh = math.max(8, (cfg.height or 12) - 2)
	f.elite:SetSize(eh, eh)                                   -- classification icon fits the bar height
	-- raid marker: global size, centered directly above the bar (the name, on hb, draws over it)
	local ms = (ns.db and ns.db.markSize) or 24
	f.mark:SetSize(ms, ms)
	-- current-target arrows: size tracks the bar height (white, no config)
	local ah = cfg.height or 12
	f.arrowL:SetSize(ah, ah)
	f.arrowR:SetSize(ah, ah)

	-- aura row (enemy plates): lay it out, then push the centered raid marker above it so they do not overlap
	local mY = 0
	if IsEnemyPlate(f.group) and ns.Auras then
		ns.Auras.Layout(f)
		local a = ns.db.auras
		if not a or a.enabled ~= false then
			mY = ((a and a.yOffset) or 5) + ((a and a.h) or 26) + 2
		end
	end
	f.mark:ClearAllPoints()
	f.mark:SetPoint("BOTTOM", f.hb, "TOP", 0, mY)

	-- Height of the DoT tint region for an enemy player = everything except the class strip along the
	-- top (see ns.TINT_CLASS_STRIP). Derived from the CONFIGURED height, not hb:GetHeight() -- hb sizes
	-- itself via SetAllPoints, so its height is unresolved until a layout pass and reads 0 on the first
	-- frame. Stashed on the frame so Tint.lua uses this exact number instead of deriving its own.
	f.splitY = math.max(1, (cfg.height or 12) - ns.TINT_CLASS_STRIP)
end

---------------------------------------------------------------------------------------------------
-- Widget creation
---------------------------------------------------------------------------------------------------
local function CastOnUpdate(self)
	local d = self.duration
	if d and d.GetRemainingDuration then
		local t = d:GetRemainingDuration()
		if not Guards.IsSecret(t) and t ~= nil then
			self.time:SetText(string.format("%.1f", t))
		else
			self.time:SetText("")
		end
	end
end

local function CreatePlateFrame(plate)
	local f = CreateFrame("Frame", nil, plate)
	f:SetSize(120, 12)
	f.classColor = B_NORMAL

	local hb = CreateFrame("StatusBar", nil, f)
	hb:SetAllPoints(f)
	hb:SetStatusBarTexture(HEALTHBAR_TEXTURE)
	hb:SetMinMaxValues(0, 1)
	hb:SetValue(1)
	f.hb = hb

	local bg = hb:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(hb)
	bg:SetColorTexture(0, 0, 0, 0.5)

	-- Important-cast recolour layer. This used to be a vertex color on the fill itself, which the
	-- DoT tints (drawn on aura buttons ABOVE the fill) would silently paint over -- so it moved up
	-- here as its own texture, driven by SetAlphaFromBoolean exactly like cb.noInterrupt below.
	-- It tracks the FILL, not the bar, so it recolours the same region the vertex color used to.
	local top = CreateFrame("Frame", nil, hb)
	top:SetFrameLevel(hb:GetFrameLevel() + ns.LEVEL_IMPORTANT)
	top:SetAllPoints(hb:GetStatusBarTexture())
	local impTint = top:CreateTexture(nil, "ARTWORK")
	impTint:SetAllPoints(top)
	impTint:SetAlpha(0)
	f.impTint = impTint

	-- Text layer: name, health %, elite icon. On its own frame above the tints so a full-bar tint
	-- cannot bury them. Anchors still point at hb, which is this frame's parent.
	local fg = CreateFrame("Frame", nil, hb)
	fg:SetFrameLevel(hb:GetFrameLevel() + ns.LEVEL_TEXT)
	fg:SetAllPoints(hb)
	f.fg = fg

	local border = CreateFrame("Frame", nil, hb, "BackdropTemplate")
	border:SetPoint("TOPLEFT", hb, "TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", 1, -1)
	border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	border:SetBackdropBorderColor(0, 0, 0, 1)
	f.border = border

	-- Everything drawn ON the bar gets a black drop shadow on top of its outline. The outline alone
	-- was enough while the bar was threat red, but a class-coloured bar can be Rogue yellow
	-- (1.00/0.96/0.41) or Priest white (1/1/1), and white text on that is gone. Shadow rather than
	-- THICKOUTLINE on purpose: thick outlines turn CJK glyphs to mush at nameplate font sizes.
	local function Legible(fs)
		fs:SetShadowColor(0, 0, 0, 1)
		fs:SetShadowOffset(1, -1)
		return fs
	end

	local name = Legible(fg:CreateFontString(nil, "OVERLAY"))
	name:SetFont(FONT, 9, "OUTLINE")
	name:SetPoint("BOTTOMLEFT", hb, "TOPLEFT", 1, 3)   -- left-aligned above the bar
	name:SetJustifyH("LEFT")
	f.name = name


	-- percent (inside bar, right): a number + a separate static "%" sign just to its right. The "%"
	-- is separate because the percent value can come back secret (cannot concat "%" onto a secret).
	local hpPctSign = Legible(fg:CreateFontString(nil, "OVERLAY"))
	hpPctSign:SetFont(FONT, 8, "OUTLINE")
	hpPctSign:SetPoint("RIGHT", hb, "RIGHT", -2, 0)
	hpPctSign:SetText("%")
	f.hpPctSign = hpPctSign

	local hpPct = Legible(fg:CreateFontString(nil, "OVERLAY"))
	hpPct:SetFont(FONT, 8, "OUTLINE")
	hpPct:SetPoint("RIGHT", hpPctSign, "LEFT", 0, 0)
	hpPct:SetJustifyH("RIGHT")
	f.hpPct = hpPct

	-- level (above bar, right -- mirrors the name top-left; keeps below-bar clear for the cast bar)
	local level = f:CreateFontString(nil, "OVERLAY")
	level:SetFont(FONT, 8, "OUTLINE")
	level:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", -1, 3)
	level:SetJustifyH("RIGHT")
	f.level = level

	local mark = f:CreateTexture(nil, "OVERLAY")   -- raid target icon, centered directly above the bar
	mark:SetSize(24, 24)
	mark:SetPoint("BOTTOM", hb, "TOP", 0, 0)       -- name (on the fg layer) draws above it
	mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")  -- pre-set; SetRaidTargetIconTexture sets only the texcoord (mirrors Plater)
	mark:Hide()
	f.mark = mark

	-- elite / rare classification icon, INSIDE the bar + left-aligned (on fg so it sits above the tints)
	local elite = fg:CreateTexture(nil, "OVERLAY")
	elite:SetPoint("LEFT", hb, "LEFT", 1, 0)
	elite:Hide()
	f.elite = elite

	-- current-target indicator: two white triangles flanking the bar (left points right, right points
	-- left), shown only on the target plate; size tracks the bar height. One texture -- the right one
	-- is mirrored via SetTexCoord. Beside the bar (clear of cast bar / name / marker), so nothing else.
	local arrowL = f:CreateTexture(nil, "OVERLAY")
	arrowL:SetPoint("RIGHT", hb, "LEFT", -2, 0)
	arrowL:SetTexture(ARROW)
	arrowL:Hide()
	f.arrowL = arrowL
	local arrowR = f:CreateTexture(nil, "OVERLAY")
	arrowR:SetPoint("LEFT", hb, "RIGHT", 2, 0)
	arrowR:SetTexture(ARROW)
	arrowR:SetTexCoord(1, 0, 0, 1)   -- mirror horizontally -> points left
	arrowR:Hide()
	f.arrowR = arrowR

	-- cast bar = a container Frame with TWO overlapping fills: forward (L->R) and reverse (R->L).
	-- Only one shows per cast, picked by SetAlphaFromBoolean(important) -- a secret-safe way to flip
	-- direction even when 'important' is secret (instances), since SetReverseFill is not secret-safe.
	local cb = CreateFrame("Frame", nil, f)
	cb:SetSize(120, 9)
	cb:SetPoint("TOP", hb, "BOTTOM", 0, -3)
	cb:Hide()
	local baseLvl = cb:GetFrameLevel()

	local cbbg = cb:CreateTexture(nil, "BACKGROUND")
	cbbg:SetAllPoints(cb)
	cbbg:SetColorTexture(0, 0, 0, 0.6)

	local fillL = CreateFrame("StatusBar", nil, cb)   -- forward fill (left -> right)
	fillL:SetAllPoints(cb)
	fillL:SetFrameLevel(baseLvl + 1)
	fillL:SetStatusBarTexture(HEALTHBAR_TEXTURE)
	cb.fillL = fillL

	local fillR = CreateFrame("StatusBar", nil, cb)   -- reverse fill (right -> left)
	fillR:SetAllPoints(cb)
	fillR:SetFrameLevel(baseLvl + 1)
	fillR:SetStatusBarTexture(HEALTHBAR_TEXTURE)
	fillR:SetReverseFill(true)
	cb.fillR = fillR

	-- thin border above the fills (stays black; just delineates the bar)
	local cborder = CreateFrame("Frame", nil, cb, "BackdropTemplate")
	cborder:SetFrameLevel(baseLvl + 2)
	cborder:SetPoint("TOPLEFT", cb, "TOPLEFT", -1, 1)
	cborder:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", 1, -1)
	cborder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	cborder:SetBackdropBorderColor(0, 0, 0, 1)
	cb.border = cborder

	-- overlay above the fills/border for icon + text + time + target + shield
	local ov = CreateFrame("Frame", nil, cb)
	ov:SetFrameLevel(baseLvl + 3)
	ov:SetAllPoints(cb)

	-- uninterruptible ("steel") cast: a tiled gray diagonal-stripe overlay over the fill, BELOW the
	-- cast text. Visibility driven by SetAlphaFromBoolean(notInterruptible) -- secret-safe.
	local noint = ov:CreateTexture(nil, "ARTWORK", nil, 1)
	noint:SetAllPoints(cb)
	noint:SetTexture(STRIPE, "REPEAT", "REPEAT")
	noint:SetAlpha(0)
	cb.noInterrupt = noint

	local cicon = ov:CreateTexture(nil, "ARTWORK")
	cicon:SetSize(11, 11)
	cicon:SetPoint("RIGHT", cb, "LEFT", -2, 0)
	cicon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	cb.icon = cicon

	local ctext = ov:CreateFontString(nil, "OVERLAY")
	ctext:SetFont(FONT, 8, "OUTLINE")
	ctext:SetPoint("LEFT", cb, "LEFT", 2, 0)
	ctext:SetPoint("RIGHT", cb, "RIGHT", -26, 0)
	ctext:SetJustifyH("LEFT")
	cb.text = ctext

	local ctime = ov:CreateFontString(nil, "OVERLAY")
	ctime:SetFont(FONT, 8, "OUTLINE")
	ctime:SetPoint("RIGHT", cb, "RIGHT", -2, 0)
	ctime:SetJustifyH("RIGHT")
	cb.time = ctime

	local shield = ov:CreateTexture(nil, "OVERLAY")
	shield:SetSize(16, 16)
	shield:SetPoint("CENTER", cb, "RIGHT", 0, 0)
	shield:SetAtlas("nameplates-InterruptShield")
	shield:SetAlpha(0)
	cb.shield = shield

	cb:SetScript("OnUpdate", CastOnUpdate)
	f.castbar = cb

	-- Cast-target bar (Midnight gives only NAME + CLASS for a spell target -- no unit token, no
	-- health). A solid class-colored bar with the target name centered inside, right-aligned just
	-- below the cast bar. Child of cb so it auto-hides when the cast bar hides.
	local tgt = CreateFrame("Frame", nil, cb)
	tgt:SetSize(120, 9)
	tgt:SetPoint("TOPRIGHT", cb, "BOTTOMRIGHT", 0, -2)
	tgt:Hide()
	local tgtfill = tgt:CreateTexture(nil, "ARTWORK")
	tgtfill:SetAllPoints(tgt)
	tgtfill:SetColorTexture(0.6, 0.6, 0.6, 1)
	tgt.fill = tgtfill
	local tgtborder = CreateFrame("Frame", nil, tgt, "BackdropTemplate")
	tgtborder:SetPoint("TOPLEFT", tgt, "TOPLEFT", -1, 1)
	tgtborder:SetPoint("BOTTOMRIGHT", tgt, "BOTTOMRIGHT", 1, -1)
	tgtborder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	tgtborder:SetBackdropBorderColor(0, 0, 0, 1)
	local tgttext = tgt:CreateFontString(nil, "OVERLAY")
	tgttext:SetFont(FONT, 8, "OUTLINE")
	tgttext:SetPoint("CENTER", tgt, "CENTER", 0, 0)
	tgttext:SetJustifyH("CENTER")
	tgttext:SetTextColor(1, 1, 1)
	tgt.text = tgttext
	f.castTarget = tgt

	if ns.Auras then ns.Auras.Create(f) end

	f.plate = plate   -- the colour path needs it to reach Blizzard's own health bar
	plate.dnp = f
	return f
end

---------------------------------------------------------------------------------------------------
-- Color
---------------------------------------------------------------------------------------------------
local function UpdateHealth(f, unit)
	local h = UnitHealth(unit)
	local hmax = UnitHealthMax(unit)
	f.hb:SetMinMaxValues(0, hmax)   -- secret-safe sink
	f.hb:SetValue(h)                -- secret-safe sink

	-- percent (right): number only (the "%" is the separate static sign). Direct math when readable;
	-- else the integer step curve (renders with no decimals even when its result is secret).
	if not Guards.IsSecret(h) and not Guards.IsSecret(hmax) and hmax and hmax > 0 then
		f.hpPct:SetText(("%.0f"):format(100 * h / hmax))
		f.hpPctSign:Show()
	elseif SCALE100 and UnitHealthPercent then
		local p = UnitHealthPercent(unit, true, SCALE100)
		if Guards.IsSecret(p) then
			f.hpPct:SetText(p); f.hpPctSign:Show()             -- integer step curve, shown via sink
		elseif p == nil then
			f.hpPct:SetText(""); f.hpPctSign:Hide()
		else
			f.hpPct:SetText(("%.0f"):format(p)); f.hpPctSign:Show()
		end
	else
		f.hpPct:SetText(""); f.hpPctSign:Hide()
	end
end

local function UpdateLevel(f, unit)
	if f.group == FRIENDLY_NPC then
		f.level:SetText("")   -- NPCs do not show level
		return
	end
	local lvl = UnitLevel(unit)
	if Guards.IsSecret(lvl) then
		f.level:SetText(lvl)            -- sink
	elseif lvl and lvl > 0 then
		f.level:SetText(lvl)
	else
		f.level:SetText("??")           -- -1 = boss / ?? level
	end
end

local function ThreatColor(unit)
	-- A spec whose tint ruleset covers the bar (Shadow) opts out of threat colouring entirely: with
	-- a DoT on nearly everything in an instance the red/blue would be painted over almost all the
	-- time, so the bar may as well hold still at "normal red" underneath. See Tint.lua flatThreat.
	if ns.Tint and ns.Tint.OverridesThreat() then return CN() end
	local s = UnitThreatSituation("player", unit)
	if Guards.IsSecret(s) or s == nil then
		return CN()
	end
	if ns.isTank then
		return (s == 3) and CN() or CW()
	else
		return (s == 0) and CN() or CW()
	end
end

local function ClassColor(unit)
	local token = UnitClassBase(unit)
	if not Guards.IsSecret(token) and token ~= nil then
		local c = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(token))
			or RAID_CLASS_COLORS[token]
		if c then return c end
	end
end

-- Class colour for an enemy player whose class we are NOT allowed to read (battleground / arena:
-- UnitClassBase is SecretWhenUnitIdentityRestricted). Blizzard's own nameplate paints that bar with
-- plain `UnitClass` + `RAID_CLASS_COLORS` in UNTAINTED code, which needs no secret handling at all --
-- so the class colour is already on screen, under the bar we hide with SetAlpha(0). Measured
-- 2026-08-17 in a battleground: the colour is still being updated while we hold it at alpha 0, and
-- reading it back yields a SECRET.
--
-- A secret is fine here. We receive it, store it, and hand it straight to SetVertexColor -- never
-- compare it, index with it, or do arithmetic on it. Same shape as SetValue(secretHealth) and
-- SetRaidTargetIconTexture(secretIndex) elsewhere in this file.
local function BlizzardBarColor(f)
	local uf = f.plate and f.plate.UnitFrame
	local bar = uf and uf.healthBar
	if not (bar and bar.GetStatusBarColor) then return nil end
	local ok, r, g, b = pcall(bar.GetStatusBarColor, bar)
	if not ok then return nil end
	-- Secret check before the nil compare, always.
	if Guards.IsSecret(r) then return { r = r, g = g, b = b, secret = true } end
	if r == nil then return nil end
	return { r = r, g = g, b = b }
end

-- One-shot report if SetVertexColor turns out to refuse these particular secrets. Not silent: a
-- quiet fall back to red is indistinguishable from "this character has no class colour", and that
-- would read as the feature simply not working.
local secretColorRefused = false
local function ReportSecretColorRefused()
	if secretColorRefused then return end
	secretColorRefused = true
	print("|cff66ccffDodoNameplate|r: SetVertexColor refused a secret class colour -- "
		.. "enemy-player bars fall back to red in restricted PvP. Please report this.")
end

local function ReactionColor(unit)
	local r, g, b = UnitSelectionColor(unit)
	if not Guards.IsSecret(r) and r ~= nil then return { r = r, g = g, b = b } end
end

-- Neutral creatures: yellow until engaged (on your threat table), then the hostile threat colors.
local function HostileColor(unit)
	local reaction = UnitReaction("player", unit)  -- non-secret; 4 = neutral
	if not Guards.IsSecret(reaction) and reaction ~= nil and reaction == 4 then
		local s = UnitThreatSituation("player", unit)
		if Guards.IsSecret(s) or s == nil then
			return ReactionColor(unit) or NEUTRAL_YELLOW   -- not engaged -> yellow
		end
	end
	return ThreatColor(unit)
end

local function GroupColor(group, unit, f)
	if group == HOSTILE then
		return HostileColor(unit)
	elseif group == ENEMY_PLAYER then
		-- Borrowing Blizzard's bar is scoped to this group on purpose. For a creature it would hand
		-- back whatever THEY decided (their threat/reaction tint), not a class colour.
		return ClassColor(unit) or BlizzardBarColor(f) or ReactionColor(unit) or CN()
	elseif group == PARTY or group == FRIENDLY then
		return ClassColor(unit) or ReactionColor(unit) or CN()
	else
		return ReactionColor(unit) or { r = 0.2, g = 0.8, b = 0.2 }
	end
end

local IMP_HP_DEFAULT = { r = 1, g = 1, b = 1 }   -- fallback important-cast health color (white)

-- Health bar color = group/threat color, and nothing else. The important-cast recolor is NOT folded
-- in here any more: it used to be a vertex color on the fill, which the DoT tints draw over, so it
-- moved to f.impTint (StartCast) -- one implementation, one place, above the tints.
local function ColorBar(f, unit)
	local tex = f.hb:GetStatusBarTexture()
	if not (tex and f.group) then return end
	local c = GroupColor(f.group, unit, f)
	if c.secret then
		-- Guarded because this is the one step nothing has verified: SetVertexColor demonstrably eats
		-- the SingleColorValue that EvaluateColorValueFromBoolean returns, but a raw secret number
		-- out of GetStatusBarColor is not the same type. Unguarded it would throw once per plate
		-- update for every enemy in a battleground.
		if pcall(tex.SetVertexColor, tex, c.r, c.g, c.b) then return end
		ReportSecretColorRefused()
		local n = CN()
		tex:SetVertexColor(n.r, n.g, n.b)
		return
	end
	tex:SetVertexColor(c.r, c.g, c.b)
end

---------------------------------------------------------------------------------------------------
-- Border state (target / focus / classification) + elite icon
---------------------------------------------------------------------------------------------------
local function ApplyHighlight(f)
	local c = f.isTarget and B_TARGET or (f.isFocus and B_FOCUS or f.classColor)
	f.border:SetBackdropBorderColor(c[1], c[2], c[3], 1)
	f:SetScale(f.isTarget and ((ns.db and ns.db.targetScale) or DEF_TSCALE) or 1.0)
	if f.arrowL then f.arrowL:SetShown(f.isTarget); f.arrowR:SetShown(f.isTarget) end
end

local function UpdateClassification(f, unit)
	local cls = UnitClassification(unit)
	if Guards.IsSecret(cls) then cls = "normal" end

	local atlas
	if cls == "worldboss" or cls == "elite" or cls == "rareelite" then
		f.classColor = B_ELITE
		atlas = "nameplates-icon-elite-gold"
	elseif cls == "rare" then
		f.classColor = B_RARE
		atlas = "nameplates-icon-elite-silver"
	else
		f.classColor = B_NORMAL
	end

	if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		f.elite:SetAtlas(atlas)
		f.elite:Show()
	else
		f.elite:Hide()
	end
	AnchorName(f)   -- elite visibility decides the mob-name left anchor (in-bar, after the icon)

	ApplyHighlight(f)
end

---------------------------------------------------------------------------------------------------
-- States
---------------------------------------------------------------------------------------------------
-- GetRaidTargetIndex is SECRET in instances, but SetRaidTargetIconTexture is a secret-safe SINK:
-- pass the (maybe-secret) index straight in -- HasValue detects secrecy before checking nil.
local function UpdateMark(f, unit)
	local idx = GetRaidTargetIndex(unit)
	if HasValue(idx) then
		SetRaidTargetIconTexture(f.mark, idx)
		f.mark:Show()
	else
		f.mark:Hide()
	end
end

-- Bar color by importance. `important` may be SECRET -> pick via EvaluateColorValueFromBoolean
-- (never compared in Lua).
local function TintBar(bar, important, imp, nrm, E)
	local tex = bar:GetStatusBarTexture()
	if not tex then return end
	if E then
		tex:SetVertexColor(E(important, imp.r, nrm.r), E(important, imp.g, nrm.g), E(important, imp.b, nrm.b))
	elseif not Guards.IsSecret(important) and important then
		tex:SetVertexColor(imp.r, imp.g, imp.b)
	else
		tex:SetVertexColor(nrm.r, nrm.g, nrm.b)
	end
end

local function ApplyCastColor(cb, important, cfg)
	local imp = (cfg and cfg.castImportantColor) or CAST_COLOR_IMPORTANT
	local nrm = (cfg and cfg.castColor) or CAST_COLOR_NORMAL
	local E = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
	TintBar(cb.fillL, important, imp, nrm, E)
	TintBar(cb.fillR, important, imp, nrm, E)
end

-- Cast-target bar: Midnight exposes only the spell target's NAME + CLASS (no unit token -> no health).
-- Color = the target's class color when it is a player, else the configurable fallback. Name centered
-- inside (SetText is a sink, safe even if the name is secret). Mirrors Plater's Midnight cast-target.
local function UpdateCastTarget(f, unit, cfg)
	local tgt = f.castTarget
	if not (cfg and cfg.castTargetShow) then tgt:Hide(); return end
	local tname = UnitSpellTargetName and UnitSpellTargetName(unit)
	if not HasValue(tname) then tgt:Hide(); return end
	local col = cfg.castTargetFallbackColor or { r = 0.6, g = 0.6, b = 0.6 }
	local tclass = UnitSpellTargetClass and UnitSpellTargetClass(unit)
	if not Guards.IsSecret(tclass) and tclass ~= nil then
		local c = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(tclass))
			or RAID_CLASS_COLORS[tclass]
		if c then col = c end
	end
	tgt.fill:SetColorTexture(col.r, col.g, col.b, 1)
	tgt.text:SetText(tname)   -- sink
	tgt:Show()
end

local function StartCast(f, unit, channeled)
	local cb = f.castbar
	local cfg = f.group and ns.db and ns.db.groups[f.group]
	f.impTint:SetAlpha(0)   -- cleared on entry so the early returns below cannot leave it lit
	if not cfg or cfg.showCast == false then cb:Hide(); return end

	local name, texture, notInterruptible, spellID
	if channeled then
		local n, _, tex, _, _, _, ni, sid = UnitChannelInfo(unit)
		name, texture, notInterruptible, spellID = n, tex, ni, sid
	else
		local n, _, tex, _, _, _, _, ni, sid = UnitCastingInfo(unit)
		name, texture, notInterruptible, spellID = n, tex, ni, sid
	end
	if not HasValue(name) then cb:Hide(); return end

	-- Blizzard's "important / golden" cast flag. May be secret in instances -> only secret-safe sinks.
	local important
	if C_Spell and C_Spell.IsSpellImportant then
		important = C_Spell.IsSpellImportant(spellID)
	end

	cb.icon:SetTexture(texture)
	cb.text:SetText(name)
	cb.duration = channeled and UnitChannelDuration(unit) or UnitCastingDuration(unit)
	local dir = channeled and CHANNEL_DIR or CAST_DIR
	if cb.duration and cb.fillL.SetTimerDuration and CAST_INTERP then
		cb.fillL:SetTimerDuration(cb.duration, CAST_INTERP, dir)
		cb.fillR:SetTimerDuration(cb.duration, CAST_INTERP, dir)
	end

	-- Health bar recolor while an important spell is casting: a texture ABOVE the DoT tints, flipped
	-- by SetAlphaFromBoolean so it works even when `important` is secret (instances). Colour comes
	-- from the group's own importantHpColor -- the same setting the old vertex-color fold read.
	if cfg.importantHpRecolor then
		local sp = cfg.importantHpColor or IMP_HP_DEFAULT
		f.impTint:SetColorTexture(sp.r, sp.g, sp.b, 1)
		f.impTint:SetAlphaFromBoolean(important, 1, 0)
	end
	ApplyCastColor(cb, important, cfg)
	-- direction (secret-safe): show the reverse (R->L) bar for important casts, the forward (L->R) bar
	-- otherwise -- toggled via SetAlphaFromBoolean so it works even when 'important' is secret.
	cb.fillL:SetAlphaFromBoolean(important, 0, 1)
	cb.fillR:SetAlphaFromBoolean(important, 1, 0)
	cb.shield:SetAlphaFromBoolean(notInterruptible, 1, 0)
	cb.noInterrupt:SetAlphaFromBoolean(notInterruptible, 1, 0)   -- striped overlay on uninterruptible casts
	cb:Show()
	UpdateCastTarget(f, unit, cfg)
end

local function StopCast(f)
	local cb = f.castbar
	cb.duration = nil
	cb:Hide()
	f.impTint:SetAlpha(0)   -- drop the important-cast recolor
end

local function CheckCast(f, unit)
	if HasValue(UnitCastingInfo(unit)) then
		StartCast(f, unit, false)
	elseif HasValue(UnitChannelInfo(unit)) then
		StartCast(f, unit, true)
	else
		StopCast(f)
	end
end

local function IsTargetPlate(plate) return plate == C_NamePlate.GetNamePlateForUnit("target") end
local function IsFocusPlate(plate)  return plate == C_NamePlate.GetNamePlateForUnit("focus")  end

---------------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------------
function Style.Apply(plate, unit, group)
	-- Never touch a forbidden/protected plate (friendly party/raid plates in PvE instances): building
	-- a child frame or SetAlpha on it taints. Bail -> Blizzard's own plate stays. See GOTCHAS.md S2.
	if not plate or not ns.db or plate:IsForbidden() then return end
	local uf = plate.UnitFrame
	local f = plate.dnp or CreatePlateFrame(plate)
	f.unit = unit
	f.impTint:SetAlpha(0)   -- reset so a recycled plate does not inherit the previous unit's recolor

	if ns.db.overlays.hideCritter and ns.IsCritter(unit) then
		if uf then uf.dnpHide = true; HookUnitFrame(uf); uf:SetAlpha(0) end
		if ns.Auras then ns.Auras.Clear(f) end
		if ns.Tint then ns.Tint.Clear(f) end
		f:Hide()
		return
	end

	local cfg = ns.db.groups[group]
	if cfg and cfg.enabled then
		f.group = group
		if uf then
			uf.dnpHide = true
			HookUnitFrame(uf)
			uf:SetAlpha(0)
		end
		f:ClearAllPoints()
		f:SetPoint("CENTER", uf or plate, "CENTER")
		LayoutPlate(f, cfg)
		UpdateHealth(f, unit)
		ColorBar(f, unit)
		f.name:SetText(UnitName(unit))   -- secret-safe sink
		UpdateLevel(f, unit)
		UpdateMark(f, unit)
		f.isTarget = IsTargetPlate(plate)
		f.isFocus = IsFocusPlate(plate)
		UpdateClassification(f, unit)    -- sets classColor + elite icon, then ApplyHighlight
		local tapped = ns.db.overlays.dimTapped and ns.IsTapped(unit)
		f:SetAlpha(tapped and 0.5 or 1)
		f:Show()
		CheckCast(f, unit)
		local enemy = IsEnemyPlate(f.group)
		if ns.Auras then
			if enemy then ns.Auras.Attach(f, unit) else ns.Auras.Clear(f) end
		end
		if ns.Tint then
			if enemy then ns.Tint.Attach(f, unit) else ns.Tint.Clear(f) end
		end
	else
		if uf then uf.dnpHide = false; uf:SetAlpha(1) end
		if ns.Auras then ns.Auras.Clear(f) end
		if ns.Tint then ns.Tint.Clear(f) end
		f:Hide()
	end
end

function Style.Clear(plate)
	if not plate then return end
	if plate.dnp then
		if ns.Auras then ns.Auras.Clear(plate.dnp) end
		if ns.Tint then ns.Tint.Clear(plate.dnp) end
		plate.dnp:Hide()
		plate.dnp.impTint:SetAlpha(0)
	end
	local uf = plate.UnitFrame
	if uf then uf.dnpHide = false; uf:SetAlpha(1) end
end

function Style.Health(plate, unit)
	local f = plate and plate.dnp
	if f and f:IsShown() then UpdateHealth(f, unit) end
end

function Style.Auras(plate, unit)
	local f = plate and plate.dnp
	if f and f:IsShown() and IsEnemyPlate(f.group) and ns.Auras then
		ns.Auras.Attach(f, unit)
	end
end

-- Re-evaluate the DoT tint for one plate (spec change; tapped state flips arrive via UNIT_FLAGS,
-- which already re-runs the whole of Style.Apply).
function Style.Tint(plate, unit)
	local f = plate and plate.dnp
	if not (f and ns.Tint) then return end
	if f:IsShown() and IsEnemyPlate(f.group) then
		ns.Tint.Attach(f, unit)
	else
		ns.Tint.Clear(f)
	end
end

-- UNIT_NAME_UPDATE: the name may be UNKNOWNOBJECT at add time and resolve a moment later.
function Style.UpdateName(plate, unit)
	local f = plate and plate.dnp
	if f and f:IsShown() then f.name:SetText(UnitName(unit)) end
end

-- UNIT_LEVEL: level may not be known at add time.
function Style.UpdateLevel(plate, unit)
	local f = plate and plate.dnp
	if f and f:IsShown() then UpdateLevel(f, unit) end
end

function Style.Recolor(plate, unit)
	local f = plate and plate.dnp
	if f and f:IsShown() then ColorBar(f, unit) end
end

function Style.SetTarget(plate, on)
	local f = plate and plate.dnp
	if f and f:IsShown() then f.isTarget = on; ApplyHighlight(f) end
end

function Style.SetFocus(plate, on)
	local f = plate and plate.dnp
	if f and f:IsShown() then f.isFocus = on; ApplyHighlight(f) end
end

function Style.Mark(plate, unit)
	local f = plate and plate.dnp
	if f and f:IsShown() then UpdateMark(f, unit) end
end

function Style.CastStart(plate, unit, channeled)
	local f = plate and plate.dnp
	if f and f:IsShown() then StartCast(f, unit, channeled) end
end

function Style.CastStop(plate)
	local f = plate and plate.dnp
	if f then StopCast(f) end
end

function Style.Shield(plate, notInterruptible)
	local f = plate and plate.dnp
	if f and f.castbar:IsShown() then f.castbar.shield:SetAlphaFromBoolean(notInterruptible, 1, 0) end
end

function Style.RefreshAll()
	for unit, entry in pairs(ns.plates) do
		if entry.plate then Style.Apply(entry.plate, unit, entry.group) end
	end
end
