-- Pure Lua tests for the bulk action queue.
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Domain/ActionQueue.lua")

local Queue = Fundraiser.Domain.ActionQueue
local failed = 0

local function assert_eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s (%s ~= %s)\n", msg or "assert_eq", tostring(a), tostring(b)))
  end
end

-- Scenario: steps run in order, one per Next call
do
  local seen = {}
  local q = Queue.New({ "a", "b", "c" }, function(item)
    seen[#seen + 1] = item
    return true
  end)
  assert_eq(q:Total(), 3, "order: total")
  assert_eq(q:Remaining(), 3, "order: everything is left at the start")
  local ok, reason, item = q:Next()
  assert_eq(ok, true, "order: first step succeeds")
  assert_eq(item, "a", "order: first item")
  assert_eq(reason, nil, "order: no reason on success")
  assert_eq(q:Done(), 1, "order: one done")
  assert_eq(q:Remaining(), 2, "order: two left")
  q:Next()
  q:Next()
  assert_eq(table.concat(seen, ","), "a,b,c", "order: items visited in order")
  assert_eq(q:Finished(), true, "order: finished after the last item")
end

-- Scenario: the queue stops at the first failure and keeps the rest
do
  local calls = 0
  local q = Queue.New({ "a", "b", "c" }, function(item)
    calls = calls + 1
    if item == "b" then
      return false, "CHAT_TARGET_POST_FAILED"
    end
    return true
  end)
  q:Next()
  local ok, reason, item = q:Next()
  assert_eq(ok, false, "failure: step fails")
  assert_eq(reason, "CHAT_TARGET_POST_FAILED", "failure: reason is passed on")
  assert_eq(item, "b", "failure: failing item is reported")
  assert_eq(q:Stopped(), true, "failure: queue is stopped")
  assert_eq(q:Done(), 1, "failure: only the first step counts as done")
  assert_eq(q:Remaining(), 2, "failure: failed and later items are still left")
  local again, areason = q:Next()
  assert_eq(again, false, "failure: a stopped queue does not run again")
  assert_eq(areason, "stopped", "failure: stopped reason")
  assert_eq(calls, 2, "failure: step is not called after the stop")
end

-- Scenario: an empty queue is finished and reports nothing to do
do
  local q = Queue.New({}, function()
    return true
  end)
  assert_eq(q:Finished(), true, "empty: finished at once")
  local ok, reason = q:Next()
  assert_eq(ok, false, "empty: nothing to run")
  assert_eq(reason, "empty", "empty: reason")
end

-- Scenario: Run steps up to a limit and stops on failure
do
  local q = Queue.New({ 1, 2, 3, 4 }, function(item)
    return item ~= 3, "bad"
  end)
  local ran = q:Run(10)
  assert_eq(ran, 2, "run: two steps succeeded before the failure")
  assert_eq(q:Stopped(), true, "run: stopped on the failure")
  local one = Queue.New({ 1, 2, 3 }, function()
    return true
  end)
  assert_eq(one:Run(1), 1, "run: limit of one step per call")
  assert_eq(one:Remaining(), 2, "run: the rest waits for the next call")
end

-- Scenario: the input list is not modified
do
  local items = { "a", "b" }
  local q = Queue.New(items, function()
    return true
  end)
  q:Run(5)
  assert_eq(#items, 2, "input: list is left alone")
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("action queue tests passed")
