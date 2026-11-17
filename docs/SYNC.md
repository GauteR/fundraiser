# Guild sync

Fundraiser uses a **thin** hidden guild channel (`SendAddonMessage` / `CHAT_MSG_ADDON`, prefix `Fundraiser`).

## Roles

| Who | Data |
| --- | --- |
| All members | `EVENT` + mailbox reminder until they mail the designated target |
| Donation target character | Writes ledger rows (incoming mail + **all** AH sales) into local SavedVariables, then broadcasts |
| Officers (`rank <= minAdminRank`) | Replica of the ledger via peer merge; UI access |

**Important:** The donation-target character should be used **only** for this fundraiser (mail intake + AH). Personal AH on that alt will be logged as fundraiser income.

## Messages

| Kind | Purpose |
| --- | --- |
| `HELLO` | Presence; officers/target may push full ledger snapshot |
| `EVENT` | Officer event snapshot (revisioned; receive-side rank check) |
| `LEDGER` | Single ledger row (`mail` or `ah`) |
| `DIGEST` | Event revision + ledger fingerprint (count/sum/maxAt) |

## Ledger merge

Replicas merge by **entry id** (union). Same id → newer `at` wins (then higher copper). Stale logins do not wipe peers; they rebase/merge like combining commits.

## Trust model

- Addon messages are not cryptographically signed.
- `EVENT` requires sender guild rank `<= minAdminRank`.
- `LEDGER` accepted from the donation target **or** an officer; only officers/target store & view.
- Members never write ledger rows (sending mail only dismisses their reminder).

## Solo debug

`Config.DEBUG = true` → `/fundraiser debug …` (see README).

## Later

LibGuildSync on CurseForge can replace the thin adapter (issue #6).
