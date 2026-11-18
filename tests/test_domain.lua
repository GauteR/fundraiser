-- Pure Lua tests for Fundraiser domain + application + codec.
-- Style: Given / When / Then scenarios.
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

local Roles = Fundraiser.Domain.Roles
local Ledger = Fundraiser.Domain.Ledger
local UC = Fundraiser.Application.UseCases
local Codec = Fundraiser.Adapters.Codec

local ev
do
  -- Given valid event fields
  -- When creating an event
  ev = Fundraiser.Domain.Event.Create({
    name = "Tabard",
    target = "Bank Alt",
    goalCopper = 100000,
    intervalSeconds = 3600,
    minAdminRank = 1,
  })
  -- Then creation succeeds with numeric goal
  assert_true(ev, "create event")
  assert_eq(ev.goalCopper, 100000, "create event goalCopper")
end

-- Scenario: Publish requires goalCopper > 0; Create allows 0 for legacy wire
do
  local zeroOk, zeroErr = Fundraiser.Domain.Event.Create({
    name = "Legacy",
    target = "Bank Alt",
    goalCopper = 0,
    intervalSeconds = 3600,
    minAdminRank = 1,
  })
  assert_true(zeroOk, "create allows goalCopper 0")
  assert_eq(zeroOk.goalCopper, 0, "legacy goalCopper 0")

  local pub, pubErr = UC.PublishEvent({
    getEvent = function()
      return nil
    end,
    setEvent = function() end,
  }, {
    name = "NoGoal",
    target = "Bank Alt",
    intervalSeconds = 3600,
  }, { rankIndex = 0, name = "GM", now = 1 })
  assert_eq(pub, nil, "publish rejects missing goal")
  assert_eq(pubErr, "bad_goal", "publish bad_goal")
end

-- Scenario: Codec EVENT field 11 goalCopper roundtrip and legacy omit
do
  local encoded = Codec.EncodeEvent(ev)
  local decoded = Codec.DecodeEvent(encoded)
  assert_true(decoded, "decode event")
  assert_eq(decoded.goalCopper, 100000, "decode goalCopper")

  -- Legacy payload without field 11
  local legacy = table.concat({
    "EVENT",
    "id1",
    "Name",
    "Bank Alt",
    "note",
    "3600",
    "1",
    "1",
    "10",
    "GM",
  }, "|")
  local legacyEv = Codec.DecodeEvent(legacy)
  assert_true(legacyEv, "decode legacy event")
  assert_eq(legacyEv.goalCopper, 0, "legacy missing goalCopper -> 0")
end

-- Scenario: Role gates for target / officers / members
do
  -- Given an active event with target Bank Alt and Config DEFAULT_MIN_ADMIN_RANK
  -- When checking view/write/manage
  -- Then target and officers pass; members fail
  assert_true(Roles.IsDonationTarget(ev, "Bank Alt"), "target")
  assert_true(Roles.CanViewLedger(ev, 0, "GM"), "officer view")
  assert_true(not Roles.CanViewLedger(ev, 5, "Grunt"), "member no ledger")
  assert_true(Roles.CanWriteLedger(ev, "Bank Alt"), "target write")
  assert_true(not Roles.CanWriteLedger(ev, "GM"), "officer no write")
  assert_true(Roles.CanManageFundraiser(0, ev), "GM manages")
  assert_true(Roles.CanManageFundraiser(1, ev), "officer manages")
  assert_true(not Roles.CanManageFundraiser(2, ev), "member no manage")
  assert_true(not Roles.CanManageFundraiser(nil, ev), "nil rank no manage")
  assert_true(Roles.CanManageFundraiser(1, nil), "default minAdmin allows rank 1")
  assert_true(not Roles.CanManageFundraiser(2, nil), "default minAdmin blocks rank 2")
end

