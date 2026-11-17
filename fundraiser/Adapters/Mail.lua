-- Detect outgoing mail to the designated donation target.
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local Mail = {}
Fundraiser.Adapters.Mail = Mail

local function normalizeName(name)
  if not name then
    return nil
  end
  name = tostring(name)
  name = name:match("^([^%-]+)") or name
  return name:lower()
end

function Mail:Initialize()
  if self.initialized then
    return
  end
  if not Fundraiser:IsEnabled() or not (Fundraiser.Config and Fundraiser.Config.REMINDER) then
    return
  end

  local frame = CreateFrame("Frame", "FundraiserMailFrame")
  -- Capture intended recipient/money before send; confirm on success.
  frame:RegisterEvent("MAIL_SEND_SUCCESS")
  frame:SetScript("OnEvent", function(_, event)
    if event == "MAIL_SEND_SUCCESS" then
      self:OnSendSuccess()
    end
  end)

  -- Hook SendMail when available to remember target + copper.
  if type(hooksecurefunc) == "function" and SendMail then
    hooksecurefunc("SendMail", function(target, _subject, _body)
      self.pendingTarget = target
      local copper = 0
      if GetSendMailMoney then
        copper = GetSendMailMoney() or 0
      end
      self.pendingCopper = copper
    end)
  end

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

  local now = (GetServerTime and GetServerTime()) or (time and time()) or 0
  local Roster = Fundraiser.Adapters.Roster
  local UC = Fundraiser.Application.UseCases
  local copper = tonumber(self.pendingCopper) or 0

  local deps = {
    getReminderState = function()
      return Store:GetReminderState()
    end,
    setReminderState = function(s)
      Store:SetReminderState(s)
    end,
    getContributions = function()
      return Store:GetContributions()
    end,
    setContributions = function(list)
      Store:SetContributions(list)
    end,
    broadcastDonation = function(entry)
      Fundraiser.Adapters.ThinGuildSync:BroadcastDonation(entry)
    end,
  }

  UC.DismissReminder(deps, now, event.id)
  local entry = {
    guid = Roster:GetPlayerGUID() or Roster:GetPlayerName() or "player",
    name = Roster:GetPlayerName() or "player",
    eventId = event.id,
    copper = copper,
    at = now,
  }
  UC.RecordDonation(deps, entry)

  if DEFAULT_CHAT_FRAME then
    local money = Fundraiser.FormatCopper and Fundraiser.FormatCopper(copper) or tostring(copper)
    DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("CHAT_DONATION_RECORDED", money, event.target))
  end

  if Fundraiser.UI and Fundraiser.UI.Reminder and Fundraiser.UI.Reminder.Hide then
    Fundraiser.UI.Reminder:Hide()
  end

  self.pendingTarget = nil
  self.pendingCopper = nil
end
