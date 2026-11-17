-- Domain: self-attested contribution ledger helpers.
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local Ledger = {}
Fundraiser.Domain.Ledger = Ledger

-- contributions: list of { name=, guid=, copper=, eventId=, at= }
function Ledger.FilterByEvent(contributions, eventId)
  local out = {}
  if type(contributions) ~= "table" or not eventId then
    return out
  end
  for _, row in ipairs(contributions) do
    if row.eventId == eventId then
      out[#out + 1] = row
    end
  end
  return out
end

function Ledger.TotalCopper(contributions)
  local sum = 0
  if type(contributions) ~= "table" then
    return 0
  end
  for _, row in ipairs(contributions) do
    sum = sum + (tonumber(row.copper) or 0)
  end
  return sum
end

-- Upsert by guid+eventId; keep higher copper / later timestamp.
function Ledger.Upsert(contributions, entry)
  contributions = contributions or {}
  if not entry or not entry.guid or not entry.eventId then
    return contributions, false
  end
  for i, row in ipairs(contributions) do
    if row.guid == entry.guid and row.eventId == entry.eventId then
      local newer = (tonumber(entry.at) or 0) >= (tonumber(row.at) or 0)
      if newer then
        contributions[i] = entry
        return contributions, true
      end
      return contributions, false
    end
  end
  contributions[#contributions + 1] = entry
  return contributions, true
end
