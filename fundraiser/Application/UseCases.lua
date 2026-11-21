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
  -- Numeric fundraising goal is required at publish (legacy wire may still carry 0).
  local goalCopper = math.floor(tonumber(fields.goalCopper) or 0)
  if goalCopper <= 0 then
    return nil, "bad_goal"
  end
  fields.goalCopper = goalCopper
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

local function isArchivedEventId(deps, eventId)
  if not eventId or not deps.getArchives then
    return false
  end
  local archives = deps.getArchives() or {}
  for i = 1, #archives do
    local archived = archives[i]
    if archived and archived.event and archived.event.id == eventId then
      return true
    end
  end
  return false
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
  -- Reject revival of a campaign that was ended/archived locally.
  if isArchivedEventId(deps, event.id) then
    return nil, "archived"
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

local function isResetScope(scope)
  return scope == "all"
    or scope == "event"
    or scope == "ledger"
    or scope == "presence"
    or scope == "campaign"
end

-- Officer ends the active campaign without publishing a replacement.
-- Always archives + ApplyResetScope(campaign) locally (bumps resetEpoch).
-- Returns true, "guild" when RESET was sent; true, "local_only" when only local wipe ran.
function UC.EndActiveEvent(deps, actor)
  local Rank = Domain().Rank
  local Roles = Domain().Roles
  actor = actor or {}
  local minRank = (Roles and Roles.GetMinAdminRank and Roles.GetMinAdminRank()) or 0
  if not Rank.IsAdmin(actor.rankIndex, minRank) then
    return nil, "not_admin"
  end
  local current = deps.getEvent and deps.getEvent() or nil
  if not current then
    return nil, "no_event"
  end

  local sent = false
  if deps.broadcastReset then
    sent = deps.broadcastReset("campaign") and true or false
  end

  -- Ensure local campaign wipe + epoch bump even if broadcast was skipped/failed mid-way.
  if deps.getEvent and deps.getEvent() then
    if deps.archiveEvent then
      deps.archiveEvent(current, deps.getContributions and deps.getContributions() or {}, actor.now or 0)
    end
    if deps.applyResetScope then
      deps.applyResetScope("campaign")
    else
      if deps.clearContributions then
        deps.clearContributions()
      end
      if deps.clearReminder then
        deps.clearReminder()
      end
      if deps.clearEvent then
        deps.clearEvent()
      end
      if deps.bumpResetEpoch then
        deps.bumpResetEpoch()
      end
    end
  end

  if sent then
    return true, "guild"
  end
  return true, "local_only"
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
  if not isResetScope(scope) then
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

-- Store a new ledger row for the active event and replicate it (no permission check here).
local function appendEntry(deps, event, fields)
  local Ledger = Domain().Ledger
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

-- Target-only write of a new ledger row (mail / AH); then replicate to the mesh.
function UC.AppendLedgerEntry(deps, fields, actor)
  local Roles = Domain().Roles
  local event = deps.getEvent and deps.getEvent() or nil
  if not event then
    return nil, "no_event"
  end
  actor = actor or {}
  if not Roles.CanWriteLedger(event, actor.name) then
    return nil, "not_target"
  end
  return appendEntry(deps, event, fields)
end

