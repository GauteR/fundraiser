-- Encode/decode thin guild sync payloads (pipe-separated, ASCII-safe).
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local Codec = {}
Fundraiser.Adapters.Codec = Codec

local SEP = "|"

local function esc(s)
  s = tostring(s or "")
  s = s:gsub("\\", "\\\\")
  s = s:gsub("|", "\\|")
  return s
end

local function unesc(s)
  s = tostring(s or "")
  local out, i = {}, 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == "\\" and i < #s then
      out[#out + 1] = s:sub(i + 1, i + 1)
      i = i + 2
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

local function split(payload)
  local parts = {}
  local buf = {}
  local i = 1
  local s = tostring(payload or "")
  while i <= #s do
    local c = s:sub(i, i)
    if c == "\\" and i < #s then
      buf[#buf + 1] = s:sub(i, i + 1)
      i = i + 2
    elseif c == SEP then
      parts[#parts + 1] = unesc(table.concat(buf))
      buf = {}
      i = i + 1
    else
      buf[#buf + 1] = c
      i = i + 1
    end
  end
  parts[#parts + 1] = unesc(table.concat(buf))
  return parts
end

function Codec.EncodeHello(version, guid, resetEpoch)
  return table.concat({ "HELLO", esc(version), esc(guid), tostring(resetEpoch or 0) }, SEP)
end

function Codec.DecodeHello(payload)
  local p = split(payload)
  if p[1] ~= "HELLO" then
    return nil
  end
  return { kind = "HELLO", version = p[2], guid = p[3], resetEpoch = tonumber(p[4]) or 0 }
end

function Codec.EncodeEvent(event)
  event = event or {}
  return table.concat({
    "EVENT",
    esc(event.id),
    esc(event.name),
    esc(event.target),
    esc(event.goal),
    tostring(event.intervalSeconds or 0),
    tostring(event.minAdminRank or 0),
    tostring(event.revision or 0),
    tostring(event.publishedAt or 0),
    esc(event.publisher),
  }, SEP)
end

function Codec.DecodeEvent(payload)
  local p = split(payload)
  if p[1] ~= "EVENT" then
    return nil
  end
  local Event = Fundraiser.Domain and Fundraiser.Domain.Event
  if not Event then
    return nil
  end
  local event, err = Event.Create({
    id = p[2],
    name = p[3],
    target = p[4],
    goal = p[5],
    intervalSeconds = tonumber(p[6]),
    minAdminRank = tonumber(p[7]),
    revision = tonumber(p[8]),
    publishedAt = tonumber(p[9]),
    publisher = p[10],
  })
  if not event then
    return nil, err
  end
  event.kind = "EVENT"
  return event
end

function Codec.EncodeLedgerEntry(entry, resetEpoch)
  entry = entry or {}
  return table.concat({
    "LEDGER",
    esc(entry.id),
    esc(entry.kind),
    esc(entry.name),
    esc(entry.detail),
    esc(entry.eventId),
    tostring(entry.copper or 0),
    tostring(entry.at or 0),
    tostring(resetEpoch or entry.resetEpoch or 0),
  }, SEP)
end

function Codec.DecodeLedgerEntry(payload)
  local p = split(payload)
  if p[1] ~= "LEDGER" then
    return nil
  end
  local Ledger = Fundraiser.Domain and Fundraiser.Domain.Ledger
  if not Ledger then
    return nil
  end
  local entry = Ledger.CreateEntry({
    id = p[2],
    kind = p[3],
    name = p[4],
    detail = p[5],
    eventId = p[6],
    copper = tonumber(p[7]),
    at = tonumber(p[8]),
  })
  if not entry then
    return nil
  end
  entry.msgKind = "LEDGER"
  entry.resetEpoch = tonumber(p[9]) or 0
  return entry
end

-- scope: all | event | ledger | presence
function Codec.EncodeReset(scope, at, publisher, resetEpoch)
  return table.concat({
    "RESET",
    esc(scope or "all"),
    tostring(at or 0),
    esc(publisher),
    tostring(resetEpoch or 0),
  }, SEP)
end

function Codec.DecodeReset(payload)
  local p = split(payload)
  if p[1] ~= "RESET" then
    return nil
  end
  local scope = p[2] or "all"
  if scope ~= "all" and scope ~= "event" and scope ~= "ledger" and scope ~= "presence" then
    return nil, "bad_scope"
  end
  return {
    kind = "RESET",
    scope = scope,
    at = tonumber(p[3]) or 0,
    publisher = p[4],
    resetEpoch = tonumber(p[5]) or 0,
  }
end

function Codec.EncodeDigest(eventRevision, ledgerCount, ledgerSum, ledgerMaxAt, resetEpoch)
  return table.concat({
    "DIGEST",
    tostring(eventRevision or 0),
    tostring(ledgerCount or 0),
    tostring(ledgerSum or 0),
    tostring(ledgerMaxAt or 0),
    tostring(resetEpoch or 0),
  }, SEP)
end

function Codec.DecodeDigest(payload)
  local p = split(payload)
  if p[1] ~= "DIGEST" then
    return nil
  end
  return {
    kind = "DIGEST",
    eventRevision = tonumber(p[2]) or 0,
    ledgerCount = tonumber(p[3]) or 0,
    ledgerSum = tonumber(p[4]) or 0,
    ledgerMaxAt = tonumber(p[5]) or 0,
    resetEpoch = tonumber(p[6]) or 0,
  }
end

function Codec.Decode(payload)
  local kind = tostring(payload or ""):match("^([^|]+)")
  if kind == "HELLO" then
    return Codec.DecodeHello(payload)
  elseif kind == "EVENT" then
    return Codec.DecodeEvent(payload)
  elseif kind == "LEDGER" then
    return Codec.DecodeLedgerEntry(payload)
  elseif kind == "DIGEST" then
    return Codec.DecodeDigest(payload)
  elseif kind == "RESET" then
    return Codec.DecodeReset(payload)
  end
  return nil, "unknown"
end
