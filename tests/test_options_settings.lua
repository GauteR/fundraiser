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

if failed > 0 then
  io.stderr:write(failed .. " failure(s)\n")
  os.exit(1)
end
print("test_options_settings: ok")
