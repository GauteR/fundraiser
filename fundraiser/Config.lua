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
  ADMIN_UI = true,
  -- Admin window: end active campaign (archive + guild wipe) without publishing a new event.
  END_EVENT = true,
  LEDGER = true,
  TARGET_UI = true,
  -- Donation target: show the Target panel beside the auction house while it is open.
  TARGET_AUTO_DOCK = true,
  -- Global frame names the dock may sit beside (the right-most visible one wins). Auctionator's
  -- tabs live inside AuctionHouseFrame; its price history window can dock to the right of it.
  -- Add another addon's auction window here by its frame name (find it with /fstack).
  TARGET_DOCK_ANCHORS = { "AuctionHouseFrame", "AuctionFrame", "AuctionatorItemHistoryFrame" },
  AH_ASSIST = true,
  -- Solo in-game simulation: /fundraiser debug …
  DEBUG = true,

  ADDON_NAME = "Fundraiser",
  VERSION = "0.1.0",
  SLASH_COMMAND = "/fundraiser",

  -- TSM custom price for "lowest" AH reference (fallback: Auctionator, then manual).
  TSM_PRICE_SOURCE = "DBMinBuyout",
  AH_CUT_FRACTION = 0.05,
  -- Forever auction duration index: 1 = 2h, 2 = 8h, 3 = 24h.
  AH_DURATION = 3,
  AH_UNDERCUT_COPPER = 0,
  -- Target page: stacks worth less than this (copper, value of the recommended action)
  -- stay listed but are left out of Post all / Sell all.
  MIN_STACK_VALUE_COPPER = 100,

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
}
