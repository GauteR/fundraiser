-- Target page: a page inside the shell window (UI/Window.lua) for the donation-target
-- character. Scans the bags, groups stacks into Auction / Vendor / Needs price
-- (Domain/TargetView.lua) and acts on one selected stack at a time.
Fundraiser = Fundraiser or {}
Fundraiser.UI = Fundraiser.UI or {}

local Target = {}
Fundraiser.UI.Target = Target

-- Same margins, card gap and padding as the Home and Ledger pages.
local PANEL_W = 620
local MARGIN = 16
local CARD_GAP = 10
local CARD_PAD = 10
local CARD_W = PANEL_W - 2 * MARGIN
local ROWS = 10
local ROW_H = 18
local LIST_TOP = -28
local LIST_CARD_H = -LIST_TOP + ROWS * ROW_H + 10
local DETAIL_CARD_H = 150
local LIST_W = CARD_W - CARD_PAD - 34
-- Opening or closing the auction house / a vendor changes what the bulk buttons may do.
local WINDOW_EVENTS = { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "MERCHANT_SHOW", "MERCHANT_CLOSED" }
local COLOR_HEADER = { 1, 0.82, 0 }
local COLOR_SELECTED = { 1, 0.82, 0, 0.22 }

local function money(copper)
  if copper == nil then
    return "-"
  end
  return Fundraiser.FormatCopper(copper)
end

local function TV()
  return Fundraiser.Domain.TargetView
end

