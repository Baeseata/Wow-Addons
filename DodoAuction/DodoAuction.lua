-- DodoAuction.lua
-- Track commodity 1% depth weighted average price over time (account-wide).
-- Right-click a bag item while the Auction House is open:
--   * If the item is already tracked, try to auto-post the clicked stack using the latest known unit price,
--     then select it in the panel, keep Blizzard's Sell view, search in background, and auto-record a fresh price.
--   * If the item is not tracked yet, just search it in the AH (manual record still available).

local ADDON_NAME = ...
local DA = CreateFrame("Frame")

-- =========================
-- Config
-- =========================
local PANEL_W = 460
local PANEL_H_EXTRA = 200
local ROW_H = 26
local ROW_POOL_MAX = 80
local MAX_POINTS = 100
local DEFAULT_RANGE_DAYS = 7
local CHART_H = 240
local AUTO_POST_TRACKED_RIGHT_CLICK = true
local AUTO_POST_DURATION = 3 -- 1/2/3 = 12/24/48h

-- =========================
-- DB
-- =========================
local function EnsureDB()
  if type(DodoAuctionDB) ~= "table" then DodoAuctionDB = {} end
  if type(DodoAuctionDB.items) ~= "table" then DodoAuctionDB.items = {} end
  if type(DodoAuctionDB.version) ~= "number" then DodoAuctionDB.version = 1 end
end

-- =========================
-- Helpers
-- =========================
local function Now()
  return time()
end

local function Money_GoldSilver(copper)
  if type(copper) ~= "number" then return "-" end
  copper = math.max(0, math.floor(copper + 0.5))
  local gold = math.floor(copper / 10000)
  local silver = math.floor((copper % 10000) / 100)
  return string.format("%dg %ds", gold, silver)
end

local function GetItemNameIcon(itemID)
  if not itemID then return nil, nil end

  local name = (C_Item and C_Item.GetItemNameByID) and C_Item.GetItemNameByID(itemID) or nil
  local icon = (C_Item and C_Item.GetItemIconByID) and C_Item.GetItemIconByID(itemID) or nil

  if not name then
    local n, _, _, _, _, _, _, _, _, tex = GetItemInfo(itemID)
    name = n
    icon = icon or tex
  end

  return name, icon
end

local function RequestItemLoad(itemID)
  if C_Item and C_Item.RequestLoadItemDataByID then
    C_Item.RequestLoadItemDataByID(itemID)
  end
end

local function GetReagentQuality(itemID)
  if not (C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo) then return nil end
  return C_TradeSkillUI.GetItemReagentQualityByItemInfo(("item:%d"):format(itemID))
end

local function NameWithStars(entry, itemID)
  local nm = (entry and entry.name) or ("item:" .. tostring(itemID))
  local q = entry and entry.quality
  local stars = (type(q) == "number" and q > 0) and (" " .. string.rep("★", q)) or ""
  return nm .. stars
end

local function SafeUTF8SortName(a, b)
  if a.name == b.name then return a.id < b.id end
  return (a.name or "") < (b.name or "")
end

local function EnsureEntry(itemID)
  EnsureDB()
  if not DodoAuctionDB.items[itemID] then
    DodoAuctionDB.items[itemID] = { records = {} }
  end
  local entry = DodoAuctionDB.items[itemID]
  entry.records = entry.records or {}

  if not entry.name or not entry.icon then
    RequestItemLoad(itemID)
    local n, ico = GetItemNameIcon(itemID)
    if n then entry.name = n end
    if ico then entry.icon = ico end
  end

  entry.quality = entry.quality or GetReagentQuality(itemID)
  return entry
end

-- =========================
-- Compute 1% cheapest weighted avg (loaded brackets only)
-- =========================
local function ComputeCheapestOnePercentAvg(itemID)
  if not (C_AuctionHouse and C_AuctionHouse.GetNumCommoditySearchResults) then return nil end

  local totalQty = (C_AuctionHouse.GetCommoditySearchResultsQuantity and C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID)) or 0
  totalQty = tonumber(totalQty) or 0
  if totalQty <= 0 then return nil, 0, 0 end

  local targetQty = math.ceil(totalQty * 0.01)
  if targetQty < 1 then targetQty = 1 end

  local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
  if n <= 0 then return nil, totalQty, targetQty end

  local used, sum = 0, 0
  for i = 1, n do
    local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    if info and info.unitPrice and info.quantity then
      local unitPrice = tonumber(info.unitPrice) or 0
      local qty = tonumber(info.quantity) or 0
      if unitPrice > 0 and qty > 0 then
        local need = targetQty - used
        if need <= 0 then break end
        local take = (qty >= need) and need or qty
        used = used + take
        sum = sum + unitPrice * take
        if used >= targetQty then break end
      end
    end
  end

  if used <= 0 then return nil, totalQty, targetQty end
  return (sum / used), totalQty, targetQty
