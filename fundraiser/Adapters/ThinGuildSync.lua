-- Thin guild sync: HELLO / EVENT / LEDGER / DIGEST / RESET over SendAddonMessage.
-- Ledger mesh: all installed clients store + relay rows; UI view stays rank-gated.
-- Epoch flow: BroadcastReset bumps local resetEpoch then encodes it; HELLO/DIGEST
-- from a higher epoch force a local ledger wipe so stale peers cannot refill.
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local Sync = {}
Fundraiser.Adapters.ThinGuildSync = Sync

local function cfg()
  return Fundraiser.Config or {}
end

local function now()
  return (GetServerTime and GetServerTime()) or (time and time()) or 0
end

function Sync:IsEnabled()
  return Fundraiser:IsEnabled() and cfg().COMM == true
end

function Sync:Send(payload)
  if not self:IsEnabled() then
    return false
  end
  if not IsInGuild or not IsInGuild() then
    return false
  end
  local prefix = cfg().COMM_PREFIX or "Fundraiser"
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(prefix, payload, "GUILD")
    return true
  end
  if SendAddonMessage then
    SendAddonMessage(prefix, payload, "GUILD")
    return true
  end
  return false
end

local function storeDeps()
  local Store = Fundraiser.Adapters.Store
  local Roster = Fundraiser.Adapters.Roster
  return {
    getEvent = function()
      return Store:GetEvent()
    end,
    setEvent = function(e)
      Store:SetEvent(e)
    end,
    getContributions = function()
      return Store:GetContributions()
    end,
    setContributions = function(list)
      Store:SetContributions(list)
    end,
    getResetEpoch = function()
      return Store:GetResetEpoch()
    end,
    archiveEvent = function(event, contributions, archivedAt)
      Store:ArchiveEvent(event, contributions, archivedAt)
    end,
    clearContributions = function()
      Store:ClearLedger()
    end,
    clearReminder = function()
      Store:SetReminderState({})
    end,
    getPlayerName = function()
      return Roster:GetPlayerName()
    end,
    getPlayerRankIndex = function()
      return Roster:GetPlayerRankIndex()
    end,
    broadcastLedgerEntry = function(entry)
      Sync:BroadcastLedgerEntry(entry)
    end,
  }
end

function Sync:LocalCanViewLedger()
  local Roles = Fundraiser.Domain.Roles
  local Store = Fundraiser.Adapters.Store
  local Roster = Fundraiser.Adapters.Roster
  local event = Store:GetEvent()
  return Roles.CanViewLedger(event, Roster:GetPlayerRankIndex(), Roster:GetPlayerName())
end

function Sync:LocalLedgerCount()
  local Store = Fundraiser.Adapters.Store
  local list = Store:GetContributions() or {}
  return #list
end

function Sync:BroadcastHello()
  local Codec = Fundraiser.Adapters.Codec
  local Store = Fundraiser.Adapters.Store
  local version = cfg().VERSION or "?"
  local guid = Fundraiser.Adapters.Roster:GetPlayerGUID() or ""
  return self:Send(Codec.EncodeHello(version, guid, Store:GetResetEpoch()))
end

function Sync:BroadcastEvent(event)
  local Codec = Fundraiser.Adapters.Codec
  return self:Send(Codec.EncodeEvent(event))
end

-- Officer broadcast: apply local wipe, bump epoch, peers apply when sender rank is admin.
function Sync:BroadcastReset(scope)
  if not cfg().RESET_SYNC then
    return false
  end
  if not (Fundraiser.CanOpenAdminUi and Fundraiser:CanOpenAdminUi()) then
    return false
  end
  local Store = Fundraiser.Adapters.Store
  local Codec = Fundraiser.Adapters.Codec
  local Roster = Fundraiser.Adapters.Roster
  local publisher = Roster and Roster.GetPlayerName and Roster:GetPlayerName() or ""
  local ok, epoch = Store:ApplyResetScope(scope or "all")
  if not ok then
    return false
  end
  return self:Send(Codec.EncodeReset(scope or "all", now(), publisher, epoch))
end

-- Originating write or mesh rebroadcast of a stored row (any holder may send).
function Sync:BroadcastLedgerEntry(entry)
  if not (cfg().LEDGER) then
    return false
  end
  if not entry then
    return false
  end
  local Codec = Fundraiser.Adapters.Codec
  local Store = Fundraiser.Adapters.Store
  return self:Send(Codec.EncodeLedgerEntry(entry, Store:GetResetEpoch()))
end

function Sync:BroadcastLedgerSnapshot()
  if not (cfg().LEDGER) then
    return false
  end
  local Store = Fundraiser.Adapters.Store
  local list = Store:GetContributions() or {}
  for _, entry in ipairs(list) do
    self:BroadcastLedgerEntry(entry)
  end
  return true
end

function Sync:BroadcastDigest()
  local Codec = Fundraiser.Adapters.Codec
  local Store = Fundraiser.Adapters.Store
  local Ledger = Fundraiser.Domain.Ledger
  local event = Store:GetEvent()
  local count, sum, maxAt = 0, 0, 0
  if cfg().LEDGER then
    count, sum, maxAt = Ledger.Fingerprint(Store:GetContributions() or {})
  end
  return self:Send(
    Codec.EncodeDigest(event and event.revision or 0, count, sum, maxAt, Store:GetResetEpoch())
  )
