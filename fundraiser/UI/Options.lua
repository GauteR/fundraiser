-- Options → AddOns → Fundraiser (status + global defaults).
Fundraiser = Fundraiser or {}
Fundraiser.UI = Fundraiser.UI or {}
Fundraiser.Options = Fundraiser.Options or {}

local Options = Fundraiser.Options
local ADDON_FOLDER = "fundraiser"

local function GetMeta(field, fallback)
  local value
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    value = C_AddOns.GetAddOnMetadata(ADDON_FOLDER, field)
  elseif GetAddOnMetadata then
    value = GetAddOnMetadata(ADDON_FOLDER, field)
  end
  if value == nil or value == "" then
    return fallback
  end
  return value
end

local function GetDisplayVersion()
  local meta = GetMeta("Version", nil)
  if meta and not string.find(meta, "@", 1, true) then
    return meta
  end
  if Fundraiser.Config and Fundraiser.Config.VERSION then
    return Fundraiser.Config.VERSION
  end
  return "?"
end

local function RefreshPanel(panel)
  if not panel then
    return
  end
  local SettingsDomain = Fundraiser.Domain and Fundraiser.Domain.Settings
  local Store = Fundraiser.Adapters and Fundraiser.Adapters.Store
  local Roster = Fundraiser.Adapters and Fundraiser.Adapters.Roster
  local event = Store and Store.GetEvent and Store:GetEvent() or nil
  local guildName = nil
  if Roster and Roster.IsInGuild and Roster:IsInGuild() and Roster.GetGuildName then
    guildName = Roster:GetGuildName()
  end
  local canOpen = Fundraiser.CanOpenAdminUi and Fundraiser:CanOpenAdminUi() or false
  local info = {
    enabled = Fundraiser.IsEnabled and Fundraiser:IsEnabled() or false,
    guildName = guildName,
    eventName = event and event.name or nil,
    eventTarget = event and event.target or nil,
    canOpenAdmin = canOpen,
  }
  local status = SettingsDomain and SettingsDomain.BuildStatus and SettingsDomain.BuildStatus(info) or {}

  if panel.enabledLabel then
    panel.enabledLabel:SetText(
      Fundraiser:T("OPTIONS_STATUS_ENABLED_FMT", Fundraiser:T(status.enabledKey or "OPTIONS_STATUS_ENABLED_OFF"))
    )
  end
  if panel.guildLabel then
    local guild = status.guildText or Fundraiser:T(status.guildKey or "OPTIONS_STATUS_GUILD_NONE")
    panel.guildLabel:SetText(Fundraiser:T("OPTIONS_STATUS_GUILD_FMT", guild))
  end
  if panel.eventLabel then
    local ev = status.eventText or Fundraiser:T(status.eventKey or "OPTIONS_STATUS_EVENT_NONE")
    panel.eventLabel:SetText(Fundraiser:T("OPTIONS_STATUS_EVENT_FMT", ev))
  end
  if panel.accessLabel then
    panel.accessLabel:SetText(
      Fundraiser:T("OPTIONS_STATUS_ACCESS_FMT", Fundraiser:T(status.accessKey or "OPTIONS_STATUS_ACCESS_NO"))
    )
  end

  if panel.intervalBox and Store and Store.GetSettings then
    local settings = Store:GetSettings()
    panel.intervalBox:SetText(tostring((settings.defaultReminderInterval or 86400) / 3600))
    panel.rankBox:SetText(tostring(settings.defaultMinAdminRank or 0))
  end

  if panel.openButton then
    if canOpen then
      panel.openButton:Show()
    else
      panel.openButton:Hide()
    end
  end
end

local function ApplySettingsFromPanel(panel)
  local Store = Fundraiser.Adapters and Fundraiser.Adapters.Store
  if not Store or not Store.SetSettings or not panel then
    return
  end
  local hours = tonumber(panel.intervalBox and panel.intervalBox:GetText())
  local rank = tonumber(panel.rankBox and panel.rankBox:GetText())
  local seconds = hours and math.floor(hours * 3600) or nil
  local _, err = Store:SetSettings({
    defaultReminderInterval = seconds,
    defaultMinAdminRank = rank,
  })
  if err and DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("OPTIONS_SAVE_FAILED", tostring(err)))
  end
  RefreshPanel(panel)
end

function Options:Open()
  if not self.category then
    self:Initialize()
  end
  if not self.category or not Settings or not Settings.OpenToCategory then
    return
  end
  -- Forever/Settings variants accept category object or ID/name.
  local ok = pcall(Settings.OpenToCategory, self.category)
  if not ok then
    local id = self.category.ID or (self.panel and self.panel.name)
    if id then
      pcall(Settings.OpenToCategory, id)
    end
  end
