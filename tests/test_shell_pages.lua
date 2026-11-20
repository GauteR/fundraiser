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

-- Scenario: the shell opens by itself at a vendor (Target page) and at the mailbox (ledger)
do
  local cfg = { TARGET_AUTO_OPEN_VENDOR = true, LEDGER_AUTO_OPEN_MAILBOX = true }
  local target = { officer = false, ledger = true, target = true }
  assert_eq(SP.AutoOpen("vendor", cfg, target), "target", "auto open: vendor opens the Target page")
  assert_eq(SP.AutoOpen("mailbox", cfg, target), "ledger", "auto open: mailbox opens the ledger")
  assert_eq(SP.AutoOpen("vendor", cfg, { officer = true, ledger = true, target = false }), nil, "auto open: vendor needs target access")
  assert_eq(SP.AutoOpen("mailbox", cfg, { officer = false, ledger = false, target = false }), nil, "auto open: mailbox needs ledger access")
  assert_eq(SP.AutoOpen("vendor", { TARGET_AUTO_OPEN_VENDOR = false }, target), nil, "auto open: vendor flag off")
  assert_eq(SP.AutoOpen("mailbox", { LEDGER_AUTO_OPEN_MAILBOX = false }, target), nil, "auto open: mailbox flag off")
  assert_eq(SP.AutoOpen("vendor", nil, target), nil, "auto open: no config counts as off")
  assert_eq(SP.AutoOpen("bank", cfg, target), nil, "auto open: unknown trigger")
  assert_eq(SP.AutoOpen("vendor", cfg, nil), nil, "auto open: unknown access")
end

-- Scenario: the window attaches to the vendor / mail frame it was opened for
do
  local cfg = { TARGET_AUTO_OPEN_VENDOR = true, LEDGER_AUTO_OPEN_MAILBOX = true }
  local access = { ledger = true, target = true }
  local _, anchor = SP.AutoOpen("vendor", cfg, access)
  assert_eq(anchor, "MerchantFrame", "anchor: vendor window")
  _, anchor = SP.AutoOpen("mailbox", cfg, access)
  assert_eq(anchor, "MailFrame", "anchor: mail window")
  assert_eq(select("#", SP.AutoOpen("vendor", {}, access)), 1, "anchor: nothing to open, nothing to anchor")
end

-- Scenario: the window closes with the window it was opened for, and only then
do
  local auto = { trigger = "vendor", page = "target" }
  assert_eq(SP.ShouldAutoClose(auto, "vendor", "target"), true, "auto close: vendor closed, still on the page")
  assert_eq(SP.ShouldAutoClose(auto, "mailbox", "target"), false, "auto close: other window closed")
  assert_eq(SP.ShouldAutoClose(auto, "vendor", "ledger"), false, "auto close: player moved on to another page")
  assert_eq(SP.ShouldAutoClose(nil, "vendor", "target"), false, "auto close: window was opened by the player")
end

if failed > 0 then
  io.stderr:write(string.format("%d test(s) failed\n", failed))
  os.exit(1)
end
print("shell pages tests passed")
