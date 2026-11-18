-- Admin window: officer event form + publish, ledger summary, links to Settings / Target.
-- Presence lives in Options (Settings -> AddOns -> Fundraiser). Summary data comes from
-- Domain/AdminSummary.lua so the rendering here stays thin.
Fundraiser = Fundraiser or {}
Fundraiser.UI = Fundraiser.UI or {}

local Window = {}
Fundraiser.UI.Window = Window

local FRAME_WIDTH = 480
local FRAME_HEIGHT = 440
local MARGIN = 16
local CONTENT_WIDTH = FRAME_WIDTH - 2 * MARGIN
local LABEL_WIDTH = 190
local FIELD_X = 214
local ROW_HEIGHT = 30

local function money(copper)
  if Fundraiser.FormatCopper then
    return Fundraiser.FormatCopper(copper)
  end
  return tostring(copper or 0) .. "c"
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

function Window:Ensure()
  if self.frame then
    return self.frame
  end

  local f = CreateFrame("Frame", "FundraiserFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  if f.TitleText then
    f.TitleText:SetText(Fundraiser:T("WINDOW_TITLE"))
  end
  tinsert(UISpecialFrames, "FundraiserFrame")

  local y = -34

  local function divider(at)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetSize(CONTENT_WIDTH, 1)
    line:SetPoint("TOPLEFT", MARGIN, at)
    return line
  end

  local function section(text)
    local fs = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", MARGIN, y)
    fs:SetText(text)
    divider(y - 18)
    y = y - 28
    return fs
  end

  local function field(labelKey, name, width)
    local fs = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", MARGIN, y - 3)
    fs:SetWidth(LABEL_WIDTH)
    fs:SetJustifyH("LEFT")
    fs:SetText(Fundraiser:T(labelKey))
    local eb = CreateFrame("EditBox", name, f, "InputBoxTemplate")
    eb:SetSize(width, 20)
    eb:SetPoint("TOPLEFT", FIELD_X, y)
    eb:SetAutoFocus(false)
    y = y - ROW_HEIGHT
    return eb
  end

  -- Status header: event name + one-line detail.
  f.statusTitle = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  f.statusTitle:SetPoint("TOPLEFT", MARGIN, y)
  f.statusTitle:SetWidth(CONTENT_WIDTH)
  f.statusTitle:SetJustifyH("LEFT")
  f.statusDetail = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.statusDetail:SetPoint("TOPLEFT", f.statusTitle, "BOTTOMLEFT", 0, -4)
  f.statusDetail:SetWidth(CONTENT_WIDTH)
  f.statusDetail:SetJustifyH("LEFT")
  y = y - 48

  -- Event form.
  section(Fundraiser:T("SECTION_EVENT_FORM"))
  f.eventName = field("LABEL_EVENT_NAME", "FundraiserEventName", 240)
  f.target = field("LABEL_TARGET", "FundraiserTarget", 240)
  f.interval = field("LABEL_INTERVAL", "FundraiserInterval", 60)
  local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("LEFT", f.interval, "RIGHT", 10, 0)
  hint:SetWidth(FRAME_WIDTH - FIELD_X - 60 - 10 - MARGIN)
  hint:SetJustifyH("LEFT")
  hint:SetText(Fundraiser:T("LABEL_INTERVAL_HINT"))
  f.goal = field("LABEL_GOAL", "FundraiserGoal", 240)

  -- Actions.
  local publish = CreateFrame("Button", "FundraiserPublishButton", f, "UIPanelButtonTemplate")
  publish:SetSize(140, 24)
  publish:SetPoint("TOPLEFT", MARGIN, y - 4)
  publish:SetText(Fundraiser:T("BTN_PUBLISH"))
  publish:SetScript("OnClick", function()
    Window:Publish()
  end)

  local refresh = CreateFrame("Button", "FundraiserRefreshButton", f, "UIPanelButtonTemplate")
  refresh:SetSize(100, 24)
  refresh:SetPoint("LEFT", publish, "RIGHT", 8, 0)
  refresh:SetText(Fundraiser:T("BTN_REFRESH"))
  refresh:SetScript("OnClick", function()
    Window:Refresh()
  end)

  local settingsBtn = CreateFrame("Button", "FundraiserAddonSettingsButton", f, "UIPanelButtonTemplate")
  settingsBtn:SetSize(120, 24)
  settingsBtn:SetPoint("LEFT", refresh, "RIGHT", 8, 0)
  settingsBtn:SetText(Fundraiser:T("BTN_ADDON_SETTINGS"))
  settingsBtn:SetScript("OnClick", function()
    if Fundraiser.Options and Fundraiser.Options.Open then
      Fundraiser.Options:Open()
    end
  end)
  y = y - 44

  -- Ledger summary card.
  section(Fundraiser:T("SECTION_LEDGER"))
  f.ledgerTotal = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  f.ledgerTotal:SetPoint("TOPLEFT", MARGIN, y)
  f.ledgerTotal:SetWidth(CONTENT_WIDTH)
  f.ledgerTotal:SetJustifyH("LEFT")
  y = y - 20
  f.ledgerBody = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.ledgerBody:SetPoint("TOPLEFT", MARGIN, y)
  f.ledgerBody:SetWidth(CONTENT_WIDTH)
  f.ledgerBody:SetJustifyH("LEFT")
  f.ledgerBody:SetJustifyV("TOP")
  y = y - 50

  local ledgerBtn = CreateFrame("Button", "FundraiserOpenLedgerButton", f, "UIPanelButtonTemplate")
  ledgerBtn:SetSize(140, 24)
  ledgerBtn:SetPoint("TOPLEFT", MARGIN, y)
  ledgerBtn:SetText(Fundraiser:T("BTN_OPEN_LEDGER"))
  -- Disabled until the dedicated ledger window exists (#15).
  ledgerBtn:Disable()
  ledgerBtn:SetScript("OnEnter", function(self)
    showTooltip(self, "TIP_OPEN_LEDGER_TITLE", "TIP_OPEN_LEDGER_BODY")
  end)
  ledgerBtn:SetScript("OnLeave", hideTooltip)
  f.ledgerBtn = ledgerBtn

  local targetBtn = CreateFrame("Button", "FundraiserTargetOpenButton", f, "UIPanelButtonTemplate")
  targetBtn:SetSize(160, 24)
  targetBtn:SetPoint("LEFT", ledgerBtn, "RIGHT", 8, 0)
  targetBtn:SetText(Fundraiser:T("BTN_TARGET_UI"))
  targetBtn:SetScript("OnClick", function()
    if Fundraiser.UI.Target then
      Fundraiser.UI.Target:Toggle()
    end
  end)
  f.targetBtn = targetBtn

  f:SetScript("OnShow", function()
    Window:Refresh()
  end)

  self.frame = f
  return f
end

function Window:Publish()
  local f = self:Ensure()
  local Store = Fundraiser.Adapters.Store
  local Roster = Fundraiser.Adapters.Roster
  local UC = Fundraiser.Application.UseCases
  local hours = tonumber(f.interval:GetText())
  local intervalSeconds
  if hours then
    intervalSeconds = math.floor(hours * 3600)
  else
    intervalSeconds = (Fundraiser.Config and tonumber(Fundraiser.Config.DEFAULT_REMINDER_INTERVAL)) or 86400
  end
  local fields = {
    name = f.eventName:GetText(),
    target = f.target:GetText(),
    goal = f.goal:GetText(),
    intervalSeconds = intervalSeconds,
  }
  local deps = {
    getEvent = function()
      return Store:GetEvent()
    end,
    setEvent = function(e)
      Store:SetEvent(e)
    end,
    getContributions = function()
      return Store:GetContributions()
    end,
    archiveEvent = function(event, contributions, archivedAt)
      Store:ArchiveEvent(event, contributions, archivedAt)
    end,
    clearContributions = function()
      Store:ClearLedger()
    end,
    clearReminder = function()
      Store:SetReminderState({})
    end,
    broadcastEvent = function(e)
      Fundraiser.Adapters.ThinGuildSync:BroadcastEvent(e)
    end,
  }
  local actor = {
    rankIndex = Roster:GetPlayerRankIndex(),
    name = Roster:GetPlayerName(),
    now = (GetServerTime and GetServerTime()) or (time and time()) or 0,
  }
  local event, err = UC.PublishEvent(deps, fields, actor)
  if not event then
    if DEFAULT_CHAT_FRAME then
      local msg = err == "not_admin" and Fundraiser:T("CHAT_NOT_ADMIN")
        or err == "target_need_full_name" and Fundraiser:T("CHAT_TARGET_NEED_FULL_NAME")
        or tostring(err)
      DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. msg)
    end
    return
  end
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("CHAT_EVENT_PUBLISHED", event.name))
  end
  self:Refresh()
