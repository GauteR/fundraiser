-- Shell window: logo band on top, menu on the left, page content on the right.
-- Pages: status dashboard (default), New event form (Publish archives the current campaign),
-- and the ledger (UI/Ledger.lua).
-- Summary data comes from Domain/AdminSummary.lua so the rendering here stays thin.
Fundraiser = Fundraiser or {}
Fundraiser.UI = Fundraiser.UI or {}

local Window = {}
Fundraiser.UI.Window = Window
Window.NAV_W = 140
Window.HEADER_H = 56

-- Content width of a page (status/create/ledger); the shell adds the menu column on the left.
local FRAME_WIDTH = 620
local NAV_W = 140
-- Logo band under the title bar; page panels start this far below the frame top.
local HEADER_H = 56
local TITLE_BAR_H = 26
-- Placeholder until the real logo texture is added (path or file id).
local LOGO_TEXTURE = "Interface\\Icons\\INV_Misc_Coin_01"
local LOGO_SIZE = 44
local SHELL_W = NAV_W + FRAME_WIDTH
-- Tall enough for event + progress/ledger + chart + Settings row above the inset edge.
local FRAME_HEIGHT_STATUS = 490
-- One fixed shell height for every page (the Home page with goal widgets is the tallest).
local SHELL_H = FRAME_HEIGHT_STATUS + HEADER_H
local MARGIN = 16
local CONTENT_WIDTH = FRAME_WIDTH - 2 * MARGIN
local LABEL_WIDTH = 190
local FIELD_X = 214
local ROW_HEIGHT = 30
local CARD_GAP = 10
local CHART_MAX_POINTS = 14
local CHART_MAX_SEGMENTS = 13
local CHART_LEGEND_W = 100
local CHART_Y_LABEL_W = 56
local CHART_X_LABEL_H = 20
local CHART_CARD_H = 168
local PROGRESS_CARD_H = 96
local COPPER_PER_GOLD = 10000
-- Raised line (blue) vs goal line (amber).
local COLOR_RAISED = { 0.30, 0.65, 1.00, 1 }
local COLOR_GOAL = { 0.95, 0.55, 0.15, 1 }

local function money(copper)
  if Fundraiser.FormatCopper then
    return Fundraiser.FormatCopper(copper)
  end
  return tostring(copper or 0) .. "c"
end

local function showTooltip(owner, titleKey, bodyKey)
  if not GameTooltip then
    return
  end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(Fundraiser:T(titleKey), 1, 1, 1)
  GameTooltip:AddLine(Fundraiser:T(bodyKey), 1, 0.82, 0, true)
  GameTooltip:Show()
end

local function hideTooltip()
  if GameTooltip then
    GameTooltip:Hide()
  end
end

local function confirmAction(dialogKey, textKey, onAccept)
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

local function defaultIntervalHours()
  local defaultSeconds = (Fundraiser.Config and tonumber(Fundraiser.Config.DEFAULT_REMINDER_INTERVAL)) or 86400
  return tostring(defaultSeconds / 3600)
end

local function applyCardBackdrop(frame)
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8x8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 8,
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.08, 0.08, 0.1, 0.85)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.45, 0.9)
  else
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.1, 0.85)
  end
end

local function makeCard(parent, name, width, height)
  local template = BackdropTemplateMixin and "BackdropTemplate" or nil
  local card = CreateFrame("Frame", name, parent, template)
  card:SetSize(width, height)
  applyCardBackdrop(card)
  local title = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetJustifyH("LEFT")
  card.title = title
  return card
end

-- Shared with the ledger page so every page uses the same cards.
Window.MakeCard = makeCard

-- Shared size so + (PlusButton art) and panel icon buttons match visually.
local CARD_ACTION_BTN_SIZE = 22

-- Bare icon button — used for Blizzard UI-PlusButton art only.
local function makeCardIconButton(parent, name, size)
  size = size or CARD_ACTION_BTN_SIZE
  local btn = CreateFrame("Button", name, parent)
  btn:SetSize(size, size)
  btn:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -8, 8)
  btn:SetFrameLevel((parent:GetFrameLevel() or 1) + 5)
  btn:EnableMouse(true)
  return btn
end

local function trySetIcon(btn, normal, pushed, highlight)
  if normal and btn.SetNormalTexture then
    btn:SetNormalTexture(normal)
  end
  if pushed and btn.SetPushedTexture then
    btn:SetPushedTexture(pushed)
  end
  if highlight and btn.SetHighlightTexture then
    btn:SetHighlightTexture(highlight)
    -- Existence check must use `.` — `btn:GetHighlightTexture and` is a parse error.
    local ht = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if ht and ht.SetBlendMode then
      ht:SetBlendMode("ADD")
    end
  end
end

local function makeTextIconFallback(btn, glyph)
  local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  fs:SetAllPoints()
  fs:SetJustifyH("CENTER")
  fs:SetJustifyV("MIDDLE")
  fs:SetText(glyph)
  btn.label = fs
end

-- Panel chrome + overlay icon (refresh / play). Same outer size as PlusButton.
local function makeCardPanelIconButton(parent, name, iconPath)
  local size = CARD_ACTION_BTN_SIZE
  local btn = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
  btn:SetSize(size, size)
  btn:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -8, 8)
  btn:SetFrameLevel((parent:GetFrameLevel() or 1) + 5)
  btn:SetText("")
  if btn.ButtonText then
    btn.ButtonText:SetText("")
  end
  local icon = btn:CreateTexture(nil, "OVERLAY")
  icon:SetSize(math.max(12, size - 8), math.max(12, size - 8))
  icon:SetPoint("CENTER", 0, 0)
  if iconPath then
    icon:SetTexture(iconPath)
  end
  btn.icon = icon
  return btn
end

-- Default placement: top edge ~1/8 down the screen, above action bars / unit frames.
function Window:PlaceDefault(frame)
  frame = frame or self.frame
  if not frame then
    return
  end
  local screenH = 768
  if GetScreenHeight then
    screenH = GetScreenHeight() or screenH
  elseif UIParent and UIParent.GetHeight then
    screenH = UIParent:GetHeight() or screenH
  end
  frame:ClearAllPoints()
  frame:SetPoint("TOP", UIParent, "TOP", 0, -math.floor(screenH * 0.12))
  frame:SetFrameStrata("DIALOG")
  if frame.SetToplevel then
    frame:SetToplevel(true)
  end
  if frame.Raise then
    frame:Raise()
  end
end

