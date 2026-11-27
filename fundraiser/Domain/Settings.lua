-- Pure helpers for Options defaults and install-presence display.
-- Normalize/ApplyToConfig: defaultReminderInterval (seconds) + defaultMinAdminRank + backupOnly.
-- BuildInstallRows/CountOnlineInstalls/BuildStatus: Options status section (no WoW API).
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local Settings = {}
Fundraiser.Domain.Settings = Settings

-- Reject non-positive interval and non-integer / negative rank before persisting.
function Settings.Normalize(raw)
  raw = raw or {}
  local interval = tonumber(raw.defaultReminderInterval)
  local rank = tonumber(raw.defaultMinAdminRank)
  if not interval or interval <= 0 then
    return nil, "bad_interval"
  end
  if rank == nil or rank < 0 or rank ~= math.floor(rank) then
    return nil, "bad_rank"
  end
  return {
    defaultReminderInterval = math.floor(interval),
    defaultMinAdminRank = math.floor(rank),
    backupOnly = raw.backupOnly == true,
  }
end

-- Defaults (interval, min admin rank) are guild-wide knobs: only admins edit them while
-- Config.DEFAULTS_ADMIN_ONLY is on. Personal choices (backupOnly) are not covered.
function Settings.CanEditDefaults(config, isAdmin)
  if type(config) ~= "table" or config.DEFAULTS_ADMIN_ONLY ~= true then
    return true
  end
  return isAdmin == true
end

-- "Only backup": the feature flag AND the saved choice (Config.BACKUP_ONLY overlay).
function Settings.IsBackupOnly(config)
  if type(config) ~= "table" then
    return false
  end
  return config.BACKUP_ONLY_OPTION == true and config.BACKUP_ONLY == true
end

function Settings.ApplyToConfig(settings, config)
  if not settings or not config then
    return
  end
  if settings.defaultReminderInterval then
    config.DEFAULT_REMINDER_INTERVAL = settings.defaultReminderInterval
  end
  if settings.defaultMinAdminRank ~= nil then
    config.DEFAULT_MIN_ADMIN_RANK = settings.defaultMinAdminRank
  end
  config.BACKUP_ONLY = settings.backupOnly == true
end

-- Online roster rows with install status + HELLO version (best-effort).
-- status: "installed" | "backup" (fresh HELLO flagged Only backup) | "stale" | "missing"
function Settings.BuildInstallRows(roster, presence, now, staleSeconds)
  roster = roster or {}
  presence = presence or {}
  now = tonumber(now) or 0
  staleSeconds = tonumber(staleSeconds) or 600
  local rows = {}
  for _, member in ipairs(roster) do
    if member and member.online then
      local p = presence[member.guid] or presence[member.name]
      local lastHello = p and tonumber(p.lastHello) or 0
      local status = "missing"
      local version = nil
      if lastHello > 0 then
        if (now - lastHello) <= staleSeconds then
          status = (p.backupOnly == true) and "backup" or "installed"
        else
          status = "stale"
        end
        if p and p.version and tostring(p.version) ~= "" then
          version = tostring(p.version)
        end
      end
      rows[#rows + 1] = {
        name = member.name or "?",
        status = status,
        version = version,
      }
    end
  end
  table.sort(rows, function(a, b)
    return tostring(a.name):lower() < tostring(b.name):lower()
  end)
  return rows
end

-- Count online guild members with a fresh HELLO (best-effort install presence).
-- Only-backup members are counted in `backup`, not in `installed`.
function Settings.CountOnlineInstalls(roster, presence, now, staleSeconds)
  local rows = Settings.BuildInstallRows(roster, presence, now, staleSeconds)
  local installed, backup = 0, 0
  for _, row in ipairs(rows) do
    if row.status == "installed" then
      installed = installed + 1
    elseif row.status == "backup" then
      backup = backup + 1
    end
  end
  local online = #rows
  return {
    online = online,
    installed = installed,
    backup = backup,
    missing = online - installed - backup,
    rows = rows,
  }
end

-- Build locale keys / display fragments for the Options status section.
function Settings.BuildStatus(info)
  info = info or {}
  local status = {
    enabledKey = info.enabled and "OPTIONS_STATUS_ENABLED_ON" or "OPTIONS_STATUS_ENABLED_OFF",
    accessKey = info.canOpenAdmin and "OPTIONS_STATUS_ACCESS_YES" or "OPTIONS_STATUS_ACCESS_NO",
  }
  if info.guildName and info.guildName ~= "" then
    status.guildText = info.guildName
  else
    status.guildKey = "OPTIONS_STATUS_GUILD_NONE"
  end
  if info.eventName and info.eventName ~= "" then
    local target = info.eventTarget or "?"
    -- ASCII separator: Forever UI fonts often miss Unicode arrows.
    status.eventText = string.format("%s -> %s", info.eventName, target)
  else
    status.eventKey = "OPTIONS_STATUS_EVENT_NONE"
  end
  if info.guildName and info.guildName ~= "" then
    status.installOnline = tonumber(info.installOnline) or 0
    status.installInstalled = tonumber(info.installInstalled) or 0
    status.installBackup = tonumber(info.installBackup) or 0
  else
    status.installKey = "OPTIONS_STATUS_INSTALL_NONE"
  end
  return status
end
