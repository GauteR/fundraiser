-- Domain: persistent preferences of the target page. A per-item ignore list (keyed by item id)
-- and an optional minimum stack value that overrides Config.MIN_STACK_VALUE_COPPER.
-- Pure Lua: no WoW API. The Store keeps the table; this module only shapes and reads it.
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local TargetPrefs = {}
Fundraiser.Domain.TargetPrefs = TargetPrefs

local function validItemId(id)
  id = tonumber(id)
  if id and id >= 1 and id == math.floor(id) then
    return id
  end
  return nil
end

local function validMinValue(value)
  value = tonumber(value)
  if value and value >= 0 and value == value and value ~= math.huge then
    return math.floor(value)
  end
  return nil
end

-- Any saved value in, a clean { ignored = { [itemId] = name }, minValue = copper|nil } out.
function TargetPrefs.Normalize(raw)
  local prefs = { ignored = {}, minValue = nil }
  if type(raw) ~= "table" then
    return prefs
  end
  if type(raw.ignored) == "table" then
    for id, name in pairs(raw.ignored) do
      local itemId = type(id) == "number" and validItemId(id) or nil
      if itemId then
        prefs.ignored[itemId] = tostring(name or "")
      end
    end
  end
  prefs.minValue = validMinValue(raw.minValue)
  return prefs
end

-- True when the feature flag is on (config may be nil in tests: counts as on).
function TargetPrefs.Enabled(config)
  if config and config.TARGET_PREFS == false then
    return false
  end
  return true
end

function TargetPrefs.IsIgnored(prefs, itemId)
  local id = validItemId(itemId)
  return id ~= nil and prefs ~= nil and prefs.ignored ~= nil and prefs.ignored[id] ~= nil
end

-- Returns true when stored, false for a bad item id.
function TargetPrefs.Ignore(prefs, itemId, name)
  local id = validItemId(itemId)
  if not id then
    return false
  end
  prefs.ignored[id] = tostring(name or "")
  return true
end

function TargetPrefs.Unignore(prefs, itemId)
  local id = validItemId(itemId)
  if id then
    prefs.ignored[id] = nil
  end
end

-- Set of ignored item ids for TargetView.Build; empty when the feature flag is off.
function TargetPrefs.IgnoredSet(prefs, config)
  local set = {}
  if not TargetPrefs.Enabled(config) then
    return set
  end
  for id in pairs(prefs and prefs.ignored or {}) do
    set[id] = true
  end
  return set
end

-- Ignored items sorted by name (then id) for display: { { itemId, name } }.
function TargetPrefs.IgnoredList(prefs)
  local list = {}
  for id, name in pairs(prefs and prefs.ignored or {}) do
    list[#list + 1] = { itemId = id, name = name }
  end
  table.sort(list, function(a, b)
    local an, bn = a.name:lower(), b.name:lower()
    if an ~= bn then
      return an < bn
    end
    return a.itemId < b.itemId
  end)
  return list
end

-- Set the override in copper; nil clears it. Returns false (and changes nothing) for bad input.
function TargetPrefs.SetMinValue(prefs, copper)
  if copper == nil then
    prefs.minValue = nil
    return true
  end
  local value = validMinValue(copper)
  if value == nil then
    return false
  end
  prefs.minValue = value
  return true
end

-- The minimum value the target page uses: the saved override, else the config default, else 0.
function TargetPrefs.EffectiveMinValue(prefs, config)
  if TargetPrefs.Enabled(config) and prefs and prefs.minValue ~= nil then
    return prefs.minValue
  end
  return tonumber(config and config.MIN_STACK_VALUE_COPPER) or 0
end
