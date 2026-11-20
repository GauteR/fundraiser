-- Bootstrap: slash, store, sync, mail, reminder, UI.
Fundraiser = Fundraiser or {}

local function Print(message)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. message)
  end
end

function Fundraiser:IsEnabled()
  return self.Config and self.Config.ENABLED == true
end

-- Money string with coin icons when the client supports it (Forever GetCoinTextureString).
-- fontHeight is optional (default 14); used by inline |T textures.
function Fundraiser.FormatCopper(copper, fontHeight)
  copper = math.max(0, math.floor(tonumber(copper) or 0))
  local height = tonumber(fontHeight) or 14
  if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
    return C_CurrencyInfo.GetCoinTextureString(copper, height)
  end
  if GetCoinTextureString then
    return GetCoinTextureString(copper, height)
  end
  -- Vanilla Forever MoneyIcons sheet (gold/silver/copper cells) when API is missing.
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local sheet = "Interface\\MoneyFrame\\UI-MoneyIcons"
  local function coin(amount, left, right)
    return string.format(
      "%d|T%s:%d:%d:2:0:4:1:%d:%d:0:1|t",
      amount,
      sheet,
      height,
      height,
      left,
      right
    )
  end
  -- Match GetCoinTextureString: only non-zero denominations (0 -> "0" copper).
  if copper == 0 then
    return coin(0, 2, 3)
  end
  local parts = {}
  if g > 0 then
    parts[#parts + 1] = coin(g, 0, 1)
  end
  if s > 0 then
    parts[#parts + 1] = coin(s, 1, 2)
  end
  if c > 0 then
    parts[#parts + 1] = coin(c, 2, 3)
  end
  return table.concat(parts, " ")
end

function Fundraiser:CanOpenAdminUi()
  if not self:IsEnabled() then
    return false
  end
  if not (self.Config and self.Config.ADMIN_UI) then
    return false
  end
  local Roster = self.Adapters and self.Adapters.Roster
  local Store = self.Adapters and self.Adapters.Store
  local Roles = self.Domain and self.Domain.Roles
  if not Roster or not Roles then
    return false
  end
  local event = Store and Store.GetEvent and Store:GetEvent() or nil
  return Roles.CanManageFundraiser(Roster:GetPlayerRankIndex(), event)
end

function Fundraiser:CanOpenTargetUi()
  if not self:IsEnabled() then
    return false
  end
  if not (self.Config and self.Config.TARGET_UI) then
    return false
  end
  local Roster = self.Adapters and self.Adapters.Roster
  local Store = self.Adapters and self.Adapters.Store
  local Roles = self.Domain and self.Domain.Roles
  if not Roster or not Roles or not Store then
    return false
  end
  local event = Store:GetEvent()
  return Roles.IsDonationTarget(event, Roster:GetPlayerName())
end

function Fundraiser:ToggleWindow()
  if not self:IsEnabled() then
    Print(self:T("CHAT_DISABLED"))
    return
  end
  if not (self.Config and self.Config.ADMIN_UI) then
    return
  end
  if not self:CanOpenAdminUi() then
    Print(self:T("CHAT_NOT_ADMIN"))
    if self.UI and self.UI.Window and self.UI.Window.Hide then
      self.UI.Window:Hide()
    end
    return
  end
  if self.UI and self.UI.Window then
    self.UI.Window:Toggle()
  end
end

function Fundraiser:ToggleTargetUi()
  if not self:IsEnabled() then
    Print(self:T("CHAT_DISABLED"))
    return
  end
  if not (self.Config and self.Config.TARGET_UI) then
    return
  end
  if not self:CanOpenTargetUi() then
    Print(self:T("CHAT_TARGET_NO_ACCESS"))
    local Window = self.UI and self.UI.Window
    if Window and Window.view == "target" then
      Window:Hide()
    end
    return
  end
  self.UI.Window:ToggleTarget()
end

-- Ledger window: same view gate as UseCases.GetLedgerView (donation target, officers).
function Fundraiser:CanOpenLedgerUi()
  if not self:IsEnabled() then
    return false
  end
  if not (self.Config and self.Config.LEDGER) then
    return false
  end
  local Ledger = self.UI and self.UI.Ledger
  if not Ledger then
    return false
  end
  return Ledger:CanView()
end

function Fundraiser:ToggleLedgerUi()
  if not self:IsEnabled() then
    Print(self:T("CHAT_DISABLED"))
    return
  end
  if not (self.Config and self.Config.LEDGER) then
    return
  end
  if not self:CanOpenLedgerUi() then
    Print(self:T("CHAT_LEDGER_NO_ACCESS"))
    local Window = self.UI and self.UI.Window
    if Window and Window.view == "ledger" then
      Window:Hide()
    end
    return
  end
  self.UI.Window:ToggleLedger()
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
    if lower == "ledger" then
      Fundraiser:ToggleLedgerUi()
      return
    end
    if lower == "target" then
      Fundraiser:ToggleTargetUi()
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
  if Fundraiser.Adapters.MailboxReminder then
    Fundraiser.Adapters.MailboxReminder:Initialize()
  end
  if Fundraiser.Options and Fundraiser.Options.Initialize then
    Fundraiser.Options:Initialize()
  end
  if Fundraiser.UI and Fundraiser.UI.Target and Fundraiser.UI.Target.Initialize then
    Fundraiser.UI.Target:Initialize()
  end

  if Fundraiser.Adapters.Roster then
    Fundraiser.Adapters.Roster:Request()
  end
end)
