-- English (enUS) UI strings.
Fundraiser = Fundraiser or {}
local L = {}
Fundraiser.L = L

L.ADDON_NAME = "Fundraiser"
L.CHAT_PREFIX = "|cff33ff99Fundraiser|r: "

L.CHAT_DISABLED = "Addon is disabled."
L.CHAT_LOADED = "Loaded. Type /fundraiser to open."
L.CHAT_STATUS_ON = "Enabled."
L.CHAT_STATUS_OFF = "Disabled via Config.ENABLED."
L.CHAT_NOT_IN_GUILD = "You are not in a guild."
L.CHAT_NO_EVENT = "No active fundraiser event."
L.CHAT_EVENT_PUBLISHED = "Published event: %s"
L.CHAT_NOT_ADMIN = "Your guild rank cannot manage fundraisers."
L.CHAT_DONATION_RECORDED = "Recorded donation of %s to %s."

L.REMINDER_FMT = "%s needs your aid for %s, please donate to the fundraiser by sending whatever you can spare to %s"

L.WINDOW_TITLE = "Fundraiser"
L.SECTION_EVENT = "Active event"
L.SECTION_LEDGER = "Ledger (self-attested)"
L.SECTION_PRESENCE = "Install presence"
L.LABEL_EVENT_NAME = "Event name"
L.LABEL_TARGET = "Donation mail target"
L.LABEL_INTERVAL = "Reminder interval (hours)"
L.LABEL_MIN_ADMIN_RANK = "Min admin rank index (0 = GM)"
L.LABEL_GOAL = "Goal note"
L.BTN_PUBLISH = "Publish event"
L.BTN_REFRESH = "Refresh"
L.COL_NAME = "Name"
L.COL_AMOUNT = "Amount"
L.COL_STATUS = "Status"
L.STATUS_HAS_ADDON = "Installed"
L.STATUS_MISSING = "Missing"
L.STATUS_UNKNOWN = "Unknown"
L.LEDGER_TOTAL_FMT = "Total: %s"
L.LEDGER_EMPTY = "No donations recorded yet."
L.PRESENCE_EMPTY = "No guild roster data yet."

L.OPTIONS_VERSION_FMT = "Version %s"
L.OPTIONS_HELP =
  "Guild fundraiser reminders for Forever. Officers publish an event; members are reminded when opening bags until they mail the designated target. Ledger entries are self-attested."
L.OPTIONS_OPEN = "Open Fundraiser"

function Fundraiser:T(key, ...)
  local text = (self.L and self.L[key]) or key
  if select("#", ...) > 0 then
    return string.format(text, ...)
  end
  return text
end
