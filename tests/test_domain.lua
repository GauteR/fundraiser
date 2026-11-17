-- Pure Lua tests for Fundraiser domain + application + codec.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Config.lua")
dofile(repo .. "/fundraiser/Locale/enUS.lua")
dofile(repo .. "/fundraiser/Domain/Event.lua")
dofile(repo .. "/fundraiser/Domain/Rank.lua")
dofile(repo .. "/fundraiser/Domain/Roles.lua")
dofile(repo .. "/fundraiser/Domain/Reminder.lua")
dofile(repo .. "/fundraiser/Domain/Ledger.lua")
dofile(repo .. "/fundraiser/Domain/SaleAdvice.lua")
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

local ev = Fundraiser.Domain.Event.Create({
  name = "Tabard",
  target = "Bank Alt",
  intervalSeconds = 3600,
  minAdminRank = 1,
})
assert_true(ev, "create event")

assert_true(Fundraiser.Domain.Roles.IsDonationTarget(ev, "Bank Alt"), "target")
assert_true(Fundraiser.Domain.Roles.CanViewLedger(ev, 0, "GM"), "officer view")
assert_true(not Fundraiser.Domain.Roles.CanViewLedger(ev, 5, "Grunt"), "member no ledger")
assert_true(Fundraiser.Domain.Roles.CanWriteLedger(ev, "Bank Alt"), "target write")
assert_true(not Fundraiser.Domain.Roles.CanWriteLedger(ev, "GM"), "officer no write")

assert_true(Fundraiser.Domain.Roles.CanManageFundraiser(0, ev), "GM manages")
assert_true(Fundraiser.Domain.Roles.CanManageFundraiser(1, ev), "officer manages")
assert_true(not Fundraiser.Domain.Roles.CanManageFundraiser(2, ev), "member no manage")
assert_true(not Fundraiser.Domain.Roles.CanManageFundraiser(nil, ev), "nil rank no manage")
assert_true(Fundraiser.Domain.Roles.CanManageFundraiser(1, nil), "default minAdmin allows rank 1")
assert_true(not Fundraiser.Domain.Roles.CanManageFundraiser(2, nil), "default minAdmin blocks rank 2")

-- Reminder skipped for donation target
local should = Fundraiser.Application.UseCases.ShouldShowReminder({
  getEvent = function()
    return ev
  end,
  getReminderState = function()
    return {}
  end,
  getPlayerName = function()
    return "Bank Alt"
  end,
}, 100)
assert_true(not should, "no reminder on target")

