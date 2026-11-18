-- Pure Lua tests for the admin window summary model.
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Domain/AdminSummary.lua")

local failed = 0

local function assert_eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s (%s ~= %s)\n", msg or "assert_eq", tostring(a), tostring(b)))
  end
end

local function assert_true(v, msg)
  if not v then
    failed = failed + 1
    io.stderr:write("FAIL: " .. (msg or "assert_true") .. "\n")
  end
end

local AdminSummary = Fundraiser.Domain.AdminSummary

-- Scenario: no event published yet
do
  -- Given no event
  -- When building the event status
  local s = AdminSummary.EventStatus(nil)
  -- Then it reports no active event
  assert_eq(s.hasEvent, false, "no event: hasEvent false")
  assert_eq(s.name, "", "no event: empty name")
  assert_eq(s.target, "", "no event: empty target")
  assert_eq(s.revision, 0, "no event: revision 0")
end

-- Scenario: active event is summarised
do
  -- Given a published event
  local ev = {
    name = "Raid Fund",
    target = "Bank Alt",
    intervalSeconds = 7200,
    revision = 3,
    publisher = "Officer One",
  }
  -- When building the event status
  local s = AdminSummary.EventStatus(ev)
  -- Then the fields are copied and interval is expressed in hours
  assert_eq(s.hasEvent, true, "event: hasEvent")
  assert_eq(s.name, "Raid Fund", "event: name")
  assert_eq(s.target, "Bank Alt", "event: target")
  assert_eq(s.intervalHours, 2, "event: interval hours")
  assert_eq(s.revision, 3, "event: revision")
  assert_eq(s.publisher, "Officer One", "event: publisher")
end

-- Scenario: fractional interval is kept
do
  -- Given an interval of 90 minutes
  local s = AdminSummary.EventStatus({ name = "X", target = "A B", intervalSeconds = 5400, revision = 1 })
  -- Then hours are fractional
  assert_eq(s.intervalHours, 1.5, "event: fractional hours")
end

-- Scenario: empty ledger
do
  -- Given no rows
  -- When summarising
  local s = AdminSummary.Ledger({}, 0)
  -- Then count and total are zero and there are no recent rows
  assert_eq(s.count, 0, "ledger empty: count")
  assert_eq(s.total, 0, "ledger empty: total")
  assert_eq(#s.recent, 0, "ledger empty: recent")
end

-- Scenario: nil rows are tolerated
do
  local s = AdminSummary.Ledger(nil, nil)
  assert_eq(s.count, 0, "ledger nil: count")
  assert_eq(s.total, 0, "ledger nil: total")
  assert_eq(#s.recent, 0, "ledger nil: recent")
end

-- Scenario: fewer rows than the recent limit
do
  -- Given two rows
  local rows = {
    { id = "a", kind = "mail", name = "Alpha One", copper = 100, at = 10 },
    { id = "b", kind = "ah", name = "Beta Two", copper = 250, at = 20 },
  }
  -- When summarising
  local s = AdminSummary.Ledger(rows, 350)
  -- Then all rows are recent, newest first
  assert_eq(s.count, 2, "ledger two: count")
  assert_eq(s.total, 350, "ledger two: total")
  assert_eq(#s.recent, 2, "ledger two: recent size")
  assert_eq(s.recent[1].id, "b", "ledger two: newest first")
  assert_eq(s.recent[2].id, "a", "ledger two: oldest last")
end

-- Scenario: more rows than the default recent limit
do
  -- Given five rows in arbitrary order
  local rows = {
    { id = "r3", copper = 3, at = 30 },
    { id = "r1", copper = 1, at = 10 },
    { id = "r5", copper = 5, at = 50 },
    { id = "r2", copper = 2, at = 20 },
    { id = "r4", copper = 4, at = 40 },
  }
  -- When summarising
  local s = AdminSummary.Ledger(rows, 15)
  -- Then only the three newest rows remain, newest first
  assert_eq(s.count, 5, "ledger five: count")
  assert_eq(#s.recent, 3, "ledger five: recent size")
  assert_eq(s.recent[1].id, "r5", "ledger five: first")
  assert_eq(s.recent[2].id, "r4", "ledger five: second")
  assert_eq(s.recent[3].id, "r3", "ledger five: third")
  -- And the input list is not reordered
  assert_eq(rows[1].id, "r3", "ledger five: input untouched")
end

-- Scenario: custom recent limit and equal timestamps
do
  -- Given rows with the same timestamp
  local rows = {
    { id = "x", copper = 1, at = 5 },
    { id = "y", copper = 1, at = 5 },
    { id = "z", copper = 1, at = 5 },
  }
  -- When limiting to 2
  local s = AdminSummary.Ledger(rows, 3, 2)
  -- Then the limit is honoured with a stable id order
  assert_eq(#s.recent, 2, "ledger limit: size")
  assert_eq(s.recent[1].id, "x", "ledger limit: stable first")
  assert_eq(s.recent[2].id, "y", "ledger limit: stable second")
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("admin summary tests passed")
