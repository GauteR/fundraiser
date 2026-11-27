-- Pure Lua tests for the sale rate lookup (Pricing:GetSaleRate), with a stubbed TSM_API.
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Config.lua")
dofile(repo .. "/fundraiser/Adapters/Pricing.lua")

local Pricing = Fundraiser.Adapters.Pricing
local failed = 0

local function assert_eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s (%s ~= %s)\n", msg or "assert_eq", tostring(a), tostring(b)))
  end
end

local calls
local function stubTsm(valueFor)
  calls = {}
  TSM_API = {
    GetCustomPriceValue = function(source, itemString)
      calls[#calls + 1] = { source = source, itemString = itemString }
      return valueFor(source, itemString)
    end,
  }
end

-- Scenario: TSM gives a sale rate for the item
TSM_API = nil
stubTsm(function()
  return 0.25
end)
assert_eq(Pricing:GetSaleRate(1234), 0.25, "sale rate: value is returned")
assert_eq(calls[1].source, Fundraiser.Config.TSM_SALE_RATE_SOURCE, "sale rate: configured source is used")
assert_eq(calls[1].itemString, "i:1234", "sale rate: item string is built from the id")

-- Scenario: a changed source name in Config is honoured
Fundraiser.Config.TSM_SALE_RATE_SOURCE = "DBRegionSaleRate"
stubTsm(function()
  return 0.5
end)
Pricing:GetSaleRate(1)
assert_eq(calls[1].source, "DBRegionSaleRate", "sale rate: source comes from Config")

-- Scenario: zero is a real rate (never sells) and is kept
stubTsm(function()
  return 0
end)
assert_eq(Pricing:GetSaleRate(1), 0, "sale rate: zero is kept")

-- Scenario: out-of-range values are clamped
stubTsm(function()
  return 1.7
end)
assert_eq(Pricing:GetSaleRate(1), 1, "sale rate: above 1 is clamped to 1")
stubTsm(function()
  return -0.2
end)
assert_eq(Pricing:GetSaleRate(1), 0, "sale rate: below 0 is clamped to 0")

-- Scenario: nothing usable gives nil, so the caller falls back
stubTsm(function()
  return nil
end)
assert_eq(Pricing:GetSaleRate(1), nil, "sale rate: nil from TSM is nil")
stubTsm(function()
  return "x"
end)
assert_eq(Pricing:GetSaleRate(1), nil, "sale rate: non-number is nil")
stubTsm(function()
  error("boom")
end)
assert_eq(Pricing:GetSaleRate(1), nil, "sale rate: an API error is nil")
assert_eq(Pricing:GetSaleRate("nope"), nil, "sale rate: non-numeric item id is nil")
TSM_API = nil
assert_eq(Pricing:GetSaleRate(1), nil, "sale rate: no TSM is nil")
TSM_API = {}
assert_eq(Pricing:GetSaleRate(1), nil, "sale rate: TSM without the API is nil")

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("test_pricing: all passed")
