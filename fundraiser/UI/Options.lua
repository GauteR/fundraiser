-- Options → AddOns → Fundraiser.
-- Blizzard Settings-style canvas: section headers, left labels, right values/controls, scroll.
Fundraiser = Fundraiser or {}
Fundraiser.UI = Fundraiser.UI or {}
Fundraiser.Options = Fundraiser.Options or {}

local Options = Fundraiser.Options
local ADDON_FOLDER = "fundraiser"

local COL_NAME_X = 8
local COL_STATUS_X = 240
local COL_VERSION_X = 380
local ROW_HEIGHT = 18
local MAX_INSTALL_ROWS = 40
local INSTALL_TABLE_HEIGHT = 160
local CONTENT_WIDTH = 560
local LABEL_WIDTH = 280
local CONTROL_X = 320

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

local function AttachTooltip(frame, titleKey, bodyKey)
  frame:EnableMouse(true)
  frame:SetScript("OnEnter", function(self)
    if not GameTooltip then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(Fundraiser:T(titleKey), 1, 1, 1)
    if bodyKey then
      GameTooltip:AddLine(Fundraiser:T(bodyKey), 1, 0.82, 0, true)
    end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
end

local function StatusLocaleKey(status)
  if status == "installed" then
    return "OPTIONS_INSTALL_STATUS_INSTALLED"
  end
  if status == "stale" then
    return "OPTIONS_INSTALL_STATUS_STALE"
  end
  return "OPTIONS_INSTALL_STATUS_MISSING"
end

local function EnsureInstallRow(panel, index)
  panel.installRows = panel.installRows or {}
  local row = panel.installRows[index]
  if row then
    return row
  end
  local parent = panel.installContent
  row = CreateFrame("Frame", nil, parent)
  row:SetSize(CONTENT_WIDTH - 40, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))

  -- Subtle highlight bar like Settings list rows.
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0.06)

  row.nameFS = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.nameFS:SetPoint("LEFT", row, "LEFT", COL_NAME_X, 0)
  row.nameFS:SetWidth(220)
  row.nameFS:SetJustifyH("LEFT")

  row.statusFS = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.statusFS:SetPoint("LEFT", row, "LEFT", COL_STATUS_X, 0)
  row.statusFS:SetWidth(130)
  row.statusFS:SetJustifyH("LEFT")

  row.versionFS = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.versionFS:SetPoint("LEFT", row, "LEFT", COL_VERSION_X, 0)
  row.versionFS:SetWidth(120)
  row.versionFS:SetJustifyH("LEFT")

  panel.installRows[index] = row
  return row
end

