-- Pure Lua tests for the Ledger window view model + use cases.
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Config.lua")
dofile(repo .. "/fundraiser/Domain/Event.lua")
dofile(repo .. "/fundraiser/Domain/Rank.lua")
dofile(repo .. "/fundraiser/Domain/Roles.lua")
dofile(repo .. "/fundraiser/Domain/Ledger.lua")
dofile(repo .. "/fundraiser/Domain/LedgerView.lua")
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

local LV = Fundraiser.Domain.LedgerView
local UC = Fundraiser.Application.UseCases

local function row(id, name, copper, at, eventId, kind)
  return { id = id, kind = kind or "mail", name = name, detail = "", copper = copper, at = at, eventId = eventId or "e1" }
end

local G = 10000

-- Scenario: active rows are listed newest first, ties broken by id
do
  local rows = { row("a", "A", 1, 10), row("c", "C", 1, 30), row("b", "B", 1, 30), row("d", "D", 1, 20) }
  local out = LV.ActiveRows(rows)
  assert_eq(#out, 4, "active rows: count")
  assert_eq(out[1].id, "b", "active rows: newest first, id tie-break (b before c)")
  assert_eq(out[2].id, "c", "active rows: second newest")
  assert_eq(out[3].id, "d", "active rows: third")
  assert_eq(out[4].id, "a", "active rows: oldest last")
  assert_eq(rows[1].id, "a", "active rows: input not mutated")
  assert_eq(#LV.ActiveRows(nil), 0, "active rows: nil input")
end

-- Scenario: archive summaries, one per archive, most recently finished first
do
  local archives = {
    { event = { id = "old", name = "Old" }, contributions = { row("1", "A", 5 * G, 1, "old") }, archivedAt = 100 },
    {
      event = { id = "new", name = "New" },
      contributions = { row("2", "A", 2 * G, 1, "new"), row("3", "B", 3 * G, 2, "new"), row("x", "B", 99, 2, "other") },
      archivedAt = 300,
    },
    { event = { id = "mid", name = "Mid" }, contributions = {}, archivedAt = 200 },
  }
  local out = LV.ArchiveSummaries(archives)
  assert_eq(#out, 3, "archives: one summary each")
  assert_eq(out[1].name, "New", "archives: newest archivedAt first")
  assert_eq(out[1].count, 2, "archives: rows of other events are ignored")
  assert_eq(out[1].total, 5 * G, "archives: total of own event only")
  assert_eq(out[2].name, "Mid", "archives: second")
  assert_eq(out[2].count, 0, "archives: empty archive count")
  assert_eq(out[3].name, "Old", "archives: oldest last")
  assert_eq(out[3].eventId, "old", "archives: event id kept")
end

-- Scenario: old or broken archives are tolerated
do
  local out = LV.ArchiveSummaries({
    { event = { id = "a" }, contributions = { row("1", "A", 7, 1, "a") } },
    { contributions = nil },
    "garbage",
  })
  assert_eq(#out, 2, "tolerant: garbage skipped, event-less archive kept")
  assert_eq(out[1].archivedAt, 0, "tolerant: missing archivedAt is 0")
  assert_eq(out[1].name, "", "tolerant: missing name is empty")
  assert_eq(#LV.ArchiveSummaries(nil), 0, "tolerant: nil archives")
end

-- Scenario: equal archivedAt keeps the later-stored archive first
do
  local out = LV.ArchiveSummaries({
    { event = { id = "a", name = "First" }, archivedAt = 5 },
    { event = { id = "b", name = "Second" }, archivedAt = 5 },
  })
  assert_eq(out[1].name, "Second", "archives: tie -> later stored first")
end

-- Scenario: top contributors sum per normalised character name
do
  local rows = {
    row("1", "Bank Alt-Realm", 3 * G, 1),
    row("2", "bank alt", 4 * G, 2),
    row("3", "Zed Zed", 8 * G, 3),
    row("4", "Amy Amy", 7 * G, 4),
    row("5", "", 100 * G, 5),
  }
  local top = LV.TopContributors(rows)
  assert_eq(#top, 3, "top: empty names skipped")
  assert_eq(top[1].name, "Zed Zed", "top: highest sum first")
  assert_eq(top[2].name, "Amy Amy", "top: equal sums tie-break by name")
  assert_eq(top[3].name, "Bank Alt", "top: realm suffix stripped, first spelling kept")
  assert_eq(top[3].copper, 7 * G, "top: same character summed across realm/case")
  assert_eq(top[3].count, 2, "top: row count per contributor")
  assert_eq(#LV.TopContributors(nil), 0, "top: nil input")
end

-- Scenario: Build combines active rows and archive summaries
do
  local ev = { id = "e1", name = "Raid Fund" }
  local rows = { row("1", "A", 2 * G, 1), row("2", "B", 3 * G, 2), row("z", "C", 9 * G, 2, "other") }
  local v = LV.Build(ev, rows, { { event = { id = "o", name = "O" }, archivedAt = 1 } })
  assert_eq(v.active.count, 2, "build: active count only for the event")
  assert_eq(v.active.total, 5 * G, "build: active total equals Ledger.TotalCopper")
  assert_eq(v.active.rows[1].id, "2", "build: active rows newest first")
  assert_eq(#v.archived, 1, "build: archived summaries present")
  assert_true(v.hasEvent, "build: hasEvent")
  local none = LV.Build(nil, rows, {})
  assert_eq(none.active.count, 0, "build: no event -> no active rows")
  assert_eq(none.hasEvent, false, "build: no event flag")
end

-- Scenario: MOTD text format
do
  local ev = { name = "Raid Fund", goalCopper = 5000 * G }
  local top = { name = "Bank Alt", copper = 800 * G }
  assert_eq(
    LV.MotdText(ev, 1200 * G, top),
    "Fundraiser Raid Fund: 1200g/5000g (24%). Top contributor: Bank Alt!",
    "motd: full format"
  )
  assert_eq(
    LV.MotdText({ name = "Raid Fund", goalCopper = 0 }, 1200 * G, top),
    "Fundraiser Raid Fund: 1200g. Top contributor: Bank Alt!",
    "motd: no goal drops goal and percent"
  )
  assert_eq(
    LV.MotdText(ev, 0, nil),
    "Fundraiser Raid Fund: 0g/5000g (0%).",
    "motd: no rows drops contributor sentence"
  )
  assert_eq(
    LV.MotdText(ev, 6000 * G, top),
    "Fundraiser Raid Fund: 6000g/5000g (120%). Top contributor: Bank Alt!",
    "motd: percent may exceed 100"
  )
  assert_eq(
    LV.MotdText(ev, 1200 * G + 9999, top),
    "Fundraiser Raid Fund: 1200g/5000g (24%). Top contributor: Bank Alt!",
    "motd: whole gold, floored"
  )
end

-- Scenario: MOTD is capped at 128 chars by shortening the event name, never the contributor
do
  local ev = { name = string.rep("N", 200), goalCopper = 5000 * G }
  local top = { name = "Bank Alt", copper = 800 * G }
  local text = LV.MotdText(ev, 1200 * G, top)
  assert_true(#text <= 128, "motd cap: within 128 bytes")
  assert_true(text:find("Top contributor: Bank Alt!", 1, true) ~= nil, "motd cap: contributor kept")
  assert_true(text:find("...", 1, true) ~= nil, "motd cap: shortened name marked with ...")
  assert_true(text:find("1200g/5000g (24%)", 1, true) ~= nil, "motd cap: numbers kept")
end

-- Scenario: MOTD cap does not cut a multi-byte character in half
do
  local ev = { name = string.rep("\195\184", 100), goalCopper = 5000 * G } -- 100 x "o with stroke"
  local text = LV.MotdText(ev, 1 * G, { name = "Bank Alt", copper = 1 })
  assert_true(#text <= 128, "motd utf8: within cap")
  -- every continuation byte must follow a lead byte: removing valid pairs leaves no stray bytes
  local stripped = text:gsub("\195\184", "")
  assert_true(not stripped:find("[\128-\255]"), "motd utf8: no half characters")
end

-- Use-case fixtures
local function deps(opts)
  opts = opts or {}
  return {
    getEvent = function()
      return opts.event
    end,
    getContributions = function()
      return opts.rows or {}
    end,
    getArchives = function()
      return opts.archives or {}
    end,
    getPlayerName = function()
      return opts.name or "Member One"
    end,
    getPlayerRankIndex = function()
      return opts.rank
    end,
    canEditMotd = function()
      return opts.canEdit ~= false
    end,
    setMotd = function(text)
      opts.motd = text
      return opts.setResult
    end,
  }
end

local event = { id = "e1", name = "Raid Fund", target = "Bank Alt", goalCopper = 5000 * G }
local rows = { row("1", "Amy Amy", 2 * G, 1), row("2", "Bob Bob", 3 * G, 2) }
local archives = { { event = { id = "o", name = "Old" }, contributions = { row("9", "X", 4 * G, 1, "o") }, archivedAt = 9 } }

-- Scenario: officer sees active rows and archive summaries
do
  local v, err = UC.GetLedgerView(deps({ event = event, rows = rows, archives = archives, rank = 1 }))
  assert_true(v ~= nil, "uc view: officer allowed " .. tostring(err))
  assert_eq(v.active.total, 5 * G, "uc view: active total")
  assert_eq(#v.archived, 1, "uc view: archive summary present")
end

-- Scenario: donation target (non-officer) may view
do
  local v = UC.GetLedgerView(deps({ event = event, rows = rows, rank = 9, name = "Bank Alt" }))
  assert_true(v ~= nil, "uc view: donation target allowed")
end

-- Scenario: regular member gets nothing
do
  local v, err = UC.GetLedgerView(deps({ event = event, rows = rows, archives = archives, rank = 9 }))
  assert_eq(v, nil, "uc view: member denied")
  assert_eq(err, "no_access", "uc view: member reason")
end

-- Scenario: no active event, officer still sees archive summaries; member does not
do
  local v = UC.GetLedgerView(deps({ event = nil, archives = archives, rank = 1 }))
  assert_true(v ~= nil, "uc view: officer without active event allowed")
  assert_eq(v.hasEvent, false, "uc view: no active event flag")
  assert_eq(#v.archived, 1, "uc view: archives shown without active event")
  local m, err = UC.GetLedgerView(deps({ event = nil, archives = archives, rank = 9 }))
  assert_eq(m, nil, "uc view: member without event denied")
  assert_eq(err, "no_access", "uc view: member without event reason")
end

-- Scenario: empty everything for an officer is an empty view, not an error
do
  local v = UC.GetLedgerView(deps({ rank = 0 }))
  assert_true(v ~= nil, "uc view: officer, nothing recorded")
  assert_eq(v.active.count, 0, "uc view: empty active")
  assert_eq(#v.archived, 0, "uc view: empty archived")
end

-- Scenario: PrepareMotd / SetMotd
do
  local o = { event = event, rows = rows, rank = 1, canEdit = true }
  local text = UC.PrepareMotd(deps(o))
  assert_eq(text, "Fundraiser Raid Fund: 5g/5000g (0%). Top contributor: Bob Bob!", "motd uc: prepared text")
  assert_eq(o.motd, nil, "motd uc: prepare does not set")
  local set = UC.SetMotd(deps(o))
  assert_eq(set, text, "motd uc: set returns text")
  assert_eq(o.motd, text, "motd uc: set calls adapter")
end

do
  local o = { event = event, rows = rows, rank = 1, canEdit = false }
  local r, err = UC.SetMotd(deps(o))
  assert_eq(r, nil, "motd uc: no edit right")
  assert_eq(err, "cannot_edit_motd", "motd uc: no edit right reason")
  assert_eq(o.motd, nil, "motd uc: not set without right")

  local fo = { event = event, rows = rows, rank = 1, setResult = false }
  local fr, ferr = UC.SetMotd(deps(fo))
  assert_eq(fr, nil, "motd uc: adapter refusal is an error")
  assert_eq(ferr, "set_failed", "motd uc: adapter refusal reason")

  local m, merr = UC.SetMotd(deps({ event = event, rows = rows, rank = 9 }))
  assert_eq(m, nil, "motd uc: member denied")
  assert_eq(merr, "no_access", "motd uc: member reason")

  local n, nerr = UC.SetMotd(deps({ event = nil, rank = 0 }))
  assert_eq(n, nil, "motd uc: no event")
  assert_eq(nerr, "no_event", "motd uc: no event reason")
end

-- Scenario: manual donation on the donation target
do
  local store = {}
  local sent = {}
  local d = {
    getEvent = function()
      return event
    end,
    getContributions = function()
      return store
    end,
    setContributions = function(list)
      store = list
    end,
    broadcastLedgerEntry = function(entry)
      sent[#sent + 1] = entry
    end,
  }
  local target = { name = "Bank Alt", now = 500 }
  local e, err = UC.AddManualDonation(d, { name = "Donor One", copper = 12 * G, detail = "traded in person" }, target)
  assert_true(e ~= nil, "manual: target may add " .. tostring(err))
  assert_eq(e.kind, "manual", "manual: kind")
  assert_eq(e.eventId, "e1", "manual: stamped with active event")
  assert_eq(e.at, 500, "manual: timestamp from actor")
  assert_eq(#store, 1, "manual: stored")
  assert_eq(#sent, 1, "manual: broadcast to the mesh")
  assert_eq(UC.GetLedger(deps({ event = event, rows = store, rank = 1 }), "e1")[1].name, "Donor One", "manual: visible in ledger")

  UC.AddManualDonation(d, { name = "Donor One", copper = 12 * G, detail = "traded in person" }, target)
  assert_eq(#store, 2, "manual: identical donation in the same second stays a separate row")

  local wire = Fundraiser.Adapters.Codec.EncodeLedgerEntry(e, 0)
  local back = Fundraiser.Adapters.Codec.DecodeLedgerEntry(wire)
  assert_true(back ~= nil and back.kind == "manual", "manual: survives the LEDGER wire format")

  local off = UC.AddManualDonation(d, { name = "Donor", copper = 5 }, { name = "Some Officer", rankIndex = 1, now = 2 })
  assert_true(off ~= nil, "manual: officers may add too")
  local x, xerr = UC.AddManualDonation(d, { name = "Donor", copper = 5 }, { name = "Plain Member", rankIndex = 9, now = 3 })
  assert_eq(x, nil, "manual: members may not add")
  assert_eq(xerr, "not_allowed", "manual: not allowed reason")
  local mail, merr = UC.AppendLedgerEntry(d, { kind = "mail", name = "X", copper = 5, at = 4 }, { name = "Some Officer", rankIndex = 1 })
  assert_eq(mail, nil, "mail/AH rows stay target-only")
  assert_eq(merr, "not_target", "mail/AH not target reason")
  assert_eq(select(2, UC.AddManualDonation(d, { name = "", copper = 5 }, target)), "bad_name", "manual: name required")
  assert_eq(select(2, UC.AddManualDonation(d, { name = "A B", copper = 0 }, target)), "bad_copper", "manual: amount required")
  assert_eq(select(2, UC.AddManualDonation(d, { name = "A B", copper = -3 }, target)), "bad_copper", "manual: negative amount")
  local none = { getEvent = function() return nil end }
  assert_eq(select(2, UC.AddManualDonation(none, { name = "A B", copper = 5 }, target)), "no_event", "manual: needs an active event")
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("ledger view tests passed")
