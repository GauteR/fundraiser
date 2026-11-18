<!--
  CurseForge / Wago project description for Fundraiser.

  How to use:
  1. Copy everything below the horizontal rule.
  2. CurseForge → project → Description → Markdown mode → paste → Save.
  Do not ship this file inside the AddOns zip.
-->

---

# Fundraiser

A fundraiser addon to help you fund your in-game **guild and group events** on **World of Warcraft: Forever**.

Officers publish a shared campaign. Members see a reminder beside the mailbox asking them to send what they can spare to the designated donation character. Incoming mail and auction-house sales on that character are logged to a guild ledger (meshed to every installed client; officers and the target can view it).

Use a character dedicated only to that role — do not mix personal AH there.

## Features

- Publish a fundraiser event (name, Forever First Last mail target, goal note, reminder interval)
- Mailbox reminder until mail is sent to the donation target
- Ledger on the donation target (mail intake + all AH sales); guild-wide mesh relay; officer/target view
- Target inbox assist: per-sender stacks, TSM -> Auctionator -> manual price, vendor vs AH advice
- Settings -> AddOns -> Fundraiser: status, online installs, default reminder interval, global min admin rank, cleanup / broadcast reset
- Best-effort install presence (who is online with the addon)

## Install

1. Install via CurseForge / your preferred client, **or** copy the `fundraiser` folder to:

   `World of Warcraft\_forever_\Interface\AddOns\fundraiser`

2. Restart the client or log out and back in.
3. Enable **Fundraiser** on the character addon list if needed.

**Requires Forever** (`Interface` 16001 / 1.60.x). Not for Classic Era or Retail.

## How to use

1. Officers: Settings -> AddOns -> Fundraiser for default interval and min admin rank, then `/fundraiser` (or **Open Fundraiser** / **Addon settings**) -> set event fields (target = dedicated fundraiser alt; interval overrides the default) -> **Publish event**.
2. Members keep the addon installed; open the mailbox to see reminders when due.
3. Send mail to the designated target to clear the current reminder window.
4. On the target alt: open the mailbox, use `/fundraiser target` (or **Target inbox assist**) to post AH or vendor stacks. Officers see the ledger when they log in; any online member with the addon can help relay mesh data.

## Slash

`/fundraiser` — open the admin window · `/fundraiser status` — enabled flag · `/fundraiser target` — donation-target inbox assist
