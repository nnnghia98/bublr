# Contributing to Bublr

Thanks for helping out. Bublr is a small, focused app: a native macOS overlay that hosts real chat
providers in isolated web sessions. Patches that keep it small and honest are very welcome.

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Getting set up

Requirements: macOS 14 or newer, Xcode 15 or newer, and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone <your fork>
cd bublr
make build          # generates Bublr.xcodeproj, then builds
make run            # launches the app
make run ARGS="--seed-demo"   # launches with sample accounts
```

The Xcode project is generated from `project.yml` and is intentionally **not** committed. If you open the
project in Xcode, re-run `make project` after changing `project.yml` or adding files.

## Before you open a pull request

```bash
make test        # unit + overlay self-test, live provider pages skipped
make test-live   # also loads Telegram, Zalo and Messenger sign-in pages
make render      # renders the real surfaces to /tmp/bublr-ui for a visual check
```

`make test` must be green. `make test-live` is expected to pass when you touch provider detection,
the web session layer, or `Sources/Model/Provider.swift` — it asserts that each provider still shows its
own sign-in surface. It needs network access; CI runs only `make test`.

For UI changes, attach a screenshot. `make render` writes PNGs of the bubble, chat, sign-in and welcome
surfaces without needing screen-recording permission, which makes before/after images easy.

## Architecture in one screen

| Path | Responsibility |
| --- | --- |
| `Sources/Model/Provider.swift` | The provider catalog: URLs, sign-in detection selectors/phrases, the injected `authProbeJS`, sign-in hints |
| `Sources/Model/Workspace.swift` | Observable state — bubbles, accounts, sign-in queue, layout metrics — and its JSON persistence |
| `Sources/Web/WebSession.swift` | One `WKWebView` per account, auth probing, unread from `document.title`, storage policy |
| `Sources/Overlay/OverlayController.swift` | Borderless always-on-top panels: layout, clamping, drag, collapse, position persistence |
| `Sources/UI/` | SwiftUI surfaces: provider bubble, sign-in, chat, welcome, design system |
| `Sources/App/` | App delegate, menu bar, global hotkey, self-test harness, offline UI renderer |

Rules of thumb:

- **The provider page is the source of truth.** Don't parse credentials, don't call provider APIs, don't
  fake a login UI. Add selectors to `ProviderSpec` and let the page do the work.
- **One account = one data store.** `WKWebsiteDataStore(forIdentifier: account.id)` keeps accounts apart.
  Never share a data store between accounts.
- **No new network endpoints.** Bublr talks only to provider pages. No analytics, no telemetry, no
  update pings.

## Adding a provider

1. Add a `ProviderSpec` in `Sources/Model/Provider.swift`:
   - `homeURL` and `hosts`
   - `loginMethods` and `defaultMethod` (`qr`, `credentials`, or both)
   - `signedInSelectors` / `loggedOutSelectors` / `loggedOutPhrases` / `loggedOutHosts` for detection
   - `loginHint` for every method
   - `credentialsSwitchJS` when the provider hides its password form behind a tab
2. Add a tile colour pair (`tintHex`, `tintHex2`) and, if the glyph needs it, a case in
   `ProviderGlyphView` (`Sources/UI/DesignSystem.swift`).
3. Verify it really works: `make build && .build/Build/Products/Debug/Bublr.app/Contents/MacOS/Bublr --probe "<home URL>" 20`
   prints the page title, body text, canvas/image counts and the detected auth state.
4. Add the provider to `liveWebTests` in `Sources/App/SelfTest.swift` with an assertion that matches what
   its sign-in surface actually is (QR canvas/SVG, password field, …).
5. If the provider cannot run in WebKit at all, set `runsInWebKit = false` plus an `unsupportedNote`
   instead of shipping a bubble that would only ever be blank. Say so in the README table.

## Style

- Swift 5 language mode, no external dependencies, no package managers. AppKit + SwiftUI + WebKit +
  Carbon (hotkey) only.
- Prefer small, explicit types over clever abstractions. Comments should explain *why*, not *what*.
- Keep user-visible strings in US English, with the provider's own language left alone (Zalo's page is
  Vietnamese; that's the provider's text, not ours).

## Pull requests

- One concern per PR. Small diffs get reviewed faster.
- Describe the user-visible change, how you tested it, and include a screenshot for UI work.
- Note any provider that changed its page, and update the selectors in the same PR.
