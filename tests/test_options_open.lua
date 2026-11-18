-- Pure Lua tests for Options:Open candidate ordering.
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Locale/enUS.lua")
dofile(repo .. "/fundraiser/UI/Options.lua")

local failed = 0

local function assert_eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s (%s ~= %s)\n", msg or "assert_eq", tostring(a), tostring(b)))
  end
end

local Options = Fundraiser.Options

-- Scenario: CollectOpenCandidates prefers numeric ID before overwritten name
do
  -- Given a registered category whose .ID was overwritten to the panel name
  local category = { ID = "Fundraiser" }
  -- When collecting open candidates
  local candidates = Options.CollectOpenCandidates(42, category, "Fundraiser")
  -- Then numeric ID is first, name once, then the category object
  assert_eq(#candidates, 3, "candidate count")
  assert_eq(candidates[1], 42, "numeric id first")
  assert_eq(candidates[2], "Fundraiser", "panel name second")
  assert_eq(candidates[3], category, "category object last")
end

-- Scenario: CollectOpenCandidates skips nils and duplicates
do
  local category = { ID = nil }
  local candidates = Options.CollectOpenCandidates(nil, category, "Fundraiser")
  assert_eq(#candidates, 2, "nil id omitted")
  assert_eq(candidates[1], "Fundraiser", "name first when no id")
  assert_eq(candidates[2], category, "category object last")
end

if failed > 0 then
  os.exit(1)
end
print("ok")