end

local function HasEnoughLoadedDepthForOnePercent(itemID)
  if not (C_AuctionHouse and C_AuctionHouse.GetNumCommoditySearchResults) then return false end

  local totalQty = (C_AuctionHouse.GetCommoditySearchResultsQuantity and C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID)) or 0
  totalQty = tonumber(totalQty) or 0
  if totalQty <= 0 then return false end

  local targetQty = math.ceil(totalQty * 0.01)
  if targetQty < 1 then targetQty = 1 end

  local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
  if n <= 0 then return false end

  local loadedQty = 0
  for i = 1, n do
    local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    if info and info.quantity then
      loadedQty = loadedQty + (tonumber(info.quantity) or 0)
      if loadedQty >= targetQty then
        return true
      end
    end
  end

  return false
end

-- =========================
-- Trend (linear regression slope) on last <=5 points
-- =========================
local function ComputeSlope(records)
  if type(records) ~= "table" or #records < 2 then return 0 end
  local n = #records
  local sumX, sumY, sumXY, sumXX = 0, 0, 0, 0
  for i = 1, n do
    local x = tonumber(records[i].t) or 0
    local y = tonumber(records[i].p) or 0
    sumX = sumX + x
    sumY = sumY + y
    sumXY = sumXY + x * y
    sumXX = sumXX + x * x
  end
  local denom = n * sumXX - sumX * sumX
  if denom == 0 then return 0 end
  local slope = (n * sumXY - sumX * sumY) / denom
  if math.abs(slope) < 1e-12 then return 0 end
  return slope
end

