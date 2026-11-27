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
-- `shared` (optional, Domain/SharedIgnore table) is added only when config.TARGET_IGNORE_SYNC is on.
function TargetPrefs.IgnoredSet(prefs, config, shared)
  local set = {}
  if not TargetPrefs.Enabled(config) then
    return set
  end
  for id in pairs(prefs and prefs.ignored or {}) do
    set[id] = true
  end
  local SharedIgnore = Fundraiser.Domain.SharedIgnore
  if shared and SharedIgnore and config and config.TARGET_IGNORE_SYNC == true then
    for id in pairs(SharedIgnore.Active(shared)) do
      set[id] = true
    end
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

-- Options list: personal entries plus, when config.TARGET_IGNORE_SYNC is on, shared-only entries,
-- sorted by name. { { itemId, name, shared } }; shared = also (or only) in the guild-shared layer.
function TargetPrefs.DisplayList(prefs, config, shared)
  local SharedIgnore = Fundraiser.Domain.SharedIgnore
  local active = {}
  if shared and SharedIgnore and config and config.TARGET_IGNORE_SYNC == true then
    active = SharedIgnore.Active(shared)
  end
  local list = {}
  for id, name in pairs(prefs and prefs.ignored or {}) do
    list[#list + 1] = { itemId = id, name = name, shared = active[id] == true }
  end
  for id in pairs(active) do
    if not (prefs and prefs.ignored and prefs.ignored[id] ~= nil) then
      list[#list + 1] = { itemId = id, name = shared[id].name, shared = true }
    end
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

-- One-line text form of the ignore list for copying between characters: "FR1:<id>=<name>;..."
-- (names percent-escaped for % ; = and control characters), ordered by item id.
local EXPORT_PREFIX = "FR1:"

local function escapeName(name)
  return (tostring(name):gsub("[%%;=%c]", function(c)
    return string.format("%%%02X", c:byte())
  end))
end

local function unescapeName(text)
  return (text:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

function TargetPrefs.Export(prefs)
  local ids = {}
  for id in pairs(prefs and prefs.ignored or {}) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  local parts = {}
  for _, id in ipairs(ids) do
    parts[#parts + 1] = string.format("%d=%s", id, escapeName(prefs.ignored[id]))
  end
  return EXPORT_PREFIX .. table.concat(parts, ";")
end

-- Merge an exported string into prefs: new items are added, items already ignored keep their name.
-- Returns true, { added, known, rejected } (rejected = malformed entries, skipped); or false,
-- "bad_format" and changes nothing when the text is not an export string.
function TargetPrefs.Import(prefs, text)
  if type(text) ~= "string" then
    return false, "bad_format"
  end
  text = text:match("^%s*(.-)%s*$")
  if text:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
    return false, "bad_format"
  end
  local info = { added = 0, known = 0, rejected = 0 }
  for entry in text:sub(#EXPORT_PREFIX + 1):gmatch("[^;]+") do
    local idText, name = entry:match("^(%d+)=(.*)$")
    local id = idText and validItemId(idText)
    if not id then
      info.rejected = info.rejected + 1
    elseif prefs.ignored[id] ~= nil then
      info.known = info.known + 1
    else
      prefs.ignored[id] = unescapeName(name)
      info.added = info.added + 1
    end
  end
  return true, info
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