function Window:Ensure()
  if self.frame then
    return self.frame
  end

  local f = CreateFrame("Frame", "FundraiserFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(SHELL_W, SHELL_H)
  f:SetFrameStrata("DIALOG")
  if f.SetToplevel then
    f:SetToplevel(true)
  end
  self:PlaceDefault(f)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    Window.userMoved = true
    -- Moved by hand: it no longer belongs to the vendor / mail frame and stays open.
    Window.autoOpened, Window.attached, Window.savedPoint = nil, false, nil
  end)
  f:HookScript("OnHide", function()
    Window:OnShellHidden()
  end)
  f:Hide()
  if f.TitleText then
    f.TitleText:SetText(Fundraiser:T("WINDOW_TITLE"))
  end
  tinsert(UISpecialFrames, "FundraiserFrame")

  -- Status dashboard (default).
  self:BuildShell(f)

  local status = CreateFrame("Frame", "FundraiserStatusPanel", f)
  status:SetPoint("TOPLEFT", NAV_W, -HEADER_H)
  status:SetPoint("BOTTOMRIGHT", 0, 0)
  f.statusPanel = status

  local y = -34
  local cardW = CONTENT_WIDTH
  local halfW = math.floor((CONTENT_WIDTH - CARD_GAP) / 2)

  -- Event card (full width).
  local eventCard = makeCard(status, "FundraiserEventCard", cardW, 78)
  eventCard:SetPoint("TOPLEFT", MARGIN, y)
  eventCard.title:SetText(Fundraiser:T("CARD_EVENT"))
  f.eventNameFs = eventCard:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  f.eventNameFs:SetPoint("TOPLEFT", 10, -28)
  f.eventNameFs:SetWidth(cardW - 20)
  f.eventNameFs:SetJustifyH("LEFT")
  f.eventDetailFs = eventCard:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.eventDetailFs:SetPoint("TOPLEFT", f.eventNameFs, "BOTTOMLEFT", 0, -4)
  f.eventDetailFs:SetWidth(cardW - 20)
  f.eventDetailFs:SetJustifyH("LEFT")
  f.eventNoteFs = eventCard:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  f.eventNoteFs:SetPoint("TOPLEFT", f.eventDetailFs, "BOTTOMLEFT", 0, -2)
  f.eventNoteFs:SetWidth(cardW - 20)
  f.eventNoteFs:SetJustifyH("LEFT")
  -- +/- (new / end event) and refresh live in the top bar; the card body is display-only.
  f.eventCard = eventCard
  y = y - 78 - CARD_GAP

  -- Row Y for progress/ledger; chart and actions are re-anchored in Refresh.
  f.dashboardMidY = y

  -- Progress card (left) - only shown when the event has a numeric goal.
  local progressCard = makeCard(status, "FundraiserProgressCard", halfW, PROGRESS_CARD_H)
  progressCard:SetPoint("TOPLEFT", MARGIN, y)
  progressCard.title:SetText(Fundraiser:T("CARD_PROGRESS"))
  f.progressText = progressCard:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  f.progressText:SetPoint("TOPLEFT", 10, -28)
  f.progressText:SetWidth(halfW - 20)
  f.progressText:SetJustifyH("LEFT")
  f.progressPct = progressCard:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  f.progressPct:SetPoint("TOPLEFT", 10, -46)
  f.progressPct:SetJustifyH("LEFT")
  local bar = CreateFrame("StatusBar", "FundraiserProgressBar", progressCard)
  bar:SetSize(halfW - 20, 14)
  bar:SetPoint("BOTTOMLEFT", 10, 14)
  bar:SetMinMaxValues(0, 100)
  bar:SetValue(0)
  if bar.SetStatusBarTexture then
    bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
  end
  if bar.SetStatusBarColor then
    bar:SetStatusBarColor(0.2, 0.7, 0.3, 1)
  end
  local barBg = bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints()
  barBg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
  f.progressBar = bar
  f.progressCard = progressCard

  -- Ledger card (beside progress when goal exists; full width otherwise).
  local ledgerCard = makeCard(status, "FundraiserLedgerCard", halfW, PROGRESS_CARD_H)
  ledgerCard:SetPoint("TOPLEFT", MARGIN + halfW + CARD_GAP, y)
  ledgerCard.title:SetText(Fundraiser:T("CARD_LEDGER"))
  f.ledgerStatus = ledgerCard:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  f.ledgerStatus:SetPoint("TOPLEFT", 10, -32)
  f.ledgerStatus:SetWidth(halfW - 20)
  f.ledgerStatus:SetJustifyH("LEFT")
  f.ledgerStatus:SetJustifyV("TOP")
  -- Whole ledger card is clickable (opens the ledger page); refresh is in the top bar.
  ledgerCard:EnableMouse(true)
  ledgerCard:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" then
      Fundraiser:ToggleLedgerUi()
    end
  end)
  ledgerCard:SetScript("OnEnter", function(self)
    showTooltip(self, "TIP_OPEN_LEDGER_TITLE", "TIP_OPEN_LEDGER_BODY")
  end)
  ledgerCard:SetScript("OnLeave", hideTooltip)
  f.ledgerCard = ledgerCard

  -- Chart card: line plot + axes + legend (only when numeric goal exists).
  local chartCard = makeCard(status, "FundraiserChartCard", cardW, CHART_CARD_H)
  chartCard:SetPoint("TOPLEFT", MARGIN, y - PROGRESS_CARD_H - CARD_GAP)
  chartCard.title:SetText(Fundraiser:T("CARD_CHART"))
  f.chartEmpty = chartCard:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  f.chartEmpty:SetPoint("CENTER", -CHART_LEGEND_W / 2, -6)
  f.chartEmpty:SetText(Fundraiser:T("CHART_EMPTY"))

  local plot = CreateFrame("Frame", "FundraiserChartPlot", chartCard)
  -- Leave room for Y labels (left), legend (right), and X labels (below).
  plot:SetPoint("TOPLEFT", 12 + CHART_Y_LABEL_W, -28)
  plot:SetPoint("BOTTOMRIGHT", -12 - CHART_LEGEND_W, 12 + CHART_X_LABEL_H)
  f.chartPlot = plot

  local plotBg = plot:CreateTexture(nil, "BACKGROUND")
  plotBg:SetAllPoints()
  plotBg:SetColorTexture(0.05, 0.05, 0.06, 0.6)

  f.chartSegments = {}
  f.chartDots = {}
  for i = 1, CHART_MAX_SEGMENTS do
    local tex = plot:CreateTexture(nil, "ARTWORK")
    tex:SetColorTexture(COLOR_RAISED[1], COLOR_RAISED[2], COLOR_RAISED[3], COLOR_RAISED[4])
    tex:Hide()
    f.chartSegments[i] = tex
  end
  for i = 1, CHART_MAX_POINTS do
    local dot = plot:CreateTexture(nil, "OVERLAY")
    dot:SetColorTexture(COLOR_RAISED[1], COLOR_RAISED[2], COLOR_RAISED[3], COLOR_RAISED[4])
    dot:SetSize(5, 5)
    dot:Hide()
    f.chartDots[i] = dot
  end

  local goalLine = plot:CreateTexture(nil, "ARTWORK")
  goalLine:SetColorTexture(COLOR_GOAL[1], COLOR_GOAL[2], COLOR_GOAL[3], COLOR_GOAL[4])
  goalLine:SetHeight(2)
  goalLine:Hide()
  f.chartGoalLine = goalLine

  f.chartYLabels = {}
  for i = 1, 3 do
    local fs = chartCard:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    fs:SetWidth(CHART_Y_LABEL_W - 4)
    fs:SetJustifyH("RIGHT")
    f.chartYLabels[i] = fs
  end
  -- Dedicated goal amount label (amber), left of the goal line.
  local goalYLabel = chartCard:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  goalYLabel:SetWidth(CHART_Y_LABEL_W - 4)
  goalYLabel:SetJustifyH("RIGHT")
  goalYLabel:SetTextColor(COLOR_GOAL[1], COLOR_GOAL[2], COLOR_GOAL[3], 1)
  goalYLabel:Hide()
  f.chartGoalYLabel = goalYLabel
  f.chartXLabels = {}
  for i = 1, CHART_MAX_POINTS do
    local fs = chartCard:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    fs:SetJustifyH("CENTER")
    f.chartXLabels[i] = fs
  end

  -- Legend (right of plot), outside the plot box.
  local legend = CreateFrame("Frame", "FundraiserChartLegend", chartCard)
  legend:SetSize(CHART_LEGEND_W - 8, 52)
  legend:SetPoint("TOPRIGHT", -10, -36)
  local raisedSwatch = legend:CreateTexture(nil, "ARTWORK")
  raisedSwatch:SetSize(16, 3)
  raisedSwatch:SetPoint("TOPLEFT", 0, -2)
  raisedSwatch:SetColorTexture(COLOR_RAISED[1], COLOR_RAISED[2], COLOR_RAISED[3], COLOR_RAISED[4])
  local raisedLbl = legend:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  raisedLbl:SetPoint("LEFT", raisedSwatch, "RIGHT", 8, 0)
  raisedLbl:SetText(Fundraiser:T("CHART_LEGEND_RAISED"))
  local goalSwatch = legend:CreateTexture(nil, "ARTWORK")
  goalSwatch:SetSize(16, 3)
  goalSwatch:SetPoint("TOPLEFT", 0, -26)
  goalSwatch:SetColorTexture(COLOR_GOAL[1], COLOR_GOAL[2], COLOR_GOAL[3], COLOR_GOAL[4])
  local goalLbl = legend:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  goalLbl:SetPoint("LEFT", goalSwatch, "RIGHT", 8, 0)
  goalLbl:SetText(Fundraiser:T("CHART_LEGEND_GOAL"))
  f.chartLegend = legend
  f.chartCard = chartCard

  f.halfW = halfW
  f.cardW = cardW

  -- Create / publish view (hidden by default).
  local create = CreateFrame("Frame", "FundraiserCreatePanel", f)
  create:SetPoint("TOPLEFT", NAV_W, -HEADER_H)
  create:SetPoint("BOTTOMRIGHT", 0, 0)
  create:Hide()
  f.createPanel = create

  local function divider(parent, at)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetSize(CONTENT_WIDTH, 1)
    line:SetPoint("TOPLEFT", MARGIN, at)
    return line
  end

  local cy = -34
  local formTitle = create:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  formTitle:SetPoint("TOPLEFT", MARGIN, cy)
  formTitle:SetText(Fundraiser:T("SECTION_EVENT_FORM"))
  divider(create, cy - 18)
  cy = cy - 28

  f.createWarn = create:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.createWarn:SetPoint("TOPLEFT", MARGIN, cy)
  f.createWarn:SetWidth(CONTENT_WIDTH)
  f.createWarn:SetJustifyH("LEFT")
  f.createWarn:SetWordWrap(true)
  f.createWarn:SetText(Fundraiser:T("CREATE_ARCHIVE_WARN"))
  cy = cy - 32

  local function field(labelKey, name, width)
    local fs = create:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", MARGIN, cy - 3)
    fs:SetWidth(LABEL_WIDTH)
    fs:SetJustifyH("LEFT")
    fs:SetText(Fundraiser:T(labelKey))
    local eb = CreateFrame("EditBox", name, create, "InputBoxTemplate")
    eb:SetSize(width, 20)
    eb:SetPoint("TOPLEFT", FIELD_X, cy)
    eb:SetAutoFocus(false)
    cy = cy - ROW_HEIGHT
    return eb
  end

  f.eventName = field("LABEL_EVENT_NAME", "FundraiserEventName", 240)
  f.target = field("LABEL_TARGET", "FundraiserTarget", 240)
  f.interval = field("LABEL_INTERVAL", "FundraiserInterval", 60)
  local hint = create:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("LEFT", f.interval, "RIGHT", 10, 0)
  hint:SetWidth(FRAME_WIDTH - FIELD_X - 60 - 10 - MARGIN)
  hint:SetJustifyH("LEFT")
  hint:SetText(Fundraiser:T("LABEL_INTERVAL_HINT"))
  f.goalGold = field("LABEL_GOAL_GOLD", "FundraiserGoalGold", 80)
  f.goal = field("LABEL_GOAL_NOTE", "FundraiserGoalNote", 240)

  local publish = CreateFrame("Button", "FundraiserPublishButton", create, "UIPanelButtonTemplate")
  publish:SetSize(140, 24)
  publish:SetPoint("TOPLEFT", MARGIN, cy - 4)
  publish:SetText(Fundraiser:T("BTN_PUBLISH"))
  publish:SetScript("OnClick", function()
    Window:Publish()
  end)

  local cancel = CreateFrame("Button", "FundraiserCreateCancelButton", create, "UIPanelButtonTemplate")
  cancel:SetSize(100, 24)
  cancel:SetPoint("LEFT", publish, "RIGHT", 8, 0)
  cancel:SetText(Fundraiser:T("BTN_CANCEL"))
  cancel:SetScript("OnClick", function()
    Window:ShowStatus()
  end)

  if Fundraiser.UI.Ledger and Fundraiser.UI.Ledger.Attach then
    Fundraiser.UI.Ledger:Attach(f)
  end
  if Fundraiser.UI.Target and Fundraiser.UI.Target.Attach then
    Fundraiser.UI.Target:Attach(f)
  end

  f:SetScript("OnShow", function()
    if not Window.userMoved then
      Window:PlaceDefault(f)
    else
      f:SetFrameStrata("DIALOG")
      if f.Raise then
        f:Raise()
      end
    end
    local page = Window.pendingPage or "status"
    Window.pendingPage = nil
    Window:ShowPage(page)
  end)

  self.view = "status"
  self.userMoved = false
  self.frame = f
  return f
