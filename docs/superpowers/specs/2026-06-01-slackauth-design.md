# SlackAuth — design

**Date:** 2026-06-01
**Status:** Approved (design decisions confirmed with user)

## Goal

A distributable, signed + notarized macOS app that lets a user sign in to Slack
in a web view, captures the `xoxc` workspace token and the `xoxd` `d` cookie, and
writes them to the macOS Keychain in **exactly** the layout
[`slack-cli`](https://github.com/natikgadzhi/slack-cli) reads. Plus Sentry crash
reporting (privacy-scrubbed, off unless a DSN is injected at release) and CI for
lint/test/build, version tag, and signed-DMG release.

Built closely on the [`copilot-auth`](https://github.com/natikgadzhi/copilot-auth)
template, which solves the same problem for a different service.

## Confirmed design decisions

1. **Multi-workspace → picker.** A Slack login can span several workspaces, each
   with its own `xoxc`; the `d` cookie is shared. `slack-cli` stores exactly one
   `xoxc` + one `xoxd`. After capture, the app lists the workspaces by name and
   the user picks which one to save.
2. **Validate before save.** The selected `xoxc` + `xoxd` are checked against
   Slack's `auth.test` API. Tokens are written only on `ok: true`; the authed
   team + user are shown as confirmation.
3. **GUI-only.** No `check`/`reset` subcommands (copilot-auth has them). Plain
   SwiftUI `App` lifecycle; the app quits when its window closes. A lightweight
   "Clear stored tokens" button in the window covers the `reset` need.

## The Slack-specific token mechanics

- **`xoxc` (workspace token):** lives in the page's `localStorage` under
  `localConfig_v2` — a JSON blob with a `teams` map; each team carries
  `{ id, name, domain, url, token: "xoxc-…" }`. Read with injected JS
  (`callAsyncJavaScript`, `.page` content world). One per workspace.
- **`xoxd` (the `d` cookie):** **HttpOnly**, so `document.cookie` cannot see it.
  Read from `WKHTTPCookieStore.getAllCookies` (`name == "d"`, host ends in
  `slack.com`). Its value is already URL-encoded `xoxd-…`, which is exactly the
  wire form `slack-cli` expects. Shared across all workspaces in the session.
- **Capture loop:** poll every ~1.5s (Slack writes `localConfig_v2`
  asynchronously after the client boots) until there is ≥1 workspace token AND
  the `d` cookie. Then stop polling and show the picker.

## Keychain compatibility (must be byte-exact for slack-cli)

`slack-cli` resolves tokens via `cli-kit` → `zalando/go-keyring`, which on macOS
creates **generic-password** items holding the **plain UTF-8 token string** (no
JSON wrapper — unlike copilot-auth's bundle). Two separate items:

| Token | `kSecAttrService` | `kSecAttrAccount` | Value |
|-------|-------------------|-------------------|-------|
| xoxc  | `slack-xoxc-token` | resolved account | sanitized `xoxc-…` |
| xoxd  | `slack-xoxd-token` | resolved account | sanitized + URL-encoded `xoxd-…` |

**Account resolution** ports `internal/config/config.go::KeychainAccount` exactly
(first non-empty wins): `$SLACK_KEYCHAIN_ACCOUNT` → `NSUserName()` → `$USER` →
`"slack-cli"`. Service names honor the same `$SLACK_XOXC_SERVICE` /
`$SLACK_XOXD_SERVICE` overrides.

**Sanitization** ports `internal/auth/sanitize.go`:
- `xoxc` → `sanitizeToken`: trim whitespace, strip surrounding quotes, strip
  `Bearer ` prefix (case-insensitive).
- `xoxd` → `sanitizeXoxd`: `sanitizeToken`, then strip a leading `d=` cookie-name
  prefix, then `normalizeXoxd` (URL-encode only if it doesn't already look
  percent-encoded). The Go unit-test cases are ported to Swift so behavior
  matches byte-for-byte.

Items are written with `kSecAttrAccessibleWhenUnlocked` (matching go-keyring) and
`write` deletes any existing item by `service`+`account` first to avoid
duplicates / stale accessibility.

**Known behavior (documented, not fixed):** the first time `slack-cli` reads an
item *this app* created, macOS shows a one-time Keychain "Always Allow" prompt
(cross-binary ACL). Standard and unavoidable without weakening the ACL.

## Module structure (mirrors copilot-auth)

```
App/                       SwiftUI app + Sentry. Telemetry.swift = ONLY Sentry import.
  SlackAuthApp.swift       @main SwiftUI App; NSApplicationDelegateAdaptor → quit on close.
  LoginWindow.swift        WKWebView + workspace picker + status/confirmation + clear button.
  Telemetry.swift          Sentry init + scrub (single chokepoint; CI greps for one import).
  About.swift              Standard About panel with version + commit SHA.
  SlackStyle.swift         A few shared color/metric constants.
  Info.plist               Custom keys SENTRY_DSN / GitCommitSHA (injected at release).
  Assets.xcassets          AppIcon slot (placeholder; no third-party art).
Packages/SlackAuthKit/     Pure logic. Imports WebKit/Security but NOT Sentry. Unit-tested.
  AuthenticationState.swift  new / authenticating / awaitingSelection / validating / saved / failed.
  Workspace.swift          { teamID, name, domain, url, xoxc } (Sendable, Equatable).
  SlackEndpoint.swift      app.slack.com, slack.com/api/auth.test, trusted-host check, slack.com host test.
  SlackCapture.swift       JS string + parse(localConfig_v2) → [Workspace]; cookie extraction helper; diagnostic.
  Sanitize.swift           Port of sanitize.go (+ ported tests).
  KeychainNames.swift      Service names + account resolution (port of config.go).
  SlackSecretStore.swift   Protocol + Keychain impl (two items) + InMemory test double.
  SlackTokenProbe.swift    auth.test request builder + response parse + classify.
  Redaction.swift          Scrub xoxc-/xoxd-/slack URLs/JWT/long-runs/user paths.
  SlackAuthManager.swift   @MainActor @Observable: webview, poll, capture, validate, save, clear.
```

## Flow / states

```
new → authenticating → awaitingSelection(workspaces) → validating → saved
                                       ↘ failed(reason) → (retry → awaitingSelection)
```

1. App launches → `SlackAuthManager.startLogin()` loads `https://app.slack.com`.
2. User authenticates (SSO/email/whatever) in the web view.
3. Capture poll reads workspaces from `localConfig_v2` and the `d` cookie from
   the cookie store. When both present → `awaitingSelection`, polling stops.
4. Window shows the workspace picker.
5. User picks → `validating` → `auth.test`. On `ok: true` → sanitize + write both
   Keychain items → `saved`, show `team` + `user`. On failure → `failed(reason)`,
   user can pick again / retry.
6. "Clear stored tokens" button deletes both items (`SecItemDelete`).

## Sentry (ported wholesale from copilot-auth)

Single `App/Telemetry.swift` importing Sentry; CI greps that exactly one App file
imports it. Empty DSN locally/CI → SDK never starts (no-op). DSN injected only at
release via `Info.plist` substitution. `beforeSend` runs every event through
`Redaction`; **fail-closed** drop if any value still looks like a token, URL, or
user path. No breadcrumbs, no PII, no network/perf/auto-session tracking. Redaction
patterns tuned for Slack: `xoxc-…`, `xoxd-…`, `slack.com` URLs, JWT-ish, long
token runs (≥32), `/Users/<name>` paths.

## CI/CD (ports copilot-auth's three workflows + scripts)

- **`ci.yml`** (push/PR, `macos-15`): xcodegen, `swift-format lint --strict`,
  single-Sentry-import check, `swift test`, unsigned `xcodebuild`.
- **`tag.yml`** (manual dispatch): bump `MARKETING_VERSION` in `project.yml`,
  commit `Release vX.Y.Z`, tag, then `gh workflow run release.yml --ref vX.Y.Z`.
- **`release.yml`** (tag-triggered): `scripts/build-dmg.sh` → archive, sign
  Developer ID, hardened runtime, notarize, staple, DMG → SHA-256 + SLSA
  attestation → GitHub Release.
- Supporting: `project.yml` (XcodeGen), `Makefile`, `.swift-format`,
  `.gitignore`, `.githooks/pre-commit`, `scripts/build-dmg.sh`.

Renamed throughout: target/scheme `SlackAuth`, bundle id `io.respawn.SlackAuth`,
product name "Slack Auth", repo `natikgadzhi/slack-cli-auth`, team `9YKSA5B4FP`.
Reuses the distribution secrets already configured in the repo
(`APPLE_DEVELOPER_ID_P12_*`, `APPLE_NOTARY_*`, `SENTRY_DSN`).

## Testing

Unit tests with no WebView dependency:
- `Sanitize` — ported Go cases (quotes, whitespace, Bearer, `d=` prefix, raw vs
  URL-encoded xoxd).
- `SlackCapture.parse` — sample `localConfig_v2` (multi-team, missing token,
  malformed JSON) → expected `[Workspace]`.
- `KeychainNames` — account resolution order honoring env overrides.
- `SlackTokenProbe` — response parse (`ok:true`/`ok:false`+`error`) and
  request shape (URL, method, Authorization + Cookie headers).
- `Redaction` — xoxc/xoxd/URL/path scrubbing + `containsLeak` backstop.
- `SlackSecretStore` — round-trip via `InMemorySlackSecretStore`.

## Out of scope (YAGNI)

- Headless `check`/`reset` subcommands.
- Manual token-paste fallback UI.
- Storing more than one workspace at a time (slack-cli holds one).
- Auto-refresh / token rotation (tokens are long-lived; re-run to refresh).
