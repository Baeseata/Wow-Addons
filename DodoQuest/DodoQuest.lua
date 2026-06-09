local addonName = ...
local DQ = CreateFrame("Frame")

local defaults = {
    enabled = true,
    autoBestReward = false,
}

local pendingBestReward = false
local optionsPanel

local function deferDelay(delay, fn)
    if type(C_Timer) == "table" and C_Timer.After then
        C_Timer.After(delay or 0.01, fn)
    else
        fn()
    end
end


local function ensureDB()
    if type(DodoQuestDB) ~= "table" then
        DodoQuestDB = {}
    end

    for key, value in pairs(defaults) do
        if DodoQuestDB[key] == nil then
            DodoQuestDB[key] = value
        end
    end
end

local function automationPaused()
    if IsShiftKeyDown and IsShiftKeyDown() then
        return true
    end

    return not (type(DodoQuestDB) == "table" and DodoQuestDB.enabled ~= false)
end

local function defer(fn)
    deferDelay(0.01, fn)
end

local function hasTableEntries(t)
    return type(t) == "table" and next(t) ~= nil
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return false
    end

    return pcall(fn, ...)
end

local function isQuestCompleteByID(questID)
    if not questID then
        return false
    end

    if type(IsQuestComplete) == "function" then
        local complete = IsQuestComplete(questID)
        if complete ~= nil and complete ~= false then
            return complete == true or complete == 1
        end
    end

    if C_QuestLog and type(C_QuestLog.IsComplete) == "function" then
        local complete = C_QuestLog.IsComplete(questID)
        return complete ~= nil and complete ~= false and complete ~= 0
    end

    return false
end

local function selectSingleSafeGossip()
    if automationPaused() then
        return false
    end

    local isOldStyleSafe
    if type(GetGossipOptions) == "function" then
        local results = { GetGossipOptions() }
        if #results == 2 and results[2] == "gossip" then
            isOldStyleSafe = true
        else
            isOldStyleSafe = false
        end
    end

    if C_GossipInfo and type(C_GossipInfo.GetOptions) == "function" then
        local options = C_GossipInfo.GetOptions()
        if type(options) == "table" and #options == 1 and isOldStyleSafe ~= false then
            local option = options[1]
            if option then
                if C_GossipInfo.SelectOption and option.gossipOptionID then
                    return safeCall(C_GossipInfo.SelectOption, option.gossipOptionID)
                end

                if C_GossipInfo.SelectOptionByIndex and option.orderIndex then
                    return safeCall(C_GossipInfo.SelectOptionByIndex, option.orderIndex)
                end
            end
        end
    end

    if isOldStyleSafe and type(SelectGossipOption) == "function" then
        return safeCall(SelectGossipOption, 1)
    end

    return false
end

local function handleLegacyGossipQuestList()
    if automationPaused() then
        return false
    end

    if type(GetNumGossipActiveQuests) == "function" and type(SelectGossipActiveQuest) == "function" then
        local numActive = GetNumGossipActiveQuests() or 0
        if numActive > 0 then
            local info = type(GetGossipActiveQuests) == "function" and { GetGossipActiveQuests() } or nil
            if type(info) == "table" and #info >= (numActive * 6) then
                for i = 1, numActive do
                    local isComplete = info[((i - 1) * 6) + 4]
                    if isComplete then
                        local idx = i
                        defer(function()
                            if not automationPaused() then
                                SelectGossipActiveQuest(idx)
                            end
                        end)
                        return true
                    end
                end
            end
        end
    end

    if type(GetNumGossipAvailableQuests) == "function" and type(SelectGossipAvailableQuest) == "function" then
        local numAvailable = GetNumGossipAvailableQuests() or 0
        if numAvailable > 0 then
            defer(function()
                if not automationPaused() then
                    SelectGossipAvailableQuest(1)
                end
            end)
            return true
        end
    end

    return false
end

