# Changelog

All notable changes to Bublr are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Duplicate a provider bubble.** Right-click a bubble's header, or use the menu bar's *Duplicate provider
  bubble*, to open a second head over the same accounts — one collapsed on another Space while the other
  watches unread, both signed in as the same logins. A duplicate shares the account list and unread count
  with its source but keeps its own position, size and collapse state. Only one head can open a given
  account's chat at a time, because an account has exactly one web view.

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