end

function Options:Initialize()
  if self.registered then
    return
  end
  if not Settings or not Settings.RegisterCanvasLayoutCategory then
    return
  end

  local panel = CreateFrame("Frame", "FundraiserOptionsPanel")
  panel.name = GetMeta("Title", Fundraiser:T("ADDON_NAME"))
  panel:Hide()

  function panel:OnCommit()
    ApplySettingsFromPanel(self)
  end
  function panel:OnDefault()
  end
  function panel:OnRefresh()
    RefreshPanel(self)
  end

  local y = -16

  local icon = panel:CreateTexture(nil, "ARTWORK")
  icon:SetSize(48, 48)
  icon:SetPoint("TOPLEFT", 16, y)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("LEFT", icon, "RIGHT", 12, 8)
  title:SetText(panel.name)

  local version = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  version:SetText(Fundraiser:T("OPTIONS_VERSION_FMT", GetDisplayVersion()))

  y = y - 68

  local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  help:SetPoint("TOPLEFT", 16, y)
  help:SetWidth(520)
  help:SetJustifyH("LEFT")
  help:SetJustifyV("TOP")
  help:SetWordWrap(true)
  help:SetText(Fundraiser:T("OPTIONS_HELP"))
  y = y - 48

  local statusHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  statusHeader:SetPoint("TOPLEFT", 16, y)
  statusHeader:SetText(Fundraiser:T("OPTIONS_SECTION_STATUS"))
  y = y - 20

  panel.enabledLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  panel.enabledLabel:SetPoint("TOPLEFT", 16, y)
  y = y - 18
  panel.guildLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  panel.guildLabel:SetPoint("TOPLEFT", 16, y)
  y = y - 18
  panel.eventLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  panel.eventLabel:SetPoint("TOPLEFT", 16, y)
  panel.eventLabel:SetWidth(520)
  panel.eventLabel:SetJustifyH("LEFT")
  y = y - 18
  panel.accessLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  panel.accessLabel:SetPoint("TOPLEFT", 16, y)
  y = y - 28

  local settingsHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  settingsHeader:SetPoint("TOPLEFT", 16, y)
  settingsHeader:SetText(Fundraiser:T("OPTIONS_SECTION_SETTINGS"))
  y = y - 20

  local intervalLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  intervalLabel:SetPoint("TOPLEFT", 16, y)
  intervalLabel:SetText(Fundraiser:T("OPTIONS_LABEL_DEFAULT_INTERVAL"))
  y = y - 18
  panel.intervalBox = CreateFrame("EditBox", "FundraiserOptionsInterval", panel, "InputBoxTemplate")
  panel.intervalBox:SetSize(80, 20)
  panel.intervalBox:SetPoint("TOPLEFT", 16, y)
  panel.intervalBox:SetAutoFocus(false)
  y = y - 28

  local rankLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  rankLabel:SetPoint("TOPLEFT", 16, y)
  rankLabel:SetText(Fundraiser:T("OPTIONS_LABEL_MIN_ADMIN_RANK"))
  y = y - 18
  panel.rankBox = CreateFrame("EditBox", "FundraiserOptionsMinRank", panel, "InputBoxTemplate")
  panel.rankBox:SetSize(80, 20)
  panel.rankBox:SetPoint("TOPLEFT", 16, y)
  panel.rankBox:SetAutoFocus(false)
  y = y - 28

  local applyButton = CreateFrame("Button", "FundraiserOptionsApplyButton", panel, "UIPanelButtonTemplate")
  applyButton:SetSize(120, 24)
  applyButton:SetPoint("TOPLEFT", 16, y)
  applyButton:SetText(Fundraiser:T("OPTIONS_APPLY"))
  applyButton:SetScript("OnClick", function()
    ApplySettingsFromPanel(panel)
  end)
  y = y - 36

  panel.openButton = CreateFrame("Button", "FundraiserOptionsOpenButton", panel, "UIPanelButtonTemplate")
  panel.openButton:SetSize(160, 24)
  panel.openButton:SetPoint("TOPLEFT", 16, y)
  panel.openButton:SetText(Fundraiser:T("OPTIONS_OPEN"))
  panel.openButton:SetScript("OnClick", function()
    if SettingsPanel and HideUIPanel then
      HideUIPanel(SettingsPanel)
    end
    if Fundraiser.ToggleWindow then
      Fundraiser:ToggleWindow()
    end
  end)

  local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, panel.name)
  if not ok or not category then
    return
  end
  category.ID = panel.name
  local registeredOk = pcall(Settings.RegisterAddOnCategory, category)
  if not registeredOk then
    return
  end

  self.panel = panel
  self.category = category
  self.registered = true
  RefreshPanel(panel)
end
