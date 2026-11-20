-- Ledger page: scrollable donation rows of the active event, then one summary line per
-- archived event. Data and gating come from UseCases.GetLedgerView (Domain/LedgerView.lua).
-- "Set MOTD" (shell menu) publishes today's status + top contributor to the guild message (always confirmed).
Fundraiser = Fundraiser or {}
Fundraiser.UI = Fundraiser.UI or {}

local Ledger = {}
Fundraiser.UI.Ledger = Ledger

-- Ledger is a page inside the shell window (UI/Window.lua): a panel under the logo band, right of the menu.
local PANEL_W = 620
-- Same outer margin, card gap and inner padding as the Home page (UI/Window.lua).
local MARGIN = 16
local CARD_GAP = 10
local CARD_PAD = 10
local CARD_W = PANEL_W - 2 * MARGIN
local SUMMARY_H = 96
-- Rows that fit the table card inside the fixed shell height (see SHELL_H in UI/Window.lua).
local ROWS = 15
local ROW_H = 18
local HEADER_Y = -28
local LIST_TOP = -46
local LIST_X = CARD_PAD
local TABLE_CARD_H = -LIST_TOP + ROWS * ROW_H + 12
local COL_TIME_X, COL_TIME_W = 4, 134
local COL_NAME_X, COL_NAME_W = 138, 128
local COL_DETAIL_X, COL_DETAIL_W = 270, 124
local COL_AMOUNT_W = 130
-- Leaves room for the scroll bar inside the card.
local TABLE_W = CARD_W - CARD_PAD - 34
-- Grid lines sit at the left edge of each column (and the table edges).
local GRID_X = { 0, COL_NAME_X - 4, COL_DETAIL_X - 4, TABLE_W - COL_AMOUNT_W - 8, TABLE_W - 1 }
local GRID_COLOR = { 0.55, 0.50, 0.35, 0.55 }
local COLOR_ARCHIVE = { 0.75, 0.75, 0.55 }
local COLOR_HEADER = { 1, 0.82, 0 }

local function money(copper, height)
  if Fundraiser.FormatCopper then
    return Fundraiser.FormatCopper(copper, height)
  end
  return tostring(copper or 0) .. "c"
end

local function formatDate(at)
  at = tonumber(at) or 0
  if at <= 0 then
    return "-"
  end
  return date("%y-%m-%d %H:%M", at)
end

local function kindLabel(kind)
  if kind == "ah" then
    return Fundraiser:T("LEDGER_KIND_AH")
  end
  if kind == "manual" then
    return Fundraiser:T("LEDGER_KIND_MANUAL")
  end
  return Fundraiser:T("LEDGER_KIND_MAIL")
end

local function showTooltip(owner, titleKey, bodyKey)
  if not GameTooltip then
    return
  end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(Fundraiser:T(titleKey), 1, 1, 1)
  GameTooltip:AddLine(Fundraiser:T(bodyKey), 1, 0.82, 0, true)
  GameTooltip:Show()
end

local function hideTooltip()
  if GameTooltip then
    GameTooltip:Hide()
  end
end

-- Ports for the use cases (store + roster + MOTD adapter).
function Ledger:Deps()
  local Store = Fundraiser.Adapters.Store
  local Roster = Fundraiser.Adapters.Roster
  return {
    getEvent = function()
      return Store:GetEvent()
    end,
    getContributions = function()
      return Store:GetContributions()
    end,
    getArchives = function()
      return Store:GetArchives()
    end,
    getPlayerName = function()
      return Roster:GetPlayerName()
    end,
    getPlayerRankIndex = function()
      return Roster:GetPlayerRankIndex()
    end,
    getDonorRankIndex = function(name)
      return Roster:RankIndexOfName(name)
    end,
    setContributions = function(list)
      Store:SetContributions(list)
    end,
    broadcastLedgerEntry = function(entry)
      Fundraiser.Adapters.ThinGuildSync:BroadcastLedgerEntry(entry)
    end,
    canEditMotd = function()
      return Roster:CanEditMotd()
    end,
    setMotd = function(text)
      return Roster:SetMotd(text)
    end,
  }
end

-- "Set MOTD" lives in the shell menu: needs ledger access, an active event and MOTD permission.
function Ledger:CanSetMotd()
  local Store = Fundraiser.Adapters.Store
  local Roster = Fundraiser.Adapters.Roster
  return self:CanView() and Store:GetEvent() ~= nil and Roster:CanEditMotd()
