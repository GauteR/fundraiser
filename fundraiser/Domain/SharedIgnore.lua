-- Domain: guild-shared ignore layer of the target page (kept apart from the personal ignore list).
-- shared = { [itemId] = { name, at, removed } }. Merge is last-write-wins per item by `at`;
-- unignore is a tombstone (removed = true) so it propagates and stale peers cannot re-add it.
-- Pure Lua: no WoW API. The Store keeps the table; the sync adapter feeds it messages.
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local SharedIgnore = {}
Fundraiser.Domain.SharedIgnore = SharedIgnore

-- Bounds memory and message size (an IGNORE message must fit in 255 bytes).
SharedIgnore.MAX_ENTRIES = 500
SharedIgnore.MAX_NAME_LENGTH = 80

local function validItemId(id)
  id = tonumber(id)
  if id and id >= 1 and id == math.floor(id) then
    return id
  end
  return nil
end

local function validTime(at)
  at = tonumber(at)
  if at and at >= 0 and at == at and at ~= math.huge then
    return math.floor(at)
  end
  return nil
end

local function cleanName(name)
  return tostring(name or ""):sub(1, SharedIgnore.MAX_NAME_LENGTH)
end

local function count(shared)
  local n = 0
  for _ in pairs(shared) do
    n = n + 1
  end
  return n
end

-- Any saved value in, a clean { [itemId] = { name, at, removed } } out.
function SharedIgnore.Normalize(raw)
  local shared = {}
  if type(raw) ~= "table" then
    return shared
  end
  for id, entry in pairs(raw) do
    local itemId = type(id) == "number" and validItemId(id) or nil
    local at = type(entry) == "table" and validTime(entry.at) or nil
    if itemId and at and count(shared) < SharedIgnore.MAX_ENTRIES then
      shared[itemId] = { name = cleanName(entry.name), at = at, removed = entry.removed == true }
    end
  end
  return shared
end

-- Apply one add/remove. Returns true, or false plus a reason:
-- bad_op | bad_id | bad_time | stale | full. A tie on `at` goes to remove so peers converge.
function SharedIgnore.Apply(shared, op, itemId, name, at)
  if op ~= "add" and op ~= "remove" then
    return false, "bad_op"
  end
  local id = validItemId(itemId)
  if not id then
    return false, "bad_id"
  end
  local time = validTime(at)
  if not time then
    return false, "bad_time"
  end
  local existing = shared[id]
  if existing then
    local newer = time > existing.at
    local tieRemove = time == existing.at and op == "remove" and not existing.removed
    if not (newer or tieRemove) then
      return false, "stale"
    end
  elseif count(shared) >= SharedIgnore.MAX_ENTRIES then
    return false, "full"
  end
  shared[id] = { name = cleanName(name), at = time, removed = op == "remove" }
  return true
end

-- Set of currently shared-ignored item ids (tombstones excluded).
function SharedIgnore.Active(shared)
  local set = {}
  for id, entry in pairs(shared or {}) do
    if not entry.removed then
      set[id] = true
    end
  end
  return set
end

-- Split a snapshot into batches of `size` so the sender can pace addon messages.
function SharedIgnore.Batches(snapshot, size)
  size = math.max(1, math.floor(tonumber(size) or 1))
  local batches = {}
  for i = 1, #snapshot do
    local b = math.ceil(i / size)
    batches[b] = batches[b] or {}
    batches[b][#batches[b] + 1] = snapshot[i]
  end
  return batches
end

-- True when a snapshot reply may go out (nil lastAt = never sent). Bounds mesh chatter on HELLO.
function SharedIgnore.SnapshotDue(lastAt, now, cooldown)
  return lastAt == nil or now - lastAt >= cooldown
end

-- Every entry, tombstones included, ordered by item id: { { itemId, op, name, at } }.
function SharedIgnore.Snapshot(shared)
  local list = {}
  for id, entry in pairs(shared or {}) do
    list[#list + 1] = { itemId = id, op = entry.removed and "remove" or "add", name = entry.name, at = entry.at }
  end
  table.sort(list, function(a, b)
    return a.itemId < b.itemId
  end)
  return list
end
