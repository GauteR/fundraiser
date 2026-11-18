# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Required numeric fundraising goal (`goalCopper`, entered as gold in the New event form) on the EVENT wire (field 11, backward compatible).
- Admin status dashboard: event card, progress toward goal (percent + bar), ledger status card, cumulative daily raised chart with goal line.
- End event (-) on the admin event card: archives the campaign, clears active event+ledger, broadcasts `RESET campaign` (`Config.END_EVENT`).

### Fixed
- Addon settings from the admin window now opens Settings → AddOns → Fundraiser (uses saved category ID before the panel-name overwrite).

### Changed
- Redesigned the `/fundraiser` admin window as a status dashboard; New event form is behind a button; Open ledger / Settings / Target shortcuts; install presence only in Settings. Row details move to the dedicated ledger window.
- Money amounts use coin icons (`GetCoinTextureString` / MoneyIcons) instead of ascii `g` / `s` / `c`.
- Raised chart: goal line has its own amber Y-axis amount label (mid scale tick hidden when it would overlap).
