-- Pure Lua tests for the shell page gate (which pages and menu entries each player may use).
-- Style: Given / When / Then scenarios.
local root = arg and arg[0] and arg[0]:match("(.+)[/\\]") or "."
local repo = root .. "/.."

dofile(repo .. "/fundraiser/Domain/ShellPages.lua")

local SP = Fundraiser.Domain.ShellPages
local failed = 0

local function assert_eq(a, b, msg)
  if a ~= b then
    failed = failed + 1
    io.stderr:write(string.format("FAIL: %s (%s ~= %s)\n", msg or "assert_eq", tostring(a), tostring(b)))
  end
end

-- Scenario: a character that is not the donation target never reaches the target page
do
  local access = { officer = true, ledger = true, target = false }
  assert_eq(SP.Allowed("target", access), false, "non-target: menu entry hidden")
  assert_eq(SP.Resolve("target", access), "status", "non-target officer: falls back to the home page")
  access = { officer = false, ledger = true, target = false }
  assert_eq(SP.Resolve("target", access), "ledger", "non-target ledger viewer: falls back to the ledger")
  access = { officer = false, ledger = false, target = false }
  assert_eq(SP.Resolve("target", access), nil, "nobody special: nothing to show")
end

-- Scenario: the donation target gets the page and the menu entry
do
  local access = { officer = false, ledger = true, target = true }
  assert_eq(SP.Allowed("target", access), true, "target: menu entry shown")
  assert_eq(SP.Resolve("target", access), "target", "target: page opens")
end

-- Scenario: other pages keep their old rules
do
  assert_eq(SP.Resolve("create", { officer = true, ledger = true }), "create", "officer: create form")
  assert_eq(SP.Resolve("status", { officer = true, ledger = true }), "status", "officer: home")
  assert_eq(SP.Resolve("status", { officer = false, ledger = true }), "ledger", "non-officer: home becomes ledger")
  assert_eq(SP.Resolve("ledger", { officer = true, ledger = false }), nil, "no ledger access: nothing")
  assert_eq(SP.Resolve("donation", { ledger = true, donation = true }), "donation", "donation form allowed")
  assert_eq(SP.Resolve("donation", { ledger = true, donation = false }), "ledger", "donation form falls back")
  assert_eq(SP.Allowed("officer", { officer = true }), true, "officer entries")
  assert_eq(SP.Allowed("motd", { motd = true }), true, "motd entry")
  assert_eq(SP.Allowed("unknown", { officer = true }), false, "unknown needs: hidden")
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("shell pages tests passed")
