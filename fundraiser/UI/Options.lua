-- Options → AddOns → Fundraiser (Settings canvas).
-- Layout mirrors Blizzard AddOns pages: section headers, left labels, right controls,
-- outer scroll for the whole page, nested scroll for the online-install table.
-- Editable knobs: default reminder interval (hours in UI, seconds in Store) and
-- global min admin rank. Per-event interval stays on the admin window.
Fundraiser = Fundraiser or {}
Fundraiser.UI = Fundraiser.UI or {}
Fundraiser.Options = Fundraiser.Options or {}

local Options = Fundraiser.Options
local ADDON_FOLDER = "fundraiser"

-- Install table columns (px from row left). Keep in sync with header FontStrings.
local COL_NAME_X = 8
local COL_STATUS_X = 240
local COL_VERSION_X = 380
local ROW_HEIGHT = 18
local MAX_INSTALL_ROWS = 40
local INSTALL_TABLE_HEIGHT = 160
local CONTENT_WIDTH = 560
local LABEL_WIDTH = 280
-- X of right-hand value/control column on status and edit rows.
local CONTROL_X = 320
-- Ignored items list: rows shown before "+N more".
local MAX_IGNORED_ROWS = 8
local COPPER_PER_GOLD = 10000

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

  local TP = Fundraiser.Domain and Fundraiser.Domain.TargetPrefs
  if panel.minValueBox and TP and Store and Store.GetTargetPrefs then
    local prefs = Store:GetTargetPrefs()
    panel.minValueBox:SetText(prefs.minValue and tostring(prefs.minValue / COPPER_PER_GOLD) or "")
    local list = TP.IgnoredList(prefs)
    for i = 1, MAX_IGNORED_ROWS do
      local row, item = panel.ignoredRows[i], list[i]
      if item then
        row.itemId = item.itemId
        row.label:SetText(item.name ~= "" and item.name or ("#" .. item.itemId))
        row:Show()
      else
        row:Hide()
      end
    end
    if #list == 0 then
      panel.ignoredEmpty:Show()
    else
      panel.ignoredEmpty:Hide()
    end
    if #list > MAX_IGNORED_ROWS then
      panel.ignoredMore:SetText(Fundraiser:T("OPTIONS_IGNORED_MORE_FMT", #list - MAX_IGNORED_ROWS))
    else
      panel.ignoredMore:SetText("")
    end
  end

  if panel.openButton then
    if canOpen then
      panel.openButton:Show()
    else
      panel.openButton:Hide()
    end
  end

  -- Danger zone + divider: only for admins.
  if panel.dangerFrame then
    if canOpen then
      panel.dangerFrame:Show()
    else
      panel.dangerFrame:Hide()
    end
  end
  if panel.dangerDivider then
    if canOpen then
      panel.dangerDivider:Show()
    else
      panel.dangerDivider:Hide()
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

local function EditBoxOf(dialog)
  return dialog.editBox or dialog.EditBox
end

local function Say(key, ...)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T(key, ...))
  end
end

-- Show the ignore list as one copyable line (Ctrl+C) in a popup edit box.
local function ShowIgnoreExport()
  local Store = Fundraiser.Adapters and Fundraiser.Adapters.Store
  local TP = Fundraiser.Domain.TargetPrefs
  if not (Store and TP and StaticPopupDialogs and StaticPopup_Show) then
    return
  end
  local text = TP.Export(Store:GetTargetPrefs())
  StaticPopupDialogs["FUNDRAISER_IGNORE_EXPORT"] = {
    text = Fundraiser:T("OPTIONS_IGNORED_EXPORT_TEXT"),
    button1 = CLOSE or OKAY or "Close",
    hasEditBox = 1,
    editBoxWidth = 340,
    maxLetters = 0,
    OnShow = function(self)
      local box = EditBoxOf(self)
      box:SetText(text)
      box:HighlightText()
      box:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self)
      self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
  }
  StaticPopup_Show("FUNDRAISER_IGNORE_EXPORT")
end

