# Fundraiser

Guild donation reminders for **World of Warcraft: Forever**.

Officers publish a shared fundraising goal; members get bag reminders until they mail the designated recipient. A self-attested ledger and install-presence list help officers follow up.

| | |
| --- | --- |
| Interface | `16001` (Forever / build line 1.60.x) |
| Slash command | `/fundraiser` |
| Language | English (UI and docs) |
| Version | From git tag via `@project-version@` in TOC (see [`docs/RELEASE.md`](docs/RELEASE.md)) |

## Features

- Feature flags in [`fundraiser/Config.lua`](fundraiser/Config.lua): `ENABLED`, `COMM`, `REMINDER`, `ADMIN_UI`, `LEDGER`
- Officer-published event (name, mail target, reminder interval, min admin rank)
- Bag-open reminder until mail is sent to the target (returns after the next interval)
- Thin guild sync (`HELLO` / `EVENT` / `DONATE` / `DIGEST`) — see [`docs/SYNC.md`](docs/SYNC.md)
- Self-attested ledger (not bank verification)
- Options → AddOns → Fundraiser panel
- Pure Lua unit tests

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
/fundraiser debug donate DebugDonor 50000
/fundraiser debug reminder
/fundraiser debug dismiss
/fundraiser debug presence
```

`event [rank]` applies a newer snapshot with a simulated sender rank (bypasses roster). `hello` / `donate` inject through the same `CHAT_MSG_ADDON` handler as real peers.

## Usage

1. Log in on a guild character.
2. Officers: `/fundraiser` → fill event fields → **Publish event**.
3. Members open bags to see reminders when due.
4. Mail gold/items to the designated character to clear the current reminder window.

Close windows with the frame X or Escape (`UISpecialFrames`).

## Configuration

Edit [`fundraiser/Config.lua`](fundraiser/Config.lua):

| Setting | Default | Meaning |
| --- | --- | --- |
| `ENABLED` | `true` | Master feature flag |
| `COMM` | `true` | Guild addon messages |
| `REMINDER` | `true` | Bag reminder + mail dismiss |
| `ADMIN_UI` | `true` | Main window |
| `LEDGER` | `true` | Show ledger totals |
| `DEBUG` | `true` | Solo sim: `/fundraiser debug …` (set `false` for normal play) |
| `DEFAULT_REMINDER_INTERVAL` | `86400` | Fallback interval (seconds) |
| `PRESENCE_STALE` | `600` | HELLO freshness for “missing install” |
| `SLASH_COMMAND` | `"/fundraiser"` | Slash command |
| `VERSION` | `"0.1.0"` | Options version when TOC placeholder is unpackaged |

After changing config, `/reload`.

## Docs

| Doc | Topic |
| --- | --- |
| [`docs/SYNC.md`](docs/SYNC.md) | Thin sync protocol and trust model |
| [`docs/CURSEFORGE.md`](docs/CURSEFORGE.md) | Store description |
| [`docs/RELEASE.md`](docs/RELEASE.md) | Packager / GitHub Release |

## Tests

```bash
lua tests/test_domain.lua
lua tests/test_release_meta.lua
```

## License

[MIT](LICENSE) © 2026 GauteR
