import Foundation

/// Pure text redaction for telemetry. Applied to the **value-bearing** fields of
/// a crash event (the exception message/value, file paths) — *never* to
/// symbol/type names. The goal: no Slack token, no URL, and no username-bearing
/// path can ever ride out in a crash report. Privacy-first — when in doubt,
/// over-redact, and the backstop drops the whole event.
///
/// Lives in the kit (no Sentry dependency) so the rot-prone regex logic is
/// unit-tested by plain `swift test`; `App/Telemetry.swift` is the only file that
/// imports Sentry and just applies these to the event's fields.
public enum Redaction {
  // Every pattern matches a VALUE shape, not a type/symbol name. The long-run
  // threshold (32) sits above this app's longest identifier so ordinary crashes
  // survive while real tokens (xoxc/xoxd are 50+ chars) are cut. `Regex` isn't
  // Sendable, but these are immutable and matching never mutates them, so reading
  // them from any thread is safe.
  nonisolated(unsafe) private static let usernamePath = try! Regex(#"/Users/[^/\s"']+"#)
  nonisolated(unsafe) private static let url = try! Regex(#"https?://[^\s"'<>]+"#)
  nonisolated(unsafe) private static let slackToken = try! Regex(#"xox[a-zA-Z]-[A-Za-z0-9%._\-]+"#)
  nonisolated(unsafe) private static let bearer = try! Regex(#"(?i)bearer\s+[A-Za-z0-9._\-]+"#)
  nonisolated(unsafe) private static let jwtish = try! Regex(#"eyJ[A-Za-z0-9._\-]{10,}"#)
  nonisolated(unsafe) private static let longTokenRun = try! Regex(#"[A-Za-z0-9_\-]{32,}"#)
  nonisolated(unsafe) private static let sensitiveHost = try! Regex(#"(?i)(slack\.com)"#)

  /// Redact one value-bearing string: drop whole URLs, mask the username in
  /// `/Users/…` paths, and mask anything token/cookie/key-shaped.
  public static func scrubValue(_ string: String) -> String {
    var out = string.replacing(url, with: "<url>")
    out = out.replacing(usernamePath, with: "/Users/<redacted>")
    out = out.replacing(bearer, with: "Bearer <redacted>")
    out = out.replacing(slackToken, with: "<redacted>")
    out = out.replacing(jwtish, with: "<redacted>")
    out = out.replacing(longTokenRun, with: "<redacted>")
    return out
  }

  /// Backstop: does this value still look like it carries a secret, a username
  /// path, or a Slack endpoint? If so the caller drops the whole event (fail
  /// closed). Only ever run on values — never on symbol/type names.
  public static func containsLeak(_ string: String) -> Bool {
    string.contains(usernamePath)
      || string.contains(url)
      || string.contains(slackToken)
      || string.contains(jwtish)
      || string.contains(longTokenRun)
      || string.contains(bearer)
      || string.contains(sensitiveHost)
  }
}
