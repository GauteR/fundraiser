-- Guild roster port (Forever / Classic-compatible APIs).
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local Roster = {}
Fundraiser.Adapters.Roster = Roster

function Roster:IsInGuild()
  if IsInGuild then
    return IsInGuild() and true or false
  end
  return false
end

function Roster:GetGuildName()
  if GetGuildInfo then
    return GetGuildInfo("player")
  end
  return nil
end

function Roster:GetPlayerRankIndex()
  if not self:IsInGuild() then
    return nil
  end
  -- GetGuildRosterInfo index for player; fall back to GuildRoster scan.
  if GetGuildInfo then
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex
  end
  return nil
end

function Roster:GetPlayerName()
  if UnitName then
    return UnitName("player")
  end
  return nil
end

function Roster:GetPlayerGUID()
  if UnitGUID then
    return UnitGUID("player")
  end
  return nil
end

function Roster:Request()
  if GuildRoster then
    GuildRoster()
  end
end

-- Returns array of { name, guid, rankIndex, online }.
function Roster:GetMembers()
  local members = {}
  if not self:IsInGuild() or not GetNumGuildMembers then
    return members
  end
  local n = GetNumGuildMembers()
  for i = 1, n do
    local name, _, rankIndex, _, _, _, _, _, online, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
    if name then
      -- Strip realm if present.
      name = name:match("^([^%-]+)") or name
      members[#members + 1] = {
        name = name,
        guid = guid or name,
        rankIndex = rankIndex,
        online = online and true or false,
      }
    end
  end
  return members
end

function Roster:RankIndexOfName(senderName)
  if not senderName then
    return nil
  end
  senderName = senderName:match("^([^%-]+)") or senderName
  for _, m in ipairs(self:GetMembers()) do
    if m.name == senderName then
      return m.rankIndex
    end
  end
  return nil
end
