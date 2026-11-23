# Fundraiser

A fundraiser addon to help you fund your in-game guild and group events on **World of Warcraft: Forever**.

Officers publish a shared campaign (name, donation mail target, reminder interval). Guild members see a reminder beside the mailbox asking them to send what they can spare to that character. The **ledger** records incoming mail and auction-house sales on the donation-target alt and meshes across every installed client; only officers and the target can view it in the UI (not encrypted).

| | |
| --- | --- |
| Interface | `16001` (Forever / build line 1.60.x) |
| Slash command | `/fundraiser` |
| Language | English (UI and docs) |
| Version | From git tag via `@project-version@` in TOC (see [`docs/RELEASE.md`](docs/RELEASE.md)) |

## Features

- Feature flags in [`fundraiser/Config.lua`](fundraiser/Config.lua): `ENABLED`, `COMM`, `RESET_SYNC`, `REMINDER`, `BACKUP_ONLY_OPTION`, `ADMIN_UI`, `END_EVENT`, `LEDGER`, `LEDGER_AUTO_REFRESH`, `TARGET_UI`, `TARGET_PREFS`, `TARGET_AUTO_DOCK`, `AH_DEPOSIT_IN_ADVICE`, `AH_ASSIST`, `DEBUG`
- Officer-published event: name, **First Last** mail target, required fundraising goal (gold), optional goal note, per-event reminder interval
- Mailbox reminder for members (beside the mail window) until mail is sent to the target; members who only want to help with backup can tick **Only backup** in Options to stop it (officers see them as **Only backup**)
- Ledger writes on the **donation-target** only (incoming mail money/items, each item mail as one row that later auction and vendor sales fill with their net proceeds, + **all** AH sales + manual donations from the **Add donation** menu page, which officers can also use); the open ledger page updates as rows arrive; every client stores/relays the mesh; officers + target view in UI
- Target page (`/fundraiser target`, **Target** in the main window menu, donation-target character only): scans your bags, shows item names in their quality colour, splits stacks into **Auction**, **Vendor** and **Needs price** lists from TSM -> Auctionator -> manual prices, one action per selected stack, or **Post all** / **Sell all** for a whole list (confirmed; stacks below the minimum value, marked **Skip** (this session) or of an **Ignored** item are left out; the ignore list and your own minimum value are saved, see Options, where the ignore list can also be exported and imported as text to copy it to another character)
- Thin guild sync (`HELLO` / `EVENT` / `LEDGER` / `DIGEST` / `RESET`) — see [`docs/SYNC.md`](docs/SYNC.md)
- Publishing a new event archives the previous event + ledger locally and clears the active ledger
- Ending an event (`END_EVENT`): Minus on the event card archives the campaign, clears active event+ledger, and broadcasts `RESET campaign` to the guild (no replacement event)
- Options -> AddOns -> Fundraiser: status, online installs (name / status / version), default reminder interval, global min admin rank; admin **Danger zone** (local clears + **Broadcast reset**)
- One window with a left menu (Home / Ledger / Settings) and top-bar buttons (+ new event, - end event, refresh) and a logo band; `/fundraiser ledger` (or the Ledger menu entry / ledger card) opens the ledger page: scrollable ledger of the active event with archived campaigns as one summary line each at the bottom; **Set MOTD** (left menu) posts raised/goal and the top contributor to the guild message (confirmation, needs MOTD permission)
- `/fundraiser` admin window: status dashboard (event, progress %, ledger, daily raised chart); **New event** / **End event**; **Addon settings** opens Options (chat warning if the jump fails)
- Pure Lua unit tests (Given / When / Then scenarios)

## Dedicated donation character

Set the donation mail target to an alt used **only** for this fundraiser (receive mail + post AH). Forever names are **First Last** — enter both parts (e.g. `Bank Alt`). Do not run personal auctions on that character — every AH sale is recorded as fundraiser income.

## Install

1. Copy the `fundraiser` folder into your Forever AddOns directory, for example:

   `World of Warcraft\_forever_\Interface\AddOns\fundraiser`

2. Restart the client, or log out and back in.
3. Enable **Fundraiser** on the character addon list if it is disabled.
4. Type `/fundraiser` in chat.

Local publish: `./scripts/publish-local.sh` or `scripts/publish-local.ps1`, then `/reload`.

### Solo debug (no other guild clients)

With `Config.DEBUG = true`:

```
/fundraiser debug help
/fundraiser debug seed
/fundraiser debug seed me   (you become the donation target)
/fundraiser debug hello DebugMember
/fundraiser debug event 0
/fundraiser debug ledger mail DebugDonor 50000 gift
/fundraiser debug ledger ah AH 120000 Sword
/fundraiser debug reminder
/fundraiser debug dismiss
/fundraiser debug presence
/fundraiser debug access
/fundraiser debug member
/fundraiser debug officer
/fundraiser debug asrank 9
/fundraiser debug asrank clear
```

## Usage

