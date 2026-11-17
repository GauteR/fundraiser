-- Local cache (SavedVariables FundraiserDB) with cold-start tolerant defaults.
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local Store = {}
Fundraiser.Adapters.Store = Store

local function emptyDb()
  return {
    event = nil,
    contributions = {},
    presence = {},
    reminder = {},
    settings = {},
  }
end

local function defaultSettingsFromConfig()
  local cfg = Fundraiser.Config or {}
  return {
    defaultReminderInterval = tonumber(cfg.DEFAULT_REMINDER_INTERVAL) or 86400,
    defaultMinAdminRank = tonumber(cfg.DEFAULT_MIN_ADMIN_RANK) or 0,
  }
end

function Store:ApplySettingsToConfig()
  local Settings = Fundraiser.Domain and Fundraiser.Domain.Settings
  local settings = self:GetSettings()
  if Settings and Settings.ApplyToConfig and Fundraiser.Config then
    Settings.ApplyToConfig(settings, Fundraiser.Config)
  end
end

function Store:Load()
  local name = (Fundraiser.Config and Fundraiser.Config.SAVED_VARIABLE) or "FundraiserDB"
  local db = _G[name]
  if type(db) ~= "table" then
    db = emptyDb()
    _G[name] = db
  end
  db.contributions = db.contributions or {}
  db.presence = db.presence or {}
  db.reminder = db.reminder or {}
  db.settings = db.settings or {}
  self.db = db
  self:ApplySettingsToConfig()
  return db
end

function Store:GetSettings()
  self.db = self.db or self:Load()
  local stored = self.db.settings or {}
  local defaults = defaultSettingsFromConfig()
  return {
    defaultReminderInterval = tonumber(stored.defaultReminderInterval) or defaults.defaultReminderInterval,
    defaultMinAdminRank = tonumber(stored.defaultMinAdminRank) or defaults.defaultMinAdminRank,
  }
end

function Store:SetSettings(raw)
  local Settings = Fundraiser.Domain and Fundraiser.Domain.Settings
  if not Settings or not Settings.Normalize then
    return nil, "no_settings"
  end
  local normalized, err = Settings.Normalize(raw)
  if not normalized then
    return nil, err
  end
  self.db = self.db or self:Load()
  self.db.settings = normalized
  self:ApplySettingsToConfig()
  return normalized
end

function Store:GetEvent()
  return self.db and self.db.event or nil
end

function Store:SetEvent(event)
  self.db = self.db or self:Load()
  self.db.event = event
end

function Store:GetContributions()
  self.db = self.db or self:Load()
  return self.db.contributions
end

function Store:SetContributions(list)
  self.db = self.db or self:Load()
  self.db.contributions = list or {}
end

function Store:GetPresence()
  self.db = self.db or self:Load()
  return self.db.presence
end

function Store:SetPresenceEntry(key, entry)
  self.db = self.db or self:Load()
  self.db.presence[key] = entry
end

function Store:GetReminderState()
  self.db = self.db or self:Load()
  return self.db.reminder
end

function Store:SetReminderState(state)
  self.db = self.db or self:Load()
  self.db.reminder = state or {}
end
