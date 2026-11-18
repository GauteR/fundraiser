-- Application use cases (pure; ports injected).
Fundraiser = Fundraiser or {}
Fundraiser.Application = Fundraiser.Application or {}

local UC = {}
Fundraiser.Application.UseCases = UC

local Domain = function()
  return Fundraiser.Domain
end

function UC.PublishEvent(deps, fields, actor)
  local Event = Domain().Event
  local Rank = Domain().Rank
  local Roles = Domain().Roles
  actor = actor or {}
  -- Admin gate and stamped wire field both use global Config/Options rank.
  local minRank = (Roles and Roles.GetMinAdminRank and Roles.GetMinAdminRank()) or 0
  if not Rank.IsAdmin(actor.rankIndex, minRank) then
    return nil, "not_admin"
  end
  local current = deps.getEvent and deps.getEvent() or nil
  fields = fields or {}
  -- Publishing replaces the active fundraiser: archive old event+ledger, start a new id.
  if current then
    if deps.archiveEvent then
      deps.archiveEvent(current, deps.getContributions and deps.getContributions() or {}, actor.now or 0)
    end
    if deps.clearContributions then
      deps.clearContributions()
    end
    if deps.clearReminder then
      deps.clearReminder()
    end
  end
  fields.id = nil
  fields.minAdminRank = minRank
  fields.revision = 1
  fields.publishedAt = actor.now or fields.publishedAt or 0
  fields.publisher = actor.name or fields.publisher or ""
  local event, err = Event.Create(fields)
  if not event then
    return nil, err
  end
  if deps.setEvent then
    deps.setEvent(event)
  end
  if deps.broadcastEvent then
    deps.broadcastEvent(event)
  end
  return event
end

function UC.AcceptRemoteEvent(deps, event, senderRankIndex)
  local Event = Domain().Event
  local Rank = Domain().Rank
  local Roles = Domain().Roles
  if not event then
    return nil, "no_event"
  end
  local minRank = (Roles and Roles.GetMinAdminRank and Roles.GetMinAdminRank()) or 0
  if not Rank.IsAdmin(senderRankIndex, minRank) then
    return nil, "not_admin"
  end
  local current = deps.getEvent and deps.getEvent() or nil
  if current and event.id and current.id and event.id ~= current.id then
    if deps.archiveEvent then
      deps.archiveEvent(current, deps.getContributions and deps.getContributions() or {}, event.publishedAt or 0)
    end
    if deps.clearContributions then
      deps.clearContributions()
    end
    if deps.clearReminder then
      deps.clearReminder()
    end
  elseif not Event.IsNewer(event, current) then
    return nil, "stale"
  end
  if deps.setEvent then
    deps.setEvent(event)
  end
  return event
end

-- Officer-only remote wipe (guild addon message). Local apply via deps.applyReset(scope, epoch).
-- All clients that accept apply the wipe (not only officers).
function UC.AcceptRemoteReset(deps, scope, senderRankIndex, resetEpoch)
  local Rank = Domain().Rank
  local Roles = Domain().Roles
  local minRank = (Roles and Roles.GetMinAdminRank and Roles.GetMinAdminRank()) or 0
  if not Rank.IsAdmin(senderRankIndex, minRank) then
    return nil, "not_admin"
  end
  scope = tostring(scope or "all")
  if scope ~= "all" and scope ~= "event" and scope ~= "ledger" and scope ~= "presence" then
    return nil, "bad_scope"
  end
  if not deps.applyReset then
    return nil, "no_apply"
  end
  local ok, err = deps.applyReset(scope, resetEpoch)
  if ok == nil and err then
    return nil, err
  end
  return true
end

-- Target-only write of a new ledger row; then replicate to officers.
function UC.AppendLedgerEntry(deps, fields, actor)
  local Ledger = Domain().Ledger
  local Roles = Domain().Roles
  local event = deps.getEvent and deps.getEvent() or nil
  if not event then
    return nil, "no_event"
  end
  actor = actor or {}
  if not Roles.CanWriteLedger(event, actor.name) then
    return nil, "not_target"
  end
  fields = fields or {}
  fields.eventId = fields.eventId or event.id
  local entry, err = Ledger.CreateEntry(fields)
  if not entry then
    return nil, err
  end
  local list = (deps.getContributions and deps.getContributions()) or {}
  local updated, changed = Ledger.Upsert(list, entry)
  if deps.setContributions then
    deps.setContributions(updated)
  end
  if changed and deps.broadcastLedgerEntry then
    deps.broadcastLedgerEntry(entry)
  end
  return entry, changed
