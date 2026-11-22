-- Domain: step through a list of stacks one action at a time (bulk Post all / Sell all).
-- The caller decides how many steps to run per call, so an action that needs a user
-- click per step (AH posting) runs one step per click. A failed step stops the queue.
-- Pure Lua: no WoW API.
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local ActionQueue = {}
Fundraiser.Domain.ActionQueue = ActionQueue
ActionQueue.__index = ActionQueue

-- step(item) returns ok, reasonKey.
function ActionQueue.New(items, step)
  local copy = {}
  for i, item in ipairs(items or {}) do
    copy[i] = item
  end
  return setmetatable({ items = copy, step = step, next = 1, stopped = false, cancelled = false }, ActionQueue)
end

function ActionQueue:Total()
  return #self.items
end

function ActionQueue:Done()
  return self.next - 1
end

function ActionQueue:Remaining()
  return #self.items - self:Done()
end

function ActionQueue:Stopped()
  return self.stopped
end

function ActionQueue:Finished()
  return not self.stopped and not self.cancelled and self:Remaining() == 0
end

-- Abandon the rest of the run (the caller left, e.g. the auction house closed).
function ActionQueue:Cancel()
  self.cancelled = true
end

function ActionQueue:Cancelled()
  return self.cancelled
end

-- Review the items not yet run: keep(item) returns false/nil to drop one (for example a stack that
-- left the bags since the queue was built), true to keep it, or another value to replace it (for
-- example a re-priced stack). Returns how many were dropped and how many were replaced. Posted
-- items stay counted. Does nothing once the run was cancelled or a step failed.
function ActionQueue:Prune(keep)
  if self.cancelled or self.stopped then
    return 0, 0
  end
  local kept = {}
  for i = 1, self.next - 1 do
    kept[#kept + 1] = self.items[i]
  end
  local dropped, changed = 0, 0
  for i = self.next, #self.items do
    local item = self.items[i]
    local verdict = keep(item)
    if verdict == true then
      kept[#kept + 1] = item
    elseif verdict then
      kept[#kept + 1] = verdict
      changed = changed + 1
    else
      dropped = dropped + 1
    end
  end
  self.items = kept
  return dropped, changed
end

-- Run one step. Returns ok, reasonKey, item.
function ActionQueue:Next()
  if self.cancelled then
    return false, "cancelled"
  end
  if self.stopped then
    return false, "stopped"
  end
  local item = self.items[self.next]
  if item == nil then
    return false, "empty"
  end
  local ok, reason = self.step(item)
  if not ok then
    self.stopped = true
    return false, reason, item
  end
  self.next = self.next + 1
  return true, nil, item
end

-- Run up to maxSteps steps; returns how many succeeded. Stops on the first failure.
function ActionQueue:Run(maxSteps)
  local ran = 0
  while ran < maxSteps and not self.stopped and not self.cancelled and self:Remaining() > 0 do
    local ok = self:Next()
    if not ok then
      break
    end
    ran = ran + 1
  end
  return ran
end
