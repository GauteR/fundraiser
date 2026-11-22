-- Domain: vendor vs AH recommendation for one item stack.
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local SaleAdvice = {}
Fundraiser.Domain.SaleAdvice = SaleAdvice

--[[
  Compare vendor take-home vs AH min buyout for the stack.
  ahCutFraction: estimated AH cut (default 0.05). Recommend vendor when
  vendorCopper >= ahNet (buyout after cut), else ah when ah price known,
  else manual when neither usable.
  deposit (optional, copper for the whole stack): the auction deposit, counted as lost, so it is
  subtracted from ahNet (never below 0). When it leaves nothing and the vendor pays, vendor wins.
]]
function SaleAdvice.Recommend(vendorCopper, ahMinBuyout, count, ahCutFraction, deposit)
  count = tonumber(count) or 1
  if count < 1 then
    count = 1
  end
  vendorCopper = tonumber(vendorCopper)
  ahMinBuyout = tonumber(ahMinBuyout)
  ahCutFraction = tonumber(ahCutFraction)
  if ahCutFraction == nil then
    ahCutFraction = 0.05
  end

  local vendorTotal = vendorCopper and (vendorCopper * count) or nil
  local ahTotal = ahMinBuyout and (ahMinBuyout * count) or nil
  local ahNet = ahTotal and math.floor(ahTotal * (1 - ahCutFraction) + 0.5) or nil
  deposit = tonumber(deposit) or 0
  if ahNet and deposit > 0 then
    ahNet = math.max(0, ahNet - deposit)
    if ahNet == 0 and vendorTotal and vendorTotal > 0 then
      return "vendor", vendorTotal, ahNet
    end
  end

  if vendorTotal and vendorTotal > 0 and ahNet and ahNet > 0 then
    if vendorTotal >= ahNet then
      return "vendor", vendorTotal, ahNet
    end
    return "ah", vendorTotal, ahNet
  end
  if ahTotal and ahTotal > 0 then
    return "ah", vendorTotal, ahNet or ahTotal
  end
  if vendorTotal and vendorTotal > 0 then
    return "vendor", vendorTotal, ahNet
  end
  return "manual", vendorTotal, ahNet
end
