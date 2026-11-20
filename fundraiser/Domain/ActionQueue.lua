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
  return setmetatable({ items = copy, step = step, next = 1, stopped = false }, ActionQueue)
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
  return not self.stopped and self:Remaining() == 0
end

-- Run one step. Returns ok, reasonKey, item.
function ActionQueue:Next()
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
  while ran < maxSteps and not self.stopped and self:Remaining() > 0 do
    local ok = self:Next()
    if not ok then
      break
    end
    ran = ran + 1
  end
  return ran
end
