-- Domain: view model for the target page. Groups bag stacks by the sale advice
-- (auction / vendor / needs price), decides which stacks may join a bulk action,
-- and moves the selection. Pure Lua: no WoW API.
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local TargetView = {}
Fundraiser.Domain.TargetView = TargetView

local GROUPS = { "auction", "vendor", "price" }
TargetView.GROUPS = GROUPS

function TargetView.Key(row)
  return tostring(row.bag) .. ":" .. tostring(row.slot)
end

local function groupOf(row)
  if row.advice == "ah" then
    return "auction"
  elseif row.advice == "vendor" then
    return "vendor"
  end
  return "price"
end

-- Value of the recommended action for the stack (nil when no price is usable).
function TargetView.Value(row)
  local group = groupOf(row)
  if group == "auction" then
    return row.ahNet
  elseif group == "vendor" then
    return row.vendorTotal
  end
  return nil
end

local function defaultMinValue()
  return tonumber(Fundraiser.Config and Fundraiser.Config.MIN_STACK_VALUE_COPPER) or 0
end

-- rows: array of { bag, slot, name, advice, vendorTotal, ahNet }.
-- opts.minValue: copper; stacks below it stay listed but leave bulk actions.
-- opts.skipped: set of TargetView.Key(row) the player excluded from bulk actions.
function TargetView.Build(rows, opts)
  opts = opts or {}
  local minValue = opts.minValue
  if minValue == nil then
    minValue = defaultMinValue()
  end
  local skipped = opts.skipped or {}
  local view = { groups = {} }
  for _, name in ipairs(GROUPS) do
    view.groups[name] = { entries = {}, total = 0, bulkCount = 0, bulkTotal = 0 }
  end

  for _, row in ipairs(rows or {}) do
    local group = groupOf(row)
    local value = TargetView.Value(row)
    local key = TargetView.Key(row)
    local belowMin = value ~= nil and value < minValue
    local isSkipped = skipped[key] == true
    local entry = {
      row = row,
      key = key,
      group = group,
      value = value,
      belowMin = belowMin,
      skipped = isSkipped,
      bulk = group ~= "price" and not belowMin and not isSkipped,
    }
    local g = view.groups[group]
    g.entries[#g.entries + 1] = entry
    g.total = g.total + (value or 0)
    if entry.bulk then
      g.bulkCount = g.bulkCount + 1
      g.bulkTotal = g.bulkTotal + (value or 0)
    end
  end

  for _, name in ipairs(GROUPS) do
    table.sort(view.groups[name].entries, function(a, b)
      local av, bv = a.value or -1, b.value or -1
      if av ~= bv then
        return av > bv
      end
      local an, bn = tostring(a.row.name or ""), tostring(b.row.name or "")
      if an ~= bn then
        return an < bn
      end
      return a.key < b.key
    end)
  end
  return view
end

-- Entries a bulk action may act on, in list order.
function TargetView.BulkEntries(view, group)
  local out = {}
  for _, entry in ipairs(view.groups[group].entries) do
    if entry.bulk then
      out[#out + 1] = entry
    end
  end
  return out
end

-- Every stack in selection order: auction, vendor, then needs price.
function TargetView.Flatten(view)
  local out = {}
  for _, name in ipairs(GROUPS) do
    for _, entry in ipairs(view.groups[name].entries) do
      out[#out + 1] = entry
    end
  end
  return out
end

-- Keep a selection index inside 1..count (0 when there is nothing to select).
function TargetView.Clamp(index, count)
  if count < 1 then
    return 0
  end
  if index < 1 then
    return 1
  end
  if index > count then
    return count
  end
  return index
end

-- Move the selection by delta and wrap around the ends.
function TargetView.Move(index, delta, count)
  if count < 1 then
    return 0
  end
  return ((index - 1 + delta) % count) + 1
end
