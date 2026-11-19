-- Guild roster port (Forever / Classic-compatible APIs).
-- Forever names include first + last (spaces); do not truncate at the first space.
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local Roster = {}
Fundraiser.Adapters.Roster = Roster

local function displayName(name)
  local Roles = Fundraiser.Domain and Fundraiser.Domain.Roles
  if Roles and Roles.DisplayName then
    return Roles.DisplayName(name)
  end
  return name
end

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
  -- Debug override: /fundraiser debug asrank <n> | member | officer | asrank clear
  if self.rankOverride ~= nil then
    return self.rankOverride
  end
  if not self:IsInGuild() then
    return nil
  end
  if GetGuildInfo then
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex
  end
  return nil
end

function Roster:SetRankOverride(rankIndex)
  if rankIndex == nil then
    self.rankOverride = nil
    return
  end
  self.rankOverride = tonumber(rankIndex)
end

function Roster:GetPlayerName()
  -- Forever names are "First Last". UnitName returns both parts, while UnitFullName may return
  -- only the first part as its name, so take whichever candidate has a space, else any.
  local candidates = {}
  if UnitName then
    candidates[#candidates + 1] = UnitName("player")
  end
  if UnitFullName then
    candidates[#candidates + 1] = (UnitFullName("player"))
  end
  local name
  for _, n in ipairs(candidates) do
    if type(n) == "string" and n ~= "" then
      name = name or n
      if n:find(" ", 1, true) then
        name = n
        break
      end
    end
  end
  return displayName(name)
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

function Roster:GetMembers()
  local members = {}
  if not self:IsInGuild() or not GetNumGuildMembers then
    return members
  end
  local n = GetNumGuildMembers()
  for i = 1, n do
    local name, _, rankIndex, _, _, _, _, _, online, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
    if name then
      name = displayName(name)
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
  local Roles = Fundraiser.Domain.Roles
  for _, m in ipairs(self:GetMembers()) do
    if Roles.NamesEqual(m.name, senderName) then
      return m.rankIndex
    end
  end
  return nil
end

-- Guild message of the day (client API may be missing on some builds: hide the button then).
function Roster:CanEditMotd()
  if C_GuildInfo and C_GuildInfo.CanEditMOTD then
    return C_GuildInfo.CanEditMOTD() and GuildSetMOTD ~= nil
  end
  if CanEditMOTD then
    return CanEditMOTD() and GuildSetMOTD ~= nil
  end
  return false
end

function Roster:SetMotd(text)
  if not GuildSetMOTD then
    return false
  end
  GuildSetMOTD(text)
  return true
end
