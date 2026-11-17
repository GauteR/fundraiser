# Fundraiser

Guild donation reminders for **World of Warcraft: Forever**.

Officers publish a shared fundraising goal; members get bag reminders until they mail the designated recipient. The **ledger** is written on the donation-target character (incoming mail + all AH sales) and merged peer-to-peer among officers.

| | |
| --- | --- |
| Interface | `16001` (Forever / build line 1.60.x) |
| Slash command | `/fundraiser` |
| Language | English (UI and docs) |
| Version | From git tag via `@project-version@` in TOC (see [`docs/RELEASE.md`](docs/RELEASE.md)) |

## Features

- Feature flags in [`fundraiser/Config.lua`](fundraiser/Config.lua): `ENABLED`, `COMM`, `REMINDER`, `ADMIN_UI`, `LEDGER`, `DEBUG`
- Officer-published event (name, mail target, reminder interval, min admin rank)
- Bag-open reminder for members until mail is sent to the target
- Ledger on the **donation-target** character only for writes; officers hold merged replicas
- Logs incoming mailbox money/items and **all** AH sales on that character
- Thin guild sync (`HELLO` / `EVENT` / `LEDGER` / `DIGEST`) — see [`docs/SYNC.md`](docs/SYNC.md)
- Options → AddOns → Fundraiser panel
- Pure Lua unit tests

## Dedicated donation character

Set `DesignatedDonationTarget` to an alt used **only** for this fundraiser (receive mail + post AH). Do not run personal auctions on that character — every AH sale is recorded as fundraiser income.

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
```

## Usage

1. Officers: `/fundraiser` → fill event fields → **Publish event** (target = dedicated fundraiser alt).
2. Members open bags to see reminders when due; mailing the target clears the interval.
3. On the target alt: open mailbox / sell on AH — rows appear in the officer ledger after sync.

Close windows with the frame X or Escape (`UISpecialFrames`).

## Configuration

Edit [`fundraiser/Config.lua`](fundraiser/Config.lua):

| Setting | Default | Meaning |
| --- | --- | --- |
| `ENABLED` | `true` | Master feature flag |
| `COMM` | `true` | Guild addon messages |
| `REMINDER` | `true` | Bag reminder + mail dismiss |
| `ADMIN_UI` | `true` | Main window |
| `LEDGER` | `true` | Target logging + officer ledger UI |
| `DEBUG` | `true` | Solo sim: `/fundraiser debug …` |
| `DEFAULT_REMINDER_INTERVAL` | `86400` | Fallback interval (seconds) |
| `PRESENCE_STALE` | `600` | HELLO freshness for “missing install” |
| `SLASH_COMMAND` | `"/fundraiser"` | Slash command |
| `VERSION` | `"0.1.0"` | Options version when TOC placeholder is unpackaged |

After changing config, `/reload`.

## Docs

| Doc | Topic |
| --- | --- |
| [`docs/SYNC.md`](docs/SYNC.md) | Thin sync, ledger merge, trust model |
| [`docs/CURSEFORGE.md`](docs/CURSEFORGE.md) | Store description |
| [`docs/RELEASE.md`](docs/RELEASE.md) | Packager / GitHub Release |

## Tests

```bash
lua tests/test_domain.lua
lua tests/test_release_meta.lua
```

## License

[MIT](LICENSE) © 2026 GauteR