local function RefreshInstallTable(panel, rows)
  if not panel or not panel.installContent then
    return
  end
  rows = rows or {}
  local n = math.min(#rows, MAX_INSTALL_ROWS)
  for i = 1, n do
    local data = rows[i]
    local row = EnsureInstallRow(panel, i)
    row:Show()
    row.nameFS:SetText(data.name or "?")
    row.statusFS:SetText(Fundraiser:T(StatusLocaleKey(data.status)))
    local ver = data.version
    if not ver or ver == "" then
      ver = Fundraiser:T("OPTIONS_INSTALL_VERSION_UNKNOWN")
    end
    row.versionFS:SetText(ver)
  end
  for i = n + 1, #(panel.installRows or {}) do
    panel.installRows[i]:Hide()
  end
  panel.installContent:SetHeight(math.max(n * ROW_HEIGHT, 1))
  if panel.installScroll and panel.installScroll.UpdateScrollChildRect then
    panel.installScroll:UpdateScrollChildRect()
  end
  if panel.installEmpty then
    if n == 0 then
      panel.installEmpty:Show()
    else
      panel.installEmpty:Hide()
    end
  end
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
  local installOnline, installInstalled = 0, 0
  local installRows = {}
  if guildName and SettingsDomain and SettingsDomain.CountOnlineInstalls and Roster and Roster.GetMembers then
    if Roster.Request then
      Roster:Request()
    end
    local now = (GetServerTime and GetServerTime()) or (time and time()) or 0
    local stale = (Fundraiser.Config and tonumber(Fundraiser.Config.PRESENCE_STALE)) or 600
    local presence = Store and Store.GetPresence and Store:GetPresence() or {}
    local counts = SettingsDomain.CountOnlineInstalls(Roster:GetMembers(), presence, now, stale)
    installOnline = counts.online
    installInstalled = counts.installed
    installRows = counts.rows or {}
  end
  local info = {
    enabled = Fundraiser.IsEnabled and Fundraiser:IsEnabled() or false,
    guildName = guildName,
    eventName = event and event.name or nil,
    eventTarget = event and event.target or nil,
    canOpenAdmin = canOpen,
    installOnline = installOnline,
    installInstalled = installInstalled,
  }
  local status = SettingsDomain and SettingsDomain.BuildStatus and SettingsDomain.BuildStatus(info) or {}

  if panel.enabledValue then
    panel.enabledValue:SetText(Fundraiser:T(status.enabledKey or "OPTIONS_STATUS_ENABLED_OFF"))
  end
  if panel.guildValue then
    panel.guildValue:SetText(status.guildText or Fundraiser:T(status.guildKey or "OPTIONS_STATUS_GUILD_NONE"))
  end
  if panel.eventValue then
    panel.eventValue:SetText(status.eventText or Fundraiser:T(status.eventKey or "OPTIONS_STATUS_EVENT_NONE"))
  end
  if panel.accessValue then
    panel.accessValue:SetText(Fundraiser:T(status.accessKey or "OPTIONS_STATUS_ACCESS_NO"))
  end
  if panel.installSummaryValue then
    if status.installKey then
      panel.installSummaryValue:SetText(Fundraiser:T(status.installKey))
    else
      panel.installSummaryValue:SetText(
        Fundraiser:T("OPTIONS_STATUS_INSTALL_FMT", status.installInstalled or 0, status.installOnline or 0)
      )
    end
  end

  RefreshInstallTable(panel, installRows)

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

  if panel.cleanupFrame then
    if canOpen then
      panel.cleanupFrame:Show()
    else
      panel.cleanupFrame:Hide()
    end
  end
end

local function ConfirmAction(dialogKey, textKey, onAccept)
  if StaticPopupDialogs and StaticPopup_Show then
    StaticPopupDialogs[dialogKey] = {
      text = Fundraiser:T(textKey),
      button1 = YES or ACCEPT or "Yes",
      button2 = NO or CANCEL or "No",
      OnAccept = onAccept,
      timeout = 0,
      whileDead = 1,
      hideOnEscape = 1,
      preferredIndex = 3,
    }
    StaticPopup_Show(dialogKey)
    return
  end
  onAccept()
end

local function AfterLocalDataChange(panel)
  if Fundraiser.UI and Fundraiser.UI.Window and Fundraiser.UI.Window.Refresh then
    Fundraiser.UI.Window:Refresh()
  end
  if Fundraiser.UI and Fundraiser.UI.Reminder and Fundraiser.UI.Reminder.Hide then
    Fundraiser.UI.Reminder:Hide()
  end
  RefreshPanel(panel)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("OPTIONS_CLEANUP_DONE"))
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

local function AddSectionHeader(parent, text, y)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetPoint("TOPLEFT", 16, y)
  fs:SetText(text)
  return y - 22
end

local function AddStatusRow(parent, labelText, y)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(CONTENT_WIDTH - 32, 22)
  row:SetPoint("TOPLEFT", 16, y)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(1, 1, 1, 0.04)

  local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  label:SetPoint("LEFT", 8, 0)
  label:SetWidth(LABEL_WIDTH)
  label:SetJustifyH("LEFT")
  label:SetText(labelText)

  local value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  value:SetPoint("LEFT", CONTROL_X - 16, 0)
  value:SetWidth(220)
  value:SetJustifyH("LEFT")
  return value, y - 24
end

local function AddEditRow(parent, labelText, tipTitle, tipBody, nameSuffix, y)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(CONTENT_WIDTH - 32, 26)
  row:SetPoint("TOPLEFT", 16, y)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(1, 1, 1, 0.04)

  local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  label:SetPoint("LEFT", 8, 0)
  label:SetWidth(LABEL_WIDTH)
  label:SetJustifyH("LEFT")
  label:SetText(labelText)
  AttachTooltip(row, tipTitle, tipBody)

  local box = CreateFrame("EditBox", "FundraiserOptions" .. nameSuffix, row, "InputBoxTemplate")
  box:SetSize(80, 20)
  box:SetPoint("LEFT", CONTROL_X - 16, 0)
  box:SetAutoFocus(false)
  return box, y - 28