-- Ask for an export string (paste with Ctrl+V) and merge it into the ignore list.
local function ShowIgnoreImport(panel)
  if not (StaticPopupDialogs and StaticPopup_Show) then
    return
  end
  StaticPopupDialogs["FUNDRAISER_IGNORE_IMPORT"] = {
    text = Fundraiser:T("OPTIONS_IGNORED_IMPORT_TEXT"),
    button1 = Fundraiser:T("OPTIONS_IGNORED_IMPORT"),
    button2 = CANCEL or "Cancel",
    hasEditBox = 1,
    editBoxWidth = 340,
    maxLetters = 0,
    OnShow = function(self)
      EditBoxOf(self):SetFocus()
    end,
    OnAccept = function(self)
      local Store = Fundraiser.Adapters and Fundraiser.Adapters.Store
      local TP = Fundraiser.Domain.TargetPrefs
      local prefs = Store:GetTargetPrefs()
      local ok, info = TP.Import(prefs, EditBoxOf(self):GetText())
      if not ok then
        Say("OPTIONS_IGNORED_IMPORT_BAD")
        return
      end
      Store:SetTargetPrefs(prefs)
      Say("OPTIONS_IGNORED_IMPORT_DONE_FMT", info.added, info.known, info.rejected)
      RefreshPanel(panel)
      if Fundraiser.UI.Target and Fundraiser.UI.Target.Refresh then
        Fundraiser.UI.Target:Refresh()
      end
    end,
    EditBoxOnEscapePressed = function(self)
      self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
  }
  StaticPopup_Show("FUNDRAISER_IGNORE_IMPORT")
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
    DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("OPTIONS_DANGER_DONE"))
  end
end

-- Persist Options defaults into FundraiserDB.settings and overlay Fundraiser.Config.
-- Interval edit box is hours for officers; Store/Domain keep seconds.
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
  local TP = Fundraiser.Domain and Fundraiser.Domain.TargetPrefs
  if TP and panel.minValueBox and Store.GetTargetPrefs and Store.SetTargetPrefs then
    local prefs = Store:GetTargetPrefs()
    local text = panel.minValueBox:GetText() or ""
    -- Empty clears the override (the config minimum applies again). Input is gold.
    local gold = tonumber(text)
    local ok
    if text:match("^%s*$") then
      ok = TP.SetMinValue(prefs, nil)
    elseif gold then
      ok = TP.SetMinValue(prefs, gold * COPPER_PER_GOLD)
    end
    if ok then
      Store:SetTargetPrefs(prefs)
    elseif DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("OPTIONS_SAVE_FAILED", "bad_min_value"))
    end
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

local function NotifyOpenFailed()
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("OPTIONS_OPEN_FAILED"))
  end
end

