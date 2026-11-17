# Fundraiser

Guild donation reminders for **World of Warcraft: Forever**.

Officers publish a shared fundraising goal; members see a reminder beside the mailbox until they mail the designated recipient. The **ledger** is written on the donation-target character (incoming mail + all AH sales) and **meshed** across every installed client; only officers and the target may view it in the UI (not encrypted).

| | |
| --- | --- |
| Interface | `16001` (Forever / build line 1.60.x) |
| Slash command | `/fundraiser` |
| Language | English (UI and docs) |
| Version | From git tag via `@project-version@` in TOC (see [`docs/RELEASE.md`](docs/RELEASE.md)) |

## Features

- Feature flags in [`fundraiser/Config.lua`](fundraiser/Config.lua): `ENABLED`, `COMM`, `REMINDER`, `ADMIN_UI`, `LEDGER`, `DEBUG`
- Officer-published event (name, mail target, per-event reminder interval)
- Mailbox reminder for members (beside the mail window) until mail is sent to the target
- Ledger writes on the **donation-target** only; all clients store/relay the mesh; officers + target view in UI
- Logs incoming mailbox money/items and **all** AH sales on that character
- Target inbox assist (`/fundraiser target`): per-sender stacks, TSM→Auctionator→manual price, vendor vs AH advice, one AH post per stack
- Thin guild sync (`HELLO` / `EVENT` / `LEDGER` / `DIGEST`) — see [`docs/SYNC.md`](docs/SYNC.md)
- Options → AddOns → Fundraiser: status, default reminder interval, global min admin rank; `/fundraiser` has an **Addon settings** button to open that panel
- Pure Lua unit tests

## Dedicated donation character

Set `DesignatedDonationTarget` to an alt used **only** for this fundraiser (receive mail + post AH). Forever names are **First Last** — enter both parts (e.g. `Bank Alt`). Do not run personal auctions on that character — every AH sale is recorded as fundraiser income.

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

1. Set **Defaults** under Settings → AddOns → Fundraiser (or **Addon settings** in the admin window): default reminder interval and global min admin rank (rank ≤ this may manage).
2. Officers: `/fundraiser` → fill event fields (per-event interval overrides the default) → **Publish event** (target = dedicated fundraiser alt). Members get a chat refusal if they open `/fundraiser`.
3. Members open the mailbox to see the reminder when due; mailing the target clears the interval.
4. On the target alt: open mailbox → `/fundraiser target` (or **Target inbox assist**) → Post AH / Vendor per stack; AH sales also hit the ledger. Other characters cannot open the target UI.

Close windows with the frame X or Escape (`UISpecialFrames`).

### Options (Settings → AddOns → Fundraiser)

| Control | Meaning |
| --- | --- |
| Status | Settings-style rows: enabled, guild, event, admin access, installed count |
| Online installs | Scrollable table (name / status / version from HELLO) |
| Defaults | Settings-style rows with tooltips; Apply saves to `FundraiserDB.settings` |
| Default reminder interval | Hours; used when publishing without a per-event override / empty interval field |
| Min admin rank | Global only (0 = GM); not set per event |
| Open Fundraiser | Shown only when your rank may manage fundraisers |

Defaults are stored in `FundraiserDB.settings` and overlaid onto `Config` at load. Forever may not restore SavedVariables after a cold start — re-apply in Options if needed. `DEBUG` stays in `Config.lua` only.

## Configuration

Edit [`fundraiser/Config.lua`](fundraiser/Config.lua) for feature flags and compile-time defaults (Options can override interval/rank at runtime via SavedVariables):

| Setting | Default | Meaning |
| --- | --- | --- |
| `ENABLED` | `true` | Master feature flag |
| `COMM` | `true` | Guild addon messages |
| `REMINDER` | `true` | Mailbox reminder popup + mail dismiss |
| `ADMIN_UI` | `true` | Main window |
| `LEDGER` | `true` | Target logging + officer ledger UI |
| `TARGET_UI` | `true` | Donation-target inbox assist window |
| `AH_ASSIST` | `true` | AH/vendor actions from target UI |
| `TSM_PRICE_SOURCE` | `"DBMinBuyout"` | TSM price key for min AH reference |
| `DEBUG` | `true` | Solo sim: `/fundraiser debug …` (not in Options) |
| `DEFAULT_REMINDER_INTERVAL` | `86400` | Default interval seconds (Options overlay) |
| `DEFAULT_MIN_ADMIN_RANK` | `1` | Global admin gate: rank ≤ this (Options overlay) |
| `PRESENCE_STALE` | `600` | HELLO freshness for “missing install” |
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

```bash
lua tests/test_domain.lua
lua tests/test_options_settings.lua
lua tests/test_release_meta.lua
```

## License

[MIT](LICENSE) © 2026 GauteR
