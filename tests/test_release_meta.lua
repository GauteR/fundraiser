-- Pure Lua tests for release tag / zip naming helpers.
-- Style: Given / When / Then scenarios.
-- Run: lua tests/test_release_meta.lua

local root = arg[0]:match("^(.*)[/\\]") or "."
package.path = root .. "/../scripts/?.lua;" .. package.path
local Meta = require("release_meta")

local failures = 0

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    failures = failures + 1
    print(string.format("FAIL: %s\n  expected: %s\n  actual:   %s", message, tostring(expected), tostring(actual)))
  else
    print("PASS: " .. message)
  end
end

-- Scenario: parse VERSION assignment from Config-like text
do
  -- Given a VERSION assignment line
  -- When parsing
  -- Then the semver string is returned (or nil when missing)
  assert_eq(Meta.parse_version('VERSION = "1.2.3",'), "1.2.3", "parse VERSION assignment")
  assert_eq(Meta.parse_version("no version here"), nil, "missing VERSION -> nil")
end

-- Scenario: annotated tag and forever zip basename
do
  -- Given a version string
  -- When building tag / zip name
  -- Then packager-compatible names are produced
  assert_eq(Meta.version_tag("1.2.0"), "v1.2.0", "version tag prefix")
  assert_eq(Meta.version_tag(""), nil, "empty version -> nil")
  assert_eq(
    Meta.forever_zip_name("fundraiser", "1.2.0"),
    "fundraiser-v1.2.0-forever.zip",
    "forever zip basename"
  )
end

-- Scenario: live Config.lua VERSION matches helper conventions
do
  -- Given fundraiser/Config.lua on disk
  local config_path = root .. "/../fundraiser/Config.lua"
  local fh = assert(io.open(config_path, "r"))
  local config_text = fh:read("*a")
  fh:close()
  -- When parsing VERSION
  local version = Meta.parse_version(config_text)
  -- Then tag and zip names follow v{VERSION}-forever
  assert_eq(type(version) == "string" and version ~= "", true, "Config.VERSION present")
  assert_eq(Meta.version_tag(version), "v" .. version, "Config tag matches VERSION")
  assert_eq(
    Meta.forever_zip_name("fundraiser", version),
    string.format("fundraiser-v%s-forever.zip", version),
    "Config zip name"
  )
end

if failures > 0 then
  print(string.format("%d failure(s)", failures))
  os.exit(1)
end
print("All release_meta tests passed.")
