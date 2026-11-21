-- Domain: which shell pages and menu entries a player may use.
-- access = { officer, ledger, target, donation, motd } (booleans from Core/Ledger gates).
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local ShellPages = {}
Fundraiser.Domain.ShellPages = ShellPages

local NEEDS = { officer = true, ledger = true, target = true, donation = true, motd = true }

-- Menu entry visibility: `needs` is the NAV_ITEMS requirement.
function ShellPages.Allowed(needs, access)
  if not NEEDS[needs] then
    return false
  end
  return access ~= nil and access[needs] == true
end

-- Page the shell opens by itself when the player starts a window: "vendor" (a merchant opens)
-- gives the Target page, "mailbox" (the mailbox opens) gives the ledger. Returns the page and
-- the name of the client frame the shell attaches to (right side), or nil when the matching
-- Config flag is off, the player is not the donation target (every other character, officers
-- included, keeps the normal vendor and mailbox), or the player may not use that page.
-- cfg: Config table; access as below.
local AUTO_OPEN = {
  vendor = { flag = "TARGET_AUTO_OPEN_VENDOR", page = "target", anchor = "MerchantFrame" },
  mailbox = { flag = "LEDGER_AUTO_OPEN_MAILBOX", page = "ledger", anchor = "MailFrame" },
}

function ShellPages.AutoOpen(trigger, cfg, access)
  local rule = AUTO_OPEN[trigger]
  if not rule or not cfg or cfg[rule.flag] ~= true then
    return nil
  end
  if not access or access.target ~= true or access[rule.page] ~= true then
    return nil
  end
  return rule.page, rule.anchor
end

-- Whether the shell closes now that a vendor / the mailbox closed. auto = { trigger, page } is
-- what opened it by itself (nil when the player opened it); view = the page showing now. A
-- player who moved on to another page keeps the window.
function ShellPages.ShouldAutoClose(auto, closedTrigger, view)
  return auto ~= nil and auto.trigger == closedTrigger and auto.page == view
end

-- The page that is actually shown for a request, or nil when nothing may be shown.
function ShellPages.Resolve(page, access)
  access = access or {}
  local function ledgerOrNil()
    if access.ledger then
      return "ledger"
    end
    return nil
  end
  if page == "donation" then
    if access.donation then
      return "donation"
    end
    return ledgerOrNil()
  end
  if page == "target" then
    if access.target then
      return "target"
    end
    if access.officer then
      return "status"
    end
    return ledgerOrNil()
  end
  if page == "ledger" or not access.officer then
    return ledgerOrNil()
  end
  if page == "create" then
    return "create"
  end
  return "status"
end