end

-- Mesh merge: every installed client stores the id-union replica.
-- UI still gates view via Roles.CanViewLedger. Addon messages are not signed;
-- a malicious peer can forge rows (documented in SYNC.md).
-- Rows stamped with resetEpoch < local epoch are dropped so a post-RESET HELLO
-- cannot refill wiped ledgers from peers that never saw the wipe.
function UC.MergeRemoteLedger(deps, remoteEntries, senderName, _senderRankIndex)
  local Ledger = Domain().Ledger
  local event = deps.getEvent and deps.getEvent() or nil
  if not event then
    return nil, "no_event"
  end
  if not senderName or tostring(senderName) == "" then
    return nil, "bad_sender"
  end
  local localEpoch = 0
  if deps.getResetEpoch then
    localEpoch = tonumber(deps.getResetEpoch()) or 0
  end
  local accepted = {}
  for _, entry in ipairs(remoteEntries or {}) do
    local entryEpoch = tonumber(entry and entry.resetEpoch) or 0
    -- Keep equal epoch (same wipe generation); reject older generations only.
    if entryEpoch >= localEpoch then
      accepted[#accepted + 1] = entry
    end
  end
  if #accepted == 0 then
    return (deps.getContributions and deps.getContributions()) or {}, false
  end
  local localList = (deps.getContributions and deps.getContributions()) or {}
  local merged = Ledger.Merge(localList, accepted)
  local _, localSum = Ledger.Fingerprint(localList)
  local _, mergedSum, _ = Ledger.Fingerprint(merged)
  local changed = #merged ~= #localList or mergedSum ~= localSum
  if changed and deps.setContributions then
    deps.setContributions(merged)
  end
  return merged, changed
end

function UC.ShouldShowReminder(deps, now)
  local Reminder = Domain().Reminder
  local Roles = Domain().Roles
  local event = deps.getEvent and deps.getEvent() or nil
  local state = deps.getReminderState and deps.getReminderState() or {}
  local me = deps.getPlayerName and deps.getPlayerName() or nil
  -- Donation target does not need mailbox reminders about mailing themselves.
  if event and Roles.IsDonationTarget(event, me) then
    return false, event
  end
  return Reminder.ShouldRemind(now, event, state), event
end

function UC.DismissReminder(deps, now, eventId)
  local Reminder = Domain().Reminder
  local state = deps.getReminderState and deps.getReminderState() or {}
  state = Reminder.MarkDismissed(state, now, eventId)
  if deps.setReminderState then
    deps.setReminderState(state)
  end
  return state
end

function UC.ListMissingInstalls(deps, now)
  local roster = (deps.getRoster and deps.getRoster()) or {}
  local presence = (deps.getPresence and deps.getPresence()) or {}
  local stale = tonumber(deps.presenceStale) or 600
  now = tonumber(now) or 0
  local missing = {}
  for _, member in ipairs(roster) do
    if member.online then
      local p = presence[member.guid] or presence[member.name]
      local lastHello = p and tonumber(p.lastHello) or 0
      if lastHello <= 0 or (now - lastHello) > stale then
        missing[#missing + 1] = {
          name = member.name,
          guid = member.guid,
          status = lastHello > 0 and "unknown" or "missing",
        }
      end
    end
  end
  return missing
end

function UC.GetLedger(deps, eventId)
  local Ledger = Domain().Ledger
  local Roles = Domain().Roles
  local event = deps.getEvent and deps.getEvent() or nil
  local me = deps.getPlayerName and deps.getPlayerName() or nil
  local myRank = deps.getPlayerRankIndex and deps.getPlayerRankIndex() or nil
  if event and not Roles.CanViewLedger(event, myRank, me) then
    return {}, 0
  end
  local list = (deps.getContributions and deps.getContributions()) or {}
  local filtered = Ledger.FilterByEvent(list, eventId)
  return filtered, Ledger.TotalCopper(filtered)
end
