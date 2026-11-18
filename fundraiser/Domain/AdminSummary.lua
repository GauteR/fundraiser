-- Domain: pure view-model helpers for the admin window (no frames, no client API).
-- The window renders these tables; tests exercise them outside the game client.
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local AdminSummary = {}
Fundraiser.Domain.AdminSummary = AdminSummary

local DEFAULT_RECENT_LIMIT = 3

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
    }
  end
  return {
    hasEvent = true,
    name = event.name or "",
    target = event.target or "",
    intervalHours = (tonumber(event.intervalSeconds) or 0) / 3600,
    revision = tonumber(event.revision) or 0,
    publisher = event.publisher or "",
  }
end

-- Ledger card data: row count, total copper and the newest rows (newest first).
-- rows is not modified. limit defaults to 3.
function AdminSummary.Ledger(rows, total, limit)
  rows = type(rows) == "table" and rows or {}
  limit = tonumber(limit) or DEFAULT_RECENT_LIMIT

  local sorted = {}
  for i, row in ipairs(rows) do
    sorted[i] = row
  end
  table.sort(sorted, function(a, b)
    local aa, ba = tonumber(a.at) or 0, tonumber(b.at) or 0
    if aa ~= ba then
      return aa > ba
    end
    return tostring(a.id) < tostring(b.id)
  end)

  local recent = {}
  for i = 1, math.min(limit, #sorted) do
    recent[i] = sorted[i]
  end

  return {
    count = #rows,
    total = tonumber(total) or 0,
    recent = recent,
  }
end
