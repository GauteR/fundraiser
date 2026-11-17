-- Donation-target inbox assist: per-sender item stacks, AH vs vendor advice.
Fundraiser = Fundraiser or {}
Fundraiser.UI = Fundraiser.UI or {}

local Target = {}
Fundraiser.UI.Target = Target

local function money(copper)
  if not copper then
    return "-"
  end
  return Fundraiser.FormatCopper(copper)
end

function Target:Ensure()
  if self.frame then
    return self.frame
  end

  local f = CreateFrame("Frame", "FundraiserTargetFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(560, 420)
  f:SetPoint("CENTER", 40, -20)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  if f.TitleText then
    f.TitleText:SetText(Fundraiser:T("TARGET_WINDOW_TITLE"))
  end
  tinsert(UISpecialFrames, "FundraiserTargetFrame")

  local hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 16, -32)
  hint:SetWidth(520)
  hint:SetJustifyH("LEFT")
  hint:SetText(Fundraiser:T("TARGET_HINT"))
  f.hint = hint

  local list = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  list:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
  list:SetWidth(520)
  list:SetHeight(160)
  list:SetJustifyH("LEFT")
  list:SetJustifyV("TOP")
  f.list = list

  local detail = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  detail:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -12)
  detail:SetWidth(520)
  detail:SetJustifyH("LEFT")
  f.detail = detail

  local priceLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  priceLabel:SetPoint("TOPLEFT", detail, "BOTTOMLEFT", 0, -16)
  priceLabel:SetText(Fundraiser:T("TARGET_MANUAL_PRICE"))

  local price = CreateFrame("EditBox", "FundraiserTargetManualPrice", f, "InputBoxTemplate")
  price:SetSize(120, 20)
  price:SetPoint("LEFT", priceLabel, "RIGHT", 8, 0)
  price:SetAutoFocus(false)
  f.manualPrice = price

  local y = -320
  local function btn(name, text, x)
    local b = CreateFrame("Button", name, f, "UIPanelButtonTemplate")
    b:SetSize(100, 24)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    return b
  end

  local refresh = btn("FundraiserTargetRefresh", Fundraiser:T("BTN_REFRESH"), 16)
  refresh:SetScript("OnClick", function()
    Target:Refresh()
  end)

  local prev = btn("FundraiserTargetPrev", "<", 130)
  prev:SetWidth(40)
  prev:SetScript("OnClick", function()
    Target:SelectDelta(-1)
  end)

  local next = btn("FundraiserTargetNext", ">", 180)
  next:SetWidth(40)
  next:SetScript("OnClick", function()
    Target:SelectDelta(1)
  end)

  local post = btn("FundraiserTargetPost", Fundraiser:T("BTN_POST_AH"), 240)
  post:SetScript("OnClick", function()
    Target:Act("ah")
  end)

  local vendor = btn("FundraiserTargetVendor", Fundraiser:T("BTN_VENDOR"), 350)
  vendor:SetScript("OnClick", function()
    Target:Act("vendor")
  end)

  f:SetScript("OnShow", function()
    Target:Refresh()
  end)

  self.index = 1
  self.rows = {}
  self.frame = f
  return f
end

function Target:SelectDelta(delta)
  if not self.rows or #self.rows == 0 then
    return
  end
  self.index = self.index + delta
  if self.index < 1 then
    self.index = #self.rows
  end
  if self.index > #self.rows then
    self.index = 1
  end
  self:ShowSelected()
end

function Target:ShowSelected()
  local f = self:Ensure()
  local row = self.rows[self.index]
  if not row then
    f.detail:SetText(Fundraiser:T("TARGET_EMPTY"))
    f.manualPrice:SetText("")
    return
  end
  local advice = row.advice or "manual"
  f.detail:SetText(Fundraiser:T(
    "TARGET_DETAIL_FMT",
    self.index,
    #self.rows,
    row.sender,
    row.name,
    tostring(row.count),
    money(row.vendorTotal),
    money(row.ahUnit and (row.ahUnit * row.count) or nil),
    money(row.ahNet),
    row.source or "?",
    Fundraiser:T("TARGET_ADVICE_" .. string.upper(advice))
  ))
  if row.ahUnit then
    f.manualPrice:SetText(tostring(row.ahUnit))
  else
    f.manualPrice:SetText("")
  end
end

function Target:Refresh()
  local f = self:Ensure()
  if not Fundraiser.Adapters.InboxAssist:IsDonationTarget() then
    f.list:SetText(Fundraiser:T("TARGET_NOT_TARGET"))
    self.rows = {}
    self:ShowSelected()
    return
  end
  self.rows = Fundraiser.Adapters.InboxAssist:Scan()
  if #self.rows == 0 then
    f.list:SetText(Fundraiser:T("TARGET_EMPTY"))
  else
    local lines = {}
    local lastSender = nil
    for i, row in ipairs(self.rows) do
      if row.sender ~= lastSender then
        lines[#lines + 1] = Fundraiser:T("TARGET_SENDER_FMT", row.sender)
        lastSender = row.sender
      end
      local mark = (i == self.index) and ">" or " "
      lines[#lines + 1] = string.format(
        "%s %d. %sx%d [%s] AH:%s Vend:%s",
        mark,
        i,
        row.name,
        row.count,
        Fundraiser:T("TARGET_ADVICE_" .. string.upper(row.advice or "manual")),
        money(row.ahUnit and row.ahUnit * row.count or nil),
        money(row.vendorTotal)
      )
    end
    f.list:SetText(table.concat(lines, "\n"))
  end
  if self.index > #self.rows then
    self.index = math.max(1, #self.rows)
  end
  self:ShowSelected()
end

function Target:Act(action)
  local row = self.rows and self.rows[self.index]
  if not row then
    return
  end
  local manual = tonumber(self.frame.manualPrice:GetText())
  Fundraiser.Adapters.AuctionPost:HandleRow(row, action, manual)
  -- Rescan shortly; TakeInboxItem is often deferred.
  if C_Timer and C_Timer.After then
    C_Timer.After(0.5, function()
      Target:Refresh()
    end)
  else
    self:Refresh()
  end
end

function Target:Toggle()
  local f = self:Ensure()
  if f:IsShown() then
    f:Hide()
  else
    f:Show()
  end
end
