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

-- Why a row is left out of bulk actions: "skipped", "below_min", "needs_price", or nil.
function TargetView.RowNote(entry)
  if entry.skipped then
    return "skipped"
  end
  if entry.belowMin then
    return "below_min"
  end
  if entry.group == "price" then
    return "needs_price"
  end
  return nil
end

-- What the row tooltip is built from: "bag" (the slot, only while it still holds the scanned
-- item, since bags may have changed since the scan), else "link", else "name".
-- slotItemId: the item id currently in row.bag / row.slot (nil when empty or unknown).
function TargetView.TooltipSource(row, slotItemId)
  if row.bag and row.slot and slotItemId ~= nil and slotItemId == row.itemId then
    return "bag"
  end
  if row.link then
    return "link"
  end
  return "name"
end

-- Which per-stack actions the selected stack allows: { post, vendor }. Posting needs the auction
-- house open and an auctionable stack; selling needs a vendor open and a vendor price.
-- env: { ahOpen, merchantOpen } (nil counts as closed). belowMin: the stack is worth less than the
-- minimum value, so neither action is offered.
function TargetView.ActionState(row, env, belowMin)
  env = env or {}
  if belowMin then
    return { post = false, vendor = false }
  end
  return {
    post = row.auctionable == true and env.ahOpen == true,
    vendor = row.vendorUnit ~= nil and env.merchantOpen == true,
  }
end

-- Whether Skip applies to the entry: not for needs-price stacks (never in bulk) nor for stacks
-- below the minimum value (already left out).
function TargetView.CanSkip(entry)
  return entry.group ~= "price" and not entry.belowMin
end

local OK_KEYS = {
  CHAT_TARGET_POSTED = true,
  CHAT_TARGET_VENDOR_OK = true,
  TARGET_BULK_DONE_FMT = true,
}

local INFO_KEYS = {
  TARGET_BULK_PROGRESS_FMT = true,
}

-- Colour class of a status line: "ok", "info" or "error".
function TargetView.StatusKind(key)
  if key == nil or INFO_KEYS[key] then
    return "info"
  end
  if OK_KEYS[key] then
    return "ok"
  end
  return "error"
end

-- Which auction window the dock goes beside: the visible one furthest to the right, so the dock
-- never covers another auction window (Blizzard's, or an addon's side panel). candidates:
-- { { name, right (screen x of the right edge, may be nil), shown } } in order of preference;
-- a tie keeps the first. Returns the name, or nil when none is shown.
function TargetView.PickAnchor(candidates)
  local best, bestRight
  for _, c in ipairs(candidates or {}) do
    if c.shown then
      local right = tonumber(c.right) or -math.huge
      if best == nil or right > bestRight then
        best, bestRight = c.name, right
      end
    end
  end
  return best
end

-- Selection after a stack is skipped: the next stack, or the same one at the end of the list.
function TargetView.AfterSkip(index, count)
  if count < 1 then
    return 0
  end
  if index < count then
    return index + 1
  end
  return count
end