-- =========================
-- Chart helpers
-- =========================
local function FilterByRange(records, days)
  if not records or #records == 0 then return {} end
  if not days then return records end
  local cutoff = Now() - days * 86400
  local out = {}
  for i = 1, #records do
    if (records[i].t or 0) >= cutoff then
      out[#out + 1] = records[i]
    end
  end
  return out
end

local function SampleByTime(records, maxPoints)
  local n = #records
  if n <= maxPoints then return records end
  if n <= 1 then return records end

  local tmin, tmax = records[1].t, records[n].t
  if not tmin or not tmax or tmax <= tmin then
    local out = {}
    for k = 1, maxPoints do
      local idx = math.floor((k - 1) * (n - 1) / (maxPoints - 1) + 1.5)
      idx = math.max(1, math.min(n, idx))
      out[#out + 1] = records[idx]
    end
    return out
  end

  local out, i, lastIdx = {}, 1, 0
  for k = 0, maxPoints - 1 do
    local targetT = tmin + (tmax - tmin) * (k / (maxPoints - 1))
    while i < n and records[i].t < targetT do
      i = i + 1
    end
    if i ~= lastIdx then
      out[#out + 1] = records[i]
      lastIdx = i
    end
  end
  return out
end

-- =========================
-- State
-- =========================
DA.state = {
  currentCommodityItemID = nil,
  selectedItemID = nil,
  rangeDays = DEFAULT_RANGE_DAYS,
  ordered = {},
  _chartRedrawScheduled = false,
}

local function ScheduleChartRedraw()
  if DA.state._chartRedrawScheduled then return end
  DA.state._chartRedrawScheduled = true
  C_Timer.After(0, function()
    DA.state._chartRedrawScheduled = false
    if DA.ui and DA.ui.panel and DA.ui.panel:IsShown() then
      DA:RefreshChart()
      DA:RefreshList()
    end
  end)
end

-- =========================
-- UI building blocks
-- =========================
local function CreateBackdropFrame(name, parent, w, h)
  local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
  f:SetSize(w, h)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  f:SetBackdropColor(0, 0, 0, 0.8)
  return f
end

local function GetVisibleRows()
  if not (DA.ui and DA.ui.rowsHost) then return 16 end
  local h = DA.ui.rowsHost:GetHeight() or 0
  local r = math.floor(h / ROW_H)
  if r < 1 then r = 1 end
  if r > ROW_POOL_MAX then r = ROW_POOL_MAX end
  return r
end

-- =========================
-- AH search helpers
-- =========================
local function MakeExactItemKey(itemID)
  if not (C_AuctionHouse and C_AuctionHouse.MakeItemKey) then return nil end
  local ok, itemKey = pcall(C_AuctionHouse.MakeItemKey, itemID)
  if ok then return itemKey end
  return nil
end

function DA:TrySendExactSearch(itemID)
  if not (C_AuctionHouse and C_AuctionHouse.SendSearchQuery) then return false end

  local itemKey = MakeExactItemKey(itemID)
  if not itemKey then return false end

  local ok = pcall(C_AuctionHouse.SendSearchQuery, itemKey, {}, false)
  return ok == true
end

function DA:SearchItemByName(name)
  if not name or name == "" then return false end
  if not AuctionHouseFrame then return false end

  local sb = AuctionHouseFrame.SearchBar
  if not sb then return false end

  local box = sb.SearchBox or sb.SearchBoxFrame or sb.SearchBox
  if box and box.SetText then
    box:SetText(name)
  else
    return false
  end

  if sb.SearchButton and sb.SearchButton.Click then
    sb.SearchButton:Click()
    return true
  end

  if box.GetScript then
    local f = box:GetScript("OnEnterPressed")
    if f then
      f(box)
      return true
    end
  end

  return false
end

function DA:RunCommoditySearch(itemID, keepCurrentTab)
  if not itemID then return end

  local entry = DodoAuctionDB and DodoAuctionDB.items and DodoAuctionDB.items[itemID] or nil
  if entry then
    EnsureEntry(itemID) -- refresh name/icon for tracked items
  end

  C_Timer.After(0, function()
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end

    if keepCurrentTab then
      -- Background search only: use API directly, don't navigate UI
      self:TrySendExactSearch(itemID)
      return
    end

    -- UI navigation: switch to Buy tab and search by name to drive AH UI
    if AuctionHouseFrameBuyTab and AuctionHouseFrameBuyTab.Click then
      AuctionHouseFrameBuyTab:Click()
    end

    local name = (entry and entry.name) or ((C_Item and C_Item.GetItemNameByID) and C_Item.GetItemNameByID(itemID) or nil)
    if name then
      self:SearchItemByName(name)
    end
  end)
end

function DA:GetPreferredPostUnitPrice(itemID)
  if not itemID then return nil end

  if self.state.currentCommodityItemID == itemID and HasEnoughLoadedDepthForOnePercent(itemID) then
    local avg = ComputeCheapestOnePercentAvg(itemID)
    if avg and avg > 0 then
      return math.floor(avg + 0.5)
    end
  end

  local entry = DodoAuctionDB and DodoAuctionDB.items and DodoAuctionDB.items[itemID] or nil
  local recs = entry and entry.records or nil
  if recs and #recs > 0 then
    local p = tonumber(recs[#recs].p) or 0
    if p > 0 then return math.floor(p + 0.5) end
  end

  return nil
end

local function CreateBagItemLocation(bag, slot)
  if ItemLocation and ItemLocation.CreateFromBagAndSlot then
    return ItemLocation:CreateFromBagAndSlot(bag, slot)
  end
  return nil
end

function DA:TryPostTrackedBagItem(bag, slot, itemID)
  if not AUTO_POST_TRACKED_RIGHT_CLICK then return false end
  if not itemID then return false end
  if not (DodoAuctionDB and DodoAuctionDB.items and DodoAuctionDB.items[itemID]) then return false end
  if not (C_AuctionHouse and C_AuctionHouse.PostCommodity) then return false end

  local itemLoc = CreateBagItemLocation(bag, slot)
  if not itemLoc then return false end

  local qty = 0
  if C_Item and C_Item.GetStackCount then
    qty = tonumber(C_Item.GetStackCount(itemLoc)) or 0
  end
  if qty <= 0 and C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    qty = (info and tonumber(info.stackCount)) or 0
  end
  if qty <= 0 then return false end

  local unitPrice = self:GetPreferredPostUnitPrice(itemID)
  if not unitPrice or unitPrice <= 0 then return false end

  local ok = pcall(C_AuctionHouse.PostCommodity, itemLoc, AUTO_POST_DURATION, qty, unitPrice)
  return ok == true
end

function DA:BeginBagRightClickFlow(itemID, bag, slot)
  if not itemID then return end
  EnsureDB()

  local tracked = DodoAuctionDB.items[itemID] ~= nil
  if tracked then
    EnsureEntry(itemID)
    self.state.selectedItemID = itemID
    self:RefreshList()
    self:RefreshChart()
    self:TryPostTrackedBagItem(bag, slot, itemID)

    -- 已追踪商品：保留出售页，同时后台搜索更新价格
    self:RunCommoditySearch(itemID, true)
  else
    -- 未追踪商品：完全交还给暴雪默认出售逻辑，不要切去购买页
  end
end

function DA:TryAutoRecord(itemID)
  if not itemID then return end
  -- Auto-record for ANY tracked item when search results are available
  if not DodoAuctionDB or not DodoAuctionDB.items or not DodoAuctionDB.items[itemID] then
    return
  end
  if not HasEnoughLoadedDepthForOnePercent(itemID) then return end

  self.state.currentCommodityItemID = itemID
  self:AutoRecordTracked(itemID)
end

-- =========================
-- Bag click hook
-- =========================
local GetBagItemCount
local MakeBagItemLocation

local function GetBagSlotFromButton(button)
  if not button then return nil, nil end

  local bag = button.GetBagID and button:GetBagID() or nil
  local slot = button.GetID and button:GetID() or nil

  if bag == nil and button.GetParent and button:GetParent() and button:GetParent().GetID then
    bag = button:GetParent():GetID()
  end

  return bag, slot
end

local function GetBagItemID(bag, slot)
  if bag == nil or slot == nil then return nil end

  if C_Container and C_Container.GetContainerItemID then
    return C_Container.GetContainerItemID(bag, slot)
  end

  if GetContainerItemID then
    return GetContainerItemID(bag, slot)
  end

  return nil
end

GetBagItemCount = function(bag, slot)
  if bag == nil or slot == nil then return 0 end

  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then
      return tonumber(info.stackCount or info.quantity or 0) or 0
    end
  end

  if GetContainerItemInfo then
    local _, count = GetContainerItemInfo(bag, slot)
    return tonumber(count) or 0
  end

  return 0
end

MakeBagItemLocation = function(bag, slot)
  if bag == nil or slot == nil then return nil end
  if not (ItemLocation and ItemLocation.CreateFromBagAndSlot) then return nil end
  return ItemLocation:CreateFromBagAndSlot(bag, slot)
end

function DA:EnsureBagClickHook()
  if self._bagClickHooked then return end
  self._bagClickHooked = true

  hooksecurefunc("ContainerFrameItemButton_OnClick", function(button, mouseButton)
    if mouseButton ~= "RightButton" then return end
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
    if not (DA.ui and DA.ui.panel and DA.ui.panel:IsShown()) then return end

    local bag, slot = GetBagSlotFromButton(button)
    local itemID = GetBagItemID(bag, slot)
    if not itemID then return end

    DA:BeginBagRightClickFlow(itemID, bag, slot)
  end)
end

-- =========================
-- UI: Ensure + Layout
-- =========================
function DA:ReanchorPanel()
  if not (self.ui and self.ui.panel and AuctionHouseFrame) then return end
  local h = AuctionHouseFrame:GetHeight()
  if type(h) ~= "number" or h <= 300 then return end

  local newH = (h - 28) + PANEL_H_EXTRA
  local maxH = (UIParent and UIParent.GetHeight and UIParent:GetHeight() - 40) or newH
  if newH > maxH then newH = maxH end
  self.ui.panel:SetHeight(newH)
end

local function InitRow(self, row, rowsHost, index)
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", rowsHost, "TOPLEFT", 6, -(index - 1) * ROW_H)
  row:SetPoint("TOPRIGHT", rowsHost, "TOPRIGHT", -4, -(index - 1) * ROW_H)
  row:RegisterForClicks("LeftButtonUp")

  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints(row)
  row.bg:SetColorTexture(1, 1, 1, 0.06)
  row.bg:Hide()

  row.searchBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.searchBtn:SetSize(44, 18)
  row.searchBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.searchBtn:SetText("搜索")
  row.searchBtn:SetScript("OnClick", function()
    if not row.itemID then return end
    local entry = DodoAuctionDB.items[row.itemID]
    if entry and entry.name then
      self.state.selectedItemID = row.itemID
      self:RefreshList()
      self:RefreshChart()
      self:RunCommoditySearch(row.itemID)
    end
  end)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(18, 18)
  row.icon:SetPoint("LEFT", row.searchBtn, "RIGHT", 6, 0)

  row.delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.delBtn:SetSize(44, 18)
  row.delBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row.delBtn:SetText("删除")
  row.delBtn:SetScript("OnClick", function()
    if not row.itemID then return end
    DodoAuctionDB.items[row.itemID] = nil
    if self.state.selectedItemID == row.itemID then self.state.selectedItemID = nil end
    self:RefreshList()
    self:RefreshChart()
  end)

  row.arrowFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.arrowFS:SetPoint("RIGHT", row.delBtn, "LEFT", -6, 0)
  row.arrowFS:SetWidth(20)
  row.arrowFS:SetJustifyH("CENTER")

  row.priceFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.priceFS:SetPoint("RIGHT", row.arrowFS, "LEFT", -6, 0)
  row.priceFS:SetJustifyH("RIGHT")
  row.priceFS:SetWidth(80)

  row.nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.nameFS:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.nameFS:SetPoint("RIGHT", row.priceFS, "LEFT", -6, 0)
  row.nameFS:SetJustifyH("LEFT")
  row.nameFS:SetMaxLines(1)
  row.nameFS:SetWordWrap(false)

  row:SetScript("OnClick", function()
    if row.itemID then
      self.state.selectedItemID = row.itemID
      self:RefreshList()
      self:RefreshChart()
    end
  end)
end

function DA:EnsureUI()
  if self.ui then return end

  if not AuctionHouseFrame then
    if UIParentLoadAddOn then UIParentLoadAddOn("Blizzard_AuctionHouseUI") end
  end
  if not AuctionHouseFrame then return end

  local panel = CreateBackdropFrame("DodoAuctionPanel", AuctionHouseFrame, PANEL_W, 540)
  panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 8, -14)
  panel:Hide()

  self.ui = { panel = panel }
  self:EnsureBagClickHook()

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
  title:SetText("DodoAuction")
  self.ui.title = title

  local cur = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cur:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  cur:SetText("当前商品：-")
  self.ui.curLabel = cur

  local recordBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  recordBtn:SetSize(90, 22)
  recordBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -10)
  recordBtn:SetText("记录")
  recordBtn:SetEnabled(false)
  recordBtn:SetScript("OnClick", function() self:OnRecordClick() end)
  self.ui.recordBtn = recordBtn

  local chartFrame = CreateBackdropFrame(nil, panel, PANEL_W - 24, CHART_H)
  chartFrame:ClearAllPoints()
  chartFrame:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 12)
  chartFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 12)
  chartFrame:SetHeight(CHART_H)
  chartFrame:SetBackdropColor(0, 0, 0, 0.45)
  self.ui.chartFrame = chartFrame

  local chartTitle = chartFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  chartTitle:SetPoint("TOPLEFT", chartFrame, "TOPLEFT", 10, -8)
  chartTitle:SetText("价格走势图")
  self.ui.chartTitle = chartTitle

  local RANGE_OPTIONS = {
    { text = "1天",  days = 1 },
    { text = "7天",  days = 7 },
    { text = "30天", days = 30 },
    { text = "全部", days = false }, -- false = 全部 (FilterByRange 把 falsy 当作不限范围)
  }

  local dd = CreateFrame("DropdownButton", "DodoAuctionRangeDropdown", chartFrame, "WowStyle1DropdownTemplate")
  dd:SetPoint("TOPRIGHT", chartFrame, "TOPRIGHT", -6, -2)
  dd:SetWidth(90)
  self.ui.rangeDropdown = dd

  dd:SetupMenu(function(_, rootDescription)
    for _, opt in ipairs(RANGE_OPTIONS) do
      rootDescription:CreateRadio(opt.text,
        function() return self.state.rangeDays == opt.days end,
        function()
          self.state.rangeDays = opt.days
          dd:GenerateMenu()
          self:RefreshChart()
        end)
    end
  end)
  dd:GenerateMenu()

  local plot = CreateFrame("Frame", nil, chartFrame)
  plot:SetPoint("TOPLEFT", chartFrame, "TOPLEFT", 12, -34)
  plot:SetPoint("BOTTOMRIGHT", chartFrame, "BOTTOMRIGHT", -12, 12)
  plot.lines, plot.points = {}, {}
  plot:HookScript("OnSizeChanged", ScheduleChartRedraw)
  self.ui.plot = plot

  local listFrame = CreateBackdropFrame(nil, panel, PANEL_W - 24, 1)
  listFrame:SetBackdropColor(0, 0, 0, 0.45)
  listFrame:ClearAllPoints()
  listFrame:SetPoint("TOPLEFT", cur, "BOTTOMLEFT", -2, -10)
  listFrame:SetPoint("BOTTOMLEFT", chartFrame, "TOPLEFT", 0, 10)
  listFrame:SetPoint("BOTTOMRIGHT", chartFrame, "TOPRIGHT", 0, 10)
  self.ui.listFrame = listFrame

  local listTitle = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  listTitle:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 10, -8)
  listTitle:SetText("已追踪商品（点击行查看图表）")

  local rowsHost = CreateFrame("Frame", nil, listFrame)
  rowsHost:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -24)
  rowsHost:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -28, 6)
  rowsHost:SetClipsChildren(true)
  rowsHost:HookScript("OnSizeChanged", ScheduleChartRedraw)
  self.ui.rowsHost = rowsHost

  local scroll = CreateFrame("ScrollFrame", "DodoAuctionScrollFrame", listFrame, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -24)
  scroll:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", 0, 6)
  scroll:EnableMouse(false)
  scroll:SetScript("OnVerticalScroll", function(_, offset)
    FauxScrollFrame_OnVerticalScroll(scroll, offset, ROW_H, function() self:RefreshList() end)
  end)
  self.ui.scroll = scroll

  local sb = _G["DodoAuctionScrollFrameScrollBar"]
  self.ui.scrollBar = sb
  if sb then
    sb:ClearAllPoints()
    sb:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -6, -24)
    sb:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -6, 6)
    sb:SetFrameLevel(listFrame:GetFrameLevel() + 50)
    sb:SetAlpha(1)
  end

  listFrame:EnableMouseWheel(true)
  listFrame:SetScript("OnMouseWheel", function(_, delta)
    local px = (scroll:GetVerticalScroll() or 0) - delta * (ROW_H * 3)
    if px < 0 then px = 0 end
    FauxScrollFrame_OnVerticalScroll(scroll, px, ROW_H, function() self:RefreshList() end)
  end)

  self.ui.rows = {}
  for i = 1, math.min(20, ROW_POOL_MAX) do
    local row = CreateFrame("Button", nil, rowsHost)
    InitRow(self, row, rowsHost, i)
    self.ui.rows[i] = row
  end

  panel:SetScript("OnShow", function()
    self:ReanchorPanel()
    self:RefreshRecordButton()
    self:RefreshList()
    self:RefreshChart()
  end)

  AuctionHouseFrame:HookScript("OnSizeChanged", function()
    self:ReanchorPanel()
    ScheduleChartRedraw()
  end)
