-- Domain: fundraiser event snapshot (officer-authored).
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local Event = {}
Fundraiser.Domain.Event = Event

local function trim(s)
  if type(s) ~= "string" then
    return ""
  end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Build a validated event table or return nil, err.
function Event.Create(fields)
  fields = fields or {}
  local name = trim(fields.name)
  local target = trim(fields.target)
  local goal = trim(fields.goal or "")
  local interval = tonumber(fields.intervalSeconds)
  local minAdminRank = tonumber(fields.minAdminRank)
  local revision = tonumber(fields.revision) or 1
  local id = trim(fields.id or "")

  if name == "" then
    return nil, "empty_name"
  end
  if target == "" then
    return nil, "empty_target"
  end
  if not interval or interval < 60 then
    return nil, "bad_interval"
  end
  if not minAdminRank or minAdminRank < 0 then
    return nil, "bad_rank"
  end
  if id == "" then
    id = string.format("%s-%d", name:gsub("%s+", "_"):lower(), revision)
  end

  return {
    id = id,
    name = name,
    target = target,
    goal = goal,
    intervalSeconds = interval,
    minAdminRank = minAdminRank,
    revision = revision,
    publishedAt = tonumber(fields.publishedAt) or 0,
    publisher = trim(fields.publisher or ""),
  }
end

function Event.IsNewer(candidate, current)
  if not candidate then
    return false
  end
  if not current then
    return true
  end
  if candidate.revision ~= current.revision then
    return candidate.revision > current.revision
  end
  return (candidate.publishedAt or 0) > (current.publishedAt or 0)
end
