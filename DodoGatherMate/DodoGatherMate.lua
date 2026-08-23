local addonName = ...

local ADDON_TITLE = "DodoGatherMate"
local HERB_SKILL_LINE = 182
local MINING_SKILL_LINE = 186
local DEDUP_THRESHOLD = 0.005
local ICON_HERB = 136246
local ICON_MINE = 136248
local ICON_AIRDROP = 132764  -- INV_Misc_Bag_10 (supply crate icon)
local MAX_MINIMAP_PINS = 80
local OPENING_SPELL_NAME = "开启"

local AIRDROP_MAPS = {
    ["永歌森林"] = true,
    ["祖阿曼"] = true,
    ["哈籁恩达尔"] = true,
    ["虚影风暴"] = true,
}

local DEFAULTS = {
    -- The minimap ring is SHARED with every other Dodo addon that draws its own
    -- button; two identical defaults stack perfectly and the lower button cannot
    -- be clicked on a fresh install. Before changing this value (or picking one
    -- for a new addon) grep the monorepo for `minimapAngle|minimap = { angle`.
    minimap = { angle = 210 },
    settings = {
        alpha = 0.4,
        worldAlpha = 0.6,
        pinSize = 12,
        worldPinSize = 14,
        showHerbs = true,
        showMines = true,
        showAirdrops = true,
        airdropAlpha = 0.8,
        airdropPinSize = 20,
        airdropWorldPinSize = 18,
    },
    iconCache = {},
    nodes = {},
    gatherLog = {},
}

local db
local eventFrame = CreateFrame("Frame")
local hasHerbalism = false
local hasMining = false
local pendingGather = nil
local minimapPinPool = {}
local minimapPinCount = 0
local minimapTicker = nil
local minimapButton = nil
local UpdateWorldMapPins
local settingsCategory

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------
local function Print(msg)
    print("|cff33ff99DodoGatherMate:|r " .. tostring(msg))
end

local function CopyDefaults(src, dst)
    if type(src) ~= "table" then return {} end
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

local function GetCurrentMapID()
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then return mapID end
    if WorldMapFrame and WorldMapFrame.GetMapID then
        return WorldMapFrame:GetMapID()
    end
    return nil
end

