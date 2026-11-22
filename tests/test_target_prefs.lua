-- Pure Lua tests for the persistent target preferences (ignore list + minimum value).
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Config.lua")
dofile(repo .. "/fundraiser/Domain/TargetPrefs.lua")

local TP = Fundraiser.Domain.TargetPrefs
local failed = 0

local function assert_eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s (%s ~= %s)\n", msg or "assert_eq", tostring(a), tostring(b)))
  end
end

-- Scenario: normalising anything yields a usable, empty prefs table
do
  local p = TP.Normalize(nil)
  assert_eq(type(p.ignored), "table", "normalize nil: ignored table")
  assert_eq(p.minValue, nil, "normalize nil: no override")
  local q = TP.Normalize("garbage")
  assert_eq(type(q.ignored), "table", "normalize string: ignored table")
end

-- Scenario: normalising drops invalid entries and keeps valid ones
do
  local p = TP.Normalize({
    ignored = { [100] = "Linen Cloth", [0] = "Bad", [-5] = "Neg", [1.5] = "Frac", ["x"] = "Str" },
    minValue = 250.7,
  })
  assert_eq(TP.IsIgnored(p, 100), true, "normalize: valid id kept")
  assert_eq(TP.IsIgnored(p, 0), false, "normalize: zero id dropped")
  assert_eq(TP.IsIgnored(p, -5), false, "normalize: negative id dropped")
  assert_eq(TP.IsIgnored(p, 1.5), false, "normalize: fractional id dropped")
  assert_eq(p.minValue, 250, "normalize: min value floored")
  assert_eq(TP.Normalize({ minValue = -1 }).minValue, nil, "normalize: negative min value dropped")
  assert_eq(TP.Normalize({ minValue = "abc" }).minValue, nil, "normalize: non-numeric min value dropped")
  assert_eq(TP.Normalize({ minValue = 0 }).minValue, 0, "normalize: zero min value is a valid override")
end

-- Scenario: ignoring and unignoring an item by id
do
  local p = TP.Normalize(nil)
  assert_eq(TP.Ignore(p, 4306, "Silk Cloth"), true, "ignore: accepted")
  assert_eq(TP.IsIgnored(p, 4306), true, "ignore: item is ignored")
  assert_eq(p.ignored[4306], "Silk Cloth", "ignore: display name kept")
  assert_eq(TP.Ignore(p, 0, "Nope"), false, "ignore: bad id rejected")
  assert_eq(TP.Ignore(p, nil, "Nope"), false, "ignore: missing id rejected")
  TP.Unignore(p, 4306)
  assert_eq(TP.IsIgnored(p, 4306), false, "unignore: item no longer ignored")
end

-- Scenario: the ignored set and the sorted list for display
do
  local p = TP.Normalize(nil)
  TP.Ignore(p, 2, "Zebra Hide")
  TP.Ignore(p, 1, "Apple")
  local set = TP.IgnoredSet(p)
  assert_eq(set[1], true, "set: id 1")
  assert_eq(set[2], true, "set: id 2")
  local list = TP.IgnoredList(p)
  assert_eq(#list, 2, "list: two entries")
  assert_eq(list[1].itemId, 1, "list: sorted by name")
  assert_eq(list[2].name, "Zebra Hide", "list: name carried")
end

-- Scenario: the minimum value override beats the config default
do
  local cfg = { MIN_STACK_VALUE_COPPER = 100 }
  local p = TP.Normalize(nil)
  assert_eq(TP.EffectiveMinValue(p, cfg), 100, "min: config default when unset")
  assert_eq(TP.SetMinValue(p, 5000), true, "min: set accepted")
  assert_eq(TP.EffectiveMinValue(p, cfg), 5000, "min: override wins")
  assert_eq(TP.SetMinValue(p, -3), false, "min: negative rejected")
  assert_eq(TP.SetMinValue(p, "abc"), false, "min: non-numeric rejected")
  assert_eq(TP.EffectiveMinValue(p, cfg), 5000, "min: rejected value leaves override alone")
  TP.SetMinValue(p, nil)
  assert_eq(TP.EffectiveMinValue(p, cfg), 100, "min: reset falls back to config")
  assert_eq(TP.EffectiveMinValue(p, {}), 0, "min: zero when config has none")
end

-- Scenario: the ignore list exports to one line and imports back (round trip)
do
  local p = TP.Normalize(nil)
  TP.Ignore(p, 7, "Silk Cloth")
  TP.Ignore(p, 12, "Odd; name = 100% (weird)")
  local text = TP.Export(p)
  assert_eq(text:sub(1, 4), "FR1:", "export: versioned prefix")
  assert_eq(text:find("\n", 1, true), nil, "export: one line")
  local q = TP.Normalize(nil)
  local ok, info = TP.Import(q, text)
  assert_eq(ok, true, "import: accepted")
  assert_eq(info.added, 2, "import: both items added")
  assert_eq(info.rejected, 0, "import: nothing rejected")
  assert_eq(q.ignored[7], "Silk Cloth", "import: name restored")
  assert_eq(q.ignored[12], "Odd; name = 100% (weird)", "import: special characters survive")
  assert_eq(TP.Export(TP.Normalize(nil)), "FR1:", "export: empty list")
end

-- Scenario: import merges with the existing list and keeps its names
do
  local p = TP.Normalize(nil)
  TP.Ignore(p, 7, "My name")
  local ok, info = TP.Import(p, "FR1:7=Other name;9=Wool")
  assert_eq(ok, true, "merge: accepted")
  assert_eq(info.added, 1, "merge: only the new item is added")
  assert_eq(info.known, 1, "merge: the existing item is counted as known")
  assert_eq(p.ignored[7], "My name", "merge: existing name is kept")
  assert_eq(p.ignored[9], "Wool", "merge: new item is in the list")
end

-- Scenario: invalid entries are rejected and counted; an invalid string changes nothing
do
  local p = TP.Normalize(nil)
  local ok, info = TP.Import(p, "  FR1:5=Linen;abc=Bad;-3=Neg;0=Zero;;6=Wool;5=Linen again  ")
  assert_eq(ok, true, "invalid entries: valid ones still import")
  assert_eq(info.added, 2, "invalid entries: valid ones added")
  assert_eq(info.rejected, 3, "invalid entries: bad ids are counted")
  assert_eq(p.ignored[5], "Linen", "invalid entries: first duplicate wins")
  local before = TP.Export(p)
  for _, bad in ipairs({ "", "hello", "FR2:5=Linen", 42 }) do
    local ok2, why = TP.Import(p, bad)
    assert_eq(ok2, false, "bad string rejected: " .. tostring(bad))
    assert_eq(why, "bad_format", "bad string reason: " .. tostring(bad))
  end
  assert_eq(TP.Export(p), before, "bad strings leave the list unchanged")
end

-- Scenario: the feature flag turns the prefs off
do
  local p = TP.Normalize(nil)
  TP.Ignore(p, 7, "Thing")
  TP.SetMinValue(p, 900)
  assert_eq(TP.Enabled({ TARGET_PREFS = true }), true, "flag: on")
  assert_eq(TP.Enabled({ TARGET_PREFS = false }), false, "flag: off")
  assert_eq(next(TP.IgnoredSet(p, { TARGET_PREFS = false })), nil, "flag off: nothing ignored")
  assert_eq(TP.EffectiveMinValue(p, { TARGET_PREFS = false, MIN_STACK_VALUE_COPPER = 100 }), 100,
    "flag off: config minimum applies")
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("ok test_target_prefs")
