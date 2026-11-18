-- Pure Lua tests for Options settings, install presence, and Store cleanup.
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Config.lua")
dofile(repo .. "/fundraiser/Locale/enUS.lua")
dofile(repo .. "/fundraiser/Domain/Rank.lua")
dofile(repo .. "/fundraiser/Domain/Roles.lua")
dofile(repo .. "/fundraiser/Domain/Settings.lua")
dofile(repo .. "/fundraiser/Adapters/Store.lua")

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

local Settings = Fundraiser.Domain.Settings
local Store = Fundraiser.Adapters.Store

-- Scenario: Normalize accepts valid Options defaults
do
  -- Given valid interval (seconds) and min admin rank
  local raw = { defaultReminderInterval = 3600, defaultMinAdminRank = 2 }
  -- When normalizing
  local ok, err = Settings.Normalize(raw)
  -- Then values are kept as floored numbers
  assert_true(ok, "normalize ok")
  assert_eq(err, nil, "normalize no err")
  assert_eq(ok.defaultReminderInterval, 3600, "interval kept")
  assert_eq(ok.defaultMinAdminRank, 2, "rank kept")
end

-- Scenario: Normalize rejects invalid interval / rank
do
  -- Given zero interval
  local ok, err = Settings.Normalize({ defaultReminderInterval = 0, defaultMinAdminRank = 0 })
  -- When/Then rejected as bad_interval
  assert_eq(ok, nil, "reject zero interval")
  assert_eq(err, "bad_interval", "zero interval err")

  -- Given negative interval
  ok, err = Settings.Normalize({ defaultReminderInterval = -1, defaultMinAdminRank = 0 })
  assert_eq(ok, nil, "reject negative interval")

  -- Given negative rank
  ok, err = Settings.Normalize({ defaultReminderInterval = 100, defaultMinAdminRank = -1 })
  assert_eq(ok, nil, "reject negative rank")
  assert_eq(err, "bad_rank", "negative rank err")

  -- Given non-numeric interval
  ok, err = Settings.Normalize({ defaultReminderInterval = "nope", defaultMinAdminRank = 1 })
  assert_eq(ok, nil, "reject non-number interval")
end

-- Scenario: ApplyToConfig overlays runtime Config used by Roles/reminders
do
  -- Given file-like Config defaults
  Fundraiser.Config.DEFAULT_REMINDER_INTERVAL = 86400
  Fundraiser.Config.DEFAULT_MIN_ADMIN_RANK = 1
  -- When applying Options settings
  Settings.ApplyToConfig({
    defaultReminderInterval = 7200,
    defaultMinAdminRank = 3,
  }, Fundraiser.Config)
  -- Then Config reflects Options values
  assert_eq(Fundraiser.Config.DEFAULT_REMINDER_INTERVAL, 7200, "apply interval")
  assert_eq(Fundraiser.Config.DEFAULT_MIN_ADMIN_RANK, 3, "apply rank")
end

-- Scenario: Store Load overlays SavedVariables settings onto Config
do
  -- Given FundraiserDB.settings from a previous session
  _G.FundraiserDB = {
    event = nil,
    contributions = {},
    presence = {},
    reminder = {},
    settings = {
      defaultReminderInterval = 1800,
      defaultMinAdminRank = 0,
    },
  }
  Fundraiser.Config.DEFAULT_REMINDER_INTERVAL = 86400
  Fundraiser.Config.DEFAULT_MIN_ADMIN_RANK = 1
  Store.db = nil
  -- When loading Store
  Store:Load()
  -- Then Config is overlaid from SV
  assert_eq(Fundraiser.Config.DEFAULT_REMINDER_INTERVAL, 1800, "load overlays interval")
  assert_eq(Fundraiser.Config.DEFAULT_MIN_ADMIN_RANK, 0, "load overlays rank")
end

-- Scenario: SetSettings persists and rejects invalid input without mutating Config
do
  -- Given a loaded store (from previous scenario) with overlaid settings
  -- When saving valid settings
  local saved, saveErr = Store:SetSettings({
    defaultReminderInterval = 900,
    defaultMinAdminRank = 2,
  })
  -- Then persist + Config update succeed
  assert_true(saved, "set settings")
  assert_eq(saveErr, nil, "set settings no err")
  assert_eq(Fundraiser.Config.DEFAULT_REMINDER_INTERVAL, 900, "set applies interval")
  assert_eq(Fundraiser.Config.DEFAULT_MIN_ADMIN_RANK, 2, "set applies rank")
  assert_eq(Store:GetSettings().defaultReminderInterval, 900, "get settings interval")

  -- When saving invalid settings
  local bad, badErr = Store:SetSettings({
    defaultReminderInterval = 0,
    defaultMinAdminRank = 1,
  })
  -- Then reject and leave Config unchanged
  assert_eq(bad, nil, "reject bad set")
  assert_eq(badErr, "bad_interval", "bad set err")
  assert_eq(Fundraiser.Config.DEFAULT_REMINDER_INTERVAL, 900, "bad set leaves config")
