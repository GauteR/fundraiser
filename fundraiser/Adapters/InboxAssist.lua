-- Scan mailbox attachments grouped by sender (one AH post per item stack).
Fundraiser = Fundraiser or {}
Fundraiser.Adapters = Fundraiser.Adapters or {}

local InboxAssist = {}
Fundraiser.Adapters.InboxAssist = InboxAssist

local MAX_ATTACH = 16

local function itemIdFromLink(link)
  if type(link) ~= "string" then
    return nil
  end
  local id = link:match("item:(%d+)")
  return id and tonumber(id) or nil
end

function InboxAssist:IsDonationTarget()
  local Store = Fundraiser.Adapters.Store
  local Roster = Fundraiser.Adapters.Roster
  local event = Store:GetEvent()
  return Fundraiser.Domain.Roles.IsDonationTarget(event, Roster:GetPlayerName())
end

-- Returns array of { sender, mailIndex, attachIndex, name, link, itemId, count, vendorUnit, ahUnit, source, advice, vendorTotal, ahNet }
function InboxAssist:Scan()
  local rows = {}
  if not GetInboxNumItems or not GetInboxHeaderInfo then
    return rows
  end
  local Pricing = Fundraiser.Adapters.Pricing
  local SaleAdvice = Fundraiser.Domain.SaleAdvice
  local cut = (Fundraiser.Config and Fundraiser.Config.AH_CUT_FRACTION) or 0.05
  local n = GetInboxNumItems() or 0

  for mailIndex = 1, n do
    local _, _, sender = GetInboxHeaderInfo(mailIndex)
    if sender then
      sender = Fundraiser.Domain.Roles.DisplayName(sender) or sender
      for attachIndex = 1, MAX_ATTACH do
        local name, count, link, itemId
        if GetInboxItemLink then
          link = GetInboxItemLink(mailIndex, attachIndex)
        end
        if GetInboxItem then
          local a, b, c, d = GetInboxItem(mailIndex, attachIndex)
          -- Classic variants: (name, …, count) or (name, itemId, texture, count, …)
          if type(a) == "string" then
            name = a
            if type(b) == "number" and b > 100 then
              itemId = b
              count = tonumber(d) or tonumber(c)
            else
              count = tonumber(c) or tonumber(b)
            end
          end
        end
        if (name or link) and (tonumber(count) or 0) > 0 then
          itemId = itemId or itemIdFromLink(link)
          if not itemId and name and GetItemInfo then
            local _, itemLink = GetItemInfo(name)
            link = link or itemLink
            itemId = itemIdFromLink(link)
          end
          count = tonumber(count) or 1
          local vendorUnit = itemId and Pricing:GetVendorUnitPrice(itemId) or nil
          local ahUnit = itemId and Pricing:GetUnitAhPrice(itemId) or nil
          local source = itemId and Pricing:PriceSource(itemId) or "manual"
          local advice, vendorTotal, ahNet = SaleAdvice.Recommend(vendorUnit, ahUnit, count, cut)
          rows[#rows + 1] = {
            sender = sender,
            mailIndex = mailIndex,
            attachIndex = attachIndex,
            name = name or link or "?",
            link = link,
            itemId = itemId,
            count = count,
            vendorUnit = vendorUnit,
            ahUnit = ahUnit,
            source = source,
            advice = advice,
            vendorTotal = vendorTotal,
            ahNet = ahNet,
          }
        end
      end
    end
  end

  table.sort(rows, function(a, b)
    if a.sender ~= b.sender then
      return a.sender < b.sender
    end
    if a.mailIndex ~= b.mailIndex then
      return a.mailIndex < b.mailIndex
    end
    return a.attachIndex < b.attachIndex
  end)
  return rows
end
