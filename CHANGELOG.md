# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- The Target panel opens by itself beside the auction house (docked to its right side) on the donation-target character and goes back to the main window when the auction house closes. `Config.TARGET_AUTO_DOCK` turns it off.
- The docked Target panel goes beside the right-most visible auction window, so it does not cover Auctionator's price history window when that is docked to the auction house. `Config.TARGET_DOCK_ANCHORS` lists the frame names it considers; add another addon's auction window there by name.
- Selected stack card on the Target page: item icon (with tooltip) and name in its quality colour, the stack size with the recommendation in its group colour, and a label / value grid for the vendor and AH values and the price source, with the recommended value highlighted.
- Skipping a stack on the Target page moves the selection on to the next stack in the list (and scrolls it into view); at the end of the list the last stack stays selected.
- Target page list: columns for item, quantity, value and a note (skipped, below minimum, needs a price), item icons, the item tooltip on hover, group headers in their own colours, a stronger selected-row marker, and a coloured status line (green for success, red for failure).
- Selling a donated item to a vendor from the Target page (Vendor or Sell all) adds the vendor price to its ledger row, like an auction sale does. Vendor sales of items nobody donated are not recorded.
- Target page bulk actions: **Post all** and **Sell all** (each confirmed with count and estimated total, stopping on the first failure) act on the Auction and Vendor lists. Posting is one stack per click ("Post next (N left)"); selling to a vendor runs in one go. A per-stack **Skip** toggle (this session only) and the minimum stack value (`Config.MIN_STACK_VALUE_COPPER`) leave stacks out of the bulk actions; they are marked in the list and can still be acted on one by one. Stacks that need a price are never part of a bulk action.
- Target page in the main window (menu entry **Target**, `/fundraiser target`, and the Home button), shown only on the donation-target character. It scans the bags, lists stacks under Auction, Vendor and Needs price headers, and posts or vendors the selected stack with the result shown inline. Rescans on bag changes. Same cards and margins as Home and Ledger.
- Target assist groundwork: a bag scan (`Adapters/BagAssist.lua`) that lists stacks with TSM / Auctionator and vendor prices and the sale advice, a view model that groups stacks into Auction, Vendor and Needs price lists (`Domain/TargetView.lua`), and a bulk action queue (`Domain/ActionQueue.lua`). New constant `Config.MIN_STACK_VALUE_COPPER` (default 100 copper): stacks below it will be left out of bulk actions. No UI change yet.
- Selling donated items adds the proceeds to the ledger row they came from (same row, updated for the guild), oldest row first, with the detail showing how many were sold (`Linen Cloth x20 (5 sold)`). Auction sales count what is left after the auction house cut (`Config.AH_CUT_FRACTION`); an auction sale of an item nobody donated still gets its own row.
- Item donations in the ledger: mail from a player with item attachments now adds a row listing the items (for example `Linen Cloth x20`), worth nothing until they are sold. Items the auction house returns by mail are not counted as donations. Mail already in the inbox from before this change may show once more as a new row.
- Groundwork for item donations in the ledger (`Domain/ItemLots.lua`): donated items wait as lots on their ledger row, and a sale's proceeds are allocated to the oldest open row for that item. No behaviour change yet.
- Manual donations: officers and the donation-target character can add a donation by hand (Add donation menu page: donor, amount in gold / silver / copper, optional note). Stored as ledger kind `manual` and shared over the guild mesh.
- Fixed window height on every page.
- Single shell window: logo band on top (placeholder icon until the real logo is added), menu on the left (Home, Ledger, Settings), and New event / End event / Refresh buttons in the top bar, page content on the right. The ledger is a page in it (`/fundraiser ledger`, the Ledger menu entry, or the admin ledger card): scrollable donation rows (time/kind, name, detail, amount), prominent total, and one summary line per previous campaign (most recently finished first). Same view gate as before (officers + donation target).
- **Set MOTD** entry in the left menu (shown with ledger access and MOTD permission): publishes `Fundraiser <name>: 1200g/5000g (24%). Top contributor: <charname>!` as the guild message of the day after a confirmation (needs guild MOTD edit permission; the top contributor's name becomes public to the guild).
- Required numeric fundraising goal (`goalCopper`, entered as gold in the New event form) on the EVENT wire (field 11, backward compatible).
- Admin status dashboard: event card, progress toward goal (percent + bar), ledger status card, cumulative daily raised chart with goal line.
- End event (-) on the admin event card: archives the campaign, clears active event+ledger, broadcasts `RESET campaign` (`Config.END_EVENT`).

### Fixed
- Posting a stack to the auction house no longer reports "Could not start auction" when the client did create the auction; only an error in the post call counts as a failure, and its text is shown.
- The donation-target check failed on Forever because `UnitName` and `UnitFullName` return the first name and the last name as two separate values, so the player never matched a "First Last" event target. The player name now comes from `GetUnitName("player", true)` (full name), joining the two values when it is missing.
- Addon settings from the admin window now opens Settings → AddOns → Fundraiser (uses saved category ID before the panel-name overwrite).

### Changed
- Removed the "Open target page" button from the Home page: the Target menu entry (and `/fundraiser target`, and the panel beside the auction house) is the way in.
- The Target page replaces the separate "Target inbox assist" window and scans bags instead of the mailbox (the mailbox cannot be open at the auctioneer); empty the mailbox the normal way first. The Home Target button and `/fundraiser target` now both go through the donation-target check.
- Auction posting now uses the modern Forever auction house API (`C_AuctionHouse` `PostItem` / `PostCommodity`) and needs the auction house to be open; the old `StartAuction` path is gone. `Config.AH_DURATION` is now the Forever duration index (1 = 2h, 2 = 8h, 3 = 24h) and defaults to 24h (index 3).
- Redesigned the `/fundraiser` admin window as a status dashboard; New event form is behind a button; Open ledger / Settings / Target shortcuts; install presence only in Settings. Row details move to the dedicated ledger window.
- Money amounts use coin icons (`GetCoinTextureString` / MoneyIcons) instead of ascii `g` / `s` / `c`.
- Raised chart: goal line has its own amber Y-axis amount label (mid scale tick hidden when it would overlap).
