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

Officers publish a shared fundraising goal. Members see a reminder beside the mailbox until they mail the designated character.

The ledger is recorded on the **donation-target character** (incoming mail and all auction-house sales) and meshed across all installed clients; officers and the target can view it. Use a character dedicated only to that role — do not mix personal AH there.

## Features

- Guild-only fundraiser events (name, mail target, reminder interval)
- Mailbox reminder until mail is sent to the target
- Officer admin ranks configurable per event
- Ledger on the donation target; guild-wide mesh relay; officer/target view
- Install presence: who is online without the addon (best-effort)

## Install

1. Install via CurseForge / your preferred client, **or** copy the `fundraiser` folder to:

   `World of Warcraft\_forever_\Interface\AddOns\fundraiser`

2. Restart the client or log out and back in.
3. Enable **Fundraiser** on the character addon list if needed.

**Requires Forever** (`Interface` 16001 / 1.60.x). Not for Classic Era or Retail.

## How to use

1. Officers: `/fundraiser` → set event fields (target = dedicated fundraiser alt) → **Publish event**.
2. Members keep the addon installed; open the mailbox to see reminders when due.
3. Send mail to the designated target to clear the current reminder window.
4. On the target alt, receive mail and run AH — any online member with the addon can relay; officers see the ledger when they log in.

## Slash

`/fundraiser` — open the window · `/fundraiser status` — enabled flag
