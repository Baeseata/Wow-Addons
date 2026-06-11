-- DodoInspect - Options.lua
-- Settings panel under Esc > Options > AddOns, plus a slash command
-- fallback. The only option for now is the overlay language.

local ADDON_NAME, ns = ...

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

-- Register the addon category in the modern Settings UI. Wrapped in
-- pcall so a Settings API change can never break the addon itself;
-- the slash command below keeps working either way.
function ns.RegisterOptions()
    if ns.OptionsRegistered then return end
    if not Settings or not Settings.RegisterVerticalLayoutCategory then return end

    local ok = pcall(function()
        local category = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)

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