1. Set **Defaults** under Settings -> AddOns -> Fundraiser (or **Settings** in the left menu of the admin window): default reminder interval and global min admin rank (rank index <= this may manage).
2. Officers: `/fundraiser` opens the admin status dashboard (event, progress toward goal, ledger status, raised chart; install presence is under Settings -> AddOns -> Fundraiser). Press **New event** (+), fill fields including **Goal (gold)** (required; per-event interval overrides the default) -> **Publish event** (target = dedicated fundraiser alt). Publishing a new event **archives** the previous event+ledger locally and clears the active ledger. Press **End event** (-) to archive and clear the active campaign for the guild without creating a replacement. Members get a chat refusal if they open `/fundraiser`.
3. Members open the mailbox to see the reminder when due; mailing the target clears the interval.
4. On the target alt: empty the mailbox the normal way, then open the auction house: the Target panel docks to its right side automatically (or open **Target** in the main window / `/fundraiser target` at a vendor) -> select a stack -> Post AH / Vendor; AH sales also hit the ledger. The page scans bags only. Other characters get no Target menu entry and cannot open the page.

Close windows with the frame X or Escape (`UISpecialFrames`).

### Options (Settings -> AddOns -> Fundraiser)

| Control | Meaning |
| --- | --- |
| Help | Short pitch: fund guild and group events |
| Only backup | Checkbox above Status (saved at once): no mailbox reminder; shown as Only backup in Online installs |
| Status | Settings-style rows: addon enabled, guild, active event, admin access, installed count |
| Online installs | Scrollable table (name / status / version from HELLO) |
| Defaults | Default reminder interval (hours) and min admin rank; Apply saves to `FundraiserDB.settings` |
| Danger zone (admin) | Separated by a rule; local reset/clear actions; **Broadcast reset** sends guild `RESET\|all` (requires `COMM` + `RESET_SYNC`, rank-gated on receive). Hidden without admin access. |
| Open Fundraiser | Shown only when your rank may manage fundraisers |

Defaults are stored in `FundraiserDB.settings` and overlaid onto `Config` at load. Forever may not restore SavedVariables after a cold start — re-apply in Options if needed. The same goes for the target page preferences (`FundraiserDB.target`: ignored items and minimum stack value, `Config.TARGET_PREFS`); without them the config minimum applies. `DEBUG` stays in `Config.lua` only.

## Configuration

Edit [`fundraiser/Config.lua`](fundraiser/Config.lua) for feature flags and compile-time defaults (Options can override interval/rank at runtime via SavedVariables):

| Setting | Default | Meaning |
| --- | --- | --- |
| `ENABLED` | `true` | Master feature flag |
| `COMM` | `true` | Guild addon messages |
| `RESET_SYNC` | `true` | Accept/send officer `RESET` wipe messages |
| `REMINDER` | `true` | Mailbox reminder popup + mail dismiss |
| `BACKUP_ONLY_OPTION` | `true` | Options **Only backup** row; sends the flag in HELLO (`false` = hidden, ignored) |
| `BACKUP_ONLY_DEFAULT` | `false` | File default for Only backup when SavedVariables are not restored |
| `ADMIN_UI` | `true` | Main window |
| `LEDGER` | `true` | Target logging + officer ledger UI |
| `TARGET_UI` | `true` | Donation-target page (bag scan, AH / vendor actions) |
| `TARGET_AUTO_DOCK` | `true` | Show the Target panel beside the auction house while it is open (donation target only) |
| `TARGET_AUTO_OPEN_VENDOR` | `true` | Open the main window on the Target page, beside the vendor window, when a vendor opens (donation target only); it closes with the vendor |
| `LEDGER_AUTO_OPEN_MAILBOX` | `true` | Open the main window on the ledger, beside the mail window, when the mailbox opens (donation target only); it closes with the mailbox |
| `LEADERBOARD_EXCLUDED_RANK` | `0` | Donations from this guild rank index (0 = Guild Master) count towards the total but not as top contributor; `nil` counts everyone |
| `AH_ASSIST` | `true` | AH/vendor actions from target UI |
| `TSM_PRICE_SOURCE` | `"DBMinBuyout"` | TSM price key for min AH reference |
| `DEBUG` | `true` | Solo sim: `/fundraiser debug …` (not in Options) |
| `DEFAULT_REMINDER_INTERVAL` | `86400` | Default interval seconds (Options overlay) |
| `DEFAULT_MIN_ADMIN_RANK` | `1` | Global admin gate: rank <= this (Options overlay) |
| `PRESENCE_STALE` | `600` | HELLO freshness for install presence |
| `SLASH_COMMAND` | `"/fundraiser"` | Slash command |
| `VERSION` | `"0.1.0"` | Options version when TOC placeholder is unpackaged |

After changing `Config.lua` flags, `/reload`.

## Docs

| Doc | Topic |
| --- | --- |
| [`docs/SYNC.md`](docs/SYNC.md) | Thin sync, ledger merge, trust model |
| [`docs/CURSEFORGE.md`](docs/CURSEFORGE.md) | Store description |
| [`docs/RELEASE.md`](docs/RELEASE.md) | Packager / GitHub Release |

## Tests

Pure Lua scenarios use **Given / When / Then** comments (no WoW client).

```bash
lua tests/test_domain.lua
lua tests/test_options_settings.lua
lua tests/test_release_meta.lua
```

## License

[MIT](LICENSE) © 2026 GauteR
