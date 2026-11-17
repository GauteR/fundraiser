-- Domain: when to show the bag donation reminder.
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local Reminder = {}
Fundraiser.Domain.Reminder = Reminder

--[[
  Show reminder when:
  - there is an active event
  - enough time has passed since lastDismissedAt (donation) for this event window
  - enough time has passed since lastShownAt (avoid spam on every bag open)

  After a donation (lastDismissedAt), the next window opens at
  lastDismissedAt + intervalSeconds. Within a window, lastShownAt suppresses
  repeats until the next bag-open after... we show once per bag open only if
  lastShownAt is nil or older than a short suppress — plan says reminder stays
  until mail sent, and returns at next interval after donate.

  Interpretation:
  - Until donated for this cycle: show on every bag open (caller may throttle UI).
  - After donate: suppress until lastDismissedAt + interval.
]]
function Reminder.ShouldRemind(now, event, state)
  now = tonumber(now) or 0
  if not event or not event.intervalSeconds then
    return false
  end
  state = state or {}
  local interval = tonumber(event.intervalSeconds) or 0
  if interval <= 0 then
    return false
  end

  local dismissed = tonumber(state.lastDismissedAt) or 0
  local dismissedEventId = state.dismissedEventId
  if dismissed > 0 and dismissedEventId == event.id then
    if now < (dismissed + interval) then
      return false
    end
  end

  return true
end

function Reminder.MarkShown(state, now, eventId)
  state = state or {}
  state.lastShownAt = tonumber(now) or 0
  state.shownEventId = eventId
  return state
end

function Reminder.MarkDismissed(state, now, eventId)
  state = state or {}
  state.lastDismissedAt = tonumber(now) or 0
  state.dismissedEventId = eventId
  return state
end
