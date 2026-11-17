-- Reminder panel anchored beside the mailbox while it is open.
Fundraiser = Fundraiser or {}
Fundraiser.UI = Fundraiser.UI or {}

local Reminder = {}
Fundraiser.UI.Reminder = Reminder

local function mailAnchor()
  if MailFrame and MailFrame:IsShown() then
    return MailFrame
  end
  if InboxFrame and InboxFrame:IsShown() then
    return InboxFrame
  end
  return nil
end

function Reminder:EnsureFrame()
  if self.frame then
    return self.frame
  end
  local f = CreateFrame("Frame", "FundraiserReminderFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(320, 140)
  f:SetMovable(false)
  f:EnableMouse(true)
  f:Hide()

  if f.TitleText then
    f.TitleText:SetText(Fundraiser:T("ADDON_NAME"))
  end

  local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("TOPLEFT", 14, -30)
  text:SetPoint("BOTTOMRIGHT", -14, 14)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("TOP")
  text:SetWordWrap(true)
  f.text = text

  -- Not in UISpecialFrames: lifecycle follows MAIL_SHOW / MAIL_CLOSED.
  self.frame = f
  return f
end

function Reminder:AnchorToMailbox()
  local f = self:EnsureFrame()
  f:ClearAllPoints()
  local anchor = mailAnchor()
  if anchor then
    -- Prefer right of mailbox; flip to left if little room on the right.
    local right = anchor:GetRight()
    local uiRight = UIParent and UIParent:GetRight()
    if right and uiRight and (uiRight - right) < (f:GetWidth() + 24) then
      f:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, 0)
    else
      f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
    end
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

function Reminder:ShowForEvent(event)
  local f = self:EnsureFrame()
  local guild = (Fundraiser.Adapters.Roster:GetGuildName()) or "Guild"
  f.text:SetText(Fundraiser:T("REMINDER_FMT", guild, event.name, event.target))
  self:AnchorToMailbox()
  f:Show()
end

function Reminder:Hide()
  if self.frame then
    self.frame:Hide()
  end
end