-- Ledger merge union
local a = Fundraiser.Domain.Ledger.CreateEntry({ kind = "mail", name = "A", copper = 100, eventId = ev.id, at = 1, detail = "x" })
local b = Fundraiser.Domain.Ledger.CreateEntry({ kind = "ah", name = "AH", copper = 500, eventId = ev.id, at = 2, detail = "Sword" })
local c = Fundraiser.Domain.Ledger.CreateEntry({
  id = a.id,
  kind = "mail",
  name = "A",
  copper = 150,
  eventId = ev.id,
  at = 3,
  detail = "x",
})
local merged = Fundraiser.Domain.Ledger.Merge({ a }, { b, c })
assert_eq(#merged, 2, "merge union")
assert_eq(Fundraiser.Domain.Ledger.TotalCopper(merged), 650, "merge total")

-- Append only as target
local storedList = {}
local deps = {
  getEvent = function()
    return ev
  end,
  getContributions = function()
    return storedList
  end,
  setContributions = function(list)
    storedList = list
  end,
}
local entry, err = Fundraiser.Application.UseCases.AppendLedgerEntry(deps, {
  kind = "mail",
  name = "Donor",
  copper = 10,
  detail = "hi",
  at = 9,
}, { name = "GM" })
assert_eq(entry, nil, "reject non-target write")
assert_eq(err, "not_target", "not_target")
entry = Fundraiser.Application.UseCases.AppendLedgerEntry(deps, {
  kind = "mail",
  name = "Donor",
  copper = 10,
  detail = "hi",
  at = 9,
}, { name = "Bank Alt" })
assert_true(entry, "target append")

-- Merge remote from target
local remote = {
  Fundraiser.Domain.Ledger.CreateEntry({ kind = "ah", name = "AH", copper = 99, eventId = ev.id, at = 10, detail = "Boot" }),
}
local merged2, changed = Fundraiser.Application.UseCases.MergeRemoteLedger({
  getEvent = function()
    return ev
  end,
  getContributions = function()
    return storedList
  end,
  setContributions = function(list)
    storedList = list
  end,
  getPlayerName = function()
    return "Officer"
  end,
  getPlayerRankIndex = function()
    return 1
  end,
}, remote, "Bank Alt", 5)
assert_true(changed, "merged remote")
assert_true(#merged2 >= 2, "rows after merge")

-- Mesh: non-officer member still stores relayed rows (UI view stays gated separately).
local memberList = {}
local memberRemote = {
  Fundraiser.Domain.Ledger.CreateEntry({ kind = "mail", name = "Donor2", copper = 42, eventId = ev.id, at = 11, detail = "relay" }),
}
local mergedMember, memberChanged = Fundraiser.Application.UseCases.MergeRemoteLedger({
  getEvent = function()
    return ev
  end,
  getContributions = function()
    return memberList
  end,
  setContributions = function(list)
    memberList = list
  end,
  getPlayerName = function()
    return "Grunt"
  end,
  getPlayerRankIndex = function()
    return 5
  end,
}, memberRemote, "Some Relay", 5)
assert_true(memberChanged, "member mesh store")
assert_eq(#mergedMember, 1, "member holds relayed row")
assert_true(not Fundraiser.Domain.Roles.CanViewLedger(ev, 5, "Grunt"), "member still no UI view")

-- Codec ledger
local Codec = Fundraiser.Adapters.Codec
local payload = Codec.EncodeLedgerEntry(entry)
local decoded = Codec.Decode(payload)
assert_eq(decoded.msgKind, "LEDGER", "msgKind")
assert_eq(decoded.copper, 10, "codec copper")

-- Codec RESET + AcceptRemoteReset rank gate
local resetPayload = Codec.EncodeReset("ledger", 123, "Officer One")
local resetMsg = Codec.Decode(resetPayload)
assert_eq(resetMsg.kind, "RESET", "reset kind")
assert_eq(resetMsg.scope, "ledger", "reset scope")
assert_eq(resetMsg.at, 123, "reset at")
local applied = false
local resetOk, resetErr = Fundraiser.Application.UseCases.AcceptRemoteReset({
  applyReset = function(scope)
    applied = scope == "ledger"
    return true
  end,
}, "ledger", 1)
assert_true(resetOk, "officer reset accepted")
assert_true(applied, "apply called")
Fundraiser.Config.DEFAULT_MIN_ADMIN_RANK = 1
resetOk, resetErr = Fundraiser.Application.UseCases.AcceptRemoteReset({
  applyReset = function()
    return true
  end,
}, "all", 5)
assert_eq(resetOk, nil, "member reset rejected")
assert_eq(resetErr, "not_admin", "member reset err")
resetOk, resetErr = Fundraiser.Application.UseCases.AcceptRemoteReset({
  applyReset = function()
    return true
  end,
}, "nope", 0)
assert_eq(resetOk, nil, "bad scope rejected")
assert_eq(resetErr, "bad_scope", "bad scope err")

-- Forever full names (First Last)
assert_true(Fundraiser.Domain.Roles.IsFullCharacterName("Jane Doe"), "full name ok")
assert_true(not Fundraiser.Domain.Roles.IsFullCharacterName("Jane"), "first only rejected")
assert_true(Fundraiser.Domain.Roles.NamesEqual("Jane Doe", "jane  doe"), "collapse spaces")
assert_true(Fundraiser.Domain.Roles.NamesEqual("Jane Doe-Realm", "Jane Doe"), "strip realm")
local badTarget = Fundraiser.Domain.Event.Create({
  name = "X",
  target = "OnlyFirst",
  intervalSeconds = 3600,
  minAdminRank = 0,
})
assert_eq(badTarget, nil, "reject single-token target")

-- SaleAdvice vendor vs AH
local advice = Fundraiser.Domain.SaleAdvice.Recommend(100, 100, 1, 0.05)
assert_eq(advice, "vendor", "vendor wins vs cut AH")
advice = Fundraiser.Domain.SaleAdvice.Recommend(10, 100, 1, 0.05)
assert_eq(advice, "ah", "ah wins")
advice = Fundraiser.Domain.SaleAdvice.Recommend(nil, nil, 1, 0.05)
assert_eq(advice, "manual", "manual when no prices")

if failed > 0 then
  io.stderr:write(failed .. " failure(s)\n")
  os.exit(1)
end
print("test_domain: ok")