end

-- Logo band + left menu (built once; pages are the panels anchored beside the menu).
local NAV_ITEMS = {
  { page = "status", key = "NAV_STATUS", needs = "officer", tip = "TIP_NAV_STATUS" },
  { page = "ledger", key = "NAV_LEDGER", needs = "ledger", tip = "TIP_NAV_LEDGER" },
  { page = "target", key = "NAV_TARGET", needs = "target", tip = "TIP_NAV_TARGET" },
  -- Actions pinned to the menu bottom (not pages): Add donation (opens the form), Set MOTD, Settings.
  { page = "donation", key = "NAV_DONATION", needs = "donation", action = "donation", tip = "TIP_NAV_DONATION" },
  { page = "motd", key = "BTN_SET_MOTD", needs = "motd", action = "motd", tip = "TIP_SET_MOTD" },
  { page = "settings", key = "NAV_SETTINGS", needs = "officer", action = "settings", tip = "TIP_NAV_SETTINGS" },
}

function Window:BuildShell(f)
  local bandTop = -TITLE_BAR_H
  local logo = f:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(LOGO_TEXTURE)
  logo:SetSize(LOGO_SIZE, LOGO_SIZE)
  logo:SetPoint("TOPLEFT", 14, bandTop - 6)
  f.logo = logo

  f.brand = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  f.brand:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -4)
  f.brand:SetText(Fundraiser:T("WINDOW_TITLE"))
  f.pageTitle = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.pageTitle:SetPoint("TOPLEFT", f.brand, "BOTTOMLEFT", 0, -3)

  local function line(horizontal)
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(1, 1, 1, 0.15)
    if horizontal then
      t:SetHeight(1)
      t:SetPoint("TOPLEFT", 8, bandTop - HEADER_H)
      t:SetPoint("TOPRIGHT", -8, bandTop - HEADER_H)
    else
      t:SetWidth(1)
      t:SetPoint("TOPLEFT", NAV_W, bandTop - HEADER_H)
      t:SetPoint("BOTTOMLEFT", NAV_W, 8)
    end
    return t
  end
  line(true)
  line(false)

  f.navButtons = {}
  for _, item in ipairs(NAV_ITEMS) do
    local b = CreateFrame("Button", "FundraiserNav_" .. item.page, f, "UIPanelButtonTemplate")
    b:SetSize(NAV_W - 20, 26)
    b:SetText(Fundraiser:T(item.key))
    b:SetScript("OnClick", function()
      if item.action == "donation" then
        Window:ShowPage("donation")
        return
      end
      if item.action == "motd" then
        Fundraiser.UI.Ledger:ConfirmSetMotd()
        return
      end
      if item.action == "settings" then
        if Fundraiser.Options and Fundraiser.Options.Open then
          Fundraiser.Options:Open()
        end
        return
      end
      Window:ShowPage(item.page)
    end)
    b.item = item
    -- Every menu entry describes what it does: <tip>_TITLE / <tip>_BODY in the locale.
    b:SetScript("OnEnter", function(self)
      showTooltip(self, item.tip .. "_TITLE", item.tip .. "_BODY")
    end)
    b:SetScript("OnLeave", hideTooltip)
    f.navButtons[#f.navButtons + 1] = b
  end

  -- Top bar actions, right-aligned, left to right: [refresh] current page, [-] end event, [+] new event.
  local refresh = makeCardPanelIconButton(f, "FundraiserRefreshButton", "Interface\\Buttons\\UI-RefreshButton")
  refresh:ClearAllPoints()
  refresh:SetPoint("TOPRIGHT", -16, bandTop - 18)
  if refresh.icon then
    local tex = refresh.icon:GetTexture()
    if not tex or tex == "" then
      refresh.icon:SetTexture("Interface\\Buttons\\UI-RotationRight-Button-Up")
    end
  end
  refresh:SetScript("OnClick", function()
    Window:RefreshCurrent()
  end)
  refresh:SetScript("OnEnter", function(self)
    showTooltip(self, "TIP_REFRESH_TITLE", "TIP_REFRESH_BODY")
  end)
  refresh:SetScript("OnLeave", hideTooltip)
  f.refreshBtn = refresh

  -- New event: original Blizzard PlusButton (no panel chrome).
  local newEvent = makeCardIconButton(f, "FundraiserNewEventButton")
  newEvent:ClearAllPoints()
  newEvent:SetPoint("RIGHT", refresh, "LEFT", -6, 0)
  trySetIcon(
    newEvent,
    "Interface\\Buttons\\UI-PlusButton-Up",
    "Interface\\Buttons\\UI-PlusButton-Down",
    "Interface\\Buttons\\UI-PlusButton-Hilight"
  )
  if not newEvent:GetNormalTexture() then
    makeTextIconFallback(newEvent, "+")
  end
  newEvent:SetScript("OnClick", function()
    Window:ShowCreate()
  end)
  newEvent:SetScript("OnEnter", function(self)
    showTooltip(self, "TIP_NEW_EVENT_TITLE", "TIP_NEW_EVENT_BODY")
  end)
  newEvent:SetScript("OnLeave", hideTooltip)
  f.newEventBtn = newEvent

  -- End event: MinusButton (archive + guild campaign wipe).
  local endEvent = makeCardIconButton(f, "FundraiserEndEventButton")
  endEvent:ClearAllPoints()
  endEvent:SetPoint("RIGHT", newEvent, "LEFT", -4, 0)
  trySetIcon(
    endEvent,
    "Interface\\Buttons\\UI-MinusButton-Up",
    "Interface\\Buttons\\UI-MinusButton-Down",
    "Interface\\Buttons\\ButtonHilight-Square"
  )
  if endEvent.SetDisabledTexture then
    endEvent:SetDisabledTexture("Interface\\Buttons\\UI-MinusButton-Disabled")
  end
  if not endEvent:GetNormalTexture() then
    makeTextIconFallback(endEvent, "-")
  end
  endEvent:SetScript("OnClick", function()
    Window:ConfirmEndEvent()
  end)
  endEvent:SetScript("OnEnter", function(self)
    showTooltip(self, "TIP_END_EVENT_TITLE", "TIP_END_EVENT_BODY")
  end)
  endEvent:SetScript("OnLeave", hideTooltip)
  endEvent:Hide()
  f.endEventBtn = endEvent

  newEvent:ClearAllPoints()
  newEvent:SetPoint("TOPRIGHT", -16, bandTop - 18)
  endEvent:ClearAllPoints()
  endEvent:SetPoint("RIGHT", newEvent, "LEFT", -4, 0)
  refresh:ClearAllPoints()
  refresh:SetPoint("RIGHT", endEvent, "LEFT", -6, 0)
end

local function isOfficer()
  return Fundraiser:CanOpenAdminUi()
end

local function canSeeLedger()
  return Fundraiser:CanOpenLedgerUi()
end

local ShellPages = Fundraiser.Domain.ShellPages

-- What the current player may use; ShellPages decides pages and menu entries from it.
function Window:Access()
  local ledger = canSeeLedger()
  return {
    officer = isOfficer(),
    ledger = ledger,
    target = Fundraiser:CanOpenTargetUi(),
    donation = Fundraiser.UI.Ledger:CanAddDonation() and true or false,
    motd = ledger and Fundraiser.UI.Ledger:CanSetMotd() and true or false,
  }
end

-- Show only the menu entries the player may use; mark the current page.
function Window:UpdateNav()
  local f = self.frame
  if not f or not f.navButtons then
    return
  end
  local access = self:Access()
  local y = -(TITLE_BAR_H + HEADER_H + 12)
  local bottomY = 14
  -- Bottom entries are listed top-to-bottom in NAV_ITEMS, so stack them upward from the end.
  for i = #f.navButtons, 1, -1 do
    local b = f.navButtons[i]
    if b.item.action then
      if ShellPages.Allowed(b.item.needs, access) then
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", 10, bottomY)
        bottomY = bottomY + 30
        b:Show()
        if b.item.page == self.view then
          b:LockHighlight()
        else
          b:UnlockHighlight()
        end
      else
        b:Hide()
      end
    end
  end
  for _, b in ipairs(f.navButtons) do
    if not b.item.action then
      if ShellPages.Allowed(b.item.needs, access) then
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 10, y)
        y = y - 30
        b:Show()
        if b.item.page == self.view then
          b:LockHighlight()
        else
          b:UnlockHighlight()
        end
      else
        b:Hide()
      end
    end
  end
  self:UpdateHeaderButtons()
