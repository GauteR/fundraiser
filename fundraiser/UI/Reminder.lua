-- Lightweight reminder panel shown on bag open.
Fundraiser = Fundraiser or {}
Fundraiser.UI = Fundraiser.UI or {}

local Reminder = {}
Fundraiser.UI.Reminder = Reminder

function Reminder:EnsureFrame()
  if self.frame then
    return self.frame
  end
  local f = CreateFrame("Frame", "FundraiserReminderFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(420, 120)
  f:SetPoint("TOP", UIParent, "TOP", 0, -80)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()

  if f.TitleText then
    f.TitleText:SetText(Fundraiser:T("ADDON_NAME"))
  end

  local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("TOPLEFT", 16, -32)
  text:SetPoint("BOTTOMRIGHT", -16, 16)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("TOP")
  text:SetWordWrap(true)
  f.text = text

  tinsert(UISpecialFrames, "FundraiserReminderFrame")
  self.frame = f
  return f
end

function Reminder:ShowForEvent(event)
  local f = self:EnsureFrame()
  local guild = (Fundraiser.Adapters.Roster:GetGuildName()) or "Guild"
  f.text:SetText(Fundraiser:T("REMINDER_FMT", guild, event.name, event.target))
  f:Show()
end

function Reminder:Hide()
  if self.frame then
    self.frame:Hide()
  end
end
