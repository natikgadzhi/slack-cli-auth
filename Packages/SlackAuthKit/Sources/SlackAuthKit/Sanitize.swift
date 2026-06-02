import Foundation

/// Token clean-up that mirrors slack-cli's `internal/auth/sanitize.go` so the
/// values we write are byte-identical to what the CLI would store itself. Kept
/// pure and dependency-free so the ported Go test cases run under plain
/// `swift test`.
public enum Sanitize {
  /// Strip common copy-paste artifacts from a token: surrounding whitespace,
  /// surrounding quotes (single or double), and a leading `Bearer ` prefix
  /// (case-insensitive). Order matches the Go implementation.
  public static func token(_ input: String) -> String {
    var t = input.trimmingCharacters(in: .whitespacesAndNewlines)

    if t.count >= 2 {
      let first = t.first
      let last = t.last
      if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
        t = String(t.dropFirst().dropLast())
      }
    }

    if t.count >= 7, t.prefix(7).lowercased() == "bearer " {
      t = String(t.dropFirst(7))
    }

    return t
  }

  /// Remove a leading `name=` cookie-name prefix (case-insensitive), e.g.
  /// `d=xoxd-…` → `xoxd-…`. Returns the (possibly unchanged) value and whether a
  /// prefix was stripped.
  public static func stripCookieName(_ token: String, name: String) -> (String, Bool) {
    let prefix = name + "="
    guard token.count >= prefix.count,
      token.prefix(prefix.count).lowercased() == prefix.lowercased()
    else {
      return (token, false)
    }
    return (String(token.dropFirst(prefix.count)), true)
  }

  /// Whether `s` contains at least one `%XX` percent-escape — a strong signal it
  /// is already URL-encoded and must not be re-encoded.
  public static func looksURLEncoded(_ s: String) -> Bool {
    let chars = Array(s.utf8)
    guard chars.count >= 3 else { return false }
    for i in 0..<(chars.count - 2) where chars[i] == UInt8(ascii: "%") {
      if isHexDigit(chars[i + 1]) && isHexDigit(chars[i + 2]) {
        return true
      }
    }
    return false
  }

  private static func isHexDigit(_ b: UInt8) -> Bool {
    switch b {
    case UInt8(ascii: "0")...UInt8(ascii: "9"),
      UInt8(ascii: "a")...UInt8(ascii: "f"),
      UInt8(ascii: "A")...UInt8(ascii: "F"):
      return true
    default:
      return false
    }
  }

  /// Canonical URL-encoded form of an `xoxd` cookie value for an HTTP `Cookie`
  /// header. If it already looks URL-encoded it is returned unchanged (never
  /// double-encode); otherwise it is percent-escaped the same way Go's
  /// `url.QueryEscape` does (notably: space → `+`).
  public static func normalizeXoxd(_ s: String) -> String {
    if s.isEmpty { return s }
    if looksURLEncoded(s) { return s }
    return queryEscape(s)
  }

  /// `sanitizeToken` + `d=` cookie-name stripping + `normalizeXoxd`, matching
  /// slack-cli's `SanitizeXoxd`. Use for the `xoxd` cookie path.
  public static func xoxd(_ input: String) -> String {
    let cleaned = token(input)
    let (stripped, _) = stripCookieName(cleaned, name: "d")
    return normalizeXoxd(stripped)
  }

  /// Port of Go's `url.QueryEscape`: percent-encode everything that is not an
  /// RFC 3986 query-safe unreserved byte, and encode space as `+`. Slack's `d`
  /// cookie value uses this exact escaping.
  static func queryEscape(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.utf8.count)
    for byte in s.utf8 {
      if byte == UInt8(ascii: " ") {
        out.append("+")
      } else if isUnreserved(byte) {
        out.append(Character(UnicodeScalar(byte)))
      } else {
        out.append("%")
        out.append(hexUpper(byte >> 4))
        out.append(hexUpper(byte & 0xF))
      }
    }
    return out
  }

  /// Go `shouldEscape(..., encodeQueryComponent)` keeps these unescaped:
  /// A–Z a–z 0–9 and `-_.~`.
  private static func isUnreserved(_ b: UInt8) -> Bool {
    switch b {
    case UInt8(ascii: "A")...UInt8(ascii: "Z"),
      UInt8(ascii: "a")...UInt8(ascii: "z"),
      UInt8(ascii: "0")...UInt8(ascii: "9"):
      return true
    case UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: "~"):
      return true
    default:
      return false
    }
  }

  private static func hexUpper(_ nibble: UInt8) -> Character {
    let table = Array("0123456789ABCDEF")
    return table[Int(nibble)]
  }
}