end

local function setShown(frame, shown)
  if shown then
    frame:Show()
  else
    frame:Hide()
  end
end

-- Top bar buttons: officers get +/-; refresh needs a page that can refresh (not the form).
function Window:UpdateHeaderButtons()
  local f = self.frame
  if not f or not f.refreshBtn then
    return
  end
  local officer = isOfficer()
  local onForm = self.view == "create" or self.view == "donation"
  local Store = Fundraiser.Adapters and Fundraiser.Adapters.Store
  local hasEvent = Store and Store:GetEvent() ~= nil
  setShown(f.refreshBtn, not onForm and (officer or canSeeLedger() or Fundraiser:CanOpenTargetUi()))
  setShown(f.newEventBtn, officer and not onForm)
  setShown(
    f.endEventBtn,
    officer and not onForm and hasEvent and (Fundraiser.Config and Fundraiser.Config.END_EVENT) and true or false
  )
end

-- Refresh whichever page is showing.
function Window:RefreshCurrent()
  if self.view == "ledger" then
    Fundraiser.UI.Ledger:Refresh()
  elseif self.view == "target" then
    Fundraiser.UI.Target:Refresh()
  else
    self:Refresh()
  end
end

local function showOnly(f, which)
  setShown(f.statusPanel, which == "status")
  setShown(f.createPanel, which == "create")
  local Ledger = Fundraiser.UI.Ledger
  if Ledger and Ledger.frame then
    setShown(Ledger.frame, which == "ledger")
  end
  if Ledger and Ledger.donationFrame then
    setShown(Ledger.donationFrame, which == "donation")
  end
  local Target = Fundraiser.UI.Target
  -- While docked beside the auction house the panel belongs to the dock, not the shell.
  if Target and Target.frame and not Target.docked then
    setShown(Target.frame, which == "target")
  end
