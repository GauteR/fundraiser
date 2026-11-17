-- Feature flags and shared settings for Forever Fundraiser.
Fundraiser = Fundraiser or {}

Fundraiser.Config = {
  -- Master switch: false disables slash, UI, sync, and reminders.
  ENABLED = true,
  COMM = true,
  REMINDER = true,
  ADMIN_UI = true,
  LEDGER = true,
  -- Solo in-game simulation: /fundraiser debug …
  DEBUG = true,

  ADDON_NAME = "Fundraiser",
  VERSION = "0.1.0",
  SLASH_COMMAND = "/fundraiser",

  -- Addon message prefix (max 16 characters on Classic-era clients).
  COMM_PREFIX = "Fundraiser",
  PROTOCOL = "1",

  -- Default reminder interval in seconds (officers override per event).
  DEFAULT_REMINDER_INTERVAL = 86400,

  -- Presence: HELLO older than this is treated as stale (seconds).
  PRESENCE_STALE = 600,

  -- SavedVariables global name (also listed in TOC).
  SAVED_VARIABLE = "FundraiserDB",
}
