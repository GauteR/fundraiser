-- Pure Lua tests: the open Ledger page refreshes when ledger rows change.
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Config.lua")
dofile(repo .. "/fundraiser/Adapters/Store.lua")
dofile(repo .. "/fundraiser/UI/Ledger.lua")

local failed = 0

local function assert_eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s (%s ~= %s)\n", msg or "assert_eq", tostring(a), tostring(b)))
  end
end

local Store = Fundraiser.Adapters.Store
local Ledger = Fundraiser.UI.Ledger

-- Store: change listener ------------------------------------------------------
do
  Store.db = { contributions = {} }
  local calls = 0
  Store:OnContributionsChanged(function()
    calls = calls + 1
  end)
  Store:SetContributions({ { id = "a" } })
  assert_eq(calls, 1, "store: listener runs after SetContributions")
  Store:SetContributions({ { id = "a" }, { id = "b" } })
  assert_eq(calls, 2, "store: listener runs on every change")
end

-- Ledger: RefreshIfVisible --------------------------------------------------------
local function setup(visible)
  local timers = {}
  C_Timer = {
    After = function(_, fn)
      timers[#timers + 1] = fn
    end,
  }
  local refreshes = 0
  Ledger.frame = {
    IsVisible = function()
      return visible.value
    end,
  }
  Ledger.pendingRefresh = nil
  Ledger.Refresh = function()
    refreshes = refreshes + 1
  end
  local function flush()
    local pending = timers
    timers = {}
    for _, fn in ipairs(pending) do
      fn()
    end
  end
  return function()
    return refreshes
  end, flush
end

do
  local visible = { value = true }
  local count, flush = setup(visible)
  Ledger:RefreshIfVisible()
  Ledger:RefreshIfVisible()
  Ledger:RefreshIfVisible()
  flush()
  assert_eq(count(), 1, "ledger: a burst of changes collapses into one refresh")
  Ledger:RefreshIfVisible()
  flush()
  assert_eq(count(), 2, "ledger: a later change refreshes again")
end

do
  local visible = { value = false }
  local count, flush = setup(visible)
  Ledger:RefreshIfVisible()
  flush()
  assert_eq(count(), 0, "ledger: hidden page is not refreshed")
  Ledger.frame = nil
  Ledger:RefreshIfVisible()
  flush()
  assert_eq(count(), 0, "ledger: no frame yet means no refresh")
end

do
  local visible = { value = true }
  local count, flush = setup(visible)
  Fundraiser.Config.LEDGER_AUTO_REFRESH = false
  Ledger:RefreshIfVisible()
  flush()
  assert_eq(count(), 0, "ledger: flag off disables auto refresh")
  Fundraiser.Config.LEDGER_AUTO_REFRESH = true
end

do
  local visible = { value = true }
  local count, flush = setup(visible)
  Ledger:RefreshIfVisible()
  visible.value = false
  flush()
  assert_eq(count(), 0, "ledger: page closed before the timer fires is skipped")
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("ledger refresh tests passed")
