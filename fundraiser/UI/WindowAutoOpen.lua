-- Opens the shell window by itself: the Target page when a vendor opens, the ledger when the
-- mailbox opens. Which page (if any) is decided by Domain/ShellPages.lua from the Config flags
-- TARGET_AUTO_OPEN_VENDOR / LEDGER_AUTO_OPEN_MAILBOX and the player's access.
Fundraiser = Fundraiser or {}
Fundraiser.UI = Fundraiser.UI or {}

local AutoOpen = {}
Fundraiser.UI.WindowAutoOpen = AutoOpen

local OPEN_EVENTS = {
  MERCHANT_SHOW = "vendor",
  MAIL_SHOW = "mailbox",
}
local CLOSE_EVENTS = {
  MERCHANT_CLOSED = "vendor",
  MAIL_CLOSED = "mailbox",
}
-- Forever may omit the close events (see Adapters/MailboxReminder.lua): also watch the client
-- frames. Only the top frame: tab switches inside the mail window hide its child frames.
local CLIENT_FRAMES = { vendor = "MerchantFrame", mailbox = "MailFrame" }

local function closed(trigger)
  local Window = Fundraiser.UI and Fundraiser.UI.Window
  if Window then
    Window:CloseFor(trigger)
  end
end

function AutoOpen:HookFrames()
  self.hooked = self.hooked or {}
  for trigger, name in pairs(CLIENT_FRAMES) do
    local frame = _G[name]
    if frame and frame.HookScript and not self.hooked[name] then
      self.hooked[name] = true
      frame:HookScript("OnHide", function()
        closed(trigger)
      end)
    end
  end
end

function AutoOpen:Handle(event)
  if CLOSE_EVENTS[event] then
    closed(CLOSE_EVENTS[event])
    return
  end
  local trigger = OPEN_EVENTS[event]
  local Window = Fundraiser.UI and Fundraiser.UI.Window
  if not trigger or not Window or not Fundraiser:IsEnabled() then
    return
  end
  self:HookFrames()
  local page, anchor = Fundraiser.Domain.ShellPages.AutoOpen(trigger, Fundraiser.Config, Window:Access())
  if page then
    Window:OpenPage(page, trigger, anchor)
  end
end

-- Called once at login.
function AutoOpen:Initialize()
  if self.initialized then
    return
  end
  local cfg = Fundraiser.Config or {}
  if not (cfg.TARGET_AUTO_OPEN_VENDOR or cfg.LEDGER_AUTO_OPEN_MAILBOX) then
    return
  end
  local ev = CreateFrame("Frame", "FundraiserWindowAutoOpenEvents")
  for event in pairs(OPEN_EVENTS) do
    ev:RegisterEvent(event)
  end
  for event in pairs(CLOSE_EVENTS) do
    ev:RegisterEvent(event)
  end
  self:HookFrames()
  ev:SetScript("OnEvent", function(_, event)
    AutoOpen:Handle(event)
  end)
  self.initialized = true
end
