-- Pure Lua tests for the bag scan (rows for the target page), with stubbed WoW globals.
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Config.lua")
dofile(repo .. "/fundraiser/Domain/SaleAdvice.lua")
dofile(repo .. "/fundraiser/Adapters/BagAssist.lua")

local BA = Fundraiser.Adapters.BagAssist
local failed = 0

local function assert_eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s (%s ~= %s)\n", msg or "assert_eq", tostring(a), tostring(b)))
  end
end

-- Stubbed bags: slots[bag][slot] = item info; prices by item id.
local slots, ahPrices, vendorPrices, classes, durability, invalid
local function reset()
  slots, ahPrices, vendorPrices, classes, durability, invalid = {}, {}, {}, {}, {}, {}
  Enum = { ItemClass = { Questitem = 12 } }
  NUM_BAG_SLOTS = 1
  ItemLocation = {
    CreateFromBagAndSlot = function(_, bag, slot)
      return { bag = bag, slot = slot }
    end,
  }
  C_Container = {
    GetContainerNumSlots = function(bag)
      local n = 0
      for slot in pairs(slots[bag] or {}) do
        if slot > n then
          n = slot
        end
      end
      return n
    end,
    GetContainerItemInfo = function(bag, slot)
      return slots[bag] and slots[bag][slot] or nil
    end,
    GetContainerItemDurability = function(bag, slot)
      local d = durability[bag .. ":" .. slot]
      if d then
        return d[1], d[2]
      end
      return nil
    end,
  }
  C_AuctionHouse = {
    IsSellItemValid = function(loc)
      return not invalid[loc.bag .. ":" .. loc.slot]
    end,
  }
  C_Item = {
    GetItemInfoInstant = function(itemId)
      return itemId, "type", "sub", "", 0, classes[itemId] or 0
    end,
  }
  GetItemInfo = function(link)
    return "Name of " .. tostring(link)
  end
  Fundraiser.Adapters.Pricing = {
    GetUnitAhPrice = function(_, id)
      return ahPrices[id]
    end,
    GetVendorUnitPrice = function(_, id)
      return vendorPrices[id]
    end,
    PriceSource = function(_, id)
      return ahPrices[id] and "TSM" or "manual"
    end,
  }
  Fundraiser.Config.AH_CUT_FRACTION = 0.05
end

local function put(bag, slot, info)
  slots[bag] = slots[bag] or {}
  slots[bag][slot] = info
end

local function item(id, count, extra)
  local info = { itemID = id, stackCount = count, hyperlink = "item:" .. id, isLocked = false, isBound = false }
  for k, v in pairs(extra or {}) do
    info[k] = v
  end
  return info
end

-- Scenario: a priced stack becomes a row carrying its bag slot, prices and advice
do
  reset()
  ahPrices[100] = 1000
  vendorPrices[100] = 50
  put(0, 3, item(100, 5))
  local rows = BA:Scan()
  assert_eq(#rows, 1, "scan: one row")
  local r = rows[1]
  assert_eq(r.bag, 0, "scan: bag")
  assert_eq(r.slot, 3, "scan: slot")
  assert_eq(r.itemId, 100, "scan: item id")
  assert_eq(r.count, 5, "scan: stack size")
  assert_eq(r.ahUnit, 1000, "scan: AH unit price")
  assert_eq(r.vendorUnit, 50, "scan: vendor unit price")
  assert_eq(r.vendorTotal, 250, "scan: vendor stack total")
  assert_eq(r.ahNet, 4750, "scan: AH net after the cut")
  assert_eq(r.advice, "ah", "scan: advice")
  assert_eq(r.source, "TSM", "scan: price source")
  assert_eq(r.name, "Name of item:100", "scan: name from the item info")
end

-- Scenario: scans cover every bag and come back in bag/slot order
do
  reset()
  vendorPrices[1], vendorPrices[2] = 10, 10
  put(1, 1, item(2, 1))
  put(0, 2, item(1, 1))
  local rows = BA:Scan()
  assert_eq(#rows, 2, "order: both bags scanned")
  assert_eq(rows[1].bag, 0, "order: bag 0 first")
  assert_eq(rows[2].bag, 1, "order: bag 1 second")
end

-- Scenario: locked stacks are skipped
do
  reset()
  vendorPrices[1] = 10
  put(0, 1, item(1, 1, { isLocked = true }))
  assert_eq(#BA:Scan(), 0, "locked: skipped")
end

-- Scenario: soulbound or damaged items never get an AH price, so they fall back to the vendor
do
  reset()
  ahPrices[1] = 1000
  vendorPrices[1] = 20
  put(0, 1, item(1, 1, { isBound = true }))
  local r = BA:Scan()[1]
  assert_eq(r.auctionable, false, "bound: not auctionable")
  assert_eq(r.ahUnit, nil, "bound: no AH price")
  assert_eq(r.advice, "vendor", "bound: advice falls back to vendor")

  reset()
  ahPrices[1] = 1000
  vendorPrices[1] = 20
  put(0, 1, item(1, 1))
  durability["0:1"] = { 40, 100 }
  r = BA:Scan()[1]
  assert_eq(r.auctionable, false, "damaged: not auctionable")
  assert_eq(r.advice, "vendor", "damaged: advice falls back to vendor")

  reset()
  ahPrices[1] = 1000
  vendorPrices[1] = 20
  put(0, 1, item(1, 1))
  durability["0:1"] = { 100, 100 }
  assert_eq(BA:Scan()[1].auctionable, true, "full durability: auctionable")

  reset()
  ahPrices[1] = 1000
  vendorPrices[1] = 20
  put(0, 1, item(1, 1))
  invalid["0:1"] = true
  assert_eq(BA:Scan()[1].auctionable, false, "invalid for sale: not auctionable")
end

-- Scenario: quest items are never offered to the vendor
do
  reset()
  vendorPrices[5] = 100
  classes[5] = 12
  put(0, 1, item(5, 1, { isBound = true }))
  assert_eq(#BA:Scan(), 0, "quest: bound quest item is not listed")
end

-- Scenario: an auctionable stack without any price is listed as needing a price
do
  reset()
  put(0, 1, item(7, 3))
  local rows = BA:Scan()
  assert_eq(#rows, 1, "no price: auctionable stack is listed")
  assert_eq(rows[1].advice, "manual", "no price: advice asks for a manual price")
end

-- Scenario: a bound stack with no value at all is not listed
do
  reset()
  put(0, 1, item(8, 1, { isBound = true }))
  assert_eq(#BA:Scan(), 0, "worthless: not listed")
end

-- Scenario: empty slots and missing APIs give no rows
do
  reset()
  put(0, 1, nil)
  assert_eq(#BA:Scan(), 0, "empty: no rows")
  C_Container = nil
  assert_eq(#BA:Scan(), 0, "no API: no rows")
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("bag assist tests passed")
