-- Thin guild sync: HELLO / EVENT / LEDGER / DIGEST over SendAddonMessage.
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

function Sync:BroadcastHello()
  local Codec = Fundraiser.Adapters.Codec
  local version = cfg().VERSION or "?"
  local guid = Fundraiser.Adapters.Roster:GetPlayerGUID() or ""
  return self:Send(Codec.EncodeHello(version, guid))
end

function Sync:BroadcastEvent(event)
  local Codec = Fundraiser.Adapters.Codec
  return self:Send(Codec.EncodeEvent(event))
end

function Sync:BroadcastLedgerEntry(entry)
  if not self:LocalCanViewLedger() then
    return false
  end
  local Codec = Fundraiser.Adapters.Codec
  return self:Send(Codec.EncodeLedgerEntry(entry))
end

function Sync:BroadcastLedgerSnapshot()
  if not self:LocalCanViewLedger() then
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
  if self:LocalCanViewLedger() then
    count, sum, maxAt = Ledger.Fingerprint(Store:GetContributions() or {})
  end
  return self:Send(Codec.EncodeDigest(event and event.revision or 0, count, sum, maxAt))
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
  local Roles = Fundraiser.Domain.Roles
  local t = now()

  if msg.kind == "HELLO" then
    local key = msg.guid ~= "" and msg.guid or sender
    Store:SetPresenceEntry(key, { name = sender, guid = msg.guid, version = msg.version, lastHello = t })
    local short = sender and (sender:match("^([^%-]+)") or sender)
    if short then
      Store:SetPresenceEntry(short, { name = short, guid = msg.guid, version = msg.version, lastHello = t })
    end
    -- If we hold a ledger replica and the peer is target/officer, push our rows.
    local event = Store:GetEvent()
    local senderRank = Roster:RankIndexOfName(sender)
    if event and self:LocalCanViewLedger() and Roles.CanAcceptLedgerFrom(event, sender, senderRank) then
      self:BroadcastLedgerSnapshot()
    end
    return
  end

  if msg.kind == "EVENT" then
    local rank = Roster:RankIndexOfName(sender)
    UC.AcceptRemoteEvent(storeDeps(), msg, rank)
    return
  end

  if msg.msgKind == "LEDGER" then
    local event = Store:GetEvent()
    if not event then
      return
    end
    local senderRank = Roster:RankIndexOfName(sender)
    UC.MergeRemoteLedger(storeDeps(), { msg }, sender, senderRank)
    return
  end

  if msg.kind == "DIGEST" then
    local event = Store:GetEvent()
    local myRev = event and event.revision or 0
    if (msg.eventRevision or 0) < myRev then
      if event then
        self:BroadcastEvent(event)
      end
    elseif (msg.eventRevision or 0) > myRev then
      self:BroadcastDigest()
    end
    if self:LocalCanViewLedger() then
      local Ledger = Fundraiser.Domain.Ledger
      local count, sum, maxAt = Ledger.Fingerprint(Store:GetContributions() or {})
      local remoteNewer = (msg.ledgerMaxAt or 0) > maxAt
        or (msg.ledgerCount or 0) > count
        or (msg.ledgerSum or 0) > sum
      if remoteNewer then
        -- Ask peers to push by saying hello again (they snapshot on HELLO).
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
