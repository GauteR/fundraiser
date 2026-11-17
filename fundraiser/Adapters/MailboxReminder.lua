-- Show fundraiser reminder when the mailbox opens; hide when it closes.
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local MailboxReminder = {}
Fundraiser.Adapters.MailboxReminder = MailboxReminder

function MailboxReminder:Initialize()
  if self.initialized then
    return
  end
  if not Fundraiser:IsEnabled() or not (Fundraiser.Config and Fundraiser.Config.REMINDER) then
    return
  end

  local frame = CreateFrame("Frame", "FundraiserMailboxReminderFrame")
  frame:RegisterEvent("MAIL_SHOW")
  frame:RegisterEvent("MAIL_CLOSED")
  frame:SetScript("OnEvent", function(_, event)
    if event == "MAIL_SHOW" then
      self:OnMailShow()
    elseif event == "MAIL_CLOSED" then
      self:OnMailClosed()
    end
  end)

  self.frame = frame
  self.initialized = true
end

function MailboxReminder:OnMailShow()
  local Store = Fundraiser.Adapters.Store
  local UC = Fundraiser.Application.UseCases
  local Roster = Fundraiser.Adapters.Roster
  local now = (GetServerTime and GetServerTime()) or (time and time()) or 0
  local deps = {
    getEvent = function()
      return Store:GetEvent()
    end,
    getReminderState = function()
      return Store:GetReminderState()
    end,
    getPlayerName = function()
      return Roster:GetPlayerName()
    end,
  }
  local should, event = UC.ShouldShowReminder(deps, now)
  if not should or not event then
    return
  end
  if Fundraiser.UI and Fundraiser.UI.Reminder and Fundraiser.UI.Reminder.ShowForEvent then
    Fundraiser.UI.Reminder:ShowForEvent(event)
    local Reminder = Fundraiser.Domain.Reminder
    local state = Store:GetReminderState()
    Store:SetReminderState(Reminder.MarkShown(state, now, event.id))
  end
end

function MailboxReminder:OnMailClosed()
  if Fundraiser.UI and Fundraiser.UI.Reminder and Fundraiser.UI.Reminder.Hide then
    Fundraiser.UI.Reminder:Hide()
  end
end
