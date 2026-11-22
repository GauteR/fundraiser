-- Domain: state of the bulk buttons (Post all / Sell all) on the target page.
-- Pure Lua: the caller passes in which windows are open.
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local BulkPlan = {}
Fundraiser.Domain.BulkPlan = BulkPlan

-- group: "auction" or "vendor". env: { ahOpen, merchantOpen }.
-- Returns { count, total, canRun, blockKey } for the stacks a bulk action would touch.
function BulkPlan.Describe(view, group, env)
  env = env or {}
  local g = view.groups[group]
  local result = { count = g.bulkCount, total = g.bulkTotal, canRun = false, blockKey = nil }
  if g.bulkCount == 0 then
    result.blockKey = "TARGET_BULK_NONE"
  elseif group == "auction" and not env.ahOpen then
    result.blockKey = "TARGET_BULK_NEED_AH"
  elseif group == "vendor" and not env.merchantOpen then
    result.blockKey = "TARGET_BULK_NEED_VENDOR"
  else
    result.canRun = true
  end
  return result
end

-- "idle" (no run), "running" (work left), "stopped" (a step failed), "cancelled" or "done".
function BulkPlan.Progress(queue)
  if not queue then
    return "idle"
  end
  if queue:Cancelled() then
    return "cancelled"
  end
  if queue:Stopped() then
    return "stopped"
  end
  if queue:Finished() then
    return "done"
  end
  return "running"
end
