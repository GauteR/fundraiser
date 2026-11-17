-- Take mail attachment and post one stack to AH, or vendor it (Unverified Forever AH API).
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local AuctionPost = {}
Fundraiser.Adapters.AuctionPost = AuctionPost

local function Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. msg)
  end
end

local function findBagItem(itemId, count)
  if not itemId or not GetContainerNumSlots then
    return nil
  end
  for bag = 0, 4 do
    local slots = GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
      local id = link and tonumber(link:match("item:(%d+)"))
      if id == itemId then
        local _, itemCount = GetContainerItemInfo(bag, slot)
        itemCount = tonumber(itemCount) or 1
        if itemCount >= (count or 1) then
          return bag, slot, itemCount
        end
      end
    end
  end
  return nil
end

function AuctionPost:TakeAttachment(mailIndex, attachIndex)
  if TakeInboxItem then
    TakeInboxItem(mailIndex, attachIndex)
    return true
  end
  return false
end

-- buyoutCopper is for the whole stack. minBid defaults to buyout.
function AuctionPost:PostStack(itemId, count, buyoutCopper)
  buyoutCopper = tonumber(buyoutCopper)
  if not buyoutCopper or buyoutCopper <= 0 then
    Print(Fundraiser:T("CHAT_TARGET_NEED_PRICE"))
    return false
  end
  local bag, slot = findBagItem(itemId, count)
  if not bag then
    Print(Fundraiser:T("CHAT_TARGET_ITEM_NOT_IN_BAGS"))
    return false
  end

  local duration = (Fundraiser.Config and Fundraiser.Config.AH_DURATION) or 2
  local minBid = buyoutCopper
  local undercut = tonumber(Fundraiser.Config and Fundraiser.Config.AH_UNDERCUT_COPPER) or 0
  if undercut > 0 and buyoutCopper > undercut then
    buyoutCopper = buyoutCopper - undercut
    minBid = buyoutCopper
  end

  -- Classic-style sell slot flow (Forever Unverified).
  if ClearCursor then
    ClearCursor()
  end
  if PickupContainerItem then
    PickupContainerItem(bag, slot)
  end
  if ClickAuctionSellItemButton then
    pcall(ClickAuctionSellItemButton)
  end
  if StartAuction then
    local ok = pcall(StartAuction, minBid, buyoutCopper, duration)
    if ok then
      Print(Fundraiser:T("CHAT_TARGET_POSTED", tostring(count), Fundraiser.FormatCopper(buyoutCopper)))
      return true
    end
  end
  Print(Fundraiser:T("CHAT_TARGET_POST_FAILED"))
  if ClearCursor then
    ClearCursor()
  end
  return false
end

function AuctionPost:VendorStack(itemId, count)
  local bag, slot = findBagItem(itemId, count)
  if not bag then
    Print(Fundraiser:T("CHAT_TARGET_ITEM_NOT_IN_BAGS"))
    return false
  end
  if not CanMerchantRepair and not MerchantFrame then
    -- Still try UseContainerItem if merchant is open.
  end
  if not (MerchantFrame and MerchantFrame:IsShown()) then
    Print(Fundraiser:T("CHAT_TARGET_OPEN_VENDOR"))
    return false
  end
  if UseContainerItem then
    UseContainerItem(bag, slot)
    Print(Fundraiser:T("CHAT_TARGET_VENDOR_OK"))
    return true
  end
  Print(Fundraiser:T("CHAT_TARGET_VENDOR_FAILED"))
  return false
end

-- High-level: take from mail if needed, then post or vendor.
function AuctionPost:HandleRow(row, action, manualBuyout)
  if not row then
    return false
  end
  self:TakeAttachment(row.mailIndex, row.attachIndex)
  -- Item arrives next frame often; try immediately then recommend /reload or retry.
  local itemId = row.itemId
  local count = row.count or 1
  if action == "vendor" then
    return self:VendorStack(itemId, count)
  end
  local unit = tonumber(manualBuyout) or row.ahUnit
  if not unit or unit <= 0 then
    Print(Fundraiser:T("CHAT_TARGET_NEED_PRICE"))
    return false
  end
  return self:PostStack(itemId, count, unit * count)
end
