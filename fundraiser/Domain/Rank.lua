-- Domain: guild rank authorization (lower index = higher privilege in WoW).
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local Rank = {}
Fundraiser.Domain.Rank = Rank

-- rankIndex 0 is typically Guild Master. Admin if index <= minAdminRank.
function Rank.IsAdmin(rankIndex, minAdminRank)
  rankIndex = tonumber(rankIndex)
  minAdminRank = tonumber(minAdminRank)
  if rankIndex == nil or minAdminRank == nil then
    return false
  end
  if rankIndex < 0 or minAdminRank < 0 then
    return false
  end
  return rankIndex <= minAdminRank
end
