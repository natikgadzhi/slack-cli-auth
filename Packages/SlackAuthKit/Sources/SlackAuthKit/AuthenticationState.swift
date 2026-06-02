/// Lifecycle of the login flow as it progresses from a fresh web view to stored
/// tokens.
public enum AuthenticationState: Sendable, Equatable {
  /// Nothing started yet.
  case new
  /// The web view is loaded and the user is signing in; the capture poll is
  /// running, waiting for an `xoxc` token and the `d` cookie to appear.
  case authenticating
  /// Tokens captured. One or more workspaces are available; the user must pick
  /// which workspace's `xoxc` to store.
  case awaitingSelection
  /// A selected workspace is being checked against `auth.test`.
  case validating
  /// Tokens validated and written to the Keychain.
  case saved
  /// Something went wrong (validation rejected, write failed, network error).
  /// Carries a human-readable, secret-free reason.
  case failed(String)
}