end

-- Scenario: Roles ignore event.minAdminRank and use global Config
do
  -- Given Config min rank 1 and an event claiming minAdminRank 9
  Fundraiser.Config.DEFAULT_MIN_ADMIN_RANK = 1
  local evHigh = { minAdminRank = 9, target = "Bank Alt" }
  -- When checking manage / ledger-accept gates
  -- Then only Config rank matters
  assert_true(Fundraiser.Domain.Roles.CanManageFundraiser(1, evHigh), "rank 1 manages via Config")
  assert_true(not Fundraiser.Domain.Roles.CanManageFundraiser(2, evHigh), "rank 2 blocked via Config despite event 9")
  assert_true(Fundraiser.Domain.Roles.CanManageFundraiser(1, nil), "nil event uses Config")
  assert_true(not Fundraiser.Domain.Roles.CanAcceptLedgerFrom(evHigh, "Peer", 5), "ledger accept uses Config not event 9")
  assert_true(Fundraiser.Domain.Roles.CanAcceptLedgerFrom(evHigh, "Peer", 1), "ledger accept rank 1 ok")
end

-- Scenario: BuildStatus maps runtime info to locale keys / display text
do
  -- Given an enabled guild character with an active event and admin access
  local status = Settings.BuildStatus({
    enabled = true,
    guildName = "Test Guild",
    eventName = "Tabard",
    eventTarget = "Bank Alt",
    canOpenAdmin = true,
  })
  -- Then status fragments are filled for Options rows
  assert_eq(status.enabledKey, "OPTIONS_STATUS_ENABLED_ON", "enabled on key")
  assert_eq(status.guildText, "Test Guild", "guild text")
  assert_eq(status.eventText, "Tabard -> Bank Alt", "event text")
  assert_eq(status.accessKey, "OPTIONS_STATUS_ACCESS_YES", "access yes")

  -- Given disabled / no guild / no event
  status = Settings.BuildStatus({
    enabled = false,
    guildName = nil,
    eventName = nil,
    eventTarget = nil,
    canOpenAdmin = false,
  })
  -- Then fallback locale keys are used
  assert_eq(status.enabledKey, "OPTIONS_STATUS_ENABLED_OFF", "enabled off key")
  assert_eq(status.guildKey, "OPTIONS_STATUS_GUILD_NONE", "no guild key")
  assert_eq(status.eventKey, "OPTIONS_STATUS_EVENT_NONE", "no event key")
  assert_eq(status.accessKey, "OPTIONS_STATUS_ACCESS_NO", "access no")
  assert_eq(status.installKey, "OPTIONS_STATUS_INSTALL_NONE", "no guild install key")
end

