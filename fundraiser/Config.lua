-- Feature flags and shared settings for Forever Fundraiser.
Fundraiser = Fundraiser or {}

Fundraiser.Config = {
  -- Master switch: false disables slash, UI, sync, and reminders.
  ENABLED = true,
  COMM = true,
  -- Reminder popup while the mailbox is open (not bags).
  REMINDER = true,
  ADMIN_UI = true,
  LEDGER = true,
  TARGET_UI = true,
  AH_ASSIST = true,
  -- Solo in-game simulation: /fundraiser debug …
  DEBUG = true,

  ADDON_NAME = "Fundraiser",
  VERSION = "0.1.0",
  SLASH_COMMAND = "/fundraiser",

  -- TSM custom price for "lowest" AH reference (fallback: Auctionator, then manual).
  TSM_PRICE_SOURCE = "DBMinBuyout",
  AH_CUT_FRACTION = 0.05,
  AH_DURATION = 2,
  AH_UNDERCUT_COPPER = 0,

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
