-- Post one bag stack to the auction house, or vendor it, on the modern Forever AH API
-- (C_AuctionHouse + C_Container, as used by Auctionator on Forever). Every action returns
-- ok, reasonKey, ... so the UI can show the result inline; HandleRow also prints it to chat.
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local AuctionPost = {}
Fundraiser.Adapters.AuctionPost = AuctionPost

-- Forever duration index: 1 = 2h, 2 = 8h, 3 = 24h.
local DURATION_DEFAULT = 3

local function Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. msg)
  end
end

function AuctionPost.IsAuctionHouseOpen()
  return AuctionHouseFrame ~= nil and AuctionHouseFrame:IsShown()
end

function AuctionPost.IsMerchantOpen()
  return MerchantFrame ~= nil and MerchantFrame:IsShown()
end

function AuctionPost.DurationIndex()
  local d = tonumber(Fundraiser.Config and Fundraiser.Config.AH_DURATION)
  if d and d >= 1 and d <= 3 and d == math.floor(d) then
    return d
  end
  return DURATION_DEFAULT
end

-- unitPrice in copper per unit; the undercut is taken per unit and ignored when it would
-- reach zero. buyout is for the whole stack (what PostItem expects).
function AuctionPost.PostPlan(unitPrice, count, undercut)
  local unit = math.floor(tonumber(unitPrice) or 0)
  undercut = tonumber(undercut) or 0
  if undercut > 0 and unit > undercut then
    unit = unit - undercut
  end
  if unit < 1 then
    unit = 1
  end
  return { unit = unit, buyout = unit * (tonumber(count) or 1) }
end

local function locationOf(row)
  return ItemLocation:CreateFromBagAndSlot(row.bag, row.slot)
end

-- row: { bag, slot, count }. unitPrice: copper per unit.
-- Returns ok, reasonKey, count, buyout (count and buyout on success).
function AuctionPost:PostStack(row, unitPrice)
  unitPrice = tonumber(unitPrice)
  if not unitPrice or unitPrice <= 0 then
    return false, "CHAT_TARGET_NEED_PRICE"
  end
  if not self.IsAuctionHouseOpen() then
    return false, "CHAT_TARGET_OPEN_AH"
  end
  if not (row and row.bag and row.slot) then
    return false, "CHAT_TARGET_ITEM_NOT_IN_BAGS"
  end
  local location = locationOf(row)
  if not C_Item.DoesItemExist(location) then
    return false, "CHAT_TARGET_ITEM_NOT_IN_BAGS"
  end
  if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
    return false, "CHAT_TARGET_AH_BUSY"
  end
  if not C_AuctionHouse.IsSellItemValid(location, false) then
    return false, "CHAT_TARGET_NOT_AUCTIONABLE"
  end

  local count = tonumber(row.count) or 1
  local plan = self.PostPlan(unitPrice, count, Fundraiser.Config and Fundraiser.Config.AH_UNDERCUT_COPPER)
  local duration = self.DurationIndex()
  local commodity = C_AuctionHouse.GetItemCommodityStatus(location) == Enum.ItemCommodityStatus.Commodity
  local ok, result
  if commodity then
    ok, result = pcall(C_AuctionHouse.PostCommodity, location, duration, count, plan.unit)
  else
    ok, result = pcall(C_AuctionHouse.PostItem, location, duration, count, nil, plan.buyout)
  end
  -- Only an error counts as a failure: the call may return false even when the client created
  -- the auction. The error text is passed on so the status line can show it.
  if not ok then
    return false, "CHAT_TARGET_POST_FAILED", tostring(result)
  end
  return true, "CHAT_TARGET_POSTED", count, plan.buyout
end

function AuctionPost:VendorStack(row)
  if not self.IsMerchantOpen() then
    return false, "CHAT_TARGET_OPEN_VENDOR"
  end
  local info = row and row.bag and row.slot and C_Container.GetContainerItemInfo(row.bag, row.slot)
  if not info or (row.itemId and info.itemID ~= row.itemId) then
    return false, "CHAT_TARGET_ITEM_NOT_IN_BAGS"
  end
  C_Container.UseContainerItem(row.bag, row.slot)
  local recorder = Fundraiser.Adapters.SaleRecorder
  if recorder and recorder.RecordVendor then
    recorder:RecordVendor(row)
  end
  return true, "CHAT_TARGET_VENDOR_OK"
end

local function report(ok, key, a, b)
  if key then
    if key == "CHAT_TARGET_POSTED" then
      Print(Fundraiser:T(key, tostring(a), Fundraiser.FormatCopper(b)))
    elseif key == "CHAT_TARGET_POST_FAILED" and a then
      Print(Fundraiser:T("CHAT_TARGET_POST_FAILED_DETAIL", tostring(a)))
    else
      Print(Fundraiser:T(key))
    end
  end
  return ok, key, a, b
end

-- Act on one stack (action "ah" or "vendor") and print the result to chat.
function AuctionPost:HandleRow(row, action, manualUnit)
  if not row then
    return false
  end
  if action == "vendor" then
    return report(self:VendorStack(row))
  end
  local unit = tonumber(manualUnit) or tonumber(row.ahUnit)
  return report(self:PostStack(row, unit))
end
