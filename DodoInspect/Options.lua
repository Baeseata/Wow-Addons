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
    if ns.UpdateInspect then ns.UpdateInspect() end
    if ns.UpdateInspectPanel then ns.UpdateInspectPanel() end
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

-- One px-value slider per panel font size, stored in DodoInspectDB[dbKey]
-- (absent = the Config default). The value is in font pixels, bounded by
-- Config.PANEL_FONT_MIN/MAX; onChanged re-flows the affected panel live.
local function AddFontSlider(category, variable, dbKey, label, tooltip, onChanged)
    local default = ns.Config.PANEL_FONT_SIZE
    local setting = Settings.RegisterProxySetting(
        category,
        variable,
        Settings.VarType.Number,
        label,
        default,
        function()
            local db = DodoInspectDB
            return (db and tonumber(db[dbKey])) or default
        end,
        function(value)
            DodoInspectDB[dbKey] = math.floor((tonumber(value) or default) + 0.5)
            onChanged()
        end
    )
    local options = Settings.CreateSliderOptions(
        ns.Config.PANEL_FONT_MIN, ns.Config.PANEL_FONT_MAX, 1)
    if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
            function(value) return tostring(math.floor(value + 0.5)) .. " px" end)
    end
    Settings.CreateSlider(category, setting, options, tooltip)
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
            "DODO_INSPECT_BANK_OVERLAYS", "showBankOverlays",
            "Bank overlays",
            "Show the same overlays on the player bank and the guild bank. The guild bank shows item level, slot label and type tags (it does not expose the per-item data needed for BOE / equipment-set tags).",
            ns.ApplyBankEnabled)

        AddFeatureCheckbox(category,
            "DODO_INSPECT_SIDE_PANEL", "showSidePanel",
            "Gear summary side panel",
            "Show the gear list panel docked to the right of the character frame.",
            ns.ApplySidePanelEnabled)

        AddFontSlider(category,
            "DODO_INSPECT_SIDE_PANEL_FONT", "sidePanelFontSize",
            "Side panel font size",
            "Font size, in pixels, of the gear summary side panel on the character frame. The panel layout scales to match.",
            ns.RebuildSidePanel)

        -- Only per-spec entries marked current=true can resolve. The
        -- SavedVariables key remains stable as the current set changes.
        if ns.Config.STAT_PRIORITY_FEATURE_ENABLED == true then
            AddFeatureCheckbox(category,
                "DODO_INSPECT_STAT_PRIORITY", "showStatPriority",
                "Stat priority line",
                "Show a fixed PvE secondary-stat priority (e.g. Mastery = Crit > Haste > Versatility) at the top of the gear summary side panels. It follows hero talents and Raid/M+ when they differ. Hover for rough targets when available, provisional status, review date, sources and the disclaimer.",
                ns.ApplyStatPriorityEnabled)
        end

        -- These two are backed by season-dated data (Data/Loot.lua carries
        -- a build and date stamp) and shipped opt-in for that reason. Owner
        -- decision 2026-08-14: default them ON like every other display
        -- toggle -- keeping the loot table current is a job he does by
        -- hand, so the addon does not need to hedge on his behalf.
        if ns.Config.LOOT_FEATURE_ENABLED == true then
            AddFeatureCheckbox(category,
                "DODO_INSPECT_LOOT_SOURCE", "showLootSource",
                "Item source on tooltips",
                "Add a line to item tooltips showing where the item drops. Raid items name the boss and its position; Mythic+ items name the dungeon only. Covers the current season's raids and Mythic+ pool; other items are left alone.",
                function() end)

            AddFeatureCheckbox(category,
                "DODO_INSPECT_GEAR_PANEL", "showGearPanel",
                "Slot candidate panel",
                "Make the slot labels in the gear side panels clickable. Clicking one opens a list of this season's drops for that slot. Most slots are ranked by how well their secondary stats match the stat priority -- a stat-fit ranking, not a best-in-slot list, with tier bonuses and on-item effects flagged beside a row but never scored. Trinkets are the exception: most carry no secondary stats at all, so their order comes from SimulationCraft results published by bloodmallet.com, single target. Specs bloodmallet has not simulated say so in the panel instead of guessing.",
                function()
                    ns.CloseGearPanel()
                    ns.UpdateSlotButtonStates()
                end)

            AddFeatureCheckbox(category,
                "DODO_INSPECT_LOOT_MINIMAP", "showLootMinimap",
                "Minimap button",
                "Show a DodoInspect button on the minimap. Clicking it opens the loot browser: this season's eight Mythic+ dungeons and nine raid bosses, with what each of them drops for the specialization you pick. Right-click the button for these options. Switching the button off does not remove the browser -- /dins loot still opens it.",
                ns.ApplyLootMinimapEnabled)
        end

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

        AddFontSlider(category,
            "DODO_INSPECT_INSPECT_PANEL_FONT", "inspectPanelFontSize",
            "Inspect panel font size",
            "Font size, in pixels, of the gear panel docked to the right of the inspect window. The panel layout scales to match.",
            ns.RebuildInspectPanel)

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

-- Slash command fallback: /dins en | cn | fr | es | loot
--
-- `loot` is not just a convenience. It is the entry point that survives
-- the minimap button being switched off, so turning that checkbox off
-- costs a button rather than a feature -- and it is the one path that
-- still works if the Settings API ever stops registering our category
-- (this whole file's registration is inside a pcall for that reason).
SLASH_DODOINSPECT1 = "/dins"
SlashCmdList["DODOINSPECT"] = function(msg)
    msg = (msg or ""):lower():gsub("%s+", "")
    if msg == "loot" then
        ns.ToggleLootPanel()
        return
    end
    if ns.Locales[msg] then
        ApplyLocale(msg)
        print("DodoInspect: language set to " .. ns.L.name)
    else
        print("DodoInspect: usage /dins en | cn | fr | es | loot (current: " .. ns.ActiveLocaleKey .. ")")
    end
end