local function handleGreeting()
    if automationPaused() then
        return
    end

    if type(GetNumActiveQuests) == "function" and type(SelectActiveQuest) == "function" then
        local numActive = GetNumActiveQuests() or 0
        for i = 1, numActive do
            local idx = i
            local questID = type(GetActiveQuestID) == "function" and GetActiveQuestID(idx) or nil
            if isQuestCompleteByID(questID) then
                defer(function()
                    if not automationPaused() then
                        SelectActiveQuest(idx)
                    end
                end)
                return
            end
        end
    end

    if type(GetNumAvailableQuests) == "function" and type(SelectAvailableQuest) == "function" then
        local numAvailable = GetNumAvailableQuests() or 0
        if numAvailable > 0 then
            defer(function()
                if not automationPaused() then
                    SelectAvailableQuest(1)
                end
            end)
        end
    end
end

local function handleGossip()
    if automationPaused() then
        return
    end

    if C_GossipInfo and type(C_GossipInfo.GetActiveQuests) == "function" and type(C_GossipInfo.SelectActiveQuest) == "function" then
        local active = C_GossipInfo.GetActiveQuests()
        if hasTableEntries(active) then
            for _, questInfo in ipairs(active) do
                if questInfo and questInfo.isComplete and questInfo.questID then
                    local questID = questInfo.questID
                    defer(function()
                        if not automationPaused() then
                            C_GossipInfo.SelectActiveQuest(questID)
                        end
                    end)
                    return
                end
            end
        end
    end

    if C_GossipInfo and type(C_GossipInfo.GetAvailableQuests) == "function" and type(C_GossipInfo.SelectAvailableQuest) == "function" then
        local available = C_GossipInfo.GetAvailableQuests()
        if hasTableEntries(available) then
            local questInfo = available[1]
            if questInfo and questInfo.questID then
                local questID = questInfo.questID
                defer(function()
                    if not automationPaused() then
                        C_GossipInfo.SelectAvailableQuest(questID)
                    end
                end)
                return
            end
        end
    end

    if handleLegacyGossipQuestList() then
        return
    end

    defer(selectSingleSafeGossip)
end

local function handleQuestDetail()
    if automationPaused() then
        return
    end

    defer(function()
        if not automationPaused() and type(AcceptQuest) == "function" then
            AcceptQuest()
        end
    end)
end

local function handleQuestProgress()
    if automationPaused() or type(IsQuestCompletable) ~= "function" or not IsQuestCompletable() then
        return
    end

    defer(function()
        if not automationPaused() and type(CompleteQuest) == "function" then
            CompleteQuest()
        end
    end)
end

local function getBestRewardChoiceIndex()
    if type(GetNumQuestChoices) ~= "function" then
        return nil, false
    end

    local choices = GetNumQuestChoices() or 0
    if choices <= 1 then
        return nil, false
    end

    local bestIndex
    local bestValue = -1
    local waitingForItemData = false

    for i = 1, choices do
        local count, itemID
        if type(GetQuestItemInfo) == "function" then
            local _, _, itemCount, _, _, questItemID = GetQuestItemInfo("choice", i)
            count = itemCount
            itemID = questItemID
        end

        local itemLink = type(GetQuestItemLink) == "function" and GetQuestItemLink("choice", i) or nil
        local priceSource = itemLink or itemID
        local sellPrice

        if priceSource and type(GetItemInfo) == "function" then
            local _, _, _, _, _, _, _, _, _, _, vendorSell = GetItemInfo(priceSource)
            sellPrice = vendorSell
        end

        if sellPrice == nil and itemID and C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
            C_Item.RequestLoadItemDataByID(itemID)
            waitingForItemData = true
        elseif type(sellPrice) == "number" then
            local totalValue = sellPrice * (count or 1)
            if totalValue > bestValue then
                bestValue = totalValue
                bestIndex = i
            end
        end
    end

    return bestIndex, waitingForItemData
end

local function handleQuestComplete()
    pendingBestReward = false

    if automationPaused() or type(GetNumQuestChoices) ~= "function" then
        return
    end

    local choices = GetNumQuestChoices() or 0
    if choices > 1 then
        if not (type(DodoQuestDB) == "table" and DodoQuestDB.autoBestReward) then
            return
        end

        local bestIndex, waitingForItemData = getBestRewardChoiceIndex()
        if bestIndex then
            defer(function()
                if not automationPaused() and type(GetQuestReward) == "function" then
                    GetQuestReward(bestIndex)
                end
            end)
            return
        end

        pendingBestReward = waitingForItemData
        return
    end

    defer(function()
        if not automationPaused() and type(GetQuestReward) == "function" then
            GetQuestReward(1)
        end
    end)
