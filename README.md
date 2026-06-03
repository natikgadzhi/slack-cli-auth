# Slack CLI Helper

A small, signed + notarized macOS app that signs you in to Slack in a web view,
captures your `xoxc` workspace token and `xoxd` session cookie, and stores them
in your Keychain in exactly the layout [`slack-cli`](https://github.com/natikgadzhi/slack-cli)
reads. Everything stays on your machine.

## Why

`slack-cli` talks to Slack's internal web API, which needs a browser session's
`xoxc` token and `xoxd` (`d`) cookie. Grabbing those by hand from devtools is
fiddly and error-prone — and SSO/2FA makes it worse. This app does it for you:
sign in normally (SSO, email magic link, 2FA — whatever your workspace uses) and
it validates and stores the tokens automatically.

## Install

### Homebrew

```sh
brew install --cask natikgadzhi/taps/slack-cli-auth
```

### Direct download

Download the latest `SlackAuth-<version>.dmg` from
[Releases](https://github.com/natikgadzhi/slack-cli-auth/releases), drag the app
to Applications, and open it. Builds are signed with a Developer ID and notarized
by Apple; verify provenance with:

```sh
gh attestation verify SlackAuth*.dmg --repo natikgadzhi/slack-cli-auth
```

### Build locally

```sh
make contrib      # install xcodegen + git hooks, generate the project
make authenticate # build (Debug) and launch the login window
```

## How it works

1. The app opens Slack's sign-in page in a `WKWebView`. You sign in as usual
   (SSO, email magic link, 2FA — whatever your workspace uses).
2. The moment you land in your workspace, it reads your `xoxc` workspace token
   from the page's `localStorage` (`localConfig_v2`) and the shared `xoxd` `d`
   cookie from the web view's cookie store (the cookie is HttpOnly, so it can't
   be read from JavaScript).
3. It validates the pair against Slack's `auth.test` API, then writes two
   Keychain items — `slack-xoxc-token` and `slack-xoxd-token`, under your login
   account name — that `slack-cli` picks up automatically.

The first time `slack-cli` reads a token this app wrote, macOS shows a one-time
Keychain "Always Allow" prompt (a normal cross-app access control).

## Development

- `make test` — run the `SlackAuthKit` unit tests (`swift test`).
- `make lint-format` — check formatting (`swift-format`).
- `make build` — build the unsigned app.
- `make dmg` — build a signed + notarized DMG (needs a Developer ID + notary
  credentials; see `scripts/build-dmg.sh`).

The reusable logic (token capture, sanitization, Keychain layout, validation)
lives in `Packages/SlackAuthKit`, which has no UI or telemetry dependency and is
fully unit-tested. The `App/` target is the SwiftUI shell plus the single Sentry
chokepoint (`Telemetry.swift`).

## Privacy & security

See [SECURITY.md](SECURITY.md). Crash reporting is off in local and open-source
builds, scrubs every event, and never sends tokens, URLs, or file paths.