end

-- =========================
-- List: rebuild + refresh
-- =========================
function DA:RebuildOrdered()
  wipe(self.state.ordered)
  for itemID, entry in pairs(DodoAuctionDB.items) do
    local id = tonumber(itemID)
    if id then
      if not entry.name or not entry.icon then
        RequestItemLoad(id)
        local n, ico = GetItemNameIcon(id)
        if n then entry.name = n end
        if ico then entry.icon = ico end
      end
      entry.quality = entry.quality or GetReagentQuality(id)
      self.state.ordered[#self.state.ordered + 1] = { id = id, name = entry.name or "" }
    end
  end
  table.sort(self.state.ordered, SafeUTF8SortName)
end

function DA:RefreshList()
  if not self.ui then return end

  self:RebuildOrdered()
  local ordered = self.state.ordered
  local numItems = #ordered
  local visible = GetVisibleRows()

  local have = #self.ui.rows
  if visible > have then
    local need = math.min(visible, ROW_POOL_MAX)
    for i = have + 1, need do
      local row = CreateFrame("Button", nil, self.ui.rowsHost)
      InitRow(self, row, self.ui.rowsHost, i)
      self.ui.rows[i] = row
    end
  end

  FauxScrollFrame_Update(self.ui.scroll, numItems, visible, ROW_H)

  local sb = self.ui.scrollBar
  if sb then
    if numItems > visible then sb:Show() else sb:Hide() end
  end

  local offset = FauxScrollFrame_GetOffset(self.ui.scroll) or 0

  for i = 1, #self.ui.rows do
    local row = self.ui.rows[i]
    if i > visible then
      row.itemID = nil
      row.bg:Hide()
      row:Hide()
    else
      local idx = i + offset
      local it = ordered[idx]
      if it then
        local itemID = it.id
        local entry = DodoAuctionDB.items[itemID]
        local recs = entry and entry.records or nil
        local lastPrice = nil

        row.itemID = itemID
        if self.state.selectedItemID == itemID then row.bg:Show() else row.bg:Hide() end
        row.icon:SetTexture(entry and entry.icon or nil)
        row.nameFS:SetText(NameWithStars(entry, itemID))

        if recs and #recs > 0 then
          lastPrice = recs[#recs].p
        end
        row.priceFS:SetText(lastPrice and Money_GoldSilver(lastPrice) or "-")

        row.arrowFS:SetText("")
        row.arrowFS:SetTextColor(1, 1, 1, 1)
        if recs and #recs >= 2 then
          local m = math.min(5, #recs)
          local slice = {}
          for k = #recs - m + 1, #recs do
            slice[#slice + 1] = recs[k]
          end
          local slope = ComputeSlope(slice)
          if slope > 0 then
            row.arrowFS:SetText("▲")
            row.arrowFS:SetTextColor(0.2, 1.0, 0.2, 1)
          elseif slope < 0 then
            row.arrowFS:SetText("▼")
            row.arrowFS:SetTextColor(1.0, 0.2, 0.2, 1)
          end
        end

        row:Show()
      else
        row.itemID = nil
        row.bg:Hide()
        row:Hide()
      end
    end
  end
end

-- =========================
-- Chart rendering
-- =========================
local function PlotClear(plot)
  for _, ln in ipairs(plot.lines) do ln:Hide() end
  for _, pt in ipairs(plot.points) do pt:Hide() end
end

local function EnsureLines(plot, n)
  while #plot.lines < n do
    local ln = plot:CreateLine(nil, "ARTWORK")
    ln:SetThickness(2)
    ln:SetColorTexture(1, 1, 1, 0.9)
    plot.lines[#plot.lines + 1] = ln
  end
end

local function EnsurePoints(plot, n)
  while #plot.points < n do
    local b = CreateFrame("Button", nil, plot)
    b:SetSize(10, 10)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints(b)
    b.tex:SetColorTexture(1, 0.9, 0.2, 1)
    b:Hide()
    plot.points[#plot.points + 1] = b
  end
end

function DA:RefreshChart()
  if not (self.ui and self.ui.plot) then return end
  local plot = self.ui.plot
  PlotClear(plot)

  local itemID = self.state.selectedItemID
  if not itemID then
    self.ui.chartTitle:SetText("价格走势图")
    return
  end

  local entry = DodoAuctionDB.items[itemID]
  local recs = entry and entry.records or nil
  if not recs or #recs == 0 then
    self.ui.chartTitle:SetText("价格走势图 - 无数据")
    return
  end

  local filtered = FilterByRange(recs, self.state.rangeDays)
  if #filtered == 0 then
    self.ui.chartTitle:SetText("价格走势图 - 该范围内无数据")
    return
  end

  local sampled = SampleByTime(filtered, MAX_POINTS)
  local tmin, tmax = sampled[1].t, sampled[#sampled].t
  local pmin, pmax = sampled[1].p, sampled[1].p
  for i = 1, #sampled do
    local p = sampled[i].p
    if p < pmin then pmin = p end
    if p > pmax then pmax = p end
  end

  self.ui.chartTitle:SetText("价格走势图 - " .. NameWithStars(entry, itemID))

  local w, h = plot:GetWidth(), plot:GetHeight()
  if not (w and h and w > 10 and h > 10) then
    ScheduleChartRedraw()
    return
  end

  local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
  end

  local function Xoff(t)
    local x
    if tmax == tmin then
      x = w * 0.5
    else
      x = (t - tmin) / (tmax - tmin) * w
    end
    return Clamp(x, 0, w)
  end

  local function Yoff(p)
    local y
    if pmax == pmin then
      y = h * 0.5
    else
      local v = (p - pmin) / (pmax - pmin)
      y = (1 - v) * h
    end
    y = Clamp(y, 0, h)
    return -y
  end

  EnsureLines(plot, math.max(0, #sampled - 1))
  for i = 2, #sampled do
    local ln = plot.lines[i - 1]
    ln:Show()
    ln:SetStartPoint("TOPLEFT", plot, Xoff(sampled[i - 1].t), Yoff(sampled[i - 1].p))
    ln:SetEndPoint("TOPLEFT", plot, Xoff(sampled[i].t), Yoff(sampled[i].p))
  end

  EnsurePoints(plot, #sampled)
  for i = 1, #sampled do
    local pt = plot.points[i]
    pt:Show()
    pt:ClearAllPoints()
    pt:SetPoint("TOPLEFT", plot, "TOPLEFT", Xoff(sampled[i].t) - 5, Yoff(sampled[i].p) - 5)
    pt.tex:SetColorTexture(1, 0.9, 0.2, 1)

    pt:SetScript("OnEnter", function()
      GameTooltip:SetOwner(pt, "ANCHOR_CURSOR")
      GameTooltip:ClearLines()
      GameTooltip:AddLine(NameWithStars(entry, itemID), 1, 1, 1)
      GameTooltip:AddLine(date("%Y-%m-%d %H:%M", sampled[i].t), 0.8, 0.8, 0.8)
      GameTooltip:AddLine("平均价: " .. Money_GoldSilver(sampled[i].p), 1, 1, 1)
      GameTooltip:AddLine("总数量: " .. tostring(sampled[i].q or 0), 1, 1, 1)
      GameTooltip:Show()
    end)
    pt:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
end

-- =========================
-- Record flow
-- =========================
function DA:RefreshRecordButton()
  if not self.ui then return end
  local itemID = self.state.currentCommodityItemID
  if not itemID then
    self.ui.recordBtn:SetEnabled(false)
    self.ui.curLabel:SetText("当前商品：-")
    return
  end

  -- Only update existing entries; never create new ones here
  local entry = DodoAuctionDB and DodoAuctionDB.items and DodoAuctionDB.items[itemID] or nil
  if entry then
    EnsureEntry(itemID) -- refresh name/icon/quality for tracked items
  end

  local displayName
  if entry then
    displayName = NameWithStars(entry, itemID)
  else
    local n = (C_Item and C_Item.GetItemNameByID) and C_Item.GetItemNameByID(itemID) or nil
    displayName = n or ("item:" .. tostring(itemID))
  end
  self.ui.curLabel:SetText("当前商品：" .. displayName)

  local totalQty = (C_AuctionHouse.GetCommoditySearchResultsQuantity and C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID)) or 0
  totalQty = tonumber(totalQty) or 0
  local num = (C_AuctionHouse.GetNumCommoditySearchResults and C_AuctionHouse.GetNumCommoditySearchResults(itemID)) or 0

  if entry or totalQty <= 0 or num <= 0 then
    -- Already tracked (auto-records), or no data available
    self.ui.recordBtn:SetEnabled(false)
  else
    -- New untracked item with data available: allow manual add
    self.ui.recordBtn:SetEnabled(true)
  end
end

-- Manual "记录" button: add a NEW item to the tracking list with its first data point
function DA:OnRecordClick()
  local itemID = self.state.currentCommodityItemID
  if not itemID then return end

  -- Only for untracked items (tracked items auto-record)
  if DodoAuctionDB and DodoAuctionDB.items and DodoAuctionDB.items[itemID] then return end

  local avg, totalQty = ComputeCheapestOnePercentAvg(itemID)
  if not avg then
    self:RefreshRecordButton()
    return
  end

  local entry = EnsureEntry(itemID)
  entry.records[#entry.records + 1] = {
    t = Now(),
    p = math.floor(avg + 0.5),
    q = totalQty or 0,
  }

  self.state.selectedItemID = itemID
  self:RefreshRecordButton()
  self:RefreshList()
  self:RefreshChart()
end

-- Auto-record a data point for an already-tracked item
function DA:AutoRecordTracked(itemID)
  if not itemID then return end
  if not (DodoAuctionDB and DodoAuctionDB.items and DodoAuctionDB.items[itemID]) then return end

  local avg, totalQty = ComputeCheapestOnePercentAvg(itemID)
  if not avg then return end

  local entry = EnsureEntry(itemID)
  entry.records[#entry.records + 1] = {
    t = Now(),
    p = math.floor(avg + 0.5),
    q = totalQty or 0,
  }

  self:RefreshList()
  self:RefreshChart()
end

-- =========================
-- Events
-- =========================
DA:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    if (...) == ADDON_NAME then
      EnsureDB()
    end
    return
  end

  if event == "AUCTION_HOUSE_SHOW" then
    self:EnsureUI()
    if self.ui and self.ui.panel then
      self.ui.panel:Show()
      self:ReanchorPanel()
      self:RefreshRecordButton()
      self:RefreshList()
      self:RefreshChart()
    end
    return
  end

  if event == "AUCTION_HOUSE_CLOSED" then
    self.state.currentCommodityItemID = nil
    if self.ui and self.ui.panel then self.ui.panel:Hide() end
    return
  end

  if event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
    local itemID = ...
    if type(itemID) == "number" and itemID > 0 then
      self.state.currentCommodityItemID = itemID
    else
      self.state.currentCommodityItemID = nil
    end
    self:RefreshRecordButton()
    self:TryAutoRecord(itemID)
    return
  end

  if event == "GET_ITEM_INFO_RECEIVED" then
    local itemID = ...
    if type(itemID) == "number" and DodoAuctionDB and DodoAuctionDB.items and DodoAuctionDB.items[itemID] then
      local entry = EnsureEntry(itemID)
      if self.state.selectedItemID == itemID and self.ui and self.ui.panel and self.ui.panel:IsShown() then
        self.ui.curLabel:SetText("当前商品：" .. NameWithStars(entry, itemID))
        self:RefreshList()
        self:RefreshChart()
      end
    end
    return
  end

  if event == "BAG_UPDATE_DELAYED" then
    if self.ui and self.ui.panel and self.ui.panel:IsShown() then
      self:RefreshList()
      self:RefreshChart()
      self:RefreshRecordButton()
    end
    return
  end
end)

DA:RegisterEvent("ADDON_LOADED")
DA:RegisterEvent("AUCTION_HOUSE_SHOW")
DA:RegisterEvent("AUCTION_HOUSE_CLOSED")
DA:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
DA:RegisterEvent("COMMODITY_SEARCH_RESULTS_ADDED")
DA:RegisterEvent("GET_ITEM_INFO_RECEIVED")
DA:RegisterEvent("BAG_UPDATE_DELAYED")
