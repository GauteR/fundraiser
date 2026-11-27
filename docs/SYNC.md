# Guild sync

Fundraiser uses a **thin** hidden guild channel (`SendAddonMessage` / `CHAT_MSG_ADDON`, prefix `Fundraiser`).

## Roles

| Who | Data |
| --- | --- |
| All members with the addon | `EVENT`, mailbox reminder, and a **ledger mesh replica** (store + relay) |
| Donation target character | Writes ledger rows (incoming mail + **all** AH sales), then broadcasts |
| Officers (`rank <=` global `DEFAULT_MIN_ADMIN_RANK` from Options/Config) + donation target | May **view** the ledger in UI |

**Important:** The donation-target character should be used **only** for this fundraiser (mail intake + AH). Personal AH on that alt will be logged as fundraiser income.

## Ledger mesh

Every installed client keeps the same id-union replica and will push a snapshot when peers say `HELLO` / when `DIGEST` shows they are behind. Officers do **not** all need to be online for the mesh to move data — any online member with rows can relay.

The ledger page (`UI/Ledger.lua`) only reads the local store and `FundraiserDB.archives`; it adds no wire traffic. **Set MOTD** calls the guild MOTD API directly (not part of the mesh).

**UI gate only:** members without view access still store/relay; they do not see ledger totals in the admin window. This is **not** encryption. A modified addon or inspection of local data can read plaintext rows.

## Messages

| Kind | Purpose |
| --- | --- |
| `HELLO` | Presence; any peer holding rows may push a full ledger snapshot |
| `EVENT` | Officer event snapshot (revisioned; receive-side rank check). Wire: `EVENT\|id\|name\|target\|goal\|interval\|minAdmin\|rev\|publishedAt\|publisher\|goalCopper` — `goal` is an optional note; `goalCopper` is the numeric fundraising target (copper). Older peers omit field 11 → treat as `0`. |
| `LEDGER` | Single ledger row (`mail`, `ah` or `manual`); all clients merge into local store |
| `DIGEST` | Event revision + ledger fingerprint (count/sum/maxAt) |
| `IGNORE` | Shared Target-page ignore list entry (only when `Config.TARGET_IGNORE_SYNC`). Wire: `IGNORE\|op\|itemId\|name\|at` with `op` = `add` or `remove`; last write wins per item, a tie goes to `remove`. Not relayed. A peer's `HELLO` triggers a throttled, batched snapshot reply. No rank check and no authentication, so any member can publish |
| `RESET` | Officer wipe (`all` / `event` / `ledger` / `presence` / `campaign`) + `resetEpoch`; sender rank check; all acceptors wipe locally. `campaign` archives the active event+ledger first, then clears both and bumps epoch. Ended campaign ids stay in local archives and are rejected on `EVENT` re-accept (blocks mesh revival after End event) |
| (epoch) | `HELLO` / `DIGEST` / `LEDGER` include `resetEpoch` (default 0 for older clients) |
| (backup) | `HELLO` may carry a trailing `1` when the sender chose **Only backup**; absent = not backup-only (older clients) |

## Ledger merge

Replicas merge by **entry id** (union). Same id → newer `at` wins (then higher copper). Stale logins do not wipe peers; they rebase/merge like combining commits.

## Trust model

- Addon messages are not cryptographically signed.
- `EVENT` requires sender guild rank `<=` local global min admin rank (Options/Config); `event.minAdminRank` on the wire is stamped for older clients but ignored for local gates.
- `RESET` (when `Config.RESET_SYNC`) requires the same admin rank gate on the **sender**. **Every** receiving client that accepts applies the wipe (members included). A `resetEpoch` is bumped and carried on `HELLO` / `DIGEST` / `LEDGER` / `RESET` so late peers adopt the wipe and **stale ledger rows from older epochs are rejected** (stops mesh refill after a wipe).
- `LEDGER` rows are accepted from any guild peer for mesh storage (so relays work). A malicious member can forge rows — treat the ledger as guild-trusted, not secret.
- Only the donation target **writes** new rows from mail/AH; manual donations (`manual`) may also be added by officers (the mesh does not check the sender, see the trust note); members only dismiss reminders when they send mail.
- Viewing remains `Roles.CanViewLedger` (target or rank ≤ global min admin rank).

## Solo debug

`Config.DEBUG = true` → `/fundraiser debug …` (see README). Use `debug member` / `asrank` to confirm UI refusal while mesh store still applies.

## Later

LibGuildSync on CurseForge can replace the thin adapter (issue #6).