-- Scenario: Donation target never sees mailbox reminder
do
  -- Given active event and player is the donation target
  -- When evaluating ShouldShowReminder
  local should = UC.ShouldShowReminder({
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
  -- Then reminder is suppressed
  assert_true(not should, "no reminder on target")
end

-- Scenario: Ledger merge is id-union; newer same-id wins
do
  -- Given two distinct rows and a newer revision of the first id
  local a = Ledger.CreateEntry({ kind = "mail", name = "A", copper = 100, eventId = ev.id, at = 1, detail = "x" })
  local b = Ledger.CreateEntry({ kind = "ah", name = "AH", copper = 500, eventId = ev.id, at = 2, detail = "Sword" })
  local c = Ledger.CreateEntry({
    id = a.id,
    kind = "mail",
    name = "A",
    copper = 150,
    eventId = ev.id,
    at = 3,
    detail = "x",
  })
  -- When merging
  local merged = Ledger.Merge({ a }, { b, c })
  -- Then union size 2 and total uses newer copper for A
  assert_eq(#merged, 2, "merge union")
  assert_eq(Ledger.TotalCopper(merged), 650, "merge total")
end

-- Scenario: Only donation target may append ledger rows
do
  -- Given empty local store and active event
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
  -- When a non-target appends
  local entry, err = UC.AppendLedgerEntry(deps, {
    kind = "mail",
    name = "Donor",
    copper = 10,
    detail = "hi",
    at = 9,
  }, { name = "GM" })
  -- Then rejected
  assert_eq(entry, nil, "reject non-target write")
  assert_eq(err, "not_target", "not_target")

  -- When the donation target appends
  entry = UC.AppendLedgerEntry(deps, {
    kind = "mail",
    name = "Donor",
    copper = 10,
    detail = "hi",
    at = 9,
  }, { name = "Bank Alt" })
  -- Then accepted
  assert_true(entry, "target append")

  -- When encoding/decoding that appended LEDGER row
  local decoded = Codec.Decode(Codec.EncodeLedgerEntry(entry, 0))
  -- Then payload retains kind/copper
  assert_eq(decoded.msgKind, "LEDGER", "msgKind")
  assert_eq(decoded.copper, 10, "codec copper")

  -- Given remote AH row from target
  local remote = {
    Ledger.CreateEntry({ kind = "ah", name = "AH", copper = 99, eventId = ev.id, at = 10, detail = "Boot" }),
  }
  -- When merging at epoch 0
  local merged2, changed = UC.MergeRemoteLedger({
    getEvent = function()
      return ev
    end,
    getContributions = function()
      return storedList
    end,
    setContributions = function(list)
      storedList = list
    end,
    getResetEpoch = function()
      return 0
    end,
  }, remote, "Bank Alt", 5)
  -- Then local store grows
  assert_true(changed, "merged remote")
  assert_true(#merged2 >= 2, "rows after merge")

  -- Given local resetEpoch 3 and a remote row stamped epoch 0
  local staleEntry = Ledger.CreateEntry({
    kind = "mail",
    name = "Old",
    copper = 1,
    eventId = ev.id,
    at = 12,
    detail = "stale",
  })
  staleEntry.resetEpoch = 0
  -- When merging
  local afterStale, staleChanged = UC.MergeRemoteLedger({
    getEvent = function()
      return ev
    end,
    getContributions = function()
      return storedList
    end,
    setContributions = function(list)
      storedList = list
    end,
    getResetEpoch = function()
      return 3
    end,
  }, { staleEntry }, "Bank Alt", 1)
  -- Then stale row is ignored (prevents post-RESET mesh refill)
  assert_true(not staleChanged, "reject pre-epoch ledger")
  assert_eq(#afterStale, #merged2, "ledger unchanged after stale reject")

  -- Given a member client with empty store
  local memberList = {}
  local memberRemote = {
    Ledger.CreateEntry({ kind = "mail", name = "Donor2", copper = 42, eventId = ev.id, at = 11, detail = "relay" }),
  }
  -- When a non-officer receives a relayed row
  local mergedMember, memberChanged = UC.MergeRemoteLedger({
    getEvent = function()
      return ev
    end,
    getContributions = function()
      return memberList
    end,
    setContributions = function(list)
      memberList = list
    end,
    getResetEpoch = function()
      return 0
    end,
  }, memberRemote, "Some Relay", 5)
  -- Then mesh stores it but UI view remains gated
  assert_true(memberChanged, "member mesh store")
  assert_eq(#mergedMember, 1, "member holds relayed row")
  assert_true(not Roles.CanViewLedger(ev, 5, "Grunt"), "member still no UI view")
end

-- Scenario: Codec round-trips RESET / HELLO epoch fields
do
  -- Given RESET fields including epoch
  -- When encoding/decoding
  local resetMsg = Codec.Decode(Codec.EncodeReset("ledger", 123, "Officer One", 7))
  local campaignMsg = Codec.Decode(Codec.EncodeReset("campaign", 124, "Officer One", 8))
  assert_true(campaignMsg, "campaign reset decodes")
  assert_eq(campaignMsg.scope, "campaign", "campaign scope")
  -- Then scope/epoch survive the wire format
  assert_eq(resetMsg.kind, "RESET", "reset kind")
  assert_eq(resetMsg.scope, "ledger", "reset scope")
  assert_eq(resetMsg.at, 123, "reset at")
  assert_eq(resetMsg.resetEpoch, 7, "reset epoch")

  local hello = Codec.Decode(Codec.EncodeHello("0.1.0", "guid", 4))
  assert_eq(hello.resetEpoch, 4, "hello epoch")
end

-- Scenario: AcceptRemoteReset gates on sender admin rank
do
  -- Given Config min admin rank 1
  Fundraiser.Config.DEFAULT_MIN_ADMIN_RANK = 1
  local appliedScope, appliedEpoch = nil, nil

  -- When an officer (rank 1) sends RESET ledger with epoch 7
  local resetOk, resetErr = UC.AcceptRemoteReset({
    applyReset = function(scope, epoch)
      appliedScope = scope
      appliedEpoch = epoch
      return true
    end,
  }, "ledger", 1, 7)
  -- Then apply runs for all local clients that accept
  assert_true(resetOk, "officer reset accepted")
  assert_eq(appliedScope, "ledger", "apply scope")
  assert_eq(appliedEpoch, 7, "apply epoch")

  -- When a member (rank 5) sends RESET
  resetOk, resetErr = UC.AcceptRemoteReset({
    applyReset = function()
      return true
    end,
  }, "all", 5, 1)
  -- Then rejected
  assert_eq(resetOk, nil, "member reset rejected")
  assert_eq(resetErr, "not_admin", "member reset err")

  -- When scope is invalid
  resetOk, resetErr = UC.AcceptRemoteReset({
    applyReset = function()
      return true
    end,
  }, "nope", 0, 1)
  -- Then rejected
  assert_eq(resetOk, nil, "bad scope rejected")
  assert_eq(resetErr, "bad_scope", "bad scope err")
end

-- Scenario: Publishing a new event archives the previous campaign and clears active ledger
do
  -- Given Store with an old event and one contribution
  dofile(repo .. "/fundraiser/Adapters/Store.lua")
  _G.FundraiserDB = nil
  local Store = Fundraiser.Adapters.Store
  Store.db = nil
  Store:Load()
  local oldEv = Fundraiser.Domain.Event.Create({
    name = "Old",
    target = "Bank Alt",
    goalCopper = 50000,
    intervalSeconds = 3600,
    minAdminRank = 1,
  })
  Store:SetEvent(oldEv)
  Store:SetContributions({
    Ledger.CreateEntry({
      kind = "mail",
      name = "Donor",
      copper = 5,
      eventId = oldEv.id,
      at = 1,
      detail = "x",
    }),
  })
  -- When an officer publishes a new event
  local published = UC.PublishEvent({
    getEvent = function()
      return Store:GetEvent()
    end,
    setEvent = function(e)
      Store:SetEvent(e)
    end,
    getContributions = function()
      return Store:GetContributions()
    end,
    archiveEvent = function(event, contributions, archivedAt)
      Store:ArchiveEvent(event, contributions, archivedAt)
    end,
    clearContributions = function()
      Store:ClearLedger()
    end,
    clearReminder = function()
      Store:SetReminderState({})
    end,
  }, {
    name = "New",
    target = "Bank Alt",
    goalCopper = 200000,
    intervalSeconds = 7200,
  }, { rankIndex = 0, name = "GM", now = 50 })
  -- Then new id is active, ledger cleared, and old campaign is archived
  assert_true(published, "publish new event")
  assert_true(published.id ~= oldEv.id, "new event id")
  assert_eq(#Store:GetContributions(), 0, "active ledger cleared")
  assert_eq(#Store:GetArchives(), 1, "archived previous")
  assert_eq(Store:GetArchives()[1].event.name, "Old", "archive name")
  assert_eq(#Store:GetArchives()[1].contributions, 1, "archive ledger rows")
end

-- Scenario: EndActiveEvent archives campaign and clears without a new event
do
  -- Given Store with an active event and one contribution
  dofile(repo .. "/fundraiser/Adapters/Store.lua")
  _G.FundraiserDB = nil
  local Store = Fundraiser.Adapters.Store
  Store.db = nil
  Store:Load()
  Fundraiser.Config.DEFAULT_MIN_ADMIN_RANK = 1
  local oldEv = Fundraiser.Domain.Event.Create({
    name = "Solo Run",
    target = "Bank Alt",
    goalCopper = 10000,
    intervalSeconds = 3600,
    minAdminRank = 1,
  })
  Store:SetEvent(oldEv)
  Store:SetContributions({
    Ledger.CreateEntry({
      kind = "mail",
      name = "Donor",
      copper = 100,
      eventId = oldEv.id,
      at = 1,
      detail = "x",
    }),
  })
  local broadcastScope = nil
  local beforeEpoch = Store:GetResetEpoch()
  -- When an officer ends the campaign (local fallback path)
  local ended, endMode = UC.EndActiveEvent({
    getEvent = function()
      return Store:GetEvent()
    end,
    getContributions = function()
      return Store:GetContributions()
    end,
    getArchives = function()
      return Store:GetArchives()
    end,
    archiveEvent = function(event, contributions, archivedAt)
      Store:ArchiveEvent(event, contributions, archivedAt)
    end,
    applyResetScope = function(scope)
      return Store:ApplyResetScope(scope)
    end,
  }, { rankIndex = 0, name = "GM", now = 99 })
  -- Then no active event, ledger empty, archive kept, epoch bumped, local_only mode
  assert_true(ended, "end ok")
  assert_eq(endMode, "local_only", "local_only mode")
  assert_eq(Store:GetEvent(), nil, "event cleared")
  assert_eq(#Store:GetContributions(), 0, "ledger cleared")
  assert_eq(#Store:GetArchives(), 1, "archived")
  assert_eq(Store:GetArchives()[1].event.name, "Solo Run", "archive name")
  assert_true(Store:GetResetEpoch() > beforeEpoch, "epoch bumped on local end")

  -- When AcceptRemoteEvent tries to revive the archived id
  local revived, reviveErr = UC.AcceptRemoteEvent({
    getEvent = function()
      return Store:GetEvent()
    end,
    getArchives = function()
      return Store:GetArchives()
    end,
    setEvent = function(e)
      Store:SetEvent(e)
    end,
  }, oldEv, 0)
  assert_eq(revived, nil, "archived event rejected")
  assert_eq(reviveErr, "archived", "archived err")

  -- When broadcastReset is provided and clears via campaign scope
  local fresh = Fundraiser.Domain.Event.Create({
    name = "Fresh",
    target = "Bank Alt",
    goalCopper = 20000,
    intervalSeconds = 3600,
    minAdminRank = 1,
  })
  Store:SetEvent(fresh)
  Store:SetContributions({
    Ledger.CreateEntry({
      kind = "mail",
      name = "Donor",
      copper = 50,
      eventId = fresh.id,
      at = 2,
      detail = "y",
    }),
  })
  ended, endMode = UC.EndActiveEvent({
    getEvent = function()
      return Store:GetEvent()
    end,
    getContributions = function()
      return Store:GetContributions()
    end,
    getArchives = function()
      return Store:GetArchives()
    end,
    archiveEvent = function(event, contributions, archivedAt)
      Store:ArchiveEvent(event, contributions, archivedAt)
    end,
    applyResetScope = function(scope)
      return Store:ApplyResetScope(scope)
    end,
    broadcastReset = function(scope)
      broadcastScope = scope
      local ev = Store:GetEvent()
      if ev then
        Store:ArchiveEvent(ev, Store:GetContributions() or {}, 100)
      end
      Store:ApplyResetScope(scope)
      return true
    end,
  }, { rankIndex = 0, name = "GM", now = 100 })
  assert_true(ended, "end via broadcast ok")
  assert_eq(endMode, "guild", "guild mode")
  assert_eq(broadcastScope, "campaign", "broadcast campaign scope")
  assert_eq(Store:GetEvent(), nil, "event cleared after broadcast path")
  assert_eq(#Store:GetContributions(), 0, "ledger cleared after broadcast path")

  -- When not admin
  Store:SetEvent(fresh)
  ended, endMode = UC.EndActiveEvent({
    getEvent = function()
      return Store:GetEvent()
    end,
  }, { rankIndex = 5, name = "Member", now = 1 })
  assert_eq(ended, nil, "member end rejected")
  assert_eq(endMode, "not_admin", "member end err")
end

-- Scenario: ApplyResetScope campaign clears event and ledger
do
  dofile(repo .. "/fundraiser/Adapters/Store.lua")
  _G.FundraiserDB = nil
  local Store = Fundraiser.Adapters.Store
  Store.db = nil
  Store:Load()
  local ev = Fundraiser.Domain.Event.Create({
    name = "C",
    target = "Bank Alt",
    goalCopper = 1,
    intervalSeconds = 60,
    minAdminRank = 0,
  })
  Store:SetEvent(ev)
  Store:SetContributions({
    Ledger.CreateEntry({
      kind = "mail",
      name = "A",
      copper = 1,
      eventId = ev.id,
      at = 1,
      detail = "z",
    }),
  })
  local beforeEpoch = Store:GetResetEpoch()
  local ok = Store:ApplyResetScope("campaign")
  assert_true(ok, "campaign reset ok")
  assert_eq(Store:GetEvent(), nil, "campaign cleared event")
  assert_eq(#Store:GetContributions(), 0, "campaign cleared ledger")
  assert_true(Store:GetResetEpoch() > beforeEpoch, "campaign bumps epoch")
end

-- Scenario: Forever names require First Last
do
  -- Given single-token vs full names
  -- When validating / comparing
  assert_true(Roles.IsFullCharacterName("Jane Doe"), "full name ok")
  assert_true(not Roles.IsFullCharacterName("Jane"), "first only rejected")
  assert_true(Roles.NamesEqual("Jane Doe", "jane  doe"), "collapse spaces")
  assert_true(Roles.NamesEqual("Jane Doe-Realm", "Jane Doe"), "strip realm")
  local badTarget = Fundraiser.Domain.Event.Create({
    name = "X",
    target = "OnlyFirst",
    goalCopper = 1000,
    intervalSeconds = 3600,
    minAdminRank = 0,
  })
  -- Then event create rejects incomplete target
  assert_eq(badTarget, nil, "reject single-token target")
end

-- Scenario: SaleAdvice picks vendor / AH / manual
do
  -- Given price pairs
  -- When recommending
  assert_eq(Fundraiser.Domain.SaleAdvice.Recommend(100, 100, 1, 0.05), "vendor", "vendor wins vs cut AH")
  assert_eq(Fundraiser.Domain.SaleAdvice.Recommend(10, 100, 1, 0.05), "ah", "ah wins")
  assert_eq(Fundraiser.Domain.SaleAdvice.Recommend(nil, nil, 1, 0.05), "manual", "manual when no prices")
end

-- Scenario: FormatCopper embeds MoneyIcons (fallback when GetCoinTextureString is absent)
do
  -- Given a stub CreateFrame so Core.lua can load under pure Lua
  if not CreateFrame then
    function CreateFrame()
      return {
        RegisterEvent = function() end,
        SetScript = function() end,
      }
    end
  end
  dofile(repo .. "/fundraiser/Core.lua")
  -- When formatting exact gold and mixed amounts
  local goldOnly = Fundraiser.FormatCopper(220000)
  local mixed = Fundraiser.FormatCopper(12345)
  local zero = Fundraiser.FormatCopper(0)
  -- Then strings use inline coin textures, not ascii g/s/c suffixes
  assert_true(goldOnly:find("UI%-MoneyIcons", 1, false), "gold uses MoneyIcons")
  assert_true(goldOnly:find("^22|T"), "gold amount prefix")
  assert_true(not goldOnly:find("%dg"), "no ascii g")
  assert_true(mixed:find("UI%-MoneyIcons", 1, false), "mixed uses MoneyIcons")
  assert_true(zero:find("UI%-MoneyIcons", 1, false), "zero uses copper icon")
end

if failed > 0 then
  io.stderr:write(failed .. " failure(s)\n")
  os.exit(1)
end
print("test_domain: ok")
