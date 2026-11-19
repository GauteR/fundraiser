-- Pure Lua tests for the player name the roles gate compares with the event target.
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Domain/Roles.lua")
dofile(repo .. "/fundraiser/Adapters/Roster.lua")

local Roster = Fundraiser.Adapters.Roster
local Roles = Fundraiser.Domain.Roles
local failed = 0

local function assert_eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s (%s ~= %s)\n", msg or "assert_eq", tostring(a), tostring(b)))
  end
end

-- Scenario: Forever returns only the first name from UnitFullName but the full name from UnitName
do
  UnitFullName = function()
    return "Neema", "Neema Miststalker"
  end
  UnitName = function()
    return "Neema Miststalker"
  end
  assert_eq(Roster:GetPlayerName(), "Neema Miststalker", "forever: full First Last name")
  assert_eq(
    Roles.IsDonationTarget({ target = "Neema Miststalker" }, Roster:GetPlayerName()),
    true,
    "forever: the donation target is recognised"
  )
end

-- Scenario: only UnitFullName carries the full name
do
  UnitFullName = function()
    return "Bank Alt", "Realm"
  end
  UnitName = function()
    return "Bank"
  end
  assert_eq(Roster:GetPlayerName(), "Bank Alt", "full name from UnitFullName when UnitName is short")
end

-- Scenario: single-word names and missing APIs still work
do
  UnitFullName = nil
  UnitName = function()
    return "Solo"
  end
  assert_eq(Roster:GetPlayerName(), "Solo", "single word name")
  UnitName = nil
  assert_eq(Roster:GetPlayerName(), nil, "no API: nil")
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("roster name tests passed")
