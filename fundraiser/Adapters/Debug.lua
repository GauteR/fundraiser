-- Solo in-game debug helpers (Config.DEBUG). Simulates peer guild messages locally.
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local Debug = {}
Fundraiser.Adapters.Debug = Debug

local function Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. msg)
  end
end

local function now()
  return (GetServerTime and GetServerTime()) or (time and time()) or 0
end

local function prefix()
  return (Fundraiser.Config and Fundraiser.Config.COMM_PREFIX) or "Fundraiser"
end

function Debug:IsEnabled()
  return Fundraiser:IsEnabled() and Fundraiser.Config and Fundraiser.Config.DEBUG == true
end

function Debug:Inject(payload, sender)
  sender = sender or "DebugPeer"
  local Sync = Fundraiser.Adapters.ThinGuildSync
  if not Sync or not Sync.OnAddonMessage then
    Print(Fundraiser:T("CHAT_DEBUG_NO_SYNC"))
    return false
  end
  Sync:OnAddonMessage(prefix(), payload, "GUILD", sender)
  return true
end

function Debug:SeedEvent()
  local Event = Fundraiser.Domain.Event
  local Store = Fundraiser.Adapters.Store
  local current = Store:GetEvent()
  local revision = current and ((tonumber(current.revision) or 0) + 1) or 1
  -- Keep target off the local player so MAIL_SHOW reminders still appear while solo-testing.
  local target = "Bank Alt"
  local event, err = Event.Create({
    id = "debug-event",
    name = "Debug Tabard Fund",
    target = target,
    goal = "Solo debug seed",
    intervalSeconds = 60,
    minAdminRank = 1,
    revision = revision,
    publishedAt = now(),
    publisher = "DebugOfficer",
  })
  if not event then
    Print(Fundraiser:T("CHAT_DEBUG_FAIL", tostring(err)))
    return nil
  end
  Store:SetEvent(event)
  Print(Fundraiser:T("CHAT_DEBUG_SEEDED", event.name, event.target, tostring(event.intervalSeconds)))
  return event
end

function Debug:FakeHello(name, guid)
  name = name or "DebugMember"
  guid = guid or ("debug-guid-" .. name)
  local Codec = Fundraiser.Adapters.Codec
  local version = (Fundraiser.Config and Fundraiser.Config.VERSION) or "0.0.0"
  if self:Inject(Codec.EncodeHello(version, guid), name) then
    Print(Fundraiser:T("CHAT_DEBUG_HELLO", name, guid))
  end
end

function Debug:FakeEvent(asRank)
  asRank = tonumber(asRank) or 0
  local Store = Fundraiser.Adapters.Store
  local event = Store:GetEvent() or self:SeedEvent()
  if not event then
    return
  end
  -- Bypass roster lookup: apply with an explicit simulated sender rank.
  local UC = Fundraiser.Application.UseCases
  local deps = {
    getEvent = function()
      return Store:GetEvent()
    end,
    setEvent = function(e)
      Store:SetEvent(e)
    end,
  }
  -- Bump revision so AcceptRemoteEvent sees a newer snapshot.
  local copy = {}
  for k, v in pairs(event) do
    copy[k] = v
  end
  copy.revision = (tonumber(event.revision) or 0) + 1
  copy.publishedAt = now()
  copy.publisher = "DebugOfficer"
  local accepted, err = UC.AcceptRemoteEvent(deps, copy, asRank)
  if accepted then
    Print(Fundraiser:T("CHAT_DEBUG_EVENT", accepted.name, tostring(asRank), tostring(accepted.revision)))
  else
    Print(Fundraiser:T("CHAT_DEBUG_FAIL", tostring(err)))
  end
end

function Debug:FakeLedger(kind, name, copper, detail)
  kind = kind or "mail"
  name = name or "DebugDonor"
  copper = tonumber(copper) or 12345
  detail = detail or "debug"
  local Store = Fundraiser.Adapters.Store
  local event = Store:GetEvent()
  if not event then
    event = self:SeedEvent()
  end
  if not event then
    return
  end
  local Ledger = Fundraiser.Domain.Ledger
  local entry = Ledger.CreateEntry({
    kind = kind,
    name = name,
    detail = detail,
    copper = copper,
    eventId = event.id,
    at = now(),
  })
  if not entry then
    Print(Fundraiser:T("CHAT_DEBUG_FAIL", "bad_entry"))
    return
  end
  local Codec = Fundraiser.Adapters.Codec
  -- Inject as if sent by the donation target so officers accept the merge.
  local sender = event.target or name
  if self:Inject(Codec.EncodeLedgerEntry(entry), sender) then
    Print(Fundraiser:T("CHAT_DEBUG_LEDGER", kind, name, Fundraiser.FormatCopper(copper)))
  end
end

function Debug:FakeDigest()
  local Codec = Fundraiser.Adapters.Codec
  local Store = Fundraiser.Adapters.Store
  local Ledger = Fundraiser.Domain.Ledger
  local event = Store:GetEvent()
  local count, sum, maxAt = Ledger.Fingerprint(Store:GetContributions() or {})
  local payload = Codec.EncodeDigest(event and event.revision or 0, count, sum, maxAt)
  if self:Inject(payload, "DebugPeer") then
    Print(Fundraiser:T("CHAT_DEBUG_DIGEST", tostring(event and event.revision or 0), tostring(count)))
  end
end