end

-- Open a page by name; officers get status/create, ledger viewers get the ledger.
function Window:ShowPage(page)
  local shown = ShellPages.Resolve(page, self:Access())
  if page == "target" and shown ~= "target" then
    DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("CHAT_TARGET_NO_ACCESS"))
  end
  if shown == "donation" then
    self:ShowDonation()
  elseif shown == "target" then
    self:ShowTarget()
  elseif shown == "ledger" then
    self:ShowLedger()
  elseif shown == "create" then
    self:ShowCreate()
  elseif shown == "status" then
    self:ShowStatus()
  else
    self:Hide()
  end
end

function Window:ShowStatus()
  local f = self:Ensure()
  self.view = "status"
  showOnly(f, "status")
  f.pageTitle:SetText(Fundraiser:T("NAV_STATUS"))
  self:UpdateNav()
  self:Refresh()
end

function Window:ShowLedger()
  local f = self:Ensure()
  local Ledger = Fundraiser.UI.Ledger
  self.view = "ledger"
  showOnly(f, "ledger")
  f.pageTitle:SetText(Fundraiser:T("NAV_LEDGER"))
  self:UpdateNav()
  Ledger:Refresh()
end

function Window:ShowTarget()
  local f = self:Ensure()
  Fundraiser.UI.Target:Undock()
  self.view = "target"
  showOnly(f, "target")
  f.pageTitle:SetText(Fundraiser:T("NAV_TARGET"))
  self:UpdateNav()
  Fundraiser.UI.Target:Open()
end

-- Put the shell to the right of a client frame (the vendor or mail window), like the Target
-- panel beside the auction house. A position the player chose is kept and comes back later.
function Window:AttachTo(anchor)
  local f = self.frame
  if not (f and anchor) then
    return
  end
  if self.userMoved and not self.attached then
    self.savedPoint = { f:GetPoint(1) }
  end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 2, 0)
  f:SetClampedToScreen(true)
  self.attached = true
