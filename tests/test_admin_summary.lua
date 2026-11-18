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
  local s = AdminSummary.EventStatus(nil)
  assert_eq(s.hasEvent, false, "no event: hasEvent false")
  assert_eq(s.goalCopper, 0, "no event: goalCopper 0")
  assert_eq(s.goalNote, "", "no event: empty note")
end

-- Scenario: active event includes goal fields
do
  local ev = {
    name = "Raid Fund",
    target = "Bank Alt",
    intervalSeconds = 7200,
    revision = 3,
    publisher = "Officer One",
    goalCopper = 500000,
    goal = "Tabards",
  }
  local s = AdminSummary.EventStatus(ev)
  assert_eq(s.hasEvent, true, "event: hasEvent")
  assert_eq(s.name, "Raid Fund", "event: name")
  assert_eq(s.intervalHours, 2, "event: interval hours")
  assert_eq(s.goalCopper, 500000, "event: goalCopper")
  assert_eq(s.goalNote, "Tabards", "event: goalNote")
end

-- Scenario: empty ledger status
do
  local s = AdminSummary.Ledger({}, 0)
  assert_eq(s.count, 0, "ledger empty: count")
  assert_eq(s.total, 0, "ledger empty: total")
  assert_eq(s.recent, nil, "ledger empty: no recent list")
end

-- Scenario: Progress percent and cap
do
  local p = AdminSummary.Progress(25000, 100000)
  assert_eq(p.total, 25000, "progress: total")
  assert_eq(p.goal, 100000, "progress: goal")
  assert_eq(p.percent, 25, "progress: 25%")
  assert_eq(p.cappedPercent, 25, "progress: capped 25")
  assert_true(p.hasGoal, "progress: hasGoal")

  p = AdminSummary.Progress(150000, 100000)
  assert_eq(p.percent, 150, "progress: over 100%")
  assert_eq(p.cappedPercent, 100, "progress: capped at 100")

  p = AdminSummary.Progress(50, 0)
  assert_eq(p.percent, 0, "progress: no goal percent 0")
  assert_true(not p.hasGoal, "progress: no goal")
end

-- Scenario: DailySeries buckets and cumulative
do
  local day = 86400
  local rows = {
    { copper = 100, at = day * 2 + 10 },
    { copper = 50, at = day * 1 + 5 },
    { copper = 25, at = day * 1 + 100 },
    { copper = 200, at = day * 3 + 1 },
  }
  local s = AdminSummary.DailySeries(rows, 500, day)
  assert_eq(#s.points, 3, "series: three days")
  assert_eq(s.points[1].day, day, "series: day1")
  assert_eq(s.points[1].copper, 75, "series: day1 copper")
  assert_eq(s.points[1].cumulative, 75, "series: day1 cum")
  assert_eq(s.points[2].copper, 100, "series: day2 copper")
  assert_eq(s.points[2].cumulative, 175, "series: day2 cum")
  assert_eq(s.points[3].cumulative, 375, "series: day3 cum")
  assert_eq(s.goalCopper, 500, "series: goal")
  assert_eq(s.maxY, 500, "series: maxY uses goal when higher")
end

-- Scenario: DailySeries maxY follows cumulative when above goal
do
  local s = AdminSummary.DailySeries({ { copper = 900, at = 10 } }, 100, 86400)
  assert_eq(s.maxY, 900, "series: maxY from cumulative")
  assert_eq(#AdminSummary.DailySeries({}, 0).points, 0, "series: empty")
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("admin summary tests passed")
