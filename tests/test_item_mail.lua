-- Pure Lua tests for recording incoming player mail (money and item attachments) in the ledger.
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Config.lua")
dofile(repo .. "/fundraiser/Locale/enUS.lua")
dofile(repo .. "/fundraiser/Domain/Event.lua")
dofile(repo .. "/fundraiser/Domain/Rank.lua")
dofile(repo .. "/fundraiser/Domain/Roles.lua")
dofile(repo .. "/fundraiser/Domain/Ledger.lua")
dofile(repo .. "/fundraiser/Domain/ItemLots.lua")
dofile(repo .. "/fundraiser/Application/UseCases.lua")

local UC = Fundraiser.Application.UseCases
local IL = Fundraiser.Domain.ItemLots
local failed = 0

local function assert_eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s (%s ~= %s)\n", msg or "assert_eq", tostring(a), tostring(b)))
  end
end

local event = { id = "ev1", name = "Guinea pigs", target = "Bank Alt", goalCopper = 1000, revision = 1 }

local function setup()
  local state = { rows = {}, lots = {}, broadcasts = 0 }
  state.deps = {
    getEvent = function()
      return event
    end,
    getContributions = function()
      return state.rows
    end,
    setContributions = function(list)
      state.rows = list
    end,
    getLots = function()
      return state.lots
    end,
    setLots = function(list)
      state.lots = list
    end,
    broadcastLedgerEntry = function()
      state.broadcasts = state.broadcasts + 1
    end,
  }
  return state
end

local actor = { name = "Bank Alt" }

local function mail(extra)
  local m = {
    id = "mail:Donor One:Hello",
    sender = "Donor One",
    subject = "Hello",
    money = 0,
    items = {},
    at = 100,
  }
  for k, v in pairs(extra or {}) do
    m[k] = v
  end
  return m
end

-- Scenario: item attachments become one row listing the items, worth nothing until sold
do
  local s = setup()
  local entry = UC.RecordItemMail(s.deps, mail({ items = { { name = "Linen Cloth", count = 20 } } }), actor)
  assert_eq(#s.rows, 1, "items: one ledger row")
  assert_eq(entry.name, "Donor One", "items: row carries the donor")
  assert_eq(entry.detail, "Linen Cloth x20", "items: detail lists the items")
  assert_eq(entry.copper, 0, "items: nothing earned yet")
  assert_eq(#s.lots, 1, "items: one lot waits to be sold")
  assert_eq(s.lots[1].id, entry.id, "items: the lot belongs to the row")
  assert_eq(s.broadcasts, 1, "items: row is shared with the guild")
end

-- Scenario: money and items in one mail: the row keeps the money
do
  local s = setup()
  local entry = UC.RecordItemMail(s.deps, mail({ money = 5000, items = { { name = "Wool Cloth", count = 5 } } }), actor)
  assert_eq(entry.copper, 5000, "money+items: money is counted")
  assert_eq(entry.detail, "Wool Cloth x5", "money+items: items in the detail")
end

-- Scenario: money only keeps the old row (subject as detail, no lots)
do
  local s = setup()
  local entry = UC.RecordItemMail(s.deps, mail({ money = 300 }), actor)
  assert_eq(entry.detail, "Hello", "money only: subject as detail")
  assert_eq(entry.copper, 300, "money only: copper")
  assert_eq(#s.lots, 0, "money only: no lots")
end

-- Scenario: seeing the same mail again does not add the items a second time
do
  local s = setup()
  local m = mail({ items = { { name = "Linen Cloth", count = 20 } } })
  local first = UC.RecordItemMail(s.deps, m, actor)
  local again, reason = UC.RecordItemMail(s.deps, m, actor)
  assert_eq(again, nil, "rescan: nothing new")
  assert_eq(reason, "known", "rescan: reported as known")
  assert_eq(#s.rows, 1, "rescan: still one row")
  assert_eq(s.lots[1].qty, 20, "rescan: quantity unchanged")
  assert_eq(s.broadcasts, 1, "rescan: not broadcast again")
  assert_eq(first.id, s.rows[1].id, "rescan: same row")
end

-- Scenario: items returned by the auction house are not donations
do
  local s = setup()
  local entry = UC.RecordItemMail(
    s.deps,
    mail({ sender = "Auction House", money = 700, fromAuctionHouse = true, items = { { name = "Linen Cloth", count = 20 } } }),
    actor
  )
  assert_eq(#s.lots, 0, "auction house: returned items do not become lots")
  assert_eq(entry.copper, 700, "auction house: money is recorded as before")
end

-- Scenario: only the donation target writes the ledger
do
  local s = setup()
  local entry, reason = UC.RecordItemMail(s.deps, mail({ items = { { name = "Linen Cloth", count = 1 } } }), { name = "Someone Else" })
  assert_eq(entry, nil, "not target: nothing written")
  assert_eq(reason, "not_target", "not target: reason")
  assert_eq(#s.lots, 0, "not target: no lots")
end

-- Scenario: the mail id keeps the old format without items and tells item mails apart
do
  assert_eq(UC.MailId("Donor One", "Hello", 300, {}), "mail:Donor One:Hello:300:0", "id: money mail keeps the old format")
  local a = UC.MailId("Donor One", "Hello", 0, { { name = "Linen Cloth", count = 20 } })
  local b = UC.MailId("Donor One", "Hello", 0, { { name = "Wool Cloth", count = 5 } })
  assert_eq(a == b, false, "id: different attachments, different rows")
  assert_eq(a, "mail:Donor One:Hello:0:1:Linen Cloth x20", "id: item signature appended")
end

-- Scenario: two different item mails from one donor stay separate rows
do
  local s = setup()
  local m1 = mail({ items = { { name = "Linen Cloth", count = 20 } } })
  local m2 = mail({ items = { { name = "Wool Cloth", count = 5 } } })
  m1.id = UC.MailId(m1.sender, m1.subject, m1.money, m1.items)
  m2.id = UC.MailId(m2.sender, m2.subject, m2.money, m2.items)
  UC.RecordItemMail(s.deps, m1, actor)
  UC.RecordItemMail(s.deps, m2, actor)
  assert_eq(#s.rows, 2, "two mails: two rows")
  assert_eq(IL.RowDetail(s.lots, s.rows[2].id), "Wool Cloth x5", "two mails: each row lists its own items")
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("item mail tests passed")
