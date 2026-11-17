# Guild sync (MVP)

Fundraiser uses a **thin** hidden guild channel (`SendAddonMessage` / `CHAT_MSG_ADDON`, prefix `Fundraiser`).

## Messages

| Kind | Purpose |
| --- | --- |
| `HELLO` | Presence + addon version |
| `EVENT` | Officer event snapshot (revisioned) |
| `DONATE` | Self-attested contribution |
| `DIGEST` | Catch-up hint (event revision + contribution count) |

## Trust model

- Addon messages are **not** cryptographically signed.
- `EVENT` is accepted only if the sender’s **guild rank index** (from roster) is `<= event.minAdminRank`.
- `DONATE` is treated as **self-attested** (honor system), not proof from the guild bank.
- SavedVariables (`FundraiserDB`) are a cache; Forever may omit them after cold start — peers rehydrate via HELLO/DIGEST/EVENT when online.

## Later

When [LibGuildSync](https://github.com/Nedyar/LibGuildSync) is available on CurseForge, it can replace the thin adapter behind the same application ports (see GitHub issue #6).