end

-- The shell was hidden by any means: forget what opened it and undo the attachment.
function Window:OnShellHidden()
  local f = self.frame
  if self.attached and f and self.savedPoint then
    f:ClearAllPoints()
    f:SetPoint(unpack(self.savedPoint))
  end
  self.autoOpened, self.attached, self.savedPoint = nil, false, nil
end

-- Open the shell on a page and keep it open when that page is already showing (unlike the
-- Toggle* functions). Used when a vendor or the mailbox opens: `trigger` ("vendor" / "mailbox")
-- and `anchorName` (a client frame) make it attach beside that window and close with it. A shell
-- the player already has open is only switched to the page, not moved.
function Window:OpenPage(page, trigger, anchorName)
  local f = self:Ensure()
  if f:IsShown() then
    if self.view ~= page then
      self:ShowPage(page)
    end
    return
  end
  self.pendingPage = page
  f:Show()
  if trigger then
    self:AttachTo(anchorName and _G[anchorName])
    self.autoOpened = { trigger = trigger, page = self.view }
  end
end

-- A vendor / the mailbox closed: close the shell when it was opened for that window.
function Window:CloseFor(trigger)
  local f = self.frame
  if f and f:IsShown() and ShellPages.ShouldAutoClose(self.autoOpened, trigger, self.view) then
    f:Hide()
  end
end

-- Open the shell on the target page (or close it when the page is already showing).
function Window:ToggleTarget()
  local f = self:Ensure()
  if f:IsShown() and self.view == "target" then
    f:Hide()
    return
  end
  if f:IsShown() then
    self:ShowPage("target")
  else
    self.pendingPage = "target"
    f:Show()
  end
end

-- Manual donation form (donation target only).
function Window:ShowDonation()
  local f = self:Ensure()
  self.view = "donation"
  showOnly(f, "donation")
  f.pageTitle:SetText(Fundraiser:T("NAV_DONATION"))
  Fundraiser.UI.Ledger:ResetDonationForm()
  self:UpdateNav()
end

-- Open the shell on the ledger page (or close it when the ledger is already showing).
function Window:ToggleLedger()
  local f = self:Ensure()
  if f:IsShown() and self.view == "ledger" then
    f:Hide()
    return
  end
  if f:IsShown() then
    self:ShowLedger()
  else
    self.pendingPage = "ledger"
    f:Show()
  end
end

function Window:ShowCreate()
  local f = self:Ensure()
  self.view = "create"
  showOnly(f, "create")
  f.pageTitle:SetText(Fundraiser:T("NAV_CREATE"))
  self:UpdateNav()

  f.eventName:SetText("")
  f.target:SetText("")
  f.goal:SetText("")
  f.goalGold:SetText("")
  f.interval:SetText(defaultIntervalHours())

  local Store = Fundraiser.Adapters and Fundraiser.Adapters.Store
  local hasEvent = Store and Store.GetEvent and Store:GetEvent() ~= nil
  if hasEvent then
    f.createWarn:SetText(Fundraiser:T("CREATE_ARCHIVE_WARN"))
  else
    f.createWarn:SetText(Fundraiser:T("CREATE_HELP"))
  end
  f.createWarn:Show()
end

function Window:ConfirmEndEvent()
  if not (Fundraiser.Config and Fundraiser.Config.END_EVENT) then
    return
  end
  local Store = Fundraiser.Adapters and Fundraiser.Adapters.Store
  if not (Store and Store.GetEvent and Store:GetEvent()) then
    return
  end
  confirmAction("FUNDRAISER_END_EVENT", "CONFIRM_END_EVENT", function()
    Window:EndEvent()
  end)
end

function Window:EndEvent()
  local Store = Fundraiser.Adapters.Store
  local Roster = Fundraiser.Adapters.Roster
  local UC = Fundraiser.Application.UseCases
  local Sync = Fundraiser.Adapters.ThinGuildSync
  local now = (GetServerTime and GetServerTime()) or (time and time()) or 0
  local ok, mode = UC.EndActiveEvent({
    getEvent = function()
      return Store:GetEvent()
    end,
    getContributions = function()
      return Store:GetContributions()
    end,
    getArchives = function()
      return Store:GetArchives()
    end,
    archiveEvent = function(event, contributions, archivedAt)
      Store:ArchiveEvent(event, contributions, archivedAt)
    end,
    applyResetScope = function(scope)
      return Store:ApplyResetScope(scope)
    end,
    clearContributions = function()
      Store:ClearLedger()
    end,
    clearReminder = function()
      Store:SetReminderState({})
    end,
    clearEvent = function()
      Store:ClearEvent()
    end,
    bumpResetEpoch = function()
      return Store:BumpResetEpoch()
    end,
    broadcastReset = function(scope)
      return Sync and Sync.BroadcastReset and Sync:BroadcastReset(scope)
    end,
  }, {
    rankIndex = Roster:GetPlayerRankIndex(),
    name = Roster:GetPlayerName(),
    now = now,
  })
  if not ok then
    if DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage(
        Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("CHAT_END_EVENT_FAILED", tostring(mode or "?"))
      )
    end
    return
  end
  if DEFAULT_CHAT_FRAME then
    if mode == "guild" then
      DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("CHAT_END_EVENT_OK"))
    else
      DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("CHAT_END_EVENT_LOCAL_ONLY"))
    end
  end
  self:ShowStatus()
end

