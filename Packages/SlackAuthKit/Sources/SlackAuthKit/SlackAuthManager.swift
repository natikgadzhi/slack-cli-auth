import Foundation
import Observation
import WebKit
import os

/// Coordinates the interactive Slack login: owns the `WKWebView` the user signs
/// into, snapshots the workspace `xoxc` tokens (from `localStorage`) and the
/// shared `xoxd` `d` cookie (from the cookie store) once they appear, then —
/// after the user picks a workspace — validates the pair against `auth.test` and
/// writes both to the Keychain in the layout slack-cli reads.
///
/// Why a real WebView instead of scripted HTTP: Slack's login is a JS-rendered
/// flow (SSO, email magic links, 2FA), so we let a genuine browser do the dance
/// and read the resulting session out of the page and its cookies.
@MainActor @Observable
public final class SlackAuthManager: NSObject {
  private let secretStore: any SlackSecretStoring
  private let log = Logger(subsystem: "io.respawn.SlackAuth", category: "auth")

  public private(set) var state: AuthenticationState = .new

  /// Workspaces captured from the session, shown in the picker once present.
  public private(set) var workspaces: [Workspace] = []

  /// Authenticated team/user names from `auth.test`, shown on the success screen.
  public private(set) var savedTeam: String?
  public private(set) var savedUser: String?

  /// Called when a capture/validation step throws — a seam for the app to report
  /// the error (e.g. to crash telemetry) without the kit depending on a reporter.
  public var onError: (@MainActor (any Error) -> Void)?

  private var webView: WKWebView?
  private var captureTask: Task<Void, Never>?

  /// The shared `d` cookie value, captured alongside the workspace tokens.
  private var capturedXoxd: String?

  /// How often the capture poll re-reads the page while waiting for login.
  private let pollInterval: Duration = .seconds(1.5)

  public init(secretStore: any SlackSecretStoring) {
    self.secretStore = secretStore
    super.init()
  }

  /// The login web view; the caller embeds this in a window. Uses the default
  /// (persistent) data store on purpose so the `d` cookie lands in the cookie
  /// store and "remember this device" reduces repeat 2FA prompts.
  public var loginWebView: WKWebView {
    if let webView { return webView }
    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    webView.navigationDelegate = self
    // Inspectable in debug only: a distributed release must not expose the
    // signed-in session's tokens to Safari's Web Inspector.
    #if DEBUG
      webView.isInspectable = true
    #endif
    self.webView = webView
    return webView
  }

  /// Start login by loading the Slack web client; it redirects to sign-in when
  /// the user isn't authenticated yet.
  public func startLogin() {
    let url = SlackEndpoint.app
    log.info("startLogin: loading \(url.absoluteString, privacy: .public)")
    transition(to: .authenticating)
    loginWebView.load(URLRequest(url: url))
    startCapturePolling()
  }