-- Scenario: BuildInstallRows lists online members with HELLO-based status + version
do
  -- Given mixed online/offline roster and presence HELLO ages
  local roster = {
    { name = "Cee", guid = "g3", online = true },
    { name = "A", guid = "g1", online = true },
    { name = "B", guid = "g2", online = true },
    { name = "D", guid = "g4", online = false },
  }
  local presence = {
    g1 = { lastHello = 1000, version = "0.1.0" },
    ["B"] = { lastHello = 1000, version = "0.2.0" },
    g3 = { lastHello = 100, version = "0.0.1" },
  }
  -- When building rows at now=1000 with stale window 600s
  local rows = Settings.BuildInstallRows(roster, presence, 1000, 600)
  -- Then only online members appear, sorted, with correct status/version
  assert_eq(#rows, 3, "online rows only")
  assert_eq(rows[1].name, "A", "sorted by name")
  assert_eq(rows[1].status, "installed", "A installed")
  assert_eq(rows[1].version, "0.1.0", "A version")
  assert_eq(rows[2].status, "installed", "B installed")
  assert_eq(rows[3].status, "stale", "Cee stale")
  assert_eq(rows[3].version, "0.0.1", "stale keeps version")

  -- Given online member with no HELLO
  local missingRows = Settings.BuildInstallRows({
    { name = "Zed", guid = "gz", online = true },
  }, {}, 1000, 600)
  -- Then status is missing and version is nil
  assert_eq(missingRows[1].status, "missing", "no hello = missing")
  assert_eq(missingRows[1].version, nil, "missing has no version")
end

-- Scenario: CountOnlineInstalls summarizes BuildInstallRows
do
  -- Given the same presence mix as above
  local counts = Settings.CountOnlineInstalls({
    { name = "A", guid = "g1", online = true },
    { name = "B", guid = "g2", online = true },
    { name = "C", guid = "g3", online = true },
    { name = "D", guid = "g4", online = false },
  }, {
    g1 = { lastHello = 1000 },
    ["B"] = { lastHello = 1000 },
    g3 = { lastHello = 100 },
  }, 1000, 600)
  -- Then installed = fresh HELLO only
  assert_eq(counts.online, 3, "online count")
  assert_eq(counts.installed, 2, "installed fresh hello")
  assert_eq(counts.missing, 1, "missing or stale")
  assert_eq(#counts.rows, 3, "counts includes rows")

  -- Given empty roster
  counts = Settings.CountOnlineInstalls({}, {}, 1000, 600)
  -- Then zeros
  assert_eq(counts.online, 0, "empty roster online")
  assert_eq(counts.installed, 0, "empty roster installed")
end

-- Scenario: BuildStatus includes install summary counts when in a guild
do
  -- Given guild + install counts
  local status = Settings.BuildStatus({
    enabled = true,
    guildName = "G",
    canOpenAdmin = true,
    installOnline = 3,
    installInstalled = 2,
  })
  -- Then numeric summary is present (not the none-key)
  assert_eq(status.installOnline, 3, "status online")
  assert_eq(status.installInstalled, 2, "status installed")
  assert_eq(status.installKey, nil, "has counts not empty key")
end

-- Scenario: Store cleanup clears scoped data; ResetAll restores Config file defaults
do
  -- Given populated SV and overlaid Config
  Fundraiser.ConfigFileDefaults = {
    DEFAULT_REMINDER_INTERVAL = 86400,
    DEFAULT_MIN_ADMIN_RANK = 1,
  }
  _G.FundraiserDB = {
    event = { name = "X", target = "Bank Alt" },
    contributions = { { id = "1" } },
    presence = { g1 = { lastHello = 1 } },
    reminder = { lastDismissedAt = 1 },
    settings = { defaultReminderInterval = 900, defaultMinAdminRank = 3 },
  }
  Fundraiser.Config.DEFAULT_REMINDER_INTERVAL = 900
  Fundraiser.Config.DEFAULT_MIN_ADMIN_RANK = 3
  Store.db = nil
  Store:Load()
  assert_eq(Store:GetEvent().name, "X", "loaded event before cleanup")

  -- When clearing presence / ledger / event
  Store:ClearPresence()
  -- Then presence is empty
  assert_eq(next(Store:GetPresence()), nil, "presence cleared")
  Store:ClearLedger()
  assert_eq(#Store:GetContributions(), 0, "ledger cleared")
  Store:ClearEvent()
  assert_eq(Store:GetEvent(), nil, "event cleared")
  assert_eq(next(Store:GetReminderState()) == nil, true, "reminder cleared with event")

  -- Given another dirty DB
  _G.FundraiserDB = {
    event = { name = "Y" },
    contributions = { { id = "2" } },
    presence = { g2 = { lastHello = 2 } },
    reminder = { x = 1 },
    settings = { defaultReminderInterval = 1200, defaultMinAdminRank = 4 },
  }
  Store.db = nil
  Store:Load()
  -- When ResetAll
  Store:ResetAll()
  -- Then SV is empty and Config file defaults are restored
  assert_eq(Store:GetEvent(), nil, "reset clears event")
  assert_eq(#Store:GetContributions(), 0, "reset clears ledger")
  assert_eq(next(Store:GetPresence()), nil, "reset clears presence")
  assert_eq(Store:GetSettings().defaultReminderInterval, 86400, "reset settings fall back to file")
  assert_eq(Store:GetSettings().defaultMinAdminRank, 1, "reset settings rank fall back")
  assert_eq(Fundraiser.Config.DEFAULT_REMINDER_INTERVAL, 86400, "reset restores config interval")
  assert_eq(Fundraiser.Config.DEFAULT_MIN_ADMIN_RANK, 1, "reset restores config rank")
end

if failed > 0 then
  io.stderr:write(failed .. " failure(s)\n")
  os.exit(1)
end
print("test_options_settings: ok")
