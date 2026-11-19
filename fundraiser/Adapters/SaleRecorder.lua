-- Record sales made from the Target page in the ledger (donation-target character only).
-- Vendor sales put the vendor price on the donated item's row; the use case ignores sales of
-- items nobody donated. Auction sales are recorded from the sale message (Adapters/Auction.lua).
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local SaleRecorder = {}
Fundraiser.Adapters.SaleRecorder = SaleRecorder

local function now()
  return (GetServerTime and GetServerTime()) or (time and time()) or 0
end

-- row: a bag stack from BagAssist (name, count, vendorTotal).
function SaleRecorder:RecordVendor(row)
  if not (Fundraiser.Config and Fundraiser.Config.LEDGER) then
    return
  end
  local proceeds = tonumber(row and row.vendorTotal) or 0
  if proceeds <= 0 then
    return
  end
  local Store = Fundraiser.Adapters.Store
  local Roster = Fundraiser.Adapters.Roster
  local written = Fundraiser.Application.UseCases.RecordSale({
    getEvent = function()
      return Store:GetEvent()
    end,
    getContributions = function()
      return Store:GetContributions()
    end,
    setContributions = function(list)
      Store:SetContributions(list)
    end,
    getLots = function()
      return Store:GetLots()
    end,
    setLots = function(list)
      Store:SetLots(list)
    end,
    broadcastLedgerEntry = function(entry)
      Fundraiser.Adapters.ThinGuildSync:BroadcastLedgerEntry(entry)
    end,
  }, {
    item = row.name,
    qty = row.count,
    proceeds = proceeds,
    at = now(),
  }, { name = Roster:GetPlayerName() })

  if written and #written > 0 and DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(
      Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("CHAT_VENDOR_LOGGED", row.name, Fundraiser.FormatCopper(proceeds))
    )
  end
end
