import Foundation

/// Result of a Slack `auth.test` call.
public struct AuthTestResult: Sendable, Equatable {
  public let ok: Bool
  public let team: String?
  public let user: String?
  public let teamID: String?
  public let userID: String?
  /// Slack's machine-readable error (e.g. `invalid_auth`) when `ok` is false.
  public let error: String?

  public init(
    ok: Bool, team: String? = nil, user: String? = nil, teamID: String? = nil,
    userID: String? = nil, error: String? = nil
  ) {
    self.ok = ok
    self.team = team
    self.user = user
    self.teamID = teamID
    self.userID = userID
    self.error = error
  }
}

/// Validates a captured `xoxc` + `xoxd` pair against Slack's `auth.test` before we
/// store it. The request shape mirrors what a browser session sends: the `xoxc`
/// as a bearer token and the `xoxd` as the `d` cookie.
///
/// Request building and response parsing are pure (and unit-tested); `run`
/// performs the network call.
public enum SlackTokenProbe {
  /// Build the `auth.test` request for a token pair. `xoxd` must already be in the
  /// URL-encoded wire form (`Sanitize.xoxd`).
  public static func makeRequest(
    xoxc: String, xoxd: String,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> URLRequest {
    var request = URLRequest(url: SlackEndpoint.authTest(environment: environment))
    request.httpMethod = "POST"
    request.setValue("Bearer \(xoxc)", forHTTPHeaderField: "Authorization")
    request.setValue("d=\(xoxd)", forHTTPHeaderField: "Cookie")
    request.setValue(
      "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data()
    return request
  }

  /// Parse an `auth.test` JSON body. A body that doesn't decode, or lacks `ok`,
  /// is treated as a failure.
  public static func parse(_ data: Data) -> AuthTestResult {
    guard let object = try? JSONSerialization.jsonObject(with: data),
      let dict = object as? [String: Any]
    else {
      return AuthTestResult(ok: false, error: "unparseable_response")
    }
    let ok = (dict["ok"] as? Bool) ?? false
    return AuthTestResult(
      ok: ok,
      team: dict["team"] as? String,
      user: dict["user"] as? String,
      teamID: dict["team_id"] as? String,
      userID: dict["user_id"] as? String,
      error: dict["error"] as? String)
  }

  /// Perform the `auth.test` call. Network/transport failures surface as
  /// `ok: false` with a generic, secret-free error string.
  public static func run(
    xoxc: String, xoxd: String, session: URLSession = .shared,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) async -> AuthTestResult {
    let request = makeRequest(xoxc: xoxc, xoxd: xoxd, environment: environment)
    do {
      let (data, _) = try await session.data(for: request)
      return parse(data)
    } catch {
      return AuthTestResult(ok: false, error: "network_error")
    }
  }
}
