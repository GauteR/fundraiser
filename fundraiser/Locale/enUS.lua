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
L.CHAT_TARGET_NO_ACCESS = "Target inbox assist is only available on the donation-target character."
L.CHAT_DEBUG_ASRANK = "Rank override set to %s (real guild rank ignored until cleared)."
L.CHAT_DEBUG_ASRANK_CLEAR = "Rank override cleared."
L.CHAT_DEBUG_ACCESS = "rank=%s manage=%s target=%s adminUi=%s targetUi=%s"
L.CHAT_MAIL_SENT_DISMISS = "Mail sent to %s — reminder cleared for this interval."
L.CHAT_AH_LOGGED = "Logged AH sale: %s for %s."
L.CHAT_DEBUG_OFF = "Debug is off (Config.DEBUG)."
L.CHAT_DEBUG_NO_SYNC = "ThinGuildSync is not loaded."
L.CHAT_DEBUG_FAIL = "Debug failed: %s"
L.CHAT_DEBUG_SEEDED = "Seeded event '%s' → mail %s (interval %ss)."
L.CHAT_DEBUG_HELLO = "Injected HELLO from %s (%s)."
L.CHAT_DEBUG_EVENT = "Accepted debug EVENT '%s' as rank %s (rev %s)."
L.CHAT_DEBUG_LEDGER = "Injected LEDGER %s from %s (%s)."
L.CHAT_DEBUG_DIGEST = "Injected DIGEST (rev %s, rows %s)."
L.CHAT_DEBUG_REMINDER = "Forced reminder panel."
L.CHAT_DEBUG_DISMISS = "Dismissed reminder window for active event."
L.CHAT_DEBUG_PRESENCE = "Presence entries: %s"
L.CHAT_DEBUG_PRESENCE_EMPTY = "Presence table is empty."
L.CHAT_DEBUG_UNKNOWN = "Unknown debug command: %s"
L.CHAT_DEBUG_HELP =
  "debug: help | seed | hello [Name] [guid] | event [rank] | ledger [mail|ah] [Name] [copper] [detail] | digest | reminder | dismiss | presence | asrank <n|clear> | member | officer | access"

L.REMINDER_FMT = "%s needs your aid for %s, please donate to the fundraiser by sending whatever you can spare to %s. Thank you. :-)"

L.WINDOW_TITLE = "Fundraiser"
L.SECTION_EVENT = "Active event"
L.SECTION_LEDGER = "Ledger"
L.LEDGER_OFFICER_ONLY =
  "Ledger view is limited to officers and the donation-target character.."
L.LEDGER_DEDICATED_HINT =
  "Use a character dedicated only to this fundraiser (mail intake + AH). Do not mix personal AH on that alt."
L.SECTION_PRESENCE = "Install presence"
L.LABEL_EVENT_NAME = "Event name"
L.LABEL_TARGET = "Donation mail target"
L.CHAT_TARGET_NEED_FULL_NAME = "Target must be a Forever full name: First Last."
L.LABEL_INTERVAL = "Reminder interval (hours, overrides default)"
L.LABEL_GOAL = "Goal note"
L.BTN_PUBLISH = "Publish event"
L.BTN_REFRESH = "Refresh"
L.BTN_ADDON_SETTINGS = "Addon settings"
L.BTN_TARGET_UI = "Target inbox assist"
L.BTN_POST_AH = "Post AH"
L.BTN_VENDOR = "Vendor"

L.TARGET_WINDOW_TITLE = "Fundraiser — Target"
L.TARGET_HINT =
  "Mailbox attachments by sender. One AH post per item stack. Prices: TSM → Auctionator → manual. Dedicated fundraiser alt only."
L.TARGET_NOT_TARGET = "Log in on the designated donation character to use this panel."
L.TARGET_EMPTY = "No mailbox item attachments found. Open the mailbox and refresh."
L.TARGET_SENDER_FMT = "From %s:"
L.TARGET_MANUAL_PRICE = "Unit AH price (copper):"
L.TARGET_DETAIL_FMT =
  "Item %d/%d — from %s\n%s x%s\nVendor stack: %s\nAH stack (gross): %s\nAH net (~cut): %s\nPrice source: %s\nAdvice: %s"
L.TARGET_ADVICE_VENDOR = "Prefer vendor"
L.TARGET_ADVICE_AH = "Prefer AH"
L.TARGET_ADVICE_MANUAL = "Enter price manually"

L.CHAT_TARGET_NEED_PRICE = "Set a unit AH price (TSM/Auctionator missing)."
L.CHAT_TARGET_ITEM_NOT_IN_BAGS = "Item not in bags yet — take from mail and retry."
L.CHAT_TARGET_POSTED = "Posted stack x%s at buyout %s (Forever AH API Unverified)."
L.CHAT_TARGET_POST_FAILED = "Could not start auction (open AH / API unsupported)."
L.CHAT_TARGET_OPEN_VENDOR = "Open a vendor, then press Vendor again."
L.CHAT_TARGET_VENDOR_OK = "Sold to vendor."
L.CHAT_TARGET_VENDOR_FAILED = "Vendor sell failed."
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
  "Guild fundraiser for Forever. Officers publish an event; members get a mailbox reminder. Default interval and min admin rank are set here; each event can override the interval."
L.OPTIONS_SECTION_STATUS = "Status"
L.OPTIONS_SECTION_SETTINGS = "Defaults"
L.OPTIONS_STATUS_ENABLED_FMT = "Addon: %s"
L.OPTIONS_STATUS_ENABLED_ON = "Enabled"
L.OPTIONS_STATUS_ENABLED_OFF = "Disabled"
L.OPTIONS_STATUS_GUILD_FMT = "Guild: %s"
L.OPTIONS_STATUS_GUILD_NONE = "Not in a guild"
L.OPTIONS_STATUS_EVENT_FMT = "Event: %s"
L.OPTIONS_STATUS_EVENT_NONE = "None"
L.OPTIONS_STATUS_ACCESS_FMT = "Admin access: %s"
L.OPTIONS_STATUS_ACCESS_YES = "Yes"
L.OPTIONS_STATUS_ACCESS_NO = "No"
L.OPTIONS_LABEL_DEFAULT_INTERVAL = "Default reminder interval (hours)"
L.OPTIONS_LABEL_MIN_ADMIN_RANK = "Min admin rank index (0 = GM, global)"
L.OPTIONS_APPLY = "Apply"
L.OPTIONS_SAVE_FAILED = "Could not save settings (%s)."
L.OPTIONS_OPEN = "Open Fundraiser"

function Fundraiser:T(key, ...)
  local text = (self.L and self.L[key]) or key
  if select("#", ...) > 0 then
    return string.format(text, ...)
  end
  return text
end
