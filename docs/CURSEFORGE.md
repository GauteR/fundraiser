<!--
  CurseForge / Wago project description for Fundraiser.

  How to use:
  1. Copy everything below the horizontal rule.
  2. CurseForge → project → Description → Markdown mode → paste → Save.
  Do not ship this file inside the AddOns zip.
-->

---

# Fundraiser

Guild **donation reminders** for **World of Warcraft: Forever**.

Officers publish a shared fundraising goal. Members see a reminder when opening bags until they mail the designated character. A simple self-attested ledger tracks who contributed what.

## Features

- Guild-only fundraiser events (name, mail target, reminder interval)
- Bag-open reminder until mail is sent to the target
- Officer admin ranks configurable per event
- Install presence: who is online without the addon (best-effort)
- Self-attested contribution ledger (not a bank audit)
- Thin hidden guild sync (no third-party sync library required in MVP)

## Install

1. Install via CurseForge / your preferred client, **or** copy the `fundraiser` folder to:

   `World of Warcraft\_forever_\Interface\AddOns\fundraiser`

2. Restart the client or log out and back in.
3. Enable **Fundraiser** on the character addon list if needed.

**Requires Forever** (`Interface` 16001 / 1.60.x). Not for Classic Era or Retail.

## How to use

1. Officers: `/fundraiser` → set event fields → **Publish event**.
2. Members keep the addon installed; open bags to see reminders when due.
3. Send mail (with gold if you like) to the designated target to clear the current reminder window.

## Slash

`/fundraiser` — open the window · `/fundraiser status` — enabled flag
