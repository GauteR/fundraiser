-- Pure Lua tests for the target page view model (grouping, bulk eligibility, selection).
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Config.lua")
dofile(repo .. "/fundraiser/Domain/SaleAdvice.lua")
dofile(repo .. "/fundraiser/Domain/TargetView.lua")

local TV = Fundraiser.Domain.TargetView
local failed = 0

local function assert_eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s (%s ~= %s)\n", msg or "assert_eq", tostring(a), tostring(b)))
  end
end

local function row(bag, slot, name, advice, vendorTotal, ahNet)
  return { bag = bag, slot = slot, name = name, advice = advice, vendorTotal = vendorTotal, ahNet = ahNet }
end

-- Scenario: stacks are grouped by the sale advice
do
  local rows = {
    row(0, 1, "Linen", "vendor", 40, 10),
    row(0, 2, "Silk", "ah", 20, 500),
    row(0, 3, "Mystery", "manual", nil, nil),
    row(0, 4, "Rune", "ah", 10, 900),
  }
  local view = TV.Build(rows, { minValue = 0 })
  assert_eq(#view.groups.auction.entries, 2, "group: two auction stacks")
  assert_eq(#view.groups.vendor.entries, 1, "group: one vendor stack")
  assert_eq(#view.groups.price.entries, 1, "group: one needs-price stack")
  assert_eq(view.groups.auction.entries[1].row.name, "Rune", "group: best value first inside a list")
  assert_eq(view.groups.auction.entries[2].row.name, "Silk", "group: second best value next")
  assert_eq(view.groups.auction.total, 1400, "group: auction total is the sum of AH net")
  assert_eq(view.groups.vendor.total, 40, "group: vendor total is the sum of vendor totals")
end

-- Scenario: the value of a stack is the value of the recommended action
do
  assert_eq(TV.Value(row(0, 1, "A", "ah", 5, 300)), 300, "value: AH net for auction stacks")
  assert_eq(TV.Value(row(0, 1, "A", "vendor", 50, 10)), 50, "value: vendor total for vendor stacks")
  assert_eq(TV.Value(row(0, 1, "A", "manual", nil, nil)), nil, "value: none without a usable price")
end

-- Scenario: stacks below the minimum value stay listed but leave bulk actions
do
  local rows = { row(0, 1, "Cheap", "vendor", 50, nil), row(0, 2, "Fine", "vendor", 150, nil) }
  local view = TV.Build(rows, { minValue = 100 })
  local cheap, fine
  for _, e in ipairs(view.groups.vendor.entries) do
    if e.row.name == "Cheap" then
      cheap = e
    else
      fine = e
    end
  end
  assert_eq(cheap.belowMin, true, "min value: cheap stack is marked")
  assert_eq(cheap.bulk, false, "min value: cheap stack is not bulk eligible")
  assert_eq(fine.belowMin, false, "min value: fine stack is not marked")
  assert_eq(fine.bulk, true, "min value: fine stack is bulk eligible")
  assert_eq(#TV.BulkEntries(view, "vendor"), 1, "min value: bulk list only has the fine stack")
  assert_eq(view.groups.vendor.bulkCount, 1, "min value: bulk count")
  assert_eq(view.groups.vendor.bulkTotal, 150, "min value: bulk total")
  assert_eq(view.groups.vendor.total, 200, "min value: group total still counts every stack")
end

-- Scenario: skipped stacks leave bulk actions, needs-price stacks never join them
do
  local rows = { row(0, 1, "A", "ah", 1, 400), row(0, 2, "B", "ah", 1, 300), row(0, 3, "C", "manual", nil, nil) }
  local view = TV.Build(rows, { minValue = 0, skipped = { [TV.Key(rows[1])] = true } })
  assert_eq(#TV.BulkEntries(view, "auction"), 1, "skip: skipped stack leaves the bulk list")
  assert_eq(TV.BulkEntries(view, "auction")[1].row.name, "B", "skip: the other stack stays")
  assert_eq(#TV.BulkEntries(view, "price"), 0, "skip: needs-price stacks are never bulk")
  assert_eq(view.groups.auction.entries[1].skipped, true, "skip: skipped stack is flagged in the list")
end

-- Scenario: the default minimum value comes from Config
do
  Fundraiser.Config.MIN_STACK_VALUE_COPPER = 100
  local view = TV.Build({ row(0, 1, "A", "vendor", 99, nil) }, {})
  assert_eq(view.groups.vendor.entries[1].belowMin, true, "config: default minimum applies")
  local none = TV.Build({ row(0, 1, "A", "vendor", 99, nil) }, { minValue = 0 })
  assert_eq(none.groups.vendor.entries[1].belowMin, false, "config: explicit minimum overrides")
end

-- Scenario: selection walks auction, then vendor, then needs-price stacks, and wraps
do
  local rows = {
    row(0, 1, "V", "vendor", 100, nil),
    row(0, 2, "A", "ah", 1, 500),
    row(0, 3, "N", "manual", nil, nil),
  }
  local view = TV.Build(rows, { minValue = 0 })
  local flat = TV.Flatten(view)
  assert_eq(#flat, 3, "flatten: every stack is selectable")
  assert_eq(flat[1].row.name, "A", "flatten: auction first")
  assert_eq(flat[2].row.name, "V", "flatten: vendor second")
  assert_eq(flat[3].row.name, "N", "flatten: needs price last")
  assert_eq(TV.Move(1, 1, 3), 2, "move: next")
  assert_eq(TV.Move(3, 1, 3), 1, "move: next wraps to the first")
  assert_eq(TV.Move(1, -1, 3), 3, "move: previous wraps to the last")
  assert_eq(TV.Move(1, 1, 0), 0, "move: nothing to select in an empty list")
end

-- Scenario: selection is clamped after the list shrinks, and an empty list selects nothing
do
  assert_eq(TV.Clamp(5, 3), 3, "clamp: above the end")
  assert_eq(TV.Clamp(0, 3), 1, "clamp: below the start")
  assert_eq(TV.Clamp(2, 3), 2, "clamp: inside the list")
  assert_eq(TV.Clamp(4, 0), 0, "clamp: empty list")
  local view = TV.Build({}, { minValue = 0 })
  assert_eq(#TV.Flatten(view), 0, "empty: no entries")
  assert_eq(view.groups.auction.total, 0, "empty: zero total")
end

-- Scenario: stack keys identify a bag slot
do
  assert_eq(TV.Key(row(2, 7, "A", "ah")), "2:7", "key: bag and slot")
end

-- Scenario: the note shown next to a row says why it is left out of bulk actions
do
  assert_eq(TV.RowNote({ group = "auction", skipped = true, belowMin = true }), "skipped", "note: skipped wins")
  assert_eq(TV.RowNote({ group = "auction", belowMin = true }), "below_min", "note: below the minimum")
  assert_eq(TV.RowNote({ group = "price" }), "needs_price", "note: no price yet")
  assert_eq(TV.RowNote({ group = "vendor" }), nil, "note: a normal row has none")
end

-- Scenario: status lines are coloured by what happened
do
  assert_eq(TV.StatusKind("CHAT_TARGET_POSTED"), "ok", "status: posted")
  assert_eq(TV.StatusKind("CHAT_TARGET_VENDOR_OK"), "ok", "status: sold")
  assert_eq(TV.StatusKind("TARGET_BULK_DONE_FMT"), "ok", "status: bulk done")
  assert_eq(TV.StatusKind("TARGET_BULK_PROGRESS_FMT"), "info", "status: bulk progress")
  assert_eq(TV.StatusKind("CHAT_TARGET_POST_FAILED"), "error", "status: failure")
  assert_eq(TV.StatusKind("CHAT_TARGET_OPEN_AH"), "error", "status: needs the auction house")
  assert_eq(TV.StatusKind("TARGET_BULK_STOPPED_FMT"), "error", "status: bulk stopped")
  assert_eq(TV.StatusKind(nil), "info", "status: nothing")
end

-- Scenario: the dock goes beside the right-most visible auction window
do
  assert_eq(
    TV.PickAnchor({
      { name = "AuctionHouseFrame", right = 900, shown = true },
      { name = "AuctionFrame", right = nil, shown = false },
      { name = "AuctionatorItemHistoryFrame", right = 1200, shown = true },
    }),
    "AuctionatorItemHistoryFrame",
    "anchor: the window furthest to the right wins"
  )
  assert_eq(
    TV.PickAnchor({
      { name = "AuctionHouseFrame", right = 900, shown = true },
      { name = "AuctionatorItemHistoryFrame", right = 1200, shown = false },
    }),
    "AuctionHouseFrame",
    "anchor: hidden windows are ignored"
  )
  assert_eq(
    TV.PickAnchor({
      { name = "A", right = 900, shown = true },
      { name = "B", right = 900, shown = true },
    }),
    "A",
    "anchor: a tie keeps the first (listed first = preferred)"
  )
  assert_eq(TV.PickAnchor({ { name = "A", right = nil, shown = true } }), "A", "anchor: unknown edge still counts")
  assert_eq(TV.PickAnchor({}), nil, "anchor: nothing to anchor to")
end

-- Scenario: skipping a stack moves the selection to the next one and stops at the end
do
  assert_eq(TV.AfterSkip(1, 3), 2, "after skip: next stack")
  assert_eq(TV.AfterSkip(2, 3), 3, "after skip: next stack again")
  assert_eq(TV.AfterSkip(3, 3), 3, "after skip: the last stack stays selected")
  assert_eq(TV.AfterSkip(1, 1), 1, "after skip: a single stack stays selected")
  assert_eq(TV.AfterSkip(0, 0), 0, "after skip: an empty list selects nothing")
end

-- Scenario: the row tooltip uses the bag slot only while that slot still holds the scanned item
do
  local row = { bag = 0, slot = 3, itemId = 2589, link = "|cffffffff|Hitem:2589|h[Linen Cloth]|h|r", name = "Linen Cloth" }
  assert_eq(TV.TooltipSource(row, 2589), "bag", "tooltip: slot still holds the item")
  assert_eq(TV.TooltipSource(row, 2592), "link", "tooltip: slot now holds another item, use the link")
  assert_eq(TV.TooltipSource(row, nil), "link", "tooltip: empty slot, use the link")
  assert_eq(
    TV.TooltipSource({ bag = 0, slot = 3, itemId = 2589, name = "Linen Cloth" }, nil),
    "name",
    "tooltip: no link left, use the name"
  )
  assert_eq(TV.TooltipSource({ link = row.link, itemId = 2589 }, nil), "link", "tooltip: row without a slot uses the link")
  assert_eq(TV.TooltipSource({}, nil), "name", "tooltip: nothing known falls back to the name")
end

-- Scenario: Post to AH / Vendor on the selected stack need their window open
do
  local both = { auctionable = true, vendorUnit = 5 }
  local st = TV.ActionState(both, { ahOpen = false, merchantOpen = false })
  assert_eq(st.post, false, "actions: no auction house, no posting")
  assert_eq(st.vendor, false, "actions: no vendor, no selling")
  st = TV.ActionState(both, { ahOpen = true, merchantOpen = false })
  assert_eq(st.post, true, "actions: auction house open enables posting")
  assert_eq(st.vendor, false, "actions: auction house open does not enable selling")
  st = TV.ActionState(both, { ahOpen = false, merchantOpen = true })
  assert_eq(st.post, false, "actions: vendor open does not enable posting")
  assert_eq(st.vendor, true, "actions: vendor open enables selling")
  st = TV.ActionState({ auctionable = false, vendorUnit = nil }, { ahOpen = true, merchantOpen = true })
  assert_eq(st.post, false, "actions: a stack that cannot be auctioned stays disabled")
  assert_eq(st.vendor, false, "actions: a stack without a vendor price stays disabled")
  st = TV.ActionState(both, nil)
  assert_eq(st.post, false, "actions: unknown windows count as closed (post)")
  assert_eq(st.vendor, false, "actions: unknown windows count as closed (vendor)")
end

-- Scenario: a stack below the minimum value cannot be posted or sold from the page
do
  local both = { auctionable = true, vendorUnit = 5 }
  local open = { ahOpen = true, merchantOpen = true }
  local st = TV.ActionState(both, open, true)
  assert_eq(st.post, false, "below min: posting stays disabled")
  assert_eq(st.vendor, false, "below min: selling stays disabled")
  st = TV.ActionState(both, open, false)
  assert_eq(st.post, true, "above min: posting is enabled")
  assert_eq(st.vendor, true, "above min: selling is enabled")
end

-- Scenario: Skip only applies to stacks that could join a bulk action
do
  assert_eq(TV.CanSkip({ group = "auction" }), true, "skip: a normal auction stack")
  assert_eq(TV.CanSkip({ group = "vendor", skipped = true }), true, "skip: a skipped stack can be included again")
  assert_eq(TV.CanSkip({ group = "price" }), false, "skip: needs-price stacks are never in bulk")
  assert_eq(TV.CanSkip({ group = "auction", belowMin = true }), false, "skip: below the minimum is already left out")
  assert_eq(TV.CanSkip({ group = "auction", ignored = true }), false, "skip: ignored items are already left out")
end

-- Scenario: a queued stack survives a re-scan only while its slot still holds the same item
do
  local scan = {
    { bag = 0, slot = 1, itemId = 100 },
    { bag = 0, slot = 2, itemId = 200 },
  }
  local keep = TV.StillInBags(scan)
  assert_eq(keep({ row = { bag = 0, slot = 1, itemId = 100 } }), true, "rescan: same slot and item stays")
  assert_eq(keep({ row = { bag = 0, slot = 2, itemId = 999 } }), false, "rescan: other item in the slot is dropped")
  assert_eq(keep({ row = { bag = 1, slot = 1, itemId = 100 } }), false, "rescan: empty slot is dropped")
  assert_eq(TV.StillInBags(nil)({ row = { bag = 0, slot = 1, itemId = 100 } }), false, "rescan: no scan keeps nothing")
end

-- Scenario: ignored items stay listed but leave bulk actions, for every stack of the item
do
  local a = row(0, 1, "Silk", "vendor", 500, nil)
  a.itemId = 4306
  local b = row(0, 2, "Silk", "vendor", 400, nil)
  b.itemId = 4306
  local c = row(0, 3, "Wool", "vendor", 300, nil)
  c.itemId = 2592
  local view = TV.Build({ a, b, c }, { minValue = 0, ignored = { [4306] = true } })
  local g = view.groups.vendor
  assert_eq(#g.entries, 3, "ignored: all stacks stay listed")
  assert_eq(g.entries[1].ignored, true, "ignored: first Silk stack flagged")
  assert_eq(g.entries[2].ignored, true, "ignored: second Silk stack flagged")
  assert_eq(g.entries[3].ignored, false, "ignored: other item not flagged")
  assert_eq(g.bulkCount, 1, "ignored: only the other item is in bulk")
  assert_eq(g.bulkTotal, 300, "ignored: bulk total leaves ignored stacks out")
  assert_eq(TV.RowNote(g.entries[1]), "ignored", "ignored: row note")
end

-- Scenario: an ignored stack that is also skipped reports the ignore first
do
  local a = row(0, 1, "Silk", "vendor", 500, nil)
  a.itemId = 4306
  local view = TV.Build({ a }, { minValue = 0, ignored = { [4306] = true }, skipped = { ["0:1"] = true } })
  assert_eq(TV.RowNote(view.groups.vendor.entries[1]), "ignored", "ignored: note beats skipped")
end

-- Scenario: item names take the colour of their quality, else the default
do
    local default = { 1, 1, 1 }
    local function colorFn(q)
        return q / 10, 0.5, 0.25
    end
    local r, g, b = TV.NameColor(3, colorFn, default)
    assert_eq(r, 0.3, "name colour: quality red")
    assert_eq(g, 0.5, "name colour: quality green")
    assert_eq(b, 0.25, "name colour: quality blue")

    r, g, b = TV.NameColor(nil, colorFn, default)
    assert_eq(r .. g .. b, "111", "name colour: uncached item uses the default")

    r, g, b = TV.NameColor(3, nil, default)
    assert_eq(r .. g .. b, "111", "name colour: no colour function uses the default")

    r, g, b = TV.NameColor(3, function() end, default)
    assert_eq(r .. g .. b, "111", "name colour: colour function without a result uses the default")
end

-- Scenario: with the profit threshold on, a stack's cost basis counts against the minimum value
do
  local function build(enabled, costBasis)
    Fundraiser.Config.PROFIT_THRESHOLD_ENABLED = enabled
    local a = row(0, 1, "Silk", "vendor", 500, nil)
    a.costBasis = costBasis
    local view = TV.Build({ a }, { minValue = 100 })
    return view.groups.vendor.entries[1]
  end

  assert_eq(Fundraiser.Config.PROFIT_THRESHOLD_ENABLED, false, "profit threshold: off by default")
  assert_eq(build(false, 450).belowMin, false, "profit threshold off: cost basis is ignored")
  assert_eq(build(true, 450).belowMin, true, "profit threshold on: profit 50 is below the minimum 100")
  assert_eq(build(true, 450).bulk, false, "profit threshold on: below-minimum profit leaves bulk actions")
  assert_eq(build(true, 300).belowMin, false, "profit threshold on: profit 200 clears the minimum")
  assert_eq(build(true, nil).belowMin, false, "profit threshold on: no cost basis falls back to the value")
  Fundraiser.Config.PROFIT_THRESHOLD_ENABLED = false
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("target view tests passed")
