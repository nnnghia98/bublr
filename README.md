<p align="center">
  <img src="docs/appicon.png" width="128" alt="Bublr app icon">
</p>

<h1 align="center">Bublr</h1>

<p align="center"><em>Every chat, floating above your work.</em></p>

<p align="center">
  A native macOS overlay that keeps one always-on-top bubble per chat provider — Telegram, Messenger,
  Zalo, Discord, Slack, Instagram, Teams, or any web chat — with every account you own stacked inside it.
</p>

![The Bublr welcome window](docs/hero-welcome.png)

Bublr is an AppKit + SwiftUI agent app (no Dock icon). Each bubble is a borderless panel that floats above
other apps and follows you across Spaces. Each account inside a bubble is a **real, isolated browser session**
against the provider's own web client — Telegram's QR, Messenger's password form, Zalo's QR — so the provider
you already trust does the talking.

| Provider bubble | Sign-in |
| --- | --- |
| ![Provider bubble with stacked accounts](docs/screenshot-bubble.png) | ![Sign-in surface with QR](docs/screenshot-signin.png) |

*Screenshots use sample data from `--seed-demo` / `--render-ui`.*

## Why

- **Not a scraper, not a bridge.** No unofficial API, no bot token, no reverse-engineered protocol that
  breaks every other week. It is the provider's own web client in a web view — the same one you would open
  in a browser tab.
- **One session per account.** Work and personal Telegram live in separate data stores, so signing out of
  one never touches the other.
- **Glanceable.** Collapsed to a circle, a bubble shows an unread badge; expanded, it lists your accounts;
  opened, it is the real chat. Drag it anywhere, and it stays there.
- **No credentials, ever.** See [Privacy](#privacy).

## Privacy

Bublr's design rule: **the only thing it may store is what a browser would have stored anyway.**

| Stored | Where | When |
| --- | --- | --- |
| Bubble positions, sizes, collapsed state | `~/Library/Application Support/Bublr/state.json` | Always |
| Account labels, provider, unread counts | same file | Always |
| Provider cookies and local storage | `~/Library/WebKit/com.nnnghia.bublr/` | Only while **Keep me signed in** is on |

- **No passwords, one-time codes or QR tokens.** Bublr never reads the login form, never proxies a
  request and never stores a credential. There is no keychain item and no vault.
- **Keep me signed in** is a per-account switch on the sign-in surface. Off means a private in-memory
  session: the provider's cookies disappear when Bublr quits.
- **Sign out and clear session** in an account's context menu erases the stored cookies immediately.
- **No telemetry, no analytics, no update pings.** The only network traffic is the provider pages you
  added (plus any Custom URL you configure).

Full threat model and reporting process: [SECURITY.md](SECURITY.md).

## Features

- One always-on-top bubble per provider, collapsible to a 64 pt circle, draggable anywhere, position remembered.
- Unlimited stacked accounts per provider, each with its own isolated `WKWebsiteDataStore`.
- The provider's real sign-in: QR where the provider offers QR, password where it does not, with a method
  switch that drives the provider's own page.
- Automatic sign-in detection from the page's own DOM (with an "I've signed in" fallback), unread counts
  from the page title.
- Pop any account out as its own floating bubble, resize chats, dock it back.
- Menu-bar controls and a global ⌥⌘B toggle. No Accessibility permission required.
- Self-test harness (model, layout, real panels, live provider pages) and an offline UI renderer.

## Providers

| Provider | Sign-in | Notes |
| --- | --- | --- |
| **Telegram** | QR, phone number | Uses the K client (`web.telegram.org/a/`), which renders in WebKit |
| **Messenger** | Email/phone + password | Full `messenger.com` client |
| **Zalo** | QR | `chat.zalo.me` / `id.zalo.me` |
| Discord | Password | Standard web client |
| Slack | Password | Standard web client |
| Instagram | Password | Standard web client |
| Teams | Password | Standard web client |
| Custom | Any URL | Give it a name and a URL |
| ~~WhatsApp~~ | — | Not offered: `web.whatsapp.com` needs Chromium and serves a "download WhatsApp" page inside WebKit. Verified, not assumed. |

Adding a provider is a `ProviderSpec` entry plus a live test — see [CONTRIBUTING.md](CONTRIBUTING.md).

## Install

Requirements: **macOS 14 or newer**, **Xcode 15 or newer**, and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/<you>/bublr.git
cd bublr
make build
make install     # copies Bublr.app to /Applications
open /Applications/Bublr.app
```

No Accessibility, screen-recording or other TCC permission is needed. The app has no Dock icon: it lives in
the menu bar.

## Using it

1. The welcome window lists providers. Pick one — its bubble appears at the right edge of the screen with the
   provider's own sign-in page already open.
2. Sign in the way the provider allows (QR or password). Bublr notices by itself and drops you into the chat.
3. **Add account** on a bubble stacks another account for that provider.
4. Drag a bubble by its header (or by the circle when collapsed); collapse with the minus button; pop an
   account out from its context menu.

| Action | How |
| --- | --- |
| Show / hide every bubble | ⌥⌘B or the menu bar item |
| Add a provider bubble | Menu bar → *Add provider bubble* |
| Start a new account | Menu bar → *New account…* |
| Keep me signed in / sign out | Right-click an account in a bubble |
| Reset all bubble positions | Menu bar → *Reset bubble layout* |

## Development

```bash
make build      # xcodegen + xcodebuild (Debug)
make test       # self-test without live provider pages (what CI runs)
make test-live  # also loads Telegram, Zalo and Messenger sign-in pages
make render     # renders the real UI surfaces to /tmp/bublr-ui
make release    # Release build zipped into dist/Bublr-<version>.zip
```

`Bublr.xcodeproj` is generated from `project.yml`; it is not committed. Run `make project` after changing
`project.yml` or adding source files.

### Debug fixtures

| Flag | Effect |
| --- | --- |
| `--seed-demo` | Telegram (3 accounts), Messenger (2), Zalo (1) with unread counts |
| `--demo-signin <provider>` | One bubble with a fresh account, straight into that provider's sign-in |
| `--probe <url> [seconds]` | Loads a URL off-screen and prints its DOM/auth state as JSON |
| `--selftest` | Runs the whole check suite, writes `/tmp/bublr-selftest.json` |
| `--render-ui <dir>` | Renders bubble, chat, sign-in and welcome surfaces to PNGs |

### How it fits together

```
Sources/
  Model/    ProviderCatalog (URLs, detection JS) · Workspace (state + persistence)
  Web/      WebSession (one WKWebView per account) · WebSessionStore
  Overlay/  OverlayController (borderless NSPanel layout, drag, collapse, clamping)
  UI/       SwiftUI surfaces: bubble, sign-in, chat, welcome, design system
  App/      App delegate, menu bar, ⌥⌘B hotkey, self-test, offline renderer
```

The provider page is always the source of truth: detection is DOM selectors and body phrases injected into
the page, never a credential read or an API call.

## Contributing

Pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for the dev loop, how to add a provider,
and what `make test` expects. This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).

## Licence

[MIT](LICENSE). Not affiliated with Telegram, Meta, Zalo, Discord, Slack, Instagram or Microsoft. Provider
names and marks belong to their owners and are used only to identify the service you are signing in to.
