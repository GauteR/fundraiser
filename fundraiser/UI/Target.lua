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
local ROWS = 9
local ROW_H = 18
local HEADER_Y = -28
local LIST_TOP = -46
local LIST_CARD_H = -LIST_TOP + ROWS * ROW_H + 10
local DETAIL_CARD_H = 150
local LIST_W = CARD_W - CARD_PAD - 34
-- List columns: icon, item name, quantity, value (net of the recommended action), note.
local ICON_SIZE = 14
local COL_NAME_X, COL_NAME_W = 22, 236
local COL_QTY_X, COL_QTY_W = 262, 40
local COL_VALUE_X, COL_VALUE_W = 306, 110
local COL_NOTE_X = 424
local COLOR_GROUP = {
  auction = { 0.30, 0.65, 1.00 },
  vendor = { 1.00, 0.82, 0.00 },
  price = { 1.00, 0.55, 0.15 },
}
local COLOR_STATUS = {
  ok = { 0.40, 1.00, 0.40 },
  error = { 1.00, 0.40, 0.40 },
  info = { 1.00, 1.00, 1.00 },
}
-- Opening or closing the auction house / a vendor changes what the bulk buttons may do.
local WINDOW_EVENTS = { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "MERCHANT_SHOW", "MERCHANT_CLOSED" }
-- Selected-stack card geometry.
local SEL_ICON = 32
local SEL_GRID_Y = -68
local SEL_LINE_H = 14
local SEL_LABEL_W = 110
local SEL_VALUE_W = 150
local SEL_COL2_X = 300
local COLOR_SELECTED = { 1, 0.82, 0, 0.30 }
local COLOR_NOTE = { 0.65, 0.65, 0.65 }

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
    items[#items + 1] = { type = "header", text = headerText, group = group }
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

-- Show a status line coloured by what happened (green ok, red failure, white info).
function Target:SetStatus(key, text)
  local c = COLOR_STATUS[TV().StatusKind(key)]
  self.frame.status:SetTextColor(c[1], c[2], c[3])
  self.frame.status:SetText(text)
end

-- Item tooltip for a row: the real bag tooltip when available, else the item link.
function Target:ShowItemTooltip(owner, row)
  if not GameTooltip then
    return
  end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if row.bag and row.slot and GameTooltip.SetBagItem then
    GameTooltip:SetBagItem(row.bag, row.slot)
  elseif row.link then
    GameTooltip:SetHyperlink(row.link)
  else
    GameTooltip:SetText(row.name or "?")
  end
  GameTooltip:Show()
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

  -- Column labels above the rows, like the ledger table.
  local head = CreateFrame("Frame", nil, card)
  head:SetPoint("TOPLEFT", CARD_PAD, HEADER_Y)
  head:SetSize(LIST_W, ROW_H)
  head.bg = head:CreateTexture(nil, "BACKGROUND")
  head.bg:SetAllPoints()
  head.bg:SetColorTexture(1, 0.82, 0, 0.18)
  local function label(x, width, key, justify)
    local fs = head:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    fs:SetPoint("LEFT", x, 0)
    fs:SetWidth(width)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetText(Fundraiser:T(key))
  end
  label(COL_NAME_X, COL_NAME_W, "TARGET_COL_ITEM")
  label(COL_QTY_X, COL_QTY_W, "TARGET_COL_QTY", "RIGHT")
  label(COL_VALUE_X, COL_VALUE_W, "TARGET_COL_VALUE", "RIGHT")
  label(COL_NOTE_X, LIST_W - COL_NOTE_X, "TARGET_COL_NOTE")

  f.rows = {}
  for i = 1, ROWS do
    local r = CreateFrame("Button", nil, card)
    r:SetSize(LIST_W, ROW_H)
    r:SetPoint("TOPLEFT", CARD_PAD, LIST_TOP - (i - 1) * ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(0, 0, 0, 0)
    -- Accent bar on the selected row.
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetColorTexture(1, 0.82, 0, 1)
    r.bar:SetWidth(2)
    r.bar:SetPoint("TOPLEFT", 0, 0)
    r.bar:SetPoint("BOTTOMLEFT", 0, 0)
    r.bar:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON_SIZE, ICON_SIZE)
    r.icon:SetPoint("LEFT", 4, 0)
    local function cell(x, width, justify)
      local fs = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      fs:SetPoint("LEFT", x, 0)
      fs:SetWidth(width)
      fs:SetJustifyH(justify or "LEFT")
      fs:SetWordWrap(false)
      return fs
    end
    r.text = cell(COL_NAME_X, COL_NAME_W)
    r.qty = cell(COL_QTY_X, COL_QTY_W, "RIGHT")
    r.value = cell(COL_VALUE_X, COL_VALUE_W, "RIGHT")
    r.note = cell(COL_NOTE_X, LIST_W - COL_NOTE_X)
    r.note:SetTextColor(COLOR_NOTE[1], COLOR_NOTE[2], COLOR_NOTE[3])
    r:SetScript("OnClick", function(self)
      if self.entry then
        Target:Select(self.entry.key)
      end
    end)
    r:SetScript("OnEnter", function(self)
      if self.entry then
        Target:ShowItemTooltip(self, self.entry.row)
      end
    end)
    r:SetScript("OnLeave", function()
      if GameTooltip then
        GameTooltip:Hide()
      end
    end)
    f.rows[i] = r
  end

  -- Detail card: the selected stack, manual unit price, actions.
  local detail = Window.MakeCard(f, "FundraiserTargetDetailCard", CARD_W, DETAIL_CARD_H)
  detail:SetPoint("TOPLEFT", MARGIN, -(34 + LIST_CARD_H + CARD_GAP))
  detail.title:SetText(Fundraiser:T("CARD_TARGET_SELECTED"))

  -- Shown instead of the stack details when nothing is selected.
  f.detail = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.detail:SetPoint("TOPLEFT", CARD_PAD, -28)
  f.detail:SetWidth(CARD_W - 2 * CARD_PAD)
  f.detail:SetJustifyH("LEFT")
  f.detail:SetJustifyV("TOP")
  f.detail:SetWordWrap(true)

  -- Selected stack: icon, item name in its quality colour, stack size and the recommendation.
  local sel = CreateFrame("Frame", nil, detail)
  sel:SetPoint("TOPLEFT", 0, 0)
  sel:SetPoint("BOTTOMRIGHT", 0, 0)
  f.sel = sel
  local iconBtn = CreateFrame("Button", nil, sel)
  iconBtn:SetSize(SEL_ICON, SEL_ICON)
  iconBtn:SetPoint("TOPLEFT", CARD_PAD, -26)
  sel.icon = iconBtn:CreateTexture(nil, "ARTWORK")
  sel.icon:SetAllPoints()
  iconBtn:SetScript("OnEnter", function(self)
    if self.row then
      Target:ShowItemTooltip(self, self.row)
    end
  end)
  iconBtn:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  sel.iconBtn = iconBtn
  sel.name = sel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  sel.name:SetPoint("TOPLEFT", iconBtn, "TOPRIGHT", 8, -1)
  sel.name:SetWidth(CARD_W - 2 * CARD_PAD - SEL_ICON - 8)
  sel.name:SetJustifyH("LEFT")
  sel.name:SetWordWrap(false)
  sel.sub = sel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sel.sub:SetPoint("TOPLEFT", sel.name, "BOTTOMLEFT", 0, -4)
  sel.sub:SetWidth(CARD_W - 2 * CARD_PAD - SEL_ICON - 8)
  sel.sub:SetJustifyH("LEFT")

  -- Label / value grid: two columns of three lines under the header.
  local function pair(x, line, labelKey)
    local y = SEL_GRID_Y - (line - 1) * SEL_LINE_H
    local label = sel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(SEL_LABEL_W)
    label:SetJustifyH("LEFT")
    label:SetTextColor(0.65, 0.65, 0.65)
    label:SetText(Fundraiser:T(labelKey))
    local value = sel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    value:SetPoint("TOPLEFT", x + SEL_LABEL_W, y)
    value:SetWidth(SEL_VALUE_W)
    value:SetJustifyH("RIGHT")
    return value
  end
  sel.vendorValue = pair(CARD_PAD, 1, "TARGET_LBL_VENDOR")
  sel.grossValue = pair(CARD_PAD, 2, "TARGET_LBL_AH_GROSS")
  sel.netValue = pair(CARD_PAD, 3, "TARGET_LBL_AH_NET")
  sel.sourceValue = pair(SEL_COL2_X, 1, "TARGET_LBL_SOURCE")
  sel.unitValue = pair(SEL_COL2_X, 2, "TARGET_LBL_UNIT")
  sel.countValue = pair(SEL_COL2_X, 3, "TARGET_LBL_STACK")

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
  f.status = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
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
    r.bar:Hide()
    r.icon:Hide()
    r.qty:SetText("")
    r.note:SetText("")
    r.text:SetWidth(COL_NAME_W)
    if not item then
      r:Hide()
    elseif item.type == "header" then
      local c = COLOR_GROUP[item.group] or COLOR_GROUP.vendor
      r.text:SetWidth(LIST_W - COL_NAME_X)
      r.text:SetText(item.text)
      r.text:SetTextColor(c[1], c[2], c[3])
      r.value:SetText("")
      r.bg:SetColorTexture(c[1], c[2], c[3], 0.12)
      r:Show()
    else
      local entry = item.entry
      local row = entry.row
      r.entry = entry
      local icon = row.itemId and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(row.itemId)
      if icon then
        r.icon:SetTexture(icon)
        r.icon:Show()
      end
      r.text:SetText(row.name or "?")
      r.text:SetTextColor(1, 1, 1)
      r.qty:SetText(tostring(row.count or 1))
      r.value:SetText(money(entry.value))
      local note = TV().RowNote(entry)
      r.note:SetText(note and Fundraiser:T("TARGET_NOTE_" .. string.upper(note)) or "")
      if entry.key == self.selectedKey then
        r.bg:SetColorTexture(COLOR_SELECTED[1], COLOR_SELECTED[2], COLOR_SELECTED[3], COLOR_SELECTED[4])
        r.bar:Show()
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
    f.sel:Hide()
    f.detail:Show()
    f.detail:SetText(#self.flat == 0 and Fundraiser:T("TARGET_EMPTY") or Fundraiser:T("TARGET_SELECT_HINT"))
    f.manualPrice:SetText("")
    f.postBtn:Disable()
    f.vendorBtn:Disable()
    f.skipBtn:Disable()
    return
  end
  local row = entry.row
  f.detail:Hide()
  local sel = f.sel
  sel:Show()
  local icon = row.itemId and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(row.itemId)
  sel.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  sel.iconBtn.row = row
  sel.name:SetText(row.name or "?")
  local quality = row.itemId and C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(row.itemId)
  local r, g, b = 1, 0.82, 0
  if quality and C_Item.GetItemQualityColor then
    r, g, b = C_Item.GetItemQualityColor(quality)
  end
  sel.name:SetTextColor(r, g, b)
  -- Recommendation in the colour of its group, next to the stack size.
  local gc = COLOR_GROUP[entry.group] or COLOR_GROUP.vendor
  local advice = Fundraiser:T("TARGET_ADVICE_" .. string.upper(row.advice or "manual"))
  sel.sub:SetText(string.format(
    "%s   |cff%02x%02x%02x%s|r",
    Fundraiser:T("TARGET_STACK_FMT", tostring(row.count)),
    math.floor(gc[1] * 255),
    math.floor(gc[2] * 255),
    math.floor(gc[3] * 255),
    advice
  ))
  sel.vendorValue:SetText(money(row.vendorTotal))
  sel.grossValue:SetText(money(row.ahUnit and (row.ahUnit * row.count) or nil))
  sel.netValue:SetText(money(row.ahNet))
  sel.sourceValue:SetText(row.source or "?")
  sel.unitValue:SetText(money(row.ahUnit))
  sel.countValue:SetText(tostring(row.count))
  -- The value of the recommended action stands out.
  sel.vendorValue:SetTextColor(1, 1, 1)
  sel.netValue:SetTextColor(1, 1, 1)
  if row.advice == "vendor" then
    sel.vendorValue:SetTextColor(gc[1], gc[2], gc[3])
  elseif row.advice == "ah" then
    sel.netValue:SetTextColor(gc[1], gc[2], gc[3])
  end
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
    self:SetStatus(key, statusText(key, a, b))
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
    self:SetStatus(d.blockKey, Fundraiser:T(d.blockKey))
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
    self:SetStatus("TARGET_BULK_STOPPED_FMT", stoppedText(queue, reason))
  elseif queue:Finished() then
    self:SetStatus("TARGET_BULK_DONE_FMT", Fundraiser:T("TARGET_BULK_DONE_FMT", queue:Done()))
  else
    self:SetStatus(
      "TARGET_BULK_PROGRESS_FMT",
      Fundraiser:T("TARGET_BULK_PROGRESS_FMT", queue:Done(), queue:Total(), queue:Remaining())
    )
  end
  self:UpdateBulk()
end

function Target:RunSell(queue)
  local f = self.frame
  while queue:Remaining() > 0 do
    local ok, reason = queue:Next()
    if not ok then
      self:SetStatus("TARGET_BULK_STOPPED_FMT", stoppedText(queue, reason))
      self:UpdateBulk()
      return
    end
  end
  self:SetStatus("TARGET_BULK_DONE_FMT", Fundraiser:T("TARGET_BULK_DONE_FMT", queue:Done()))
  self:UpdateBulk()
end

-- The same panel docks beside the auction house while it is open (donation target only):
-- it moves from the shell window into a compact frame anchored to the right of the auction
-- house, and goes back to the shell when the auction house closes.
local PANEL_H = 490

function Target:EnsureDock()
  if self.dock then
    return self.dock
  end
  local d = CreateFrame("Frame", "FundraiserTargetDock", UIParent, "BasicFrameTemplateWithInset")
  d:SetSize(PANEL_W + 8, PANEL_H + 28)
  d:SetFrameStrata("DIALOG")
  d:SetClampedToScreen(true)
  d:EnableMouse(true)
  if d.TitleText then
    d.TitleText:SetText(Fundraiser:T("TARGET_DOCK_TITLE"))
  end
  d:Hide()
  self.dock = d
  return d
end

-- Place the dock beside the right-most visible auction window.
function Target:Reanchor()
  local dock = self.dock
  if not dock then
    return
  end
  local candidates = {}
  for _, name in ipairs((Fundraiser.Config and Fundraiser.Config.TARGET_DOCK_ANCHORS) or { "AuctionHouseFrame" }) do
    local frame = _G[name]
    if frame then
      candidates[#candidates + 1] = {
        name = name,
        right = frame.GetRight and frame:GetRight() or nil,
        shown = frame.IsShown and frame:IsShown() or false,
      }
    end
  end
  local picked = TV().PickAnchor(candidates)
  dock:ClearAllPoints()
  if picked then
    dock:SetPoint("TOPLEFT", _G[picked], "TOPRIGHT", 2, 0)
  else
    dock:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
  end
end

-- Move the dock again when an addon's side window (for example Auctionator's price history)
-- opens or closes; windows that do not exist yet are picked up on the next dock.
function Target:WatchAnchors()
  self.watched = self.watched or {}
  for _, name in ipairs((Fundraiser.Config and Fundraiser.Config.TARGET_DOCK_ANCHORS) or {}) do
    local frame = _G[name]
    if frame and frame.HookScript and not self.watched[name] then
      self.watched[name] = true
      local function again()
        if Target.docked then
          Target:Reanchor()
        end
      end
      frame:HookScript("OnShow", again)
      frame:HookScript("OnHide", again)
    end
  end
end

function Target:Dock()
  if not Fundraiser:CanOpenTargetUi() then
    return
  end
  local Window = Fundraiser.UI.Window
  -- Already on screen as the shell's Target page: leave it there.
  if Window.frame and Window.frame:IsShown() and Window.view == "target" then
    return
  end
  Window:Ensure()
  local f = self.frame
  if not f then
    return
  end
  local dock = self:EnsureDock()
  self:Reanchor()
  self:WatchAnchors()
  f:SetParent(dock)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", dock, "TOPLEFT", 4, -24)
  f:SetSize(PANEL_W, PANEL_H)
  self.docked = true
  dock:Show()
  f:Show()
  self:Open()
end

-- Back into the shell window (it shows there only while the shell is on the Target page).
function Target:Undock()
  if not self.docked then
    return
  end
  self.docked = false
  local f = self.frame
  local Window = Fundraiser.UI.Window
  local shell = Window.frame
  if self.dock then
    self.dock:Hide()
  end
  if not (f and shell) then
    return
  end
  f:SetParent(shell)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", shell, "TOPLEFT", Window.NAV_W, -Window.HEADER_H)
  f:SetPoint("BOTTOMRIGHT", 0, 0)
  if shell:IsShown() and Window.view == "target" then
    f:Show()
  else
    f:Hide()
  end
end

-- Watches the auction house window; called once at login.
function Target:Initialize()
  if self.initialized then
    return
  end
  local cfg = Fundraiser.Config or {}
  if not (cfg.TARGET_UI and cfg.TARGET_AUTO_DOCK) then
    return
  end
  local ev = CreateFrame("Frame", "FundraiserTargetDockEvents")
  ev:RegisterEvent("AUCTION_HOUSE_SHOW")
  ev:RegisterEvent("AUCTION_HOUSE_CLOSED")
  ev:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
      Target:Dock()
    else
      Target:Undock()
    end
  end)
  self.initialized = true
end

-- Called by the shell when the page opens.
function Target:Open()
  if self.frame then
    self:SetStatus("TARGET_HINT", Fundraiser:T("TARGET_HINT"))
  end
  self:Refresh()
end
