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
  return status
end
