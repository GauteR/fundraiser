-- Domain: who may view/write/accept ledger replicas.
-- Forever character names are "First Last" (spaces); do not truncate at the first space.
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local Roles = {}
Fundraiser.Domain.Roles = Roles

-- Strip a trailing -Realm token only; keep "First Last".
local function stripRealm(name)
  -- "First Last-Realm" or "Name-Realm" → drop realm when it has no spaces.
  local base, realm = name:match("^(.-)%-([%w]+)$")
  if base and realm then
    return base
  end
  return name
end

-- Canonical compare key: full Forever name, lowercased, collapsed spaces.
function Roles.NormalizeName(name)
  if name == nil then
    return nil
  end
  name = tostring(name)
  name = stripRealm(name)
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  name = name:gsub("%s+", " ")
  if name == "" then
    return nil
  end
  return name:lower()
end

-- Preserve "First Last" casing for storage/display (still strip realm + collapse spaces).
function Roles.DisplayName(name)
  if name == nil then
    return nil
  end
  name = tostring(name)
  name = stripRealm(name)
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  name = name:gsub("%s+", " ")
  if name == "" then
    return nil
  end
  return name
end

function Roles.IsFullCharacterName(name)
  local n = Roles.NormalizeName(name)
  if not n then
    return false
  end
  local parts = 0
  for _ in n:gmatch("%S+") do
    parts = parts + 1
  end
  return parts >= 2
end

function Roles.NamesEqual(a, b)
  local na, nb = Roles.NormalizeName(a), Roles.NormalizeName(b)
  return na ~= nil and nb ~= nil and na == nb
end

function Roles.IsDonationTarget(event, playerName)
  if not event or not event.target then
    return false
  end
  return Roles.NamesEqual(event.target, playerName)
end

function Roles.CanViewLedger(event, rankIndex, playerName)
  if not event then
    return false
  end
  if Roles.IsDonationTarget(event, playerName) then
    return true
  end
  local Rank = Fundraiser.Domain.Rank
  return Rank.IsAdmin(rankIndex, event.minAdminRank)
end

function Roles.CanWriteLedger(event, playerName)
  return Roles.IsDonationTarget(event, playerName)
end

function Roles.CanAcceptLedgerFrom(event, senderName, senderRankIndex)
  if not event then
    return false
  end
  if Roles.IsDonationTarget(event, senderName) then
    return true
  end
  local Rank = Fundraiser.Domain.Rank
  return Rank.IsAdmin(senderRankIndex, event.minAdminRank)
end