end

-- Menu entries depend on the data (event, permissions), so refresh them with the page.
function Ledger:UpdateMenu()
  local Window = Fundraiser.UI.Window
  if Window and Window.UpdateNav then
    Window:UpdateNav()
  end
end

-- Manual donations: the donation target and officers (mail/AH rows stay target-only).
function Ledger:CanAddDonation()
  if not (Fundraiser.Config and Fundraiser.Config.LEDGER) then
    return false
  end
  local Store = Fundraiser.Adapters.Store
  local Roster = Fundraiser.Adapters.Roster
  local event = Store:GetEvent()
  return event ~= nil
    and Fundraiser.Domain.Roles.CanAddManualDonation(event, Roster:GetPlayerRankIndex(), Roster:GetPlayerName())
end

function Ledger:CanView()
  local UC = Fundraiser.Application.UseCases
  return UC.GetLedgerView(self:Deps()) ~= nil
end

-- Flat list the scroll frame renders: donation rows, then archived summaries.
local function buildItems(view)
  local items = {}
  for _, row in ipairs(view.active.rows) do
    items[#items + 1] = { type = "row", row = row }
  end
  if #view.archived > 0 then
    items[#items + 1] = { type = "header", text = Fundraiser:T("LEDGER_PREVIOUS_HEADER") }
    for _, a in ipairs(view.archived) do
      items[#items + 1] = { type = "archive", archive = a }
    end
  end
  return items
end

local function makeCell(parent, template, x, width, justify)
  local fs = parent:CreateFontString(nil, "ARTWORK", template)
  fs:SetPoint("LEFT", x + 2, 0)
  fs:SetWidth(width - 6)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

-- Cell backdrop, bottom hairline and vertical column lines for one table row.
local function addGrid(frame, withBottom)
  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints()
  frame.bg:SetColorTexture(0, 0, 0, 0)
  for _, x in ipairs(GRID_X) do
    local v = frame:CreateTexture(nil, "BORDER")
    v:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], GRID_COLOR[4])
    v:SetWidth(1)
    v:SetPoint("TOPLEFT", x, 0)
    v:SetPoint("BOTTOMLEFT", x, 0)
  end
  if withBottom then
    local b = frame:CreateTexture(nil, "BORDER")
    b:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], GRID_COLOR[4])
    b:SetHeight(1)
    b:SetPoint("BOTTOMLEFT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", 0, 0)
  end
end

