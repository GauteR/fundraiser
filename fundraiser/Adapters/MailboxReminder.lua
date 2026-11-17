-- Show fundraiser reminder when the mailbox opens; hide when it closes.
-- Forever may not fire MAIL_CLOSED reliably — also hook MailFrame OnHide / CloseMail.
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local MailboxReminder = {}
Fundraiser.Adapters.MailboxReminder = MailboxReminder

local function hookOnHide(frame, handler)
  if not frame or frame._FundraiserMailHideHooked then
    return
  end
  frame._FundraiserMailHideHooked = true
  if frame.HookScript then
    frame:HookScript("OnHide", handler)
  else
    local prev = frame:GetScript("OnHide")
    frame:SetScript("OnHide", function(...)
      if prev then
        prev(...)
      end
      handler(...)
    end)
  end
end

function MailboxReminder:HookMailFrames()
  local handler = function()
    self:OnMailClosed()
  end
  hookOnHide(MailFrame, handler)
  hookOnHide(InboxFrame, handler)
  hookOnHide(SendMailFrame, handler)
end

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
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:SetScript("OnEvent", function(_, event)
    if event == "MAIL_SHOW" then
      self:HookMailFrames()
      self:OnMailShow()
    elseif event == "MAIL_CLOSED" or event == "PLAYER_ENTERING_WORLD" then
      self:OnMailClosed()
    end
  end)

  if type(hooksecurefunc) == "function" and CloseMail then
    hooksecurefunc("CloseMail", function()
      self:OnMailClosed()
    end)
  end
  if type(hooksecurefunc) == "function" and HideUIPanel then
    hooksecurefunc("HideUIPanel", function(panel)
      if panel == MailFrame or panel == InboxFrame then
        self:OnMailClosed()
      end
    end)
  end

  self:HookMailFrames()
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
