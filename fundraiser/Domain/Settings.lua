-- Pure helpers for Options defaults (interval + global min admin rank).
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local Settings = {}
Fundraiser.Domain.Settings = Settings

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
  }
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
end

-- Count online guild members with a fresh HELLO (best-effort install presence).
function Settings.CountOnlineInstalls(roster, presence, now, staleSeconds)
  roster = roster or {}
  presence = presence or {}
  now = tonumber(now) or 0
  staleSeconds = tonumber(staleSeconds) or 600
  local online = 0
  local installed = 0
  for _, member in ipairs(roster) do
    if member and member.online then
      online = online + 1
      local p = presence[member.guid] or presence[member.name]
      local lastHello = p and tonumber(p.lastHello) or 0
      if lastHello > 0 and (now - lastHello) <= staleSeconds then
        installed = installed + 1
      end
    end
  end
  return {
    online = online,
    installed = installed,
    missing = online - installed,
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
    status.eventText = string.format("%s → %s", info.eventName, target)
  else
    status.eventKey = "OPTIONS_STATUS_EVENT_NONE"
  end
  if info.guildName and info.guildName ~= "" then
    status.installOnline = tonumber(info.installOnline) or 0
    status.installInstalled = tonumber(info.installInstalled) or 0
  else
    status.installKey = "OPTIONS_STATUS_INSTALL_NONE"
  end
  return status
end
