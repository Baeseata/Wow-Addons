-- DodoNameplate :: Locale.lua
-- Options-panel localization ONLY (not in-game plate text). ns.L resolves to the active language
-- table; ns.ApplyLocale() picks it from ns.db.locale ("auto" follows the client) at PLAYER_LOGIN.
-- zhCN falls back to enUS for any missing key (metatable), so enUS is the complete key set.

local ADDON, ns = ...

local enUS = {
	-- General page
	note_subpages    = "Per-group styling lives in the sub-pages on the left. /dnp opens this.",
	hdr_threat       = "Threat colors (hostile bar)",
	col_normal       = "Normal (right for your role)",
	col_warn         = "Warning (wrong for your role)",
	hdr_overlays     = "Overlays",
	chk_dimTapped    = "Dim tapped creatures",
	chk_hideCritter  = "Hide critters",
	hdr_misc         = "Misc",
	sld_targetScale  = "Target scale (%)",
	sld_markSize     = "Raid marker size",
	hdr_language     = "Language (options panel)",
	opt_english      = "English",
	opt_chinese      = "Chinese",
	note_reload      = "Reload UI to apply (/reload).",
	-- Group pages
	chk_enable       = "Enable (DodoNameplate styles this group)",
	sld_hpWidth      = "Healthbar width",
	sld_hpHeight     = "Healthbar height",
	chk_showName     = "Show name",
	sld_nameSize     = "Name size",
	sld_levelSize    = "Level size",
	sld_pctSize      = "Percent size",
	hdr_castbar      = "Cast bar",
	chk_showCast     = "Show cast bar",
	sld_castHeight   = "Cast bar height",
	sld_castTextSize = "Cast text size",
	col_castColor    = "Cast bar color",
	col_castImportant= "Important cast color",
	hdr_castTarget   = "Cast target bar",
	chk_castTargetShow     = "Show cast target bar",
	sld_castTargetHeight   = "Target bar height",
	sld_castTargetWidth    = "Target bar width",
	sld_castTargetTextSize = "Target text size",
	col_castTargetFallback = "Cast target bar color",
	hdr_impHp        = "Important cast -> health bar",
	chk_impHpRecolor = "Important cast recolors health bar",
	col_impHpColor   = "Recolor color",
	-- Sub-page (category tree) names
	page_hostile     = "Hostile creature",
	page_enemyPlayer = "Enemy Player",
	page_friendlyNpc = "Friendly NPC",
	page_party       = "Party / Raid",
	page_other       = "Other Players",
	-- Auras sub-page
	page_auras       = "Auras",
	note_auras       = "Secure 12.1 aura categories on enemy plates (mobs + enemy players).",
	hdr_auraCats     = "Show categories",
	chk_auraEnable   = "Enable auras",
	chk_auraMine     = "Personal debuffs",
	chk_auraCC       = "Shared crowd control",
	chk_auraImportant = "Priority debuffs",
	chk_auraBuffs    = "Enemy buffs",
	chk_auraPurge    = "Purgeable buffs (if you can purge)",
	chk_auraDefensive = "Defensive buffs (enemy players)",
	hdr_auraLayout   = "Layout",
	sld_auraCount    = "Max icons",
	sld_auraW        = "Icon width",
	sld_auraH        = "Icon height",
	chk_auraTimer    = "Show countdown number",
}

local zhCN = {
	note_subpages    = "每组的样式在左侧子页里设置。/dnp 打开本面板。",
	hdr_threat       = "威胁颜色(敌对血条)",
	col_normal       = "正常(符合你的职责)",
	col_warn         = "警告(不符合你的职责)",
	hdr_overlays     = "覆盖层",
	chk_dimTapped    = "变暗被夺取的生物",
	chk_hideCritter  = "隐藏小动物",
	hdr_misc         = "杂项",
	sld_targetScale  = "目标缩放(%)",
	sld_markSize     = "队伍标记大小",
	hdr_language     = "语言(设置面板)",
	opt_english      = "English",
	opt_chinese      = "中文",
	note_reload      = "重载界面后生效(/reload)。",
	chk_enable       = "启用(DodoNameplate 接管该组)",
	sld_hpWidth      = "血条宽度",
	sld_hpHeight     = "血条高度",
	chk_showName     = "显示名字",
	sld_nameSize     = "名字大小",
	sld_levelSize    = "等级大小",
	sld_pctSize      = "百分比大小",
	hdr_castbar      = "施法条",
	chk_showCast     = "显示施法条",
	sld_castHeight   = "施法条高度",
	sld_castTextSize = "施法条文字大小",
	col_castColor    = "施法条颜色",
	col_castImportant= "重要施法颜色",
	hdr_castTarget   = "施法目标条",
	chk_castTargetShow     = "显示施法目标条",
	sld_castTargetHeight   = "目标条高度",
	sld_castTargetWidth    = "目标条宽度",
	sld_castTargetTextSize = "目标条文字大小",
	col_castTargetFallback = "施法目标条颜色",
	hdr_impHp        = "重要施法 -> 血条",
	chk_impHpRecolor = "重要施法时血条变色",
	col_impHpColor   = "变色颜色",
	page_hostile     = "敌对生物",
	page_enemyPlayer = "敌方玩家",
	page_friendlyNpc = "友好NPC",
	page_party       = "小队 / 团队",
	page_other       = "其他玩家",
	page_auras       = "光环",
	note_auras       = "敌方血条上的 12.1 安全光环分类（敌怪 + 敌方玩家）。",
	hdr_auraCats     = "显示分类",
	chk_auraEnable   = "启用光环",
	chk_auraMine     = "个人减益",
	chk_auraCC       = "共享控制",
	chk_auraImportant = "优先减益",
	chk_auraBuffs    = "敌方增益",
	chk_auraPurge    = "可净化增益(仅可净化职业)",
	chk_auraDefensive = "防御性增益(仅敌方玩家)",
	hdr_auraLayout   = "布局",
	sld_auraCount    = "最大数量",
	sld_auraW        = "图标宽度",
	sld_auraH        = "图标高度",
	chk_auraTimer    = "显示倒计时数字",
}

local locales = { enUS = enUS, zhCN = zhCN }

-- Resolve ns.L from ns.db.locale; "auto"/unknown follows the client locale. Called at PLAYER_LOGIN
-- (after ns.db is ready) and after a language change + /reload.
function ns.ApplyLocale()
	local loc = ns.db and ns.db.locale
	if loc ~= "enUS" and loc ~= "zhCN" then
		local g = GetLocale()
		loc = (g == "zhCN" or g == "zhTW") and "zhCN" or "enUS"
	end
	ns.L = setmetatable(locales[loc] or enUS, { __index = enUS })
end
