-- Show fundraiser reminder when bags open.
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local Bags = {}
Fundraiser.Adapters.Bags = Bags

function Bags:Initialize()
  if self.initialized then
    return
  end
  if not Fundraiser:IsEnabled() or not (Fundraiser.Config and Fundraiser.Config.REMINDER) then
    return
  end

  -- Do not use BAG_UPDATE (fires on item moves). Hook open/toggle only.
  local function hook(name)
    if type(hooksecurefunc) == "function" and _G[name] then
      hooksecurefunc(name, function()
        self:OnBagsTouched()
      end)
    end
  end
  hook("OpenAllBags")
  hook("ToggleBackpack")
  hook("ToggleAllBags")
  hook("OpenBag")

  self.initialized = true
end

function Bags:OnBagsTouched()
  if Fundraiser.UI and Fundraiser.UI.Reminder and Fundraiser.UI.Reminder.frame and Fundraiser.UI.Reminder.frame:IsShown() then
    return
  end
  local Store = Fundraiser.Adapters.Store
  local UC = Fundraiser.Application.UseCases
  local now = (GetServerTime and GetServerTime()) or (time and time()) or 0
  local Roster = Fundraiser.Adapters.Roster
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
