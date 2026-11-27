-- Local cache (SavedVariables FundraiserDB) with cold-start tolerant defaults.
-- target: persistent target page prefs (ignore list, min stack value).
-- settings: Options overlays for reminder interval + min admin rank (applied onto Config).
-- archives: capped history of replaced events (publish / remote EVENT with new id).
-- resetEpoch: monotonic counter bumped on ledger/all wipe; stamped on HELLO/LEDGER/DIGEST/RESET.
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local Store = {}
Fundraiser.Adapters.Store = Store

local MAX_ARCHIVES = 25

local function emptyDb()
  return {
    event = nil,
    contributions = {},
    -- Donated items waiting to be sold (Domain/ItemLots.lua); local only, not shared.
    lots = {},
    presence = {},
    reminder = {},
    settings = {},
    -- Target page preferences (Domain/TargetPrefs.lua): ignored item ids + min stack value.
    target = {},
    archives = {},
    resetEpoch = 0,
  }
end

-- Fall back to Config.lua when FundraiserDB.settings is empty (first load / after ResetAll).
local function defaultSettingsFromConfig()
  local cfg = Fundraiser.Config or {}
  return {
    defaultReminderInterval = tonumber(cfg.DEFAULT_REMINDER_INTERVAL) or 86400,
    defaultMinAdminRank = tonumber(cfg.DEFAULT_MIN_ADMIN_RANK) or 0,
    backupOnly = cfg.BACKUP_ONLY_DEFAULT == true,
  }
end

local function copyTable(t)
  if type(t) ~= "table" then
    return t
  end
  local out = {}
  for k, v in pairs(t) do
    if type(v) == "table" then
      out[k] = copyTable(v)
    else
      out[k] = v
    end
  end
  return out
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
  db.lots = db.lots or {}
  db.presence = db.presence or {}
  db.reminder = db.reminder or {}
  db.settings = db.settings or {}
  db.target = db.target or {}
  db.archives = db.archives or {}
  db.resetEpoch = tonumber(db.resetEpoch) or 0
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
    backupOnly = (type(stored.backupOnly) == "boolean") and stored.backupOnly or defaults.backupOnly,
  }
end

function Store:SetSettings(raw)
  local Settings = Fundraiser.Domain and Fundraiser.Domain.Settings
  if not Settings or not Settings.Normalize then
    return nil, "no_settings"
  end
  raw = raw or {}
  -- A caller that omits backupOnly keeps the current choice.
  if raw.backupOnly == nil then
    raw.backupOnly = self:GetSettings().backupOnly
  end
  -- Non-admins keep the stored interval/rank (only their personal choices are saved).
  -- Without the Core admin check (bare tests) nothing is restricted.
  local isAdmin = true
  if Fundraiser.CanOpenAdminUi then
    isAdmin = Fundraiser:CanOpenAdminUi() == true
  end
  if not Settings.CanEditDefaults(Fundraiser.Config, isAdmin) then
    local current = self:GetSettings()
    raw.defaultReminderInterval = current.defaultReminderInterval
    raw.defaultMinAdminRank = current.defaultMinAdminRank
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

-- Target page preferences, always a clean table (see Domain/TargetPrefs.lua).
function Store:GetTargetPrefs()
  self.db = self.db or self:Load()
  local TP = Fundraiser.Domain and Fundraiser.Domain.TargetPrefs
  if TP then
    self.db.target = TP.Normalize(self.db.target)
  end
  return self.db.target
end

-- Persist prefs after changing the table GetTargetPrefs returned (or a new one).
function Store:SetTargetPrefs(prefs)
  self.db = self.db or self:Load()
  local TP = Fundraiser.Domain and Fundraiser.Domain.TargetPrefs
  self.db.target = TP and TP.Normalize(prefs) or {}
  return self.db.target
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

function Store:GetLots()
  self.db = self.db or self:Load()
  self.db.lots = self.db.lots or {}
  return self.db.lots
end

function Store:SetLots(list)
  self.db = self.db or self:Load()
  self.db.lots = list or {}
end

-- Listeners run after every SetContributions (mail, sales, AH, guild sync, manual rows).
local contributionListeners = {}