-- Target-only: a sale puts its proceeds on the oldest open row of that item (same row id, newer
-- timestamp, so the mesh replaces the old row). sale: { item, qty, proceeds (copper, net), at, ownRow }.
-- Proceeds no row can take get a row of their own when sale.ownRow is set (auction sales);
-- vendor sales of items nobody donated are not recorded. Returns the rows written (maybe none).
function UC.RecordSale(deps, sale, actor)
  local Roles = Domain().Roles
  local ItemLots = Domain().ItemLots
  local event = deps.getEvent and deps.getEvent() or nil
  if not event then
    return nil, "no_event"
  end
  actor = actor or {}
  if not Roles.CanWriteLedger(event, actor.name) then
    return nil, "not_target"
  end
  local lots = deps.getLots and deps.getLots() or {}
  local parts, restQty, restCopper = ItemLots.Allocate(lots, sale.item, sale.qty, sale.proceeds)
  if deps.setLots then
    deps.setLots(lots)
  end

  local written = {}
  local at = tonumber(sale.at) or 0
  for _, part in ipairs(parts) do
    local row
    for _, r in ipairs((deps.getContributions and deps.getContributions()) or {}) do
      if r.id == part.id then
        row = r
        break
      end
    end
    if row then
      local entry = appendEntry(deps, event, {
        id = row.id,
        kind = row.kind,
        name = row.name,
        detail = ItemLots.RowDetail(lots, row.id),
        copper = (tonumber(row.copper) or 0) + part.copper,
        at = math.max(at, (tonumber(row.at) or 0) + 1),
      })
      written[#written + 1] = entry
    else
      -- The row is gone (ledger cleared or replaced): keep the money.
      restCopper = restCopper + part.copper
      restQty = restQty + part.qty
    end
  end

  if restCopper > 0 and sale.ownRow then
    local name = ItemLots.ParseCount(sale.item)
    local entry = appendEntry(deps, event, {
      id = string.format("ah:%s:%d:%d", tostring(sale.item), restCopper, at),
      kind = "ah",
      name = "AH",
      detail = name,
      copper = restCopper,
      at = at,
    })
    written[#written + 1] = entry
  end
  return written
end

-- Ledger row id for an incoming mail. Without attachments it keeps the old format; item
-- attachments are appended so two mails from one donor stay separate rows.
function UC.MailId(sender, subject, money, items)
  local id = string.format(
    "mail:%s:%s:%d:%s",
    tostring(sender),
    tostring(subject or ""),
    tonumber(money) or 0,
    (items and #items > 0) and "1" or "0"
  )
  if items and #items > 0 then
    local parts = {}
    for _, item in ipairs(items) do
      parts[#parts + 1] = string.format("%s x%d", tostring(item.name), tonumber(item.count) or 1)
    end
    id = id .. ":" .. table.concat(parts, ",")
  end
  return id
end

-- Target-only: record one incoming player mail. Money goes on the row as before; item
-- attachments become lots on the same row, listed in its detail and worth nothing until sold.
-- mail: { id, sender, subject, money, items = { { name, count } }, fromAuctionHouse, at }.
-- Items the auction house sends back (expired or cancelled auctions) are not donations.
-- Returns the row, or nil, reason ("known" when this mail's items are already recorded).
function UC.RecordItemMail(deps, mail, actor)
  local Roles = Domain().Roles
  local ItemLots = Domain().ItemLots
  local event = deps.getEvent and deps.getEvent() or nil
  if not event then
    return nil, "no_event"
  end
  actor = actor or {}
  if not Roles.CanWriteLedger(event, actor.name) then
    return nil, "not_target"
  end
  local items = (not mail.fromAuctionHouse and mail.items) or {}
  local lots = deps.getLots and deps.getLots() or {}
  if #items > 0 then
    if ItemLots.HasRow(lots, mail.id) then
      return nil, "known"
    end
    for _, item in ipairs(items) do
      ItemLots.Add(lots, { id = mail.id, item = item.name, qty = item.count })
    end
    if deps.setLots then
      deps.setLots(lots)
    end
  end
  local detail = #items > 0 and ItemLots.RowDetail(lots, mail.id) or (mail.subject or "")
  return appendEntry(deps, event, {
    id = mail.id,
    kind = "mail",
    name = Roles.DisplayName(mail.sender) or mail.sender,
    detail = detail,
    copper = (tonumber(mail.money) or 0) + ItemLots.RowCopper(lots, mail.id),
    at = mail.at,
  })
end

local manualSeq = 0

-- Manual donation entered by hand; stored and meshed like mail/AH rows.
-- Allowed for the donation target and for officers (Roles.CanAddManualDonation).
-- fields: name (donor), copper (> 0), detail (optional). actor: name, rankIndex, now.
function UC.AddManualDonation(deps, fields, actor)
  local Roles = Domain().Roles
  fields = fields or {}
  actor = actor or {}
  local name = Roles.DisplayName(fields.name)
  if not name then
    return nil, "bad_name"
  end
  local copper = math.floor(tonumber(fields.copper) or 0)
  if copper <= 0 then
    return nil, "bad_copper"
  end
  local event = deps.getEvent and deps.getEvent() or nil
  if not event then
    return nil, "no_event"
  end
  if not Roles.CanAddManualDonation(event, actor.rankIndex, actor.name) then
    return nil, "not_allowed"
  end
  local at = tonumber(actor.now) or 0
  -- Sequence keeps two identical donations in the same second as separate rows.
  manualSeq = manualSeq + 1
  return appendEntry(deps, event, {
    id = string.format("manual:%s:%d:%d:%d", name, copper, at, manualSeq),
    kind = "manual",
    name = name,
    detail = fields.detail or "",
    copper = copper,
    at = at,
  })
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

local function canViewLedgerNow(deps, event)
  local Roles = Domain().Roles
  local me = deps.getPlayerName and deps.getPlayerName() or nil
  local myRank = deps.getPlayerRankIndex and deps.getPlayerRankIndex() or nil
  if event then
    return Roles.CanViewLedger(event, myRank, me)
  end
  -- No active event (e.g. after End event): officers may still read archived summaries.
  return Roles.CanManageFundraiser(myRank, nil)
end

-- Ledger window model (today's view gate). Returns nil, "no_access" when not allowed.
function UC.GetLedgerView(deps)
  local event = deps.getEvent and deps.getEvent() or nil
  if not canViewLedgerNow(deps, event) then
    return nil, "no_access"
  end
  local rows = (deps.getContributions and deps.getContributions()) or {}
  local archives = (deps.getArchives and deps.getArchives()) or {}
  return Domain().LedgerView.Build(event, rows, archives)
end

-- Text that "Set MOTD" would publish (also used for the confirm dialog).
function UC.PrepareMotd(deps)
  local event = deps.getEvent and deps.getEvent() or nil
  if not event then
    return nil, "no_event"
  end
  if not canViewLedgerNow(deps, event) then
    return nil, "no_access"
  end
  local LV = Domain().LedgerView
  local view = UC.GetLedgerView(deps)
  -- Donors of the excluded guild rank (rank 0, the guild master) stay in the total but are not
  -- the "top contributor". Unknown ranks (not in the guild roster) count.
  local excluded = Fundraiser.Config and Fundraiser.Config.LEADERBOARD_EXCLUDED_RANK
  local skip
  if excluded ~= nil and deps.getDonorRankIndex then
    skip = function(name)
      return deps.getDonorRankIndex(name) == excluded
    end
  end
  local top = LV.TopContributors(view.active.rows, { skip = skip })[1]
  return LV.MotdText(event, view.active.total, top)
end

function UC.SetMotd(deps)
  local text, err = UC.PrepareMotd(deps)
  if not text then
    return nil, err
  end
  if not (deps.canEditMotd and deps.canEditMotd()) then
    return nil, "cannot_edit_motd"
  end
  -- Adapter returns false when the client API is missing or refuses.
  if not deps.setMotd or deps.setMotd(text) == false then
    return nil, "set_failed"
  end
  return text
end
