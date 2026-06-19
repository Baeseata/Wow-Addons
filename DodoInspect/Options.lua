-- DodoInspect - Options.lua
-- Settings panel under Esc > Options > AddOns, plus a slash command
-- fallback. Options: overlay language, plus one independent toggle
-- per feature (equipment slot item levels, bag overlays, side panel)
-- so users can switch off whatever another addon already covers.

local ADDON_NAME, ns = ...

-- Addon version straight from the TOC, so the panel can never show a
-- number that drifts from the actual build.
local function GetVersion()
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return (meta and meta(ADDON_NAME, "Version")) or "?"
end

local function BuildLanguageOptions()
    local container = Settings.CreateControlTextContainer()
    for _, key in ipairs(ns.LocaleOrder) do
        container:Add(key, ns.Locales[key].name)
    end
    return container:GetData()
end

local function ApplyLocale(key)
    ns.SetLocale(key)
    ns.UpdateAllVisible()
end

-- One checkbox per feature toggle, stored in DodoInspectDB[dbKey]
-- (absent = on; see ns.IsEnabled). onChanged applies the new state
-- to anything currently on screen.
local function AddFeatureCheckbox(category, variable, dbKey, label, tooltip, onChanged)
    local setting = Settings.RegisterProxySetting(
        category,
        variable,
        Settings.VarType.Boolean,
        label,
        true,
        function() return ns.IsEnabled(dbKey) end,
        function(value)
            DodoInspectDB[dbKey] = value and true or false
            onChanged()
        end
    )
    Settings.CreateCheckbox(category, setting, tooltip)
end

-- Register the addon category in the modern Settings UI. Wrapped in
-- pcall so a Settings API change can never break the addon itself;
-- the slash command below keeps working either way.
function ns.RegisterOptions()
    if ns.OptionsRegistered then return end
    if not Settings or not Settings.RegisterVerticalLayoutCategory then return end

    local ok = pcall(function()
        local category, layout = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)

        -- Version banner at the top of the panel. Guarded so a future
        -- Settings internals change can't stop the options registering.
        if layout and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(
                "DodoInspect  v" .. GetVersion()))
        end

        local setting = Settings.RegisterProxySetting(
            category,
            "DODO_INSPECT_LANGUAGE",
            Settings.VarType.String,
            "Language",
            ns.DEFAULT_LOCALE,
            function() return ns.ActiveLocaleKey end,
            ApplyLocale
        )
        Settings.CreateDropdown(category, setting, BuildLanguageOptions,
            "Language used for the slot labels and the item type tags (junk, quest, consumables).")

        AddFeatureCheckbox(category,
            "DODO_INSPECT_EQUIPMENT_ILVL", "showEquipmentIlvl",
            "Equipment slot overlays",
            "Show item level (top-left), enchant (bottom-left) and gems (bottom-right) on each equipment slot of the character frame.",
            ns.UpdateEquipment)

        AddFeatureCheckbox(category,
            "DODO_INSPECT_INSPECT_ILVL", "showInspectIlvl",
            "Inspect window gear overlays",
            "Show item level (top-left), enchant (bottom-left) and gems (bottom-right) on each gear slot when inspecting another player.",
            ns.ApplyInspectEnabled)

        AddFeatureCheckbox(category,
            "DODO_INSPECT_BAG_OVERLAYS", "showBagOverlays",
            "Bag overlays",
            "Show item levels, slot labels, BOE and item type tags on the Blizzard bags.",
            ns.UpdateAllVisible)

        AddFeatureCheckbox(category,
            "DODO_INSPECT_SIDE_PANEL", "showSidePanel",
            "Gear summary side panel",
            "Show the gear list panel docked to the right of the character frame.",
            ns.ApplySidePanelEnabled)

        AddFeatureCheckbox(category,
            "DODO_INSPECT_DURABILITY", "showDurability",
            "Average durability",
            "Show the average durability of your equipped gear at the bottom of the character stats pane.",
            ns.UpdateDurability)

        AddFeatureCheckbox(category,
            "DODO_INSPECT_STAT_RATINGS", "showStatRatings",
            "Secondary stat ratings",
            "Append the rating value next to each secondary stat percentage in the character stats pane. Out of combat only -- secret in-combat values are never touched.",
            ns.RefreshStatRatings)

        AddFeatureCheckbox(category,
            "DODO_INSPECT_INSPECT_PANEL", "showInspectPanel",
            "Inspect window gear panel",
            "Show a simplified gear panel (stats, enchants, gems) docked to the right of the inspect window.",
            ns.ApplyInspectPanelEnabled)

        AddFeatureCheckbox(category,
            "DODO_INSPECT_TARGET_INFO", "showTargetInfo",
            "Target info",
            "Show item level, race, class, spec and hero talent above the target frame when targeting a player. Hostile players show what the game exposes: race and class, plus the spec inside battlegrounds and arenas.",
            ns.ApplyTargetInfoEnabled)

        Settings.RegisterAddOnCategory(category)
        ns.OptionsCategory = category
    end)

    ns.OptionsRegistered = ok or nil
end

-- Slash command fallback: /dins en | cn | fr | es
SLASH_DODOINSPECT1 = "/dins"
SlashCmdList["DODOINSPECT"] = function(msg)
    msg = (msg or ""):lower():gsub("%s+", "")
    if ns.Locales[msg] then
        ApplyLocale(msg)
        print("DodoInspect: language set to " .. ns.L.name)
    else
        print("DodoInspect: usage /dins en | cn | fr | es (current: " .. ns.ActiveLocaleKey .. ")")
    end
end
