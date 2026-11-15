# Changelog

All notable changes to Bublr are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] — 2026-11-15

Re-release that exercises the in-app updater against a real GitHub release. The application code is identical to
1.0.0: no behaviour changed, and nothing here needs to be read as a fix or a feature.

### Changed

- Version 1.0.1 (build 2). An installed 1.0.0 build now finds a newer release, so the menu bar offers
  *Update to Bublr 1.0.1…* and *Install and Relaunch* performs a real download, checksum check and bundle swap.

## [1.0.0] — 2026-11-06

First release with the shape the app is meant to keep.

### Added

- **The chat opens beside its head, not instead of it.** Each bubble now owns two panels: the head, which keeps its
  badge, name and drag handle, and a chat panel anchored to it. Placement is automatic — it picks a side with room
  and never covers the head — or fixed to a side you choose; the choice is stored per bubble.
- **Live resizing from any edge.** Chat, sign-in page and account list all resize while the pointer moves, with
  floors that keep provider pages usable. Sizes are remembered per bubble and per account.
- **A duplicate head can be retired.** Hiding is per provider; *Remove this bubble* acts on one head and leaves the
  accounts alone — as does removing every head of a provider, which used to delete its accounts.
- **Per-provider visibility.** A provider with no accounts stays off the overlay until you ask for it, with a
  right-click override either way.
- **Zoom inside a chat**, 50–200% in one-decimal steps, remembered per account and applied before the first load.
- **Collapse and expand animate**, off under Reduce Motion, and only size changes animate.
- **Click away to collapse everything**, on by default and switchable from the menu bar.
- The menu bar shows the running build: `Bublr 1.0.0 · <commit>`.
- **In-app updates.** *Check for Updates…* in the menu bar, plus a quiet once-a-day check that only renames the
  menu item. The download is verified against the release's published SHA-256 and the version inside the archive
  before anything is replaced; the swap happens after the app quits and it reopens itself.
- `make release` builds a signed-if-you-have-certificates DMG and a zip (the zip is what the updater installs),
  with checksums and a Homebrew cask.
- **Duplicate a provider bubble.** Right-click a bubble's header, or use *Add another bubble* in Settings, to
  open a second head over the same accounts — one collapsed on another Space while the other watches unread,
  both signed in as the same logins. A duplicate shares the account list and unread count with its source but
  keeps its own position, size and collapse state. Only one head can open a given account's chat at a time,
  because an account has exactly one web view.
- **Settings is the one place to add providers and accounts.** Pick a provider in the sidebar, add its
  bubble, and add accounts from there. Each provider's accounts are listed with their status, unread count
  and a ⋯ menu for rename, *Keep me signed in*, sign out and remove.

### Changed

- A Debug build carries its own bundle id (`com.nnnghia.bublr.dev`) and its own state file, so it can never
  answer to the installed app's name or fight it over one workspace.
- The onboarding copy names the providers the app can actually host, derived from the catalogue.
- **Sign-in happens in Settings, not in a bubble.** The provider's own page opens in a sheet over the
  Settings window, so authentication never takes over a bubble that is showing conversations. A row that
  needs a sign-in, and a chat whose session ended, both open that sheet.
- **A bubble now carries chats only.** The header's add-account button, the account context menu's rename,
  session and remove items, the provider hide/show item and the menu bar's *Add provider bubble*, *Duplicate
  provider bubble* and *New account…* items moved to Settings. What remains on a bubble is opening a chat,
  popping one out, collapse, drag, resize, the chat's side, and duplicating or retiring that head.
- Bubbles are no longer pre-seeded on first launch: the Settings window is where a provider first gets one.

### Fixed

- A state file written by an older build no longer risks being silently replaced by an empty workspace when a new
  key is missing.
- A duplicated head inherits its source's side and list height.
- **A bubble no longer jumps when you close its list or chat near the bottom of the screen.** A head
  parked against the bottom edge is slid up to make room for the list it opens; it now remembers the top
  it was parked at, so collapsing returns it exactly there instead of a bubble-height higher.

## [0.1] — 2026-11-04

First public release.

### Added

- Always-on-top bubbles, one per chat provider — Telegram, Messenger, Zalo, Discord, Slack, Instagram,
  Teams and any custom URL — as borderless panels that follow you across Spaces and never take focus.
- Unlimited accounts stacked inside a bubble, each a real provider web session in its own
  `WKWebsiteDataStore`, so work and personal logins never share cookies.
- The provider's own sign-in: QR where the provider offers it, password where it does not, with a method
  switch that drives the provider's page. Sign-in is detected from the page itself, with a manual fallback.
- Collapse a bubble to a 64 pt circle with an unread badge, drag it anywhere, resize a chat, pop an account
  out as its own floating bubble, or reset the whole layout.
- **Keep me signed in** per account, with *Sign out and clear session*. With it off, the provider's cookies
  live in memory only and are gone when Bublr quits.
- Menu-bar controls, a global ⌥⌘B toggle, and no Accessibility, screen-recording or other TCC permission.
- Self-test harness (`--selftest`) covering model, layout, real panels and live provider pages, plus an
  offline UI renderer (`--render-ui`) and debug fixtures (`--seed-demo`, `--demo-signin`, `--probe`).
- `BUBLR_SKIP_LIVE=1` to run the self-test without touching provider pages.

### Privacy

- No passwords, one-time codes or QR tokens are stored: no keychain item, no credential vault, no telemetry,
  no analytics, no update pings. The only network traffic is the provider pages you added.
