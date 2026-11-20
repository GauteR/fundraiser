-- Pure Lua tests for recording a sale: proceeds go on the donated item's ledger row.
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
local Ledger = Fundraiser.Domain.Ledger
local failed = 0

local function assert_eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s (%s ~= %s)\n", msg or "assert_eq", tostring(a), tostring(b)))
  end
end

local event = { id = "ev1", name = "Guinea pigs", target = "Bank Alt", goalCopper = 1000, revision = 1 }
local actor = { name = "Bank Alt" }

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

local function donate(s, sender, item, count, at)
  local m = { sender = sender, subject = "Hi", money = 0, items = { { name = item, count = count } }, at = at or 100 }
  m.id = UC.MailId(m.sender, m.subject, m.money, m.items)
  return UC.RecordItemMail(s.deps, m, actor)
end

-- Scenario: the net proceeds after the auction house cut
do
  assert_eq(IL.AfterCut(1000, 0.05), 950, "cut: 5% off")
  assert_eq(IL.AfterCut(99, 0.05), 94, "cut: rounded to the nearest copper")
  assert_eq(IL.AfterCut(1000, nil), 1000, "cut: none given")
end

-- Scenario: a trailing count in the sale text is split from the item name
do
  local name, qty = IL.ParseCount("Linen Cloth x20")
  assert_eq(name, "Linen Cloth", "count: name")
  assert_eq(qty, 20, "count: x20")
  name, qty = IL.ParseCount("Linen Cloth (20)")
  assert_eq(name, "Linen Cloth", "count: name in brackets form")
  assert_eq(qty, 20, "count: (20)")
  name, qty = IL.ParseCount("Linen Cloth")
  assert_eq(name, "Linen Cloth", "count: plain name kept")
  assert_eq(qty, nil, "count: none")
end

-- Scenario: a sale adds its proceeds to the donated item's row, which stays one row
do
  local s = setup()
  local row = donate(s, "Donor One", "Linen Cloth", 20, 100)
  local before = s.broadcasts
  local result = UC.RecordSale(s.deps, { item = "Linen Cloth", qty = 5, proceeds = 500, at = 200, ownRow = true }, actor)
  assert_eq(#s.rows, 1, "sale: still one row")
  assert_eq(s.rows[1].id, row.id, "sale: same row id")
  assert_eq(s.rows[1].copper, 500, "sale: proceeds on the row")
  assert_eq(s.rows[1].detail, "Linen Cloth x20 (5 sold)", "sale: detail shows what was sold")
  assert_eq(s.rows[1].at, 200, "sale: newer timestamp so the mesh replaces the row")
  assert_eq(s.broadcasts, before + 1, "sale: updated row is shared")
  assert_eq(#result, 1, "sale: one row reported")
  UC.RecordSale(s.deps, { item = "Linen Cloth", qty = 3, proceeds = 300, at = 300, ownRow = true }, actor)
  assert_eq(s.rows[1].copper, 800, "sale: proceeds add up")
  assert_eq(s.rows[1].detail, "Linen Cloth x20 (8 sold)", "sale: sold count adds up")
  assert_eq(Ledger.TotalCopper(s.rows), 800, "sale: ledger total is the proceeds")
end

-- Scenario: a sale at the same second still replaces the row
do
  local s = setup()
  donate(s, "Donor One", "Linen Cloth", 2, 100)
  UC.RecordSale(s.deps, { item = "Linen Cloth", qty = 1, proceeds = 40, at = 100, ownRow = true }, actor)
  assert_eq(s.rows[1].copper, 40, "same second: still recorded")
  assert_eq(s.rows[1].at > 100, true, "same second: timestamp moved forward")
end

-- Scenario: the oldest row is filled first and a big sale spills to the next
do
  local s = setup()
  donate(s, "Donor One", "Linen Cloth", 3, 100)
  donate(s, "Donor Two", "Linen Cloth", 10, 110)
  UC.RecordSale(s.deps, { item = "Linen Cloth", qty = 5, proceeds = 100, at = 200, ownRow = true }, actor)
  assert_eq(#s.rows, 2, "spill: no extra row")
  assert_eq(s.rows[1].copper + s.rows[2].copper, 100, "spill: all proceeds placed")
  assert_eq(s.rows[1].detail, "Linen Cloth x3 (3 sold)", "spill: oldest row sold out")
  assert_eq(s.rows[2].detail, "Linen Cloth x10 (2 sold)", "spill: rest on the newer row")
end

-- Scenario: an auction sale of something nobody donated keeps its own row
do
  local s = setup()
  UC.RecordSale(s.deps, { item = "Iron Bar", qty = 1, proceeds = 300, at = 200, ownRow = true }, actor)
  assert_eq(#s.rows, 1, "own row: recorded")
  assert_eq(s.rows[1].kind, "ah", "own row: auction kind")
  assert_eq(s.rows[1].detail, "Iron Bar", "own row: item as detail")
  assert_eq(s.rows[1].copper, 300, "own row: proceeds")
end

-- Scenario: a vendor sale of something nobody donated is not recorded
do
  local s = setup()
  local result = UC.RecordSale(s.deps, { item = "Iron Bar", qty = 1, proceeds = 300, at = 200 }, actor)
  assert_eq(#s.rows, 0, "vendor, not donated: nothing recorded")
  assert_eq(#result, 0, "vendor, not donated: nothing reported")
end

-- Scenario: a lot whose row is gone from the ledger does not lose the money
do
  local s = setup()
  donate(s, "Donor One", "Linen Cloth", 5, 100)
  s.rows = {}
  UC.RecordSale(s.deps, { item = "Linen Cloth", qty = 5, proceeds = 250, at = 200, ownRow = true }, actor)
  assert_eq(#s.rows, 1, "stale lot: proceeds get their own row")
  assert_eq(s.rows[1].copper, 250, "stale lot: proceeds kept")
end

-- Scenario: only the donation target writes the ledger
do
  local s = setup()
  donate(s, "Donor One", "Linen Cloth", 5, 100)
  local result, reason = UC.RecordSale(s.deps, { item = "Linen Cloth", qty = 1, proceeds = 50, at = 200 }, { name = "Someone Else" })
  assert_eq(result, nil, "not target: nothing written")
  assert_eq(reason, "not_target", "not target: reason")
  assert_eq(s.rows[1].copper, 0, "not target: row untouched")
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("item sale tests passed")
