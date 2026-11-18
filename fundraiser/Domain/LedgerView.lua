-- Domain: pure view model for the Ledger window (no frames, no client API).
-- Active event rows newest first, one summary per archived event, top contributor, MOTD text.
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local LedgerView = {}
Fundraiser.Domain.LedgerView = LedgerView

-- Guild message of the day is limited to 128 characters.
LedgerView.MOTD_MAX = 128

local COPPER_PER_GOLD = 10000

local function num(v)
  return tonumber(v) or 0
end

local function Ledger()
  return Fundraiser.Domain.Ledger
end

local function Roles()
  return Fundraiser.Domain.Roles
end

-- Copy of rows, newest first (equal time: id ascending).
function LedgerView.ActiveRows(rows)
  local out = {}
  if type(rows) ~= "table" then
    return out
  end
  for _, r in ipairs(rows) do
    out[#out + 1] = r
  end
  table.sort(out, function(a, b)
    local aa, ba = num(a.at), num(b.at)
    if aa ~= ba then
      return aa > ba
    end
    return tostring(a.id) < tostring(b.id)
  end)
  return out
end

-- One summary per archive, most recently finished first (equal time: later stored first).
function LedgerView.ArchiveSummaries(archives)
  local out = {}
  if type(archives) ~= "table" then
    return out
  end
  for i, archive in ipairs(archives) do
    if type(archive) == "table" then
      local event = type(archive.event) == "table" and archive.event or {}
      local rows = type(archive.contributions) == "table" and archive.contributions or {}
      if event.id then
        rows = Ledger().FilterByEvent(rows, event.id)
      end
      out[#out + 1] = {
        eventId = event.id,
        name = event.name or "",
        count = #rows,
        total = Ledger().TotalCopper(rows),
        archivedAt = num(archive.archivedAt),
        order = i,
      }
    end
  end
  table.sort(out, function(a, b)
    if a.archivedAt ~= b.archivedAt then
      return a.archivedAt > b.archivedAt
    end
    return a.order > b.order
  end)
  return out
end

-- Sum copper per character (normalised name), highest first (equal sums: name ascending).
function LedgerView.TopContributors(rows)
  local byKey, list = {}, {}
  if type(rows) ~= "table" then
    return list
  end
  local R = Roles()
  for _, r in ipairs(rows) do
    local key = R.NormalizeName(r.name)
    if key then
      local entry = byKey[key]
      if not entry then
        entry = { key = key, name = R.DisplayName(r.name), copper = 0, count = 0 }
        byKey[key] = entry
        list[#list + 1] = entry
      end
      entry.copper = entry.copper + num(r.copper)
      entry.count = entry.count + 1
    end
  end
  table.sort(list, function(a, b)
    if a.copper ~= b.copper then
      return a.copper > b.copper
    end
    return a.key < b.key
  end)
  return list
end

-- Window model: active event section + archived summaries.
function LedgerView.Build(activeEvent, rows, archives)
  local active = { rows = {}, total = 0, count = 0 }
  if type(activeEvent) == "table" and activeEvent.id then
    local filtered = Ledger().FilterByEvent(rows, activeEvent.id)
    active.rows = LedgerView.ActiveRows(filtered)
    active.total = Ledger().TotalCopper(filtered)
    active.count = #filtered
  end
  return {
    hasEvent = type(activeEvent) == "table",
    event = activeEvent,
    active = active,
    archived = LedgerView.ArchiveSummaries(archives),
  }
end

-- Cut s to at most maxBytes without splitting a UTF-8 character.
local function cutUtf8(s, maxBytes)
  if #s <= maxBytes then
    return s
  end
  local out, used = {}, 0
  for ch in s:gmatch("[\1-\127\194-\244][\128-\191]*") do
    if used + #ch > maxBytes then
      break
    end
    out[#out + 1] = ch
    used = used + #ch
  end
  return table.concat(out)
end

local function buildMotd(name, total, goalCopper, top)
  local gold = math.floor(num(total) / COPPER_PER_GOLD)
  local text = "Fundraiser " .. name .. ": " .. gold .. "g"
  if goalCopper > 0 then
    local percent = math.floor(num(total) / goalCopper * 100)
    text = text .. "/" .. math.floor(goalCopper / COPPER_PER_GOLD) .. "g (" .. percent .. "%)"
  end
  text = text .. "."
  if top and top.name and top.name ~= "" then
    text = text .. " Top contributor: " .. top.name .. "!"
  end
  return text
end

-- MOTD: "Fundraiser <name>: 1200g/5000g (24%). Top contributor: <charname>!"
-- Without goal the "/5000g (24%)" part is dropped; without a top contributor the last sentence is.
-- Over MOTD_MAX the event name is shortened first (with "..."), never the contributor.
function LedgerView.MotdText(event, total, top)
  event = type(event) == "table" and event or {}
  local name = event.name or ""
  local goalCopper = math.floor(num(event.goalCopper))
  local text = buildMotd(name, total, goalCopper, top)
  if #text <= LedgerView.MOTD_MAX then
    return text
  end
  local over = #text - LedgerView.MOTD_MAX
  local keep = math.max(0, #name - over - 3)
  text = buildMotd(cutUtf8(name, keep) .. "...", total, goalCopper, top)
  return text
end
