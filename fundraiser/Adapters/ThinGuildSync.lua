-- Thin guild sync: HELLO / EVENT / DONATE / DIGEST over SendAddonMessage.
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local Sync = {}
Fundraiser.Adapters.ThinGuildSync = Sync

local function cfg()
  return Fundraiser.Config or {}
end

local function printMsg(msg)
  if DEFAULT_CHAT_FRAME and Fundraiser.T then
    DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. msg)
  end
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

function Sync:BroadcastDonation(entry)
  local Codec = Fundraiser.Adapters.Codec
  return self:Send(Codec.EncodeDonate(entry))
end

function Sync:BroadcastDigest()
  local Codec = Fundraiser.Adapters.Codec
  local Store = Fundraiser.Adapters.Store
  local event = Store:GetEvent()
  local contribs = Store:GetContributions() or {}
  return self:Send(Codec.EncodeDigest(event and event.revision or 0, #contribs))
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
  local now = (GetServerTime and GetServerTime()) or (time and time()) or 0

  if msg.kind == "HELLO" then
    local key = msg.guid ~= "" and msg.guid or sender
    Store:SetPresenceEntry(key, { name = sender, guid = msg.guid, version = msg.version, lastHello = now })
    -- Also index by short name for missing-install scans.
    local short = sender and (sender:match("^([^%-]+)") or sender)
    if short then
      Store:SetPresenceEntry(short, { name = short, guid = msg.guid, version = msg.version, lastHello = now })
    end
    return
  end

  if msg.kind == "EVENT" then
    local rank = Roster:RankIndexOfName(sender)
    local deps = {
      getEvent = function()
        return Store:GetEvent()
      end,
      setEvent = function(e)
        Store:SetEvent(e)
      end,
    }
    UC.AcceptRemoteEvent(deps, msg, rank)
    return
  end

  if msg.kind == "DONATE" then
    -- Only accept donations claimed for the sender's own identity (best-effort).
    local short = sender and (sender:match("^([^%-]+)") or sender)
    if msg.name and short and msg.name ~= short then
      return
    end
    local deps = {
      getContributions = function()
        return Store:GetContributions()
      end,
      setContributions = function(list)
        Store:SetContributions(list)
      end,
    }
    UC.RecordDonation(deps, msg)
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
      -- Peer has newer event; ask by re-broadcasting digest — they may push EVENT.
      self:BroadcastDigest()
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
