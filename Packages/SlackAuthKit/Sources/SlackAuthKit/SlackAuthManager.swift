import Foundation
import Observation
import WebKit
import os

/// Coordinates the interactive Slack login. The user signs in in the web view;
/// the moment authentication completes (a navigation to `app.slack.com/client/…`),
/// the view is covered and the app automatically captures the active workspace's
/// `xoxc` token plus the shared `xoxd` cookie, validates them against `auth.test`,
/// and writes them to the Keychain in the layout slack-cli reads.
///
/// V1 stores a single workspace — the one the user landed in. Multi-workspace
/// selection can come later.
@MainActor @Observable
public final class SlackAuthManager: NSObject {
  private let secretStore: any SlackSecretStoring
  private let log = Logger(subsystem: "io.respawn.SlackAuth", category: "auth")

  public private(set) var state: AuthenticationState = .new

  /// Step shown on the cover while `finishing` ("Finishing sign-in…",
  /// "Verifying with Slack…", "Saving to Keychain…").
  public private(set) var statusMessage = ""

  /// Authenticated team/user names from `auth.test`, shown on the success screen.
  public private(set) var savedTeam: String?
  public private(set) var savedUser: String?

  /// Called when a capture step throws — a seam for the app to report the error
  /// (e.g. to crash telemetry) without the kit depending on a reporter.
  public var onError: (@MainActor (any Error) -> Void)?

  private var webView: WKWebView?
  private var captureTask: Task<Void, Never>?

  /// Workspaces read from the session (kept internal; V1 auto-picks one).
  private var workspaces: [Workspace] = []
  /// The shared `d` cookie value, captured alongside the workspace tokens.
  private var capturedXoxd: String?
  /// Team id of the workspace the user landed in (from the client URL).
  private var activeTeamID: String?
  /// Guards the validate+save step so the poll can't start it twice.
  private var saving = false
  /// Poll attempts spent waiting for tokens after auth, for a timeout.
  private var finishingAttempts = 0

  #if DEBUG
    private var debugRelay: WebConsoleRelay?
  #endif

  /// How often the capture poll re-reads the page while waiting.
  private let pollInterval: Duration = .seconds(1.5)
  /// ~25s of polling after auth before giving up reading the tokens.
  private let maxFinishingAttempts = 16

  public init(secretStore: any SlackSecretStoring) {
    self.secretStore = secretStore
    super.init()
  }

  /// The login web view; the caller embeds this in a window. Uses the default
  /// (persistent) data store on purpose so the `d` cookie lands in the cookie
  /// store and "remember this device" reduces repeat 2FA prompts.
  public var loginWebView: WKWebView {
    if let webView { return webView }
    let configuration = WKWebViewConfiguration()
    #if DEBUG
      // Forward the page's console + JS errors to /tmp/slackauth-webview.log.
      let relay = WebConsoleRelay()
      configuration.userContentController.addUserScript(
        WKUserScript(
          source: WebConsoleRelay.captureJS, injectionTime: .atDocumentStart,
          forMainFrameOnly: false))
      configuration.userContentController.add(relay, name: "slackAuthDebug")
      debugRelay = relay
    #endif
    let webView = WKWebView(frame: .zero, configuration: configuration)
    // Slack rejects WKWebView's default User-Agent ("browser is not supported"),
    // so present as the installed desktop Safari. Must be set before any load.
    webView.customUserAgent = SlackEndpoint.loginUserAgent
    webView.navigationDelegate = self
    // SSO "Authenticate" opens the identity provider via window.open; without a
    // UI delegate WKWebView silently drops it and the button does nothing.
    webView.uiDelegate = self
    // Inspectable in debug only: a distributed release must not expose the
    // signed-in session's tokens to Safari's Web Inspector.
    #if DEBUG
      webView.isInspectable = true
    #endif
    self.webView = webView
    return webView
  }

  /// Start login by loading the Slack sign-in page.
  public func startLogin() {
    let url = SlackEndpoint.signIn
    log.info("startLogin: loading \(url.absoluteString, privacy: .public)")
    transition(to: .signingIn)
    loginWebView.load(URLRequest(url: url))
    startCapturePolling()
  }

