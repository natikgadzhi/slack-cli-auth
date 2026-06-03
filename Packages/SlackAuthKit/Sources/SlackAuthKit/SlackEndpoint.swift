import Foundation

/// Slack URLs and host checks used by the login flow. Centralized so the web
/// client URL and the API base live in one place.
public enum SlackEndpoint {
  /// The Slack sign-in page — the entry point we load first so the user lands
  /// straight on the login form. After authenticating, Slack redirects to the
  /// workspace client at `app.slack.com`, where the `xoxc` tokens live in
  /// `localStorage` (the `#/signin` fragment routes the SPA directly to sign-in).
  public static let signIn = URL(string: "https://slack.com/signin#/signin")!

  /// Default Slack Web API base. Override with `$SLACK_BASE_URL` (trailing `/`
  /// trimmed) — same knob slack-cli exposes for stubbing in tests.
  public static func apiBase(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> URL {
    if let v = environment["SLACK_BASE_URL"], !v.isEmpty {
      let trimmed = v.hasSuffix("/") ? String(v.dropLast()) : v
      if let url = URL(string: trimmed) { return url }
    }
    return URL(string: "https://slack.com/api")!
  }

  /// `auth.test` endpoint for the given API base.
  public static func authTest(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> URL {
    apiBase(environment: environment).appendingPathComponent("auth.test")
  }

  /// Whether a cookie domain belongs to Slack (so we pick up the `d` cookie set
  /// on `.slack.com`). Matches `slack.com` and any subdomain.
  public static func isSlackCookieDomain(_ domain: String) -> Bool {
    let d = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
    return d == "slack.com" || d.hasSuffix(".slack.com")
  }

  /// A desktop Safari User-Agent for the login web view.
  ///
  /// Slack sniffs the User-Agent and rejects WKWebView's default — which is
  /// `…AppleWebKit/605.1.15 (KHTML, like Gecko)` with no trailing
  /// `Version/<n> Safari/605.1.15` token — with "your browser is not supported".
  /// WKWebView *is* Safari's engine and already reports
  /// `navigator.vendor = "Apple Computer, Inc."`, so presenting as Safari is
  /// consistent (unlike Firefox, which had to spoof the vendor) and accepted.
  ///
  /// The Safari version is read from the installed Safari so the string stays
  /// current as the OS updates; a recent version is the fallback if Safari can't
  /// be found. The `Intel Mac OS X 10_15_7` platform token is intentional —
  /// Safari reports it verbatim on Apple Silicon too.
  public static var loginUserAgent: String {
    let version = installedSafariShortVersion ?? "26.0"
    return
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
      + "(KHTML, like Gecko) Version/\(version) Safari/605.1.15"
  }

  private static var installedSafariShortVersion: String? {
    let url = URL(fileURLWithPath: "/Applications/Safari.app/Contents/Info.plist")
    guard let dict = NSDictionary(contentsOf: url),
      let version = dict["CFBundleShortVersionString"] as? String, !version.isEmpty
    else {
      return nil
    }
    return version
  }
}
