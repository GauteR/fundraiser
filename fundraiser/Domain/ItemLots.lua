-- Domain: donated items waiting to be sold ("lots") and the allocation of a sale's proceeds
-- to the oldest open ledger row. A lot is one item on one ledger row:
--   { id = ledger row id, key = normalized item name, name = display name, qty, sold, copper }
-- Pure Lua: no WoW API.
Fundraiser = Fundraiser or {}
Fundraiser.Domain = Fundraiser.Domain or {}

local ItemLots = {}
Fundraiser.Domain.ItemLots = ItemLots

-- Display name from plain text, "[Name]" or an item link.
local function displayName(text)
  if text == nil then
    return ""
  end
  text = tostring(text)
  local linked = text:match("|h%[(.-)%]|h")
  if linked then
    text = linked
  else
    text = text:match("^%s*%[(.-)%]%s*$") or text
  end
  return (text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- Comparable item key: chat text, links and plain names all map to the same string.
function ItemLots.ItemKey(text)
  return displayName(text):lower()
end

-- Item name and quantity from sale text such as "Linen Cloth x20" or "Linen Cloth (20)".
-- Returns the name and the quantity (nil when the text carries none).
function ItemLots.ParseCount(text)
  local name = displayName(text)
  local base, qty = name:match("^(.-)%s+x(%d+)$")
  if not base then
    base, qty = name:match("^(.-)%s*%((%d+)%)$")
  end
  if base and base ~= "" then
    return base, tonumber(qty)
  end
  return name, nil
end

-- Proceeds after the auction house cut (fraction, for example 0.05), rounded to the copper.
function ItemLots.AfterCut(gross, cut)
  return math.floor((tonumber(gross) or 0) * (1 - (tonumber(cut) or 0)) + 0.5)
end

-- Add quantity for an item on a ledger row (same row and item merge).
function ItemLots.Add(lots, fields)
  local key = ItemLots.ItemKey(fields.item)
  local qty = tonumber(fields.qty) or 1
  if key == "" or qty <= 0 then
    return lots
  end
  for _, lot in ipairs(lots) do
    if lot.id == fields.id and lot.key == key then
      lot.qty = lot.qty + qty
      return lots
    end
  end
  lots[#lots + 1] = {
    id = fields.id,
    key = key,
    name = displayName(fields.item),
    qty = qty,
    sold = 0,
    copper = 0,
  }
  return lots
end

-- Sell qty of an item for proceeds (copper): oldest open lots first. Updates the lots and returns
-- parts ({ id, qty, copper } per touched row), then the quantity and copper that no lot could take.
-- Copper is split by quantity; the last piece takes the rounding remainder so nothing is lost.
function ItemLots.Allocate(lots, item, qty, proceeds)
  local key = ItemLots.ItemKey(item)
  qty = tonumber(qty) or 1
  if qty < 1 then
    qty = 1
  end
  proceeds = tonumber(proceeds) or 0

  local picked, left = {}, qty
  for _, lot in ipairs(lots) do
    if left == 0 then
      break
    end
    if lot.key == key and lot.sold < lot.qty then
      local take = math.min(left, lot.qty - lot.sold)
      picked[#picked + 1] = { lot = lot, qty = take }
      left = left - take
    end
  end

  local parts = {}
  local remaining = proceeds
  local segments = #picked + (left > 0 and 1 or 0)
  for i, p in ipairs(picked) do
    local share = (i == segments) and remaining or math.floor(proceeds * p.qty / qty)
    remaining = remaining - share
    p.lot.sold = p.lot.sold + p.qty
    p.lot.copper = p.lot.copper + share
    parts[#parts + 1] = { id = p.lot.id, qty = p.qty, copper = share }
  end
  return parts, left, (left > 0) and remaining or 0
end

-- True when the ledger row already has lots (its mail was recorded before).
function ItemLots.HasRow(lots, id)
  for _, lot in ipairs(lots) do
    if lot.id == id then
      return true
    end
  end
  return false
end

-- Copper earned on a ledger row (sum over its lots).
function ItemLots.RowCopper(lots, id)
  local sum = 0
  for _, lot in ipairs(lots) do
    if lot.id == id then
      sum = sum + lot.copper
    end
  end
  return sum
end

-- "Linen Cloth x20 (5 sold), Wool Cloth x5" for a ledger row.
function ItemLots.RowDetail(lots, id)
  local parts = {}
  for _, lot in ipairs(lots) do
    if lot.id == id then
      local text = string.format("%s x%d", lot.name, lot.qty)
      if lot.sold > 0 then
        text = text .. string.format(" (%d sold)", lot.sold)
      end
      parts[#parts + 1] = text
    end
  end
  return table.concat(parts, ", ")
end