function Store:OnContributionsChanged(fn)
  contributionListeners[#contributionListeners + 1] = fn
end

function Store:SetContributions(list)
  self.db = self.db or self:Load()
  self.db.contributions = list or {}
  for _, fn in ipairs(contributionListeners) do
    fn()
  end
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

function Store:GetArchives()
  self.db = self.db or self:Load()
  return self.db.archives or {}
end

function Store:GetResetEpoch()
  self.db = self.db or self:Load()
  return tonumber(self.db.resetEpoch) or 0
end

function Store:SetResetEpoch(epoch)
  self.db = self.db or self:Load()
  self.db.resetEpoch = math.max(0, math.floor(tonumber(epoch) or 0))
  return self.db.resetEpoch
end

function Store:BumpResetEpoch()
  return self:SetResetEpoch(self:GetResetEpoch() + 1)
end

-- Keep previous event + its ledger rows for later reference (capped).
function Store:ArchiveEvent(event, contributions, archivedAt)
  if not event then
    return nil
  end
  self.db = self.db or self:Load()
  self.db.archives = self.db.archives or {}
  local rows = contributions or {}
  local Ledger = Fundraiser.Domain and Fundraiser.Domain.Ledger
  if Ledger and Ledger.FilterByEvent and event.id then
    rows = Ledger.FilterByEvent(rows, event.id)
  end
  local entry = {
    event = copyTable(event),
    contributions = copyTable(rows),
    archivedAt = tonumber(archivedAt) or 0,
  }
  self.db.archives[#self.db.archives + 1] = entry
  while #self.db.archives > MAX_ARCHIVES do
    table.remove(self.db.archives, 1)
  end
  return entry
end

function Store:RestoreConfigFileDefaults()
  local cfg = Fundraiser.Config
  local file = Fundraiser.ConfigFileDefaults
  if not cfg or not file then
    return
  end
  if file.DEFAULT_REMINDER_INTERVAL ~= nil then
    cfg.DEFAULT_REMINDER_INTERVAL = file.DEFAULT_REMINDER_INTERVAL
  end
  if file.DEFAULT_MIN_ADMIN_RANK ~= nil then
    cfg.DEFAULT_MIN_ADMIN_RANK = file.DEFAULT_MIN_ADMIN_RANK
  end
end

-- Wipe SavedVariables to empty defaults and restore Config file defaults for Options overlays.
function Store:ResetAll()
  local name = (Fundraiser.Config and Fundraiser.Config.SAVED_VARIABLE) or "FundraiserDB"
  local db = emptyDb()
  _G[name] = db
  self.db = db
  self:RestoreConfigFileDefaults()
  self:ApplySettingsToConfig()
  return db
end

function Store:ClearPresence()
  self.db = self.db or self:Load()
  self.db.presence = {}
  return self.db.presence
end

function Store:ClearLedger()
  self.db = self.db or self:Load()
  self.db.contributions = {}
  self.db.lots = {}
  return self.db.contributions
end

function Store:ClearEvent()
  self.db = self.db or self:Load()
  self.db.event = nil
  self.db.reminder = {}
  return true
end

-- scope: all | event | ledger | presence | campaign (event + ledger)
-- forcedEpoch: set ledger epoch when wiping ledger/all/campaign (remote RESET).
function Store:ApplyResetScope(scope, forcedEpoch)
  scope = tostring(scope or "all")
  local bumpEpoch = scope == "all" or scope == "ledger" or scope == "campaign"
  if scope == "all" then
    self:ResetAll()
  elseif scope == "campaign" then
    self:ClearEvent()
    self:ClearLedger()
  elseif scope == "event" then
    self:ClearEvent()
  elseif scope == "ledger" then
    self:ClearLedger()
  elseif scope == "presence" then
    self:ClearPresence()
  else
    return nil, "bad_scope"
  end
  if bumpEpoch then
    if forcedEpoch ~= nil then
      self:SetResetEpoch(math.max(self:GetResetEpoch(), tonumber(forcedEpoch) or 0))
    else
      self:BumpResetEpoch()
    end
  end
  return true, self:GetResetEpoch()
end
