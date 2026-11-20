-- Pure Lua tests for the player name the roles gate compares with the event target.
-- Style: Given / When / Then scenarios.
-- Real Forever values (observed in the client): UnitName("player") and UnitFullName("player")
-- both return "First", "Last" as two values; GetUnitName("player", true) returns "First Last".
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

local function reset()
  GetUnitName, UnitName, UnitFullName = nil, nil, nil
end

-- Scenario: Forever gives the full name from GetUnitName
do
  reset()
  GetUnitName = function()
    return "Neema Miststalker"
  end
  UnitName = function()
    return "Neema", "Miststalker"
  end
  UnitFullName = UnitName
  assert_eq(Roster:GetPlayerName(), "Neema Miststalker", "forever: full First Last name")
  assert_eq(
    Roles.IsDonationTarget({ target = "Neema Miststalker" }, Roster:GetPlayerName()),
    true,
    "forever: the donation target is recognised"
  )
end

-- Scenario: without GetUnitName the last name comes from the second return value
do
  reset()
  UnitName = function()
    return "Neema", "Miststalker"
  end
  assert_eq(Roster:GetPlayerName(), "Neema Miststalker", "UnitName: first and last joined")
  reset()
  UnitFullName = function()
    return "Neema", "Miststalker"
  end
  assert_eq(Roster:GetPlayerName(), "Neema Miststalker", "UnitFullName: first and last joined")
end

-- Scenario: a name that already has both parts is used as is
do
  reset()
  UnitName = function()
    return "Bank Alt"
  end
  assert_eq(Roster:GetPlayerName(), "Bank Alt", "full name from UnitName")
end

-- Scenario: single-word names and missing APIs still work
do
  reset()
  UnitName = function()
    return "Solo"
  end
  assert_eq(Roster:GetPlayerName(), "Solo", "single word name")
  reset()
  assert_eq(Roster:GetPlayerName(), nil, "no API: nil")
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("roster name tests passed")