local function GetDistance(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

--------------------------------------------------------------------------------
-- Gold / Price Helpers
--------------------------------------------------------------------------------
local function FormatGold(copper)
    if type(copper) ~= "number" or copper <= 0 then return "0g" end
    copper = math.floor(copper + 0.5)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    if gold > 0 then
        return string.format("%dg %ds", gold, silver)
    else
        return string.format("%ds", silver)
    end
end

local function GetReagentQualityStars(itemID)
    if not (C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo) then return "" end
    local ok, q = pcall(C_TradeSkillUI.GetItemReagentQualityByItemInfo, string.format("item:%d", itemID))
    if ok and type(q) == "number" and q > 0 then
        return " " .. string.rep("★", q)
    end
    return ""
end

local function GetAuctionPrice(itemID)
    if not DodoAuctionDB or not DodoAuctionDB.items then return nil end
    local entry = DodoAuctionDB.items[itemID]
    if not entry or not entry.records or #entry.records == 0 then return nil end
    local p = entry.records[#entry.records].p
    return (p and p > 0) and p or nil
end

local function PruneGatherLog()
    if not db or not db.gatherLog then return end
    local cutoff = time() - 3600
    local newLog = {}
    for _, entry in ipairs(db.gatherLog) do
        if entry.t >= cutoff then
            newLog[#newLog + 1] = entry
        end
    end
    db.gatherLog = newLog
end

local function GetHourlyEarnings()
    if not db or not db.gatherLog then return {}, 0 end
    PruneGatherLog()

    local byItem = {}
    for _, entry in ipairs(db.gatherLog) do
        local id = entry.itemID
        if id then
            if not byItem[id] then
                byItem[id] = { itemID = id, name = entry.name or "", icon = entry.icon or 0, qty = 0 }
            end
            byItem[id].qty = byItem[id].qty + (entry.qty or 0)
        end
    end

    local results = {}
    local totalCopper = 0
    for id, info in pairs(byItem) do
        local unitPrice = GetAuctionPrice(id)
        if unitPrice then
            local subtotal = unitPrice * info.qty
            results[#results + 1] = {
                itemID = id,
                name = info.name,
                icon = info.icon,
                qty = info.qty,
                unitPrice = unitPrice,
                subtotal = subtotal,
            }
            totalCopper = totalCopper + subtotal
        end
    end

    table.sort(results, function(a, b) return a.name < b.name end)
    return results, totalCopper
end

--------------------------------------------------------------------------------
-- Profession Detection
--------------------------------------------------------------------------------
local function UpdateProfessions()
    hasHerbalism = false
    hasMining = false

    local prof1, prof2 = GetProfessions()
    for _, idx in ipairs({ prof1, prof2 }) do
        if idx then
            local _, _, _, _, _, _, skillLine = GetProfessionInfo(idx)
            if skillLine == HERB_SKILL_LINE then
                hasHerbalism = true
            elseif skillLine == MINING_SKILL_LINE then
                hasMining = true
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Node Storage
--------------------------------------------------------------------------------
local function AddNode(mapID, x, y, name, nodeType, icon)
    if not mapID or not x or not y or not name then return false end

    db.nodes[mapID] = db.nodes[mapID] or {}
    local list = db.nodes[mapID]

    for _, node in ipairs(list) do
        if node.name == name and GetDistance(node.x, node.y, x, y) < DEDUP_THRESHOLD then
            if icon and icon ~= 0 then
                node.icon = icon
            end
            return false
        end
    end

    table.insert(list, {
        x = x,
        y = y,
        name = name,
        type = nodeType,
        icon = icon or 0,
    })
    return true
end

local function RemoveNode(mapID, index)
    if not db.nodes[mapID] then return end
    table.remove(db.nodes[mapID], index)
    if #db.nodes[mapID] == 0 then
        db.nodes[mapID] = nil
    end
end

local function ClearNodesForMap(mapID)
    db.nodes[mapID] = nil
end

local function ClearAllNodes()
    db.nodes = {}
end

local function GetNodeIcon(node)
    if node.icon and node.icon ~= 0 then
        return node.icon
    end
    if node.type == "airdrop" then
        return ICON_AIRDROP
    end
    if db.iconCache[node.name] then
        return db.iconCache[node.name]
    end
    if node.type == "herb" then
        return ICON_HERB
    end
    return ICON_MINE
end

local function ShouldShowNode(node)
    if node.type == "herb" then
        return hasHerbalism and db.settings.showHerbs
    elseif node.type == "mine" then
        return hasMining and db.settings.showMines
    elseif node.type == "airdrop" then
        return db.settings.showAirdrops
    end
    return false
end

--------------------------------------------------------------------------------
-- Gathering Detection
--------------------------------------------------------------------------------
local function Detaint(text)
    -- Rebuild string byte-by-byte to remove taint
    local bytes = { string.byte(text, 1, #text) }
    return string.char(unpack(bytes))
end

local function GetTooltipNodeName()
    if not GameTooltip or not GameTooltip:IsShown() then return nil end
    local line = _G["GameTooltipTextLeft1"]
    if not line or not line.GetText then return nil end
    local ok, text = pcall(line.GetText, line)
    if not ok or not text then return nil end
    local ok2, clean = pcall(Detaint, text)
    if ok2 and clean and #clean > 0 then return clean end
    return nil
end

local function IsGatheringSpell(spellID)
    if not spellID then return nil end

    local info = C_Spell.GetSpellInfo(spellID)
    if not info then return nil end

    local spellName = info.name
    if not spellName then return nil end

    local subtext = C_Spell.GetSpellSubtext(spellID)

    if subtext then
        local lower = subtext:lower()
        if lower == "herbalism" or lower:find("草药") or lower:find("采药") then
            return "herb"
        end
        if lower == "mining" or lower:find("采矿") then
            return "mine"
        end
    end

    local lower = spellName:lower()
    if lower:find("herb gathering") or lower:find("采药")
        or lower:find("草药") or lower:find("采集草药") then
        return "herb"
    end
    if lower:find("mining") or lower:find("采矿")
        or lower:find("矿石") or lower:find("开采") then
        return "mine"
    end

    return nil
end

local function GetCurrentMapName()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local info = C_Map.GetMapInfo(mapID)
    return info and info.name or nil
end

local function OnSpellCastStart(_, _, unit, _, spellID)
    if unit ~= "player" then return end

    local nodeType = IsGatheringSpell(spellID)

    -- Check for airdrop: "Opening" spell on tracked maps, only specific crate names
    if not nodeType then
        local info = spellID and C_Spell.GetSpellInfo(spellID)
        if info and info.name == OPENING_SPELL_NAME then
            local mapName = GetCurrentMapName()
            if mapName and AIRDROP_MAPS[mapName] then
                local targetName = GetTooltipNodeName()
                if targetName and (targetName == "战争补给箱" or targetName == "战争物资箱") then
                    nodeType = "airdrop"
                end
            end
        end
    end

    if not nodeType then return end

    if nodeType == "herb" and not hasHerbalism then return end
    if nodeType == "mine" and not hasMining then return end

    local mapID = GetCurrentMapID()
    if not mapID then return end

    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local px, py = pos:GetXY()
    if not px or px == 0 and py == 0 then return end

    local nodeName
    if nodeType == "airdrop" then
        nodeName = "空投补给"
    else
        nodeName = GetTooltipNodeName() or "Unknown"
    end

    local icon = (nodeType == "airdrop") and ICON_AIRDROP or (db.iconCache[nodeName] or 0)

    pendingGather = {
        mapID = mapID,
        x = px,
        y = py,
        name = nodeName,
        type = nodeType,
        icon = icon,
    }

    local added = AddNode(mapID, px, py, nodeName, nodeType, icon)
    if added then
        RefreshAllPins()
    end
end

local function OnLootOpened()
    if not pendingGather then return end

    local numItems = GetNumLootItems()
    if numItems and numItems > 0 then
        -- Icon learning (existing logic)
        local lootIcon = GetLootSlotInfo(1)
        if lootIcon then
            local name = pendingGather.name
            if name and name ~= "Unknown" then
                db.iconCache[name] = lootIcon

                local mapID = pendingGather.mapID
                if db.nodes[mapID] then
                    for _, node in ipairs(db.nodes[mapID]) do
                        if node.name == name and (not node.icon or node.icon == 0) then
                            node.icon = lootIcon
                        end
                    end
                end
                RefreshAllPins()
            end
        end

        -- Gather log: record loot items for earnings (herb/mine only)
        local gatherType = pendingGather.type
        if (gatherType == "herb" or gatherType == "mine") and db.gatherLog then
            local t = time()
            for i = 1, numItems do
                local slotIcon, itemName, itemQty = GetLootSlotInfo(i)
                local link = GetLootSlotLink(i)
                if link then
                    local itemID = tonumber(link:match("item:(%d+)"))
                    if itemID and itemQty and itemQty > 0 then
                        db.gatherLog[#db.gatherLog + 1] = {
                            t = t,
                            itemID = itemID,
                            qty = itemQty,
                            icon = slotIcon or 0,
                            name = itemName or "",
                        }
                    end
                end
            end
            PruneGatherLog()
        end
    end

    pendingGather = nil
end

--------------------------------------------------------------------------------
-- Minimap Pins
--------------------------------------------------------------------------------
local function GetOrCreateMinimapPin(index)
    if minimapPinPool[index] then
        return minimapPinPool[index]
    end

    local pin = CreateFrame("Button", nil, Minimap)
    pin:SetSize(db.settings.pinSize or 16, db.settings.pinSize or 16)
    pin:SetFrameStrata("MEDIUM")
    pin:SetFrameLevel(3)
    pin:RegisterForClicks("RightButtonUp")
    pin:Hide()

    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    -- Disable texel snapping to prevent jitter (technique from HereBeDragons)
    pin.icon:SetTexelSnappingBias(0)
    pin.icon:SetSnapToPixelGrid(false)

    pin:SetScript("OnEnter", function(self)
        if not self.nodeData then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.nodeData.name or "Unknown", 1, 1, 1)
        local t = self.nodeData.type
        local typeName = t == "herb" and "草药" or (t == "airdrop" and "空投" or "矿石")
        GameTooltip:AddLine(typeName, 0.7, 0.7, 0.7)
        GameTooltip:AddLine("右键点击删除", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)

    pin:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    pin:SetScript("OnClick", function(self, button)
        if button == "RightButton" and self.nodeMapID and self.nodeIndex then
            RemoveNode(self.nodeMapID, self.nodeIndex)
            RefreshAllPins()
        end
    end)

    minimapPinPool[index] = pin
    return pin
end

local minimapActiveCount = 0

local function UpdateMinimapPins()
    local mapID = GetCurrentMapID()
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    local px, py
    if pos then px, py = pos:GetXY() end

    local nodes = (px and db.nodes[mapID]) or nil
    local mapWidth, mapHeight
    if nodes then
        mapWidth, mapHeight = C_Map.GetMapWorldSize(mapID)
        if not mapWidth or mapWidth == 0 then nodes = nil end
    end

    local viewRadius
    if nodes then
        if C_Minimap and C_Minimap.GetViewRadius then
            viewRadius = C_Minimap.GetViewRadius()
        else
            local zoom = Minimap:GetZoom()
            local maxZoom = Minimap:GetZoomLevels() - 1
            if maxZoom <= 0 then maxZoom = 1 end
            viewRadius = 125 * (1 - (zoom / maxZoom) * 0.6)
        end
        if not viewRadius or viewRadius <= 0 then nodes = nil end
    end

    local minimapRadius = Minimap:GetWidth() / 2
    local rotateMinimap = GetCVar("rotateMinimap") == "1"
    local facing = rotateMinimap and (GetPlayerFacing() or 0) or 0
    local pinIndex = 0

    if nodes then
        local yardToPixel = minimapRadius / viewRadius

        for i, node in ipairs(nodes) do
            if ShouldShowNode(node) and pinIndex < MAX_MINIMAP_PINS then
                local dx = (node.x - px) * mapWidth
                local dy = (py - node.y) * mapHeight

                if rotateMinimap then
                    local sinF = math.sin(-facing)
                    local cosF = math.cos(-facing)
                    dx, dy = dx * cosF - dy * sinF, dx * sinF + dy * cosF
                end

                local isAirdrop = node.type == "airdrop"
                local pinSize = isAirdrop and (db.settings.airdropPinSize or 20) or (db.settings.pinSize or 16)
                local alpha = isAirdrop and (db.settings.airdropAlpha or 0.8) or (db.settings.alpha or 0.6)

                local screenX = dx * yardToPixel
                local screenY = dy * yardToPixel
                local screenDist = screenX * screenX + screenY * screenY
                local limit = minimapRadius - pinSize / 2

                if screenDist < limit * limit then
                    pinIndex = pinIndex + 1
                    local pin = GetOrCreateMinimapPin(pinIndex)
                    pin.nodeData = node
                    pin.nodeMapID = mapID
                    pin.nodeIndex = i

                    pin:SetSize(pinSize, pinSize)
                    pin.icon:SetTexture(GetNodeIcon(node))
                    pin.icon:SetAlpha(alpha)
                    pin:ClearAllPoints()
                    pin:SetPoint("CENTER", Minimap, "CENTER", screenX, screenY)
                    if not pin:IsShown() then pin:Show() end
                end
            end
        end
    end

    -- Hide pins that are no longer used (without hiding active ones)
    for j = pinIndex + 1, minimapActiveCount do
        if minimapPinPool[j] then
            minimapPinPool[j]:Hide()
        end
    end
    minimapActiveCount = pinIndex
end

--------------------------------------------------------------------------------
-- Refresh All Pins
--------------------------------------------------------------------------------
function RefreshAllPins()
    if not db then return end
    UpdateMinimapPins()
    UpdateWorldMapPins()
end

--------------------------------------------------------------------------------
-- Earnings Window
--------------------------------------------------------------------------------
local earningsFrame
local earningsRows = {}
local MAX_EARNINGS_ROWS = 20

local EARNINGS_COL_NAME = 26
local EARNINGS_COL_QTY = 210
local EARNINGS_COL_PRICE = 260
local EARNINGS_COL_SUB = 360
local EARNINGS_WIDTH = 460

local function CreateEarningsWindow()
    earningsFrame = CreateFrame("Frame", addonName .. "EarningsFrame", UIParent, "BackdropTemplate")
    earningsFrame:SetSize(EARNINGS_WIDTH, 180)
    earningsFrame:SetPoint("CENTER")
    earningsFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    earningsFrame:SetMovable(true)
    earningsFrame:EnableMouse(true)
    earningsFrame:RegisterForDrag("LeftButton")
    earningsFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    earningsFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    earningsFrame:SetFrameStrata("DIALOG")
    earningsFrame:Hide()

    earningsFrame.title = earningsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    earningsFrame.title:SetPoint("TOP", 0, -16)
    earningsFrame.title:SetText("最近1小时采集收益")

    earningsFrame.close = CreateFrame("Button", nil, earningsFrame, "UIPanelCloseButton")
    earningsFrame.close:SetPoint("TOPRIGHT", -6, -6)

    -- Column headers
    local hdrY = -44
    local hName = earningsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hName:SetPoint("TOPLEFT", EARNINGS_COL_NAME, hdrY)
    hName:SetText("物品")

    local hQty = earningsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hQty:SetPoint("TOPLEFT", EARNINGS_COL_QTY, hdrY)
    hQty:SetWidth(40)
    hQty:SetJustifyH("RIGHT")
    hQty:SetText("数量")

    local hPrice = earningsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hPrice:SetPoint("TOPLEFT", EARNINGS_COL_PRICE, hdrY)
    hPrice:SetWidth(80)
    hPrice:SetJustifyH("RIGHT")
    hPrice:SetText("单价")

    local hSub = earningsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hSub:SetPoint("TOPLEFT", EARNINGS_COL_SUB, hdrY)
    hSub:SetWidth(80)
    hSub:SetJustifyH("RIGHT")
    hSub:SetText("小计")

    -- Total footer
    earningsFrame.totalText = earningsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    earningsFrame.totalText:SetPoint("BOTTOMRIGHT", -20, 16)
    earningsFrame.totalText:SetJustifyH("RIGHT")

    earningsFrame.noDataText = earningsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    earningsFrame.noDataText:SetPoint("CENTER", 0, -10)
    earningsFrame.noDataText:SetText("暂无采集记录或需要安装DodoAuction获取价格数据")
    earningsFrame.noDataText:Hide()
end

local function GetOrCreateEarningsRow(index)
    if earningsRows[index] then return earningsRows[index] end

    local row = CreateFrame("Frame", nil, earningsFrame)
    local rowY = -62 - (index - 1) * 24
    row:SetSize(EARNINGS_WIDTH - 20, 22)
    row:SetPoint("TOPLEFT", 0, rowY)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", EARNINGS_COL_NAME, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.name:SetWidth(160)
    row.name:SetJustifyH("LEFT")
    row.name:SetMaxLines(1)
    row.name:SetWordWrap(false)

    row.qty = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.qty:SetPoint("LEFT", row, "LEFT", EARNINGS_COL_QTY, 0)
    row.qty:SetWidth(40)
    row.qty:SetJustifyH("RIGHT")

    row.price = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.price:SetPoint("LEFT", row, "LEFT", EARNINGS_COL_PRICE, 0)
    row.price:SetWidth(80)
    row.price:SetJustifyH("RIGHT")

    row.subtotal = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.subtotal:SetPoint("LEFT", row, "LEFT", EARNINGS_COL_SUB, 0)
    row.subtotal:SetWidth(80)
    row.subtotal:SetJustifyH("RIGHT")

    earningsRows[index] = row
    return row
end

local function RefreshEarningsWindow()
    if not earningsFrame or not earningsFrame:IsShown() then return end

    local results, totalCopper = GetHourlyEarnings()
    local count = #results

    -- Hide all existing rows first
    for _, row in pairs(earningsRows) do
        row:Hide()
    end

    if count == 0 then
        earningsFrame.noDataText:Show()
        earningsFrame.totalText:SetText("")
        earningsFrame:SetHeight(180)
        earningsFrame:SetWidth(EARNINGS_WIDTH)
        return
    end

    earningsFrame.noDataText:Hide()

    local shown = math.min(count, MAX_EARNINGS_ROWS)
    for i = 1, shown do
        local r = results[i]
        local row = GetOrCreateEarningsRow(i)
        row.icon:SetTexture(r.icon)
        local displayName = r.name .. GetReagentQualityStars(r.itemID)
        row.name:SetText(displayName)
        row.qty:SetText(tostring(r.qty))
        row.price:SetText(FormatGold(r.unitPrice))
        row.subtotal:SetText(FormatGold(r.subtotal))
        row:Show()
    end

    earningsFrame.totalText:SetText("|cffFFD100总计：|r " .. FormatGold(totalCopper))

    -- Dynamic height: title(62) + rows(24 each) + footer(44)
    local height = 62 + shown * 24 + 44
    if height < 180 then height = 180 end
    earningsFrame:SetHeight(height)
end

local function ToggleEarningsWindow()
    if not earningsFrame then
        CreateEarningsWindow()
    end
    if earningsFrame:IsShown() then
        earningsFrame:Hide()
    else
        RefreshEarningsWindow()
        earningsFrame:Show()
        RefreshEarningsWindow()
    end
end

--------------------------------------------------------------------------------
-- Minimap Button
--------------------------------------------------------------------------------
local function NormalizeAngle(angle)
    angle = tonumber(angle) or DEFAULTS.minimap.angle
    angle = angle % 360
    if angle < 0 then angle = angle + 360 end
    return angle
end

local function UpdateMinimapButtonPosition()
    if not minimapButton then return end
    db.minimap.angle = NormalizeAngle(db.minimap.angle)
    local radius = (Minimap:GetWidth() / 2) + 6
    local angle = math.rad(db.minimap.angle)
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function UpdateMinimapButtonFromCursor()
    if not minimapButton then return end
    local cx, cy = Minimap:GetCenter()
    if not cx then return end
    local mx, my = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    mx, my = mx / scale, my / scale
    local dx, dy = mx - cx, my - cy
    if dx == 0 and dy == 0 then return end
    db.minimap.angle = math.deg(math.atan2(dy, dx))
    UpdateMinimapButtonPosition()
end

local function OpenSettings()
    if settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(settingsCategory:GetID())
    end
end

local function CreateMinimapButton()
    minimapButton = CreateFrame("Button", "DodoGatherMateMinimapButton", Minimap)
    minimapButton:SetSize(31, 31)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local icon = minimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\Trade_Mining")

    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local highlight = minimapButton:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(23, 23)
    highlight:SetPoint("CENTER", 0, 1)
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")

    minimapButton:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and IsShiftKeyDown() then
            self.isDragging = true
            self:SetScript("OnUpdate", function() UpdateMinimapButtonFromCursor() end)
        end
    end)

    minimapButton:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.isDragging then
            self.isDragging = false
            self:SetScript("OnUpdate", nil)
            self.suppressNextClick = true
        end
    end)

    minimapButton:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if self.suppressNextClick then
                self.suppressNextClick = nil
                return
            end
            ToggleEarningsWindow()
        elseif button == "RightButton" then
            OpenSettings()
        end
    end)

    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("DodoGatherMate", 1, 1, 1)
        GameTooltip:AddLine("左键：采集收益", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("右键：打开设置", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Shift+左键拖动：移动图标", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    minimapButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    UpdateMinimapButtonPosition()
end

--------------------------------------------------------------------------------
-- Settings Panel
--------------------------------------------------------------------------------
local function CreateSlider(parent, name, label, minVal, maxVal, step, anchorTo, offsetY, getter, setter)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetWidth(200)
    slider:SetHeight(17)
    slider:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, offsetY or -30)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    local low = _G[name .. "Low"]
    local high = _G[name .. "High"]
    local text = _G[name .. "Text"]

    if low then low:SetText(tostring(minVal)) end
    if high then high:SetText(tostring(maxVal)) end
    if text then text:SetText(label) end

    local valueText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valueText:SetPoint("TOP", slider, "BOTTOM", 0, -2)
    slider.valueText = valueText

    slider:SetValue(getter())
    valueText:SetText(string.format("%.2f", getter()))

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        setter(value)
        self.valueText:SetText(string.format("%.2f", value))
        RefreshAllPins()
    end)

    return slider
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = ADDON_TITLE
    panel:Hide()

    panel.OnCommit = function() end
    panel.OnDefault = function()
        db.settings.alpha = DEFAULTS.settings.alpha
        db.settings.worldAlpha = DEFAULTS.settings.worldAlpha
        db.settings.pinSize = DEFAULTS.settings.pinSize
        db.settings.worldPinSize = DEFAULTS.settings.worldPinSize
        db.settings.showHerbs = DEFAULTS.settings.showHerbs
        db.settings.showMines = DEFAULTS.settings.showMines
        db.settings.showAirdrops = DEFAULTS.settings.showAirdrops
        db.settings.airdropAlpha = DEFAULTS.settings.airdropAlpha
        db.settings.airdropPinSize = DEFAULTS.settings.airdropPinSize
        db.settings.airdropWorldPinSize = DEFAULTS.settings.airdropWorldPinSize
        RefreshAllPins()
    end
    panel.OnRefresh = function() end

    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 16, -16)
    header:SetText("DodoGatherMate")

    local subText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subText:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    subText:SetWidth(520)
    subText:SetJustifyH("LEFT")
    subText:SetText("自动记录采集节点位置并在大地图/小地图上显示。")

    -- Minimap Alpha Slider
    local alphaSlider = CreateSlider(
        panel, ADDON_TITLE .. "AlphaSlider", "小地图图标透明度",
        0.1, 1.0, 0.05, subText, -40,
        function() return db.settings.alpha end,
        function(v) db.settings.alpha = v end
    )

    -- World Map Alpha Slider
    local worldAlphaSlider = CreateSlider(
        panel, ADDON_TITLE .. "WorldAlphaSlider", "大地图图标透明度",
        0.1, 1.0, 0.05, alphaSlider, -40,
        function() return db.settings.worldAlpha end,
        function(v) db.settings.worldAlpha = v end
    )

    -- Minimap Pin Size Slider
    local minimapSizeSlider = CreateSlider(
        panel, ADDON_TITLE .. "MinimapSizeSlider", "小地图图标大小",
        8, 32, 1, worldAlphaSlider, -40,
        function() return db.settings.pinSize end,
        function(v) db.settings.pinSize = v end
    )

    -- World Map Pin Size Slider
    local worldSizeSlider = CreateSlider(
        panel, ADDON_TITLE .. "WorldSizeSlider", "大地图图标大小",
        8, 32, 1, minimapSizeSlider, -40,
        function() return db.settings.worldPinSize end,
        function(v) db.settings.worldPinSize = v end
    )

    -- Show Herbs Checkbox
    local herbCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    herbCheck:SetPoint("TOPLEFT", worldSizeSlider, "BOTTOMLEFT", 0, -24)
    local herbLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    herbLabel:SetPoint("LEFT", herbCheck, "RIGHT", 4, 0)
    herbLabel:SetText("显示草药节点")
    herbCheck:SetChecked(db.settings.showHerbs)
    herbCheck:SetScript("OnClick", function(self)
        db.settings.showHerbs = self:GetChecked() and true or false
        RefreshAllPins()
    end)

    -- Show Mines Checkbox
    local mineCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    mineCheck:SetPoint("TOPLEFT", herbCheck, "BOTTOMLEFT", 0, -8)
    local mineLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    mineLabel:SetPoint("LEFT", mineCheck, "RIGHT", 4, 0)
    mineLabel:SetText("显示矿石节点")
    mineCheck:SetChecked(db.settings.showMines)
    mineCheck:SetScript("OnClick", function(self)
        db.settings.showMines = self:GetChecked() and true or false
        RefreshAllPins()
    end)

    -- Airdrop Section Header
    local airdropHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    airdropHeader:SetPoint("TOPLEFT", mineCheck, "BOTTOMLEFT", 0, -20)
    airdropHeader:SetText("|cffFFD100空投设置|r")

    -- Show Airdrops Checkbox
    local airdropCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    airdropCheck:SetPoint("TOPLEFT", airdropHeader, "BOTTOMLEFT", 0, -8)
    local airdropLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    airdropLabel:SetPoint("LEFT", airdropCheck, "RIGHT", 4, 0)
    airdropLabel:SetText("显示空投节点")
    airdropCheck:SetChecked(db.settings.showAirdrops)
    airdropCheck:SetScript("OnClick", function(self)
        db.settings.showAirdrops = self:GetChecked() and true or false
        RefreshAllPins()
    end)

    -- Airdrop Alpha Slider
    local airdropAlphaSlider = CreateSlider(
        panel, ADDON_TITLE .. "AirdropAlphaSlider", "空投图标透明度",
        0.1, 1.0, 0.05, airdropCheck, -30,
        function() return db.settings.airdropAlpha end,
        function(v) db.settings.airdropAlpha = v end
    )

    -- Airdrop Minimap Pin Size Slider
    local airdropMinimapSlider = CreateSlider(
        panel, ADDON_TITLE .. "AirdropMinimapSlider", "空投小地图图标大小",
        8, 108, 1, airdropAlphaSlider, -40,
        function() return db.settings.airdropPinSize end,
        function(v) db.settings.airdropPinSize = v end
    )

    -- Airdrop World Map Pin Size Slider
    local airdropWorldSlider = CreateSlider(
        panel, ADDON_TITLE .. "AirdropWorldSlider", "空投大地图图标大小",
        8, 108, 1, airdropMinimapSlider, -40,
        function() return db.settings.airdropWorldPinSize end,
        function(v) db.settings.airdropWorldPinSize = v end
    )

    -- Clear Current Map Button
    local clearMapBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clearMapBtn:SetSize(140, 24)
    clearMapBtn:SetPoint("TOPLEFT", airdropWorldSlider, "BOTTOMLEFT", 0, -20)
    clearMapBtn:SetText("清空当前地图")
    clearMapBtn:SetScript("OnClick", function()
        local mapID = GetCurrentMapID()
        if mapID then
            ClearNodesForMap(mapID)
            RefreshAllPins()
            Print("已清空当前地图的采集记录。")
        end
    end)

    -- Clear All Button
    local clearAllBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clearAllBtn:SetSize(140, 24)
    clearAllBtn:SetPoint("LEFT", clearMapBtn, "RIGHT", 12, 0)
    clearAllBtn:SetText("清空所有记录")
    clearAllBtn:SetScript("OnClick", function()
        StaticPopup_Show(ADDON_TITLE .. "_CONFIRM_CLEAR_ALL")
    end)

    -- Confirm dialog for clear all
    StaticPopupDialogs[ADDON_TITLE .. "_CONFIRM_CLEAR_ALL"] = {
        text = "确定要清空所有采集记录吗？此操作不可撤销。",
        button1 = "确定",
        button2 = "取消",
        OnAccept = function()
            ClearAllNodes()
            RefreshAllPins()
            Print("已清空所有采集记录。")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    -- Stats
    local statsText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statsText:SetPoint("TOPLEFT", clearMapBtn, "BOTTOMLEFT", 0, -16)
    statsText:SetWidth(400)
    statsText:SetJustifyH("LEFT")

    panel:SetScript("OnShow", function()
        herbCheck:SetChecked(db.settings.showHerbs)
        mineCheck:SetChecked(db.settings.showMines)
        airdropCheck:SetChecked(db.settings.showAirdrops)

        local totalNodes = 0
        local totalMaps = 0
        for mapID, nodes in pairs(db.nodes) do
            totalMaps = totalMaps + 1
            totalNodes = totalNodes + #nodes
        end
        statsText:SetText(string.format("共记录 %d 个节点，分布在 %d 个地图中。", totalNodes, totalMaps))
    end)

    local category, layout = Settings.RegisterCanvasLayoutCategory(panel, ADDON_TITLE, ADDON_TITLE)
    if layout and layout.AddAnchorPoint then
        layout:AddAnchorPoint("TOPLEFT", 0, 0)
        layout:AddAnchorPoint("BOTTOMRIGHT", 0, 0)
    end
    Settings.RegisterAddOnCategory(category)
    settingsCategory = category
end

--------------------------------------------------------------------------------
-- World Map Pins (manual frame management)
--------------------------------------------------------------------------------
local worldMapPinPool = {}

local function HideAllWorldMapPins()
    for _, pin in pairs(worldMapPinPool) do
        pin:Hide()
    end
end

local function GetOrCreateWorldMapPin(index)
    if worldMapPinPool[index] then
        return worldMapPinPool[index]
    end

    local canvas = WorldMapFrame.ScrollContainer.Child
    local pin = CreateFrame("Button", nil, canvas)
    pin:SetSize(14, 14)
    pin:SetFrameStrata("HIGH")
    pin:RegisterForClicks("RightButtonUp")
    pin:Hide()

    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()

    pin:SetScript("OnEnter", function(self)
        if not self.nodeData then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.nodeData.name or "Unknown", 1, 1, 1)
        local t = self.nodeData.type
        local typeName = t == "herb" and "草药" or (t == "airdrop" and "空投" or "矿石")
        GameTooltip:AddLine(typeName, 0.7, 0.7, 0.7)
        GameTooltip:AddLine("右键点击删除", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)

    pin:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    pin:SetScript("OnClick", function(self, button)
        if button == "RightButton" and self.nodeMapID and self.nodeIndex then
            RemoveNode(self.nodeMapID, self.nodeIndex)
            RefreshAllPins()
        end
    end)

    worldMapPinPool[index] = pin
    return pin
end

UpdateWorldMapPins = function()
    HideAllWorldMapPins()

    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end

    local mapID = WorldMapFrame:GetMapID()
    if not mapID then return end

    local nodes = db.nodes[mapID]
    if not nodes then return end

    local canvas = WorldMapFrame.ScrollContainer.Child
    local cWidth, cHeight = canvas:GetSize()
    if not cWidth or cWidth == 0 then return end

    local pinIndex = 0

    for i, node in ipairs(nodes) do
        if ShouldShowNode(node) then
            pinIndex = pinIndex + 1
            local isAirdrop = node.type == "airdrop"
            local size = isAirdrop and (db.settings.airdropWorldPinSize or 18) or (db.settings.worldPinSize or 14)
            local alpha = isAirdrop and (db.settings.airdropAlpha or 0.8) or (db.settings.worldAlpha or 0.6)
            local pin = GetOrCreateWorldMapPin(pinIndex)
            pin:SetSize(size, size)
            pin.icon:SetTexture(GetNodeIcon(node))
            pin.icon:SetAlpha(alpha)
            pin.nodeData = node
            pin.nodeMapID = mapID
            pin.nodeIndex = i
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", canvas, "TOPLEFT", node.x * cWidth, -node.y * cHeight)
            pin:Show()
        end
    end
end

local function RegisterWorldMapHook()
    if WorldMapFrame then
        hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
            if db then UpdateWorldMapPins() end
        end)
        WorldMapFrame:HookScript("OnShow", function()
            if db then UpdateWorldMapPins() end
        end)
    end
end

--------------------------------------------------------------------------------
-- Slash Command
--------------------------------------------------------------------------------
local function RegisterSlashCommand()
    SLASH_DODOGATHERMATE1 = "/dgm"
    SLASH_DODOGATHERMATE2 = "/dodogathermate"
    SlashCmdList["DODOGATHERMATE"] = function(msg)
        msg = (msg or ""):lower():trim()
        if msg == "clear" then
            local mapID = GetCurrentMapID()
            if mapID then
                ClearNodesForMap(mapID)
                RefreshAllPins()
                Print("已清空当前地图的采集记录。")
            end
        elseif msg == "clearall" then
            ClearAllNodes()
            RefreshAllPins()
            Print("已清空所有采集记录。")
        elseif msg == "status" then
            local totalNodes = 0
            for _, nodes in pairs(db.nodes) do
                totalNodes = totalNodes + #nodes
            end
            Print(string.format("草药学: %s | 采矿: %s | 已记录节点: %d",
                hasHerbalism and "|cff00ff00是|r" or "|cffff0000否|r",
                hasMining and "|cff00ff00是|r" or "|cffff0000否|r",
                totalNodes))
        else
            OpenSettings()
        end
    end
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------
local function Initialize()
    DodoGatherMateDB = CopyDefaults(DEFAULTS, DodoGatherMateDB)
    db = DodoGatherMateDB

    UpdateProfessions()

    CreateMinimapButton()
    CreateOptionsPanel()
    RegisterWorldMapHook()
    RegisterSlashCommand()

    local minimapUpdateFrame = CreateFrame("Frame")
    minimapUpdateFrame:SetScript("OnUpdate", function()
        if db then UpdateMinimapPins() end
    end)

    Print("已加载。输入 /dgm 打开设置。")
end

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
eventFrame:RegisterEvent("LOOT_OPENED")
eventFrame:RegisterEvent("SKILL_LINES_CHANGED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        Initialize()
    elseif event == "UNIT_SPELLCAST_START" then
        OnSpellCastStart(nil, nil, ...)
    elseif event == "LOOT_OPENED" then
        OnLootOpened()
    elseif event == "SKILL_LINES_CHANGED" then
        UpdateProfessions()
        RefreshAllPins()
    end
end)