end

local function refreshOptionsPanel()
    if not optionsPanel then
        return
    end

    if optionsPanel.enableCheck then
        optionsPanel.enableCheck:SetChecked(DodoQuestDB.enabled ~= false)
    end

    if optionsPanel.bestRewardCheck then
        optionsPanel.bestRewardCheck:SetChecked(DodoQuestDB.autoBestReward == true)
    end
end

local function createCheckbox(parent, name, labelText, descriptionText, anchorTo, onClick)
    local check = CreateFrame("CheckButton", name, parent, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -12)

    local text = check.Text or _G[name .. "Text"]
    if text then
        text:SetText(labelText)
    end

    local desc = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 26, -4)
    desc:SetWidth(600)
    desc:SetJustifyH("LEFT")
    desc:SetText(descriptionText)

    check:SetScript("OnClick", onClick)
    check.description = desc

    return check
end

local function registerOptionsPanel()
    if optionsPanel then
        return
    end

    local panel = CreateFrame("Frame", addonName .. "OptionsPanel", UIParent)
    panel.name = addonName
    optionsPanel = panel

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("DodoQuest")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetWidth(600)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("轻量级自动任务助手。按住 Shift 可以暂时暂停所有自动化操作。同时支持旧式任务列表对话页。")

    panel.enableCheck = createCheckbox(
        panel,
        addonName .. "EnableCheck",
        "启用自动接受/交付任务",
        "开启后，DodoQuest 会自动接受普通任务、交付已完成的任务、点击旧式对话页中的单个任务条目，并跳过单一安全对话选项。",
        subtitle,
        function(self)
            DodoQuestDB.enabled = self:GetChecked() and true or false
            refreshOptionsPanel()
        end
    )

    panel.bestRewardCheck = createCheckbox(
        panel,
        addonName .. "BestRewardCheck",
        "自动选择最高价值奖励",
        "对于有多个奖励可选的任务，自动选择卖店价格最高的物品。如果物品价格数据暂时不可用，会等待而不是随机选择。",
        panel.enableCheck.description,
        function(self)
            DodoQuestDB.autoBestReward = self:GetChecked() and true or false
            refreshOptionsPanel()
        end
    )

    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", panel.bestRewardCheck.description, "BOTTOMLEFT", -26, -16)
    note:SetWidth(600)
    note:SetJustifyH("LEFT")
    note:SetText("默认值：自动化已启用，自动选择奖励已关闭。")

    panel:SetScript("OnShow", refreshOptionsPanel)

    if Settings and type(Settings.RegisterCanvasLayoutCategory) == "function" and type(Settings.RegisterAddOnCategory) == "function" then
        local category = Settings.RegisterCanvasLayoutCategory(panel, addonName, addonName)
        Settings.RegisterAddOnCategory(category)
    elseif type(InterfaceOptions_AddCategory) == "function" then
        InterfaceOptions_AddCategory(panel)
    end
end

DQ:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName == addonName then
            ensureDB()
            registerOptionsPanel()
            refreshOptionsPanel()
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if pendingBestReward then
            handleQuestComplete()
        end
    elseif event == "GOSSIP_SHOW" or event == "GOSSIP_OPTIONS_REFRESHED" then
        handleGossip()
    elseif event == "QUEST_GREETING" then
        handleGreeting()
    elseif event == "QUEST_DETAIL" then
        handleQuestDetail()
    elseif event == "QUEST_PROGRESS" then
        handleQuestProgress()
    elseif event == "QUEST_COMPLETE" then
        handleQuestComplete()
    end
end)

DQ:RegisterEvent("ADDON_LOADED")
DQ:RegisterEvent("GET_ITEM_INFO_RECEIVED")
DQ:RegisterEvent("GOSSIP_SHOW")
DQ:RegisterEvent("GOSSIP_OPTIONS_REFRESHED")
DQ:RegisterEvent("QUEST_GREETING")
DQ:RegisterEvent("QUEST_DETAIL")
DQ:RegisterEvent("QUEST_PROGRESS")
DQ:RegisterEvent("QUEST_COMPLETE")
