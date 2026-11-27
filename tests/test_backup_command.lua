-- Pure Lua tests for the /fundraiser backup slash command (parser + use case).
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Config.lua")
dofile(repo .. "/fundraiser/Domain/Settings.lua")
dofile(repo .. "/fundraiser/Application/UseCases.lua")

local failed = 0

local function assert_eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s (%s ~= %s)\n", msg or "assert_eq", tostring(a), tostring(b)))
  end
end

local Settings = Fundraiser.Domain.Settings
local UC = Fundraiser.Application.UseCases

-- Scenario: argument parsing
do
  -- Given a bare command or an explicit argument (any case, extra spaces)
  -- When parsing against the current value
  -- Then toggle flips, on/off set, status reports, anything else is invalid
  local a, v = Settings.ParseBackupCommand("", false)
  assert_eq(a, "set", "bare: action")
  assert_eq(v, true, "bare from off turns on")
  a, v = Settings.ParseBackupCommand("  ", true)
  assert_eq(v, false, "blank from on turns off")
  a, v = Settings.ParseBackupCommand("ON", false)
  assert_eq(a, "set", "on: action")
  assert_eq(v, true, "on: value")
  a, v = Settings.ParseBackupCommand("on", true)
  assert_eq(v, true, "on stays on")
  a, v = Settings.ParseBackupCommand(" Off ", true)
  assert_eq(v, false, "off: value")
  a, v = Settings.ParseBackupCommand("status", true)
  assert_eq(a, "status", "status: action")
  assert_eq(v, true, "status: current value")
  a = Settings.ParseBackupCommand("foo", false)
  assert_eq(a, "invalid", "garbage is invalid")
  a = Settings.ParseBackupCommand(nil, false)
  assert_eq(a, "set", "nil arg is a toggle")
end

local function makeDeps(opts)
  local saved = {}
  local state = { backupOnly = opts.backupOnly == true, hello = 0, saves = 0, refreshed = 0 }
  local deps = {
    isOptionEnabled = function()
      return opts.enabled ~= false
    end,
    getSettings = function()
      return { defaultReminderInterval = 7200, defaultMinAdminRank = 3, backupOnly = state.backupOnly }
    end,
    setSettings = function(raw)
      state.saves = state.saves + 1
      saved = raw
      state.backupOnly = raw.backupOnly
      return raw
    end,
    broadcastHello = function()
      state.hello = state.hello + 1
    end,
    refreshOptions = function()
      state.refreshed = state.refreshed + 1
    end,
  }
  return deps, state, function()
    return saved
  end
end

-- Scenario: toggle saves, keeps other settings, announces and refreshes
do
  -- Given the option is on and backup-only is off
  local deps, state, saved = makeDeps({ backupOnly = false })
  -- When toggling
  local outcome, value = UC.SetBackupOnlyFromCommand(deps, "")
  -- Then it saves true, keeps interval and rank, sends HELLO, refreshes Options
  assert_eq(outcome, "changed", "toggle outcome")
  assert_eq(value, true, "toggle value")
  assert_eq(saved().backupOnly, true, "saved backupOnly")
  assert_eq(saved().defaultReminderInterval, 7200, "interval kept")
  assert_eq(saved().defaultMinAdminRank, 3, "rank kept")
  assert_eq(state.hello, 1, "hello sent once")
  assert_eq(state.refreshed, 1, "options refreshed once")
end

-- Scenario: status does not change anything
do
  local deps, state = makeDeps({ backupOnly = true })
  local outcome, value = UC.SetBackupOnlyFromCommand(deps, "status")
  assert_eq(outcome, "status", "status outcome")
  assert_eq(value, true, "status value")
  assert_eq(state.saves, 0, "status does not save")
  assert_eq(state.hello, 0, "status does not send HELLO")
end

-- Scenario: invalid argument changes nothing
do
  local deps, state = makeDeps({ backupOnly = false })
  local outcome = UC.SetBackupOnlyFromCommand(deps, "foo")
  assert_eq(outcome, "invalid", "invalid outcome")
  assert_eq(state.saves, 0, "invalid does not save")
end

-- Scenario: feature flag off is a no-op
do
  local deps, state = makeDeps({ backupOnly = false, enabled = false })
  local outcome = UC.SetBackupOnlyFromCommand(deps, "on")
  assert_eq(outcome, "disabled", "disabled outcome")
  assert_eq(state.saves, 0, "disabled does not save")
  assert_eq(state.hello, 0, "disabled does not send HELLO")
end

-- Scenario: a failed save is reported and sends nothing
do
  local deps, state = makeDeps({ backupOnly = false })
  deps.setSettings = function()
    return nil, "boom"
  end
  local outcome, err = UC.SetBackupOnlyFromCommand(deps, "on")
  assert_eq(outcome, "error", "error outcome")
  assert_eq(err, "boom", "error value")
  assert_eq(state.hello, 0, "no HELLO after failed save")
end

if failed > 0 then
  io.stderr:write(failed .. " failure(s)\n")
  os.exit(1)
end
print("test_backup_command: ok")
