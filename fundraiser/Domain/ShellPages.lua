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