end

function Options:Open()
  if not self.category then
    self:Initialize()
  end
  if not self.category or not Settings or not Settings.OpenToCategory then
    return
  end
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

  -- Outer Settings canvas; inner scroll matches Blizzard AddOns option pages.
  local scroll = CreateFrame("ScrollFrame", "FundraiserOptionsScroll", panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -8)
  scroll:SetPoint("BOTTOMRIGHT", -28, 8)
  panel.mainScroll = scroll

  local content = CreateFrame("Frame", "FundraiserOptionsContent", scroll)
  content:SetSize(CONTENT_WIDTH, 900)
  scroll:SetScrollChild(content)
  panel.content = content

  local y = -12

  local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, y)
  title:SetText(panel.name)

  local version = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  version:SetText(Fundraiser:T("OPTIONS_VERSION_FMT", GetDisplayVersion()))
  y = y - 40

  local help = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  help:SetPoint("TOPLEFT", 16, y)
  help:SetWidth(CONTENT_WIDTH - 40)
  help:SetJustifyH("LEFT")
  help:SetJustifyV("TOP")
  help:SetWordWrap(true)
  help:SetText(Fundraiser:T("OPTIONS_HELP"))
  y = y - 36

  y = AddSectionHeader(content, Fundraiser:T("OPTIONS_SECTION_STATUS"), y)
  panel.enabledValue, y = AddStatusRow(content, Fundraiser:T("OPTIONS_ROW_ENABLED"), y)
  panel.guildValue, y = AddStatusRow(content, Fundraiser:T("OPTIONS_ROW_GUILD"), y)
  panel.eventValue, y = AddStatusRow(content, Fundraiser:T("OPTIONS_ROW_EVENT"), y)
  panel.accessValue, y = AddStatusRow(content, Fundraiser:T("OPTIONS_ROW_ACCESS"), y)
  panel.installSummaryValue, y = AddStatusRow(content, Fundraiser:T("OPTIONS_ROW_INSTALL_SUMMARY"), y)
  y = y - 8

  y = AddSectionHeader(content, Fundraiser:T("OPTIONS_SECTION_INSTALL"), y)

  local colName = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  colName:SetPoint("TOPLEFT", 24 + COL_NAME_X, y)
  colName:SetText(Fundraiser:T("OPTIONS_INSTALL_COL_NAME"))
  local colStatus = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  colStatus:SetPoint("TOPLEFT", 24 + COL_STATUS_X, y)
  colStatus:SetText(Fundraiser:T("OPTIONS_INSTALL_COL_STATUS"))
  local colVersion = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  colVersion:SetPoint("TOPLEFT", 24 + COL_VERSION_X, y)
  colVersion:SetText(Fundraiser:T("OPTIONS_INSTALL_COL_VERSION"))
  y = y - 16

  local installScroll = CreateFrame("ScrollFrame", "FundraiserOptionsInstallScroll", content, "UIPanelScrollFrameTemplate")
  installScroll:SetPoint("TOPLEFT", 16, y)
  installScroll:SetSize(CONTENT_WIDTH - 32, INSTALL_TABLE_HEIGHT)
  panel.installScroll = installScroll

  local installContent = CreateFrame("Frame", "FundraiserOptionsInstallContent", installScroll)
  installContent:SetSize(CONTENT_WIDTH - 48, 1)
  installScroll:SetScrollChild(installContent)
  panel.installContent = installContent
  panel.installRows = {}

  panel.installEmpty = installContent:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  panel.installEmpty:SetPoint("TOPLEFT", installContent, "TOPLEFT", COL_NAME_X, 0)
  panel.installEmpty:SetText(Fundraiser:T("OPTIONS_INSTALL_EMPTY"))

  y = y - INSTALL_TABLE_HEIGHT - 16

  y = AddSectionHeader(content, Fundraiser:T("OPTIONS_SECTION_SETTINGS"), y)
  panel.intervalBox, y = AddEditRow(
    content,
    Fundraiser:T("OPTIONS_LABEL_DEFAULT_INTERVAL"),
    "OPTIONS_TIP_INTERVAL_TITLE",
    "OPTIONS_TIP_INTERVAL_BODY",
    "Interval",
    y
  )
  panel.rankBox, y = AddEditRow(
    content,
    Fundraiser:T("OPTIONS_LABEL_MIN_ADMIN_RANK"),
    "OPTIONS_TIP_RANK_TITLE",
    "OPTIONS_TIP_RANK_BODY",
    "MinRank",
    y
  )
  y = y - 8

  local applyButton = CreateFrame("Button", "FundraiserOptionsApplyButton", content, "UIPanelButtonTemplate")
  applyButton:SetSize(120, 24)
  applyButton:SetPoint("TOPLEFT", 16, y)
  applyButton:SetText(Fundraiser:T("OPTIONS_APPLY"))
  applyButton:SetScript("OnClick", function()
    ApplySettingsFromPanel(panel)
  end)

  panel.openButton = CreateFrame("Button", "FundraiserOptionsOpenButton", content, "UIPanelButtonTemplate")
  panel.openButton:SetSize(160, 24)
  panel.openButton:SetPoint("LEFT", applyButton, "RIGHT", 8, 0)
  panel.openButton:SetText(Fundraiser:T("OPTIONS_OPEN"))
  panel.openButton:SetScript("OnClick", function()
    if SettingsPanel and HideUIPanel then
      HideUIPanel(SettingsPanel)
    end
    if Fundraiser.ToggleWindow then
      Fundraiser:ToggleWindow()
    end
  end)
  y = y - 36

  -- Admin-only local cleanup (does not wipe other clients' mesh replicas).
  local cleanup = CreateFrame("Frame", "FundraiserOptionsCleanup", content)
  cleanup:SetSize(CONTENT_WIDTH - 32, 150)
  cleanup:SetPoint("TOPLEFT", 16, y)
  panel.cleanupFrame = cleanup

  local cleanupHeader = cleanup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  cleanupHeader:SetPoint("TOPLEFT", 0, 0)
  cleanupHeader:SetText(Fundraiser:T("OPTIONS_SECTION_CLEANUP"))

  local cleanupHelp = cleanup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  cleanupHelp:SetPoint("TOPLEFT", 0, -20)
  cleanupHelp:SetWidth(CONTENT_WIDTH - 40)
  cleanupHelp:SetJustifyH("LEFT")
  cleanupHelp:SetWordWrap(true)
  cleanupHelp:SetText(Fundraiser:T("OPTIONS_CLEANUP_HELP"))

  local resetAll = CreateFrame("Button", "FundraiserOptionsResetAll", cleanup, "UIPanelButtonTemplate")
  resetAll:SetSize(140, 24)
  resetAll:SetPoint("TOPLEFT", 0, -52)
  resetAll:SetText(Fundraiser:T("OPTIONS_BTN_RESET_ALL"))
  AttachTooltip(resetAll, "OPTIONS_TIP_RESET_ALL_TITLE", "OPTIONS_TIP_RESET_ALL_BODY")
  resetAll:SetScript("OnClick", function()
    if not (Fundraiser.CanOpenAdminUi and Fundraiser:CanOpenAdminUi()) then
      return
    end
    ConfirmAction("FUNDRAISER_RESET_ALL", "OPTIONS_CONFIRM_RESET_ALL", function()
      local Store = Fundraiser.Adapters and Fundraiser.Adapters.Store
      if Store and Store.ResetAll then
        Store:ResetAll()
      end
      AfterLocalDataChange(panel)
    end)
  end)

  local clearPresence = CreateFrame("Button", "FundraiserOptionsClearPresence", cleanup, "UIPanelButtonTemplate")
  clearPresence:SetSize(140, 24)
  clearPresence:SetPoint("LEFT", resetAll, "RIGHT", 8, 0)
  clearPresence:SetText(Fundraiser:T("OPTIONS_BTN_CLEAR_PRESENCE"))
  AttachTooltip(clearPresence, "OPTIONS_TIP_CLEAR_PRESENCE_TITLE", "OPTIONS_TIP_CLEAR_PRESENCE_BODY")
  clearPresence:SetScript("OnClick", function()
    if not (Fundraiser.CanOpenAdminUi and Fundraiser:CanOpenAdminUi()) then
      return
    end
    ConfirmAction("FUNDRAISER_CLEAR_PRESENCE", "OPTIONS_CONFIRM_CLEAR_PRESENCE", function()
      local Store = Fundraiser.Adapters and Fundraiser.Adapters.Store
      if Store and Store.ClearPresence then
        Store:ClearPresence()
      end
      AfterLocalDataChange(panel)
    end)
  end)

  local clearLedger = CreateFrame("Button", "FundraiserOptionsClearLedger", cleanup, "UIPanelButtonTemplate")
  clearLedger:SetSize(140, 24)
  clearLedger:SetPoint("TOPLEFT", resetAll, "BOTTOMLEFT", 0, -8)
  clearLedger:SetText(Fundraiser:T("OPTIONS_BTN_CLEAR_LEDGER"))
  AttachTooltip(clearLedger, "OPTIONS_TIP_CLEAR_LEDGER_TITLE", "OPTIONS_TIP_CLEAR_LEDGER_BODY")
  clearLedger:SetScript("OnClick", function()
    if not (Fundraiser.CanOpenAdminUi and Fundraiser:CanOpenAdminUi()) then
      return
    end
    ConfirmAction("FUNDRAISER_CLEAR_LEDGER", "OPTIONS_CONFIRM_CLEAR_LEDGER", function()
      local Store = Fundraiser.Adapters and Fundraiser.Adapters.Store
      if Store and Store.ClearLedger then
        Store:ClearLedger()
      end
      AfterLocalDataChange(panel)
    end)
  end)

  local clearEvent = CreateFrame("Button", "FundraiserOptionsClearEvent", cleanup, "UIPanelButtonTemplate")
  clearEvent:SetSize(140, 24)
  clearEvent:SetPoint("LEFT", clearLedger, "RIGHT", 8, 0)
  clearEvent:SetText(Fundraiser:T("OPTIONS_BTN_CLEAR_EVENT"))
  AttachTooltip(clearEvent, "OPTIONS_TIP_CLEAR_EVENT_TITLE", "OPTIONS_TIP_CLEAR_EVENT_BODY")
  clearEvent:SetScript("OnClick", function()
    if not (Fundraiser.CanOpenAdminUi and Fundraiser:CanOpenAdminUi()) then
      return
    end
    ConfirmAction("FUNDRAISER_CLEAR_EVENT", "OPTIONS_CONFIRM_CLEAR_EVENT", function()
      local Store = Fundraiser.Adapters and Fundraiser.Adapters.Store
      if Store and Store.ClearEvent then
        Store:ClearEvent()
      end
      AfterLocalDataChange(panel)
    end)
  end)

  local broadcastReset = CreateFrame("Button", "FundraiserOptionsBroadcastReset", cleanup, "UIPanelButtonTemplate")
  broadcastReset:SetSize(160, 24)
  broadcastReset:SetPoint("TOPLEFT", clearLedger, "BOTTOMLEFT", 0, -8)
  broadcastReset:SetText(Fundraiser:T("OPTIONS_BTN_BROADCAST_RESET"))
  AttachTooltip(broadcastReset, "OPTIONS_TIP_BROADCAST_RESET_TITLE", "OPTIONS_TIP_BROADCAST_RESET_BODY")
  broadcastReset:SetScript("OnClick", function()
    if not (Fundraiser.CanOpenAdminUi and Fundraiser:CanOpenAdminUi()) then
      return
    end
    ConfirmAction("FUNDRAISER_BROADCAST_RESET", "OPTIONS_CONFIRM_BROADCAST_RESET", function()
      local Sync = Fundraiser.Adapters and Fundraiser.Adapters.ThinGuildSync
      -- BroadcastReset applies local wipe + epoch bump, then notifies guild.
      local sent = Sync and Sync.BroadcastReset and Sync:BroadcastReset("all")
      AfterLocalDataChange(panel)
      if DEFAULT_CHAT_FRAME then
        if sent then
          DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("OPTIONS_BROADCAST_RESET_SENT"))
        else
          DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("OPTIONS_BROADCAST_RESET_FAILED"))
        end
      end
    end)
  end)

  y = y - 160
  content:SetHeight(math.abs(y) + 24)

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