-- Builds the ledger panel inside the shell window (called once from Window:Ensure).
-- Same margins/padding as the Home page: cards at MARGIN, CARD_GAP between them, CARD_PAD inside.
function Ledger:Attach(shell)
  if self.frame then
    return self.frame
  end
  local Window = Fundraiser.UI.Window
  local f = CreateFrame("Frame", "FundraiserLedgerPanel", shell)
  f:SetPoint("TOPLEFT", shell, "TOPLEFT", Window.NAV_W, -Window.HEADER_H)
  f:SetPoint("BOTTOMRIGHT", 0, 0)
  f:Hide()

  -- Summary card: total (prominent), event + count, empty-state hint.
  local summary = Window.MakeCard(f, "FundraiserLedgerSummaryCard", CARD_W, SUMMARY_H)
  summary:SetPoint("TOPLEFT", MARGIN, -34)
  summary.title:SetText(Fundraiser:T("CARD_LEDGER"))

  f.total = summary:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
  f.total:SetPoint("TOPLEFT", CARD_PAD, -26)

  f.summary = summary:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  f.summary:SetPoint("TOPLEFT", CARD_PAD, -50)

  f.hint = summary:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.hint:SetPoint("TOPLEFT", CARD_PAD, -68)
  f.hint:SetWidth(CARD_W - 2 * CARD_PAD)
  f.hint:SetJustifyH("LEFT")

  -- Table card: column headers + scrolling rows.
  local card = Window.MakeCard(f, "FundraiserLedgerTableCard", CARD_W, TABLE_CARD_H)
  card:SetPoint("TOPLEFT", MARGIN, -(34 + SUMMARY_H + CARD_GAP))
  card.title:SetText(Fundraiser:T("CARD_DONATIONS"))

  local header = CreateFrame("Frame", nil, card)
  header:SetPoint("TOPLEFT", LIST_X, HEADER_Y)
  header:SetSize(TABLE_W, ROW_H)
  addGrid(header, true)
  header.bg:SetColorTexture(1, 0.82, 0, 0.18)
  local top = header:CreateTexture(nil, "BORDER")
  top:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], GRID_COLOR[4])
  top:SetHeight(1)
  top:SetPoint("TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", 0, 0)
  makeCell(header, "GameFontNormalSmall", COL_TIME_X, COL_TIME_W):SetText(Fundraiser:T("LEDGER_COL_TIME"))
  makeCell(header, "GameFontNormalSmall", COL_NAME_X, COL_NAME_W):SetText(Fundraiser:T("LEDGER_COL_NAME"))
  makeCell(header, "GameFontNormalSmall", COL_DETAIL_X, COL_DETAIL_W):SetText(Fundraiser:T("LEDGER_COL_DETAIL"))
  local amountHead = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  amountHead:SetPoint("RIGHT", -4, 0)
  amountHead:SetWidth(COL_AMOUNT_W)
  amountHead:SetJustifyH("RIGHT")
  amountHead:SetText(Fundraiser:T("LEDGER_COL_AMOUNT"))
  f.header = header

  local scroll = CreateFrame("ScrollFrame", "FundraiserLedgerScroll", card, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", LIST_X, LIST_TOP)
  scroll:SetPoint("BOTTOMRIGHT", -34, 12)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, function()
      Ledger:UpdateRows()
    end)
  end)
  f.scroll = scroll

  f.rows = {}
  for i = 1, ROWS do
    local r = CreateFrame("Frame", nil, card)
    r:SetSize(TABLE_W, ROW_H)
    addGrid(r, true)
    r:SetPoint("TOPLEFT", LIST_X, LIST_TOP - (i - 1) * ROW_H)
    r.time = makeCell(r, "GameFontHighlightSmall", COL_TIME_X, COL_TIME_W)
    r.name = makeCell(r, "GameFontHighlightSmall", COL_NAME_X, COL_NAME_W)
    r.detail = makeCell(r, "GameFontHighlightSmall", COL_DETAIL_X, COL_DETAIL_W)
    r.amount = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.amount:SetPoint("RIGHT", -4, 0)
    r.amount:SetWidth(COL_AMOUNT_W)
    r.amount:SetJustifyH("RIGHT")
    f.rows[i] = r
  end

  self.frame = f
  self:AttachDonation(shell)
  return f
end

-- "Add donation" page: donor, amount in gold/silver/copper, optional note. Reachable for officers and the donation target.
function Ledger:AttachDonation(shell)
  local p = CreateFrame("Frame", "FundraiserDonationPanel", shell)
  p:SetPoint("TOPLEFT", shell, "TOPLEFT", Fundraiser.UI.Window.NAV_W, -Fundraiser.UI.Window.HEADER_H)
  p:SetPoint("BOTTOMRIGHT", 0, 0)
  p:Hide()

  local y = -34
  local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", MARGIN, y)
  title:SetText(Fundraiser:T("SECTION_DONATION"))
  local line = p:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 1, 1, 0.15)
  line:SetSize(PANEL_W - 2 * MARGIN, 1)
  line:SetPoint("TOPLEFT", MARGIN, y - 18)
  y = y - 28

  local help = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  help:SetPoint("TOPLEFT", MARGIN, y)
  help:SetWidth(PANEL_W - 2 * MARGIN)
  help:SetJustifyH("LEFT")
  help:SetWordWrap(true)
  help:SetText(Fundraiser:T("DONATION_HELP"))
  y = y - 44

  local function field(labelKey, name, width)
    local fs = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", MARGIN, y - 3)
    fs:SetWidth(190)
    fs:SetJustifyH("LEFT")
    fs:SetText(Fundraiser:T(labelKey))
    local eb = CreateFrame("EditBox", name, p, "InputBoxTemplate")
    eb:SetSize(width, 20)
    eb:SetPoint("TOPLEFT", 214, y)
    eb:SetAutoFocus(false)
    y = y - 30
    return eb
  end

  p.donor = field("LABEL_DONOR", "FundraiserDonationDonor", 240)
  -- Amount: gold / silver / copper boxes on one row.
  local amountLabel = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  amountLabel:SetPoint("TOPLEFT", MARGIN, y - 3)
  amountLabel:SetWidth(190)
  amountLabel:SetJustifyH("LEFT")
  amountLabel:SetText(Fundraiser:T("LABEL_DONATION_AMOUNT"))
  local prev
  local function unitBox(name, width, unitKey)
    local eb = CreateFrame("EditBox", name, p, "InputBoxTemplate")
    eb:SetSize(width, 20)
    if prev then
      eb:SetPoint("LEFT", prev, "RIGHT", 22, 0)
    else
      eb:SetPoint("TOPLEFT", 214, y)
    end
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(7)
    local unit = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    unit:SetPoint("LEFT", eb, "RIGHT", 6, 0)
    unit:SetText(Fundraiser:T(unitKey))
    prev = eb
    return eb
  end
  p.gold = unitBox("FundraiserDonationGold", 70, "UNIT_GOLD")
  p.silver = unitBox("FundraiserDonationSilver", 40, "UNIT_SILVER")
  p.copper = unitBox("FundraiserDonationCopper", 40, "UNIT_COPPER")
  p.silver:SetMaxLetters(2)
  p.copper:SetMaxLetters(2)
  y = y - 30
  p.note = field("LABEL_DONATION_NOTE", "FundraiserDonationNote", 240)

  local add = CreateFrame("Button", "FundraiserDonationAddButton", p, "UIPanelButtonTemplate")
  add:SetSize(140, 24)
  add:SetPoint("TOPLEFT", MARGIN, y - 4)
  add:SetText(Fundraiser:T("BTN_ADD_DONATION"))
  add:SetScript("OnClick", function()
    Ledger:SubmitDonation()
  end)

  local cancel = CreateFrame("Button", "FundraiserDonationCancelButton", p, "UIPanelButtonTemplate")
  cancel:SetSize(100, 24)
  cancel:SetPoint("LEFT", add, "RIGHT", 8, 0)
  cancel:SetText(Fundraiser:T("BTN_CANCEL"))
  cancel:SetScript("OnClick", function()
    Fundraiser.UI.Window:ShowLedger()
  end)

  self.donationFrame = p
