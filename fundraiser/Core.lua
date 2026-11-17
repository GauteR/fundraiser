-- Bootstrap: slash, store, sync, mail, bags, UI.
Fundraiser = Fundraiser or {}

local function Print(message)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. message)
  end
end

function Fundraiser:IsEnabled()
  return self.Config and self.Config.ENABLED == true
end

function Fundraiser.FormatCopper(copper)
  copper = tonumber(copper) or 0
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local parts = {}
  if g > 0 then
    parts[#parts + 1] = g .. "g"
  end
  if s > 0 or g > 0 then
    parts[#parts + 1] = s .. "s"
  end
  parts[#parts + 1] = c .. "c"
  return table.concat(parts, " ")
end

function Fundraiser:ToggleWindow()
  if not self:IsEnabled() then
    Print(self:T("CHAT_DISABLED"))
    return
  end
  if not (self.Config and self.Config.ADMIN_UI) then
    return
  end
  if self.UI and self.UI.Window then
    self.UI.Window:Toggle()
  end
end

function Fundraiser:PrintStatus()
  if self:IsEnabled() then
    Print(self:T("CHAT_STATUS_ON"))
  else
    Print(self:T("CHAT_STATUS_OFF"))
  end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event)
  if event ~= "PLAYER_LOGIN" then
    return
  end

  Fundraiser.Adapters.Store:Load()

  if not Fundraiser:IsEnabled() then
    Print(Fundraiser:T("CHAT_DISABLED"))
    return
  end

  SLASH_FUNDRAISER1 = (Fundraiser.Config and Fundraiser.Config.SLASH_COMMAND) or "/fundraiser"
  SlashCmdList["FUNDRAISER"] = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local lower = msg:lower()
    if lower == "status" then
      Fundraiser:PrintStatus()
      return
    end
    local debugArg = lower:match("^debug%s*(.*)$")
    if debugArg ~= nil then
      if Fundraiser.Adapters.Debug then
        -- Pass original tail after "debug" to preserve Name casing.
        local tail = msg:match("^[Dd][Ee][Bb][Uu][Gg]%s*(.*)$") or debugArg
        Fundraiser.Adapters.Debug:Handle(tail)
      end
      return
    end
    Fundraiser:ToggleWindow()
  end

  if Fundraiser.Adapters.ThinGuildSync then
    Fundraiser.Adapters.ThinGuildSync:Initialize()
  end
  if Fundraiser.Adapters.Mail then
    Fundraiser.Adapters.Mail:Initialize()
  end
  if Fundraiser.Adapters.Auction then
    Fundraiser.Adapters.Auction:Initialize()
  end
  if Fundraiser.Adapters.Bags then
    Fundraiser.Adapters.Bags:Initialize()
  end
  if Fundraiser.Options and Fundraiser.Options.Initialize then
    Fundraiser.Options:Initialize()
  end

  if Fundraiser.Adapters.Roster then
    Fundraiser.Adapters.Roster:Request()
  end
end)
