-- Pure Lua tests for the bulk action button state (Post all / Sell all).
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Config.lua")
dofile(repo .. "/fundraiser/Domain/ActionQueue.lua")
dofile(repo .. "/fundraiser/Domain/TargetView.lua")
dofile(repo .. "/fundraiser/Domain/BulkPlan.lua")

local TV = Fundraiser.Domain.TargetView
local BP = Fundraiser.Domain.BulkPlan
local Queue = Fundraiser.Domain.ActionQueue
local failed = 0

local function assert_eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s (%s ~= %s)\n", msg or "assert_eq", tostring(a), tostring(b)))
  end
end

local function row(bag, slot, advice, vendorTotal, ahNet)
  return { bag = bag, slot = slot, name = "Item " .. bag .. slot, advice = advice, vendorTotal = vendorTotal, ahNet = ahNet }
end

local function view()
  return TV.Build({
    row(0, 1, "ah", 100, 5000),
    row(0, 2, "ah", 100, 3000),
    row(0, 3, "ah", 10, 50), -- below the minimum
    row(0, 4, "vendor", 400, 300),
    row(0, 5, "manual", nil, nil),
  }, { minValue = 100, skipped = { ["0:2"] = true } })
end

-- Scenario: Post all counts only stacks that are in bulk and needs an open auction house
do
  local v = view()
  local d = BP.Describe(v, "auction", { ahOpen = true, merchantOpen = false })
  assert_eq(d.count, 1, "auction: skipped and below-minimum stacks are left out")
  assert_eq(d.total, 5000, "auction: total is the net of the counted stacks")
  assert_eq(d.canRun, true, "auction: runs with the auction house open")
  d = BP.Describe(v, "auction", { ahOpen = false, merchantOpen = true })
  assert_eq(d.canRun, false, "auction: blocked without the auction house")
  assert_eq(d.blockKey, "TARGET_BULK_NEED_AH", "auction: says why")
end

-- Scenario: Sell all needs an open vendor
do
  local v = view()
  local d = BP.Describe(v, "vendor", { ahOpen = true, merchantOpen = false })
  assert_eq(d.count, 1, "vendor: one stack")
  assert_eq(d.canRun, false, "vendor: blocked without a merchant")
  assert_eq(d.blockKey, "TARGET_BULK_NEED_VENDOR", "vendor: says why")
  d = BP.Describe(v, "vendor", { merchantOpen = true })
  assert_eq(d.canRun, true, "vendor: runs with a merchant")
end

-- Scenario: nothing to do disables the button
do
  local v = TV.Build({}, { minValue = 100 })
  local d = BP.Describe(v, "auction", { ahOpen = true })
  assert_eq(d.count, 0, "empty: no stacks")
  assert_eq(d.canRun, false, "empty: cannot run")
  assert_eq(d.blockKey, "TARGET_BULK_NONE", "empty: says why")
end

-- Scenario: progress of a queue that posts one stack per click
do
  assert_eq(BP.Progress(nil), "idle", "progress: no queue")
  local q = Queue.New({ "a", "b" }, function()
    return true
  end)
  assert_eq(BP.Progress(q), "running", "progress: queue with work left")
  q:Next()
  assert_eq(BP.Progress(q), "running", "progress: still one left")
  q:Next()
  assert_eq(BP.Progress(q), "done", "progress: finished")
  local failing = Queue.New({ "a" }, function()
    return false, "CHAT_TARGET_POST_FAILED"
  end)
  failing:Next()
  assert_eq(BP.Progress(failing), "stopped", "progress: stopped after a failure")
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("bulk plan tests passed")
