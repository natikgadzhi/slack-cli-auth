/// Lifecycle of the login flow. V1 saves a single workspace and hides the web
/// view as soon as authentication completes.
public enum AuthenticationState: Sendable, Equatable {
  /// Nothing started yet.
  case new
  /// The web view is visible and the user is signing in (SSO/email/2FA). The
  /// capture poll runs, waiting for the workspace token and `d` cookie.
  case signingIn
  /// Authentication succeeded and the web view is covered. Tokens are being
  /// captured, validated against `auth.test`, and written to the Keychain —
  /// all automatically. `statusMessage` carries the current step.
  case finishing
  /// Tokens validated and written.
  case saved
  /// Something went wrong (validation rejected, write failed, capture timed out).
  /// Carries a human-readable, secret-free reason.
  case failed(String)
}