  /// Poll the page until the workspace tokens and the `d` cookie are present.
  /// Slack writes `localConfig_v2` asynchronously after the client boots, so a
  /// single read misses it.
  private func startCapturePolling() {
    guard captureTask == nil else { return }
    captureTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        guard let self, self.isCapturing else { return }
        await self.attemptCapture()
        if !self.isCapturing { return }
        try? await Task.sleep(for: self.pollInterval)
      }
    }
  }

  private var isCapturing: Bool {
    state == .signingIn || state == .finishing
  }

  /// One capture attempt: read the workspace tokens and the `d` cookie. When both
  /// are present, hand off to the automatic validate + save. While `finishing`,
  /// count misses toward a timeout so we don't spin forever behind the cover.
  private func attemptCapture() async {
    guard let webView, !saving else { return }
    do {
      let result = try await webView.callAsyncJavaScript(
        SlackCapture.localConfigReadJS, arguments: [:], contentWorld: .page)
      let parsed = SlackCapture.parse(result)
      let dCookie = await currentDCookie()

      guard let parsed, let dCookie else {
        let diag = SlackCapture.diagnostic(result)
        let haveCookie = dCookie != nil
        log.info("capture miss: \(diag, privacy: .public) dCookie=\(haveCookie, privacy: .public)")
        if state == .finishing {
          finishingAttempts += 1
          if finishingAttempts > maxFinishingAttempts {
            transition(to: .failed("Couldn't read your Slack tokens after signing in. Try again."))
          }
        }
        return
      }

      workspaces = parsed
      capturedXoxd = dCookie
      log.info("captured \(parsed.count, privacy: .public) workspace(s) + d cookie")
      await completeSave()
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

  /// Validate the captured tokens for the active workspace and, on success, store
  /// them. Runs automatically once tokens are captured; guarded so it runs once.
  private func completeSave() async {
    guard !saving else { return }
    saving = true
    defer { saving = false }

    if state != .finishing {
      transition(to: .finishing)
    }

    guard let workspace = chooseWorkspace() else {
      transition(to: .failed("Couldn't find a workspace to save."))
      return
    }

    statusMessage = "Verifying with Slack…"
    let xoxc = Sanitize.token(workspace.xoxc)
    let xoxd = Sanitize.xoxd(capturedXoxd ?? "")

    let result = await SlackTokenProbe.run(xoxc: xoxc, xoxd: xoxd)
    guard result.ok else {
      log.error("auth.test rejected: \(result.error ?? "unknown", privacy: .public)")
      transition(to: .failed(Self.failureReason(result.error)))
      return
    }

    statusMessage = "Saving to Keychain…"
    guard secretStore.write(SlackTokens(xoxc: xoxc, xoxd: xoxd)) else {
      log.error("keychain write failed")
      transition(to: .failed("Couldn't write the tokens to your Keychain."))
      return
    }

    savedTeam = result.team ?? (workspace.name.isEmpty ? nil : workspace.name)
    savedUser = result.user
    log.info("saved tokens for the active workspace")
    transition(to: .saved)
  }

  /// The workspace the user landed in (match the client URL's team id), falling
  /// back to the first captured workspace.
  private func chooseWorkspace() -> Workspace? {
    if let id = activeTeamID, let match = workspaces.first(where: { $0.teamID == id }) {
      return match
    }
    return workspaces.first
  }

  /// Retry after a failure. If tokens were already captured (e.g. a transient
  /// Keychain write failure), just re-run validate + save; otherwise restart the
  /// sign-in from scratch.
  public func retry() {
    guard case .failed = state else { return }
    if !workspaces.isEmpty, capturedXoxd != nil {
      Task { await completeSave() }
    } else {
      startLogin()
    }
  }

  /// Remove any stored Slack tokens this app or slack-cli wrote.
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

  /// Enter the covered "finishing" phase once auth lands on the workspace client.
  private func beginFinishing(activeTeamID: String?) {
    guard state == .signingIn else { return }
    self.activeTeamID = activeTeamID
    finishingAttempts = 0
    statusMessage = "Finishing sign-in…"
    transition(to: .finishing)
  }

  private func isClientURL(_ url: URL) -> Bool {
    url.host == "app.slack.com" && url.path.hasPrefix("/client/")
  }

  private func teamID(from url: URL) -> String? {
    let parts = url.path.split(separator: "/").map(String.init)
    guard let index = parts.firstIndex(of: "client"), index + 1 < parts.count else { return nil }
    let candidate = parts[index + 1]
    return candidate.hasPrefix("T") ? candidate : nil
  }

  /// The single place `state` changes. Stops the capture poll once we reach a
  /// terminal state.
  private func transition(to newState: AuthenticationState) {
    state = newState
    switch newState {
    case .saved, .failed, .new:
      cancelCapturePolling()
    case .signingIn, .finishing:
      break
    }
  }

  private func cancelCapturePolling() {
    captureTask?.cancel()
    captureTask = nil
  }
}

extension SlackAuthManager: WKNavigationDelegate {
  /// Cover the web view the instant we navigate into the workspace client — that
  /// nav means auth succeeded, and covering before it paints keeps the user's
  /// Slack content from flashing on screen.
  public func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
  ) async -> WKNavigationActionPolicy {
    if let url = navigationAction.request.url, isClientURL(url) {
      #if DEBUG
        WebDebugLog.write("[nav] entering client \(url.absoluteString)")
      #endif
      beginFinishing(activeTeamID: teamID(from: url))
    }
    return .allow
  }

  public func webView(
    _ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!
  ) {
    log.info("didStart: \(webView.url?.host ?? "<nil>", privacy: .public)")
    #if DEBUG
      WebDebugLog.write("[nav] start \(webView.url?.absoluteString ?? "<nil>")")
    #endif
  }

  public func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    log.error("didFailProvisional: \(error.localizedDescription, privacy: .public)")
    #if DEBUG
      WebDebugLog.write("[nav] failProvisional \(error.localizedDescription)")
    #endif
  }

  public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    log.info("didFinish: \(webView.url?.host ?? "<nil>", privacy: .public)")
    #if DEBUG
      WebDebugLog.write("[nav] finish \(webView.url?.absoluteString ?? "<nil>")")
    #endif
  }

  /// The web content process crashing is the classic "blank page" cause — log it
  /// loudly so we can tell it apart from a network/navigation failure.
  public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    log.error("webContentProcessDidTerminate — WKWebView render process died")
  }
}

extension SlackAuthManager: WKUIDelegate {
  /// Slack's SSO "Authenticate" (and "open in new tab" links) call `window.open`,
  /// which asks the UI delegate for a new web view. We have only one window, so
  /// load the request in the existing view — the session and cookies stay in one
  /// place, and the IdP round-trip redirects back to Slack here.
  public func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    #if DEBUG
      WebDebugLog.write(
        "[popup] window.open -> \(navigationAction.request.url?.absoluteString ?? "<nil>")")
    #endif
    if navigationAction.targetFrame == nil {
      webView.load(navigationAction.request)
    }
    return nil
  }
}
