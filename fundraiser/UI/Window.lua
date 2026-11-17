-- Admin / member overview window.
Fundraiser = Fundraiser or {}
Fundraiser.UI = Fundraiser.UI or {}

local Window = {}
Fundraiser.UI.Window = Window

local function money(copper)
  if Fundraiser.FormatCopper then
    return Fundraiser.FormatCopper(copper)
  end
  return tostring(copper or 0) .. "c"
end

function Window:Ensure()
  if self.frame then
    return self.frame
  end

  local f = CreateFrame("Frame", "FundraiserFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(520, 480)
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

  local y = -36

  local function label(text, dy)
    local fs = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetText(text)
    y = y - (dy or 18)
    return fs
  end

  label(Fundraiser:T("SECTION_EVENT"), 20)

  local function editBox(name, width)
    local eb = CreateFrame("EditBox", name, f, "InputBoxTemplate")
    eb:SetSize(width or 280, 20)
    eb:SetPoint("TOPLEFT", 16, y)
    eb:SetAutoFocus(false)
    y = y - 28
    return eb
  end

  label(Fundraiser:T("LABEL_EVENT_NAME"))
  f.eventName = editBox("FundraiserEventName")
  label(Fundraiser:T("LABEL_TARGET"))
  f.target = editBox("FundraiserTarget")
  label(Fundraiser:T("LABEL_INTERVAL"))
  f.interval = editBox("FundraiserInterval", 80)
  label(Fundraiser:T("LABEL_MIN_ADMIN_RANK"))
  f.minRank = editBox("FundraiserMinRank", 80)
  label(Fundraiser:T("LABEL_GOAL"))
  f.goal = editBox("FundraiserGoal", 400)

  local publish = CreateFrame("Button", "FundraiserPublishButton", f, "UIPanelButtonTemplate")
  publish:SetSize(140, 24)
  publish:SetPoint("TOPLEFT", 16, y)
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

  local targetBtn = CreateFrame("Button", "FundraiserTargetOpenButton", f, "UIPanelButtonTemplate")
  targetBtn:SetSize(140, 24)
  targetBtn:SetPoint("LEFT", refresh, "RIGHT", 8, 0)
  targetBtn:SetText(Fundraiser:T("BTN_TARGET_UI"))
  targetBtn:SetScript("OnClick", function()
    if Fundraiser.UI.Target then
      Fundraiser.UI.Target:Toggle()
    end
  end)
  f.targetBtn = targetBtn
  y = y - 36

  label(Fundraiser:T("SECTION_LEDGER"), 20)
  f.ledgerTotal = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  f.ledgerTotal:SetPoint("TOPLEFT", 16, y)
  y = y - 18
  f.ledgerBody = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.ledgerBody:SetPoint("TOPLEFT", 16, y)
  f.ledgerBody:SetWidth(480)
  f.ledgerBody:SetJustifyH("LEFT")
  f.ledgerBody:SetJustifyV("TOP")
  y = y - 100

  label(Fundraiser:T("SECTION_PRESENCE"), 20)
  f.presenceBody = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.presenceBody:SetPoint("TOPLEFT", 16, y)
  f.presenceBody:SetWidth(480)
  f.presenceBody:SetJustifyH("LEFT")
  f.presenceBody:SetJustifyV("TOP")

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
  local hours = tonumber(f.interval:GetText()) or 24
  local fields = {
    name = f.eventName:GetText(),
    target = f.target:GetText(),
    goal = f.goal:GetText(),
    intervalSeconds = math.floor(hours * 3600),
    minAdminRank = tonumber(f.minRank:GetText()) or 0,
  }
  local deps = {
    getEvent = function()
      return Store:GetEvent()
    end,
    setEvent = function(e)
      Store:SetEvent(e)
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
      local msg = err == "not_admin" and Fundraiser:T("CHAT_NOT_ADMIN") or tostring(err)
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
  local event = Store:GetEvent()

  if event then
    f.eventName:SetText(event.name or "")
    f.target:SetText(event.target or "")
    f.interval:SetText(tostring((event.intervalSeconds or 0) / 3600))
    f.minRank:SetText(tostring(event.minAdminRank or 0))
    f.goal:SetText(event.goal or "")
  end

  local Roles = Fundraiser.Domain.Roles
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
    f.ledgerTotal:SetText(Fundraiser:T("LEDGER_TOTAL_FMT", money(total)))
    if #rows == 0 then
      f.ledgerBody:SetText(Fundraiser:T("LEDGER_EMPTY") .. "\n" .. Fundraiser:T("LEDGER_DEDICATED_HINT"))
    else
      local lines = { Fundraiser:T("LEDGER_DEDICATED_HINT") }
      for _, row in ipairs(rows) do
        lines[#lines + 1] = string.format("[%s] %s %s — %s", row.kind or "?", row.name or "?", row.detail or "", money(row.copper))
      end
      f.ledgerBody:SetText(table.concat(lines, "\n"))
    end
  else
    f.ledgerTotal:SetText("")
    f.ledgerBody:SetText(Fundraiser:T("LEDGER_OFFICER_ONLY"))
  end

  if f.targetBtn then
    local showTarget = Fundraiser.Config.TARGET_UI
      and event
      and Roles.IsDonationTarget(event, Roster:GetPlayerName())
    if showTarget then
      f.targetBtn:Show()
    else
      f.targetBtn:Hide()
    end
  end

  local now = (GetServerTime and GetServerTime()) or (time and time()) or 0
  Roster:Request()
  local missing = UC.ListMissingInstalls({
    getRoster = function()
      return Roster:GetMembers()
    end,
    getPresence = function()
      return Store:GetPresence()
    end,
    presenceStale = Fundraiser.Config.PRESENCE_STALE,
  }, now)
  if #missing == 0 then
    f.presenceBody:SetText(Fundraiser:T("PRESENCE_EMPTY"))
  else
    local lines = {}
    for _, m in ipairs(missing) do
      local status = m.status == "missing" and Fundraiser:T("STATUS_MISSING") or Fundraiser:T("STATUS_UNKNOWN")
      lines[#lines + 1] = string.format("%s — %s", m.name, status)
    end
    f.presenceBody:SetText(table.concat(lines, "\n"))
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
