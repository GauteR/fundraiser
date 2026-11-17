-- Log all auction-house income on the donation-target character (dedicated alt).
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local Auction = {}
Fundraiser.Adapters.Auction = Auction

local function now()
  return (GetServerTime and GetServerTime()) or (time and time()) or 0
end

-- English Forever client patterns (Unverified — extend when in-game samples exist).
local SOLD_PATTERNS = {
  "^Your auction of (.+) sold for (.+)%.$",
  "^You sold (.+) for (.+)%.$",
}

local function parseMoneyText(text)
  if not text then
    return 0
  end
  text = tostring(text)
  local g = tonumber(text:match("(%d+)%s*[Gg]old")) or 0
  local s = tonumber(text:match("(%d+)%s*[Ss]ilver")) or 0
  local c = tonumber(text:match("(%d+)%s*[Cc]opper")) or 0
  if g == 0 and s == 0 and c == 0 then
    -- Numeric copper only
    return tonumber(text:match("(%d+)")) or 0
  end
  return g * 10000 + s * 100 + c
end

function Auction:IsDonationTarget()
  local Store = Fundraiser.Adapters.Store
  local Roster = Fundraiser.Adapters.Roster
  local event = Store:GetEvent()
  return Fundraiser.Domain.Roles.IsDonationTarget(event, Roster:GetPlayerName())
end

function Auction:Initialize()
  if self.initialized then
    return
  end
  if not Fundraiser:IsEnabled() or not (Fundraiser.Config and Fundraiser.Config.LEDGER) then
    return
  end

  local frame = CreateFrame("Frame", "FundraiserAuctionFrame")
  frame:RegisterEvent("CHAT_MSG_SYSTEM")
  frame:SetScript("OnEvent", function(_, event, msg)
    if event == "CHAT_MSG_SYSTEM" then
      self:OnSystemMessage(msg)
    end
  end)
  self.frame = frame
  self.initialized = true
end

function Auction:OnSystemMessage(msg)
  if type(msg) ~= "string" or msg == "" then
    return
  end
  if not self:IsDonationTarget() then
    return
  end
  local item, moneyText
  for _, pat in ipairs(SOLD_PATTERNS) do
    item, moneyText = msg:match(pat)
    if item then
      break
    end
  end
  if not item then
    return
  end
  local copper = parseMoneyText(moneyText)
  if copper <= 0 then
    return
  end
  self:RecordSale(item, copper)
end

function Auction:RecordSale(item, copper)
  local Store = Fundraiser.Adapters.Store
  local event = Store:GetEvent()
  if not event then
    return
  end
  local Roster = Fundraiser.Adapters.Roster
  local UC = Fundraiser.Application.UseCases
  local t = now()
  local id = string.format("ah:%s:%d:%d", tostring(item), copper, t)
  UC.AppendLedgerEntry({
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
  }, {
    id = id,
    kind = "ah",
    name = "AH",
    detail = item,
    copper = copper,
    eventId = event.id,
    at = t,
  }, { name = Roster:GetPlayerName() })

  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(
      Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("CHAT_AH_LOGGED", item, Fundraiser.FormatCopper(copper))
    )
  end
end
