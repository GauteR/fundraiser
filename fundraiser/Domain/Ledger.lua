-- Domain: donation-target ledger with id-based merge (union / newer wins).
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local Ledger = {}
Fundraiser.Domain.Ledger = Ledger

local function trim(s)
  if type(s) ~= "string" then
    return ""
  end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Build a stable entry. id optional; derived from kind/name/copper/at/detail when missing.
function Ledger.CreateEntry(fields)
  fields = fields or {}
  local kind = trim(fields.kind or "")
  -- manual = donation entered by hand on the donation target (e.g. gold traded in person).
  if kind ~= "mail" and kind ~= "ah" and kind ~= "manual" then
    return nil, "bad_kind"
  end
  local eventId = trim(fields.eventId or "")
  if eventId == "" then
    return nil, "bad_event"
  end
  local copper = tonumber(fields.copper) or 0
  if copper < 0 then
    return nil, "bad_copper"
  end
  local at = tonumber(fields.at) or 0
  local name = trim(fields.name or "")
  local detail = trim(fields.detail or "")
  local id = trim(fields.id or "")
  if id == "" then
    id = string.format("%s:%s:%d:%d:%s", kind, name, copper, at, detail)
  end
  return {
    id = id,
    kind = kind,
    name = name,
    detail = detail,
    copper = copper,
    eventId = eventId,
    at = at,
  }
end

function Ledger.FilterByEvent(entries, eventId)
  local out = {}
  if type(entries) ~= "table" or not eventId then
    return out
  end
  for _, row in ipairs(entries) do
    if row.eventId == eventId then
      out[#out + 1] = row
    end
  end
  return out
end

function Ledger.TotalCopper(entries)
  local sum = 0
  if type(entries) ~= "table" then
    return 0
  end
  for _, row in ipairs(entries) do
    sum = sum + (tonumber(row.copper) or 0)
  end
  return sum
end

-- Insert or replace by id (newer at wins; equal at keeps higher copper).
function Ledger.Upsert(entries, entry)
  entries = entries or {}
  if not entry or not entry.id then
    return entries, false
  end
  for i, row in ipairs(entries) do
    if row.id == entry.id then
      local ea, ra = tonumber(entry.at) or 0, tonumber(row.at) or 0
      if ea > ra or (ea == ra and (tonumber(entry.copper) or 0) > (tonumber(row.copper) or 0)) then
        entries[i] = entry
        return entries, true
      end
      return entries, false
    end
  end
  entries[#entries + 1] = entry
  return entries, true
end

-- Union merge like a repo merge: keep every id; conflicts → newer at / richer copper.
function Ledger.Merge(localEntries, remoteEntries)
  local byId = {}
  local function consider(list)
    if type(list) ~= "table" then
      return
    end
    for _, row in ipairs(list) do
      if row and row.id then
        local cur = byId[row.id]
        if not cur then
          byId[row.id] = row
        else
          local ra, ca = tonumber(row.at) or 0, tonumber(cur.at) or 0
          if ra > ca or (ra == ca and (tonumber(row.copper) or 0) > (tonumber(cur.copper) or 0)) then
            byId[row.id] = row
          end
        end
      end
    end
  end
  consider(localEntries)
  consider(remoteEntries)
  local out = {}
  for _, row in pairs(byId) do
    out[#out + 1] = row
  end
  table.sort(out, function(a, b)
    local aa, ba = tonumber(a.at) or 0, tonumber(b.at) or 0
    if aa ~= ba then
      return aa < ba
    end
    return tostring(a.id) < tostring(b.id)
  end)
  return out
end

function Ledger.Fingerprint(entries)
  entries = entries or {}
  local n = #entries
  local sum = Ledger.TotalCopper(entries)
  local maxAt = 0
  for _, row in ipairs(entries) do
    local at = tonumber(row.at) or 0
    if at > maxAt then
      maxAt = at
    end
  end
  return n, sum, maxAt
end