end

function Ledger:ResetDonationForm()
  local p = self.donationFrame
  if not p then
    return
  end
  p.donor:SetText("")
  p.gold:SetText("")
  p.silver:SetText("")
  p.copper:SetText("")
  p.note:SetText("")
end

local function chat(text)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. text)
  end
end

function Ledger:SubmitDonation()
  local p = self.donationFrame
  local UC = Fundraiser.Application.UseCases
  local Roster = Fundraiser.Adapters.Roster
  local copper = (tonumber(p.gold:GetText()) or 0) * 10000
    + (tonumber(p.silver:GetText()) or 0) * 100
    + (tonumber(p.copper:GetText()) or 0)
  local donor = p.donor:GetText()
  local actor = {
    name = Roster:GetPlayerName(),
    rankIndex = Roster:GetPlayerRankIndex(),
    now = (GetServerTime and GetServerTime()) or time(),
  }
  local entry, err = UC.AddManualDonation(self:Deps(), { name = donor, copper = copper, detail = p.note:GetText() }, actor)
  if not entry then
    local keys = {
      not_allowed = "CHAT_DONATION_NOT_ALLOWED",
      bad_name = "CHAT_DONATION_BAD_NAME",
      bad_copper = "CHAT_DONATION_BAD_AMOUNT",
      no_event = "STATUS_NO_EVENT",
    }
    chat(Fundraiser:T(keys[err] or "CHAT_DONATION_FAILED"))
    return
  end
  chat(Fundraiser:T("CHAT_DONATION_ADDED", entry.name, money(entry.copper, 12)))
  Fundraiser.UI.Window:ShowLedger()
end

-- The panel exists once the shell window has been built.
function Ledger:Ensure()
  if not self.frame then
    Fundraiser.UI.Window:Ensure()
  end
  return self.frame
end

local function setColor(row, color)
  row.time:SetTextColor(color[1], color[2], color[3])
  row.name:SetTextColor(color[1], color[2], color[3])
  row.detail:SetTextColor(color[1], color[2], color[3])
end

-- FauxScrollFrame_Update hides the bar when everything fits; keep it as a disabled rail instead.
local function keepScrollBarVisible(scroll, scrollable)
  local name = scroll:GetName()
  local bar = name and _G[name .. "ScrollBar"]
  if not bar then
    return
  end
  bar:Show()
  local up = _G[name .. "ScrollBarScrollUpButton"]
  local down = _G[name .. "ScrollBarScrollDownButton"]
  if up and down then
    if scrollable then
      up:Enable()
      down:Enable()
    else
      up:Disable()
      down:Disable()
    end
  end
  local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
  if thumb then
    if scrollable then
      thumb:Show()
    else
      thumb:Hide()
    end
  end