end

function Sync:OnAddonMessage(prefix, message, channel, sender)
  if not self:IsEnabled() then
    return
  end
  if prefix ~= (cfg().COMM_PREFIX or "Fundraiser") then
    return
  end
  if channel ~= "GUILD" then
    return
  end
  local Codec = Fundraiser.Adapters.Codec
  local msg = Codec.Decode(message)
  if not msg then
    return
  end

  local Store = Fundraiser.Adapters.Store
  local Roster = Fundraiser.Adapters.Roster
  local UC = Fundraiser.Application.UseCases
  local t = now()

  if msg.kind == "HELLO" then
    local key = msg.guid ~= "" and msg.guid or sender
    Store:SetPresenceEntry(key, { name = sender, guid = msg.guid, version = msg.version, lastHello = t })
    local full = sender and Fundraiser.Domain.Roles.DisplayName(sender)
    if full then
      Store:SetPresenceEntry(full, { name = full, guid = msg.guid, version = msg.version, lastHello = t })
    end
    local remoteEpoch = tonumber(msg.resetEpoch) or 0
    local localEpoch = Store:GetResetEpoch()
    if remoteEpoch > localEpoch then
      -- Peer already wiped; drop stale local ledger and adopt their epoch.
      Store:ApplyResetScope("ledger", remoteEpoch)
    elseif remoteEpoch < localEpoch then
      self:BroadcastDigest()
    elseif Store:GetEvent() and self:LocalLedgerCount() > 0 then
      -- Same epoch: any peer holding rows can push so officers need not all be online.
      self:BroadcastLedgerSnapshot()
    end
    return
  end

  if msg.kind == "EVENT" then
    local rank = Roster:RankIndexOfName(sender)
    UC.AcceptRemoteEvent(storeDeps(), msg, rank)
    return
  end

  if msg.kind == "RESET" then
    if not cfg().RESET_SYNC then
      return
    end
    local rank = Roster:RankIndexOfName(sender)
    local ok = UC.AcceptRemoteReset({
      applyReset = function(scope, epoch)
        return Store:ApplyResetScope(scope, epoch)
      end,
    }, msg.scope, rank, msg.resetEpoch)
    if ok and DEFAULT_CHAT_FRAME and Fundraiser.T then
      DEFAULT_CHAT_FRAME:AddMessage(
        Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("CHAT_RESET_APPLIED", tostring(msg.scope), tostring(sender))
      )
    end
    return
  end

  if msg.msgKind == "LEDGER" then
    if not cfg().LEDGER then
      return
    end
    local event = Store:GetEvent()
    if not event then
      return
    end
    local senderRank = Roster:RankIndexOfName(sender)
    UC.MergeRemoteLedger(storeDeps(), { msg }, sender, senderRank)
    return
  end

  if msg.kind == "DIGEST" then
    local remoteEpoch = tonumber(msg.resetEpoch) or 0
    local localEpoch = Store:GetResetEpoch()
    if remoteEpoch > localEpoch then
      Store:ApplyResetScope("ledger", remoteEpoch)
    end
    local event = Store:GetEvent()
    local myRev = event and event.revision or 0
    if (msg.eventRevision or 0) < myRev then
      if event then
        self:BroadcastEvent(event)
      end
    elseif (msg.eventRevision or 0) > myRev then
      self:BroadcastDigest()
    end
    if cfg().LEDGER then
      localEpoch = Store:GetResetEpoch()
      remoteEpoch = tonumber(msg.resetEpoch) or 0
      if remoteEpoch ~= localEpoch then
        -- Epoch mismatch: digest already handled adopt; do not exchange stale rows.
        return
      end
      local Ledger = Fundraiser.Domain.Ledger
      local count, sum, maxAt = Ledger.Fingerprint(Store:GetContributions() or {})
      local remoteNewer = (msg.ledgerMaxAt or 0) > maxAt
        or (msg.ledgerCount or 0) > count
        or (msg.ledgerSum or 0) > sum
      if remoteNewer then
        self:BroadcastHello()
      elseif (msg.ledgerCount or 0) < count then
        self:BroadcastLedgerSnapshot()
      end
    end
  end
end

function Sync:Initialize()
  if self.initialized then
    return
  end
  if not self:IsEnabled() then
    return
  end

  local prefix = cfg().COMM_PREFIX or "Fundraiser"
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(prefix)
  end

  local frame = CreateFrame("Frame", "FundraiserSyncFrame")
  frame:RegisterEvent("CHAT_MSG_ADDON")
  frame:RegisterEvent("PLAYER_GUILD_UPDATE")
  frame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
      self:OnAddonMessage(...)
    elseif event == "PLAYER_GUILD_UPDATE" then
      self:BroadcastHello()
      self:BroadcastDigest()
    end
  end)
  self.frame = frame
  self.initialized = true

  self:BroadcastHello()
  self:BroadcastDigest()
end
