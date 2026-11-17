-- Pure Lua tests for Fundraiser domain + application + codec.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Config.lua")
dofile(repo .. "/fundraiser/Locale/enUS.lua")
dofile(repo .. "/fundraiser/Domain/Event.lua")
dofile(repo .. "/fundraiser/Domain/Rank.lua")
dofile(repo .. "/fundraiser/Domain/Reminder.lua")
dofile(repo .. "/fundraiser/Domain/Ledger.lua")
dofile(repo .. "/fundraiser/Application/UseCases.lua")
dofile(repo .. "/fundraiser/Adapters/Codec.lua")

local failed = 0

local function assert_eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s (%s ~= %s)\n", msg or "assert_eq", tostring(a), tostring(b)))
  end
end

local function assert_true(v, msg)
  if not v then
    failed = failed + 1
    io.stderr:write("FAIL: " .. (msg or "assert_true") .. "\n")
  end
end

-- Event
local ev, err = Fundraiser.Domain.Event.Create({
  name = "Tabard",
  target = "Bankalt",
  intervalSeconds = 3600,
  minAdminRank = 1,
})
assert_true(ev, "create event")
assert_eq(err, nil, "no err")
assert_eq(ev.name, "Tabard", "name")
local bad = Fundraiser.Domain.Event.Create({ name = "", target = "x", intervalSeconds = 3600, minAdminRank = 0 })
assert_eq(bad, nil, "reject empty name")

-- Rank
assert_true(Fundraiser.Domain.Rank.IsAdmin(0, 1), "GM admin")
assert_true(Fundraiser.Domain.Rank.IsAdmin(1, 1), "officer admin")
assert_true(not Fundraiser.Domain.Rank.IsAdmin(2, 1), "member not admin")

-- Reminder
local event = ev
assert_true(Fundraiser.Domain.Reminder.ShouldRemind(100, event, {}), "show initially")
local st = Fundraiser.Domain.Reminder.MarkDismissed({}, 100, event.id)
assert_true(not Fundraiser.Domain.Reminder.ShouldRemind(200, event, st), "suppressed after dismiss")
assert_true(Fundraiser.Domain.Reminder.ShouldRemind(100 + event.intervalSeconds, event, st), "after interval")

-- Ledger
local list = {}
list = select(1, Fundraiser.Domain.Ledger.Upsert(list, { guid = "g1", name = "A", eventId = event.id, copper = 100, at = 1 }))
list = select(1, Fundraiser.Domain.Ledger.Upsert(list, { guid = "g1", name = "A", eventId = event.id, copper = 250, at = 2 }))
assert_eq(#list, 1, "upsert one")
assert_eq(Fundraiser.Domain.Ledger.TotalCopper(list), 250, "total")

-- UseCases AcceptRemoteEvent rank gate
local stored = nil
local deps = {
  getEvent = function()
    return stored
  end,
  setEvent = function(e)
    stored = e
  end,
}
local okEv, okErr = Fundraiser.Application.UseCases.AcceptRemoteEvent(deps, event, 5)
assert_eq(okEv, nil, "reject low rank")
assert_eq(okErr, "not_admin", "not_admin")
okEv = Fundraiser.Application.UseCases.AcceptRemoteEvent(deps, event, 0)
assert_true(okEv, "accept GM")
assert_true(stored ~= nil, "stored")

-- PublishEvent
stored = nil
local published, perr = Fundraiser.Application.UseCases.PublishEvent(deps, {
  name = "Raid repairs",
  target = "Officerbank",
  intervalSeconds = 7200,
  minAdminRank = 1,
}, { rankIndex = 0, name = "GM", now = 50 })
assert_true(published, "publish " .. tostring(perr))
assert_eq(published.revision, 1, "rev1")

-- Codec roundtrip
local Codec = Fundraiser.Adapters.Codec
local payload = Codec.EncodeEvent(published)
local decoded = Codec.DecodeEvent(payload)
assert_true(decoded, "decode event")
assert_eq(decoded.name, published.name, "codec name")
assert_eq(decoded.target, published.target, "codec target")

local hello = Codec.Decode(Codec.EncodeHello("0.1.0", "guid-1"))
assert_eq(hello.kind, "HELLO", "hello kind")
local donate = Codec.Decode(Codec.EncodeDonate({ guid = "g", name = "N", eventId = "e", copper = 5, at = 9 }))
assert_eq(donate.copper, 5, "donate copper")

-- Missing installs
local missing = Fundraiser.Application.UseCases.ListMissingInstalls({
  getRoster = function()
    return {
      { name = "OnlineNoAddon", guid = "1", online = true },
      { name = "HasAddon", guid = "2", online = true },
      { name = "Offline", guid = "3", online = false },
    }
  end,
  getPresence = function()
    return { ["2"] = { lastHello = 1000 }, HasAddon = { lastHello = 1000 } }
  end,
  presenceStale = 600,
}, 1000)
assert_eq(#missing, 1, "one missing")
assert_eq(missing[1].name, "OnlineNoAddon", "missing name")

if failed > 0 then
  io.stderr:write(failed .. " failure(s)\n")
  os.exit(1)
end
print("test_domain: ok")
