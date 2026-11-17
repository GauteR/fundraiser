-- Donor: dismiss reminder after mailing the target.
-- Target: log incoming player mail (money/items) into the ledger.
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local Mail = {}
Fundraiser.Adapters.Mail = Mail

local function normalizeName(name)
  return Fundraiser.Domain.Roles.NormalizeName(name)
end

local function now()
  return (GetServerTime and GetServerTime()) or (time and time()) or 0
end

function Mail:IsDonationTarget()
  local Store = Fundraiser.Adapters.Store
  local Roster = Fundraiser.Adapters.Roster
  local event = Store:GetEvent()
  return Fundraiser.Domain.Roles.IsDonationTarget(event, Roster:GetPlayerName())
end

function Mail:Initialize()
  if self.initialized then
    return
  end
  if not Fundraiser:IsEnabled() then
    return
  end

  local frame = CreateFrame("Frame", "FundraiserMailFrame")
  if Fundraiser.Config and Fundraiser.Config.REMINDER then
    frame:RegisterEvent("MAIL_SEND_SUCCESS")
  end
  if Fundraiser.Config and Fundraiser.Config.LEDGER then
    frame:RegisterEvent("MAIL_INBOX_UPDATE")
  end
  frame:SetScript("OnEvent", function(_, event)
    if event == "MAIL_SEND_SUCCESS" then
      self:OnSendSuccess()
    elseif event == "MAIL_INBOX_UPDATE" then
      self:ScanInbox()
    end
  end)

  if Fundraiser.Config and Fundraiser.Config.REMINDER and type(hooksecurefunc) == "function" and SendMail then
    hooksecurefunc("SendMail", function(target, _subject, _body)
      self.pendingTarget = target
      local copper = 0
      if GetSendMailMoney then
        copper = GetSendMailMoney() or 0
      end
      self.pendingCopper = copper
    end)
  end

  self.seenMail = self.seenMail or {}
  self.frame = frame
  self.initialized = true
end

function Mail:OnSendSuccess()
  local Store = Fundraiser.Adapters.Store
  local event = Store:GetEvent()
  if not event then
    return
  end
  local target = normalizeName(self.pendingTarget)
  local expected = normalizeName(event.target)
  if not target or not expected or target ~= expected then
    self.pendingTarget = nil
    self.pendingCopper = nil
    return
  end

  local UC = Fundraiser.Application.UseCases
  UC.DismissReminder({
    getReminderState = function()
      return Store:GetReminderState()
    end,
    setReminderState = function(s)
      Store:SetReminderState(s)
    end,
  }, now(), event.id)

  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("CHAT_MAIL_SENT_DISMISS", event.target))
  end
  if Fundraiser.UI and Fundraiser.UI.Reminder and Fundraiser.UI.Reminder.Hide then
    Fundraiser.UI.Reminder:Hide()
  end

  self.pendingTarget = nil
  self.pendingCopper = nil
end

function Mail:ScanInbox()
  if not (Fundraiser.Config and Fundraiser.Config.LEDGER) then
    return
  end
  if not self:IsDonationTarget() then
    return
  end
  if not GetInboxNumItems or not GetInboxHeaderInfo then
    return
  end

  local Store = Fundraiser.Adapters.Store
  local event = Store:GetEvent()
  if not event then
    return
  end

  local n = GetInboxNumItems() or 0
  local Roster = Fundraiser.Adapters.Roster
  local UC = Fundraiser.Application.UseCases
  local deps = {
    getEvent = function()
      return Store:GetEvent()
    end,
    getContributions = function()
      return Store:GetContributions()
    end,
    setContributions = function(list)
      Store:SetContributions(list)
    end,
    broadcastLedgerEntry = function(entry)
      Fundraiser.Adapters.ThinGuildSync:BroadcastLedgerEntry(entry)
    end,
  }
  local actor = { name = Roster:GetPlayerName() }

  for i = 1, n do
    local _, _, sender, subject, money, CODAmount, _, hasItem = GetInboxHeaderInfo(i)
    money = tonumber(money) or 0
    CODAmount = tonumber(CODAmount) or 0
    if CODAmount <= 0 and sender and (money > 0 or hasItem) then
      local id = string.format("mail:%s:%s:%d:%s", tostring(sender), tostring(subject or ""), money, tostring(hasItem and 1 or 0))
      if not self.seenMail[id] then
        self.seenMail[id] = true
        UC.AppendLedgerEntry(deps, {
          id = id,
          kind = "mail",
          name = sender:match("^([^%-]+)") or sender,
          detail = subject or "",
          copper = money,
          eventId = event.id,
          at = now(),
        }, actor)
      end
    end
  end
end
