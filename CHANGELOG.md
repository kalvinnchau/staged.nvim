# Changelog

## [0.1.0] - 2026-09-14

First versioned release.

### Breaking changes

- Require Neovim >= 0.12.5 and codediff.nvim >= 4.0.5, < 5.0.0.
- JSON exports use schema 2 with revision metadata and an explicit modified side.
- Comments are separate per working-tree, index, or commit revision.

### Added

- Cross-file and revision-aware sidebar navigation.
- Opt-in explorer comment counts and configurable indicator priority.
- Auto-sizing comment input and expanded health checks.
- Real-codediff integration tests and `just check`.

### Fixed

- Sidebar placement and stable export paths with current codediff APIs.
- Comment positions, snippets, and undo anchors survive buffer unload/reload.
- Reliable file/revision switching, independent sidebar scrolling, and input cleanup.
- Comment controls stay inactive in original-only/deleted-file views.

## Unversioned history

Earlier commits are grouped below without assigning retrospective versions.

### 2026-09-14 — keymap restoration ([commit](https://github.com/kalvinnchau/staged.nvim/commit/eaf115f))

- Restored script-local buffer mappings correctly when switching files.

### 2026-07-29–31 — workflow tools and hardening ([commits](https://github.com/kalvinnchau/staged.nvim/compare/6b14073...fe80631))

- Added overlapping-comment selection, session undo/redo, JSON schema 1 exports,
  health checks, and public comment events.
- Hardened session cleanup, buffer-replacement anchors, mapping ownership, and config validation;
  completed plain-text exports and `vim.ui.input` support.
- Preserved Escape-to-Normal behavior and customized mappings; fixed export command completion.

### 2026-03-19 — buffer bounds ([commit](https://github.com/kalvinnchau/staged.nvim/commit/6b14073))

- Clamped comment positions and inline indicators to current buffer bounds.

### 2026-01-14–21 — initial implementation ([commits](https://github.com/kalvinnchau/staged.nvim/compare/ec3c5b1...3691012))

- Introduced tab-scoped line/range comments, extmark tracking, sidebar and inline indicators,
  comment input, navigation, Markdown exports, and tests.
- Corrected the codediff.nvim dependency URL.
