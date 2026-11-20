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

- Admin window status dashboard: event card, progress toward goal, ledger status, raised-over-time chart; New event (+) and End event (-) on the event card; Settings / Target shortcuts
- Publish a fundraiser event (name, Forever First Last mail target, required goal in gold, optional note, reminder interval); end an active campaign (archive + guild wipe) without publishing a replacement
- Mailbox reminder until mail is sent to the donation target
- One window with a left menu (Home / Ledger / Settings) and top-bar buttons (+ new event, - end event, refresh). Ledger page (`/fundraiser ledger`, menu entry or the admin ledger card): scrollable donation rows, total, previous campaigns as summary lines, and a **Set MOTD** menu entry for the guild message (raised vs goal + top contributor)
- Ledger on the donation target (mail intake + all AH sales; officers and the target can add manual donations); guild-wide mesh relay; officer/target view
- Target page in the main window (donation target only): bag stacks split into Auction / Vendor / Needs price lists, TSM -> Auctionator -> manual price, post or vendor one stack at a time or a whole list after a confirmation (Skip and a minimum value keep stacks out)
- Settings -> AddOns -> Fundraiser: status, online installs, default reminder interval, global min admin rank; admin Danger zone for cleanup / broadcast reset
- Best-effort install presence (who is online with the addon)

## Install

1. Install via CurseForge / your preferred client, **or** copy the `fundraiser` folder to:

   `World of Warcraft\_forever_\Interface\AddOns\fundraiser`

2. Restart the client or log out and back in.
3. Enable **Fundraiser** on the character addon list if needed.

**Requires Forever** (`Interface` 16001 / 1.60.x). Not for Classic Era or Retail.

## How to use

1. Officers: Settings -> AddOns -> Fundraiser for default interval and min admin rank, then `/fundraiser` -> **New event** -> set fields (target = dedicated fundraiser alt; **Goal (gold)** required; interval overrides the default) -> **Publish event**. Use **End event** to archive and clear the active campaign for the guild without creating a new one.
2. Members keep the addon installed; open the mailbox to see reminders when due.
3. Send mail to the designated target to clear the current reminder window.
4. On the target alt: empty the mailbox, then open **Target** in the main window (or `/fundraiser target`) at the auction house or a vendor to post or sell stacks from your bags. Officers see the ledger when they log in; any online member with the addon can help relay mesh data.

## Slash

`/fundraiser` — open the admin window · `/fundraiser status` — enabled flag · `/fundraiser target` — donation-target page