function Debug:ShowReminder()
  local Store = Fundraiser.Adapters.Store
  local event = Store:GetEvent() or self:SeedEvent()
  if not event then
    return
  end
  if Fundraiser.UI and Fundraiser.UI.Reminder and Fundraiser.UI.Reminder.ShowForEvent then
    Fundraiser.UI.Reminder:ShowForEvent(event)
    Print(Fundraiser:T("CHAT_DEBUG_REMINDER"))
  end
end

function Debug:DismissReminder()
  local Store = Fundraiser.Adapters.Store
  local event = Store:GetEvent()
  if not event then
    Print(Fundraiser:T("CHAT_NO_EVENT"))
    return
  end
  local UC = Fundraiser.Application.UseCases
  UC.DismissReminder({
    getReminderState = function()
      return Store:GetReminderState()
    end,
    setReminderState = function(s)
      Store:SetReminderState(s)
    end,
  }, now(), event.id)
  if Fundraiser.UI and Fundraiser.UI.Reminder and Fundraiser.UI.Reminder.Hide then
    Fundraiser.UI.Reminder:Hide()
  end
  Print(Fundraiser:T("CHAT_DEBUG_DISMISS"))
end

function Debug:PrintPresence()
  local Store = Fundraiser.Adapters.Store
  local presence = Store:GetPresence() or {}
  local n = 0
  for key, entry in pairs(presence) do
    n = n + 1
    Print(string.format("  %s → hello=%s ver=%s", tostring(key), tostring(entry.lastHello), tostring(entry.version)))
  end
  if n == 0 then
    Print(Fundraiser:T("CHAT_DEBUG_PRESENCE_EMPTY"))
  else
    Print(Fundraiser:T("CHAT_DEBUG_PRESENCE", tostring(n)))
  end
end

function Debug:SetAsRank(rankIndex)
  local Roster = Fundraiser.Adapters.Roster
  if rankIndex == nil then
    Roster:SetRankOverride(nil)
    Print(Fundraiser:T("CHAT_DEBUG_ASRANK_CLEAR"))
    return
  end
  Roster:SetRankOverride(rankIndex)
  Print(Fundraiser:T("CHAT_DEBUG_ASRANK", tostring(rankIndex)))
end

function Debug:PrintAccess()
  local Roster = Fundraiser.Adapters.Roster
  local Store = Fundraiser.Adapters.Store
  local Roles = Fundraiser.Domain.Roles
  local event = Store:GetEvent()
  local rank = Roster:GetPlayerRankIndex()
  local manage = Roles.CanManageFundraiser(rank, event) and "yes" or "no"
  local target = Roles.IsDonationTarget(event, Roster:GetPlayerName()) and "yes" or "no"
  local adminUi = Fundraiser.CanOpenAdminUi and Fundraiser:CanOpenAdminUi() and "yes" or "no"
  local targetUi = Fundraiser.CanOpenTargetUi and Fundraiser:CanOpenTargetUi() and "yes" or "no"
  Print(Fundraiser:T("CHAT_DEBUG_ACCESS", tostring(rank), manage, target, adminUi, targetUi))
end

-- Simulate a non-officer: high rank index, then try opening admin UI (should refuse).
function Debug:SimulateMember()
  self:SeedEvent()
  self:SetAsRank(9)
  self:PrintAccess()
  if Fundraiser.ToggleWindow then
    Fundraiser:ToggleWindow()
  end
end

function Debug:SimulateOfficer()
  self:SetAsRank(0)
  self:PrintAccess()
end

function Debug:Help()
  Print(Fundraiser:T("CHAT_DEBUG_HELP"))
end

-- msg is the text after "debug"
function Debug:Handle(msg)
  if not self:IsEnabled() then
    Print(Fundraiser:T("CHAT_DEBUG_OFF"))
    return
  end
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "" or msg == "help" then
    self:Help()
    return
  end

  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = cmd and cmd:lower() or ""
  rest = rest or ""

  if cmd == "seed" then
    self:SeedEvent()
  elseif cmd == "hello" then
    local name, guid = rest:match("^(%S+)%s*(%S*)$")
    self:FakeHello(name ~= "" and name or nil, guid ~= "" and guid or nil)
  elseif cmd == "event" then
    local rank = rest:match("^(%d+)")
    self:FakeEvent(rank)
  elseif cmd == "ledger" or cmd == "donate" or cmd == "mail" or cmd == "ah" then
    local kind = "mail"
    if cmd == "ah" then
      kind = "ah"
    elseif cmd == "ledger" then
      local k = rest:match("^(%S+)")
      if k == "ah" or k == "mail" then
        kind = k
        rest = rest:gsub("^%S+%s*", "")
      end
    end
    local name, copper, detail = rest:match("^(%S+)%s*(%S*)%s*(.*)$")
    self:FakeLedger(kind, name ~= "" and name or nil, copper, detail ~= "" and detail or nil)
  elseif cmd == "digest" then
    self:FakeDigest()
  elseif cmd == "reminder" then
    self:ShowReminder()
  elseif cmd == "dismiss" then
    self:DismissReminder()
  elseif cmd == "presence" then
    self:PrintPresence()
  elseif cmd == "asrank" then
    local arg = (rest:match("^(%S+)") or ""):lower()
    if arg == "" or arg == "clear" or arg == "reset" then
      self:SetAsRank(nil)
    else
      self:SetAsRank(tonumber(arg))
    end
    self:PrintAccess()
  elseif cmd == "member" then
    self:SimulateMember()
  elseif cmd == "officer" then
    self:SimulateOfficer()
  elseif cmd == "access" then
    self:PrintAccess()
  else
    Print(Fundraiser:T("CHAT_DEBUG_UNKNOWN", cmd))
    self:Help()
  end
end
