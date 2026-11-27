-- Pure Lua tests for the guild-shared ignore layer and its IGNORE wire message.
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Config.lua")
dofile(repo .. "/fundraiser/Domain/SharedIgnore.lua")
dofile(repo .. "/fundraiser/Domain/TargetPrefs.lua")
dofile(repo .. "/fundraiser/Application/UseCases.lua")
dofile(repo .. "/fundraiser/Adapters/Codec.lua")

local SI = Fundraiser.Domain.SharedIgnore
local Codec = Fundraiser.Adapters.Codec
local TP = Fundraiser.Domain.TargetPrefs
local UC = Fundraiser.Application.UseCases
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

-- Scenario: the ignored set unions personal and shared entries only when the sync flag is on
do
  local prefs = TP.Normalize(nil)
  TP.Ignore(prefs, 1, "Mine")
  local shared = SI.Normalize(nil)
  SI.Apply(shared, "add", 2, "Theirs", 10)
  SI.Apply(shared, "add", 3, "Removed", 10)
  SI.Apply(shared, "remove", 3, "Removed", 20)
  local on = TP.IgnoredSet(prefs, { TARGET_PREFS = true, TARGET_IGNORE_SYNC = true }, shared)
  assert_eq(on[1], true, "union: personal")
  assert_eq(on[2], true, "union: shared")
  assert_eq(on[3], nil, "union: tombstone not ignored")
  local off = TP.IgnoredSet(prefs, { TARGET_PREFS = true, TARGET_IGNORE_SYNC = false }, shared)
  assert_eq(off[1], true, "sync off: personal kept")
  assert_eq(off[2], nil, "sync off: shared ignored")
  local noPrefs = TP.IgnoredSet(prefs, { TARGET_PREFS = false, TARGET_IGNORE_SYNC = true }, shared)
  assert_eq(next(noPrefs), nil, "prefs off: nothing ignored")
end

-- Scenario: snapshot is split into batches so it can be paced
do
  local snap = {}
  for i = 1, 25 do
    snap[i] = { itemId = i }
  end
  local batches = SI.Batches(snap, 10)
  assert_eq(#batches, 3, "batches: count")
  assert_eq(#batches[3], 5, "batches: remainder")
  assert_eq(#SI.Batches({}, 10), 0, "batches: empty")
end

-- Scenario: snapshot replies are throttled
do
  assert_eq(SI.SnapshotDue(nil, 1000, 120), true, "throttle: first send")
  assert_eq(SI.SnapshotDue(950, 1000, 120), false, "throttle: too soon")
  assert_eq(SI.SnapshotDue(800, 1000, 120), true, "throttle: after cooldown")
end

local function ignoreDeps(enabled)
  local state = { shared = SI.Normalize(nil), saved = 0, sent = {} }
  state.deps = {
    enabled = function()
      return enabled
    end,
    getShared = function()
      return state.shared
    end,
    setShared = function(s)
      state.shared = s
      state.saved = state.saved + 1
    end,
    now = function()
      return 500
    end,
    broadcast = function(op, id, name, at)
      state.sent[#state.sent + 1] = { op = op, id = id, name = name, at = at }
    end,
  }
  return state
end

-- Scenario: a remote IGNORE is merged and saved when sync is on
do
  local st = ignoreDeps(true)
  local ok = UC.AcceptRemoteIgnore(st.deps, { op = "add", itemId = 9, name = "Junk", at = 100 })
  assert_eq(ok, true, "remote: applied")
  assert_eq(SI.Active(st.shared)[9], true, "remote: active")
  assert_eq(st.saved, 1, "remote: saved")
  local again, reason = UC.AcceptRemoteIgnore(st.deps, { op = "add", itemId = 9, name = "Junk", at = 100 })
  assert_eq(again, false, "remote: duplicate not applied")
  assert_eq(reason, "stale", "remote: duplicate reason")
  assert_eq(st.saved, 1, "remote: duplicate not saved")
  assert_eq(#st.sent, 0, "remote: never rebroadcast")
end

-- Scenario: a remote IGNORE is dropped when sync is off
do
  local st = ignoreDeps(false)
  local ok, reason = UC.AcceptRemoteIgnore(st.deps, { op = "add", itemId = 9, name = "Junk", at = 100 })
  assert_eq(ok, false, "remote off: not applied")
  assert_eq(reason, "disabled", "remote off: reason")
  assert_eq(next(st.shared), nil, "remote off: nothing stored")
end

-- Scenario: publishing stores locally and broadcasts only when sync is on
do
  local st = ignoreDeps(true)
  assert_eq(UC.PublishIgnore(st.deps, "add", 4, "Rag"), true, "publish: ok")
  assert_eq(SI.Active(st.shared)[4], true, "publish: stored")
  assert_eq(#st.sent, 1, "publish: broadcast once")
  assert_eq(st.sent[1].at, 500, "publish: stamped with now")
  UC.PublishIgnore(st.deps, "remove", 4, "Rag")
  assert_eq(SI.Active(st.shared)[4], nil, "publish: remove stored")
  local off = ignoreDeps(false)
  local ok, reason = UC.PublishIgnore(off.deps, "add", 4, "Rag")
  assert_eq(ok, false, "publish off: not ok")
  assert_eq(reason, "disabled", "publish off: reason")
  assert_eq(#off.sent, 0, "publish off: no broadcast")
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("ok test_shared_ignore")