-- Flat list the scroll frame renders: a header per non-empty group, then its stacks.
local function buildItems(view)
  local items = {}
  local function section(group, headerText)
    local g = view.groups[group]
    if #g.entries == 0 then
      return
    end
    items[#items + 1] = { type = "header", text = headerText }
    for _, entry in ipairs(g.entries) do
      items[#items + 1] = { type = "entry", entry = entry }
    end
  end
  local g = view.groups
  section("auction", Fundraiser:T("TARGET_GROUP_AUCTION_FMT", #g.auction.entries, money(g.auction.total)))
  section("vendor", Fundraiser:T("TARGET_GROUP_VENDOR_FMT", #g.vendor.entries, money(g.vendor.total)))
  section("price", Fundraiser:T("TARGET_GROUP_PRICE_FMT", #g.price.entries))
  return items
end

-- Inline status text for an action result (reason keys come from AuctionPost).
local function statusText(key, a, b)
  if key == "CHAT_TARGET_POSTED" then
    return Fundraiser:T(key, tostring(a), money(b))
  end
  return Fundraiser:T(key)
end

function Target:Attach(shell)
  if self.frame then
    return self.frame
  end
  local Window = Fundraiser.UI.Window
  local f = CreateFrame("Frame", "FundraiserTargetPanel", shell)
  f:SetPoint("TOPLEFT", shell, "TOPLEFT", Window.NAV_W, -Window.HEADER_H)
  f:SetPoint("BOTTOMRIGHT", 0, 0)
  f:Hide()

  -- List card: group headers and stacks, click to select.
  local card = Window.MakeCard(f, "FundraiserTargetListCard", CARD_W, LIST_CARD_H)
  card:SetPoint("TOPLEFT", MARGIN, -34)
  card.title:SetText(Fundraiser:T("CARD_TARGET_STACKS"))

  local scroll = CreateFrame("ScrollFrame", "FundraiserTargetScroll", card, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", CARD_PAD, LIST_TOP)
  scroll:SetPoint("BOTTOMRIGHT", -34, 10)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, function()
      Target:UpdateRows()
    end)
  end)
  f.scroll = scroll

  f.rows = {}
  for i = 1, ROWS do
    local r = CreateFrame("Button", nil, card)
    r:SetSize(LIST_W, ROW_H)
    r:SetPoint("TOPLEFT", CARD_PAD, LIST_TOP - (i - 1) * ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(0, 0, 0, 0)
    r.value = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.value:SetPoint("RIGHT", -4, 0)
    r.value:SetWidth(120)
    r.value:SetJustifyH("RIGHT")
    r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 4, 0)
    r.text:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r:SetScript("OnClick", function(self)
      if self.entry then
        Target:Select(self.entry.key)
      end
    end)
    f.rows[i] = r
  end

  -- Detail card: the selected stack, manual unit price, actions.
  local detail = Window.MakeCard(f, "FundraiserTargetDetailCard", CARD_W, DETAIL_CARD_H)
  detail:SetPoint("TOPLEFT", MARGIN, -(34 + LIST_CARD_H + CARD_GAP))
  detail.title:SetText(Fundraiser:T("CARD_TARGET_SELECTED"))

  f.detail = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.detail:SetPoint("TOPLEFT", CARD_PAD, -28)
  f.detail:SetWidth(CARD_W - 2 * CARD_PAD)
  f.detail:SetJustifyH("LEFT")
  f.detail:SetJustifyV("TOP")
  f.detail:SetWordWrap(true)

  local priceLabel = detail:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  priceLabel:SetPoint("BOTTOMLEFT", CARD_PAD, 14)
  priceLabel:SetText(Fundraiser:T("TARGET_MANUAL_PRICE"))
  local price = CreateFrame("EditBox", "FundraiserTargetManualPrice", detail, "InputBoxTemplate")
  price:SetSize(100, 20)
  price:SetPoint("LEFT", priceLabel, "RIGHT", 10, 0)
  price:SetAutoFocus(false)
  f.manualPrice = price

  local vendorBtn = CreateFrame("Button", "FundraiserTargetVendor", detail, "UIPanelButtonTemplate")
  vendorBtn:SetSize(100, 24)
  vendorBtn:SetPoint("BOTTOMRIGHT", -CARD_PAD, 10)
  vendorBtn:SetText(Fundraiser:T("BTN_VENDOR"))
  vendorBtn:SetScript("OnClick", function()
    Target:Act("vendor")
  end)
  f.vendorBtn = vendorBtn

  local postBtn = CreateFrame("Button", "FundraiserTargetPost", detail, "UIPanelButtonTemplate")
  postBtn:SetSize(100, 24)
  postBtn:SetPoint("RIGHT", vendorBtn, "LEFT", -8, 0)
  postBtn:SetText(Fundraiser:T("BTN_POST_AH"))
  postBtn:SetScript("OnClick", function()
    Target:Act("ah")
  end)
  f.postBtn = postBtn

  -- Skip: leaves the selected stack out of Post all / Sell all (this session only).
  local skipBtn = CreateFrame("Button", "FundraiserTargetSkip", detail, "UIPanelButtonTemplate")
  skipBtn:SetSize(90, 24)
  skipBtn:SetPoint("RIGHT", postBtn, "LEFT", -8, 0)
  skipBtn:SetText(Fundraiser:T("BTN_SKIP"))
  skipBtn:SetScript("OnClick", function()
    Target:ToggleSkip()
  end)
  f.skipBtn = skipBtn

  -- Bulk actions under the cards. Both confirm first and stop on the first failure.
  local bulkY = -(34 + LIST_CARD_H + CARD_GAP + DETAIL_CARD_H + 8)
  local postAll = CreateFrame("Button", "FundraiserTargetPostAll", f, "UIPanelButtonTemplate")
  postAll:SetSize(170, 24)
  postAll:SetPoint("TOPLEFT", MARGIN, bulkY)
  postAll:SetScript("OnClick", function()
    Target:BulkClick("auction")
  end)
  f.postAllBtn = postAll
  local sellAll = CreateFrame("Button", "FundraiserTargetSellAll", f, "UIPanelButtonTemplate")
  sellAll:SetSize(170, 24)
  sellAll:SetPoint("LEFT", postAll, "RIGHT", 8, 0)
  sellAll:SetScript("OnClick", function()
    Target:BulkClick("vendor")
  end)
  f.sellAllBtn = sellAll

  -- Inline result of the last action (chat gets the same message from AuctionPost).
  f.status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.status:SetPoint("TOPLEFT", MARGIN, bulkY - 32)
  f.status:SetWidth(CARD_W)
  f.status:SetJustifyH("LEFT")

  -- Items moved or looted while the page is open show up without a manual refresh.
  f:SetScript("OnShow", function(self)
    self:RegisterEvent("BAG_UPDATE_DELAYED")
    for _, e in ipairs(WINDOW_EVENTS) do
      self:RegisterEvent(e)
    end
  end)
  f:SetScript("OnHide", function(self)
    self:UnregisterEvent("BAG_UPDATE_DELAYED")
    for _, e in ipairs(WINDOW_EVENTS) do
      self:UnregisterEvent(e)
    end
  end)
  f:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE_DELAYED" then
      Target:Refresh()
    else
      Target:UpdateBulk()
    end
  end)

  self.skipped = {}
  self.items = {}
  self.flat = {}
  self.selectedKey = nil
  self.selectedIndex = 0
  self.frame = f
  return f
end

function Target:Selected()
  return self.flat[self.selectedIndex]
end

function Target:Select(key)
  for i, entry in ipairs(self.flat) do
    if entry.key == key then
      self.selectedIndex = i
      self.selectedKey = key
      self:UpdateRows()
      self:ShowSelected()
      return
    end
  end
end

function Target:UpdateRows()
  local f = self.frame
  if not f then
    return
  end
  FauxScrollFrame_Update(f.scroll, #self.items, ROWS, ROW_H)
  local offset = FauxScrollFrame_GetOffset(f.scroll)
  for i = 1, ROWS do
    local r = f.rows[i]
    local item = self.items[offset + i]
    r.entry = nil
    if not item then
      r:Hide()
    elseif item.type == "header" then
      r.text:SetText(item.text)
      r.text:SetTextColor(COLOR_HEADER[1], COLOR_HEADER[2], COLOR_HEADER[3])
      r.value:SetText("")
      r.bg:SetColorTexture(1, 1, 1, 0.06)
      r:Show()
    else
      local entry = item.entry
      local row = entry.row
      r.entry = entry
      local mark = ""
      if entry.skipped then
        mark = Fundraiser:T("TARGET_MARK_SKIPPED")
      elseif entry.belowMin then
        mark = Fundraiser:T("TARGET_MARK_BELOW_MIN")
      end
      r.text:SetText(string.format("%s x%d%s", row.name or "?", row.count or 1, mark))
      r.text:SetTextColor(1, 1, 1)
      r.value:SetText(money(entry.value))
      if entry.key == self.selectedKey then
        r.bg:SetColorTexture(COLOR_SELECTED[1], COLOR_SELECTED[2], COLOR_SELECTED[3], COLOR_SELECTED[4])
      else
        r.bg:SetColorTexture(0, 0, 0, 0)
      end
      r:Show()
    end
  end
end

function Target:ShowSelected()
  local f = self.frame
  local entry = self:Selected()
  if not entry then
    f.detail:SetText(#self.flat == 0 and Fundraiser:T("TARGET_EMPTY") or Fundraiser:T("TARGET_SELECT_HINT"))
    f.manualPrice:SetText("")
    f.postBtn:Disable()
    f.vendorBtn:Disable()
    f.skipBtn:Disable()
    return
  end
  local row = entry.row
  f.detail:SetText(Fundraiser:T(
    "TARGET_DETAIL_FMT",
    row.name or "?",
    tostring(row.count),
    money(row.vendorTotal),
    money(row.ahUnit and (row.ahUnit * row.count) or nil),
    money(row.ahNet),
    row.source or "?",
    Fundraiser:T("TARGET_ADVICE_" .. string.upper(row.advice or "manual"))
  ))
  f.manualPrice:SetText(row.ahUnit and tostring(row.ahUnit) or "")
  f.skipBtn:SetText(Fundraiser:T(entry.skipped and "BTN_INCLUDE" or "BTN_SKIP"))
  if entry.group == "price" then
    f.skipBtn:Disable()
  else
    f.skipBtn:Enable()
  end
  if row.auctionable then
    f.postBtn:Enable()
  else
    f.postBtn:Disable()
  end
  if row.vendorUnit then
    f.vendorBtn:Enable()
  else
    f.vendorBtn:Disable()
  end
end

-- Rescan the bags and rebuild the lists; the selection follows its stack when it is still there.
function Target:Refresh()
  local f = self.frame
  if not f then
    return
  end
  if not Fundraiser:CanOpenTargetUi() then
    self.items, self.flat, self.selectedIndex, self.selectedKey = {}, {}, 0, nil
    self.view = TV().Build({}, { skipped = self.skipped })
    self:UpdateRows()
    self:ShowSelected()
    self:UpdateBulk()
    return
  end
  local rows = Fundraiser.Adapters.BagAssist:Scan()
  local view = TV().Build(rows, { skipped = self.skipped })
  self.view = view
  self.items = buildItems(view)
  self.flat = TV().Flatten(view)

  local found
  for i, entry in ipairs(self.flat) do
    if entry.key == self.selectedKey then
      found = i
      break
    end
  end
  self.selectedIndex = found or TV().Clamp(self.selectedIndex, #self.flat)
  local selected = self.flat[self.selectedIndex]
  self.selectedKey = selected and selected.key or nil

  self:UpdateRows()
  self:ShowSelected()
  self:UpdateBulk()
end

-- Act on the selected stack ("ah" or "vendor"); the result shows inline and goes to chat.
function Target:Act(action)
  local entry = self:Selected()
  if not entry then
    return
  end
  local manual = tonumber(self.frame.manualPrice:GetText())
  local ok, key, a, b = Fundraiser.Adapters.AuctionPost:HandleRow(entry.row, action, manual)
  if key then
    self.frame.status:SetText(statusText(key, a, b))
  end
  -- BAG_UPDATE_DELAYED rescans when the bag actually changes.
end

function Target:ToggleSkip()
  local entry = self:Selected()
  if not entry or entry.group == "price" then
    return
  end
  self.skipped[entry.key] = (not entry.skipped) or nil
  self:Refresh()
end

local function windowsOpen()
  local AP = Fundraiser.Adapters.AuctionPost
  return { ahOpen = AP.IsAuctionHouseOpen(), merchantOpen = AP.IsMerchantOpen() }
end

-- Button captions and enabled state from the current view and any running Post all.
function Target:UpdateBulk()
  local f = self.frame
  if not f or not self.view then
    return
  end
  local BP = Fundraiser.Domain.BulkPlan
  local env = windowsOpen()
  local post = BP.Describe(self.view, "auction", env)
  if BP.Progress(self.postQueue) == "running" then
    f.postAllBtn:SetText(Fundraiser:T("BTN_POST_NEXT_FMT", self.postQueue:Remaining()))
    f.postAllBtn:Enable()
  else
    f.postAllBtn:SetText(Fundraiser:T("BTN_POST_ALL_FMT", post.count))
    if post.canRun then
      f.postAllBtn:Enable()
    else
      f.postAllBtn:Disable()
    end
  end
  local sell = BP.Describe(self.view, "vendor", env)
  f.sellAllBtn:SetText(Fundraiser:T("BTN_SELL_ALL_FMT", sell.count))
  if sell.canRun then
    f.sellAllBtn:Enable()
  else
    f.sellAllBtn:Disable()
  end
end

-- A step re-checks the slot first: bags may have changed since the scan.
local function stepFor(group)
  local AP = Fundraiser.Adapters.AuctionPost
  return function(entry)
    local row = entry.row
    local info = C_Container.GetContainerItemInfo(row.bag, row.slot)
    if not info or info.itemID ~= row.itemId then
      return false, "CHAT_TARGET_ITEM_NOT_IN_BAGS"
    end
    if group == "auction" then
      return AP:PostStack(row, row.ahUnit)
    end
    return AP:VendorStack(row)
  end
end

local function confirm(text, onAccept)
  if StaticPopupDialogs and StaticPopup_Show then
    StaticPopupDialogs["FUNDRAISER_TARGET_BULK"] = {
      text = "%s",
      button1 = YES or ACCEPT or "Yes",
      button2 = NO or CANCEL or "No",
      OnAccept = onAccept,
      timeout = 0,
      whileDead = 1,
      hideOnEscape = 1,
      preferredIndex = 3,
    }
    StaticPopup_Show("FUNDRAISER_TARGET_BULK", text)
    return
  end
  onAccept()
end

-- Post all / Sell all button. Posting needs a click per stack (hardware event assumed), so the
-- first click confirms and posts one; further clicks post the next. Vendor sells in one go.
function Target:BulkClick(group)
  local BP = Fundraiser.Domain.BulkPlan
  local f = self.frame
  if group == "auction" and BP.Progress(self.postQueue) == "running" then
    self:RunPost()
    return
  end
  local d = BP.Describe(self.view, group, windowsOpen())
  if not d.canRun then
    f.status:SetText(Fundraiser:T(d.blockKey))
    return
  end
  local entries = TV().BulkEntries(self.view, group)
  local key = group == "auction" and "TARGET_CONFIRM_POST_FMT" or "TARGET_CONFIRM_SELL_FMT"
  confirm(Fundraiser:T(key, d.count, money(d.total)), function()
    local queue = Fundraiser.Domain.ActionQueue.New(entries, stepFor(group))
    if group == "auction" then
      self.postQueue = queue
      self:RunPost()
    else
      self:RunSell(queue)
    end
  end)
end

local function stoppedText(queue, reasonKey)
  return Fundraiser:T("TARGET_BULK_STOPPED_FMT", queue:Done(), queue:Total(), Fundraiser:T(reasonKey))
end

function Target:RunPost()
  local queue = self.postQueue
  local ok, reason = queue:Next()
  local f = self.frame
  if not ok then
    f.status:SetText(stoppedText(queue, reason))
  elseif queue:Finished() then
    f.status:SetText(Fundraiser:T("TARGET_BULK_DONE_FMT", queue:Done()))
  else
    f.status:SetText(Fundraiser:T("TARGET_BULK_PROGRESS_FMT", queue:Done(), queue:Total(), queue:Remaining()))
  end
  self:UpdateBulk()
end

function Target:RunSell(queue)
  local f = self.frame
  while queue:Remaining() > 0 do
    local ok, reason = queue:Next()
    if not ok then
      f.status:SetText(stoppedText(queue, reason))
      self:UpdateBulk()
      return
    end
  end
  f.status:SetText(Fundraiser:T("TARGET_BULK_DONE_FMT", queue:Done()))
  self:UpdateBulk()
end

-- Called by the shell when the page opens.
function Target:Open()
  if self.frame then
    self.frame.status:SetText(Fundraiser:T("TARGET_HINT"))
  end
  self:Refresh()
end
