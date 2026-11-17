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
  }
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
  self.db = db
  return db
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