-- Pure helper for tests and Open(). Forever often resolves by panel name; also try
-- numeric ID and the category object. Do not rely on overwriting category.ID.
function Options.CollectOpenCandidates(categoryID, category, panelName)
  local candidates = {}
  local function addCandidate(value)
    if value == nil then
      return
    end
    for i = 1, #candidates do
      if candidates[i] == value then
        return
      end
    end
    candidates[#candidates + 1] = value
  end
  -- Name first: matches Settings after RegisterCanvasLayoutCategory(panel, name).
  addCandidate(panelName)
  if category then
    addCandidate(category.ID)
  end
  addCandidate(categoryID)
  addCandidate(category)
  return candidates
end

local function categoryLooksLikeOurs(current, category, categoryID, panelName)
  if current == nil or category == nil then
    return false
  end
  if current == category then
    return true
  end
  local curId
  if current.GetID then
    local ok, id = pcall(current.GetID, current)
    if ok then
      curId = id
    end
  end
  if curId == nil then
    curId = current.ID
  end
  local ours = { categoryID, category.ID, panelName }
  for i = 1, #ours do
    local id = ours[i]
    if id ~= nil and curId ~= nil and tostring(id) == tostring(curId) then
      return true
    end
  end
  if panelName and (current.name == panelName or current.Name == panelName) then
    return true
  end
  return false
end

-- Open Settings to the Fundraiser AddOns page. Forever's OpenToCategory accept
-- name and/or numeric ID; GetCurrentCategory identity checks are unreliable, so
-- treat a shown SettingsPanel after a successful call as a soft success.
function Options:Open()
  if not self.category then
    self:Initialize()
  end
  local category = self.category
  if not category then
    NotifyOpenFailed()
    return
  end

  local panelName = self.categoryName or (self.panel and self.panel.name)
  local categoryID = self.categoryID
  local softOk = false

  local function panelShown()
    return SettingsPanel and SettingsPanel:IsShown()
  end

  local function openedHard()
    if not panelShown() then
      return false
    end
    if not SettingsPanel.GetCurrentCategory then
      return true
    end
    local current = SettingsPanel:GetCurrentCategory()
    if current == nil then
      return true
    end
    return categoryLooksLikeOurs(current, category, categoryID, panelName)
  end

  local function tryOpen(candidate)
    if candidate == nil or not Settings or not Settings.OpenToCategory then
      return false
    end
    -- Some clients need two calls (same quirk as InterfaceOptionsFrame_OpenToCategory).
    local ok1 = pcall(Settings.OpenToCategory, candidate)
    pcall(Settings.OpenToCategory, candidate)
    if not ok1 then
      return false
    end
    if openedHard() then
      return true
    end
    if panelShown() then
      softOk = true
    end
    return false
  end

  if Settings and Settings.OpenToCategory then
    local candidates = Options.CollectOpenCandidates(categoryID, category, panelName)
    for _, candidate in ipairs(candidates) do
      if tryOpen(candidate) then
        return
      end
    end
  end

  -- Pre-Settings / hybrid clients.
  if InterfaceOptionsFrame_OpenToCategory and self.panel then
    InterfaceOptionsFrame_OpenToCategory(self.panel)
    InterfaceOptionsFrame_OpenToCategory(self.panel)
    if panelShown() or (InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown()) then
      return
    end
  end

  if softOk then
    -- Settings is open; category match could not be verified on this client.
    return
  end

  if SettingsPanel and not SettingsPanel:IsShown() and ShowUIPanel then
    ShowUIPanel(SettingsPanel)
  end
  NotifyOpenFailed()
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
  panel.ignoredRows = {}
  if Fundraiser.Domain.TargetPrefs and Fundraiser.Domain.TargetPrefs.Enabled(Fundraiser.Config) then
    panel.minValueBox, y = AddEditRow(
      content,
      Fundraiser:T("OPTIONS_LABEL_TARGET_MIN_VALUE"),
      "OPTIONS_TIP_TARGET_MIN_TITLE",
      "OPTIONS_TIP_TARGET_MIN_BODY",
      "TargetMinValue",
      y
    )
    y = y - 8

    y = AddSectionHeader(content, Fundraiser:T("OPTIONS_SECTION_IGNORED"), y)
    panel.ignoredEmpty = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    panel.ignoredEmpty:SetPoint("TOPLEFT", 24, y)
    panel.ignoredEmpty:SetText(Fundraiser:T("OPTIONS_IGNORED_EMPTY"))
    for i = 1, MAX_IGNORED_ROWS do
      local row = CreateFrame("Frame", nil, content)
      row:SetSize(CONTENT_WIDTH - 32, 22)
      row:SetPoint("TOPLEFT", 16, y - (i - 1) * 24)
      row.bg = row:CreateTexture(nil, "BACKGROUND")
      row.bg:SetAllPoints()
      row.bg:SetColorTexture(1, 1, 1, 0.04)
      row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
      row.label:SetPoint("LEFT", 8, 0)
      row.label:SetWidth(LABEL_WIDTH)
      row.label:SetJustifyH("LEFT")
      local remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
      remove:SetSize(90, 20)
      remove:SetPoint("LEFT", CONTROL_X - 16, 0)
      remove:SetText(Fundraiser:T("OPTIONS_IGNORED_REMOVE"))
      remove:SetScript("OnClick", function()
        local Store = Fundraiser.Adapters and Fundraiser.Adapters.Store
        local TP = Fundraiser.Domain.TargetPrefs
        if Store and row.itemId then
          local prefs = Store:GetTargetPrefs()
          TP.Unignore(prefs, row.itemId)
          Store:SetTargetPrefs(prefs)
        end
        RefreshPanel(panel)
        if Fundraiser.UI.Target and Fundraiser.UI.Target.Refresh then
          Fundraiser.UI.Target:Refresh()
        end
      end)
      row:Hide()
      panel.ignoredRows[i] = row
    end
    y = y - MAX_IGNORED_ROWS * 24
    panel.ignoredMore = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.ignoredMore:SetPoint("TOPLEFT", 24, y)
    y = y - 22
    local exportButton = CreateFrame("Button", "FundraiserOptionsIgnoreExport", content, "UIPanelButtonTemplate")
    exportButton:SetSize(140, 24)
    exportButton:SetPoint("TOPLEFT", 16, y)
    exportButton:SetText(Fundraiser:T("OPTIONS_IGNORED_EXPORT"))
    exportButton:SetScript("OnClick", ShowIgnoreExport)
    local importButton = CreateFrame("Button", "FundraiserOptionsIgnoreImport", content, "UIPanelButtonTemplate")
    importButton:SetSize(140, 24)
    importButton:SetPoint("LEFT", exportButton, "RIGHT", 8, 0)
    importButton:SetText(Fundraiser:T("OPTIONS_IGNORED_IMPORT"))
    importButton:SetScript("OnClick", function()
      ShowIgnoreImport(panel)
    end)
    y = y - 32
  end
  y = y - 8

  -- Safe actions under Defaults: Apply for everyone; Open Fundraiser for admins.
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
  y = y - 40

  -- Horizontal rule separates Defaults from admin-only destructive actions.
  local divider = content:CreateTexture(nil, "ARTWORK")
  divider:SetColorTexture(0.5, 0.5, 0.5, 0.6)
  divider:SetHeight(1)
  divider:SetPoint("TOPLEFT", 16, y)
  divider:SetPoint("TOPRIGHT", content, "TOPRIGHT", -16, y)
  panel.dangerDivider = divider
  y = y - 16

  -- Admin-only Danger zone (local clears + guild broadcast wipe).
  local DANGER_BTN_W = 148
  local DANGER_BTN_H = 24
  local DANGER_GAP = 8
  local danger = CreateFrame("Frame", "FundraiserOptionsDanger", content)
  danger:SetSize(CONTENT_WIDTH - 32, 130)
  danger:SetPoint("TOPLEFT", 16, y)
  panel.dangerFrame = danger

  local dangerHeader = danger:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  dangerHeader:SetPoint("TOPLEFT", 0, 0)
  dangerHeader:SetText(Fundraiser:T("OPTIONS_SECTION_DANGER"))

  local dangerHelp = danger:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  dangerHelp:SetPoint("TOPLEFT", 0, -18)
  dangerHelp:SetWidth(CONTENT_WIDTH - 40)
  dangerHelp:SetJustifyH("LEFT")
  dangerHelp:SetWordWrap(true)
  dangerHelp:SetText(Fundraiser:T("OPTIONS_DANGER_HELP"))

  local resetAll = CreateFrame("Button", "FundraiserOptionsResetAll", danger, "UIPanelButtonTemplate")
  resetAll:SetSize(DANGER_BTN_W, DANGER_BTN_H)
  resetAll:SetPoint("TOPLEFT", 0, -48)
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

  local clearPresence = CreateFrame("Button", "FundraiserOptionsClearPresence", danger, "UIPanelButtonTemplate")
  clearPresence:SetSize(DANGER_BTN_W, DANGER_BTN_H)
  clearPresence:SetPoint("LEFT", resetAll, "RIGHT", DANGER_GAP, 0)
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

  local clearLedger = CreateFrame("Button", "FundraiserOptionsClearLedger", danger, "UIPanelButtonTemplate")
  clearLedger:SetSize(DANGER_BTN_W, DANGER_BTN_H)
  clearLedger:SetPoint("LEFT", clearPresence, "RIGHT", DANGER_GAP, 0)
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

  local clearEvent = CreateFrame("Button", "FundraiserOptionsClearEvent", danger, "UIPanelButtonTemplate")
  clearEvent:SetSize(DANGER_BTN_W, DANGER_BTN_H)
  clearEvent:SetPoint("TOPLEFT", resetAll, "BOTTOMLEFT", 0, -DANGER_GAP)
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

  local broadcastReset = CreateFrame("Button", "FundraiserOptionsBroadcastReset", danger, "UIPanelButtonTemplate")
  broadcastReset:SetSize(DANGER_BTN_W * 2 + DANGER_GAP, DANGER_BTN_H)
  broadcastReset:SetPoint("LEFT", clearEvent, "RIGHT", DANGER_GAP, 0)
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

  y = y - 140
  content:SetHeight(math.abs(y) + 24)

  local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, panel.name)
  if not ok or not category then
    return
  end

  -- Keep the system ID intact. Overwriting category.ID with panel.name breaks
  -- OpenToCategory on clients that key by numeric ID (Forever).
  local categoryID
  if category.GetID then
    local okId, id = pcall(category.GetID, category)
    if okId then
      categoryID = id
    end
  end
  if categoryID == nil and category.ID ~= nil then
    categoryID = category.ID
  end

  local registeredOk = pcall(Settings.RegisterAddOnCategory, category)
  if not registeredOk then
    return
  end

  self.panel = panel
  self.category = category
  self.categoryID = categoryID
  self.categoryName = panel.name
  self.registered = true
  RefreshPanel(panel)
end
