-- Pure Lua tests for the guild-shared ignore layer and its IGNORE wire message.
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Config.lua")
dofile(repo .. "/fundraiser/Domain/SharedIgnore.lua")
dofile(repo .. "/fundraiser/Adapters/Codec.lua")

local SI = Fundraiser.Domain.SharedIgnore
local Codec = Fundraiser.Adapters.Codec
local failed = 0

local function assert_eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s (%s ~= %s)\n", msg or "assert_eq", tostring(a), tostring(b)))
  end
end

-- Scenario: normalising anything yields an empty usable table
do
  assert_eq(next(SI.Normalize(nil)), nil, "normalize nil: empty")
  assert_eq(next(SI.Normalize("junk")), nil, "normalize string: empty")
end

-- Scenario: normalising drops invalid entries and keeps valid ones
do
  local s = SI.Normalize({
    [12] = { name = "Linen Cloth", at = 100 },
    [13] = { name = "Gone", at = 50, removed = true },
    [0] = { name = "Bad id", at = 1 },
    ["x"] = { name = "Bad key", at = 1 },
    [14] = { name = "No time" },
    [15] = "not a table",
  })
  assert_eq(s[12].name, "Linen Cloth", "normalize: keeps valid")
  assert_eq(s[13].removed, true, "normalize: keeps tombstone")
  assert_eq(s[0], nil, "normalize: drops id 0")
  assert_eq(s[14], nil, "normalize: drops missing time")
  assert_eq(s[15], nil, "normalize: drops non-table")
end

-- Scenario: adding an item makes it active
do
  local s = SI.Normalize(nil)
  local ok = SI.Apply(s, "add", 2589, "Linen Cloth", 100)
  assert_eq(ok, true, "add: applied")
  assert_eq(SI.Active(s)[2589], true, "add: active")
end

-- Scenario: removing records a tombstone and deactivates the item
do
  local s = SI.Normalize(nil)
  SI.Apply(s, "add", 2589, "Linen Cloth", 100)
  local ok = SI.Apply(s, "remove", 2589, "Linen Cloth", 200)
  assert_eq(ok, true, "remove: applied")
  assert_eq(SI.Active(s)[2589], nil, "remove: not active")
  assert_eq(s[2589].removed, true, "remove: tombstone kept")
end

-- Scenario: a stale add cannot resurrect a removed item
do
  local s = SI.Normalize(nil)
  SI.Apply(s, "add", 5, "Thing", 100)
  SI.Apply(s, "remove", 5, "Thing", 200)
  local ok, reason = SI.Apply(s, "add", 5, "Thing", 150)
  assert_eq(ok, false, "stale add: rejected")
  assert_eq(reason, "stale", "stale add: reason")
  assert_eq(SI.Active(s)[5], nil, "stale add: still removed")
end

-- Scenario: a newer add after a remove wins
do
  local s = SI.Normalize(nil)
  SI.Apply(s, "add", 5, "Thing", 100)
  SI.Apply(s, "remove", 5, "Thing", 200)
  assert_eq(SI.Apply(s, "add", 5, "Thing", 300), true, "newer add: applied")
  assert_eq(SI.Active(s)[5], true, "newer add: active again")
end

-- Scenario: same timestamp, remove wins so peers converge
do
  local a, b = SI.Normalize(nil), SI.Normalize(nil)
  SI.Apply(a, "add", 5, "Thing", 100)
  SI.Apply(a, "remove", 5, "Thing", 100)
  SI.Apply(b, "remove", 5, "Thing", 100)
  SI.Apply(b, "add", 5, "Thing", 100)
  assert_eq(SI.Active(a)[5], nil, "tie: a removed")
  assert_eq(SI.Active(b)[5], nil, "tie: b removed")
end

-- Scenario: malformed input is rejected and changes nothing
do
  local s = SI.Normalize(nil)
  assert_eq(SI.Apply(s, "nuke", 5, "x", 1), false, "bad op")
  assert_eq(SI.Apply(s, "add", 0, "x", 1), false, "bad id zero")
  assert_eq(SI.Apply(s, "add", 1.5, "x", 1), false, "bad id fraction")
  assert_eq(SI.Apply(s, "add", 5, "x", -1), false, "bad time")
  assert_eq(SI.Apply(s, "add", 5, "x", nil), false, "missing time")
  assert_eq(next(s), nil, "bad input: nothing stored")
end

-- Scenario: long names are truncated
do
  local s = SI.Normalize(nil)
  SI.Apply(s, "add", 5, string.rep("a", 500), 1)
  assert_eq(#s[5].name <= SI.MAX_NAME_LENGTH, true, "name capped")
end

-- Scenario: the entry cap bounds memory but still updates known items
do
  local s = SI.Normalize(nil)
  for id = 1, SI.MAX_ENTRIES do
    SI.Apply(s, "add", id, "n", 1)
  end
  local ok, reason = SI.Apply(s, "add", SI.MAX_ENTRIES + 1, "n", 1)
  assert_eq(ok, false, "cap: new item rejected")
  assert_eq(reason, "full", "cap: reason")
  assert_eq(SI.Apply(s, "remove", 1, "n", 2), true, "cap: known item still updates")
end

-- Scenario: snapshot lists every entry (tombstones too) ordered by item id
do
  local s = SI.Normalize(nil)
  SI.Apply(s, "add", 30, "C", 1)
  SI.Apply(s, "add", 10, "A", 2)
  SI.Apply(s, "remove", 20, "B", 3)
  local snap = SI.Snapshot(s)
  assert_eq(#snap, 3, "snapshot: size")
  assert_eq(snap[1].itemId, 10, "snapshot: order 1")
  assert_eq(snap[2].op, "remove", "snapshot: tombstone op")
  assert_eq(snap[3].itemId, 30, "snapshot: order 3")
  assert_eq(snap[1].at, 2, "snapshot: time")
end

-- Scenario: IGNORE message round trip, including separators in the name
do
  local payload = Codec.EncodeIgnore("add", 2589, "Odd|Name\\x", 1700000000)
  local msg = Codec.Decode(payload)
  assert_eq(msg.kind, "IGNORE", "codec: kind")
  assert_eq(msg.op, "add", "codec: op")
  assert_eq(msg.itemId, 2589, "codec: item id")
  assert_eq(msg.name, "Odd|Name\\x","codec: name round trip")
  assert_eq(msg.at, 1700000000, "codec: time")
  assert_eq(#payload <= 255, true, "codec: fits an addon message")
end

-- Scenario: malformed IGNORE messages do not decode
do
  assert_eq(Codec.Decode("IGNORE|nuke|5|x|1"), nil, "codec: bad op")
  assert_eq(Codec.Decode("IGNORE|add|zero|x|1"), nil, "codec: bad id")
  assert_eq(Codec.Decode("IGNORE|add|5|x|"), nil, "codec: missing time")
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("ok test_shared_ignore")
