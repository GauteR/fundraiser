-- Domain: pure view-model helpers for the admin window (no frames, no client API).
-- The window renders these tables; tests exercise them outside the game client.
-- Ledger row details belong in the dedicated ledger window (#15), not here.
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local AdminSummary = {}
Fundraiser.Domain.AdminSummary = AdminSummary

local DEFAULT_DAY_SECONDS = 86400

-- Status line data for the active event (nil event = nothing published yet).
function AdminSummary.EventStatus(event)
  if type(event) ~= "table" then
    return {
      hasEvent = false,
      name = "",
      target = "",
      intervalHours = 0,
      revision = 0,
      publisher = "",
      goalCopper = 0,
      goalNote = "",
    }
  end
  return {
    hasEvent = true,
    name = event.name or "",
    target = event.target or "",
    intervalHours = (tonumber(event.intervalSeconds) or 0) / 3600,
    revision = tonumber(event.revision) or 0,
    publisher = event.publisher or "",
    goalCopper = math.floor(tonumber(event.goalCopper) or 0),
    goalNote = event.goal or "",
  }
end

-- Ledger status for the admin window: count + total only (no row preview).
function AdminSummary.Ledger(rows, total)
  rows = type(rows) == "table" and rows or {}
  return {
    count = #rows,
    total = tonumber(total) or 0,
  }
end

-- Progress toward the numeric fundraising goal.
function AdminSummary.Progress(total, goalCopper)
  total = tonumber(total) or 0
  if total < 0 then
    total = 0
  end
  goalCopper = math.floor(tonumber(goalCopper) or 0)
  local percent = 0
  if goalCopper > 0 then
    percent = (total / goalCopper) * 100
  end
  local capped = percent
  if capped > 100 then
    capped = 100
  elseif capped < 0 then
    capped = 0
  end
  return {
    total = total,
    goal = goalCopper,
    percent = percent,
    cappedPercent = capped,
    hasGoal = goalCopper > 0,
  }
end

-- Cumulative daily series for the chart card (oldest day first).
-- daySeconds defaults to 86400. maxY is max(last cumulative, goalCopper, 1).
function AdminSummary.DailySeries(rows, goalCopper, daySeconds)
  rows = type(rows) == "table" and rows or {}
  goalCopper = math.floor(tonumber(goalCopper) or 0)
  daySeconds = tonumber(daySeconds) or DEFAULT_DAY_SECONDS
  if daySeconds < 1 then
    daySeconds = DEFAULT_DAY_SECONDS
  end

  local buckets = {}
  local dayList = {}
  for _, row in ipairs(rows) do
    local at = tonumber(row.at) or 0
    local copper = tonumber(row.copper) or 0
    local day = math.floor(at / daySeconds) * daySeconds
    if buckets[day] == nil then
      buckets[day] = 0
      dayList[#dayList + 1] = day
    end
    buckets[day] = buckets[day] + copper
  end
  table.sort(dayList)

  local points = {}
  local cumulative = 0
  for i, day in ipairs(dayList) do
    cumulative = cumulative + buckets[day]
    points[i] = {
      day = day,
      copper = buckets[day],
      cumulative = cumulative,
    }
  end

  local maxY = cumulative
  if goalCopper > maxY then
    maxY = goalCopper
  end
  if maxY < 1 then
    maxY = 1
  end

  return {
    points = points,
    goalCopper = goalCopper,
    maxY = maxY,
  }
end
