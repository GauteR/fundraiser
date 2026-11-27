-- Feature flags and shared settings for Forever Fundraiser.
Fundraiser = Fundraiser or {}

Fundraiser.Config = {
  -- Master switch: false disables slash, UI, sync, and reminders.
  ENABLED = true,
  COMM = true,
  -- Allow officers to broadcast RESET over guild addon messages (best-effort wipe).
  RESET_SYNC = true,
  -- Reminder popup while the mailbox is open (not bags).
  REMINDER = true,
  -- "Only backup" Options row: members who keep the addon for backup/sync only (no mailbox
  -- reminder popup). The choice is also sent in HELLO so officers see "Only backup".
  -- false hides the row, ignores the saved choice, and stops sending the flag.
  BACKUP_ONLY_OPTION = true,
  -- File default for "Only backup" (Forever may not restore SavedVariables after a cold start).
  -- BACKUP_ONLY is the runtime overlay of the saved choice (see Domain/Settings.lua).
  BACKUP_ONLY_DEFAULT = false,
  -- Only admins (CanOpenAdminUi) can change the Defaults in Options (reminder interval,
  -- minimum admin rank); others see them read-only. Personal choices stay open to everyone.
  DEFAULTS_ADMIN_ONLY = true,
  ADMIN_UI = true,
  -- Admin window: end active campaign (archive + guild wipe) without publishing a new event.
  END_EVENT = true,
  LEDGER = true,
  -- Redraw the open Ledger page when a row is recorded (mail, sale, AH, guild sync).
  LEDGER_AUTO_REFRESH = true,
  TARGET_UI = true,
  -- Donation target: persistent per-item ignore list and minimum stack value (FundraiserDB.target).
  -- Forever may not restore SavedVariables after a cold start: the config minimum is the fallback.
  TARGET_PREFS = true,
  -- Donation target: share the ignore list with guild members running the addon (IGNORE sync
  -- messages, last write wins). Opt-in; needs TARGET_PREFS and COMM. Messages are unauthenticated.
  TARGET_IGNORE_SYNC = false,
  -- Donation target: show the Target panel beside the auction house while it is open.
  TARGET_AUTO_DOCK = true,
  -- Global frame names the dock may sit beside (the right-most visible one wins). Auctionator's
  -- tabs live inside AuctionHouseFrame; its price history window can dock to the right of it.
  -- Add another addon's auction window here by its frame name (find it with /fstack).
  TARGET_DOCK_ANCHORS = { "AuctionHouseFrame", "AuctionFrame", "AuctionatorItemHistoryFrame" },
  -- Donation target: open the main window on the Target page when a vendor opens.
  TARGET_AUTO_OPEN_VENDOR = true,
  -- Ledger viewers: open the main window on the ledger when the mailbox opens.
  LEDGER_AUTO_OPEN_MAILBOX = true,
  -- Leaderboard (top contributor in the MOTD): donations from characters of this guild rank
  -- index (0 = Guild Master) still count towards the total but not as a contributor.
  -- nil counts everyone.
  LEADERBOARD_EXCLUDED_RANK = 0,
  AH_ASSIST = true,
  -- Solo in-game simulation: /fundraiser debug …
  DEBUG = true,

  ADDON_NAME = "Fundraiser",
  VERSION = "1.0.0-rc2",
  SLASH_COMMAND = "/fundraiser",

  -- TSM custom price for "lowest" AH reference (fallback: Auctionator, then manual).
  TSM_PRICE_SOURCE = "DBMinBuyout",
  -- TSM custom price source for the item's sale rate (0..1). Region-wide, so a coarse proxy for the
  -- realm. Auctionator has no sale rate.
  TSM_SALE_RATE_SOURCE = "DBRegionSaleRate",
  AH_CUT_FRACTION = 0.05,
  -- Forever auction duration index: 1 = 2h, 2 = 8h, 3 = 24h.
  AH_DURATION = 3,
  AH_UNDERCUT_COPPER = 0,
  -- Sale advice: subtract the auction deposit (counted as lost) from the AH net value.
  AH_DEPOSIT_IN_ADVICE = true,
  -- Target page: stacks worth less than this (copper, value of the recommended action)
  -- stay listed but are left out of Post all / Sell all.
  MIN_STACK_VALUE_COPPER = 100,
  -- Target page: when true, a stack's row.costBasis (copper, optional) is subtracted from its value
  -- before the minimum above is applied. Donated items have no cost basis yet, so this stays off.
  PROFIT_THRESHOLD_ENABLED = false,

  -- Addon message prefix (max 16 characters on Classic-era clients).
  COMM_PREFIX = "Fundraiser",
  PROTOCOL = "1",

  -- Default reminder interval in seconds (officers override per event).
  DEFAULT_REMINDER_INTERVAL = 86400,
  -- When no event exists yet, admin UI requires rankIndex <= this (0 = GM).
  DEFAULT_MIN_ADMIN_RANK = 1,

  -- Presence: HELLO older than this is treated as stale (seconds).
  PRESENCE_STALE = 600,

  -- SavedVariables global name (also listed in TOC).
  SAVED_VARIABLE = "FundraiserDB",
}

-- Snapshot of file defaults for Options "reset" (Config may be overlaid at runtime).
Fundraiser.ConfigFileDefaults = {
  DEFAULT_REMINDER_INTERVAL = Fundraiser.Config.DEFAULT_REMINDER_INTERVAL,
  DEFAULT_MIN_ADMIN_RANK = Fundraiser.Config.DEFAULT_MIN_ADMIN_RANK,
  BACKUP_ONLY_DEFAULT = Fundraiser.Config.BACKUP_ONLY_DEFAULT,
}