function Window:Publish()
  local f = self:Ensure()
  local Store = Fundraiser.Adapters.Store
  local Roster = Fundraiser.Adapters.Roster
  local UC = Fundraiser.Application.UseCases
  local hours = tonumber(f.interval:GetText())
  local intervalSeconds
  if hours then
    intervalSeconds = math.floor(hours * 3600)
  else
    intervalSeconds = (Fundraiser.Config and tonumber(Fundraiser.Config.DEFAULT_REMINDER_INTERVAL)) or 86400
  end
  local gold = tonumber(f.goalGold:GetText())
  local goalCopper = 0
  if gold and gold > 0 then
    goalCopper = math.floor(gold * COPPER_PER_GOLD)
  end
  local fields = {
    name = f.eventName:GetText(),
    target = f.target:GetText(),
    goal = f.goal:GetText(),
    goalCopper = goalCopper,
    intervalSeconds = intervalSeconds,
  }
  local deps = {
    getEvent = function()
      return Store:GetEvent()
    end,
    setEvent = function(e)
      Store:SetEvent(e)
    end,
    getContributions = function()
      return Store:GetContributions()
    end,
    archiveEvent = function(event, contributions, archivedAt)
      Store:ArchiveEvent(event, contributions, archivedAt)
    end,
    clearContributions = function()
      Store:ClearLedger()
    end,
    clearReminder = function()
      Store:SetReminderState({})
    end,
    broadcastEvent = function(e)
      Fundraiser.Adapters.ThinGuildSync:BroadcastEvent(e)
    end,
  }
  local actor = {
    rankIndex = Roster:GetPlayerRankIndex(),
    name = Roster:GetPlayerName(),
    now = (GetServerTime and GetServerTime()) or (time and time()) or 0,
  }
  local event, err = UC.PublishEvent(deps, fields, actor)
  if not event then
    if DEFAULT_CHAT_FRAME then
      local msg = err == "not_admin" and Fundraiser:T("CHAT_NOT_ADMIN")
        or err == "target_need_full_name" and Fundraiser:T("CHAT_TARGET_NEED_FULL_NAME")
        or err == "bad_goal" and Fundraiser:T("CHAT_BAD_GOAL")
        or tostring(err)
      DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. msg)
    end
    return
  end
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(Fundraiser:T("CHAT_PREFIX") .. Fundraiser:T("CHAT_EVENT_PUBLISHED", event.name))
  end
  self:ShowStatus()
end

local function formatAxisGold(copper)
  local g = math.floor((tonumber(copper) or 0) / COPPER_PER_GOLD)
  -- Gold-only axis tick with coin icon (compact chart label).
  if Fundraiser.FormatCopper then
    return Fundraiser.FormatCopper(g * COPPER_PER_GOLD, 10)
  end
  return g .. "g"
end

local function formatAxisDay(day)
  day = tonumber(day) or 0
  if date then
    return date("%d/%m", day)
  end
  return tostring(day)
end

-- Place a line segment texture between two plot-local points (bottom-left origin).
local function placeSegment(tex, x1, y1, x2, y2)
  local dx = x2 - x1
  local dy = y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1 then
    tex:Hide()
    return
  end
  tex:ClearAllPoints()
  tex:SetSize(len, 2)
  tex:SetPoint("CENTER", tex:GetParent(), "BOTTOMLEFT", (x1 + x2) / 2, (y1 + y2) / 2)
  if tex.SetRotation then
    tex:SetRotation(math.atan2(dy, dx))
  end
  tex:Show()
end

-- Show/hide progress + chart; ledger goes full width when goal widgets are hidden.
function Window:LayoutGoalWidgets(showGoal)
  local f = self.frame
  if not f then
    return
  end
  local midY = f.dashboardMidY
  local halfW = f.halfW
  local cardW = f.cardW

  f.ledgerCard:ClearAllPoints()
  if showGoal then
    f.progressCard:Show()
    f.chartCard:Show()
    f.progressCard:ClearAllPoints()
    f.progressCard:SetPoint("TOPLEFT", MARGIN, midY)
    f.progressCard:SetSize(halfW, PROGRESS_CARD_H)
    f.ledgerCard:SetPoint("TOPLEFT", MARGIN + halfW + CARD_GAP, midY)
    f.ledgerCard:SetSize(halfW, PROGRESS_CARD_H)
    f.ledgerStatus:SetWidth(halfW - 20)
    f.chartCard:ClearAllPoints()
    f.chartCard:SetPoint("TOPLEFT", MARGIN, midY - PROGRESS_CARD_H - CARD_GAP)
  else
    f.progressCard:Hide()
    f.chartCard:Hide()
    f.ledgerCard:SetPoint("TOPLEFT", MARGIN, midY)
    f.ledgerCard:SetSize(cardW, PROGRESS_CARD_H)
    f.ledgerStatus:SetWidth(cardW - 20)
  end
end

