-- Pure Lua tests for Options settings overlay + global min admin rank.
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

-- Normalize / validate
local ok, err = Settings.Normalize({
  defaultReminderInterval = 3600,
  defaultMinAdminRank = 2,
})
assert_true(ok, "normalize ok")
assert_eq(ok.defaultReminderInterval, 3600, "interval kept")
assert_eq(ok.defaultMinAdminRank, 2, "rank kept")

ok, err = Settings.Normalize({ defaultReminderInterval = 0, defaultMinAdminRank = 0 })
assert_eq(ok, nil, "reject zero interval")
assert_eq(err, "bad_interval", "zero interval err")

ok, err = Settings.Normalize({ defaultReminderInterval = -1, defaultMinAdminRank = 0 })
assert_eq(ok, nil, "reject negative interval")

ok, err = Settings.Normalize({ defaultReminderInterval = 100, defaultMinAdminRank = -1 })
assert_eq(ok, nil, "reject negative rank")
assert_eq(err, "bad_rank", "negative rank err")

ok, err = Settings.Normalize({ defaultReminderInterval = "nope", defaultMinAdminRank = 1 })
assert_eq(ok, nil, "reject non-number interval")

-- ApplyToConfig
Fundraiser.Config.DEFAULT_REMINDER_INTERVAL = 86400
Fundraiser.Config.DEFAULT_MIN_ADMIN_RANK = 1
Settings.ApplyToConfig({
  defaultReminderInterval = 7200,
  defaultMinAdminRank = 3,
}, Fundraiser.Config)
assert_eq(Fundraiser.Config.DEFAULT_REMINDER_INTERVAL, 7200, "apply interval")
assert_eq(Fundraiser.Config.DEFAULT_MIN_ADMIN_RANK, 3, "apply rank")

-- Store overlay from SavedVariables-like table
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
local Store = Fundraiser.Adapters.Store
Store:Load()
assert_eq(Fundraiser.Config.DEFAULT_REMINDER_INTERVAL, 1800, "load overlays interval")
assert_eq(Fundraiser.Config.DEFAULT_MIN_ADMIN_RANK, 0, "load overlays rank")

local saved, saveErr = Store:SetSettings({
  defaultReminderInterval = 900,
  defaultMinAdminRank = 2,
})
assert_true(saved, "set settings")
assert_eq(saveErr, nil, "set settings no err")
assert_eq(Fundraiser.Config.DEFAULT_REMINDER_INTERVAL, 900, "set applies interval")
assert_eq(Fundraiser.Config.DEFAULT_MIN_ADMIN_RANK, 2, "set applies rank")
assert_eq(Store:GetSettings().defaultReminderInterval, 900, "get settings interval")

local bad, badErr = Store:SetSettings({
  defaultReminderInterval = 0,
  defaultMinAdminRank = 1,
})
assert_eq(bad, nil, "reject bad set")
assert_eq(badErr, "bad_interval", "bad set err")
assert_eq(Fundraiser.Config.DEFAULT_REMINDER_INTERVAL, 900, "bad set leaves config")

-- Roles always use Config, ignore event.minAdminRank
Fundraiser.Config.DEFAULT_MIN_ADMIN_RANK = 1
local evHigh = { minAdminRank = 9, target = "Bank Alt" }
assert_true(Fundraiser.Domain.Roles.CanManageFundraiser(1, evHigh), "rank 1 manages via Config")
assert_true(not Fundraiser.Domain.Roles.CanManageFundraiser(2, evHigh), "rank 2 blocked via Config despite event 9")
assert_true(Fundraiser.Domain.Roles.CanManageFundraiser(1, nil), "nil event uses Config")
assert_true(not Fundraiser.Domain.Roles.CanAcceptLedgerFrom(evHigh, "Peer", 5), "ledger accept uses Config not event 9")
assert_true(Fundraiser.Domain.Roles.CanAcceptLedgerFrom(evHigh, "Peer", 1), "ledger accept rank 1 ok")

-- Status helper labels
local status = Settings.BuildStatus({
  enabled = true,
  guildName = "Test Guild",
  eventName = "Tabard",
  eventTarget = "Bank Alt",
  canOpenAdmin = true,
})
assert_eq(status.enabledKey, "OPTIONS_STATUS_ENABLED_ON", "enabled on key")
assert_eq(status.guildText, "Test Guild", "guild text")
assert_eq(status.eventText, "Tabard → Bank Alt", "event text")
assert_eq(status.accessKey, "OPTIONS_STATUS_ACCESS_YES", "access yes")

status = Settings.BuildStatus({
  enabled = false,
  guildName = nil,
  eventName = nil,
  eventTarget = nil,
  canOpenAdmin = false,
})
assert_eq(status.enabledKey, "OPTIONS_STATUS_ENABLED_OFF", "enabled off key")
assert_eq(status.guildKey, "OPTIONS_STATUS_GUILD_NONE", "no guild key")
assert_eq(status.eventKey, "OPTIONS_STATUS_EVENT_NONE", "no event key")
assert_eq(status.accessKey, "OPTIONS_STATUS_ACCESS_NO", "access no")

-- Online install rows + counts (fresh HELLO = installed; version from presence)
local rows = Settings.BuildInstallRows({
  { name = "Cee", guid = "g3", online = true },
  { name = "A", guid = "g1", online = true },
  { name = "B", guid = "g2", online = true },
  { name = "D", guid = "g4", online = false },
}, {
  g1 = { lastHello = 1000, version = "0.1.0" },
  ["B"] = { lastHello = 1000, version = "0.2.0" },
  g3 = { lastHello = 100, version = "0.0.1" },
}, 1000, 600)
assert_eq(#rows, 3, "online rows only")
assert_eq(rows[1].name, "A", "sorted by name")
assert_eq(rows[1].status, "installed", "A installed")
assert_eq(rows[1].version, "0.1.0", "A version")
assert_eq(rows[2].status, "installed", "B installed")
assert_eq(rows[3].status, "stale", "Cee stale")
assert_eq(rows[3].version, "0.0.1", "stale keeps version")

local missingRows = Settings.BuildInstallRows({
  { name = "Zed", guid = "gz", online = true },
}, {}, 1000, 600)
assert_eq(missingRows[1].status, "missing", "no hello = missing")
assert_eq(missingRows[1].version, nil, "missing has no version")

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
assert_eq(counts.online, 3, "online count")
assert_eq(counts.installed, 2, "installed fresh hello")
assert_eq(counts.missing, 1, "missing or stale")
assert_eq(#counts.rows, 3, "counts includes rows")

counts = Settings.CountOnlineInstalls({}, {}, 1000, 600)
assert_eq(counts.online, 0, "empty roster online")
assert_eq(counts.installed, 0, "empty roster installed")

status = Settings.BuildStatus({
  enabled = true,
  guildName = "G",
  canOpenAdmin = true,
  installOnline = 3,
  installInstalled = 2,
})
assert_eq(status.installOnline, 3, "status online")
assert_eq(status.installInstalled, 2, "status installed")
assert_eq(status.installKey, nil, "has counts not empty key")

status = Settings.BuildStatus({
  enabled = true,
  guildName = nil,
  canOpenAdmin = false,
})
assert_eq(status.installKey, "OPTIONS_STATUS_INSTALL_NONE", "no guild install key")

if failed > 0 then
  io.stderr:write(failed .. " failure(s)\n")
  os.exit(1)
end
print("test_options_settings: ok")
