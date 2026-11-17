-- Soft-deps: TSM then Auctionator for min/unit AH price; else nil (manual).
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local Pricing = {}
Fundraiser.Adapters.Pricing = Pricing

function Pricing:GetTSMPrice(itemId)
  if type(itemId) ~= "number" then
    return nil
  end
  local api = TSM_API
  if type(api) ~= "table" or type(api.GetCustomPriceValue) ~= "function" then
    return nil
  end
  local itemString = "i:" .. tostring(itemId)
  if type(api.ToItemString) == "function" then
    local okLink, converted = pcall(api.ToItemString, "item:" .. tostring(itemId))
    if okLink and type(converted) == "string" and converted ~= "" then
      itemString = converted
    end
  end
  local source = (Fundraiser.Config and Fundraiser.Config.TSM_PRICE_SOURCE) or "DBMinBuyout"
  local ok, price = pcall(api.GetCustomPriceValue, source, itemString)
  if not ok or type(price) ~= "number" or price <= 0 then
    return nil
  end
  return math.floor(price + 0.5)
end

function Pricing:GetAuctionatorPrice(itemId)
  if type(itemId) ~= "number" then
    return nil
  end
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  local fn = api and api.GetAuctionPriceByItemID
  if type(fn) ~= "function" then
    return nil
  end
  local callerId = (Fundraiser.Config and Fundraiser.Config.ADDON_NAME) or "Fundraiser"
  local ok, price = pcall(fn, callerId, itemId)
  if not ok or type(price) ~= "number" or price <= 0 then
    return nil
  end
  return math.floor(price + 0.5)
end

-- Unit AH reference price (prefer TSM min source, then Auctionator).
function Pricing:GetUnitAhPrice(itemId)
  return self:GetTSMPrice(itemId) or self:GetAuctionatorPrice(itemId)
end

function Pricing:GetVendorUnitPrice(itemId)
  if type(itemId) ~= "number" or not GetItemInfo then
    return nil
  end
  local ok, sellPrice = pcall(function()
    local info = { GetItemInfo(itemId) }
    -- Classic/Forever: sell price is commonly the 11th return.
    return info[11]
  end)
  if ok and type(sellPrice) == "number" and sellPrice > 0 then
    return sellPrice
  end
  return nil
end

function Pricing:PriceSource(itemId)
  if self:GetTSMPrice(itemId) then
    return "TSM"
  end
  if self:GetAuctionatorPrice(itemId) then
    return "Auctionator"
  end
  return "manual"
end
