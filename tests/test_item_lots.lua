-- Pure Lua tests for item lots: donated items that wait to be sold, and how a sale's
-- proceeds are allocated to the oldest open ledger row.
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Domain/ItemLots.lua")

local IL = Fundraiser.Domain.ItemLots
local failed = 0

local function assert_eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s (%s ~= %s)\n", msg or "assert_eq", tostring(a), tostring(b)))
  end
end

-- Scenario: item names from chat text, links and plain names compare equal
do
  assert_eq(IL.ItemKey("Linen Cloth"), "linen cloth", "key: plain name")
  assert_eq(IL.ItemKey("[Linen Cloth]"), "linen cloth", "key: bracketed name")
  assert_eq(
    IL.ItemKey("|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r"),
    "linen cloth",
    "key: item link"
  )
  assert_eq(IL.ItemKey("  Linen   Cloth "), "linen cloth", "key: extra spaces")
  assert_eq(IL.ItemKey(nil), "", "key: nil")
end

-- Scenario: a mail with two attachments becomes two lots on one row; same item adds up
do
  local lots = {}
  IL.Add(lots, { id = "mail:a", item = "Linen Cloth", qty = 20 })
  IL.Add(lots, { id = "mail:a", item = "Wool Cloth", qty = 5 })
  IL.Add(lots, { id = "mail:a", item = "linen cloth", qty = 10 })
  assert_eq(#lots, 2, "add: same item on the same row merges")
  assert_eq(lots[1].qty, 30, "add: quantities add up")
  assert_eq(IL.RowDetail(lots, "mail:a"), "Linen Cloth x30, Wool Cloth x5", "add: row detail lists the items")
  assert_eq(IL.RowCopper(lots, "mail:a"), 0, "add: nothing earned yet")
end

-- Scenario: a sale fills the oldest open row first and the row shows what was sold
do
  local lots = {}
  IL.Add(lots, { id = "mail:old", item = "Linen Cloth", qty = 20 })
  IL.Add(lots, { id = "mail:new", item = "Linen Cloth", qty = 20 })
  local parts, restQty, restCopper = IL.Allocate(lots, "[Linen Cloth]", 5, 500)
  assert_eq(#parts, 1, "allocate: one row touched")
  assert_eq(parts[1].id, "mail:old", "allocate: oldest row first")
  assert_eq(parts[1].qty, 5, "allocate: quantity")
  assert_eq(parts[1].copper, 500, "allocate: proceeds")
  assert_eq(restQty, 0, "allocate: nothing left over")
  assert_eq(restCopper, 0, "allocate: no leftover proceeds")
  assert_eq(IL.RowCopper(lots, "mail:old"), 500, "allocate: row copper")
  assert_eq(IL.RowCopper(lots, "mail:new"), 0, "allocate: newer row untouched")
  assert_eq(IL.RowDetail(lots, "mail:old"), "Linen Cloth x20 (5 sold)", "allocate: detail shows sold")
end

-- Scenario: a sale larger than the oldest row spills into the next one; proceeds add up exactly
do
  local lots = {}
  IL.Add(lots, { id = "mail:old", item = "Linen Cloth", qty = 3 })
  IL.Add(lots, { id = "mail:new", item = "Linen Cloth", qty = 10 })
  local parts = IL.Allocate(lots, "Linen Cloth", 7, 100)
  assert_eq(#parts, 2, "spill: two rows touched")
  assert_eq(parts[1].qty, 3, "spill: oldest row emptied")
  assert_eq(parts[2].qty, 4, "spill: rest on the next row")
  assert_eq(parts[1].copper + parts[2].copper, 100, "spill: no copper lost to rounding")
  assert_eq(IL.RowDetail(lots, "mail:old"), "Linen Cloth x3 (3 sold)", "spill: fully sold row")
end

-- Scenario: more sold than donated, or an item that never came from a player
do
  local lots = {}
  IL.Add(lots, { id = "mail:a", item = "Linen Cloth", qty = 2 })
  local parts, restQty, restCopper = IL.Allocate(lots, "Linen Cloth", 5, 500)
  assert_eq(parts[1].qty, 2, "over: donated part is allocated")
  assert_eq(restQty, 3, "over: rest quantity is reported")
  assert_eq(parts[1].copper + restCopper, 500, "over: proceeds are split, none lost")
  parts, restQty, restCopper = IL.Allocate(lots, "Iron Bar", 1, 300)
  assert_eq(#parts, 0, "unknown: no row")
  assert_eq(restQty, 1, "unknown: all of it is left over")
  assert_eq(restCopper, 300, "unknown: all proceeds are left over")
end

-- Scenario: a sale without a known quantity counts as one item
do
  local lots = {}
  IL.Add(lots, { id = "mail:a", item = "Linen Cloth", qty = 4 })
  local parts = IL.Allocate(lots, "Linen Cloth", nil, 50)
  assert_eq(parts[1].qty, 1, "default quantity: one")
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("item lots tests passed")
