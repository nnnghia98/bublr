# Security policy

## What Bublr stores

Bublr's whole job is to host chat providers' own web clients, so the only thing it can store is
what those pages would store in a browser:

| Stored | Where | Why |
| --- | --- | --- |
| Bubble positions, sizes, collapsed state | `~/Library/Application Support/Bublr/state.json` | Restore your layout |
| Account labels, provider, unread counts | same file | Show the bubbles |
| Provider session cookies / local storage | `~/Library/WebKit/com.nnnghia.bublr/…` | Only when **Keep me signed in** is on |

**Bublr never stores a password, a one-time code, a QR token or a recovery code.** Sign-in happens
inside the provider's own page; Bublr never reads the form fields, never proxies a request and never
inspects what you type. There is no keychain item, no credential vault and no sync.

Turning **Keep me signed in** off gives the account a private, in-memory session: the provider's cookies
are gone the moment Bublr quits, and nothing is written to disk. **Sign out and clear session** erases
the stored cookies for that account immediately.

## Network access

The app only loads the provider pages listed in `Sources/Model/Provider.swift` (plus any URL you add as a
*Custom* provider). There is no telemetry, no crash reporting, no update check, no analytics endpoint and
no server operated by this project.

## Threat model — what this does not protect against

Be honest with yourself about the boundary:

- **A local session is a login.** With *Keep me signed in* on, anyone who can use your macOS account can
  open Bublr and read those chats, exactly as they could open your browser profile. Lock your Mac.
- **Not a sandbox.** Bublr builds without the App Sandbox and with an ad-hoc signature so it is easy to
  build from source. If you need a hardened build, sign it with your own Developer ID and enable the
  hardened runtime.
- **The provider is in charge.** Each bubble is the provider's real web client. Their code runs with the
  access a browser would give it, including camera/microphone prompts for calls.
- **Screen capture and malware** are outside the model, as they are for any app.

## Reporting a vulnerability

Please **do not** open a public issue. Use GitHub's private reporting:

1. Go to the repository's **Security** tab → **Report a vulnerability**.
2. Include the version (`Bublr → About` shows it), the provider involved, and reproduction steps.

You can expect an acknowledgement within a few days. There is no bug bounty; credit is given in the
release notes if you want it.