function Window:UpdateChart(series)
  local f = self.frame
  if not f or not f.chartSegments or not f.chartCard:IsShown() then
    return
  end
  local points = series and series.points or {}
  local maxY = (series and series.maxY) or 1
  local goalCopper = (series and series.goalCopper) or 0
  local plot = f.chartPlot
  local width = plot:GetWidth()
  local height = plot:GetHeight()
  if not width or width < 1 then
    width = CONTENT_WIDTH - CHART_Y_LABEL_W - CHART_LEGEND_W - 24
  end
  if not height or height < 1 then
    height = CHART_CARD_H - 26 - 8 - CHART_X_LABEL_H
  end
  if maxY < 1 then
    maxY = 1
  end

  for i = 1, CHART_MAX_SEGMENTS do
    f.chartSegments[i]:Hide()
  end
  for i = 1, CHART_MAX_POINTS do
    f.chartDots[i]:Hide()
    f.chartXLabels[i]:Hide()
  end

  -- Inner padding so dots/labels are not clipped on the plot edges.
  local padX = 8
  local padY = 6
  local innerW = math.max(1, width - padX * 2)
  local innerH = math.max(1, height - padY * 2)

  local goalFrac = nil
  local gy = nil
  if goalCopper > 0 then
    goalFrac = goalCopper / maxY
    gy = padY + goalFrac * innerH
    if gy < 1 then
      gy = 1
    end
    if gy > height - 1 then
      gy = height - 1
    end
  end

  local function drawGoalAxis()
    if goalCopper > 0 and gy then
      f.chartGoalLine:ClearAllPoints()
      f.chartGoalLine:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", padX, gy)
      f.chartGoalLine:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", -padX, gy)
      f.chartGoalLine:Show()
      if f.chartGoalYLabel then
        f.chartGoalYLabel:ClearAllPoints()
        f.chartGoalYLabel:SetPoint("RIGHT", plot, "BOTTOMLEFT", -8, gy)
        f.chartGoalYLabel:SetText(formatAxisGold(goalCopper))
        f.chartGoalYLabel:Show()
      end
    else
      f.chartGoalLine:Hide()
      if f.chartGoalYLabel then
        f.chartGoalYLabel:Hide()
      end
    end
  end

  local function drawScaleTicks()
    -- max / mid / 0. Hide mid near goal; hide max when goal is at the top.
    local yVals = { maxY, maxY / 2, 0 }
    local yFracs = { 1, 0.5, 0 }
    local hideMid = goalFrac and math.abs(goalFrac - 0.5) < 0.12
    local hideMax = goalFrac and goalFrac > 0.88
    for i = 1, 3 do
      local fs = f.chartYLabels[i]
      if (i == 1 and hideMax) or (i == 2 and hideMid) then
        fs:Hide()
      else
        local yy = padY + yFracs[i] * innerH
        fs:ClearAllPoints()
        fs:SetPoint("RIGHT", plot, "BOTTOMLEFT", -8, yy)
        fs:SetText(formatAxisGold(yVals[i]))
        fs:Show()
      end
    end
  end

  if #points == 0 then
    f.chartEmpty:Show()
    for i = 1, CHART_MAX_POINTS do
      f.chartXLabels[i]:Hide()
    end
    -- Still show goal line/label + scale when a numeric goal exists.
    if goalCopper > 0 then
      drawScaleTicks()
      drawGoalAxis()
    else
      f.chartGoalLine:Hide()
      if f.chartGoalYLabel then
        f.chartGoalYLabel:Hide()
      end
      for i = 1, 3 do
        f.chartYLabels[i]:Hide()
      end
    end
    return
  end
  f.chartEmpty:Hide()

  local start = 1
  if #points > CHART_MAX_POINTS then
    start = #points - CHART_MAX_POINTS + 1
  end
  local n = #points - start + 1
  local coords = {}
  for i = 1, n do
    local pt = points[start + i - 1]
    local x
    if n == 1 then
      x = padX + innerW / 2
    else
      x = padX + ((i - 1) / (n - 1)) * innerW
    end
    local y = padY + (pt.cumulative / maxY) * innerH
    coords[i] = { x = x, y = y, day = pt.day }
  end

  for i = 1, n - 1 do
    placeSegment(f.chartSegments[i], coords[i].x, coords[i].y, coords[i + 1].x, coords[i + 1].y)
  end
  for i = 1, n do
    local dot = f.chartDots[i]
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", plot, "BOTTOMLEFT", coords[i].x, coords[i].y)
    dot:Show()
  end

  drawScaleTicks()
  drawGoalAxis()

  -- X-axis: first / mid / last below the plot, with corner clearance on the first label.
  local xIdx = { 1 }
  if n >= 3 then
    xIdx[#xIdx + 1] = math.floor((n + 1) / 2)
  end
  if n >= 2 then
    xIdx[#xIdx + 1] = n
  end
  local used = {}
  for _, idx in ipairs(xIdx) do
    if not used[idx] then
      used[idx] = true
      local fs = f.chartXLabels[idx]
      local xx = coords[idx].x
      if idx == 1 then
        xx = math.max(xx, 16)
      elseif idx == n then
        xx = math.min(xx, width - 16)
      end
      fs:ClearAllPoints()
      fs:SetPoint("TOP", plot, "BOTTOMLEFT", xx, -6)
      fs:SetText(formatAxisDay(coords[idx].day))
      fs:Show()
    end
  end
end

function Window:Refresh()
  local f = self:Ensure()
  if self.view ~= "status" then
    return
  end

  local Store = Fundraiser.Adapters.Store
  local Roster = Fundraiser.Adapters.Roster
  local UC = Fundraiser.Application.UseCases
  local Summary = Fundraiser.Domain.AdminSummary
  local Roles = Fundraiser.Domain.Roles
  local event = Store:GetEvent()

  local status = Summary.EventStatus(event)
  if status.hasEvent then
    f.eventNameFs:SetText(status.name)
    local hoursStr
    if status.intervalHours > 0 and status.intervalHours < 1 then
      hoursStr = string.format("%.2f", status.intervalHours)
    else
      hoursStr = string.format("%g", status.intervalHours)
    end
    f.eventDetailFs:SetText(
      Fundraiser:T("STATUS_EVENT_DETAIL_FMT", status.target, hoursStr, status.revision)
    )
    if status.goalNote ~= "" then
      f.eventNoteFs:SetText(Fundraiser:T("STATUS_GOAL_NOTE_FMT", status.goalNote))
    else
      f.eventNoteFs:SetText("")
    end
  else
    f.eventNameFs:SetText(Fundraiser:T("SECTION_EVENT"))
    f.eventDetailFs:SetText(Fundraiser:T("STATUS_NO_EVENT"))
    f.eventNoteFs:SetText("")
  end
  self:UpdateHeaderButtons()

  local rows, total = {}, 0
  local canLedger = Fundraiser.Config.LEDGER
    and event
    and Roles.CanViewLedger(event, Roster:GetPlayerRankIndex(), Roster:GetPlayerName())
  if canLedger then
    rows, total = UC.GetLedger({
      getEvent = function()
        return Store:GetEvent()
      end,
      getContributions = function()
        return Store:GetContributions()
      end,
      getPlayerName = function()
        return Roster:GetPlayerName()
      end,
      getPlayerRankIndex = function()
        return Roster:GetPlayerRankIndex()
      end,
    }, event.id)
    local ledger = Summary.Ledger(rows, total)
    if ledger.count == 0 then
      f.ledgerStatus:SetText(Fundraiser:T("LEDGER_EMPTY"))
    else
      f.ledgerStatus:SetText(
        Fundraiser:T("LEDGER_TOTAL_FMT", money(ledger.total))
          .. "\n"
          .. Fundraiser:T("LEDGER_COUNT_FMT", ledger.count)
      )
    end
  else
    f.ledgerStatus:SetText(Fundraiser:T("LEDGER_OFFICER_ONLY"))
  end

  local goalCopper = status.goalCopper or 0
  local progress = Summary.Progress(canLedger and total or 0, goalCopper)
  -- Progress + chart only when the active event has a numeric goal.
  local showGoalWidgets = status.hasEvent and progress.hasGoal
  self:LayoutGoalWidgets(showGoalWidgets)
  if showGoalWidgets then
    if canLedger then
      f.progressText:SetText(Fundraiser:T("PROGRESS_FMT", money(progress.total), money(progress.goal)))
      f.progressPct:SetText(Fundraiser:T("PROGRESS_PCT_FMT", string.format("%.0f", progress.percent)))
      f.progressBar:SetValue(progress.cappedPercent)
      self:UpdateChart(Summary.DailySeries(rows, goalCopper))
    else
      f.progressText:SetText(Fundraiser:T("LEDGER_OFFICER_ONLY"))
      f.progressPct:SetText("")
      f.progressBar:SetValue(0)
      self:UpdateChart({ points = {}, goalCopper = goalCopper, maxY = math.max(goalCopper, 1) })
    end
  end
end

function Window:Hide()
  if self.frame then
    self.frame:Hide()
  end
end

function Window:Toggle()
  local f = self:Ensure()
  if f:IsShown() then
    f:Hide()
  else
    f:Show()
  end
end
