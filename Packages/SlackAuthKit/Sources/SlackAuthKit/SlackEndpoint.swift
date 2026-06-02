import Foundation

/// Slack URLs and host checks used by the login flow. Centralized so the web
/// client URL and the API base live in one place.
public enum SlackEndpoint {
  /// The Slack web client. Loading this redirects to sign-in when the session
  /// isn't authenticated, and lands on the workspace once it is.
  public static let app = URL(string: "https://app.slack.com")!

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
}
