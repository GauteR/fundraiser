# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Target page in the main window (menu entry **Target**, `/fundraiser target`, and the Home button), shown only on the donation-target character. It scans the bags, lists stacks under Auction, Vendor and Needs price headers, and posts or vendors the selected stack with the result shown inline. Rescans on bag changes. Same cards and margins as Home and Ledger.
- Target assist groundwork: a bag scan (`Adapters/BagAssist.lua`) that lists stacks with TSM / Auctionator and vendor prices and the sale advice, a view model that groups stacks into Auction, Vendor and Needs price lists (`Domain/TargetView.lua`), and a bulk action queue (`Domain/ActionQueue.lua`). New constant `Config.MIN_STACK_VALUE_COPPER` (default 100 copper): stacks below it will be left out of bulk actions. No UI change yet.
- Manual donations: officers and the donation-target character can add a donation by hand (Add donation menu page: donor, amount in gold / silver / copper, optional note). Stored as ledger kind `manual` and shared over the guild mesh.
- Fixed window height on every page.
- Single shell window: logo band on top (placeholder icon until the real logo is added), menu on the left (Home, Ledger, Settings), and New event / End event / Refresh buttons in the top bar, page content on the right. The ledger is a page in it (`/fundraiser ledger`, the Ledger menu entry, or the admin ledger card): scrollable donation rows (time/kind, name, detail, amount), prominent total, and one summary line per previous campaign (most recently finished first). Same view gate as before (officers + donation target).
- **Set MOTD** entry in the left menu (shown with ledger access and MOTD permission): publishes `Fundraiser <name>: 1200g/5000g (24%). Top contributor: <charname>!` as the guild message of the day after a confirmation (needs guild MOTD edit permission; the top contributor's name becomes public to the guild).
- Required numeric fundraising goal (`goalCopper`, entered as gold in the New event form) on the EVENT wire (field 11, backward compatible).
- Admin status dashboard: event card, progress toward goal (percent + bar), ledger status card, cumulative daily raised chart with goal line.
- End event (-) on the admin event card: archives the campaign, clears active event+ledger, broadcasts `RESET campaign` (`Config.END_EVENT`).

### Fixed
- The donation-target check failed on Forever because `UnitFullName` returns only the first name; the player name now prefers the full "First Last" name from `UnitName`, so the target character is recognised.
- Addon settings from the admin window now opens Settings → AddOns → Fundraiser (uses saved category ID before the panel-name overwrite).

### Changed
- The Target page replaces the separate "Target inbox assist" window and scans bags instead of the mailbox (the mailbox cannot be open at the auctioneer); empty the mailbox the normal way first. The Home Target button and `/fundraiser target` now both go through the donation-target check.
- Auction posting now uses the modern Forever auction house API (`C_AuctionHouse` `PostItem` / `PostCommodity`) and needs the auction house to be open; the old `StartAuction` path is gone. `Config.AH_DURATION` is now the Forever duration index (1 = 2h, 2 = 8h, 3 = 24h) and defaults to 24h (index 3).
- Redesigned the `/fundraiser` admin window as a status dashboard; New event form is behind a button; Open ledger / Settings / Target shortcuts; install presence only in Settings. Row details move to the dedicated ledger window.
- Money amounts use coin icons (`GetCoinTextureString` / MoneyIcons) instead of ascii `g` / `s` / `c`.
- Raised chart: goal line has its own amber Y-axis amount label (mid scale tick hidden when it would overlap).
