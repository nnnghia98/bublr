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

A Debug build carries the bundle id `com.nnnghia.bublr.dev`, not the release one. `xcodebuild` registers
every bundle it produces with LaunchServices, so an identical id would let a `.build/` Debug copy answer to
the installed app's name and launch in its place. The state file is keyed by path, not bundle id, so both
builds still share one workspace. `make` also stamps the commit into `Info.plist`; the menu bar shows it as
`Bublr 0.1 · <hash>`, which is the quickest way to tell whether the running copy is the one you just built.

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

## Who can merge

`main` is protected by the `main-protection` ruleset, so a pull request can only be merged by a
**contributor** or an **admin**:

| Who | Can merge? |
| --- | --- |
| Admins (repository owner) | Yes |
| Contributors — collaborators with the write role | Yes, once the rules below pass |
| Everyone else — fork authors, readers, triage | No. Open a PR and a maintainer merges it |

Every merge into `main` also needs:

- one approving review, with stale approvals dismissed when new commits land
- an approval of the most recent push, so nobody merges code they pushed themselves
- all review conversations resolved
- the **Build & self-test** and **Conventions** CI checks green
- a squash or merge commit — no rebase merges, no force pushes, no branch deletion

Fork authors never need an invitation: their PRs are welcome, they just cannot merge them. To make
someone a contributor, invite them with write access:

```bash
gh api -X PUT repos/nnnghia98/bublr/collaborators/USERNAME -f permission=push
```

The rule lives in a repository ruleset, not in the workflow files. `Tools/merge-policy.sh` recreates
it, which is the way to change the policy or reapply it after a repo transfer or branch rename.

Agents and automation work under a stricter rule: they open the pull request and stop, and the owner
merges it. [`AGENTS.md`](AGENTS.md) says why, and what counts as an explicit instruction to merge.

## Branches, commits and pull requests

`main` takes squash merges, and the squash commit is built from the pull request **title and body**, not
from the WIP commits on your branch. So the title is the commit message that ends up in the history —
write it as one.

### Commit and PR titles

```
<type>(<scope>): <subject>
```

- imperative subject (`add`, not `added` or `adds`), lower case after the colon, no trailing period,
  at most 72 characters
- optional body, wrapped at 72, explaining **why**
- optional footers: `Closes #12`, `BREAKING CHANGE: <what breaks>`

| Type | Use for | Changelog | SemVer |
| --- | --- | --- | --- |
| `feat` | new capability | Added | minor |
| `fix` | user-visible bug | Fixed | patch |
| `perf` | faster, same behaviour | Changed | patch |
| `refactor` | internal reshape, same behaviour | — | — |
| `test` | self-test and live tests | — | — |
| `docs` | README, CONTRIBUTING | — | — |
| `build` | `project.yml`, `Makefile`, `Support/Info.plist` | — | — |
| `ci` | `.github/workflows` | — | — |
| `chore` | repo housekeeping and releases | — | — |
| `revert` | undoing an earlier commit | Fixed | patch |

Scopes are the directories you already know: `provider`, `workspace`, `session`, `overlay`, `ui`, `app`,
`selftest`, `build`, `ci`, `docs`, `deps`, `repo`. Use a provider name when the change is specific to one.

```
feat(provider): add Zalo QR sign-in
fix(session): keep the unread count when a page title churns
fix(overlay): clamp a dragged bubble back onto the active screen
refactor(workspace): persist layout metrics separately from accounts
```

Mark a breaking change with `!` after the type or scope, and say what breaks in a footer:

```
fix(provider)!: drop WhatsApp, its page no longer loads in WebKit

BREAKING CHANGE: WhatsApp is removed from ProviderSpec.all; accounts persisted
for it are dropped on first launch.
```

### Branch names

`<type>/<slug>` — the same type you will use in the PR title, then a lower-case kebab slug of two to five
words. No dates, no usernames, no `wip`. Add the issue number when there is one.

```
feat/zalo-qr-signin
fix/overlay-clamp-drag
fix/142-overlay-clamp-drag
chore/merge-policy
```

Branches are short-lived: one concern each, and they are deleted when the PR merges.

### Opening the PR

- One concern per PR. Small diffs get reviewed faster.
- Title must pass the **Conventions** check. The branch name is only a warning, since forks often arrive
  as `patch-1`.
- Describe the user-visible change, how you tested it, and include a screenshot for UI work.
- Note any provider that changed its page, and update the selectors in the same PR.
- Keep the body honest: it becomes the squash commit body, so it is the part of this PR that outlives it.
