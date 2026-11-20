-- Scan the character's bags into stacks for the target page: prices (TSM -> Auctionator,
-- vendor sell price) and the sale advice per stack. The mailbox cannot be open at the
-- auctioneer, so bags are the only source.
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local BagAssist = {}
Fundraiser.Adapters.BagAssist = BagAssist

local function isQuestItem(itemId)
  if not (C_Item and C_Item.GetItemInfoInstant and Enum and Enum.ItemClass) then
    return false
  end
  local _, _, _, _, _, classId = C_Item.GetItemInfoInstant(itemId)
  return classId == Enum.ItemClass.Questitem
end

-- Same rules as Auctionator: not bound, full durability, valid for sale.
local function isAuctionable(info, bag, slot, location)
  if info.isBound then
    return false
  end
  if C_Container.GetContainerItemDurability then
    local current, max = C_Container.GetContainerItemDurability(bag, slot)
    if max and current ~= max then
      return false
    end
  end
  return C_AuctionHouse.IsSellItemValid(location, false) and true or false
end

local function itemName(info)
  local link = info.hyperlink
  if GetItemInfo and link then
    local name = GetItemInfo(link)
    if name then
      return name
    end
  end
  return link or tostring(info.itemID)
end

-- Returns an array of { bag, slot, itemId, link, name, count, auctionable, vendorUnit, ahUnit,
-- source, advice, vendorTotal, ahNet }, ordered by bag then slot.
function BagAssist:Scan()
  local rows = {}
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
    return rows
  end
  local Pricing = Fundraiser.Adapters.Pricing
  local SaleAdvice = Fundraiser.Domain.SaleAdvice
  local cut = (Fundraiser.Config and Fundraiser.Config.AH_CUT_FRACTION) or 0.05

  for bag = 0, tonumber(NUM_BAG_SLOTS) or 4 do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and not info.isLocked then
        local itemId = info.itemID
        local count = tonumber(info.stackCount) or 1
        local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
        local auctionable = isAuctionable(info, bag, slot, location)
        local vendorUnit = (not isQuestItem(itemId)) and Pricing:GetVendorUnitPrice(itemId) or nil
        local ahUnit = auctionable and Pricing:GetUnitAhPrice(itemId) or nil
        -- Worth listing when it can be sold somewhere, or posted at a manual price.
        if vendorUnit or ahUnit or auctionable then
          local advice, vendorTotal, ahNet = SaleAdvice.Recommend(vendorUnit, ahUnit, count, cut)
          rows[#rows + 1] = {
            bag = bag,
            slot = slot,
            itemId = itemId,
            link = info.hyperlink,
            name = itemName(info),
            count = count,
            auctionable = auctionable,
            vendorUnit = vendorUnit,
            ahUnit = ahUnit,
            source = ahUnit and Pricing:PriceSource(itemId) or "manual",
            advice = advice,
            vendorTotal = vendorTotal,
            ahNet = ahNet,
          }
        end
      end
    end
  end
  return rows
end
