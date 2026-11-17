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
  target = "Bankalt",
  intervalSeconds = 3600,
  minAdminRank = 1,
})
assert_true(ev, "create event")

assert_true(Fundraiser.Domain.Roles.IsDonationTarget(ev, "Bankalt"), "target")
assert_true(Fundraiser.Domain.Roles.CanViewLedger(ev, 0, "GM"), "officer view")
assert_true(not Fundraiser.Domain.Roles.CanViewLedger(ev, 5, "Grunt"), "member no ledger")
assert_true(Fundraiser.Domain.Roles.CanWriteLedger(ev, "Bankalt"), "target write")
assert_true(not Fundraiser.Domain.Roles.CanWriteLedger(ev, "GM"), "officer no write")

-- Reminder skipped for donation target
local should = Fundraiser.Application.UseCases.ShouldShowReminder({
  getEvent = function()
    return ev
  end,
  getReminderState = function()
    return {}
  end,
  getPlayerName = function()
    return "Bankalt"
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
}, { name = "Bankalt" })
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
}, remote, "Bankalt", 5)
assert_true(changed, "merged remote")
assert_true(#merged2 >= 2, "rows after merge")

-- Codec ledger
local Codec = Fundraiser.Adapters.Codec
local payload = Codec.EncodeLedgerEntry(entry)
local decoded = Codec.Decode(payload)
assert_eq(decoded.msgKind, "LEDGER", "msgKind")
assert_eq(decoded.copper, 10, "codec copper")

if failed > 0 then
  io.stderr:write(failed .. " failure(s)\n")
  os.exit(1)
end
print("test_domain: ok")