end

function Window:Refresh()
  local f = self:Ensure()
  local Store = Fundraiser.Adapters.Store
  local Roster = Fundraiser.Adapters.Roster
  local UC = Fundraiser.Application.UseCases
  local Summary = Fundraiser.Domain.AdminSummary
  local Roles = Fundraiser.Domain.Roles
  local event = Store:GetEvent()

  local status = Summary.EventStatus(event)
  if status.hasEvent then
    f.statusTitle:SetText(status.name)
    f.statusDetail:SetText(
      Fundraiser:T("STATUS_EVENT_DETAIL_FMT", status.target, string.format("%g", status.intervalHours), status.revision)
    )
    f.eventName:SetText(event.name or "")
    f.target:SetText(event.target or "")
    f.interval:SetText(tostring((event.intervalSeconds or 0) / 3600))
    f.goal:SetText(event.goal or "")
  else
    f.statusTitle:SetText(Fundraiser:T("SECTION_EVENT"))
    f.statusDetail:SetText(Fundraiser:T("STATUS_NO_EVENT"))
    local defaultSeconds = (Fundraiser.Config and tonumber(Fundraiser.Config.DEFAULT_REMINDER_INTERVAL)) or 86400
    f.interval:SetText(tostring(defaultSeconds / 3600))
  end

  local canLedger = Fundraiser.Config.LEDGER
    and event
    and Roles.CanViewLedger(event, Roster:GetPlayerRankIndex(), Roster:GetPlayerName())
  if canLedger then
    local rows, total = UC.GetLedger({
      getEvent = function()
        return Store:GetEvent()
      end,
      getContributions = function()
        return Store:GetContributions()
      end,
      getPlayerName = function()
        return Roster:GetPlayerName()
      end,
      getPlayerRankIndex = function()
        return Roster:GetPlayerRankIndex()
      end,
    }, event.id)
    local ledger = Summary.Ledger(rows, total)
    f.ledgerTotal:SetText(
      Fundraiser:T("LEDGER_TOTAL_FMT", money(ledger.total)) .. "  (" .. Fundraiser:T("LEDGER_COUNT_FMT", ledger.count) .. ")"
    )
    if ledger.count == 0 then
      f.ledgerBody:SetText(Fundraiser:T("LEDGER_EMPTY"))
    else
      local lines = {}
      for _, row in ipairs(ledger.recent) do
        lines[#lines + 1] = Fundraiser:T("LEDGER_RECENT_FMT", row.kind or "?", row.name or "?", money(row.copper))
      end
      f.ledgerBody:SetText(table.concat(lines, "\n"))
    end
  else
    f.ledgerTotal:SetText("")
    f.ledgerBody:SetText(Fundraiser:T("LEDGER_OFFICER_ONLY"))
  end

  local showTarget = Fundraiser.Config.TARGET_UI
    and event
    and Roles.IsDonationTarget(event, Roster:GetPlayerName())
  if showTarget then
    f.targetBtn:Show()
  else
    f.targetBtn:Hide()
  end
end

function Window:Hide()
  if self.frame then
    self.frame:Hide()
  end
end

function Window:Toggle()
  local f = self:Ensure()
  if f:IsShown() then
    f:Hide()
  else
    f:Show()
  end
end
