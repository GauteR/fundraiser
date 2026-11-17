-- Domain: who may view/write/accept ledger replicas.
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local Roles = {}
Fundraiser.Domain.Roles = Roles

local function shortName(name)
  if not name then
    return nil
  end
  name = tostring(name)
  name = name:match("^([^%-]+)") or name
  return name:lower()
end

function Roles.NormalizeName(name)
  return shortName(name)
end

function Roles.IsDonationTarget(event, playerName)
  if not event or not event.target then
    return false
  end
  local a = shortName(event.target)
  local b = shortName(playerName)
  return a ~= nil and b ~= nil and a == b
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

-- New ledger rows originate on the donation target; officers only replicate.
function Roles.CanWriteLedger(event, playerName)
  return Roles.IsDonationTarget(event, playerName)
end

-- Accept a replica push from the target or from another officer.
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
