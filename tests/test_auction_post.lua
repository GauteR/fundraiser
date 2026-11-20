-- Pure Lua tests for AuctionPost on the modern (C_AuctionHouse) Forever API, with stubbed WoW globals.
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Config.lua")

local chat = {}
DEFAULT_CHAT_FRAME = {
  AddMessage = function(_, msg)
    chat[#chat + 1] = msg
  end,
}
function Fundraiser:T(key, ...)
  local n = select("#", ...)
  if n == 0 then
    return key
  end
  local parts = { key }
  for i = 1, n do
    parts[#parts + 1] = tostring((select(i, ...)))
  end
  return table.concat(parts, "|")
end
Fundraiser.FormatCopper = function(c)
  return tostring(c) .. "c"
end

dofile(repo .. "/fundraiser/Adapters/AuctionPost.lua")

local AP = Fundraiser.Adapters.AuctionPost
local failed = 0

local function assert_eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s (%s ~= %s)\n", msg or "assert_eq", tostring(a), tostring(b)))
  end
end

-- Stubbed modern AH world; each scenario resets it.
local world
local function reset()
  chat = {}
  world = { ahOpen = true, merchantOpen = true, throttleReady = true, valid = true, commodity = false, exists = true, posts = {}, used = {} }
  Enum = { ItemCommodityStatus = { Item = 1, Commodity = 2 } }
  ItemLocation = {
    CreateFromBagAndSlot = function(_, bag, slot)
      return { bag = bag, slot = slot }
    end,
  }
  C_Item = {
    DoesItemExist = function()
      return world.exists
    end,
  }
  C_AuctionHouse = {
    IsThrottledMessageSystemReady = function()
      return world.throttleReady
    end,
    IsSellItemValid = function()
      return world.valid
    end,
    GetItemCommodityStatus = function()
      return world.commodity and 2 or 1
    end,
    PostCommodity = function(loc, duration, qty, unit)
      world.posts[#world.posts + 1] = { kind = "commodity", loc = loc, duration = duration, qty = qty, unit = unit }
    end,
    PostItem = function(loc, duration, qty, bid, buyout)
      world.posts[#world.posts + 1] = { kind = "item", loc = loc, duration = duration, qty = qty, bid = bid, buyout = buyout }
    end,
  }
  C_Container = {
    GetContainerItemInfo = function()
      return { itemID = 100, stackCount = 5 }
    end,
    UseContainerItem = function(bag, slot)
      world.used[#world.used + 1] = bag .. ":" .. slot
    end,
  }
  AP.IsAuctionHouseOpen = function()
    return world.ahOpen
  end
  AP.IsMerchantOpen = function()
    return world.merchantOpen
  end
  Fundraiser.Config.AH_DURATION = 3
  Fundraiser.Config.AH_UNDERCUT_COPPER = 0
end

local function stack(extra)
  local row = { bag = 1, slot = 2, itemId = 100, count = 5, ahUnit = 200 }
  for k, v in pairs(extra or {}) do
    row[k] = v
  end
  return row
end

-- Scenario: the duration setting is the Forever duration index (1 = 2h, 2 = 8h, 3 = 24h)
do
  reset()
  assert_eq(AP.DurationIndex(), 3, "duration: configured index")
  Fundraiser.Config.AH_DURATION = 1
  assert_eq(AP.DurationIndex(), 1, "duration: shortest")
  Fundraiser.Config.AH_DURATION = 9
  assert_eq(AP.DurationIndex(), 3, "duration: out of range falls back to 24h")
  Fundraiser.Config.AH_DURATION = nil
  assert_eq(AP.DurationIndex(), 3, "duration: default is 24h")
end

-- Scenario: the post plan applies the undercut per unit and never goes below one copper
do
  reset()
  local plan = AP.PostPlan(200, 5, 0)
  assert_eq(plan.unit, 200, "plan: no undercut keeps the unit price")
  assert_eq(plan.buyout, 1000, "plan: stack buyout is unit * count")
  assert_eq(AP.PostPlan(200, 5, 20).unit, 180, "plan: undercut is per unit")
  assert_eq(AP.PostPlan(10, 5, 50).unit, 10, "plan: undercut larger than the price is ignored")
  assert_eq(AP.PostPlan(1, 1, 0).unit, 1, "plan: minimum one copper")
end

-- Scenario: a missing price is refused before anything is posted
do
  reset()
  local ok, key = AP:PostStack(stack(), nil)
  assert_eq(ok, false, "no price: refused")
  assert_eq(key, "CHAT_TARGET_NEED_PRICE", "no price: reason")
  assert_eq(#world.posts, 0, "no price: nothing posted")
  local ok0, key0 = AP:PostStack(stack(), 0)
  assert_eq(ok0, false, "zero price: refused")
  assert_eq(key0, "CHAT_TARGET_NEED_PRICE", "zero price: reason")
end

-- Scenario: posting needs an open auction house, an existing item and a ready AH
do
  reset()
  world.ahOpen = false
  local ok, key = AP:PostStack(stack(), 200)
  assert_eq(ok, false, "closed AH: refused")
  assert_eq(key, "CHAT_TARGET_OPEN_AH", "closed AH: reason")

  reset()
  world.exists = false
  ok, key = AP:PostStack(stack(), 200)
  assert_eq(key, "CHAT_TARGET_ITEM_NOT_IN_BAGS", "missing item: reason")

  reset()
  world.throttleReady = false
  ok, key = AP:PostStack(stack(), 200)
  assert_eq(key, "CHAT_TARGET_AH_BUSY", "throttled: reason")

  reset()
  world.valid = false
  ok, key = AP:PostStack(stack(), 200)
  assert_eq(key, "CHAT_TARGET_NOT_AUCTIONABLE", "invalid item: reason")
  assert_eq(#world.posts, 0, "refusals: nothing posted")
end

-- Scenario: a normal item is posted with PostItem for the whole stack
do
  reset()
  local ok, key, count, buyout = AP:PostStack(stack(), 200)
  assert_eq(ok, true, "item: posted")
  assert_eq(key, "CHAT_TARGET_POSTED", "item: success key")
  assert_eq(count, 5, "item: success count")
  assert_eq(buyout, 1000, "item: success buyout")
  assert_eq(#world.posts, 1, "item: one post call")
  local p = world.posts[1]
  assert_eq(p.kind, "item", "item: PostItem")
  assert_eq(p.qty, 5, "item: quantity is the stack size")
  assert_eq(p.buyout, 1000, "item: buyout covers the stack")
  assert_eq(p.bid, nil, "item: no separate bid")
  assert_eq(p.duration, 3, "item: 24h index")
  assert_eq(p.loc.bag, 1, "item: location bag")
  assert_eq(p.loc.slot, 2, "item: location slot")
end

-- Scenario: a commodity is posted with PostCommodity at the unit price
do
  reset()
  world.commodity = true
  Fundraiser.Config.AH_UNDERCUT_COPPER = 10
  local ok, key, count, buyout = AP:PostStack(stack(), 200)
  assert_eq(ok, true, "commodity: posted")
  assert_eq(world.posts[1].kind, "commodity", "commodity: PostCommodity")
  assert_eq(world.posts[1].unit, 190, "commodity: unit price after undercut")
  assert_eq(world.posts[1].qty, 5, "commodity: quantity")
  assert_eq(buyout, 950, "commodity: reported stack total")
  assert_eq(count, 5, "commodity: reported count")
end

-- Scenario: an error inside the AH call is reported as a failed post
do
  reset()
  C_AuctionHouse.PostItem = function()
    error("blocked")
  end
  local ok, key = AP:PostStack(stack(), 200)
  assert_eq(ok, false, "api error: refused")
  assert_eq(key, "CHAT_TARGET_POST_FAILED", "api error: reason")
end

-- Scenario: vendoring needs an open merchant and the item in the bag slot
do
  reset()
  world.merchantOpen = false
  local ok, key = AP:VendorStack(stack())
  assert_eq(ok, false, "vendor: closed merchant refused")
  assert_eq(key, "CHAT_TARGET_OPEN_VENDOR", "vendor: closed merchant reason")
  assert_eq(#world.used, 0, "vendor: nothing sold")

  reset()
  C_Container.GetContainerItemInfo = function()
    return nil
  end
  ok, key = AP:VendorStack(stack())
  assert_eq(key, "CHAT_TARGET_ITEM_NOT_IN_BAGS", "vendor: empty slot reason")

  reset()
  C_Container.GetContainerItemInfo = function()
    return { itemID = 999, stackCount = 5 }
  end
  ok, key = AP:VendorStack(stack())
  assert_eq(key, "CHAT_TARGET_ITEM_NOT_IN_BAGS", "vendor: other item in the slot reason")

  reset()
  ok, key = AP:VendorStack(stack())
  assert_eq(ok, true, "vendor: sold")
  assert_eq(key, "CHAT_TARGET_VENDOR_OK", "vendor: success key")
  assert_eq(world.used[1], "1:2", "vendor: the right slot is used")
end

-- Scenario: HandleRow routes the action and reports the result in chat
do
  reset()
  local ok, key = AP:HandleRow(stack(), "ah", nil)
  assert_eq(ok, true, "handle: AH uses the row price")
  assert_eq(world.posts[1].buyout, 1000, "handle: row unit price * count")
  assert_eq(chat[1] ~= nil and chat[1]:find("CHAT_TARGET_POSTED", 1, true) ~= nil, true, "handle: success is printed")

  reset()
  ok, key = AP:HandleRow(stack(), "ah", 300)
  assert_eq(world.posts[1].buyout, 1500, "handle: manual price wins")

  reset()
  ok, key = AP:HandleRow(stack({ ahUnit = false }), "ah", nil)
  assert_eq(ok, false, "handle: no price refused")
  assert_eq(key, "CHAT_TARGET_NEED_PRICE", "handle: no price reason")
  assert_eq(chat[1] ~= nil and chat[1]:find("CHAT_TARGET_NEED_PRICE", 1, true) ~= nil, true, "handle: failure is printed")

  reset()
  ok, key = AP:HandleRow(stack(), "vendor", nil)
  assert_eq(ok, true, "handle: vendor action")
  assert_eq(world.used[1], "1:2", "handle: vendor uses the slot")
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("auction post tests passed")
