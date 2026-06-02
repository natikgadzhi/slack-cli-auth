# Security & Privacy

Slack Auth handles credentials that grant access to your Slack workspace, so it
is built to keep them on your machine and to never leak them through telemetry.

## What it stores, and where

Two macOS Keychain generic-password items, under your login account name:

| Item | Service | Contents |
|------|---------|----------|
| Workspace token | `slack-xoxc-token` | your `xoxc-…` token |
| Session cookie  | `slack-xoxd-token` | your URL-encoded `xoxd-…` `d` cookie |

These are exactly the items [`slack-cli`](https://github.com/natikgadzhi/slack-cli)
reads (same service names, same account-name resolution). Items are written with
`kSecAttrAccessibleWhenUnlocked` — readable only while your Mac is unlocked,
never synced to iCloud, never in an unencrypted backup.

Nothing is written to disk outside the Keychain, and the tokens are never sent
anywhere except to Slack's own `auth.test` endpoint to confirm they work before
storing.

## Crash reporting

Crash reporting (Sentry) is **disabled** in local and open-source builds — the
SDK only starts when a DSN is baked into an official notarized release. Even
then, it is locked down:

- **One chokepoint.** Exactly one source file imports the Sentry SDK
  (`App/Telemetry.swift`); CI fails the build if that ever changes.
- **Crashes and explicit errors only.** No analytics, no breadcrumbs, no
  performance tracing, no network capture, no screenshots, no IP or user id.
- **Every event is scrubbed.** URLs, `/Users/<name>` paths, `xoxc`/`xoxd` tokens,
  bearer tokens, and JWT-shaped strings are redacted. If anything secret-shaped
  survives the scrub, the entire event is dropped (fail closed). The redaction
  logic lives in `SlackAuthKit` and is unit-tested.

You can turn crash reporting off entirely; it defaults to on only for official
builds and respects the `telemetry.crashReportsEnabled` user default.

## Verifying a release

Each release publishes a SHA-256 and a SLSA build-provenance attestation. The
DMG is built, signed, and notarized only in CI — no laptop is in the trust path.

```sh
shasum -a 256 SlackAuth*.dmg                  # matches the published hash
gh attestation verify SlackAuth*.dmg --repo natikgadzhi/slack-cli-auth
```

The app's About panel shows the exact commit it was built from.

## Reporting a vulnerability

Open a private security advisory on the GitHub repository, or contact the
maintainer directly. Please don't file public issues for security reports.
