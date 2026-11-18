-- Ledger window: scrollable donation rows of the active event, then one summary line per
-- archived event. Data and gating come from UseCases.GetLedgerView (Domain/LedgerView.lua).
-- "Set MOTD" publishes today's status + top contributor to the guild message (always confirmed).
Fundraiser = Fundraiser or {}
Fundraiser.UI = Fundraiser.UI or {}

local Ledger = {}
Fundraiser.UI.Ledger = Ledger

local FRAME_W = 640
local FRAME_H = 470
local ROWS = 16
local ROW_H = 18
local LIST_TOP = -112
local COL_TIME_X, COL_TIME_W = 4, 144
local COL_NAME_X, COL_NAME_W = 148, 140
local COL_DETAIL_X, COL_DETAIL_W = 292, 150
local COL_AMOUNT_W = 130
local TABLE_W = FRAME_W - 56
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
  return date("%Y-%m-%d %H:%M", at)
end

local function kindLabel(kind)
  if kind == "ah" then
    return Fundraiser:T("LEDGER_KIND_AH")
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
    canEditMotd = function()
      return Roster:CanEditMotd()
    end,
    setMotd = function(text)
      return Roster:SetMotd(text)
    end,
  }
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

function Ledger:Ensure()
  if self.frame then
    return self.frame
  end

  local f = CreateFrame("Frame", "FundraiserLedgerFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(FRAME_W, FRAME_H)
  f:SetPoint("CENTER", 20, 0)
  -- Above the admin window (MEDIUM) so it never opens behind it; still under popups (DIALOG).
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  if f.TitleText then
    f.TitleText:SetText(Fundraiser:T("LEDGER_WINDOW_TITLE"))
  end
  tinsert(UISpecialFrames, "FundraiserLedgerFrame")

  f.total = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
  f.total:SetPoint("TOPLEFT", 16, -34)

  f.summary = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  f.summary:SetPoint("TOPLEFT", 16, -58)

  f.hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.hint:SetPoint("TOPLEFT", 16, -78)
  f.hint:SetWidth(FRAME_W - 40)
  f.hint:SetJustifyH("LEFT")

  local refresh = CreateFrame("Button", "FundraiserLedgerRefresh", f, "UIPanelButtonTemplate")
  refresh:SetSize(90, 22)
  refresh:SetPoint("TOPRIGHT", -14, -32)
  refresh:SetText(Fundraiser:T("BTN_REFRESH"))
  refresh:SetScript("OnClick", function()
    Ledger:Refresh()
  end)

  local motd = CreateFrame("Button", "FundraiserLedgerSetMotd", f, "UIPanelButtonTemplate")
  motd:SetSize(100, 22)
  motd:SetPoint("RIGHT", refresh, "LEFT", -6, 0)
  motd:SetText(Fundraiser:T("BTN_SET_MOTD"))
  motd:SetScript("OnClick", function()
    Ledger:ConfirmSetMotd()
  end)
  motd:SetScript("OnEnter", function(self)
    showTooltip(self, "TIP_SET_MOTD_TITLE", "TIP_SET_MOTD_BODY")
  end)
  motd:SetScript("OnLeave", hideTooltip)
  f.motdBtn = motd

  -- Column headers.
  local header = CreateFrame("Frame", nil, f)
  header:SetPoint("TOPLEFT", 14, LIST_TOP + 18)
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

  local scroll = CreateFrame("ScrollFrame", "FundraiserLedgerScroll", f, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, LIST_TOP)
  scroll:SetPoint("BOTTOMRIGHT", -34, 14)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, function()
      Ledger:UpdateRows()
    end)
  end)
  f.scroll = scroll

  f.rows = {}
  for i = 1, ROWS do
    local r = CreateFrame("Frame", nil, f)
    r:SetSize(TABLE_W, ROW_H)
    addGrid(r, true)
    r:SetPoint("TOPLEFT", 14, LIST_TOP - (i - 1) * ROW_H)
    r.time = makeCell(r, "GameFontHighlightSmall", COL_TIME_X, COL_TIME_W)
    r.name = makeCell(r, "GameFontHighlightSmall", COL_NAME_X, COL_NAME_W)
    r.detail = makeCell(r, "GameFontHighlightSmall", COL_DETAIL_X, COL_DETAIL_W)
    r.amount = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.amount:SetPoint("RIGHT", -4, 0)
    r.amount:SetWidth(COL_AMOUNT_W)
    r.amount:SetJustifyH("RIGHT")
    f.rows[i] = r
  end

  f:SetScript("OnShow", function()
    Ledger:Refresh()
  end)

  self.frame = f
  return f
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

local function setColor(row, color)
  row.time:SetTextColor(color[1], color[2], color[3])
  row.name:SetTextColor(color[1], color[2], color[3])
  row.detail:SetTextColor(color[1], color[2], color[3])
end

function Ledger:UpdateRows()
  local f = self:Ensure()
  local items = self.items or {}
  FauxScrollFrame_Update(f.scroll, #items, ROWS, ROW_H)
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
  f.motdBtn:Hide()
  self:UpdateRows()
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

  if view.hasEvent and Roster:CanEditMotd() then
    f.motdBtn:Show()
  else
    f.motdBtn:Hide()
  end
  self:UpdateRows()
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

function Ledger:Hide()
  if self.frame then
    self.frame:Hide()
  end
end

function Ledger:Toggle()
  local f = self:Ensure()
  if f:IsShown() then
    f:Hide()
  else
    f:Show()
  end
end