end

function Ledger:UpdateRows()
  local f = self:Ensure()
  local items = self.items or {}
  FauxScrollFrame_Update(f.scroll, #items, ROWS, ROW_H)
  keepScrollBarVisible(f.scroll, #items > ROWS)
  local offset = FauxScrollFrame_GetOffset(f.scroll)
  for i = 1, ROWS do
    local row = f.rows[i]
    local item = items[offset + i]
    if not item then
      row:Hide()
    else
      row:Show()
      if item.type == "row" then
        -- Zebra stripes follow the item index so they stay put while scrolling.
        row.bg:SetColorTexture(1, 1, 1, (offset + i) % 2 == 0 and 0.07 or 0.02)
        local r = item.row
        setColor(row, { 1, 1, 1 })
        row.time:SetText(formatDate(r.at) .. " " .. kindLabel(r.kind))
        row.name:SetText(r.name or "?")
        row.detail:SetText(r.detail or "")
        row.amount:SetText(money(r.copper, 12))
      elseif item.type == "header" then
        row.bg:SetColorTexture(1, 0.82, 0, 0.18)
        setColor(row, COLOR_HEADER)
        row.time:SetText(item.text)
        row.name:SetText("")
        row.detail:SetText("")
        row.amount:SetText("")
      else
        local a = item.archive
        row.bg:SetColorTexture(0.75, 0.75, 0.55, 0.10)
        setColor(row, COLOR_ARCHIVE)
        row.time:SetText(formatDate(a.archivedAt))
        row.name:SetText(Fundraiser:T("LEDGER_PREVIOUS_FMT", a.name ~= "" and a.name or "?"))
        row.detail:SetText(Fundraiser:T("LEDGER_COUNT_FMT", a.count))
        row.amount:SetText(money(a.total, 12))
      end
    end
  end
end

function Ledger:ShowEmpty(text)
  local f = self:Ensure()
  self.items = {}
  f.total:SetText("")
  f.summary:SetText(text)
  f.hint:SetText("")
  self:UpdateRows()
  self:UpdateMenu()
end

function Ledger:Refresh()
  local f = self:Ensure()
  local UC = Fundraiser.Application.UseCases
  local Roster = Fundraiser.Adapters.Roster
  if Roster and Roster.Request then
    Roster:Request()
  end
  local view = UC.GetLedgerView(self:Deps())
  if not view then
    self:ShowEmpty(Fundraiser:T("LEDGER_OFFICER_ONLY"))
    return
  end

  self.items = buildItems(view)
  if view.hasEvent then
    f.total:SetText(Fundraiser:T("LEDGER_TOTAL_FMT", money(view.active.total, 16)))
    f.summary:SetText((view.event.name or "") .. " - " .. Fundraiser:T("LEDGER_COUNT_FMT", view.active.count))
    f.hint:SetText(view.active.count == 0 and Fundraiser:T("LEDGER_EMPTY") .. " " .. Fundraiser:T("LEDGER_DEDICATED_HINT") or "")
  else
    f.total:SetText("")
    f.summary:SetText(#view.archived == 0 and Fundraiser:T("STATUS_NO_EVENT") or "")
    f.hint:SetText("")
  end

  self:UpdateRows()
  self:UpdateMenu()
end

function Ledger:ConfirmSetMotd()
  local UC = Fundraiser.Application.UseCases
  local text = UC.PrepareMotd(self:Deps())
  if not text then
    DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("CHAT_MOTD_FAILED"))
    return
  end
  local function accept()
    local set = UC.SetMotd(Ledger:Deps())
    if set then
      DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("CHAT_MOTD_SET", set))
    else
      DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("CHAT_MOTD_FAILED"))
    end
  end
  if StaticPopupDialogs and StaticPopup_Show then
    StaticPopupDialogs["FUNDRAISER_SET_MOTD"] = {
      text = Fundraiser:T("MOTD_CONFIRM_FMT"),
      button1 = YES or ACCEPT or "Yes",
      button2 = NO or CANCEL or "No",
      OnAccept = accept,
      timeout = 0,
      whileDead = 1,
      hideOnEscape = 1,
      preferredIndex = 3,
    }
    StaticPopup_Show("FUNDRAISER_SET_MOTD", text)
    return
  end
  accept()
end