  /// Poll the page until both the workspace tokens and the `d` cookie are present.
  /// Slack writes `localConfig_v2` asynchronously after the client boots — often
  /// with no further navigation — so a single read on `didFinish` misses it.
  private func startCapturePolling() {
    guard captureTask == nil else { return }
    captureTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        guard let self, self.state == .authenticating else { return }
        await self.attemptCapture()
        if self.state != .authenticating { return }
        try? await Task.sleep(for: self.pollInterval)
      }
    }
  }

  /// One capture attempt: read the workspace tokens and the `d` cookie. When both
  /// are present, stop polling and move to workspace selection.
  private func attemptCapture() async {
    guard let webView else { return }
    do {
      let result = try await webView.callAsyncJavaScript(
        SlackCapture.localConfigReadJS, arguments: [:], contentWorld: .page)
      let parsed = SlackCapture.parse(result)
      let dCookie = await currentDCookie()

      guard let parsed, let dCookie else {
        let diag = SlackCapture.diagnostic(result)
        let haveCookie = dCookie != nil
        log.info("capture miss: \(diag, privacy: .public) dCookie=\(haveCookie, privacy: .public)")
        return
      }

      workspaces = parsed
      capturedXoxd = dCookie
      log.info("captured \(parsed.count, privacy: .public) workspace(s) + d cookie")
      transition(to: .awaitingSelection)
    } catch {
      log.error("capture error: \(error.localizedDescription, privacy: .public)")
      onError?(error)
    }
  }

  /// The shared Slack `d` cookie (HttpOnly, so unreadable from JavaScript) from
  /// the web view's cookie store, in its on-the-wire URL-encoded form.
  private func currentDCookie() async -> String? {
    let store = loginWebView.configuration.websiteDataStore.httpCookieStore
    let cookies = await store.allCookies()
    for cookie in cookies
    where cookie.name == "d" && SlackEndpoint.isSlackCookieDomain(cookie.domain) {
      if !cookie.value.isEmpty { return cookie.value }
    }
    return nil
  }

  /// Validate the selected workspace's tokens against `auth.test`, then store them
  /// on success. The `xoxc`/`xoxd` are sanitized to the exact form slack-cli
  /// expects before both validating and writing, so the bytes we verify are the
  /// bytes we persist.
  public func select(_ workspace: Workspace) async {
    transition(to: .validating)
    let xoxc = Sanitize.token(workspace.xoxc)
    let xoxd = Sanitize.xoxd(capturedXoxd ?? "")

    let result = await SlackTokenProbe.run(xoxc: xoxc, xoxd: xoxd)
    guard result.ok else {
      let reason = Self.failureReason(result.error)
      log.error("auth.test rejected: \(result.error ?? "unknown", privacy: .public)")
      transition(to: .failed(reason))
      return
    }

    guard secretStore.write(SlackTokens(xoxc: xoxc, xoxd: xoxd)) else {
      log.error("keychain write failed")
      transition(to: .failed("Couldn't write the tokens to your Keychain."))
      return
    }

    savedTeam = result.team ?? (workspace.name.isEmpty ? nil : workspace.name)
    savedUser = result.user
    log.info("saved tokens for the selected workspace")
    transition(to: .saved)
  }

  /// Return to the workspace picker after a failed attempt (tokens are still
  /// captured in memory).
  public func retrySelection() {
    guard !workspaces.isEmpty else {
      transition(to: .authenticating)
      startCapturePolling()
      return
    }
    transition(to: .awaitingSelection)
  }

  /// Remove any stored Slack tokens this app or slack-cli wrote. Independent of
  /// the current capture session.
  public func clearStoredTokens() {
    secretStore.clear()
    log.info("cleared stored tokens")
  }

  private static func failureReason(_ error: String?) -> String {
    switch error {
    case "invalid_auth", "not_authed", "token_revoked":
      return "Slack rejected these tokens (\(error ?? "")). Try signing in again."
    case "network_error":
      return "Couldn't reach Slack to verify the tokens. Check your connection."
    case .some(let other) where !other.isEmpty:
      return "Validation failed: \(other)."
    default:
      return "Validation failed."
    }
  }

  /// The single place `state` changes. Capture polling is meaningful only while
  /// `.authenticating`, so leaving that state always stops it.
  private func transition(to newState: AuthenticationState) {
    state = newState
    if newState != .authenticating {
      cancelCapturePolling()
    }
  }

  private func cancelCapturePolling() {
    captureTask?.cancel()
    captureTask = nil
  }
}

extension SlackAuthManager: WKNavigationDelegate {
  public func webView(
    _ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!
  ) {
    log.info("didStart: \(webView.url?.host ?? "<nil>", privacy: .public)")
  }

  public func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    log.error("didFailProvisional: \(error.localizedDescription, privacy: .public)")
  }

  public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    log.info("didFinish: \(webView.url?.host ?? "<nil>", privacy: .public)")
  }

  /// The web content process crashing is the classic "blank page" cause — log it
  /// loudly so we can tell it apart from a network/navigation failure.
  public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    log.error("webContentProcessDidTerminate — WKWebView render process died")
  }
}
